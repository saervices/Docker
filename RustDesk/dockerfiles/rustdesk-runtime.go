// SPDX-License-Identifier: MIT
// Copyright (c) 2025 it.særvices
//
// RustDesk shellless stærtup preflight, key bootstræp, ænd listener probe.
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
)

const (
	dataDirectory  = "/root"
	privateKeyName = "id_ed25519"
	publicKeyName  = "id_ed25519.pub"
	maxKeyFileSize = 1024
)

var requiredInvariantVariables = []string{
	"RUSTDESK_APP_IMAGE_REFERENCE",
	"RUSTDESK_RELAY_IMAGE_REFERENCE",
	"RUSTDESK_APP_UID",
	"RUSTDESK_APP_GID",
	"RUSTDESK_RELAY_UID",
	"RUSTDESK_RELAY_GID",
}

func fail(format string, arguments ...any) {
	fmt.Fprintf(os.Stderr, "[rustdesk-runtime] ERROR: "+format+"\n", arguments...)
	os.Exit(1)
}

func requiredEnvironment(name string) (string, error) {
	value, ok := os.LookupEnv(name)
	if !ok || value == "" {
		return "", fmt.Errorf("%s is required", name)
	}
	return value, nil
}

func parseIdentity(name, value string) (int, error) {
	identity, err := strconv.Atoi(value)
	if err != nil || identity < 1 || identity > 2147483647 {
		return 0, fmt.Errorf("%s must be a numeric identity from 1 to 2147483647", name)
	}
	return identity, nil
}

func validateInvariants() error {
	values := make(map[string]string, len(requiredInvariantVariables))
	for _, name := range requiredInvariantVariables {
		value, err := requiredEnvironment(name)
		if err != nil {
			return err
		}
		values[name] = value
	}
	if values["RUSTDESK_APP_IMAGE_REFERENCE"] != values["RUSTDESK_RELAY_IMAGE_REFERENCE"] {
		return errors.New("hbbs and hbbr image references must be identical")
	}

	appUID, err := parseIdentity("RUSTDESK_APP_UID", values["RUSTDESK_APP_UID"])
	if err != nil {
		return err
	}
	appGID, err := parseIdentity("RUSTDESK_APP_GID", values["RUSTDESK_APP_GID"])
	if err != nil {
		return err
	}
	relayUID, err := parseIdentity("RUSTDESK_RELAY_UID", values["RUSTDESK_RELAY_UID"])
	if err != nil {
		return err
	}
	relayGID, err := parseIdentity("RUSTDESK_RELAY_GID", values["RUSTDESK_RELAY_GID"])
	if err != nil {
		return err
	}
	if appUID != relayUID || appGID != relayGID {
		return errors.New("hbbs and hbbr UID/GID values must be identical")
	}
	if os.Geteuid() != appUID || os.Getegid() != appGID {
		return fmt.Errorf("effective identity %d:%d does not match configured identity", os.Geteuid(), os.Getegid())
	}
	return nil
}

func openRegularNoFollow(path string, maximumSize int64, requiredMode uint32, fixMode bool) ([]byte, error) {
	fd, err := syscall.Open(path, syscall.O_RDONLY|syscall.O_NONBLOCK|syscall.O_NOFOLLOW, 0)
	if err != nil {
		return nil, err
	}
	file := os.NewFile(uintptr(fd), path)
	if file == nil {
		_ = syscall.Close(fd)
		return nil, fmt.Errorf("failed to wrap descriptor for %s", path)
	}
	defer file.Close()

	var metadata syscall.Stat_t
	if err := syscall.Fstat(fd, &metadata); err != nil {
		return nil, err
	}
	if metadata.Mode&syscall.S_IFMT != syscall.S_IFREG {
		return nil, fmt.Errorf("%s is not a regular file", path)
	}
	if metadata.Size < 1 || metadata.Size > maximumSize {
		return nil, fmt.Errorf("%s has an invalid size", path)
	}
	if fixMode {
		if err := syscall.Fchmod(fd, requiredMode); err != nil {
			return nil, fmt.Errorf("failed to set mode on %s: %w", path, err)
		}
	} else if metadata.Mode&0o777 != requiredMode {
		return nil, fmt.Errorf("%s must have mode %04o", path, requiredMode)
	}

	content, err := io.ReadAll(io.LimitReader(file, maximumSize+1))
	if err != nil {
		return nil, err
	}
	if int64(len(content)) > maximumSize {
		return nil, fmt.Errorf("%s exceeds the size limit", path)
	}
	return content, nil
}

