// SPDX-License-Identifier: MIT
// Copyright (c) 2025 it.særvices

package main

import (
	"bytes"
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"
	"syscall"
	"unicode"
)

const (
	privateKeyPath         = "/etc/coolwsd/proof_key"
	publicKeyPath          = "/etc/coolwsd/proof_key.pub"
	extraParamsEnvironment = "COLLABORA_EXTRA_PARAMS"
	maximumKeySize         = 64 * 1024
	minimumRSABits         = 2048
	maximumExtraParamsSize = 8 * 1024
	maximumExtraParamSize  = 1024
	maximumExtraParamCount = 32
)

var vendorCommandBase = []string{
	"/usr/bin/coolwsd",
	"--use-env-vars",
	"--o:sys_template_path=/opt/cool/systemplate",
	"--o:child_root_path=/opt/cool/child-roots",
	"--o:file_server_root_path=/usr/share/coolwsd",
	"--o:cache_files.path=/opt/cool/cache",
	"--o:logging.color=false",
	"--o:stop_on_config_change=true",
}

var mandatoryParams = []string{
	"--o:ssl.enable=false",
	"--o:ssl.termination=true",
	"--o:mount_jail_tree=false",
	"--o:security.capabilities=false",
}

func main() {
	if err := validateKeyPair(privateKeyPath, publicKeyPath); err != nil {
		fmt.Fprintf(os.Stderr, "[collabora-preflight] ERROR: %v\n", err)
		os.Exit(1)
	}
	vendorCommand, err := buildVendorCommand(os.Getenv(extraParamsEnvironment))
	if err != nil {
		fmt.Fprintf(os.Stderr, "[collabora-preflight] ERROR: %v\n", err)
		os.Exit(1)
	}

	if len(os.Args) == 2 && os.Args[1] == "--preflight-only" {
		return
	}
	if len(os.Args) != 1 {
		fmt.Fprintln(os.Stderr, "[collabora-preflight] ERROR: unexpected wrapper arguments")
		os.Exit(1)
	}

	if err := syscall.Exec(vendorCommand[0], vendorCommand, os.Environ()); err != nil {
		fmt.Fprintln(os.Stderr, "[collabora-preflight] ERROR: vendor entrypoint execution failed")
		os.Exit(1)
	}
}

func buildVendorCommand(rawExtraParams string) ([]string, error) {
	extraParams, err := parseExtraParams(rawExtraParams)
	if err != nil {
		return nil, err
	}

	command := make([]string, 0, len(vendorCommandBase)+len(extraParams)+len(mandatoryParams))
	command = append(command, vendorCommandBase...)
	command = append(command, extraParams...)
	command = append(command, mandatoryParams...)
	return command, nil
}

func parseExtraParams(raw string) ([]string, error) {
	if len(raw) > maximumExtraParamsSize {
		return nil, errors.New("COLLABORA_EXTRA_PARAMS exceeds the maximum total length")
	}
	for _, character := range raw {
		if unicode.IsControl(character) {
			return nil, errors.New("COLLABORA_EXTRA_PARAMS contains a control character")
		}
	}

	fields := strings.Fields(raw)
	if len(fields) > maximumExtraParamCount {
		return nil, errors.New("COLLABORA_EXTRA_PARAMS contains too many options")
	}

	reservedKeys := make(map[string]struct{}, len(vendorCommandBase)+len(mandatoryParams))
	reservedOptions := make([]string, 0, len(vendorCommandBase)+len(mandatoryParams))
	reservedOptions = append(reservedOptions, vendorCommandBase...)
	reservedOptions = append(reservedOptions, mandatoryParams...)
	for _, option := range reservedOptions {
		if !strings.HasPrefix(option, "--o:") {
			continue
		}
		key, err := optionKey(option)
		if err != nil {
			return nil, errors.New("internal Collabora option is invalid")
		}
		reservedKeys[key] = struct{}{}
	}

	seenKeys := make(map[string]struct{}, len(fields))
	for _, option := range fields {
		if len(option) > maximumExtraParamSize {
			return nil, errors.New("COLLABORA_EXTRA_PARAMS contains an oversized option")
		}
		key, err := optionKey(option)
		if err != nil {
			return nil, errors.New("COLLABORA_EXTRA_PARAMS accepts only --o:key=value options")
		}
		if _, reserved := reservedKeys[key]; reserved {
			return nil, fmt.Errorf("COLLABORA_EXTRA_PARAMS may not override mandatory option %q", key)
		}
		if _, duplicate := seenKeys[key]; duplicate {
			return nil, fmt.Errorf("COLLABORA_EXTRA_PARAMS contains duplicate option %q", key)
		}
		seenKeys[key] = struct{}{}
	}
	return fields, nil
}

