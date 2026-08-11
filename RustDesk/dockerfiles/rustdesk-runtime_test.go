// SPDX-License-Identifier: MIT
// Copyright (c) 2025 it.særvices
package main

import (
	"encoding/base64"
	"os"
	"path/filepath"
	"testing"
)

func TestEnsureKeyPairCreatesAndRepairsModes(t *testing.T) {
	directory := t.TempDir()
	if err := ensureKeyPairAt(directory, true); err != nil {
		t.Fatalf("initial key generation failed: %v", err)
	}

	privatePath := filepath.Join(directory, privateKeyName)
	publicPath := filepath.Join(directory, publicKeyName)
	privateEncoded, err := os.ReadFile(privatePath)
	if err != nil {
		t.Fatal(err)
	}
	publicEncoded, err := os.ReadFile(publicPath)
	if err != nil {
		t.Fatal(err)
	}
	privateDecoded, err := base64.StdEncoding.DecodeString(string(privateEncoded))
	if err != nil || len(privateDecoded) != 64 {
		t.Fatalf("unexpected private-key encoding")
	}
	publicDecoded, err := base64.StdEncoding.DecodeString(string(publicEncoded))
	if err != nil || len(publicDecoded) != 32 {
		t.Fatalf("unexpected public-key encoding")
	}

	if err := os.Chmod(privatePath, 0o660); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(publicPath, 0o660); err != nil {
		t.Fatal(err)
	}
	if err := ensureKeyPairAt(directory, true); err != nil {
		t.Fatalf("mode repair failed: %v", err)
	}
	privateMetadata, _ := os.Stat(privatePath)
	publicMetadata, _ := os.Stat(publicPath)
	if privateMetadata.Mode().Perm() != 0o600 {
		t.Fatalf("private-key mode = %04o, want 0600", privateMetadata.Mode().Perm())
	}
	if publicMetadata.Mode().Perm() != 0o644 {
		t.Fatalf("public-key mode = %04o, want 0644", publicMetadata.Mode().Perm())
	}
}

func TestEnsureKeyPairRejectsIncompletePair(t *testing.T) {
	directory := t.TempDir()
	if err := os.WriteFile(filepath.Join(directory, privateKeyName), []byte("invalid"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := ensureKeyPairAt(directory, true); err == nil {
		t.Fatal("incomplete key pair was accepted")
	}
}

func TestEnsureKeyPairRejectsSymlink(t *testing.T) {
	directory := t.TempDir()
	outside := filepath.Join(t.TempDir(), "outside")
	if err := os.WriteFile(outside, []byte("outside"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(directory, privateKeyName)); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, publicKeyName), []byte("invalid"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := ensureKeyPairAt(directory, true); err == nil {
		t.Fatal("symlinked private key was accepted")
	}
	content, err := os.ReadFile(outside)
	if err != nil {
		t.Fatal(err)
	}
	if string(content) != "outside" {
		t.Fatal("outside symlink target changed")
	}
}

func TestParseProcNet(t *testing.T) {
	content := "  sl  local_address rem_address   st\n" +
		"   0: 00000000:527C 00000000:0000 0A\n" +
		"   1: 00000000:527D 00000000:0000 01\n"
	ports := parseProcNet(content, "0A")
	if !ports[21116] {
		t.Fatal("expected listening port 21116")
	}
	if ports[21117] {
		t.Fatal("accepted a non-listening socket")
	}
}
