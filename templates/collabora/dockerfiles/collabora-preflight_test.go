// SPDX-License-Identifier: MIT
// Copyright (c) 2025 it.særvices

package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
)

func TestValidateKeyPair(t *testing.T) {
	privateOne, publicOne := generateKeyPair(t, 2048)
	privateTwo, publicTwo := generateKeyPair(t, 2048)
	privatePKCS1, publicPKCS1 := generatePKCS1KeyPair(t, 2048)
	privateECDSA, publicECDSA := generateECDSAKeyPair(t)
	tweak := append([]byte(nil), publicOne...)
	tweak[len(tweak)/2] ^= 1

	tests := []struct {
		name       string
		privatePEM []byte
		publicPEM  []byte
		prepare    func(t *testing.T, privatePath, publicPath string)
		wantError  bool
	}{
		{name: "valid", privatePEM: privateOne, publicPEM: publicOne},
		{name: "valid-pkcs1", privatePEM: privatePKCS1, publicPEM: publicPKCS1},
		{name: "missing-private", privatePEM: privateOne, publicPEM: publicOne, wantError: true, prepare: removePrivate},
		{name: "missing-public", privatePEM: privateOne, publicPEM: publicOne, wantError: true, prepare: removePublic},
		{name: "empty-private", privatePEM: nil, publicPEM: publicOne, wantError: true},
		{name: "empty-public", privatePEM: privateOne, publicPEM: nil, wantError: true},
		{name: "placeholder-private", privatePEM: []byte("CHANGE_ME"), publicPEM: publicOne, wantError: true},
		{name: "placeholder-public", privatePEM: privateOne, publicPEM: []byte("CHANGE_ME"), wantError: true},
		{name: "malformed-private", privatePEM: []byte("not-a-key"), publicPEM: publicOne, wantError: true},
		{name: "malformed-public", privatePEM: privateOne, publicPEM: []byte("not-a-key"), wantError: true},
		{name: "corrupt-public", privatePEM: privateOne, publicPEM: tweak, wantError: true},
		{name: "mismatched-pair", privatePEM: privateOne, publicPEM: publicTwo, wantError: true},
		{name: "trailing-private-data", privatePEM: append(privateOne, []byte("unexpected")...), publicPEM: publicOne, wantError: true},
		{name: "trailing-public-data", privatePEM: privateOne, publicPEM: append(publicOne, []byte("unexpected")...), wantError: true},
		{name: "private-symlink", privatePEM: privateOne, publicPEM: publicOne, wantError: true, prepare: symlinkPrivate},
		{name: "public-symlink", privatePEM: privateOne, publicPEM: publicOne, wantError: true, prepare: symlinkPublic},
		{name: "private-fifo", privatePEM: privateOne, publicPEM: publicOne, wantError: true, prepare: fifoPrivate},
		{name: "public-fifo", privatePEM: privateOne, publicPEM: publicOne, wantError: true, prepare: fifoPublic},
		{name: "oversized-private", privatePEM: []byte(strings.Repeat("x", maximumKeySize+1)), publicPEM: publicOne, wantError: true},
		{name: "oversized-public", privatePEM: privateOne, publicPEM: []byte(strings.Repeat("x", maximumKeySize+1)), wantError: true},
		{name: "encrypted-private", privatePEM: pem.EncodeToMemory(&pem.Block{Type: "ENCRYPTED PRIVATE KEY", Bytes: []byte("encrypted")}), publicPEM: publicOne, wantError: true},
		{name: "non-rsa-private", privatePEM: privateECDSA, publicPEM: publicOne, wantError: true},
		{name: "non-rsa-public", privatePEM: privateOne, publicPEM: publicECDSA, wantError: true},
		{name: "second-private-key", privatePEM: append(privateOne, privateTwo...), publicPEM: publicOne, wantError: true},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			directory := t.TempDir()
			privatePath := filepath.Join(directory, "proof_key")
			publicPath := filepath.Join(directory, "proof_key.pub")
			writeFile(t, privatePath, test.privatePEM)
			writeFile(t, publicPath, test.publicPEM)
			if test.prepare != nil {
				test.prepare(t, privatePath, publicPath)
			}

			err := validateKeyPair(privatePath, publicPath)
			if test.wantError && err == nil {
				t.Fatal("expected validation failure")
			}
			if !test.wantError && err != nil {
				t.Fatalf("unexpected validation failure: %v", err)
			}
		})
	}
}

