// SPDX-License-Identifier: MIT
// Copyright (c) 2025 it.særvices
//
// Græfænæ descriptor-bæsed secret preflight ænd one-shot ædmin bootstræp.
package main

import (
	"bytes"
	cryptorand "crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/mail"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unicode"
	"unicode/utf8"
	"unsafe"
)

const (
	defaultSecretDirectory          = "/run/secrets"
	defaultRuntimeSecretDir         = "/run/grafana-secrets"
	defaultBootstrapStateDir        = "/var/lib/grafana-bootstrap-state"
	defaultBootstrapPluginDir       = "/run/grafana-bootstrap-plugins"
	defaultVendorEntrypoint         = "/run.sh"
	defaultGrafanaBinary            = "/usr/share/grafana/bin/grafana"
	defaultGrafanaHome              = "/usr/share/grafana"
	defaultGrafanaConfig            = "/etc/grafana/grafana.ini"
	bootstrapMarkerName             = "bootstrap-v1.complete"
	bootstrapMarkerContent          = "grafana-bootstrap-v1"
	maximumSecretBytes        int64 = 4096
)

var errMarkerMissing = errors.New("bootstrap marker is missing")
var errBootstrapChildExited = errors.New("Grafana bootstrap child exited before verification")

type exitCodeError struct {
	code int
	err  error
}

func (e *exitCodeError) Error() string {
	return e.err.Error()
}

type fileIdentity struct {
	device     uint64
	inode      uint64
	mode       uint32
	linkCount  uint64
	size       int64
	modifySec  int64
	modifyNsec int64
	changeSec  int64
	changeNsec int64
}

func identityFromStat(stat *syscall.Stat_t) fileIdentity {
	return fileIdentity{
		device:     uint64(stat.Dev),
		inode:      stat.Ino,
		mode:       stat.Mode,
		linkCount:  uint64(stat.Nlink),
		size:       stat.Size,
		modifySec:  stat.Mtim.Sec,
		modifyNsec: stat.Mtim.Nsec,
		changeSec:  stat.Ctim.Sec,
		changeNsec: stat.Ctim.Nsec,
	}
}

func wipe(value []byte) {
	for index := range value {
		value[index] = 0
	}
}

func openDirectory(path string) (int, error) {
	fd, err := syscall.Open(path, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return -1, fmt.Errorf("cannot open directory safely")
	}
	var stat syscall.Stat_t
	if err := syscall.Fstat(fd, &stat); err != nil {
		syscall.Close(fd)
		return -1, fmt.Errorf("cannot inspect directory safely")
	}
	if stat.Mode&syscall.S_IFMT != syscall.S_IFDIR {
		syscall.Close(fd)
		return -1, fmt.Errorf("path is not a directory")
	}
	return fd, nil
}

func readBoundedRegularAt(directoryFD int, name string, maximumBytes int64) ([]byte, error) {
	if name == "" || name != filepath.Base(name) || strings.ContainsRune(name, '/') {
		return nil, fmt.Errorf("invalid file name")
	}
	fd, err := syscall.Openat(directoryFD, name, syscall.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return nil, fmt.Errorf("cannot open file safely")
	}
	file := os.NewFile(uintptr(fd), name)
	if file == nil {
		syscall.Close(fd)
		return nil, fmt.Errorf("cannot bind file descriptor")
	}
	defer file.Close()

	var before syscall.Stat_t
	if err := syscall.Fstat(fd, &before); err != nil {
		return nil, fmt.Errorf("cannot inspect file")
	}
	if before.Mode&syscall.S_IFMT != syscall.S_IFREG {
		return nil, fmt.Errorf("file is not regular")
	}
	if before.Nlink != 1 {
		return nil, fmt.Errorf("file must have exactly one hard link")
	}
	if before.Size < 1 || before.Size > maximumBytes {
		return nil, fmt.Errorf("file has an invalid length")
	}

	value, err := io.ReadAll(io.LimitReader(file, maximumBytes+1))
	if err != nil {
		return nil, fmt.Errorf("cannot read file safely")
	}
	if int64(len(value)) != before.Size || int64(len(value)) > maximumBytes {
		wipe(value)
		return nil, fmt.Errorf("file changed while it was read")
	}

	var after syscall.Stat_t
	if err := syscall.Fstat(fd, &after); err != nil {
		wipe(value)
		return nil, fmt.Errorf("cannot re-inspect file")
	}
	if identityFromStat(&before) != identityFromStat(&after) {
		wipe(value)
		return nil, fmt.Errorf("file identity changed while it was read")
	}
	return value, nil
}

func validateSecretValue(value []byte) error {
	if bytes.Equal(value, []byte("CHANGE_ME")) {
		return fmt.Errorf("secret still contains the placeholder")
	}
	if !utf8.Valid(value) {
		return fmt.Errorf("secret is not valid UTF-8")
	}
	secret := string(value)
	if strings.TrimSpace(secret) != secret {
		return fmt.Errorf("secret contains leading or trailing whitespace")
	}
	for _, character := range secret {
		if unicode.IsControl(character) || unicode.In(character, unicode.Zl, unicode.Zp) {
			return fmt.Errorf("secret contains control characters")
		}
	}
	return nil
}

func readSecret(secretDirectory, name string) ([]byte, error) {
	directoryFD, err := openDirectory(secretDirectory)
	if err != nil {
		return nil, err
	}
	defer syscall.Close(directoryFD)
	value, err := readBoundedRegularAt(directoryFD, name, maximumSecretBytes)
	if err != nil {
		return nil, fmt.Errorf("required secret %s is invalid: %w", name, err)
	}
	if err := validateSecretValue(value); err != nil {
		wipe(value)
		return nil, fmt.Errorf("required secret %s is invalid: %w", name, err)
	}
	return value, nil
}

func secretExists(secretDirectory, name string) (bool, error) {
	directoryFD, err := openDirectory(secretDirectory)
	if err != nil {
		return false, err
	}
	defer syscall.Close(directoryFD)
	fd, err := syscall.Openat(directoryFD, name, syscall.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if errors.Is(err, syscall.ENOENT) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("cannot inspect optional secret %s safely", name)
	}
	defer syscall.Close(fd)
	var stat syscall.Stat_t
	if err := syscall.Fstat(fd, &stat); err != nil {
		return false, fmt.Errorf("cannot inspect optional secret %s", name)
	}
	if stat.Mode&syscall.S_IFMT != syscall.S_IFREG || stat.Nlink != 1 {
		return false, fmt.Errorf("optional secret %s is not a single regular file", name)
	}
	return true, nil
}

