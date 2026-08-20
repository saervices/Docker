// SPDX-License-Identifier: MIT
// Copyright (c) 2025 it.særvices
//
// Negætive ænd lifecycle tests for the Græfænæ entrypoint.
package main

import (
	"bytes"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func preserveEnvironment(t *testing.T) {
	t.Helper()
	original := append([]string(nil), os.Environ()...)
	t.Cleanup(func() {
		os.Clearenv()
		for _, item := range original {
			name, value, found := strings.Cut(item, "=")
			if found {
				_ = os.Setenv(name, value)
			}
		}
	})
}

func writeTestSecret(t *testing.T, directory, name string, value []byte) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(directory, name), value, 0o600); err != nil {
		t.Fatalf("write secret %s: %v", name, err)
	}
}

func configureOIDCTestEnvironment(t *testing.T) {
	t.Helper()
	configureDatabaseTestEnvironment(t)
	for name, value := range map[string]string{
		"APP_DOMAIN":                "grafana.example.test",
		"AUTHENTIK_DOMAIN":          "authentik.example.test",
		"GRAFANA_OIDC_SLUG":         "grafana",
		"GRAFANA_OIDC_NAME":         "authentik",
		"GRAFANA_OIDC_ACCESS_GROUP": "grafana-users",
		"GRAFANA_OIDC_ADMIN_GROUP":  "grafana-admins",
		"GRAFANA_OIDC_EDITOR_GROUP": "grafana-editors",
		"GRAFANA_OIDC_VIEWER_GROUP": "grafana-viewers",
		"GRAFANA_OIDC_SCOPES":       "openid profile email offline_access",
		"GRAFANA_OAUTH_AUTO_LOGIN":  "false",
		"GRAFANA_SMTP_ENABLED":      "false",
	} {
		t.Setenv(name, value)
	}
}

func configureDatabaseTestEnvironment(t *testing.T) {
	t.Helper()
	for name, value := range map[string]string{
		"GF_DATABASE_TYPE":     "postgres",
		"GF_DATABASE_HOST":     "grafana-postgresql:5432",
		"GF_DATABASE_NAME":     "grafana",
		"GF_DATABASE_USER":     "grafana",
		"GF_DATABASE_SSL_MODE": "disable",
	} {
		t.Setenv(name, value)
	}
}

func prepareApplicationSecrets(t *testing.T) string {
	t.Helper()
	directory := t.TempDir()
	for name, value := range map[string]string{
		"POSTGRES_PASSWORD":          "postgres-password",
		"GRAFANA_SECRET_KEY":         "grafana-secret-key",
		"GRAFANA_OIDC_CLIENT_ID":     "grafana-client-id",
		"GRAFANA_OIDC_CLIENT_SECRET": "grafana-client-secret",
	} {
		writeTestSecret(t, directory, name, []byte(value))
	}
	return directory
}

func TestReadSecretValidation(t *testing.T) {
	directory := t.TempDir()
	writeTestSecret(t, directory, "VALID", []byte("välid-secret"))
	value, err := readSecret(directory, "VALID")
	if err != nil {
		t.Fatalf("valid secret rejected: %v", err)
	}
	if string(value) != "välid-secret" {
		t.Fatal("valid secret changed")
	}
	wipe(value)
	writeTestSecret(t, directory, "VALID_INNER_SPACE", []byte("valid inner space"))
	if value, err := readSecret(directory, "VALID_INNER_SPACE"); err != nil {
		t.Fatalf("valid inner whitespace rejected: %v", err)
	} else {
		wipe(value)
	}

	invalidValues := map[string][]byte{
		"EMPTY":          {},
		"PLACEHOLDER":    []byte("CHANGE_ME"),
		"LINE_FEED":      []byte("secret\n"),
		"CARRIAGE":       []byte("secret\r"),
		"CONTROL":        []byte{'s', 0, 'x'},
		"UTF8":           {0xff, 'x'},
		"LEADING_SPACE":  []byte(" secret"),
		"TRAILING_SPACE": []byte("secret "),
		"UNICODE_SPACE":  []byte("\u00a0secret"),
		"LINE_SEPARATOR": []byte("secret\u2028value"),
		"PARA_SEPARATOR": []byte("secret\u2029value"),
		"ONLY_SPACES":    []byte("   "),
		"OVERSIZED":      []byte(strings.Repeat("x", int(maximumSecretBytes+1))),
	}
	for name, invalid := range invalidValues {
		t.Run(name, func(t *testing.T) {
			writeTestSecret(t, directory, name, invalid)
			if value, err := readSecret(directory, name); err == nil {
				wipe(value)
				t.Fatal("invalid secret accepted")
			}
		})
	}
}

func TestReadSecretRejectsUnsafeFileTypes(t *testing.T) {
	directory := t.TempDir()
	target := filepath.Join(directory, "TARGET")
	writeTestSecret(t, directory, "TARGET", []byte("secret"))
	if err := os.Symlink(target, filepath.Join(directory, "SYMLINK")); err != nil {
		t.Fatal(err)
	}
	if value, err := readSecret(directory, "SYMLINK"); err == nil {
		wipe(value)
		t.Fatal("symlink secret accepted")
	}
	if err := os.Link(target, filepath.Join(directory, "HARDLINK")); err != nil {
		t.Fatal(err)
	}
	if value, err := readSecret(directory, "TARGET"); err == nil {
		wipe(value)
		t.Fatal("multiply linked secret accepted")
	}
	if err := syscall.Mkfifo(filepath.Join(directory, "FIFO"), 0o600); err != nil {
		t.Fatal(err)
	}
	if value, err := readSecret(directory, "FIFO"); err == nil {
		wipe(value)
		t.Fatal("FIFO secret accepted")
	}
}

func TestLoadAndStageSecrets(t *testing.T) {
	secretDirectory := t.TempDir()
	runtimeDirectory := filepath.Join(t.TempDir(), "runtime-secrets")
	writeTestSecret(t, secretDirectory, "SECRET", []byte("exact-value"))
	values, err := loadAndStageSecrets(secretDirectory, runtimeDirectory, []string{"SECRET"})
	if err != nil {
		t.Fatalf("stage valid secret: %v", err)
	}
	defer wipe(values["SECRET"])
	staged, err := os.ReadFile(filepath.Join(runtimeDirectory, "SECRET"))
	if err != nil {
		t.Fatal(err)
	}
	if string(staged) != "exact-value" {
		t.Fatal("staged secret changed")
	}
	info, err := os.Stat(filepath.Join(runtimeDirectory, "SECRET"))
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o400 {
		t.Fatalf("unexpected staged mode: %o", info.Mode().Perm())
	}
}

