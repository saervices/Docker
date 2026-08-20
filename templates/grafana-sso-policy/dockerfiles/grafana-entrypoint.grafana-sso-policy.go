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
	defaultSecretDirectory                = "/run/secrets"
	defaultRuntimeSecretDir               = "/run/grafana-secrets"
	defaultBootstrapStateDir              = "/var/lib/grafana-bootstrap-state"
	defaultBootstrapPluginDir             = "/run/grafana-bootstrap-plugins"
	defaultReviewedPluginDirectory        = "/usr/share/grafana/plugins-reviewed"
	defaultPSQLBinary                     = "/usr/lib/postgresql/18/bin/psql"
	defaultSSOPolicyRuntimeDir            = "/run/grafana-sso-policy"
	defaultVendorEntrypoint               = "/run.sh"
	defaultGrafanaBinary                  = "/usr/share/grafana/bin/grafana"
	defaultGrafanaHome                    = "/usr/share/grafana"
	defaultGrafanaConfig                  = "/etc/grafana/grafana.ini"
	bootstrapMarkerName                   = "bootstrap-v1.complete"
	bootstrapMarkerContent                = "grafana-bootstrap-v1"
	ssoConfigurationLockProvider          = "saervices_policy_locked"
	defaultLoginMaximumLifetime           = "8h"
	defaultLoginInactiveLifetime          = "1h"
	defaultTokenRotationMinutes           = 5
	defaultServiceAccountExpiryDays       = 90
	maximumSecretBytes              int64 = 4096
	maximumPolicyOutputBytes              = 16384
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

type ssoPolicyRuntime struct {
	psqlBinary       string
	secretDirectory  string
	runtimeDirectory string
	output           io.Writer
	interrupted      <-chan os.Signal
}

type boundedCommandOutput struct {
	buffer    bytes.Buffer
	maximum   int
	truncated bool
}

func (output *boundedCommandOutput) Write(value []byte) (int, error) {
	originalLength := len(value)
	remaining := output.maximum - output.buffer.Len()
	if remaining <= 0 {
		output.truncated = true
		return originalLength, nil
	}
	if len(value) > remaining {
		value = value[:remaining]
		output.truncated = true
	}
	_, _ = output.buffer.Write(value)
	return originalLength, nil
}