func TestRejectsWeakRSAKey(t *testing.T) {
	privatePEM, publicPEM := generateKeyPair(t, 1024)
	directory := t.TempDir()
	privatePath := filepath.Join(directory, "proof_key")
	publicPath := filepath.Join(directory, "proof_key.pub")
	writeFile(t, privatePath, privatePEM)
	writeFile(t, publicPath, publicPEM)
	if err := validateKeyPair(privatePath, publicPath); err == nil {
		t.Fatal("expected weak RSA key to fail")
	}
}

func TestVendorCommandBaseMatchesCurrentShelllessImage(t *testing.T) {
	want := []string{
		"/usr/bin/coolwsd",
		"--use-env-vars",
		"--o:sys_template_path=/opt/cool/systemplate",
		"--o:child_root_path=/opt/cool/child-roots",
		"--o:file_server_root_path=/usr/share/coolwsd",
		"--o:cache_files.path=/opt/cool/cache",
		"--o:logging.color=false",
		"--o:stop_on_config_change=true",
	}
	if strings.Join(vendorCommandBase, "\x00") != strings.Join(want, "\x00") {
		t.Fatalf("unexpected vendor command base: %#v", vendorCommandBase)
	}
}

func TestBuildVendorCommandAppendsExtrasAndMandatoryOptions(t *testing.T) {
	want := append([]string{}, vendorCommandBase...)
	want = append(want, "--o:logging.level=warning", "--o:net.proto=IPv4")
	want = append(want, mandatoryParams...)

	got, err := buildVendorCommand("--o:logging.level=warning --o:net.proto=IPv4")
	if err != nil {
		t.Fatalf("unexpected command validation failure: %v", err)
	}
	if strings.Join(got, "\x00") != strings.Join(want, "\x00") {
		t.Fatalf("unexpected effective command: %#v", got)
	}
}

func TestParseExtraParams(t *testing.T) {
	tests := []struct {
		name      string
		raw       string
		want      []string
		wantError bool
	}{
		{name: "empty"},
		{name: "valid", raw: "--o:logging.level=warning --o:net.proto=IPv4", want: []string{"--o:logging.level=warning", "--o:net.proto=IPv4"}},
		{name: "shell-syntax-remains-literal", raw: "--o:logging.file=$(touch_/tmp/never)", want: []string{"--o:logging.file=$(touch_/tmp/never)"}},
		{name: "non-option", raw: "--version", wantError: true},
		{name: "missing-key", raw: "--o:=value", wantError: true},
		{name: "missing-value-separator", raw: "--o:logging.level", wantError: true},
		{name: "reserved-ssl-enable", raw: "--o:ssl.enable=true", wantError: true},
		{name: "reserved-ssl-termination", raw: "--o:ssl.termination=false", wantError: true},
		{name: "reserved-mount-jail-tree", raw: "--o:mount_jail_tree=true", wantError: true},
		{name: "reserved-capabilities", raw: "--o:security.capabilities=true", wantError: true},
		{name: "reserved-system-template", raw: "--o:sys_template_path=/tmp/override", wantError: true},
		{name: "reserved-child-root", raw: "--o:child_root_path=/tmp/override", wantError: true},
		{name: "reserved-file-server-root", raw: "--o:file_server_root_path=/tmp/override", wantError: true},
		{name: "reserved-cache-path", raw: "--o:cache_files.path=/tmp/override", wantError: true},
		{name: "reserved-log-color", raw: "--o:logging.color=true", wantError: true},
		{name: "reserved-stop-on-config-change", raw: "--o:stop_on_config_change=false", wantError: true},
		{name: "duplicate-key", raw: "--o:logging.level=warning --o:logging.level=debug", wantError: true},
		{name: "newline", raw: "--o:logging.level=warning\n--o:net.proto=IPv4", wantError: true},
		{name: "tab", raw: "--o:logging.level=warning\t--o:net.proto=IPv4", wantError: true},
		{name: "null-byte", raw: "--o:logging.level=warning\x00", wantError: true},
		{name: "too-many", raw: strings.Repeat("--o:test.value=1 ", maximumExtraParamCount+1), wantError: true},
		{name: "oversized-option", raw: "--o:test.value=" + strings.Repeat("x", maximumExtraParamSize), wantError: true},
		{name: "oversized-total", raw: strings.Repeat(" ", maximumExtraParamsSize+1), wantError: true},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got, err := parseExtraParams(test.raw)
			if test.wantError && err == nil {
				t.Fatal("expected option validation failure")
			}
			if !test.wantError && err != nil {
				t.Fatalf("unexpected option validation failure: %v", err)
			}
			if !test.wantError && strings.Join(got, "\x00") != strings.Join(test.want, "\x00") {
				t.Fatalf("unexpected parsed options: %#v", got)
			}
		})
	}
}