func TestConfigureApplicationSecurityContract(t *testing.T) {
	preserveEnvironment(t)
	configureOIDCTestEnvironment(t)
	secretDirectory := prepareApplicationSecrets(t)
	runtimeDirectory := filepath.Join(t.TempDir(), "runtime")
	values, err := configureApplication(secretDirectory, runtimeDirectory)
	if err != nil {
		t.Fatalf("valid application configuration rejected: %v", err)
	}
	for _, value := range values {
		wipe(value)
	}
	checks := map[string]string{
		"GF_DATABASE_PASSWORD":                             "$__file{" + runtimeDirectory + "/POSTGRES_PASSWORD}",
		"GF_DATABASE_SKIP_MIGRATIONS":                      "false",
		"GF_DATABASE_MIGRATION_LOCKING":                    "true",
		"GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC":          "0",
		"GF_SECURITY_SECRET_KEY":                           "$__file{" + runtimeDirectory + "/GRAFANA_SECRET_KEY}",
		"GF_SECURITY_DISABLE_INITIAL_ADMIN_CREATION":       "true",
		"GF_SECURITY_COOKIE_SECURE":                        "true",
		"GF_SECURITY_DISABLE_GRAVATAR":                     "true",
		"GF_USERS_ALLOW_SIGN_UP":                           "false",
		"GF_USERS_ALLOW_ORG_CREATE":                        "false",
		"GF_AUTH_OAUTH_ALLOW_INSECURE_EMAIL_LOOKUP":        "false",
		"GF_AUTH_GENERIC_OAUTH_VALIDATE_ID_TOKEN":          "true",
		"GF_AUTH_GENERIC_OAUTH_USE_REFRESH_TOKEN":          "true",
		"GF_AUTH_GENERIC_OAUTH_SCOPES":                     "openid profile email offline_access",
		"GF_AUTH_GENERIC_OAUTH_LOGIN_ATTRIBUTE_PATH":       "sub",
		"GF_AUTH_GENERIC_OAUTH_ALLOWED_GROUPS":             "grafana-users",
		"GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_STRICT":      "true",
		"GF_AUTH_GENERIC_OAUTH_JWK_SET_URL":                "https://authentik.example.test/application/o/grafana/jwks/",
		"GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES":            "false",
		"GF_AUTH_BASIC_ENABLED":                            "false",
		"GF_AUTH_ANONYMOUS_ENABLED":                        "false",
		"GF_AUTH_GENERIC_OAUTH_ALLOW_ASSIGN_GRAFANA_ADMIN": "true",
		"GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH":        "contains(groups[*], 'grafana-admins') && !contains(groups[*], 'grafana-editors') && !contains(groups[*], 'grafana-viewers') && 'GrafanaAdmin' || !contains(groups[*], 'grafana-admins') && contains(groups[*], 'grafana-editors') && !contains(groups[*], 'grafana-viewers') && 'Editor' || !contains(groups[*], 'grafana-admins') && !contains(groups[*], 'grafana-editors') && contains(groups[*], 'grafana-viewers') && 'Viewer'",
		"GF_AUTH_LOGIN_MAXIMUM_LIFETIME_DURATION":          "8h",
		"GF_AUTH_LOGIN_MAXIMUM_INACTIVE_LIFETIME_DURATION": "1h",
		"GF_AUTH_TOKEN_ROTATION_INTERVAL_MINUTES":          "5",
		"GF_SERVICE_ACCOUNTS_TOKEN_EXPIRATION_DAY_LIMIT":   "90",
		"GF_AUTH_API_KEY_MAX_SECONDS_TO_LIVE":              "7776000",
		"GF_SSO_SETTINGS_CONFIGURABLE_PROVIDERS":           ssoConfigurationLockProvider,
		"GF_METRICS_ENABLED":                               "false",
		"GF_PUBLIC_DASHBOARDS_ENABLED":                     "false",
		"GF_SNAPSHOTS_ENABLED":                             "false",
		"GF_SNAPSHOTS_EXTERNAL_ENABLED":                    "false",
		"GF_PATHS_PLUGINS":                                 defaultReviewedPluginDirectory,
		"GF_PLUGINS_PLUGIN_ADMIN_ENABLED":                  "false",
		"GF_PLUGINS_PREINSTALL_DISABLED":                   "true",
		"GF_PLUGINS_PREINSTALL_AUTO_UPDATE":                "false",
	}
	for name, expected := range checks {
		if actual := os.Getenv(name); actual != expected {
			t.Fatalf("%s: got %q, want %q", name, actual, expected)
		}
	}
	if _, exists := os.LookupEnv("GF_SECURITY_ADMIN_PASSWORD"); exists {
		t.Fatal("final application received bootstrap password configuration")
	}
}

func TestConfigureApplicationRejectsForbiddenMounts(t *testing.T) {
	for _, secretName := range []string{"GRAFANA_ADMIN_PASSWORD", "MAILER_SMTP_PASSWORD"} {
		t.Run(secretName, func(t *testing.T) {
			preserveEnvironment(t)
			configureOIDCTestEnvironment(t)
			secretDirectory := prepareApplicationSecrets(t)
			writeTestSecret(t, secretDirectory, secretName, []byte("must-not-be-mounted"))
			_, err := configureApplication(secretDirectory, filepath.Join(t.TempDir(), "runtime"))
			if err == nil {
				t.Fatal("forbidden secret mount accepted")
			}
		})
	}
}

func TestConfigureApplicationRejectsProtectedEnvironment(t *testing.T) {
	for _, name := range []string{
		"GF_DATABASE_PASSWORD",
		"GF_DATABASE_PASSWORD__FILE",
		"GF_SECURITY_SECRET_KEY",
		"GF_SECURITY_ADMIN_PASSWORD",
		"GF_AUTH_GENERIC_OAUTH_CLIENT_ID",
		"GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET__FILE",
		"GF_SMTP_PASSWORD",
	} {
		t.Run(name, func(t *testing.T) {
			preserveEnvironment(t)
			configureOIDCTestEnvironment(t)
			t.Setenv(name, "forbidden")
			secretDirectory := prepareApplicationSecrets(t)
			if _, err := configureApplication(secretDirectory, filepath.Join(t.TempDir(), "runtime")); err == nil {
				t.Fatal("protected environment override accepted")
			}
		})
	}
}

func TestConfigureOIDCRejectsOverlappingGroups(t *testing.T) {
	preserveEnvironment(t)
	configureOIDCTestEnvironment(t)
	t.Setenv("GRAFANA_OIDC_VIEWER_GROUP", "grafana-users")
	if err := configureOIDC(t.TempDir()); err == nil {
		t.Fatal("overlapping access and role groups accepted")
	}
}

func TestConfigureOIDCRequiresRefreshScopeAndUniqueScopes(t *testing.T) {
	for _, scopes := range []string{
		"openid profile email",
		"openid profile email offline_access email",
	} {
		t.Run(scopes, func(t *testing.T) {
			preserveEnvironment(t)
			configureOIDCTestEnvironment(t)
			t.Setenv("GRAFANA_OIDC_SCOPES", scopes)
			if err := configureOIDC(t.TempDir()); err == nil {
				t.Fatal("unsafe OIDC scope set accepted")
			}
		})
	}
}