func prepareRuntimeSecretDirectory(path string) (int, error) {
	if err := os.Mkdir(path, 0o700); err != nil {
		return -1, fmt.Errorf("cannot create private runtime secret directory")
	}
	if err := os.Chmod(path, 0o700); err != nil {
		return -1, fmt.Errorf("cannot lock private runtime secret directory")
	}
	return openDirectory(path)
}

func stageSecret(directoryFD int, name string, value []byte) error {
	fd, err := syscall.Openat(directoryFD, name, syscall.O_WRONLY|syscall.O_CREAT|syscall.O_EXCL|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0o400)
	if err != nil {
		return fmt.Errorf("cannot create private copy for %s", name)
	}
	file := os.NewFile(uintptr(fd), name)
	if file == nil {
		syscall.Close(fd)
		return fmt.Errorf("cannot bind private copy for %s", name)
	}
	if _, err := file.Write(value); err != nil {
		file.Close()
		return fmt.Errorf("cannot write private copy for %s", name)
	}
	if err := file.Sync(); err != nil {
		file.Close()
		return fmt.Errorf("cannot sync private copy for %s", name)
	}
	if err := file.Close(); err != nil {
		return fmt.Errorf("cannot close private copy for %s", name)
	}
	return nil
}

func loadAndStageSecrets(secretDirectory, runtimeDirectory string, names []string) (map[string][]byte, error) {
	runtimeFD, err := prepareRuntimeSecretDirectory(runtimeDirectory)
	if err != nil {
		return nil, err
	}
	defer syscall.Close(runtimeFD)
	values := make(map[string][]byte, len(names))
	cleanup := func() {
		for _, value := range values {
			wipe(value)
		}
	}
	for _, name := range names {
		value, err := readSecret(secretDirectory, name)
		if err != nil {
			cleanup()
			return nil, err
		}
		if err := stageSecret(runtimeFD, name, value); err != nil {
			wipe(value)
			cleanup()
			return nil, err
		}
		values[name] = value
	}
	if err := syscall.Fsync(runtimeFD); err != nil {
		cleanup()
		return nil, fmt.Errorf("cannot sync private runtime secret directory")
	}
	return values, nil
}

func rejectProtectedEnvironment(names ...string) error {
	for _, name := range names {
		if _, exists := os.LookupEnv(name); exists {
			return fmt.Errorf("protected environment variable %s must not be supplied", name)
		}
	}
	return nil
}

func setEnvironment(name, value string) error {
	if err := os.Setenv(name, value); err != nil {
		return fmt.Errorf("cannot set runtime configuration %s", name)
	}
	return nil
}

func setEnvironments(values map[string]string) error {
	for name, value := range values {
		if err := setEnvironment(name, value); err != nil {
			return err
		}
	}
	return nil
}

func parseStrictBoolean(name string, defaultValue bool) (bool, error) {
	value, exists := os.LookupEnv(name)
	if !exists || value == "" {
		return defaultValue, nil
	}
	switch value {
	case "true":
		return true, nil
	case "false":
		return false, nil
	default:
		return false, fmt.Errorf("%s must be true or false", name)
	}
}

func validateHostname(name, value string) error {
	if value == "" || value != strings.ToLower(value) || len(value) > 253 || strings.Contains(value, "..") {
		return fmt.Errorf("%s must be a lower-case DNS hostname", name)
	}
	labels := strings.Split(value, ".")
	for _, label := range labels {
		if label == "" || len(label) > 63 || label[0] == '-' || label[len(label)-1] == '-' {
			return fmt.Errorf("%s must be a lower-case DNS hostname", name)
		}
		for _, character := range label {
			if (character < 'a' || character > 'z') && (character < '0' || character > '9') && character != '-' {
				return fmt.Errorf("%s must be a lower-case DNS hostname", name)
			}
		}
	}
	return nil
}

func validateToken(name, value string) error {
	if value == "" || value == "CHANGE_ME" || len(value) > 128 {
		return fmt.Errorf("%s has an invalid length", name)
	}
	for _, character := range value {
		if (character < 'a' || character > 'z') && (character < 'A' || character > 'Z') && (character < '0' || character > '9') && !strings.ContainsRune("._:@+-", character) {
			return fmt.Errorf("%s contains unsupported characters", name)
		}
	}
	return nil
}

func validateDisplayValue(name, value string) error {
	if value == "" || value == "CHANGE_ME" || len(value) > 128 || !utf8.ValidString(value) {
		return fmt.Errorf("%s has an invalid value", name)
	}
	for _, character := range value {
		if unicode.IsControl(character) {
			return fmt.Errorf("%s contains control characters", name)
		}
	}
	return nil
}

func validateURLSlug(name, value string) error {
	if value == "" || len(value) > 64 || value != strings.ToLower(value) {
		return fmt.Errorf("%s must be a lower-case URL slug", name)
	}
	for index, character := range value {
		isLetterOrDigit := (character >= 'a' && character <= 'z') || (character >= '0' && character <= '9')
		if !isLetterOrDigit && character != '-' && character != '_' {
			return fmt.Errorf("%s must be a lower-case URL slug", name)
		}
		if (index == 0 || index == len(value)-1) && !isLetterOrDigit {
			return fmt.Errorf("%s must start and end with a letter or digit", name)
		}
	}
	return nil
}