func writeNewRegularFile(path string, content []byte, mode uint32) error {
	fd, err := syscall.Open(path, syscall.O_WRONLY|syscall.O_CREAT|syscall.O_EXCL|syscall.O_NOFOLLOW, mode)
	if err != nil {
		return err
	}
	file := os.NewFile(uintptr(fd), path)
	if file == nil {
		_ = syscall.Close(fd)
		return fmt.Errorf("failed to wrap descriptor for %s", path)
	}
	defer file.Close()

	if err := syscall.Fchmod(fd, mode); err != nil {
		return err
	}
	if _, err := file.Write(content); err != nil {
		return err
	}
	return file.Sync()
}

func validateKeyPair(privateEncoded, publicEncoded []byte) error {
	if len(privateEncoded) != 88 || len(publicEncoded) != 44 {
		return errors.New("RustDesk key files have invalid encoded lengths")
	}
	privateDecoded, err := base64.StdEncoding.DecodeString(string(privateEncoded))
	if err != nil || len(privateDecoded) != ed25519.PrivateKeySize {
		return errors.New("RustDesk private key is not valid base64 Ed25519 data")
	}
	publicDecoded, err := base64.StdEncoding.DecodeString(string(publicEncoded))
	if err != nil || len(publicDecoded) != ed25519.PublicKeySize {
		return errors.New("RustDesk public key is not valid base64 Ed25519 data")
	}
	derivedPublic := ed25519.PrivateKey(privateDecoded).Public().(ed25519.PublicKey)
	if subtle.ConstantTimeCompare(derivedPublic, publicDecoded) != 1 {
		return errors.New("RustDesk private and public keys do not match")
	}
	return nil
}

func ensureKeyPairAt(directory string, fixModes bool) error {
	metadata, err := os.Lstat(directory)
	if err != nil {
		return fmt.Errorf("failed to inspect data directory: %w", err)
	}
	if !metadata.IsDir() || metadata.Mode()&os.ModeSymlink != 0 {
		return errors.New("RustDesk data path must be a real directory")
	}

	privatePath := filepath.Join(directory, privateKeyName)
	publicPath := filepath.Join(directory, publicKeyName)
	privateMetadata, privateErr := os.Lstat(privatePath)
	publicMetadata, publicErr := os.Lstat(publicPath)
	privateMissing := errors.Is(privateErr, os.ErrNotExist)
	publicMissing := errors.Is(publicErr, os.ErrNotExist)
	if privateErr != nil && !privateMissing {
		return privateErr
	}
	if publicErr != nil && !publicMissing {
		return publicErr
	}
	if privateMissing != publicMissing {
		return errors.New("RustDesk key pair is incomplete")
	}

	if privateMissing {
		publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
		if err != nil {
			return fmt.Errorf("failed to generate RustDesk key pair: %w", err)
		}
		privateEncoded := []byte(base64.StdEncoding.EncodeToString(privateKey))
		publicEncoded := []byte(base64.StdEncoding.EncodeToString(publicKey))
		if err := writeNewRegularFile(privatePath, privateEncoded, 0o600); err != nil {
			return fmt.Errorf("failed to create RustDesk private key: %w", err)
		}
		if err := writeNewRegularFile(publicPath, publicEncoded, 0o644); err != nil {
			_ = os.Remove(privatePath)
			return fmt.Errorf("failed to create RustDesk public key: %w", err)
		}
		privateMetadata, _ = os.Lstat(privatePath)
		publicMetadata, _ = os.Lstat(publicPath)
	}
	if privateMetadata.Mode()&os.ModeSymlink != 0 || publicMetadata.Mode()&os.ModeSymlink != 0 {
		return errors.New("RustDesk key files must not be symlinks")
	}

	privateEncoded, err := openRegularNoFollow(privatePath, maxKeyFileSize, 0o600, fixModes)
	if err != nil {
		return fmt.Errorf("private-key validation failed: %w", err)
	}
	publicEncoded, err := openRegularNoFollow(publicPath, maxKeyFileSize, 0o644, fixModes)
	if err != nil {
		return fmt.Errorf("public-key validation failed: %w", err)
	}
	return validateKeyPair(privateEncoded, publicEncoded)
}