func (output *boundedCommandOutput) String() string {
	return output.buffer.String()
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

func rejectUnexpectedEnvironmentValue(name string, allowedValues ...string) error {
	value, exists := os.LookupEnv(name)
	if !exists {
		return nil
	}
	for _, allowedValue := range allowedValues {
		if value == allowedValue {
			return nil
		}
	}
	return fmt.Errorf("environment variable %s contains an unsupported value", name)
}

func rejectDirectSecretEnvironment() error {
	return rejectProtectedEnvironment(
		"GF_DATABASE_PASSWORD", "GF_DATABASE_PASSWORD_FILE", "GF_DATABASE_PASSWORD__FILE",
		"GF_SECURITY_SECRET_KEY", "GF_SECURITY_SECRET_KEY_FILE", "GF_SECURITY_SECRET_KEY__FILE",
		"GF_SECURITY_ADMIN_PASSWORD", "GF_SECURITY_ADMIN_PASSWORD_FILE", "GF_SECURITY_ADMIN_PASSWORD__FILE",
		"GF_AUTH_GENERIC_OAUTH_CLIENT_ID", "GF_AUTH_GENERIC_OAUTH_CLIENT_ID_FILE", "GF_AUTH_GENERIC_OAUTH_CLIENT_ID__FILE",
		"GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET", "GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET_FILE", "GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET__FILE",
		"GF_SMTP_PASSWORD", "GF_SMTP_PASSWORD_FILE", "GF_SMTP_PASSWORD__FILE",
		"POSTGRES_PASSWORD", "POSTGRES_PASSWORD_FILE", "POSTGRES_PASSWORD__FILE",
		"GRAFANA_SECRET_KEY", "GRAFANA_SECRET_KEY_FILE", "GRAFANA_SECRET_KEY__FILE",
		"GRAFANA_ADMIN_PASSWORD", "GRAFANA_ADMIN_PASSWORD_FILE", "GRAFANA_ADMIN_PASSWORD__FILE",
		"GRAFANA_OIDC_CLIENT_ID", "GRAFANA_OIDC_CLIENT_ID_FILE", "GRAFANA_OIDC_CLIENT_ID__FILE",
		"GRAFANA_OIDC_CLIENT_SECRET", "GRAFANA_OIDC_CLIENT_SECRET_FILE", "GRAFANA_OIDC_CLIENT_SECRET__FILE",
		"MAILER_SMTP_PASSWORD", "MAILER_SMTP_PASSWORD_FILE", "MAILER_SMTP_PASSWORD__FILE",
		"GRAFANA_API_KEY", "GRAFANA_API_TOKEN",
		"PGHOST", "PGHOSTADDR", "PGPORT", "PGDATABASE", "PGUSER",
		"PGPASSWORD", "PGPASSFILE", "PGSERVICE", "PGSERVICEFILE",
		"PGOPTIONS", "PGAPPNAME", "PGCONNECT_TIMEOUT", "PGCLIENTENCODING",
		"PGSSLMODE", "PGREQUIRESSL", "PGSSLNEGOTIATION", "PGSSLCOMPRESSION",
		"PGSSLCERT", "PGSSLKEY", "PGSSLROOTCERT", "PGSSLCRL", "PGSSLCRLDIR",
		"PGREQUIREPEER", "PGCHANNELBINDING", "PGGSSENCMODE", "PGKRBSRVNAME",
		"PGGSSLIB", "PGTARGETSESSIONATTRS", "PGLOADBALANCEHOSTS", "PGREQUIREAUTH",
	)
}

func configurePluginPolicy() error {
	if err := rejectUnexpectedEnvironmentValue(
		"GF_PATHS_PLUGINS",
		"/var/lib/grafana/plugins",
		defaultReviewedPluginDirectory,
	); err != nil {
		return err
	}
	for _, name := range []string{
		"GF_INSTALL_PLUGINS",
		"GF_INSTALL_IMAGE_RENDERER_PLUGIN",
		"GF_PLUGINS_PREINSTALL",
		"GF_PLUGINS_PREINSTALL_SYNC",
	} {
		if value, exists := os.LookupEnv(name); exists && value != "" {
			return fmt.Errorf("plugin installation environment variable %s must not be supplied", name)
		}
		os.Unsetenv(name)
	}
	return setEnvironments(map[string]string{
		"GF_PATHS_PLUGINS":                  defaultReviewedPluginDirectory,
		"GF_PLUGINS_PLUGIN_ADMIN_ENABLED":   "false",
		"GF_PLUGINS_PREINSTALL_DISABLED":    "true",
		"GF_PLUGINS_PREINSTALL_AUTO_UPDATE": "false",
	})
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

func parseBoundedDuration(name, defaultValue string, minimum, maximum time.Duration) (string, time.Duration, error) {
	value := os.Getenv(name)
	if value == "" {
		value = defaultValue
	}
	duration, err := time.ParseDuration(value)
	if err != nil || duration < minimum || duration > maximum {
		return "", 0, fmt.Errorf("%s must be a duration between %s and %s", name, minimum, maximum)
	}
	return value, duration, nil
}

func parseBoundedInteger(name string, defaultValue, minimum, maximum int) (int, error) {
	value := os.Getenv(name)
	if value == "" {
		return defaultValue, nil
	}
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed < minimum || parsed > maximum {
		return 0, fmt.Errorf("%s must be between %d and %d", name, minimum, maximum)
	}
	return parsed, nil
}

func configureSessionAndTokenPolicy() error {
	maximumValue, maximumDuration, err := parseBoundedDuration(
		"GRAFANA_LOGIN_MAXIMUM_LIFETIME_DURATION",
		defaultLoginMaximumLifetime,
		5*time.Minute,
		24*time.Hour,
	)
	if err != nil {
		return err
	}
	inactiveValue, inactiveDuration, err := parseBoundedDuration(
		"GRAFANA_LOGIN_MAXIMUM_INACTIVE_LIFETIME_DURATION",
		defaultLoginInactiveLifetime,
		5*time.Minute,
		24*time.Hour,
	)
	if err != nil {
		return err
	}
	if inactiveDuration > maximumDuration {
		return fmt.Errorf("GRAFANA_LOGIN_MAXIMUM_INACTIVE_LIFETIME_DURATION must not exceed GRAFANA_LOGIN_MAXIMUM_LIFETIME_DURATION")
	}
	rotationMinutes, err := parseBoundedInteger(
		"GRAFANA_TOKEN_ROTATION_INTERVAL_MINUTES",
		defaultTokenRotationMinutes,
		1,
		60,
	)
	if err != nil {
		return err
	}
	if time.Duration(rotationMinutes)*time.Minute > inactiveDuration {
		return fmt.Errorf("GRAFANA_TOKEN_ROTATION_INTERVAL_MINUTES must not exceed the inactive session lifetime")
	}
	expirationDays, err := parseBoundedInteger(
		"GRAFANA_SERVICE_ACCOUNT_TOKEN_EXPIRATION_DAYS",
		defaultServiceAccountExpiryDays,
		1,
		365,
	)
	if err != nil {
		return err
	}
	return setEnvironments(map[string]string{
		"GF_AUTH_LOGIN_MAXIMUM_LIFETIME_DURATION":          maximumValue,
		"GF_AUTH_LOGIN_MAXIMUM_INACTIVE_LIFETIME_DURATION": inactiveValue,
		"GF_AUTH_TOKEN_ROTATION_INTERVAL_MINUTES":          strconv.Itoa(rotationMinutes),
		"GF_SERVICE_ACCOUNTS_TOKEN_EXPIRATION_DAY_LIMIT":   strconv.Itoa(expirationDays),
		"GF_AUTH_API_KEY_MAX_SECONDS_TO_LIVE":              strconv.Itoa(expirationDays * 24 * 60 * 60),
	})
}

func validatePostgresIdentifier(name, value string) error {
	if value == "" || len(value) > 63 || value != strings.ToLower(value) {
		return fmt.Errorf("%s must be a lower-case PostgreSQL identifier", name)
	}
	for index, character := range value {
		letter := character >= 'a' && character <= 'z'
		digit := character >= '0' && character <= '9'
		if (index == 0 && !letter && character != '_') || (index > 0 && !letter && !digit && character != '_') {
			return fmt.Errorf("%s must be a lower-case PostgreSQL identifier", name)
		}
	}
	return nil
}

func parsePostgresEndpoint(value string) (string, string, error) {
	host, portValue, err := net.SplitHostPort(value)
	if err != nil || validateHostname("GF_DATABASE_HOST", host) != nil {
		return "", "", fmt.Errorf("GF_DATABASE_HOST must contain a lower-case DNS hostname and TCP port")
	}
	port, err := strconv.Atoi(portValue)
	if err != nil || port < 1 || port > 65535 || strconv.Itoa(port) != portValue {
		return "", "", fmt.Errorf("GF_DATABASE_HOST must contain a lower-case DNS hostname and TCP port")
	}
	return host, portValue, nil
}

func validateDatabaseEnvironmentPolicy() (map[string]string, error) {
	reviewed := map[string]bool{
		"GF_DATABASE_TYPE":                        true,
		"GF_DATABASE_HOST":                        true,
		"GF_DATABASE_NAME":                        true,
		"GF_DATABASE_USER":                        true,
		"GF_DATABASE_SSL_MODE":                    true,
		"GF_DATABASE_SKIP_MIGRATIONS":             true,
		"GF_DATABASE_MIGRATION_LOCKING":           true,
		"GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC": true,
	}
	for _, item := range os.Environ() {
		name, _, found := strings.Cut(item, "=")
		if found && strings.HasPrefix(name, "GF_DATABASE_") && !reviewed[name] {
			return nil, fmt.Errorf("unreviewed Grafana database environment variable %s must not be supplied", name)
		}
	}
	if os.Getenv("GF_DATABASE_TYPE") != "postgres" {
		return nil, fmt.Errorf("GF_DATABASE_TYPE must be postgres")
	}
	host, port, err := parsePostgresEndpoint(os.Getenv("GF_DATABASE_HOST"))
	if err != nil {
		return nil, err
	}
	if port != "5432" {
		return nil, fmt.Errorf("GF_DATABASE_HOST must use the reviewed PostgreSQL port 5432")
	}
	database := os.Getenv("GF_DATABASE_NAME")
	user := os.Getenv("GF_DATABASE_USER")
	if err := validatePostgresIdentifier("GF_DATABASE_NAME", database); err != nil {
		return nil, err
	}
	if err := validatePostgresIdentifier("GF_DATABASE_USER", user); err != nil {
		return nil, err
	}
	if os.Getenv("GF_DATABASE_SSL_MODE") != "disable" {
		return nil, fmt.Errorf("GF_DATABASE_SSL_MODE must be disable on the isolated backend network")
	}
	for name, expected := range map[string]string{
		"GF_DATABASE_SKIP_MIGRATIONS":             "false",
		"GF_DATABASE_MIGRATION_LOCKING":           "true",
		"GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC": "0",
	} {
		if value, exists := os.LookupEnv(name); exists && value != expected {
			return nil, fmt.Errorf("%s must be %s", name, expected)
		}
	}
	return map[string]string{
		"GF_DATABASE_TYPE":                        "postgres",
		"GF_DATABASE_HOST":                        net.JoinHostPort(host, port),
		"GF_DATABASE_NAME":                        database,
		"GF_DATABASE_USER":                        user,
		"GF_DATABASE_SSL_MODE":                    "disable",
		"GF_DATABASE_SKIP_MIGRATIONS":             "false",
		"GF_DATABASE_MIGRATION_LOCKING":           "true",
		"GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC": "0",
	}, nil
}

func databaseRuntimeEnvironment(runtimeSecretDirectory string) (map[string]string, error) {
	values, err := validateDatabaseEnvironmentPolicy()
	if err != nil {
		return nil, err
	}
	values["GF_DATABASE_PASSWORD"] = "$__file{" + runtimeSecretDirectory + "/POSTGRES_PASSWORD}"
	return values, nil
}

func rejectSSOPolicyEnvironment() error {
	if err := rejectDirectSecretEnvironment(); err != nil {
		return err
	}
	reviewedDatabaseNames := map[string]bool{
		"GF_DATABASE_TYPE":     true,
		"GF_DATABASE_HOST":     true,
		"GF_DATABASE_NAME":     true,
		"GF_DATABASE_USER":     true,
		"GF_DATABASE_SSL_MODE": true,
	}
	for _, item := range os.Environ() {
		name, _, found := strings.Cut(item, "=")
		if !found {
			continue
		}
		if strings.HasPrefix(name, "GF_DATABASE_") && !reviewedDatabaseNames[name] {
			return fmt.Errorf("protected environment variable %s must not be supplied", name)
		}
		for _, prefix := range []string{
			"GF_AUTH_",
			"GF_SECURITY_",
			"GF_SMTP_",
			"GRAFANA_ADMIN_",
			"GRAFANA_OIDC_",
			"GRAFANA_SMTP_",
		} {
			if strings.HasPrefix(name, prefix) {
				return fmt.Errorf("protected environment variable %s must not be supplied", name)
			}
		}
	}
	return nil
}

func validateExactSecretMounts(secretDirectory, serviceName string, expectedNames ...string) error {
	directoryFD, err := openDirectory(secretDirectory)
	if err != nil {
		return err
	}
	defer syscall.Close(directoryFD)
	expected := make(map[string]bool, len(expectedNames))
	for _, name := range expectedNames {
		expected[name] = false
	}
	buffer := make([]byte, 4096)
	for {
		count, err := syscall.ReadDirent(directoryFD, buffer)
		if err != nil {
			return fmt.Errorf("cannot inventory %s secrets safely", serviceName)
		}
		if count == 0 {
			break
		}
		_, _, names := syscall.ParseDirent(buffer[:count], -1, nil)
		for _, name := range names {
			if _, allowed := expected[name]; !allowed {
				return fmt.Errorf("%s service mounted an unexpected secret", serviceName)
			}
			expected[name] = true
		}
	}
	for _, name := range expectedNames {
		if !expected[name] {
			return fmt.Errorf("%s service requires %s", serviceName, name)
		}
	}
	return nil
}

func validateSSOPolicySecretMounts(secretDirectory string) error {
	return validateExactSecretMounts(secretDirectory, "SSO policy", "POSTGRES_PASSWORD")
}

func validateMigratorSecretMounts(secretDirectory string) error {
	return validateExactSecretMounts(secretDirectory, "Grafana migrator", "POSTGRES_PASSWORD", "GRAFANA_SECRET_KEY")
}

func escapePGPassField(value []byte) []byte {
	escaped := make([]byte, 0, len(value)+1)
	for _, character := range value {
		if character == '\\' || character == ':' {
			escaped = append(escaped, '\\')
		}
		escaped = append(escaped, character)
	}
	return escaped
}

func buildPGPassEntry(host, port, database, user string, password []byte) []byte {
	fields := [][]byte{[]byte(host), []byte(port), []byte(database), []byte(user), password}
	entry := make([]byte, 0, len(host)+len(port)+len(database)+len(user)+len(password)+5)
	for index, field := range fields {
		if index > 0 {
			entry = append(entry, ':')
		}
		escaped := escapePGPassField(field)
		entry = append(entry, escaped...)
		wipe(escaped)
	}
	return append(entry, '\n')
}

func stagePolicyPasswordFile(directoryFD int, value []byte) error {
	const name = ".pgpass"
	fd, err := syscall.Openat(directoryFD, name, syscall.O_WRONLY|syscall.O_CREAT|syscall.O_EXCL|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0o600)
	if err != nil {
		return fmt.Errorf("cannot create private PostgreSQL password file")
	}
	file := os.NewFile(uintptr(fd), name)
	if file == nil {
		syscall.Close(fd)
		return fmt.Errorf("cannot bind private PostgreSQL password file")
	}
	if err := syscall.Fchmod(fd, 0o600); err != nil {
		file.Close()
		return fmt.Errorf("cannot lock private PostgreSQL password file")
	}
	if _, err := file.Write(value); err != nil {
		file.Close()
		return fmt.Errorf("cannot write private PostgreSQL password file")
	}
	if err := file.Sync(); err != nil {
		file.Close()
		return fmt.Errorf("cannot sync private PostgreSQL password file")
	}
	var stat syscall.Stat_t
	if err := syscall.Fstat(fd, &stat); err != nil || stat.Mode&syscall.S_IFMT != syscall.S_IFREG || stat.Nlink != 1 || stat.Mode&0o777 != 0o600 || stat.Size != int64(len(value)) {
		file.Close()
		return fmt.Errorf("private PostgreSQL password file failed verification")
	}
	if err := file.Close(); err != nil {
		return fmt.Errorf("cannot close private PostgreSQL password file")
	}
	if err := syscall.Fsync(directoryFD); err != nil {
		return fmt.Errorf("cannot sync private PostgreSQL runtime directory")
	}
	return nil
}

func validateRegularExecutable(path string) error {
	if path == "" || !filepath.IsAbs(path) || filepath.Clean(path) != path {
		return fmt.Errorf("PostgreSQL client path is invalid")
	}
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0o111 == 0 {
		return fmt.Errorf("PostgreSQL client is missing or not a regular executable")
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok || stat.Nlink != 1 {
		return fmt.Errorf("PostgreSQL client must have exactly one regular executable link")
	}
	return nil
}

func ssoPolicySQL(expirationDays int) string {
	return fmt.Sprintf(`BEGIN;
SET LOCAL search_path = pg_catalog, public;
SET LOCAL TIME ZONE 'UTC';
DO $policy$
DECLARE
  column_matches bigint;
  primary_key_matches bigint;
BEGIN
  SELECT count(*) INTO column_matches
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'sso_setting'
     AND (
       (column_name = 'id' AND data_type = 'character varying' AND character_maximum_length = 40 AND is_nullable = 'NO') OR
       (column_name = 'provider' AND data_type = 'character varying' AND character_maximum_length = 255 AND is_nullable = 'NO') OR
       (column_name = 'settings' AND data_type = 'text' AND is_nullable = 'NO') OR
       (column_name = 'created' AND data_type = 'timestamp without time zone' AND is_nullable = 'NO') OR
       (column_name = 'updated' AND data_type = 'timestamp without time zone' AND is_nullable = 'NO') OR
       (column_name = 'is_deleted' AND data_type = 'boolean' AND is_nullable = 'NO')
     );
  IF column_matches <> 6 OR (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'sso_setting') <> 6 THEN
    RAISE EXCEPTION 'grafana_policy_sso_schema_mismatch';
  END IF;
  SELECT count(*) INTO primary_key_matches
    FROM pg_constraint constraint_row
    JOIN pg_class table_row ON table_row.oid = constraint_row.conrelid
    JOIN pg_namespace namespace_row ON namespace_row.oid = table_row.relnamespace
   WHERE namespace_row.nspname = 'public' AND table_row.relname = 'sso_setting' AND constraint_row.contype = 'p'
     AND (SELECT array_agg(attribute_row.attname ORDER BY key_row.ordinality)
            FROM unnest(constraint_row.conkey) WITH ORDINALITY AS key_row(attnum, ordinality)
            JOIN pg_attribute attribute_row ON attribute_row.attrelid = table_row.oid AND attribute_row.attnum = key_row.attnum) = ARRAY['id'::name];
  IF primary_key_matches <> 1 THEN
    RAISE EXCEPTION 'grafana_policy_sso_primary_key_mismatch';
  END IF;

  SELECT count(*) INTO column_matches
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'api_key'
     AND (
       (column_name = 'id' AND data_type = 'integer' AND is_nullable = 'NO') OR
       (column_name = 'org_id' AND data_type = 'bigint' AND is_nullable = 'NO') OR
       (column_name = 'name' AND data_type = 'character varying' AND character_maximum_length = 190 AND is_nullable = 'NO') OR
       (column_name = 'key' AND data_type = 'character varying' AND character_maximum_length = 190 AND is_nullable = 'NO') OR
       (column_name = 'role' AND data_type = 'character varying' AND character_maximum_length = 255 AND is_nullable = 'NO') OR
       (column_name = 'created' AND data_type = 'timestamp without time zone' AND is_nullable = 'NO') OR
       (column_name = 'updated' AND data_type = 'timestamp without time zone' AND is_nullable = 'NO') OR
       (column_name = 'expires' AND data_type = 'bigint' AND is_nullable = 'YES') OR
       (column_name = 'service_account_id' AND data_type = 'bigint' AND is_nullable = 'YES') OR
       (column_name = 'last_used_at' AND data_type = 'timestamp without time zone' AND is_nullable = 'YES') OR
       (column_name = 'is_revoked' AND data_type = 'boolean' AND is_nullable = 'YES')
     );
  IF column_matches <> 11 OR (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'api_key') <> 11 THEN
    RAISE EXCEPTION 'grafana_policy_api_key_schema_mismatch';
  END IF;
END
$policy$;

LOCK TABLE public.sso_setting, public.api_key IN SHARE ROW EXCLUSIVE MODE;
DO $policy$
DECLARE
  token_debt bigint;
BEGIN
  SELECT count(*) INTO token_debt
    FROM public.api_key
   WHERE COALESCE(is_revoked, false) = false
     AND (expires IS NULL OR expires > floor(extract(epoch FROM CURRENT_TIMESTAMP + make_interval(days => %d)))::bigint);
  IF token_debt > 0 THEN
    RAISE EXCEPTION 'grafana_policy_token_debt=%%', token_debt;
  END IF;
END
$policy$;

SELECT 'token_compliant=' || count(*)
  FROM public.api_key
 WHERE COALESCE(is_revoked, false) = false
   AND expires IS NOT NULL
   AND expires > floor(extract(epoch FROM CURRENT_TIMESTAMP))::bigint;
WITH changed AS (
  UPDATE public.sso_setting
     SET is_deleted = true, updated = CURRENT_TIMESTAMP
   WHERE is_deleted = false
  RETURNING 1
)
SELECT 'sso_deleted=' || count(*) FROM changed;
SELECT 'sso_active=' || count(*) FROM public.sso_setting WHERE is_deleted = false;
COMMIT;
`, expirationDays)
}

func parsePolicyCount(output, prefix string) (int64, error) {
	if !strings.HasPrefix(output, prefix) {
		return 0, fmt.Errorf("PostgreSQL policy returned an invalid result")
	}
	value, err := strconv.ParseInt(strings.TrimPrefix(output, prefix), 10, 64)
	if err != nil || value < 0 {
		return 0, fmt.Errorf("PostgreSQL policy returned an invalid result")
	}
	return value, nil
}

func parseSSOPolicyResult(output string) (int64, int64, int64, error) {
	lines := strings.Split(strings.TrimSpace(output), "\n")
	if len(lines) != 3 {
		return 0, 0, 0, fmt.Errorf("PostgreSQL policy returned an invalid result")
	}
	compliantTokens, err := parsePolicyCount(strings.TrimSpace(lines[0]), "token_compliant=")
	if err != nil {
		return 0, 0, 0, err
	}
	deleted, err := parsePolicyCount(strings.TrimSpace(lines[1]), "sso_deleted=")
	if err != nil {
		return 0, 0, 0, err
	}
	active, err := parsePolicyCount(strings.TrimSpace(lines[2]), "sso_active=")
	if err != nil {
		return 0, 0, 0, err
	}
	return compliantTokens, deleted, active, nil
}

func policyTokenDebt(stderr string) (int64, bool) {
	const marker = "grafana_policy_token_debt="
	index := strings.Index(stderr, marker)
	if index < 0 {
		return 0, false
	}
	value := stderr[index+len(marker):]
	end := 0
	for end < len(value) && value[end] >= '0' && value[end] <= '9' {
		end++
	}
	if end == 0 {
		return 0, false
	}
	count, err := strconv.ParseInt(value[:end], 10, 64)
	return count, err == nil && count > 0
}

func executePolicyCommand(command *exec.Cmd, timeout time.Duration, interrupted <-chan os.Signal) error {
	if err := command.Start(); err != nil {
		return fmt.Errorf("cannot start PostgreSQL policy client")
	}
	done := make(chan error, 1)
	go func() { done <- command.Wait() }()
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	select {
	case err := <-done:
		return err
	case signalValue := <-interrupted:
		signalNumber, ok := signalValue.(syscall.Signal)
		if !ok {
			signalNumber = syscall.SIGTERM
		}
		_ = stopChild(command, done, signalNumber, 5*time.Second)
		return &exitCodeError{code: 128 + int(signalNumber), err: fmt.Errorf("Grafana SSO policy interrupted")}
	case <-timer.C:
		_ = stopChild(command, done, syscall.SIGTERM, 5*time.Second)
		return fmt.Errorf("Grafana SSO policy timed out")
	}
}

func runSSOPolicyWithRuntime(runtime ssoPolicyRuntime) (returnError error) {
	if runtime.output == nil {
		runtime.output = io.Discard
	}
	if err := rejectSSOPolicyEnvironment(); err != nil {
		return err
	}
	if _, err := validateDatabaseEnvironmentPolicy(); err != nil {
		return err
	}
	if err := validateSSOPolicySecretMounts(runtime.secretDirectory); err != nil {
		return err
	}
	if os.Getenv("GF_DATABASE_TYPE") != "postgres" {
		return fmt.Errorf("SSO policy requires GF_DATABASE_TYPE=postgres")
	}
	if os.Getenv("GF_DATABASE_SSL_MODE") != "disable" {
		return fmt.Errorf("SSO policy requires GF_DATABASE_SSL_MODE=disable")
	}
	host, port, err := parsePostgresEndpoint(os.Getenv("GF_DATABASE_HOST"))
	if err != nil {
		return err
	}
	database := os.Getenv("GF_DATABASE_NAME")
	user := os.Getenv("GF_DATABASE_USER")
	if err := validatePostgresIdentifier("GF_DATABASE_NAME", database); err != nil {
		return err
	}
	if err := validatePostgresIdentifier("GF_DATABASE_USER", user); err != nil {
		return err
	}
	timeoutSeconds, err := parseBoundedInteger("GRAFANA_SSO_POLICY_TIMEOUT_SECONDS", 30, 5, 120)
	if err != nil {
		return err
	}
	expirationDays, err := parseBoundedInteger("GRAFANA_SERVICE_ACCOUNT_TOKEN_EXPIRATION_DAYS", defaultServiceAccountExpiryDays, 1, 365)
	if err != nil {
		return err
	}
	if err := validateRegularExecutable(runtime.psqlBinary); err != nil {
		return err
	}

	password, err := readSecret(runtime.secretDirectory, "POSTGRES_PASSWORD")
	if err != nil {
		return err
	}
	entry := buildPGPassEntry(host, port, database, user, password)
	wipe(password)
	runtimeFD, err := prepareRuntimeSecretDirectory(runtime.runtimeDirectory)
	if err != nil {
		wipe(entry)
		return err
	}
	defer syscall.Close(runtimeFD)
	passwordFile := filepath.Join(runtime.runtimeDirectory, ".pgpass")
	defer func() {
		cleanupError := syscall.Unlinkat(runtimeFD, ".pgpass")
		if cleanupError != nil && !errors.Is(cleanupError, syscall.ENOENT) {
			if returnError == nil {
				returnError = fmt.Errorf("cannot remove private PostgreSQL password file")
			}
			return
		}
		if syncError := syscall.Fsync(runtimeFD); syncError != nil && returnError == nil {
			returnError = fmt.Errorf("cannot sync PostgreSQL password-file removal")
		}
	}()
	if err := stagePolicyPasswordFile(runtimeFD, entry); err != nil {
		wipe(entry)
		return err
	}
	wipe(entry)

	arguments := []string{
		"--no-psqlrc",
		"--no-password",
		"--set=ON_ERROR_STOP=1",
		"--set=VERBOSITY=terse",
		"--host", host,
		"--port", port,
		"--username", user,
		"--dbname", database,
		"--no-align",
		"--tuples-only",
		"--quiet",
	}
	command := exec.Command(runtime.psqlBinary, arguments...)
	command.Env = []string{
		"LANG=C",
		"LC_ALL=C",
		"PGAPPNAME=grafana-sso-policy",
		"PGCONNECT_TIMEOUT=5",
		"PGOPTIONS=-c statement_timeout=" + strconv.Itoa(timeoutSeconds*1000) + " -c lock_timeout=5000",
		"PGPASSFILE=" + passwordFile,
		"PGSSLMODE=disable",
	}
	command.Stdin = strings.NewReader(ssoPolicySQL(expirationDays))
	stdout := &boundedCommandOutput{maximum: maximumPolicyOutputBytes}
	stderr := &boundedCommandOutput{maximum: maximumPolicyOutputBytes}
	command.Stdout = stdout
	command.Stderr = stderr
	command.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := executePolicyCommand(command, time.Duration(timeoutSeconds)*time.Second, runtime.interrupted); err != nil {
		if debt, found := policyTokenDebt(stderr.String()); found {
			return fmt.Errorf("%d active API or service-account token(s) violate the %d-day expiration policy", debt, expirationDays)
		}
		if strings.Contains(stderr.String(), "grafana_policy_sso_schema_mismatch") || strings.Contains(stderr.String(), "grafana_policy_sso_primary_key_mismatch") {
			return fmt.Errorf("Grafana 13.2 sso_setting schema does not match the reviewed policy")
		}
		if strings.Contains(stderr.String(), "grafana_policy_api_key_schema_mismatch") {
			return fmt.Errorf("Grafana 13.2 api_key schema does not match the reviewed policy")
		}
		var coded *exitCodeError
		if errors.As(err, &coded) || strings.Contains(err.Error(), "timed out") || strings.Contains(err.Error(), "cannot start") {
			return err
		}
		return fmt.Errorf("PostgreSQL policy transaction failed")
	}
	if stdout.truncated || stderr.truncated || strings.TrimSpace(stderr.String()) != "" {
		return fmt.Errorf("PostgreSQL policy returned unexpected diagnostics")
	}
	compliantTokens, deleted, active, err := parseSSOPolicyResult(stdout.String())
	if err != nil {
		return err
	}
	if active != 0 {
		return fmt.Errorf("Grafana SSO policy left %d active database override(s)", active)
	}
	fmt.Fprintf(runtime.output, "[grafana-sso-policy] Verified %d compliant active API/service-account token(s); reconciled %d active SSO override(s); active overrides: 0.\n", compliantTokens, deleted)
	return nil
}

func runSSOPolicy() error {
	interrupted := make(chan os.Signal, 1)
	signal.Notify(interrupted, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(interrupted)
	return runSSOPolicyWithRuntime(ssoPolicyRuntime{
		psqlBinary:       defaultPSQLBinary,
		secretDirectory:  defaultSecretDirectory,
		runtimeDirectory: defaultSSOPolicyRuntimeDir,
		output:           os.Stdout,
		interrupted:      interrupted,
	})
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
		if seenScopes[scope] {
			return fmt.Errorf("GRAFANA_OIDC_SCOPES must not contain duplicate scopes")
		}
		seenScopes[scope] = true
	}
	for _, requiredScope := range []string{"openid", "profile", "email", "offline_access"} {
		if !seenScopes[requiredScope] {
			return fmt.Errorf("GRAFANA_OIDC_SCOPES must include %s", requiredScope)
		}
	}
	baseURL := "https://" + authentikDomain + "/application/o/"
	roleExpression := fmt.Sprintf(
		"contains(groups[*], '%s') && !contains(groups[*], '%s') && !contains(groups[*], '%s') && 'GrafanaAdmin' || !contains(groups[*], '%s') && contains(groups[*], '%s') && !contains(groups[*], '%s') && 'Editor' || !contains(groups[*], '%s') && !contains(groups[*], '%s') && contains(groups[*], '%s') && 'Viewer'",
		adminGroup,
		editorGroup,
		viewerGroup,
		adminGroup,
		editorGroup,
		viewerGroup,
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
		"GF_AUTH_OAUTH_ALLOW_INSECURE_EMAIL_LOOKUP":        "false",
		"GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP":              "true",
		"GF_AUTH_GENERIC_OAUTH_AUTO_LOGIN":                 os.Getenv("GRAFANA_OAUTH_AUTO_LOGIN"),
		"GF_AUTH_GENERIC_OAUTH_USE_PKCE":                   "true",
		"GF_AUTH_GENERIC_OAUTH_USE_REFRESH_TOKEN":          "true",
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
	if err := rejectDirectSecretEnvironment(); err != nil {
		return nil, err
	}
	databaseEnvironment, err := databaseRuntimeEnvironment(runtimeSecretDirectory)
	if err != nil {
		return nil, err
	}
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
	if err := configurePluginPolicy(); err != nil {
		return nil, err
	}
	if err := configureSessionAndTokenPolicy(); err != nil {
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
	runtimeEnvironment := map[string]string{
		"GF_SECURITY_SECRET_KEY":                     "$__file{" + runtimeSecretDirectory + "/GRAFANA_SECRET_KEY}",
		"GF_SECURITY_DISABLE_INITIAL_ADMIN_CREATION": "true",
		"GF_SECURITY_COOKIE_SECURE":                  "true",
		"GF_SECURITY_DISABLE_GRAVATAR":               "true",
		"GF_USERS_ALLOW_SIGN_UP":                     "false",
		"GF_USERS_ALLOW_ORG_CREATE":                  "false",
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
		"GF_SSO_SETTINGS_CONFIGURABLE_PROVIDERS":     ssoConfigurationLockProvider,
		"GF_ANALYTICS_REPORTING_ENABLED":             "false",
		"GF_ANALYTICS_CHECK_FOR_UPDATES":             "false",
		"GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES":      "false",
		"GF_METRICS_ENABLED":                         "false",
		"GF_PUBLIC_DASHBOARDS_ENABLED":               "false",
		"GF_SNAPSHOTS_ENABLED":                       "false",
		"GF_SNAPSHOTS_EXTERNAL_ENABLED":              "false",
		"GF_PLUGINS_PLUGIN_ADMIN_ENABLED":            "false",
		"GF_NEWS_NEWS_FEED_ENABLED":                  "false",
	}
	for name, value := range databaseEnvironment {
		runtimeEnvironment[name] = value
	}
	if err := setEnvironments(runtimeEnvironment); err != nil {
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
	if err := rejectDirectSecretEnvironment(); err != nil {
		return err
	}
	databaseEnvironment, err := databaseRuntimeEnvironment(secretDirectory)
	if err != nil {
		return err
	}
	if err := rejectProtectedEnvironment(
		"GF_DATABASE_PASSWORD", "GF_DATABASE_PASSWORD__FILE",
		"GF_SECURITY_SECRET_KEY", "GF_SECURITY_SECRET_KEY__FILE",
		"GF_SECURITY_ADMIN_PASSWORD", "GF_SECURITY_ADMIN_PASSWORD__FILE",
	); err != nil {
		return err
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
	databaseEnvironment["GF_SECURITY_SECRET_KEY"] = "$__file{" + secretDirectory + "/GRAFANA_SECRET_KEY}"
	return setEnvironments(databaseEnvironment)
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

func parseMigratorStopTimeout() (time.Duration, error) {
	timeout, err := parsePositiveSeconds("GRAFANA_MIGRATOR_STOP_TIMEOUT_SECONDS", 30)
	if err != nil {
		return 0, err
	}
	if timeout > 60*time.Second {
		return 0, fmt.Errorf("GRAFANA_MIGRATOR_STOP_TIMEOUT_SECONDS must not exceed 60 seconds")
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
	databaseEnvironment, err := databaseRuntimeEnvironment(runtimeSecretDirectory)
	if err != nil {
		return nil, err
	}
	adminUser := os.Getenv("GRAFANA_ADMIN_USER")
	if adminUser == "" {
		adminUser = "admin"
	}
	values := map[string]string{
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
		"GF_SSO_SETTINGS_CONFIGURABLE_PROVIDERS":     ssoConfigurationLockProvider,
		"GF_SMTP_ENABLED":                            "false",
		"GF_ANALYTICS_REPORTING_ENABLED":             "false",
		"GF_ANALYTICS_CHECK_FOR_UPDATES":             "false",
		"GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES":      "false",
		"GF_METRICS_ENABLED":                         "false",
		"GF_PUBLIC_DASHBOARDS_ENABLED":               "false",
		"GF_SNAPSHOTS_ENABLED":                       "false",
		"GF_SNAPSHOTS_EXTERNAL_ENABLED":              "false",
		"GF_PLUGINS_PLUGIN_ADMIN_ENABLED":            "false",
		"GF_PATHS_PLUGINS":                           defaultBootstrapPluginDir,
	}
	if includeAdminPassword {
		values["GF_SECURITY_ADMIN_PASSWORD"] = "$__file{" + runtimeSecretDirectory + "/GRAFANA_ADMIN_PASSWORD}"
	}
	for name, value := range databaseEnvironment {
		values[name] = value
	}
	environment := os.Environ()
	protectedPrefixes := []string{
		"GF_DATABASE_",
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

func migrationEnvironment(runtimeSecretDirectory string) ([]string, error) {
	environment, err := vendorEnvironment(runtimeSecretDirectory, false)
	if err != nil {
		return nil, err
	}
	filtered := environment[:0]
	for _, item := range environment {
		if strings.HasPrefix(item, "GF_SECURITY_ADMIN_USER=") ||
			strings.HasPrefix(item, "GF_AUTH_DISABLE_LOGIN_FORM=") ||
			strings.HasPrefix(item, "GF_AUTH_BASIC_ENABLED=") {
			continue
		}
		filtered = append(filtered, item)
	}
	return append(
		filtered,
		"GF_AUTH_DISABLE_LOGIN_FORM=true",
		"GF_AUTH_BASIC_ENABLED=false",
	), nil
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

func waitForMigrationHealth(done <-chan error, interrupted <-chan os.Signal, healthURL string, timeout time.Duration) error {
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
			return fmt.Errorf("Grafana migration verification timed out")
		case <-ticker.C:
			if err := checkHealthURL(healthURL); err == nil {
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

func runMigrationChild(runtimeSecretDirectory, healthURL string, readyTimeout, stopTimeout time.Duration, interrupted <-chan os.Signal) error {
	environment, err := migrationEnvironment(runtimeSecretDirectory)
	if err != nil {
		return err
	}
	command, done, err := startBootstrapChild(environment)
	if err != nil {
		return err
	}
	verificationError := waitForMigrationHealth(done, interrupted, healthURL, readyTimeout)
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

func runMigration() error {
	if err := rejectDirectSecretEnvironment(); err != nil {
		return err
	}
	if _, err := validateDatabaseEnvironmentPolicy(); err != nil {
		return err
	}
	if err := configurePluginPolicy(); err != nil {
		return err
	}
	if err := os.Mkdir(defaultBootstrapPluginDir, 0o700); err != nil && !errors.Is(err, os.ErrExist) {
		return fmt.Errorf("cannot create private migration plugin directory")
	}
	if err := rejectProtectedEnvironment(
		"GF_DATABASE_PASSWORD", "GF_DATABASE_PASSWORD__FILE",
		"GF_SECURITY_SECRET_KEY", "GF_SECURITY_SECRET_KEY__FILE",
		"GF_SECURITY_ADMIN_PASSWORD", "GF_SECURITY_ADMIN_PASSWORD__FILE",
		"GRAFANA_ADMIN_PASSWORD", "GRAFANA_ADMIN_PASSWORD_FILE", "GRAFANA_ADMIN_PASSWORD__FILE",
		"GF_AUTH_GENERIC_OAUTH_CLIENT_ID", "GF_AUTH_GENERIC_OAUTH_CLIENT_ID__FILE",
		"GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET", "GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET__FILE",
		"GF_SMTP_PASSWORD", "GF_SMTP_PASSWORD__FILE",
	); err != nil {
		return err
	}
	secretDirectory := defaultSecretDirectory
	runtimeSecretDirectory := defaultRuntimeSecretDir
	if err := validateMigratorSecretMounts(secretDirectory); err != nil {
		return err
	}
	values, err := loadAndStageSecrets(secretDirectory, runtimeSecretDirectory, []string{"POSTGRES_PASSWORD", "GRAFANA_SECRET_KEY"})
	if err != nil {
		return err
	}
	defer func() {
		for _, value := range values {
			wipe(value)
		}
	}()
	readyTimeout, err := parsePositiveSeconds("GRAFANA_MIGRATOR_READY_TIMEOUT_SECONDS", 300)
	if err != nil {
		return err
	}
	stopTimeout, err := parseMigratorStopTimeout()
	if err != nil {
		return err
	}
	interrupted := make(chan os.Signal, 1)
	signal.Notify(interrupted, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(interrupted)
	if err := runMigrationChild(runtimeSecretDirectory, "http://127.0.0.1:3000/api/health", readyTimeout, stopTimeout, interrupted); err != nil {
		return fmt.Errorf("Grafana migration verification failed: %w", err)
	}
	fmt.Fprintln(os.Stdout, "[grafana-migrator] Database migrations and health verified without the bootstrap administrator credential.")
	return nil
}

func runBootstrap() error {
	if err := rejectDirectSecretEnvironment(); err != nil {
		return err
	}
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
	if _, err := validateDatabaseEnvironmentPolicy(); err != nil {
		return err
	}
	if err := configurePluginPolicy(); err != nil {
		return err
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
		case "migrate":
			err = runMigration()
		case "health":
			err = runHealthcheck()
		case "preflight":
			err = runApplication(nil, true)
		case "sso-policy":
			err = runSSOPolicy()
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