func configureOIDC(runtimeSecretDirectory string) error {
	appDomain := os.Getenv("APP_DOMAIN")
	authentikDomain := os.Getenv("AUTHENTIK_DOMAIN")
	slug := os.Getenv("GRAFANA_OIDC_SLUG")
	providerName := os.Getenv("GRAFANA_OIDC_NAME")
	accessGroup := os.Getenv("GRAFANA_OIDC_ACCESS_GROUP")
	adminGroup := os.Getenv("GRAFANA_OIDC_ADMIN_GROUP")
	editorGroup := os.Getenv("GRAFANA_OIDC_EDITOR_GROUP")
	viewerGroup := os.Getenv("GRAFANA_OIDC_VIEWER_GROUP")
	scopes := strings.Fields(os.Getenv("GRAFANA_OIDC_SCOPES"))
	if err := validateHostname("APP_DOMAIN", appDomain); err != nil {
		return err
	}
	if err := validateHostname("AUTHENTIK_DOMAIN", authentikDomain); err != nil {
		return err
	}
	if err := validateURLSlug("GRAFANA_OIDC_SLUG", slug); err != nil {
		return err
	}
	for name, value := range map[string]string{
		"GRAFANA_OIDC_ACCESS_GROUP": accessGroup,
		"GRAFANA_OIDC_ADMIN_GROUP":  adminGroup,
		"GRAFANA_OIDC_EDITOR_GROUP": editorGroup,
		"GRAFANA_OIDC_VIEWER_GROUP": viewerGroup,
	} {
		if err := validateToken(name, value); err != nil {
			return err
		}
	}
	groupNames := []string{accessGroup, adminGroup, editorGroup, viewerGroup}
	for index, groupName := range groupNames {
		for otherIndex := index + 1; otherIndex < len(groupNames); otherIndex++ {
			if groupName == groupNames[otherIndex] {
				return fmt.Errorf("OIDC access and role groups must be distinct")
			}
		}
	}
	if err := validateDisplayValue("GRAFANA_OIDC_NAME", providerName); err != nil {
		return err
	}
	seenScopes := make(map[string]bool)
	for _, scope := range scopes {
		if err := validateToken("GRAFANA_OIDC_SCOPES", scope); err != nil {
			return err
		}
		seenScopes[scope] = true
	}
	for _, requiredScope := range []string{"openid", "profile", "email"} {
		if !seenScopes[requiredScope] {
			return fmt.Errorf("GRAFANA_OIDC_SCOPES must include %s", requiredScope)
		}
	}
	baseURL := "https://" + authentikDomain + "/application/o/"
	roleExpression := fmt.Sprintf(
		"contains(groups[*], '%s') && 'GrafanaAdmin' || contains(groups[*], '%s') && 'Editor' || contains(groups[*], '%s') && 'Viewer'",
		adminGroup,
		editorGroup,
		viewerGroup,
	)
	return setEnvironments(map[string]string{
		"GF_SERVER_ROOT_URL":                               "https://" + appDomain + "/",
		"GF_AUTH_GENERIC_OAUTH_ENABLED":                    "true",
		"GF_AUTH_GENERIC_OAUTH_NAME":                       providerName,
		"GF_AUTH_GENERIC_OAUTH_SCOPES":                     strings.Join(scopes, " "),
		"GF_AUTH_GENERIC_OAUTH_AUTH_URL":                   baseURL + "authorize/",
		"GF_AUTH_GENERIC_OAUTH_TOKEN_URL":                  baseURL + "token/",
		"GF_AUTH_GENERIC_OAUTH_API_URL":                    baseURL + "userinfo/",
		"GF_AUTH_GENERIC_OAUTH_JWK_SET_URL":                baseURL + slug + "/jwks/",
		"GF_AUTH_SIGNOUT_REDIRECT_URL":                     baseURL + slug + "/end-session/",
		"GF_AUTH_GENERIC_OAUTH_CLIENT_ID":                  "$__file{" + runtimeSecretDirectory + "/GRAFANA_OIDC_CLIENT_ID}",
		"GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET":              "$__file{" + runtimeSecretDirectory + "/GRAFANA_OIDC_CLIENT_SECRET}",
		"GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP":              "true",
		"GF_AUTH_GENERIC_OAUTH_AUTO_LOGIN":                 os.Getenv("GRAFANA_OAUTH_AUTO_LOGIN"),
		"GF_AUTH_GENERIC_OAUTH_USE_PKCE":                   "true",
		"GF_AUTH_GENERIC_OAUTH_VALIDATE_ID_TOKEN":          "true",
		"GF_AUTH_GENERIC_OAUTH_LOGIN_ATTRIBUTE_PATH":       "sub",
		"GF_AUTH_GENERIC_OAUTH_NAME_ATTRIBUTE_PATH":        "name",
		"GF_AUTH_GENERIC_OAUTH_EMAIL_ATTRIBUTE_PATH":       "email",
		"GF_AUTH_GENERIC_OAUTH_GROUPS_ATTRIBUTE_PATH":      "groups",
		"GF_AUTH_GENERIC_OAUTH_ALLOWED_GROUPS":             accessGroup,
		"GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH":        roleExpression,
		"GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_STRICT":      "true",
		"GF_AUTH_GENERIC_OAUTH_ALLOW_ASSIGN_GRAFANA_ADMIN": "true",
	})
}

func configureSMTP(secretDirectory, runtimeSecretDirectory string) ([]string, error) {
	enabled, err := parseStrictBoolean("GRAFANA_SMTP_ENABLED", false)
	if err != nil {
		return nil, err
	}
	if !enabled {
		exists, err := secretExists(secretDirectory, "MAILER_SMTP_PASSWORD")
		if err != nil {
			return nil, err
		}
		if exists {
			return nil, fmt.Errorf("disabled SMTP must not mount MAILER_SMTP_PASSWORD")
		}
		for _, name := range []string{"GF_SMTP_PASSWORD", "GF_SMTP_PASSWORD__FILE", "GF_SMTP_HOST", "GF_SMTP_USER", "GF_SMTP_FROM_ADDRESS", "GF_SMTP_FROM_NAME", "GF_SMTP_STARTTLS_POLICY", "GF_SMTP_SKIP_VERIFY"} {
			os.Unsetenv(name)
		}
		return nil, setEnvironment("GF_SMTP_ENABLED", "false")
	}
	host := os.Getenv("GRAFANA_SMTP_HOST")
	portValue := os.Getenv("GRAFANA_SMTP_PORT")
	user := os.Getenv("GRAFANA_SMTP_USER")
	from := os.Getenv("GRAFANA_SMTP_FROM")
	fromName := os.Getenv("GRAFANA_SMTP_FROM_NAME")
	tlsMode := os.Getenv("GRAFANA_SMTP_TLS_MODE")
	if err := validateHostname("GRAFANA_SMTP_HOST", host); err != nil {
		return nil, err
	}
	port, err := strconv.Atoi(portValue)
	if err != nil || port < 1 || port > 65535 {
		return nil, fmt.Errorf("GRAFANA_SMTP_PORT must be a valid TCP port")
	}
	if err := validateDisplayValue("GRAFANA_SMTP_USER", user); err != nil {
		return nil, err
	}
	address, err := mail.ParseAddress(from)
	if err != nil || address.Address != from {
		return nil, fmt.Errorf("GRAFANA_SMTP_FROM must be a plain email address")
	}
	if err := validateDisplayValue("GRAFANA_SMTP_FROM_NAME", fromName); err != nil {
		return nil, err
	}
	startTLSPolicy := ""
	switch tlsMode {
	case "implicit":
		if port != 465 {
			return nil, fmt.Errorf("implicit SMTP TLS requires port 465")
		}
	case "starttls":
		if port != 587 {
			return nil, fmt.Errorf("mandatory SMTP STARTTLS requires port 587")
		}
		startTLSPolicy = "MandatoryStartTLS"
	default:
		return nil, fmt.Errorf("GRAFANA_SMTP_TLS_MODE must be implicit or starttls")
	}
	if err := setEnvironments(map[string]string{
		"GF_SMTP_ENABLED":         "true",
		"GF_SMTP_HOST":            net.JoinHostPort(host, portValue),
		"GF_SMTP_USER":            user,
		"GF_SMTP_PASSWORD":        "$__file{" + runtimeSecretDirectory + "/MAILER_SMTP_PASSWORD}",
		"GF_SMTP_FROM_ADDRESS":    from,
		"GF_SMTP_FROM_NAME":       fromName,
		"GF_SMTP_STARTTLS_POLICY": startTLSPolicy,
		"GF_SMTP_SKIP_VERIFY":     "false",
	}); err != nil {
		return nil, err
	}
	return []string{"MAILER_SMTP_PASSWORD"}, nil
}