func TestSessionAndTokenPolicyBounds(t *testing.T) {
	invalid := []struct {
		name  string
		key   string
		value string
	}{
		{name: "maximum-too-long", key: "GRAFANA_LOGIN_MAXIMUM_LIFETIME_DURATION", value: "25h"},
		{name: "inactive-exceeds-maximum", key: "GRAFANA_LOGIN_MAXIMUM_INACTIVE_LIFETIME_DURATION", value: "9h"},
		{name: "rotation-exceeds-inactive", key: "GRAFANA_LOGIN_MAXIMUM_INACTIVE_LIFETIME_DURATION", value: "4m"},
		{name: "rotation-zero", key: "GRAFANA_TOKEN_ROTATION_INTERVAL_MINUTES", value: "0"},
		{name: "token-expiry-zero", key: "GRAFANA_SERVICE_ACCOUNT_TOKEN_EXPIRATION_DAYS", value: "0"},
		{name: "token-expiry-too-long", key: "GRAFANA_SERVICE_ACCOUNT_TOKEN_EXPIRATION_DAYS", value: "366"},
	}
	for _, testCase := range invalid {
		t.Run(testCase.name, func(t *testing.T) {
			preserveEnvironment(t)
			t.Setenv(testCase.key, testCase.value)
			if err := configureSessionAndTokenPolicy(); err == nil {
				t.Fatal("unsafe session or token policy accepted")
			}
		})
	}
}

func TestPluginPolicyRejectsMutableSources(t *testing.T) {
	for _, testCase := range []struct {
		name  string
		value string
	}{
		{name: "GF_PATHS_PLUGINS", value: "/var/lib/grafana/other"},
		{name: "GF_INSTALL_PLUGINS", value: "unsigned-plugin"},
		{name: "GF_INSTALL_IMAGE_RENDERER_PLUGIN", value: "true"},
		{name: "GF_PLUGINS_PREINSTALL", value: "plugin@latest"},
		{name: "GF_PLUGINS_PREINSTALL_SYNC", value: "true"},
	} {
		t.Run(testCase.name, func(t *testing.T) {
			preserveEnvironment(t)
			t.Setenv(testCase.name, testCase.value)
			if err := configurePluginPolicy(); err == nil {
				t.Fatal("mutable plugin source accepted")
			}
		})
	}
}

func TestDirectSecretEnvironmentIsRejected(t *testing.T) {
	for _, name := range []string{
		"POSTGRES_PASSWORD",
		"POSTGRES_PASSWORD_FILE",
		"GF_DATABASE_PASSWORD_FILE",
		"GRAFANA_SECRET_KEY__FILE",
		"GRAFANA_ADMIN_PASSWORD",
		"GRAFANA_OIDC_CLIENT_ID_FILE",
		"GRAFANA_OIDC_CLIENT_SECRET",
		"MAILER_SMTP_PASSWORD__FILE",
		"GRAFANA_API_TOKEN",
		"PGPASSWORD",
	} {
		t.Run(name, func(t *testing.T) {
			preserveEnvironment(t)
			t.Setenv(name, "forbidden-secret-input")
			if err := rejectDirectSecretEnvironment(); err == nil {
				t.Fatalf("direct secret environment %s accepted", name)
			}
		})
	}
}

func TestDatabaseEnvironmentPolicyRejectsCompetingConfiguration(t *testing.T) {
	for _, testCase := range []struct {
		name  string
		value string
	}{
		{name: "GF_DATABASE_URL", value: "postgres://other.example.test/grafana"},
		{name: "GF_DATABASE_SKIP_MIGRATIONS", value: "true"},
		{name: "GF_DATABASE_MIGRATION_LOCKING", value: "false"},
		{name: "GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC", value: "1"},
		{name: "GF_DATABASE_QUERY_RETRIES", value: "9"},
	} {
		t.Run(testCase.name, func(t *testing.T) {
			preserveEnvironment(t)
			configureDatabaseTestEnvironment(t)
			t.Setenv(testCase.name, testCase.value)
			if _, err := validateDatabaseEnvironmentPolicy(); err == nil {
				t.Fatal("competing Grafana database configuration accepted")
			}
		})
	}
}

func TestDatabaseEnvironmentPolicyReappliesMigrationSafety(t *testing.T) {
	preserveEnvironment(t)
	configureDatabaseTestEnvironment(t)
	values, err := databaseRuntimeEnvironment("/run/private")
	if err != nil {
		t.Fatalf("reviewed database configuration rejected: %v", err)
	}
	for name, expected := range map[string]string{
		"GF_DATABASE_PASSWORD":                    "$__file{/run/private/POSTGRES_PASSWORD}",
		"GF_DATABASE_SKIP_MIGRATIONS":             "false",
		"GF_DATABASE_MIGRATION_LOCKING":           "true",
		"GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC": "0",
	} {
		if values[name] != expected {
			t.Fatalf("%s: got %q, want %q", name, values[name], expected)
		}
	}
}

func TestBootstrapAppliesPluginPolicyBeforeSecrets(t *testing.T) {
	preserveEnvironment(t)
	configureDatabaseTestEnvironment(t)
	t.Setenv("GRAFANA_BOOTSTRAP_STATE_DIR", t.TempDir())
	t.Setenv("GF_INSTALL_PLUGINS", "unreviewed-plugin")
	err := runBootstrap()
	if err == nil || !strings.Contains(err.Error(), "GF_INSTALL_PLUGINS") {
		t.Fatalf("bootstrap did not reject mutable plugin input before secrets: %v", err)
	}
}

func TestConfigureOIDCRejectsUnsafeSlug(t *testing.T) {
	for _, slug := range []string{"../grafana", "grafana/path", "Grafana", "-grafana", "grafana-", "CHANGE_ME"} {
		t.Run(slug, func(t *testing.T) {
			preserveEnvironment(t)
			configureOIDCTestEnvironment(t)
			t.Setenv("GRAFANA_OIDC_SLUG", slug)
			if err := configureOIDC(t.TempDir()); err == nil {
				t.Fatal("unsafe OIDC slug accepted")
			}
		})
	}
}