func parseProcNet(content string, expectedState string) map[int]bool {
	ports := make(map[int]bool)
	for _, line := range strings.Split(content, "\n") {
		fields := strings.Fields(line)
		if len(fields) < 4 || fields[3] != expectedState {
			continue
		}
		local := fields[1]
		separator := strings.LastIndexByte(local, ':')
		if separator < 0 {
			continue
		}
		port, err := strconv.ParseUint(local[separator+1:], 16, 16)
		if err == nil {
			ports[int(port)] = true
		}
	}
	return ports
}

func collectPorts(paths []string, expectedState string) (map[int]bool, error) {
	collected := make(map[int]bool)
	for _, path := range paths {
		content, err := os.ReadFile(path)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			return nil, err
		}
		for port := range parseProcNet(string(content), expectedState) {
			collected[port] = true
		}
	}
	return collected, nil
}

func processExists(role string) bool {
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return false
	}
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		if _, err := strconv.Atoi(entry.Name()); err != nil {
			continue
		}
		content, err := os.ReadFile(filepath.Join("/proc", entry.Name(), "comm"))
		if err == nil && strings.TrimSpace(string(content)) == role {
			return true
		}
	}
	return false
}

func isProImage() bool {
	metadata, err := os.Stat("/usr/bin/rustdesk-utils")
	return err == nil && metadata.Mode().IsRegular()
}

func validateListenerSet(role string) error {
	tcpPorts, err := collectPorts([]string{"/proc/net/tcp", "/proc/net/tcp6"}, "0A")
	if err != nil {
		return err
	}
	udpPorts, err := collectPorts([]string{"/proc/net/udp", "/proc/net/udp6"}, "07")
	if err != nil {
		return err
	}

	var requiredTCP []int
	var requiredUDP []int
	switch role {
	case "hbbs":
		requiredTCP = []int{21115, 21116, 21118}
		requiredUDP = []int{21116}
		if isProImage() {
			requiredTCP = append(requiredTCP, 21114)
		}
	case "hbbr":
		requiredTCP = []int{21117, 21119}
	default:
		return errors.New("unsupported RustDesk role")
	}
	for _, port := range requiredTCP {
		if !tcpPorts[port] {
			return fmt.Errorf("%s is not listening on TCP %d", role, port)
		}
	}
	for _, port := range requiredUDP {
		if !udpPorts[port] {
			return fmt.Errorf("%s is not listening on UDP %d", role, port)
		}
	}
	return nil
}

func runHealth(role string) error {
	if role != "hbbs" && role != "hbbr" {
		return errors.New("health role must be hbbs or hbbr")
	}
	if err := validateInvariants(); err != nil {
		return err
	}
	if err := ensureKeyPairAt(dataDirectory, false); err != nil {
		return err
	}
	if !processExists(role) {
		return fmt.Errorf("%s process is not running", role)
	}
	return validateListenerSet(role)
}

func runDaemon(role string) error {
	if role != "hbbs" && role != "hbbr" {
		return errors.New("daemon role must be hbbs or hbbr")
	}
	if err := validateInvariants(); err != nil {
		return err
	}
	if err := ensureKeyPairAt(dataDirectory, true); err != nil {
		return err
	}
	binary := "/usr/bin/" + role
	return syscall.Exec(binary, []string{binary}, os.Environ())
}

func main() {
	syscall.Umask(0o077)
	arguments := os.Args[1:]
	if len(arguments) == 2 && arguments[0] == "health" {
		if err := runHealth(arguments[1]); err != nil {
			fail("%v", err)
		}
		return
	}
	if len(arguments) != 1 {
		fail("expected exactly one hbbs or hbbr daemon argument")
	}
	if err := runDaemon(arguments[0]); err != nil {
		fail("%v", err)
	}
}