func configureApplication(secretDirectory, runtimeSecretDirectory string) (map[string][]byte, error) {
	if err := rejectProtectedEnvironment(
		"GF_DATABASE_PASSWORD", "GF_DATABASE_PASSWORD__FILE",
		"GF_SECURITY_SECRET_KEY", "GF_SECURITY_SECRET_KEY__FILE",
		"GF_SECURITY_ADMIN_PASSWORD", "GF_SECURITY_ADMIN_PASSWORD__FILE",
		"GF_AUTH_GENERIC_OAUTH_CLIENT_ID", "GF_AUTH_GENERIC_OAUTH_CLIENT_ID__FILE",
		"GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET", "GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET__FILE",
		"GF_SMTP_PASSWORD", "GF_SMTP_PASSWORD__FILE",
	); err != nil {
		return nil, err
	}
	adminSecretMounted, err := secretExists(secretDirectory, "GRAFANA_ADMIN_PASSWORD")
	if err != nil {
		return nil, err
	}
	if adminSecretMounted {
		return nil, fmt.Errorf("final Grafana service must not mount GRAFANA_ADMIN_PASSWORD")
	}
	if _, err := parseStrictBoolean("GRAFANA_DISABLE_LOGIN_FORM", true); err != nil {
		return nil, err
	}
	autoLogin, err := parseStrictBoolean("GRAFANA_OAUTH_AUTO_LOGIN", false)
	if err != nil {
		return nil, err
	}
	if err := setEnvironment("GRAFANA_OAUTH_AUTO_LOGIN", strconv.FormatBool(autoLogin)); err != nil {
		return nil, err
	}
	smtpSecrets, err := configureSMTP(secretDirectory, runtimeSecretDirectory)
	if err != nil {
		return nil, err
	}
	names := append([]string{"POSTGRES_PASSWORD", "GRAFANA_SECRET_KEY", "GRAFANA_OIDC_CLIENT_ID", "GRAFANA_OIDC_CLIENT_SECRET"}, smtpSecrets...)
	values, err := loadAndStageSecrets(secretDirectory, runtimeSecretDirectory, names)
	if err != nil {
		return nil, err
	}
	if err := configureOIDC(runtimeSecretDirectory); err != nil {
		for _, value := range values {
			wipe(value)
		}
		return nil, err
	}
	disableLoginForm, _ := parseStrictBoolean("GRAFANA_DISABLE_LOGIN_FORM", true)
	if err := setEnvironments(map[string]string{
		"GF_DATABASE_PASSWORD":                       "$__file{" + runtimeSecretDirectory + "/POSTGRES_PASSWORD}",
		"GF_SECURITY_SECRET_KEY":                     "$__file{" + runtimeSecretDirectory + "/GRAFANA_SECRET_KEY}",
		"GF_SECURITY_DISABLE_INITIAL_ADMIN_CREATION": "true",
		"GF_AUTH_DISABLE_LOGIN_FORM":                 strconv.FormatBool(disableLoginForm),
		"GF_AUTH_BASIC_ENABLED":                      "false",
		"GF_AUTH_ANONYMOUS_ENABLED":                  "false",
		"GF_AUTH_PROXY_ENABLED":                      "false",
		"GF_AUTH_LDAP_ENABLED":                       "false",
		"GF_AUTH_JWT_ENABLED":                        "false",
		"GF_AUTH_SAML_ENABLED":                       "false",
		"GF_AUTH_GITHUB_ENABLED":                     "false",
		"GF_AUTH_GITLAB_ENABLED":                     "false",
		"GF_AUTH_GOOGLE_ENABLED":                     "false",
		"GF_AUTH_AZUREAD_ENABLED":                    "false",
		"GF_AUTH_OKTA_ENABLED":                       "false",
		"GF_AUTH_GRAFANA_COM_ENABLED":                "false",
		"GF_ANALYTICS_REPORTING_ENABLED":             "false",
		"GF_ANALYTICS_CHECK_FOR_UPDATES":             "false",
		"GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES":      "false",
		"GF_SNAPSHOTS_EXTERNAL_ENABLED":              "false",
		"GF_NEWS_NEWS_FEED_ENABLED":                  "false",
	}); err != nil {
		for _, value := range values {
			wipe(value)
		}
		return nil, err
	}
	return values, nil
}