func generateKeyPair(t *testing.T, bits int) ([]byte, []byte) {
	t.Helper()
	privateKey, err := rsa.GenerateKey(rand.Reader, bits)
	if err != nil {
		t.Fatalf("generate private key: %v", err)
	}
	privateDER, err := x509.MarshalPKCS8PrivateKey(privateKey)
	if err != nil {
		t.Fatalf("marshal private key: %v", err)
	}
	publicDER, err := x509.MarshalPKIXPublicKey(&privateKey.PublicKey)
	if err != nil {
		t.Fatalf("marshal public key: %v", err)
	}
	return pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: privateDER}),
		pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: publicDER})
}

func generatePKCS1KeyPair(t *testing.T, bits int) ([]byte, []byte) {
	t.Helper()
	privateKey, err := rsa.GenerateKey(rand.Reader, bits)
	if err != nil {
		t.Fatalf("generate PKCS1 private key: %v", err)
	}
	return pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(privateKey)}),
		pem.EncodeToMemory(&pem.Block{Type: "RSA PUBLIC KEY", Bytes: x509.MarshalPKCS1PublicKey(&privateKey.PublicKey)})
}

func generateECDSAKeyPair(t *testing.T) ([]byte, []byte) {
	t.Helper()
	privateKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("generate ECDSA private key: %v", err)
	}
	privateDER, err := x509.MarshalPKCS8PrivateKey(privateKey)
	if err != nil {
		t.Fatalf("marshal ECDSA private key: %v", err)
	}
	publicDER, err := x509.MarshalPKIXPublicKey(&privateKey.PublicKey)
	if err != nil {
		t.Fatalf("marshal ECDSA public key: %v", err)
	}
	return pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: privateDER}),
		pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: publicDER})
}

func writeFile(t *testing.T, path string, content []byte) {
	t.Helper()
	if err := os.WriteFile(path, content, 0o600); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
}

func removePrivate(t *testing.T, privatePath, _ string) {
	t.Helper()
	if err := os.Remove(privatePath); err != nil {
		t.Fatalf("remove private fixture: %v", err)
	}
}

func removePublic(t *testing.T, _, publicPath string) {
	t.Helper()
	if err := os.Remove(publicPath); err != nil {
		t.Fatalf("remove public fixture: %v", err)
	}
}

func symlinkPrivate(t *testing.T, privatePath, _ string) {
	t.Helper()
	target := privatePath + ".target"
	if err := os.Rename(privatePath, target); err != nil {
		t.Fatalf("move private fixture: %v", err)
	}
	if err := os.Symlink(target, privatePath); err != nil {
		t.Fatalf("symlink private fixture: %v", err)
	}
}

func symlinkPublic(t *testing.T, _, publicPath string) {
	t.Helper()
	target := publicPath + ".target"
	if err := os.Rename(publicPath, target); err != nil {
		t.Fatalf("move public fixture: %v", err)
	}
	if err := os.Symlink(target, publicPath); err != nil {
		t.Fatalf("symlink public fixture: %v", err)
	}
}

func fifoPrivate(t *testing.T, privatePath, _ string) {
	t.Helper()
	if err := os.Remove(privatePath); err != nil {
		t.Fatalf("remove private fixture: %v", err)
	}
	if err := syscall.Mkfifo(privatePath, 0o600); err != nil {
		t.Fatalf("create private FIFO: %v", err)
	}
}

func fifoPublic(t *testing.T, _, publicPath string) {
	t.Helper()
	if err := os.Remove(publicPath); err != nil {
		t.Fatalf("remove public fixture: %v", err)
	}
	if err := syscall.Mkfifo(publicPath, 0o600); err != nil {
		t.Fatalf("create public FIFO: %v", err)
	}
}