func TestAdminResetArgumentsRequireStdin(t *testing.T) {
	for _, arguments := range [][]string{
		{"admin", "reset-admin-password", "--user-id", "7", "--password-from-stdin"},
		{"admin", "reset-admin-password", "--password-from-stdin", "--user-id", "7"},
	} {
		if err := validateAdminResetArguments(arguments); err != nil {
			t.Fatalf("safe CLI arguments rejected: %v", err)
		}
	}
	for _, arguments := range [][]string{
		{"admin", "reset-admin-password", "literal-password"},
		{"admin", "reset-admin-password"},
		{"admin", "reset-admin-password", "--password-from-stdin"},
		{"admin", "reset-admin-password", "--user-id", "0", "--password-from-stdin"},
		{"admin", "reset-admin-password", "--user-id", "1", "--user-id", "2", "--password-from-stdin"},
		{"admin", "reset-admin-password", "--user-id=1", "--password-from-stdin"},
		{"admin", "reset-admin-password", "--password-from-stdin", "--password-from-stdin"},
		{"plugins", "ls", "--password-from-stdin"},
	} {
		if err := validateAdminResetArguments(arguments); err == nil {
			t.Fatalf("unsafe CLI arguments accepted: %q", arguments)
		}
	}
}

func TestConfigureGrafanaCLIUsesPostgresSecretFiles(t *testing.T) {
	preserveEnvironment(t)
	secretDirectory := t.TempDir()
	writeTestSecret(t, secretDirectory, "POSTGRES_PASSWORD", []byte("postgres-password"))
	writeTestSecret(t, secretDirectory, "GRAFANA_SECRET_KEY", []byte("grafana-secret-key"))
	for name, value := range map[string]string{
		"GF_DATABASE_TYPE":     "postgres",
		"GF_DATABASE_HOST":     "grafana-postgresql:5432",
		"GF_DATABASE_NAME":     "grafana",
		"GF_DATABASE_USER":     "grafana",
		"GF_DATABASE_SSL_MODE": "disable",
	} {
		t.Setenv(name, value)
	}
	if err := configureGrafanaCLI(secretDirectory); err != nil {
		t.Fatalf("safe PostgreSQL CLI configuration rejected: %v", err)
	}
	if os.Getenv("GF_DATABASE_PASSWORD") != "$__file{"+secretDirectory+"/POSTGRES_PASSWORD}" {
		t.Fatal("CLI database password does not use the validated file")
	}
	if os.Getenv("GF_SECURITY_SECRET_KEY") != "$__file{"+secretDirectory+"/GRAFANA_SECRET_KEY}" {
		t.Fatal("CLI secret key does not use the validated file")
	}
}

func TestConfigureGrafanaCLIRejectsSQLiteAndAdminMount(t *testing.T) {
	for _, testCase := range []struct {
		name       string
		database   string
		mountAdmin bool
	}{
		{name: "sqlite", database: "sqlite3"},
		{name: "admin-mount", database: "postgres", mountAdmin: true},
	} {
		t.Run(testCase.name, func(t *testing.T) {
			preserveEnvironment(t)
			secretDirectory := t.TempDir()
			writeTestSecret(t, secretDirectory, "POSTGRES_PASSWORD", []byte("postgres-password"))
			writeTestSecret(t, secretDirectory, "GRAFANA_SECRET_KEY", []byte("grafana-secret-key"))
			if testCase.mountAdmin {
				writeTestSecret(t, secretDirectory, "GRAFANA_ADMIN_PASSWORD", []byte("admin-password"))
			}
			for name, value := range map[string]string{
				"GF_DATABASE_TYPE":     testCase.database,
				"GF_DATABASE_HOST":     "grafana-postgresql:5432",
				"GF_DATABASE_NAME":     "grafana",
				"GF_DATABASE_USER":     "grafana",
				"GF_DATABASE_SSL_MODE": "disable",
			} {
				t.Setenv(name, value)
			}
			if err := configureGrafanaCLI(secretDirectory); err == nil {
				t.Fatal("unsafe CLI database configuration accepted")
			}
		})
	}
}

func TestConfigureSMTPEnabled(t *testing.T) {
	preserveEnvironment(t)
	secretDirectory := t.TempDir()
	runtimeDirectory := filepath.Join(t.TempDir(), "runtime")
	writeTestSecret(t, secretDirectory, "POSTGRES_PASSWORD", []byte("postgres-password"))
	writeTestSecret(t, secretDirectory, "GRAFANA_SECRET_KEY", []byte("grafana-secret-key"))
	writeTestSecret(t, secretDirectory, "GRAFANA_OIDC_CLIENT_ID", []byte("client-id"))
	writeTestSecret(t, secretDirectory, "GRAFANA_OIDC_CLIENT_SECRET", []byte("client-secret"))
	writeTestSecret(t, secretDirectory, "MAILER_SMTP_PASSWORD", []byte("smtp-password"))
	configureOIDCTestEnvironment(t)
	for name, value := range map[string]string{
		"GRAFANA_SMTP_ENABLED":   "true",
		"GRAFANA_SMTP_HOST":      "mail.example.test",
		"GRAFANA_SMTP_PORT":      "587",
		"GRAFANA_SMTP_USER":      "grafana@example.test",
		"GRAFANA_SMTP_FROM":      "grafana@example.test",
		"GRAFANA_SMTP_FROM_NAME": "Grafana",
		"GRAFANA_SMTP_TLS_MODE":  "starttls",
	} {
		t.Setenv(name, value)
	}
	values, err := configureApplication(secretDirectory, runtimeDirectory)
	if err != nil {
		t.Fatalf("valid SMTP configuration rejected: %v", err)
	}
	for _, value := range values {
		wipe(value)
	}
	if os.Getenv("GF_SMTP_HOST") != "mail.example.test:587" || os.Getenv("GF_SMTP_STARTTLS_POLICY") != "MandatoryStartTLS" {
		t.Fatal("SMTP settings were not rendered safely")
	}
	if os.Getenv("GF_SMTP_PASSWORD") != "$__file{"+runtimeDirectory+"/MAILER_SMTP_PASSWORD}" {
		t.Fatal("SMTP password did not use the staged file reference")
	}
}

func TestConfigureSMTPRejectsDowngradeAndPlaceholders(t *testing.T) {
	invalidCases := []struct {
		name  string
		key   string
		value string
	}{
		{name: "implicit-wrong-port", key: "GRAFANA_SMTP_PORT", value: "587"},
		{name: "starttls-wrong-port", key: "GRAFANA_SMTP_TLS_MODE", value: "starttls"},
		{name: "placeholder-host", key: "GRAFANA_SMTP_HOST", value: "CHANGE_ME"},
		{name: "placeholder-user", key: "GRAFANA_SMTP_USER", value: "CHANGE_ME"},
		{name: "invalid-boolean", key: "GRAFANA_SMTP_ENABLED", value: "yes"},
	}
	for _, testCase := range invalidCases {
		t.Run(testCase.name, func(t *testing.T) {
			preserveEnvironment(t)
			secretDirectory := t.TempDir()
			writeTestSecret(t, secretDirectory, "MAILER_SMTP_PASSWORD", []byte("smtp-password"))
			for name, value := range map[string]string{
				"GRAFANA_SMTP_ENABLED":   "true",
				"GRAFANA_SMTP_HOST":      "mail.example.test",
				"GRAFANA_SMTP_PORT":      "465",
				"GRAFANA_SMTP_USER":      "grafana@example.test",
				"GRAFANA_SMTP_FROM":      "grafana@example.test",
				"GRAFANA_SMTP_FROM_NAME": "Grafana",
				"GRAFANA_SMTP_TLS_MODE":  "implicit",
			} {
				t.Setenv(name, value)
			}
			t.Setenv(testCase.key, testCase.value)
			if _, err := configureSMTP(secretDirectory, filepath.Join(t.TempDir(), "runtime")); err == nil {
				t.Fatal("invalid SMTP configuration accepted")
			}
		})
	}
}