func optionKey(option string) (string, error) {
	if !strings.HasPrefix(option, "--o:") {
		return "", errors.New("missing --o: prefix")
	}
	key, _, hasValue := strings.Cut(strings.TrimPrefix(option, "--o:"), "=")
	if !hasValue || key == "" {
		return "", errors.New("missing option key or value separator")
	}
	return key, nil
}

func validateKeyPair(privatePath, publicPath string) error {
	privatePEM, err := readSecretFile(privatePath, "private proof key")
	if err != nil {
		return err
	}
	publicPEM, err := readSecretFile(publicPath, "public proof key")
	if err != nil {
		return err
	}

	privateKey, err := parsePrivateKey(privatePEM)
	if err != nil {
		return errors.New("private proof key is not a valid unencrypted RSA PEM key")
	}
	publicKey, err := parsePublicKey(publicPEM)
	if err != nil {
		return errors.New("public proof key is not a valid RSA PEM key")
	}

	if privateKey.N.BitLen() < minimumRSABits || publicKey.N.BitLen() < minimumRSABits {
		return fmt.Errorf("proof keys must use RSA with at least %d bits", minimumRSABits)
	}
	if privateKey.N.Cmp(publicKey.N) != 0 || privateKey.E != publicKey.E {
		return errors.New("private and public proof keys do not form a matching pair")
	}
	return nil
}

func readSecretFile(path, label string) ([]byte, error) {
	fd, err := syscall.Open(path, syscall.O_RDONLY|syscall.O_CLOEXEC|syscall.O_NOFOLLOW|syscall.O_NONBLOCK, 0)
	if err != nil {
		return nil, fmt.Errorf("%s is missing, unreadable, or not a regular file", label)
	}
	file := os.NewFile(uintptr(fd), path)
	if file == nil {
		syscall.Close(fd)
		return nil, fmt.Errorf("%s could not be opened safely", label)
	}
	defer file.Close()

	before, err := file.Stat()
	if err != nil || !before.Mode().IsRegular() {
		return nil, fmt.Errorf("%s is not a regular file", label)
	}
	if before.Size() < 1 || before.Size() > maximumKeySize {
		return nil, fmt.Errorf("%s has an invalid size", label)
	}

	content, err := io.ReadAll(io.LimitReader(file, maximumKeySize+1))
	if err != nil || int64(len(content)) != before.Size() || len(content) > maximumKeySize {
		return nil, fmt.Errorf("%s changed or could not be read completely", label)
	}
	after, err := file.Stat()
	if err != nil || !os.SameFile(before, after) || before.Size() != after.Size() {
		return nil, fmt.Errorf("%s changed while it was being read", label)
	}
	if bytes.Equal(content, []byte("CHANGE_ME")) {
		return nil, fmt.Errorf("%s still contains the placeholder value", label)
	}
	return content, nil
}

func parsePrivateKey(content []byte) (*rsa.PrivateKey, error) {
	block, rest := pem.Decode(content)
	if block == nil || len(bytes.TrimSpace(rest)) != 0 {
		return nil, errors.New("invalid private PEM document")
	}

	var privateKey *rsa.PrivateKey
	switch block.Type {
	case "PRIVATE KEY":
		parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
		if err != nil {
			return nil, err
		}
		var ok bool
		privateKey, ok = parsed.(*rsa.PrivateKey)
		if !ok {
			return nil, errors.New("private key is not RSA")
		}
	case "RSA PRIVATE KEY":
		parsed, err := x509.ParsePKCS1PrivateKey(block.Bytes)
		if err != nil {
			return nil, err
		}
		privateKey = parsed
	default:
		return nil, errors.New("unsupported private key type")
	}

	if err := privateKey.Validate(); err != nil {
		return nil, err
	}
	return privateKey, nil
}

func parsePublicKey(content []byte) (*rsa.PublicKey, error) {
	block, rest := pem.Decode(content)
	if block == nil || len(bytes.TrimSpace(rest)) != 0 {
		return nil, errors.New("invalid public PEM document")
	}

	switch block.Type {
	case "PUBLIC KEY":
		parsed, err := x509.ParsePKIXPublicKey(block.Bytes)
		if err != nil {
			return nil, err
		}
		publicKey, ok := parsed.(*rsa.PublicKey)
		if !ok {
			return nil, errors.New("public key is not RSA")
		}
		return publicKey, nil
	case "RSA PUBLIC KEY":
		return x509.ParsePKCS1PublicKey(block.Bytes)
	default:
		return nil, errors.New("unsupported public key type")
	}
}