func validateAdminResetArguments(arguments []string) error {
	if len(arguments) < 3 || arguments[0] != "admin" || arguments[1] != "reset-admin-password" {
		return fmt.Errorf("grafana-cli permits only admin reset-admin-password")
	}
	foundPasswordFromStdin := false
	foundUserID := false
	for index := 2; index < len(arguments); index++ {
		switch arguments[index] {
		case "--password-from-stdin":
			if foundPasswordFromStdin {
				return fmt.Errorf("--password-from-stdin must occur exactly once")
			}
			foundPasswordFromStdin = true
		case "--user-id":
			if foundUserID {
				return fmt.Errorf("--user-id must occur exactly once")
			}
			foundUserID = true
			if index+1 >= len(arguments) {
				return fmt.Errorf("--user-id requires a positive numeric value")
			}
			index++
			userID, err := strconv.ParseUint(arguments[index], 10, 31)
			if err != nil || userID == 0 {
				return fmt.Errorf("--user-id requires a positive numeric value")
			}
		default:
			return fmt.Errorf("grafana-cli rejects positional passwords and unsupported options")
		}
	}
	if !foundPasswordFromStdin {
		return fmt.Errorf("--password-from-stdin is required")
	}
	if !foundUserID {
		return fmt.Errorf("--user-id is required")
	}
	return nil
}

func configureGrafanaCLI(secretDirectory string) error {
	if err := rejectProtectedEnvironment(
		"GF_DATABASE_PASSWORD", "GF_DATABASE_PASSWORD__FILE",
		"GF_SECURITY_SECRET_KEY", "GF_SECURITY_SECRET_KEY__FILE",
		"GF_SECURITY_ADMIN_PASSWORD", "GF_SECURITY_ADMIN_PASSWORD__FILE",
	); err != nil {
		return err
	}
	if os.Getenv("GF_DATABASE_TYPE") != "postgres" {
		return fmt.Errorf("grafana-cli requires the configured PostgreSQL database")
	}
	for _, name := range []string{"GF_DATABASE_HOST", "GF_DATABASE_NAME", "GF_DATABASE_USER"} {
		if err := validateDisplayValue(name, os.Getenv(name)); err != nil {
			return err
		}
	}
	adminSecretMounted, err := secretExists(secretDirectory, "GRAFANA_ADMIN_PASSWORD")
	if err != nil {
		return err
	}
	if adminSecretMounted {
		return fmt.Errorf("final Grafana service must not mount GRAFANA_ADMIN_PASSWORD")
	}
	for _, name := range []string{"POSTGRES_PASSWORD", "GRAFANA_SECRET_KEY"} {
		value, err := readSecret(secretDirectory, name)
		if err != nil {
			return err
		}
		wipe(value)
	}
	return setEnvironments(map[string]string{
		"GF_DATABASE_PASSWORD":   "$__file{" + secretDirectory + "/POSTGRES_PASSWORD}",
		"GF_SECURITY_SECRET_KEY": "$__file{" + secretDirectory + "/GRAFANA_SECRET_KEY}",
	})
}

func runGrafanaCLI(arguments []string) error {
	if err := validateAdminResetArguments(arguments); err != nil {
		return err
	}
	if err := configureGrafanaCLI(defaultSecretDirectory); err != nil {
		return err
	}
	info, err := os.Stat(defaultGrafanaBinary)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0o111 == 0 {
		return fmt.Errorf("Grafana CLI binary is missing or not executable")
	}
	command := []string{
		defaultGrafanaBinary,
		"cli",
		"--homepath", defaultGrafanaHome,
		"--config", defaultGrafanaConfig,
	}
	command = append(command, arguments...)
	return syscall.Exec(defaultGrafanaBinary, command, os.Environ())
}

func parsePositiveSeconds(name string, defaultValue int) (time.Duration, error) {
	value := os.Getenv(name)
	if value == "" {
		return time.Duration(defaultValue) * time.Second, nil
	}
	seconds, err := strconv.Atoi(value)
	if err != nil || seconds < 1 || seconds > 7200 {
		return 0, fmt.Errorf("%s must be between 1 and 7200 seconds", name)
	}
	return time.Duration(seconds) * time.Second, nil
}

func parseBootstrapStopTimeout() (time.Duration, error) {
	timeout, err := parsePositiveSeconds("GRAFANA_BOOTSTRAP_STOP_TIMEOUT_SECONDS", 30)
	if err != nil {
		return 0, err
	}
	if timeout > 60*time.Second {
		return 0, fmt.Errorf("GRAFANA_BOOTSTRAP_STOP_TIMEOUT_SECONDS must not exceed 60 seconds")
	}
	return timeout, nil
}

func validateAdminUser(user string) error {
	if err := validateToken("GRAFANA_ADMIN_USER", user); err != nil {
		return err
	}
	if strings.ContainsRune(user, ':') {
		return fmt.Errorf("GRAFANA_ADMIN_USER must not contain a colon")
	}
	return nil
}

