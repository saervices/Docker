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
	for name, value := range map[string]string{
		"APP_DOMAIN":                "grafana.example.test",
		"AUTHENTIK_DOMAIN":          "authentik.example.test",
		"GRAFANA_OIDC_SLUG":         "grafana",
		"GRAFANA_OIDC_NAME":         "authentik",
		"GRAFANA_OIDC_ACCESS_GROUP": "grafana-users",
		"GRAFANA_OIDC_ADMIN_GROUP":  "grafana-admins",
		"GRAFANA_OIDC_EDITOR_GROUP": "grafana-editors",
		"GRAFANA_OIDC_VIEWER_GROUP": "grafana-viewers",
		"GRAFANA_OIDC_SCOPES":       "openid profile email",
		"GRAFANA_OAUTH_AUTO_LOGIN":  "false",
		"GRAFANA_SMTP_ENABLED":      "false",
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
		"GF_SECURITY_SECRET_KEY":                           "$__file{" + runtimeDirectory + "/GRAFANA_SECRET_KEY}",
		"GF_SECURITY_DISABLE_INITIAL_ADMIN_CREATION":       "true",
		"GF_AUTH_GENERIC_OAUTH_VALIDATE_ID_TOKEN":          "true",
		"GF_AUTH_GENERIC_OAUTH_LOGIN_ATTRIBUTE_PATH":       "sub",
		"GF_AUTH_GENERIC_OAUTH_ALLOWED_GROUPS":             "grafana-users",
		"GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_STRICT":      "true",
		"GF_AUTH_GENERIC_OAUTH_JWK_SET_URL":                "https://authentik.example.test/application/o/grafana/jwks/",
		"GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES":            "false",
		"GF_AUTH_BASIC_ENABLED":                            "false",
		"GF_AUTH_ANONYMOUS_ENABLED":                        "false",
		"GF_AUTH_GENERIC_OAUTH_ALLOW_ASSIGN_GRAFANA_ADMIN": "true",
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
		"GF_DATABASE_TYPE": "postgres",
		"GF_DATABASE_HOST": "grafana-postgresql:5432",
		"GF_DATABASE_NAME": "grafana",
		"GF_DATABASE_USER": "grafana",
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
				"GF_DATABASE_TYPE": testCase.database,
				"GF_DATABASE_HOST": "grafana-postgresql:5432",
				"GF_DATABASE_NAME": "grafana",
				"GF_DATABASE_USER": "grafana",
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