type ssoPolicyFixture struct {
	directory        string
	psqlBinary       string
	secretDirectory  string
	runtimeDirectory string
}

func configureSSOPolicyTestEnvironment(t *testing.T) {
	t.Helper()
	os.Clearenv()
	for name, value := range map[string]string{
		"GF_DATABASE_TYPE":                              "postgres",
		"GF_DATABASE_HOST":                              "grafana-postgresql:5432",
		"GF_DATABASE_NAME":                              "grafana",
		"GF_DATABASE_USER":                              "grafana",
		"GF_DATABASE_SSL_MODE":                          "disable",
		"GRAFANA_SSO_POLICY_TIMEOUT_SECONDS":            "30",
		"GRAFANA_SERVICE_ACCOUNT_TOKEN_EXPIRATION_DAYS": "90",
	} {
		t.Setenv(name, value)
	}
}

func newSSOPolicyFixture(t *testing.T, response, diagnostic string, exitCode int) ssoPolicyFixture {
	t.Helper()
	directory := t.TempDir()
	secretDirectory := filepath.Join(directory, "secrets")
	if err := os.Mkdir(secretDirectory, 0o700); err != nil {
		t.Fatal(err)
	}
	writeTestSecret(t, secretDirectory, "POSTGRES_PASSWORD", []byte(`pa:ss\word`))
	if err := os.WriteFile(filepath.Join(directory, "response"), []byte(response), 0o600); err != nil {
		t.Fatal(err)
	}
	if diagnostic != "" {
		if err := os.WriteFile(filepath.Join(directory, "diagnostic"), []byte(diagnostic), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(directory, "exit-code"), []byte(strconv.Itoa(exitCode)+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	script := `#!/bin/sh
fixture_directory=${0%/*}
: >"$fixture_directory/arguments"
for argument do
  printf '%s\n' "$argument" >>"$fixture_directory/arguments"
done
{
  printf 'LANG=%s\n' "$LANG"
  printf 'LC_ALL=%s\n' "$LC_ALL"
  printf 'PGAPPNAME=%s\n' "$PGAPPNAME"
  printf 'PGCONNECT_TIMEOUT=%s\n' "$PGCONNECT_TIMEOUT"
  printf 'PGOPTIONS=%s\n' "$PGOPTIONS"
  printf 'PGPASSFILE=%s\n' "$PGPASSFILE"
  printf 'PGSSLMODE=%s\n' "$PGSSLMODE"
  printf 'POSTGRES_PASSWORD_SET=%s\n' "${POSTGRES_PASSWORD+x}"
  printf 'GRAFANA_OIDC_CLIENT_SECRET_SET=%s\n' "${GRAFANA_OIDC_CLIENT_SECRET+x}"
} >"$fixture_directory/environment"
: >"$fixture_directory/pgpass"
while IFS= read -r line || [ -n "$line" ]; do
  printf '%s\n' "$line" >>"$fixture_directory/pgpass"
done <"$PGPASSFILE"
: >"$fixture_directory/sql"
while IFS= read -r line || [ -n "$line" ]; do
  printf '%s\n' "$line" >>"$fixture_directory/sql"
done
if [ -r "$fixture_directory/response" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    printf '%s\n' "$line"
  done <"$fixture_directory/response"
fi
if [ -r "$fixture_directory/diagnostic" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    printf '%s\n' "$line" >&2
  done <"$fixture_directory/diagnostic"
fi
exit_code=1
IFS= read -r exit_code <"$fixture_directory/exit-code"
exit "$exit_code"
`
	psqlBinary := filepath.Join(directory, "psql")
	if err := os.WriteFile(psqlBinary, []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	return ssoPolicyFixture{
		directory:        directory,
		psqlBinary:       psqlBinary,
		secretDirectory:  secretDirectory,
		runtimeDirectory: filepath.Join(directory, "runtime"),
	}
}

func runSSOPolicyFixture(t *testing.T, fixture ssoPolicyFixture, interrupted <-chan os.Signal) (string, error) {
	t.Helper()
	var output bytes.Buffer
	err := runSSOPolicyWithRuntime(ssoPolicyRuntime{
		psqlBinary:       fixture.psqlBinary,
		secretDirectory:  fixture.secretDirectory,
		runtimeDirectory: fixture.runtimeDirectory,
		output:           &output,
		interrupted:      interrupted,
	})
	return output.String(), err
}

func readFixtureCapture(t *testing.T, fixture ssoPolicyFixture, name string) string {
	t.Helper()
	value, err := os.ReadFile(filepath.Join(fixture.directory, name))
	if err != nil {
		t.Fatal(err)
	}
	return string(value)
}

func TestPGPassEscapingAndPrivateMode(t *testing.T) {
	entry := buildPGPassEntry("grafana-postgresql", "5432", "grafana", "grafana", []byte(`pa:ss\word`))
	defer wipe(entry)
	if actual, expected := string(entry), "grafana-postgresql:5432:grafana:grafana:pa\\:ss\\\\word\n"; actual != expected {
		t.Fatalf("pgpass escaping: got %q, want %q", actual, expected)
	}
	directory := filepath.Join(t.TempDir(), "runtime")
	directoryFD, err := prepareRuntimeSecretDirectory(directory)
	if err != nil {
		t.Fatal(err)
	}
	defer syscall.Close(directoryFD)
	if err := stagePolicyPasswordFile(directoryFD, entry); err != nil {
		t.Fatal(err)
	}
	info, err := os.Lstat(filepath.Join(directory, ".pgpass"))
	if err != nil {
		t.Fatal(err)
	}
	if !info.Mode().IsRegular() || info.Mode().Perm() != 0o600 {
		t.Fatalf("unexpected pgpass mode: %v", info.Mode())
	}
}

func TestSSOPolicyCommandContractAndReconciliation(t *testing.T) {
	preserveEnvironment(t)
	configureSSOPolicyTestEnvironment(t)
	fixture := newSSOPolicyFixture(t, "token_compliant=4\nsso_deleted=2\nsso_active=0\n", "", 0)
	output, err := runSSOPolicyFixture(t, fixture, nil)
	if err != nil {
		t.Fatalf("valid SSO policy rejected: %v", err)
	}
	if output != "[grafana-sso-policy] Verified 4 compliant active API/service-account token(s); reconciled 2 active SSO override(s); active overrides: 0.\n" {
		t.Fatalf("unexpected policy output: %q", output)
	}
	if actual := readFixtureCapture(t, fixture, "pgpass"); actual != "grafana-postgresql:5432:grafana:grafana:pa\\:ss\\\\word\n" {
		t.Fatalf("unexpected staged pgpass: %q", actual)
	}
	arguments := readFixtureCapture(t, fixture, "arguments")
	for _, expected := range []string{"--no-psqlrc", "--no-password", "--set=ON_ERROR_STOP=1", "--host", "grafana-postgresql", "--port", "5432", "--username", "grafana", "--dbname"} {
		if !strings.Contains("\n"+arguments, "\n"+expected+"\n") {
			t.Fatalf("missing psql argument %q in %q", expected, arguments)
		}
	}
	if strings.Contains(arguments, "pa:ss") {
		t.Fatal("database password leaked into psql argv")
	}
	environment := readFixtureCapture(t, fixture, "environment")
	for _, expected := range []string{"LC_ALL=C", "PGAPPNAME=grafana-sso-policy", "PGCONNECT_TIMEOUT=5", "PGSSLMODE=disable", "POSTGRES_PASSWORD_SET=", "GRAFANA_OIDC_CLIENT_SECRET_SET="} {
		if !strings.Contains(environment, expected+"\n") {
			t.Fatalf("missing isolated child environment %q in %q", expected, environment)
		}
	}
	if strings.Contains(environment, "pa:ss") {
		t.Fatal("database password leaked into child environment")
	}
	sql := readFixtureCapture(t, fixture, "sql")
	for _, expected := range []string{
		"SET LOCAL TIME ZONE 'UTC'",
		"ARRAY['id'::name]",
		"grafana_policy_sso_schema_mismatch",
		"grafana_policy_api_key_schema_mismatch",
		"COALESCE(is_revoked, false) = false",
		"expires > floor(extract(epoch FROM CURRENT_TIMESTAMP))::bigint",
		"make_interval(days => 90)",
		"UPDATE public.sso_setting",
		"SET is_deleted = true, updated = CURRENT_TIMESTAMP",
	} {
		if !strings.Contains(sql, expected) {
			t.Fatalf("policy SQL missing %q", expected)
		}
	}
	if strings.Contains(sql, "pa:ss") {
		t.Fatal("database password leaked into policy SQL")
	}
	if _, err := os.Lstat(filepath.Join(fixture.runtimeDirectory, ".pgpass")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("private pgpass was not removed: %v", err)
	}
}

func TestSSOPolicyFailsClosedOnDebtSchemaAndClientErrors(t *testing.T) {
	for _, testCase := range []struct {
		name       string
		response   string
		diagnostic string
		exitCode   int
		want       string
	}{
		{name: "token-debt", diagnostic: "ERROR: grafana_policy_token_debt=3", exitCode: 1, want: "3 active API or service-account token(s) violate the 90-day expiration policy"},
		{name: "sso-schema", diagnostic: "ERROR: grafana_policy_sso_schema_mismatch", exitCode: 1, want: "sso_setting schema does not match"},
		{name: "api-key-schema", diagnostic: "ERROR: grafana_policy_api_key_schema_mismatch", exitCode: 1, want: "api_key schema does not match"},
		{name: "psql-failure", diagnostic: "ERROR: secret pa:ss\\word must never escape", exitCode: 2, want: "PostgreSQL policy transaction failed"},
		{name: "active-remains", response: "token_compliant=0\nsso_deleted=1\nsso_active=1\n", exitCode: 0, want: "left 1 active database override"},
		{name: "invalid-count", response: "unexpected\n", exitCode: 0, want: "invalid result"},
	} {
		t.Run(testCase.name, func(t *testing.T) {
			preserveEnvironment(t)
			configureSSOPolicyTestEnvironment(t)
			fixture := newSSOPolicyFixture(t, testCase.response, testCase.diagnostic, testCase.exitCode)
			_, err := runSSOPolicyFixture(t, fixture, nil)
			if err == nil || !strings.Contains(err.Error(), testCase.want) {
				t.Fatalf("unexpected policy failure: %v", err)
			}
			if strings.Contains(err.Error(), "pa:ss") {
				t.Fatal("psql diagnostic leaked secret content")
			}
			if _, statError := os.Lstat(filepath.Join(fixture.runtimeDirectory, ".pgpass")); !errors.Is(statError, os.ErrNotExist) {
				t.Fatalf("failed policy retained pgpass: %v", statError)
			}
		})
	}
}

func TestSSOPolicyRejectsCompetingInputsAndUnsafeClient(t *testing.T) {
	t.Run("extra-secret", func(t *testing.T) {
		preserveEnvironment(t)
		configureSSOPolicyTestEnvironment(t)
		fixture := newSSOPolicyFixture(t, "token_compliant=0\nsso_deleted=0\nsso_active=0\n", "", 0)
		writeTestSecret(t, fixture.secretDirectory, "GRAFANA_OIDC_CLIENT_SECRET", []byte("forbidden"))
		if _, err := runSSOPolicyFixture(t, fixture, nil); err == nil {
			t.Fatal("extra policy secret mount accepted")
		}
	})
	t.Run("protected-environment", func(t *testing.T) {
		preserveEnvironment(t)
		configureSSOPolicyTestEnvironment(t)
		fixture := newSSOPolicyFixture(t, "token_compliant=0\nsso_deleted=0\nsso_active=0\n", "", 0)
		t.Setenv("GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET", "forbidden")
		if _, err := runSSOPolicyFixture(t, fixture, nil); err == nil {
			t.Fatal("protected policy environment accepted")
		}
	})
	for _, name := range []string{"GF_DATABASE_URL", "GF_DATABASE_CONNECTION_STRING", "GF_DATABASE_SKIP_MIGRATIONS"} {
		t.Run("database-environment-"+name, func(t *testing.T) {
			preserveEnvironment(t)
			configureSSOPolicyTestEnvironment(t)
			fixture := newSSOPolicyFixture(t, "token_compliant=0\nsso_deleted=0\nsso_active=0\n", "", 0)
			t.Setenv(name, "forbidden")
			if _, err := runSSOPolicyFixture(t, fixture, nil); err == nil {
				t.Fatal("unreviewed policy database environment accepted")
			}
		})
	}
	t.Run("symlink-client", func(t *testing.T) {
		preserveEnvironment(t)
		configureSSOPolicyTestEnvironment(t)
		fixture := newSSOPolicyFixture(t, "token_compliant=0\nsso_deleted=0\nsso_active=0\n", "", 0)
		link := filepath.Join(fixture.directory, "psql-link")
		if err := os.Symlink(fixture.psqlBinary, link); err != nil {
			t.Fatal(err)
		}
		fixture.psqlBinary = link
		if _, err := runSSOPolicyFixture(t, fixture, nil); err == nil {
			t.Fatal("symlinked PostgreSQL client accepted")
		}
	})
	for _, timeout := range []string{"4", "121", "not-a-number"} {
		t.Run("timeout-"+timeout, func(t *testing.T) {
			preserveEnvironment(t)
			configureSSOPolicyTestEnvironment(t)
			fixture := newSSOPolicyFixture(t, "token_compliant=0\nsso_deleted=0\nsso_active=0\n", "", 0)
			t.Setenv("GRAFANA_SSO_POLICY_TIMEOUT_SECONDS", timeout)
			if _, err := runSSOPolicyFixture(t, fixture, nil); err == nil {
				t.Fatal("unsafe SSO policy timeout accepted")
			}
		})
	}
}

func TestSSOPolicyForwardsInterruptAndRemovesPasswordFile(t *testing.T) {
	preserveEnvironment(t)
	configureSSOPolicyTestEnvironment(t)
	fixture := newSSOPolicyFixture(t, "", "", 0)
	if err := os.WriteFile(fixture.psqlBinary, []byte("#!/bin/sh\ntrap 'exit 0' TERM INT\nwhile :; do :; done\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	interrupted := make(chan os.Signal, 1)
	interrupted <- syscall.SIGTERM
	started := time.Now()
	_, err := runSSOPolicyFixture(t, fixture, interrupted)
	var coded *exitCodeError
	if !errors.As(err, &coded) || coded.code != 143 {
		t.Fatalf("unexpected interrupted policy result: %v", err)
	}
	if time.Since(started) > 7*time.Second {
		t.Fatal("interrupted policy exceeded its bounded shutdown")
	}
	if _, statError := os.Lstat(filepath.Join(fixture.runtimeDirectory, ".pgpass")); !errors.Is(statError, os.ErrNotExist) {
		t.Fatalf("interrupted policy retained pgpass: %v", statError)
	}
}

func TestBootstrapMarkerContract(t *testing.T) {
	stateDirectory := t.TempDir()
	if err := readBootstrapMarker(stateDirectory); !errors.Is(err, errMarkerMissing) {
		t.Fatalf("missing marker result: %v", err)
	}
	if err := writeBootstrapMarker(stateDirectory); err != nil {
		t.Fatalf("write marker: %v", err)
	}
	if err := readBootstrapMarker(stateDirectory); err != nil {
		t.Fatalf("read valid marker: %v", err)
	}
	matches, err := filepath.Glob(filepath.Join(stateDirectory, bootstrapMarkerName+".pending-*"))
	if err != nil || len(matches) != 0 {
		t.Fatal("bootstrap marker staging file remained after atomic publication")
	}
	if err := os.WriteFile(filepath.Join(stateDirectory, bootstrapMarkerName), []byte("wrong"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := readBootstrapMarker(stateDirectory); err == nil {
		t.Fatal("malformed marker accepted")
	}
}

func TestBootstrapConfigurationBounds(t *testing.T) {
	preserveEnvironment(t)
	if err := validateAdminUser("recovery-admin"); err != nil {
		t.Fatalf("valid recovery admin rejected: %v", err)
	}
	if err := validateAdminUser("recovery:admin"); err == nil {
		t.Fatal("colon-containing recovery admin accepted")
	}
	t.Setenv("GRAFANA_BOOTSTRAP_STOP_TIMEOUT_SECONDS", "60")
	if _, err := parseBootstrapStopTimeout(); err != nil {
		t.Fatalf("maximum safe stop timeout rejected: %v", err)
	}
	t.Setenv("GRAFANA_BOOTSTRAP_STOP_TIMEOUT_SECONDS", "61")
	if _, err := parseBootstrapStopTimeout(); err == nil {
		t.Fatal("stop timeout exceeding Compose grace period accepted")
	}
}

func TestBootstrapMarkerSkipsCredentialPhase(t *testing.T) {
	preserveEnvironment(t)
	stateDirectory := t.TempDir()
	if err := writeBootstrapMarker(stateDirectory); err != nil {
		t.Fatal(err)
	}
	t.Setenv("GRAFANA_BOOTSTRAP_STATE_DIR", stateDirectory)
	t.Setenv("GRAFANA_VENDOR_ENTRYPOINT", filepath.Join(t.TempDir(), "missing"))
	if err := runBootstrap(); err != nil {
		t.Fatalf("verified marker did not skip credential phase: %v", err)
	}
}

func TestMigrationBootstrapChildVerifiesHealthWithoutAdminPassword(t *testing.T) {
	preserveEnvironment(t)
	configureDatabaseTestEnvironment(t)
	vendorEntrypoint := filepath.Join(t.TempDir(), "vendor-entrypoint")
	if err := os.WriteFile(vendorEntrypoint, []byte("#!/bin/sh\n[ -z \"${GF_SECURITY_ADMIN_PASSWORD+x}\" ] || exit 41\n[ -z \"${GF_SECURITY_ADMIN_USER+x}\" ] || exit 42\n[ \"${GF_AUTH_DISABLE_LOGIN_FORM:-}\" = true ] || exit 43\n[ \"${GF_AUTH_BASIC_ENABLED:-}\" = false ] || exit 44\n[ \"${GF_DATABASE_SKIP_MIGRATIONS:-}\" = false ] || exit 45\n[ \"${GF_DATABASE_MIGRATION_LOCKING:-}\" = true ] || exit 46\n[ \"${GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC:-}\" = 0 ] || exit 47\n[ -z \"${GF_DATABASE_URL+x}\" ] || exit 48\ntrap 'exit 0' TERM INT\nwhile :; do sleep 1; done\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("GRAFANA_VENDOR_ENTRYPOINT", vendorEntrypoint)
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		response.Header().Set("Content-Type", "application/json")
		_, _ = response.Write([]byte(`{"database":"ok"}`))
	}))
	defer server.Close()
	interrupted := make(chan os.Signal, 1)
	if err := runMigrationChild(t.TempDir(), server.URL, 3*time.Second, 2*time.Second, interrupted); err != nil {
		t.Fatalf("credential-free migration child failed: %v", err)
	}
}

func TestMigratorRequiresExactSecretMounts(t *testing.T) {
	secretDirectory := t.TempDir()
	for _, name := range []string{"POSTGRES_PASSWORD", "GRAFANA_SECRET_KEY"} {
		if err := os.WriteFile(filepath.Join(secretDirectory, name), []byte("valid-secret"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	if err := validateMigratorSecretMounts(secretDirectory); err != nil {
		t.Fatalf("exact migrator secrets rejected: %v", err)
	}
	if err := os.WriteFile(filepath.Join(secretDirectory, "GRAFANA_ADMIN_PASSWORD"), []byte("forbidden"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := validateMigratorSecretMounts(secretDirectory); err == nil {
		t.Fatal("migrator accepted bootstrap administrator secret")
	}
	if err := os.Remove(filepath.Join(secretDirectory, "GRAFANA_ADMIN_PASSWORD")); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(filepath.Join(secretDirectory, "GRAFANA_SECRET_KEY")); err != nil {
		t.Fatal(err)
	}
	if err := validateMigratorSecretMounts(secretDirectory); err == nil {
		t.Fatal("migrator accepted a missing secret key")
	}
}

func TestMigratorStopTimeoutIsBoundedByComposeGracePeriod(t *testing.T) {
	preserveEnvironment(t)
	t.Setenv("GRAFANA_MIGRATOR_STOP_TIMEOUT_SECONDS", "60")
	if _, err := parseMigratorStopTimeout(); err != nil {
		t.Fatalf("maximum safe migrator stop timeout rejected: %v", err)
	}
	t.Setenv("GRAFANA_MIGRATOR_STOP_TIMEOUT_SECONDS", "61")
	if _, err := parseMigratorStopTimeout(); err == nil {
		t.Fatal("migrator stop timeout exceeding Compose grace period accepted")
	}
}

func TestBootstrapMarkerIgnoresStalePIDPendingFile(t *testing.T) {
	stateDirectory := t.TempDir()
	staleName := bootstrapMarkerName + ".pending-" + strconv.Itoa(os.Getpid())
	if err := os.WriteFile(filepath.Join(stateDirectory, staleName), []byte("stale"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := writeBootstrapMarker(stateDirectory); err != nil {
		t.Fatalf("stale PID-based pending marker blocked publication: %v", err)
	}
	if err := readBootstrapMarker(stateDirectory); err != nil {
		t.Fatalf("published marker is invalid: %v", err)
	}
}

func TestBootstrapMarkerIsNotPublishedAfterInterrupt(t *testing.T) {
	stateDirectory := t.TempDir()
	interrupted := make(chan os.Signal, 1)
	interrupted <- syscall.SIGTERM
	err := writeBootstrapMarker(stateDirectory, interrupted)
	var coded *exitCodeError
	if !errors.As(err, &coded) || coded.code != 143 {
		t.Fatalf("interrupted marker publication returned %v", err)
	}
	if err := readBootstrapMarker(stateDirectory); !errors.Is(err, errMarkerMissing) {
		t.Fatalf("interrupted bootstrap published a marker: %v", err)
	}
}

func TestBootstrapMarkerPublicationNeverReplacesExistingPath(t *testing.T) {
	stateDirectory := t.TempDir()
	markerPath := filepath.Join(stateDirectory, bootstrapMarkerName)
	original := []byte("concurrent-marker")
	if err := os.WriteFile(markerPath, original, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := writeBootstrapMarker(stateDirectory); err == nil {
		t.Fatal("existing marker path was replaced")
	}
	actual, err := os.ReadFile(markerPath)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(actual, original) {
		t.Fatal("existing marker content changed")
	}
}

func TestBootstrapMarkerRevokesInterruptBeforeDurableCommit(t *testing.T) {
	stateDirectory := t.TempDir()
	interrupted := make(chan os.Signal, 1)
	err := writeBootstrapMarkerWithHook(stateDirectory, interrupted, func() {
		interrupted <- syscall.SIGTERM
	})
	var coded *exitCodeError
	if !errors.As(err, &coded) || coded.code != 143 {
		t.Fatalf("late-interrupted marker publication returned %v", err)
	}
	if err := readBootstrapMarker(stateDirectory); !errors.Is(err, errMarkerMissing) {
		t.Fatalf("late-interrupted bootstrap retained a marker: %v", err)
	}
}

func TestVendorEnvironmentScrubsAdminPassword(t *testing.T) {
	preserveEnvironment(t)
	configureDatabaseTestEnvironment(t)
	t.Setenv("GRAFANA_ADMIN_USER", "recovery-admin")
	t.Setenv("GF_SECURITY_ADMIN_PASSWORD", "stale-secret")
	first, err := vendorEnvironment("/run/private", true)
	if err != nil {
		t.Fatal(err)
	}
	second, err := vendorEnvironment("/run/private", false)
	if err != nil {
		t.Fatal(err)
	}
	join := func(environment []string) string { return "\n" + strings.Join(environment, "\n") + "\n" }
	if strings.Contains(join(first), "stale-secret") || !strings.Contains(join(first), "\nGF_SECURITY_ADMIN_PASSWORD=$__file{/run/private/GRAFANA_ADMIN_PASSWORD}\n") {
		t.Fatal("first child did not receive only the file reference")
	}
	if strings.Contains(join(second), "GF_SECURITY_ADMIN_PASSWORD=") || !strings.Contains(join(second), "\nGF_SECURITY_DISABLE_INITIAL_ADMIN_CREATION=true\n") {
		t.Fatal("second child retained bootstrap password configuration")
	}
}

func TestHealthcheckRequiresDatabaseOK(t *testing.T) {
	for _, testCase := range []struct {
		database  string
		wantError bool
	}{
		{database: "ok", wantError: false},
		{database: "failed", wantError: true},
	} {
		t.Run(testCase.database, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
				response.Header().Set("Content-Type", "application/json")
				_, _ = response.Write([]byte(`{"database":"` + testCase.database + `"}`))
			}))
			defer server.Close()
			err := checkHealthURL(server.URL)
			if (err != nil) != testCase.wantError {
				t.Fatalf("health result: %v", err)
			}
		})
	}
}

func TestStopChildEscalatesToKill(t *testing.T) {
	ready := filepath.Join(t.TempDir(), "ready")
	command := exec.Command("/bin/sh", "-c", "trap '' TERM INT; : >\"$1\"; while :; do :; done", "fixture", ready)
	command.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := command.Start(); err != nil {
		t.Skipf("cannot start signal fixture: %v", err)
	}
	done := make(chan error, 1)
	go func() { done <- command.Wait() }()
	deadline := time.Now().Add(2 * time.Second)
	for {
		if _, err := os.Stat(ready); err == nil {
			break
		}
		if time.Now().After(deadline) {
			_ = syscall.Kill(-command.Process.Pid, syscall.SIGKILL)
			<-done
			t.Fatal("signal fixture did not become ready")
		}
		time.Sleep(10 * time.Millisecond)
	}
	started := time.Now()
	if err := stopChild(command, done, syscall.SIGTERM, 200*time.Millisecond); err != nil {
		t.Fatalf("bounded TERM-to-KILL failed: %v", err)
	}
	elapsed := time.Since(started)
	if elapsed < 500*time.Millisecond {
		t.Fatal("TERM-resistant child exited before KILL escalation")
	}
	if elapsed > 12*time.Second {
		t.Fatal("TERM-to-KILL escalation exceeded its bound")
	}
}