func readBootstrapMarker(stateDirectory string) error {
	directoryFD, err := openDirectory(stateDirectory)
	if err != nil {
		return err
	}
	defer syscall.Close(directoryFD)
	value, err := readBoundedRegularAt(directoryFD, bootstrapMarkerName, 128)
	if err != nil {
		fd, openErr := syscall.Openat(directoryFD, bootstrapMarkerName, syscall.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
		if errors.Is(openErr, syscall.ENOENT) {
			return errMarkerMissing
		}
		if openErr == nil {
			syscall.Close(fd)
		}
		return fmt.Errorf("bootstrap marker is invalid")
	}
	defer wipe(value)
	if string(value) != bootstrapMarkerContent {
		return fmt.Errorf("bootstrap marker has unexpected content")
	}
	return nil
}

func bootstrapInterruptError(interrupted <-chan os.Signal) error {
	if interrupted == nil {
		return nil
	}
	select {
	case signalValue := <-interrupted:
		signalNumber, ok := signalValue.(syscall.Signal)
		if !ok {
			return &exitCodeError{code: 1, err: fmt.Errorf("bootstrap interrupted by an unsupported signal")}
		}
		return &exitCodeError{code: 128 + int(signalNumber), err: fmt.Errorf("bootstrap interrupted")}
	default:
		return nil
	}
}

func bootstrapMarkerMatchesIdentity(directoryFD int, device, inode uint64) (bool, error) {
	fd, err := syscall.Openat(directoryFD, bootstrapMarkerName, syscall.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if errors.Is(err, syscall.ENOENT) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("cannot inspect uncommitted bootstrap marker")
	}
	defer syscall.Close(fd)
	var stat syscall.Stat_t
	if err := syscall.Fstat(fd, &stat); err != nil {
		return false, fmt.Errorf("cannot identify uncommitted bootstrap marker")
	}
	if stat.Mode&syscall.S_IFMT != syscall.S_IFREG || uint64(stat.Dev) != device || stat.Ino != inode {
		return false, fmt.Errorf("uncommitted bootstrap marker identity changed; refusing removal")
	}
	return true, nil
}

func linkAtNoReplace(directoryFD int, oldName, newName string) error {
	oldPointer, err := syscall.BytePtrFromString(oldName)
	if err != nil {
		return err
	}
	newPointer, err := syscall.BytePtrFromString(newName)
	if err != nil {
		return err
	}
	_, _, errno := syscall.Syscall6(
		syscall.SYS_LINKAT,
		uintptr(directoryFD),
		uintptr(unsafe.Pointer(oldPointer)),
		uintptr(directoryFD),
		uintptr(unsafe.Pointer(newPointer)),
		0,
		0,
	)
	if errno != 0 {
		return errno
	}
	return nil
}

func writeBootstrapMarker(stateDirectory string, interruptChannels ...<-chan os.Signal) error {
	if len(interruptChannels) > 1 {
		return fmt.Errorf("bootstrap marker accepts at most one interrupt channel")
	}
	var interrupted <-chan os.Signal
	if len(interruptChannels) == 1 {
		interrupted = interruptChannels[0]
	}
	return writeBootstrapMarkerWithHook(stateDirectory, interrupted, nil)
}

func writeBootstrapMarkerWithHook(stateDirectory string, interrupted <-chan os.Signal, beforeDirectorySync func()) (returnError error) {
	if err := bootstrapInterruptError(interrupted); err != nil {
		return err
	}
	directoryFD, err := openDirectory(stateDirectory)
	if err != nil {
		return err
	}
	defer syscall.Close(directoryFD)
	var temporaryName string
	var fd int
	for attempt := 0; attempt < 4; attempt++ {
		randomSuffix := make([]byte, 16)
		if _, err := io.ReadFull(cryptorand.Reader, randomSuffix); err != nil {
			return fmt.Errorf("cannot create unique bootstrap marker name")
		}
		temporaryName = bootstrapMarkerName + ".pending-" + hex.EncodeToString(randomSuffix)
		fd, err = syscall.Openat(directoryFD, temporaryName, syscall.O_WRONLY|syscall.O_CREAT|syscall.O_EXCL|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0o600)
		wipe(randomSuffix)
		if err == nil {
			break
		}
		if !errors.Is(err, syscall.EEXIST) {
			return fmt.Errorf("cannot stage bootstrap marker")
		}
	}
	if fd < 0 || err != nil {
		return fmt.Errorf("cannot stage uniquely named bootstrap marker")
	}
	var stagedStat syscall.Stat_t
	if err := syscall.Fstat(fd, &stagedStat); err != nil {
		syscall.Close(fd)
		return fmt.Errorf("cannot inspect staged bootstrap marker")
	}
	stagedDevice := uint64(stagedStat.Dev)
	stagedInode := stagedStat.Ino
	published := false
	committed := false
	defer func() {
		if committed {
			return
		}
		appendCleanupError := func(message string) {
			if returnError == nil {
				returnError = errors.New(message)
			} else {
				returnError = fmt.Errorf("%w; %s", returnError, message)
			}
		}
		if published && !committed {
			matches, identityError := bootstrapMarkerMatchesIdentity(directoryFD, stagedDevice, stagedInode)
			if identityError != nil {
				appendCleanupError(identityError.Error())
			} else if matches {
				if cleanupError := syscall.Unlinkat(directoryFD, bootstrapMarkerName); cleanupError != nil && !errors.Is(cleanupError, syscall.ENOENT) {
					appendCleanupError("cannot revoke uncommitted bootstrap marker")
				}
			}
		}
		if cleanupError := syscall.Unlinkat(directoryFD, temporaryName); cleanupError != nil && !errors.Is(cleanupError, syscall.ENOENT) {
			appendCleanupError("cannot retire uncommitted bootstrap marker staging name")
		}
		if cleanupError := syscall.Fsync(directoryFD); cleanupError != nil {
			appendCleanupError("cannot sync bootstrap marker cleanup")
		}
	}()
	file := os.NewFile(uintptr(fd), temporaryName)
	if file == nil {
		syscall.Close(fd)
		return fmt.Errorf("cannot bind bootstrap marker descriptor")
	}
	if _, err := io.WriteString(file, bootstrapMarkerContent); err != nil {
		file.Close()
		return fmt.Errorf("cannot write bootstrap marker")
	}
	if err := file.Sync(); err != nil {
		file.Close()
		return fmt.Errorf("cannot sync bootstrap marker")
	}
	if err := file.Close(); err != nil {
		return fmt.Errorf("cannot close bootstrap marker")
	}
	if err := bootstrapInterruptError(interrupted); err != nil {
		return err
	}
	if err := linkAtNoReplace(directoryFD, temporaryName, bootstrapMarkerName); err != nil {
		if errors.Is(err, os.ErrExist) {
			return fmt.Errorf("bootstrap marker already exists; refusing replacement")
		}
		return fmt.Errorf("cannot publish bootstrap marker atomically without replacement")
	}
	published = true
	if err := syscall.Unlinkat(directoryFD, temporaryName); err != nil {
		return fmt.Errorf("cannot retire staged bootstrap marker name")
	}
	if beforeDirectorySync != nil {
		beforeDirectorySync()
	}
	if err := syscall.Fsync(directoryFD); err != nil {
		return fmt.Errorf("cannot sync bootstrap marker directory")
	}
	if err := bootstrapInterruptError(interrupted); err != nil {
		return err
	}
	committed = true
	return nil
}

func vendorEnvironment(runtimeSecretDirectory string, includeAdminPassword bool) ([]string, error) {
	adminUser := os.Getenv("GRAFANA_ADMIN_USER")
	if adminUser == "" {
		adminUser = "admin"
	}
	values := map[string]string{
		"GF_DATABASE_PASSWORD":                       "$__file{" + runtimeSecretDirectory + "/POSTGRES_PASSWORD}",
		"GF_SECURITY_SECRET_KEY":                     "$__file{" + runtimeSecretDirectory + "/GRAFANA_SECRET_KEY}",
		"GF_SECURITY_DISABLE_INITIAL_ADMIN_CREATION": strconv.FormatBool(!includeAdminPassword),
		"GF_SECURITY_ADMIN_USER":                     adminUser,
		"GF_SERVER_HTTP_ADDR":                        "127.0.0.1",
		"GF_SERVER_HTTP_PORT":                        "3000",
		"GF_SERVER_ROOT_URL":                         "http://127.0.0.1:3000/",
		"GF_AUTH_DISABLE_LOGIN_FORM":                 "false",
		"GF_AUTH_BASIC_ENABLED":                      "true",
		"GF_AUTH_ANONYMOUS_ENABLED":                  "false",
		"GF_AUTH_GENERIC_OAUTH_ENABLED":              "false",
		"GF_AUTH_PROXY_ENABLED":                      "false",
		"GF_AUTH_LDAP_ENABLED":                       "false",
		"GF_AUTH_JWT_ENABLED":                        "false",
		"GF_AUTH_SAML_ENABLED":                       "false",
		"GF_AUTH_GITHUB_ENABLED":                     "false",
		"GF_AUTH_GITLAB_ENABLED":                     "false",
		"GF_AUTH_GOOGLE_ENABLED":                     "false",
		"GF_AUTH_AZUREAD_ENABLED":                    "false",
		"GF_AUTH_OKTA_ENABLED":                       "false",
		"GF_AUTH_GRAFANA_COM_ENABLED":                "false",
		"GF_SMTP_ENABLED":                            "false",
		"GF_ANALYTICS_REPORTING_ENABLED":             "false",
		"GF_ANALYTICS_CHECK_FOR_UPDATES":             "false",
		"GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES":      "false",
		"GF_PATHS_PLUGINS":                           defaultBootstrapPluginDir,
	}
	if includeAdminPassword {
		values["GF_SECURITY_ADMIN_PASSWORD"] = "$__file{" + runtimeSecretDirectory + "/GRAFANA_ADMIN_PASSWORD}"
	}
	environment := os.Environ()
	protectedPrefixes := []string{
		"GF_DATABASE_PASSWORD=", "GF_DATABASE_PASSWORD__FILE=",
		"GF_SECURITY_SECRET_KEY=", "GF_SECURITY_SECRET_KEY__FILE=",
		"GF_SECURITY_ADMIN_PASSWORD=", "GF_SECURITY_ADMIN_PASSWORD__FILE=",
	}
	for name := range values {
		protectedPrefixes = append(protectedPrefixes, name+"=")
	}
	filtered := environment[:0]
	for _, item := range environment {
		protected := false
		for _, prefix := range protectedPrefixes {
			if strings.HasPrefix(item, prefix) {
				protected = true
				break
			}
		}
		if !protected {
			filtered = append(filtered, item)
		}
	}
	for name, value := range values {
		filtered = append(filtered, name+"="+value)
	}
	return filtered, nil
}

func checkAdminAPI(client *http.Client, user string, password []byte) error {
	request, err := http.NewRequest(http.MethodGet, "http://127.0.0.1:3000/api/admin/settings", nil)
	if err != nil {
		return err
	}
	credentials := base64.StdEncoding.EncodeToString(append(append([]byte(user), ':'), password...))
	request.Header.Set("Authorization", "Basic "+credentials)
	response, err := client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("authenticated admin verification returned HTTP %d", response.StatusCode)
	}
	return nil
}

func waitForBootstrapReady(done <-chan error, interrupted <-chan os.Signal, user string, password []byte, timeout time.Duration) error {
	client := &http.Client{
		Timeout: 5 * time.Second,
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case signalValue := <-interrupted:
			return &exitCodeError{code: 128 + int(signalValue.(syscall.Signal)), err: fmt.Errorf("bootstrap interrupted")}
		case <-done:
			return errBootstrapChildExited
		case <-timer.C:
			return fmt.Errorf("Grafana bootstrap verification timed out")
		case <-ticker.C:
			if err := checkAdminAPI(client, user, password); err == nil {
				return nil
			}
		}
	}
}

func processGroupExists(processGroup int) (bool, error) {
	err := syscall.Kill(processGroup, 0)
	if err == nil || errors.Is(err, syscall.EPERM) {
		return true, nil
	}
	if errors.Is(err, syscall.ESRCH) {
		return false, nil
	}
	return false, err
}

func waitForProcessGroupExit(processGroup int, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		exists, err := processGroupExists(processGroup)
		if err != nil {
			return fmt.Errorf("cannot inspect Grafana bootstrap process group")
		}
		if !exists {
			return nil
		}
		time.Sleep(100 * time.Millisecond)
	}
	return fmt.Errorf("Grafana bootstrap process group did not stop")
}

func stopChild(command *exec.Cmd, done <-chan error, signalValue syscall.Signal, timeout time.Duration) error {
	if command.Process == nil {
		return nil
	}
	processGroup := -command.Process.Pid
	_ = syscall.Kill(processGroup, signalValue)
	leaderExited := false
	select {
	case <-done:
		leaderExited = true
	case <-time.After(timeout):
	}
	if err := waitForProcessGroupExit(processGroup, 500*time.Millisecond); err == nil {
		return nil
	}
	_ = syscall.Kill(processGroup, syscall.SIGKILL)
	if !leaderExited {
		select {
		case <-done:
		case <-time.After(10 * time.Second):
			return fmt.Errorf("Grafana bootstrap child leader was not reaped")
		}
	}
	return waitForProcessGroupExit(processGroup, 10*time.Second)
}

func startBootstrapChild(environment []string) (*exec.Cmd, <-chan error, error) {
	vendorEntrypoint := os.Getenv("GRAFANA_VENDOR_ENTRYPOINT")
	if vendorEntrypoint == "" {
		vendorEntrypoint = defaultVendorEntrypoint
	}
	info, err := os.Stat(vendorEntrypoint)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0o111 == 0 {
		return nil, nil, fmt.Errorf("vendor Grafana entrypoint is missing or not executable")
	}
	command := exec.Command(vendorEntrypoint)
	command.Env = environment
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	command.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := command.Start(); err != nil {
		return nil, nil, fmt.Errorf("cannot start vendor Grafana entrypoint")
	}
	done := make(chan error, 1)
	go func() {
		done <- command.Wait()
	}()
	return command, done, nil
}

func runVerifiedBootstrapChild(runtimeSecretDirectory, user string, password []byte, includeAdminPassword bool, readyTimeout, stopTimeout time.Duration, interrupted <-chan os.Signal) error {
	environment, err := vendorEnvironment(runtimeSecretDirectory, includeAdminPassword)
	if err != nil {
		return err
	}
	command, done, err := startBootstrapChild(environment)
	if err != nil {
		return err
	}
	verificationError := waitForBootstrapReady(done, interrupted, user, password, readyTimeout)
	var coded *exitCodeError
	if errors.As(verificationError, &coded) {
		_ = stopChild(command, done, syscall.Signal(coded.code-128), stopTimeout)
		return coded
	}
	if errors.Is(verificationError, errBootstrapChildExited) {
		processGroup := -command.Process.Pid
		_ = syscall.Kill(processGroup, syscall.SIGKILL)
		_ = waitForProcessGroupExit(processGroup, 10*time.Second)
		return verificationError
	}
	stopError := stopChild(command, done, syscall.SIGTERM, stopTimeout)
	if verificationError != nil {
		return verificationError
	}
	if interruptError := bootstrapInterruptError(interrupted); interruptError != nil {
		return interruptError
	}
	return stopError
}

func runBootstrap() error {
	stateDirectory := os.Getenv("GRAFANA_BOOTSTRAP_STATE_DIR")
	if stateDirectory == "" {
		stateDirectory = defaultBootstrapStateDir
	}
	markerError := readBootstrapMarker(stateDirectory)
	if markerError == nil {
		fmt.Fprintln(os.Stdout, "[grafana-bootstrap] Existing verified bootstrap marker; credential phase skipped.")
		return nil
	}
	if !errors.Is(markerError, errMarkerMissing) {
		return markerError
	}
	if err := os.Mkdir(defaultBootstrapPluginDir, 0o700); err != nil && !errors.Is(err, os.ErrExist) {
		return fmt.Errorf("cannot create private bootstrap plugin directory")
	}
	secretDirectory := defaultSecretDirectory
	runtimeSecretDirectory := defaultRuntimeSecretDir
	if err := rejectProtectedEnvironment(
		"GF_DATABASE_PASSWORD", "GF_DATABASE_PASSWORD__FILE",
		"GF_SECURITY_SECRET_KEY", "GF_SECURITY_SECRET_KEY__FILE",
		"GF_SECURITY_ADMIN_PASSWORD", "GF_SECURITY_ADMIN_PASSWORD__FILE",
	); err != nil {
		return err
	}
	for _, forbiddenSecret := range []string{"GRAFANA_OIDC_CLIENT_ID", "GRAFANA_OIDC_CLIENT_SECRET", "MAILER_SMTP_PASSWORD"} {
		exists, err := secretExists(secretDirectory, forbiddenSecret)
		if err != nil {
			return err
		}
		if exists {
			return fmt.Errorf("bootstrap service must not mount %s", forbiddenSecret)
		}
	}
	values, err := loadAndStageSecrets(secretDirectory, runtimeSecretDirectory, []string{"POSTGRES_PASSWORD", "GRAFANA_SECRET_KEY", "GRAFANA_ADMIN_PASSWORD"})
	if err != nil {
		return err
	}
	defer func() {
		for _, value := range values {
			wipe(value)
		}
	}()
	adminUser := os.Getenv("GRAFANA_ADMIN_USER")
	if adminUser == "" {
		adminUser = "admin"
	}
	if err := validateAdminUser(adminUser); err != nil {
		return err
	}
	readyTimeout, err := parsePositiveSeconds("GRAFANA_BOOTSTRAP_READY_TIMEOUT_SECONDS", 300)
	if err != nil {
		return err
	}
	stopTimeout, err := parseBootstrapStopTimeout()
	if err != nil {
		return err
	}
	interrupted := make(chan os.Signal, 1)
	signal.Notify(interrupted, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(interrupted)
	if err := runVerifiedBootstrapChild(runtimeSecretDirectory, adminUser, values["GRAFANA_ADMIN_PASSWORD"], true, readyTimeout, stopTimeout, interrupted); err != nil {
		return err
	}
	if err := runVerifiedBootstrapChild(runtimeSecretDirectory, adminUser, values["GRAFANA_ADMIN_PASSWORD"], false, readyTimeout, stopTimeout, interrupted); err != nil {
		return fmt.Errorf("persisted admin verification failed: %w", err)
	}
	if err := writeBootstrapMarker(stateDirectory, interrupted); err != nil {
		return err
	}
	fmt.Fprintln(os.Stdout, "[grafana-bootstrap] Local recovery administrator initialized and persistence verified.")
	return nil
}

func checkHealthURL(url string) error {
	client := &http.Client{
		Timeout: 4 * time.Second,
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}
	response, err := client.Get(url)
	if err != nil {
		return fmt.Errorf("Grafana health request failed")
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("Grafana health returned HTTP %d", response.StatusCode)
	}
	var payload struct {
		Database string `json:"database"`
	}
	decoder := json.NewDecoder(io.LimitReader(response.Body, 8192))
	if err := decoder.Decode(&payload); err != nil || payload.Database != "ok" {
		return fmt.Errorf("Grafana database health is not ok")
	}
	return nil
}

func runHealthcheck() error {
	return checkHealthURL("http://127.0.0.1:3000/api/health")
}

func runApplication(arguments []string, preflightOnly bool) error {
	values, err := configureApplication(defaultSecretDirectory, defaultRuntimeSecretDir)
	if err != nil {
		return err
	}
	for _, value := range values {
		wipe(value)
	}
	if preflightOnly {
		return nil
	}
	vendorEntrypoint := os.Getenv("GRAFANA_VENDOR_ENTRYPOINT")
	if vendorEntrypoint == "" {
		vendorEntrypoint = defaultVendorEntrypoint
	}
	info, err := os.Stat(vendorEntrypoint)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0o111 == 0 {
		return fmt.Errorf("vendor Grafana entrypoint is missing or not executable")
	}
	return syscall.Exec(vendorEntrypoint, append([]string{vendorEntrypoint}, arguments...), os.Environ())
}

func main() {
	var err error
	arguments := os.Args[1:]
	if len(arguments) > 0 {
		switch arguments[0] {
		case "bootstrap":
			err = runBootstrap()
		case "health":
			err = runHealthcheck()
		case "preflight":
			err = runApplication(nil, true)
		case "grafana-cli":
			err = runGrafanaCLI(arguments[1:])
		default:
			err = runApplication(arguments, false)
		}
	} else {
		err = runApplication(nil, false)
	}
	if err == nil {
		return
	}
	fmt.Fprintf(os.Stderr, "[grafana-entrypoint] ERROR: %s\n", err)
	var coded *exitCodeError
	if errors.As(err, &coded) {
		os.Exit(coded.code)
	}
	os.Exit(1)
}
