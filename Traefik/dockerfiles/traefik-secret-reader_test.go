// SPDX-License-Identifier: MIT
// Copyright (c) 2025 it.særvices

package main

import (
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"time"
)

func writeFixture(t *testing.T, path string, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}

func TestReadSecretAcceptsOneStableRegularFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "secret")
	writeFixture(t, path, "valid-token")
	secret, err := readSecret(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(secret) != "valid-token" {
		t.Fatal("reader returned unexpected bytes")
	}
}

func TestValidateForwardedHeaderSourceUsesCanonicalIPParsing(t *testing.T) {
	valid := []string{
		"192.0.2.1",
		"10.0.0.0/8",
		"2001:db8::1",
		"2001:db8::/32",
		"::1",
	}
	for _, candidate := range valid {
		if err := validateForwardedHeaderSource(candidate); err != nil {
			t.Fatalf("valid forwarded-header source %q rejected: %v", candidate, err)
		}
	}
	invalid := []string{
		"1:2",
		":1",
		"1:",
		"1:2:3:4:5:6:7:8:9",
		"2001:0DB8::/32",
		"2001:db8::1/32",
		"192.168.1.1/24",
		"10.0.0.0/0",
		"2001:db8::/0",
		"fe80::1%eth0",
		" 10.0.0.0/8",
		"10.0.0.0/33",
	}
	for _, candidate := range invalid {
		if err := validateForwardedHeaderSource(candidate); err == nil {
			t.Fatalf("invalid forwarded-header source %q accepted", candidate)
		}
	}
}

func TestReadSecretRejectsUnsafeNodesAndContent(t *testing.T) {
	fixtures := []struct {
		name    string
		content string
	}{
		{name: "placeholder", content: "CHANGE_ME"},
		{name: "spaces", content: "   "},
		{name: "newline", content: "token\n"},
		{name: "control", content: "token\x00value"},
		{name: "invalid-utf8", content: string([]byte{0xff, 0xfe})},
		{name: "unicode", content: "tökén"},
		{name: "delete-control", content: "token\x7fvalue"},
	}
	for _, fixture := range fixtures {
		t.Run(fixture.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "secret")
			writeFixture(t, path, fixture.content)
			if _, err := readSecret(path); err == nil {
				t.Fatal("unsafe content was accepted")
			}
		})
	}

	directory := t.TempDir()
	target := filepath.Join(directory, "target")
	writeFixture(t, target, "valid-token")
	symlink := filepath.Join(directory, "symlink")
	if err := os.Symlink(target, symlink); err != nil {
		t.Fatal(err)
	}
	if _, err := readSecret(symlink); err == nil {
		t.Fatal("symlink was accepted")
	}
	hardlink := filepath.Join(directory, "hardlink")
	if err := os.Link(target, hardlink); err != nil {
		t.Fatal(err)
	}
	if _, err := readSecret(target); err == nil {
		t.Fatal("multiply linked file was accepted")
	}
}

func TestReadSecretRejectsFIFOWithoutBlocking(t *testing.T) {
	path := filepath.Join(t.TempDir(), "fifo")
	if err := syscall.Mkfifo(path, 0o600); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() {
		_, err := readSecret(path)
		done <- err
	}()
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("FIFO was accepted")
		}
	case <-time.After(time.Second):
		t.Fatal("FIFO validation blocked")
	}
}

func TestReadSecretRejectsInPlaceAndPathRaces(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "secret")
	writeFixture(t, path, "first-token")
	if _, err := readSecretWithHook(path, func() {
		writeFixture(t, path, "other-token")
	}); err == nil {
		t.Fatal("same-length in-place rewrite was accepted")
	}

	writeFixture(t, path, "first-token")
	replacement := filepath.Join(directory, "replacement")
	writeFixture(t, replacement, "first-token")
	if _, err := readSecretWithHook(path, func() {
		if err := os.Rename(replacement, path); err != nil {
			t.Fatal(err)
		}
	}); err == nil {
		t.Fatal("path replacement was accepted")
	}
}

func TestPublishSecretCreatesPrivateSingleLinkFile(t *testing.T) {
	directory := filepath.Join(t.TempDir(), "runtime")
	if err := publishSecret(directory, "DNS_API_TOKEN", []byte("valid-token")); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(filepath.Join(directory, "DNS_API_TOKEN"))
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 || info.Size() != int64(len("valid-token")) {
		t.Fatal("published secret has unexpected metadata")
	}
	if err := publishSecret(directory, "DNS_API_TOKEN", []byte("replacement")); err == nil {
		t.Fatal("existing runtime secret was replaced")
	}
}

func TestPublishSecretRejectsSameLengthDestinationRewrite(t *testing.T) {
	directory := filepath.Join(t.TempDir(), "runtime")
	originalHook := runtimeSecretBeforeFinalHook
	t.Cleanup(func() { runtimeSecretBeforeFinalHook = originalHook })
	runtimeSecretBeforeFinalHook = func(path string) {
		if err := os.WriteFile(path, []byte("other-token"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	if err := publishSecret(directory, "DNS_API_TOKEN", []byte("valid-token")); err == nil {
		t.Fatal("same-length runtime-secret rewrite was accepted")
	}
	runtimeSecretBeforeFinalHook = originalHook
}

func TestPublishSecretRejectsRewriteAfterDescriptorReadback(t *testing.T) {
	directory := filepath.Join(t.TempDir(), "runtime")
	originalHook := runtimeSecretAfterReadHook
	t.Cleanup(func() { runtimeSecretAfterReadHook = originalHook })
	runtimeSecretAfterReadHook = func(path string) {
		if err := os.WriteFile(path, []byte("other-token"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	if err := publishSecret(directory, "DNS_API_TOKEN", []byte("valid-token")); err == nil {
		t.Fatal("runtime-secret rewrite after descriptor readback was accepted")
	}
	runtimeSecretAfterReadHook = originalHook
}

func TestCopySecretToDestinationCreatesExclusiveVerifiedFile(t *testing.T) {
	directory := t.TempDir()
	destination := filepath.Join(directory, "DNS_API_TOKEN")
	secret := []byte("valid-migration-token")
	if err := copySecretToDestination(destination, secret); err != nil {
		t.Fatal(err)
	}
	content, err := os.ReadFile(destination)
	if err != nil {
		t.Fatal(err)
	}
	info, err := os.Lstat(destination)
	if err != nil {
		t.Fatal(err)
	}
	if string(content) != string(secret) || !info.Mode().IsRegular() || info.Mode().Perm() != 0o600 || info.Sys().(*syscall.Stat_t).Nlink != 1 {
		t.Fatal("exclusive migration destination changed bytes or metadata")
	}
	if err := copySecretToDestination(destination, []byte("replacement")); err == nil {
		t.Fatal("existing migration destination was overwritten")
	}
	content, err = os.ReadFile(destination)
	if err != nil || string(content) != string(secret) {
		t.Fatal("failed migration overwrite changed the existing destination")
	}
}

func TestCopySecretToDestinationRejectsSameLengthRewrite(t *testing.T) {
	directory := t.TempDir()
	destination := filepath.Join(directory, "DNS_API_TOKEN")
	originalHook := secretCopyBeforeFinalHook
	t.Cleanup(func() { secretCopyBeforeFinalHook = originalHook })
	secretCopyBeforeFinalHook = func(path string) {
		if err := os.WriteFile(path, []byte("other-migration-token"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	if err := copySecretToDestination(destination, []byte("valid-migration-token")); err == nil {
		t.Fatal("same-length migration-destination rewrite was accepted")
	}
	secretCopyBeforeFinalHook = originalHook
	content, err := os.ReadFile(destination)
	if err != nil || string(content) != "other-migration-token" {
		t.Fatal("failed migration verification deleted or changed the conflicting destination")
	}
}

func TestCopySecretToDestinationRejectsRewriteAfterDescriptorReadback(t *testing.T) {
	directory := t.TempDir()
	destination := filepath.Join(directory, "DNS_API_TOKEN")
	originalHook := secretCopyAfterReadHook
	t.Cleanup(func() { secretCopyAfterReadHook = originalHook })
	secretCopyAfterReadHook = func(path string) {
		if err := os.WriteFile(path, []byte("other-migration-token"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	if err := copySecretToDestination(destination, []byte("valid-migration-token")); err == nil {
		t.Fatal("migration rewrite after descriptor readback was accepted")
	}
	secretCopyAfterReadHook = originalHook
	content, err := os.ReadFile(destination)
	if err != nil || string(content) != "other-migration-token" {
		t.Fatal("failed post-read migration verification deleted or changed the conflicting destination")
	}
}

func TestCopySecretToDestinationRejectsUnsafeDestinationWithoutTargetMutation(t *testing.T) {
	directory := t.TempDir()
	target := filepath.Join(directory, "outside")
	writeFixture(t, target, "outside-sentinel")
	for _, kind := range []string{"symlink", "fifo"} {
		t.Run(kind, func(t *testing.T) {
			destination := filepath.Join(directory, "destination-"+kind)
			switch kind {
			case "symlink":
				if err := os.Symlink(target, destination); err != nil {
					t.Fatal(err)
				}
			case "fifo":
				if err := syscall.Mkfifo(destination, 0o600); err != nil {
					t.Fatal(err)
				}
			}
			done := make(chan error, 1)
			go func() { done <- copySecretToDestination(destination, []byte("valid-token")) }()
			select {
			case err := <-done:
				if err == nil {
					t.Fatal("unsafe existing migration destination was accepted")
				}
			case <-time.After(time.Second):
				t.Fatal("unsafe migration destination blocked")
			}
			content, err := os.ReadFile(target)
			if err != nil || string(content) != "outside-sentinel" {
				t.Fatal("unsafe migration destination changed the outside target")
			}
		})
	}
}

func TestHardenACMEStoreCreatesAndNormalizesPrivateFile(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "acme.json")
	if err := hardenACMEStore(path); err != nil {
		t.Fatal(err)
	}
	info, err := os.Lstat(path)
	if err != nil {
		t.Fatal(err)
	}
	if !info.Mode().IsRegular() || info.Mode().Perm() != 0o600 || info.Sys().(*syscall.Stat_t).Nlink != 1 {
		t.Fatal("created ACME store has unsafe metadata")
	}
	if err := os.WriteFile(path, []byte(`{"Account":{}}`), 0o660); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, 0o660); err != nil {
		t.Fatal(err)
	}
	if err := hardenACMEStore(path); err != nil {
		t.Fatal(err)
	}
	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	info, err = os.Lstat(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(content) != `{"Account":{}}` || info.Mode().Perm() != 0o600 {
		t.Fatal("existing ACME store was not normalized without content loss")
	}
}

func TestHardenACMEStoreRejectsUnsafeNodesWithoutBlocking(t *testing.T) {
	directory := t.TempDir()
	target := filepath.Join(directory, "target")
	writeFixture(t, target, "unchanged")
	symlink := filepath.Join(directory, "symlink")
	if err := os.Symlink(target, symlink); err != nil {
		t.Fatal(err)
	}
	hardlink := filepath.Join(directory, "hardlink")
	if err := os.Link(target, hardlink); err != nil {
		t.Fatal(err)
	}
	fifo := filepath.Join(directory, "fifo")
	if err := syscall.Mkfifo(fifo, 0o600); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{symlink, hardlink, fifo} {
		done := make(chan error, 1)
		go func(candidate string) { done <- hardenACMEStore(candidate) }(path)
		select {
		case err := <-done:
			if err == nil {
				t.Fatalf("unsafe ACME store accepted: %s", path)
			}
		case <-time.After(time.Second):
			t.Fatalf("unsafe ACME store validation blocked: %s", path)
		}
	}
}

func TestHardenACMEStoreRejectsAtomicPathReplacement(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "acme.json")
	original := filepath.Join(directory, "original.json")
	replacement := filepath.Join(directory, "replacement.json")
	writeFixture(t, path, "original")
	writeFixture(t, replacement, "different")
	err := hardenACMEStoreWithHook(path, func() {
		if renameErr := os.Rename(path, original); renameErr != nil {
			t.Fatal(renameErr)
		}
		if renameErr := os.Rename(replacement, path); renameErr != nil {
			t.Fatal(renameErr)
		}
	})
	if err == nil {
		t.Fatal("atomic ACME store path replacement was accepted")
	}
}

func TestHardenACMEStoreRejectsInPlaceAndParentRaces(t *testing.T) {
	t.Run("same-size-in-place", func(t *testing.T) {
		directory := t.TempDir()
		path := filepath.Join(directory, "acme.json")
		writeFixture(t, path, "original")
		err := hardenACMEStoreWithHook(path, func() {
			writeFixture(t, path, "modified")
		})
		if err == nil {
			t.Fatal("same-size ACME store mutation was accepted")
		}
	})

	t.Run("parent-replacement", func(t *testing.T) {
		root := t.TempDir()
		directory := filepath.Join(root, "acme")
		originalDirectory := filepath.Join(root, "acme.original")
		if err := os.Mkdir(directory, 0o700); err != nil {
			t.Fatal(err)
		}
		path := filepath.Join(directory, "acme.json")
		writeFixture(t, path, "original")
		err := hardenACMEStoreWithHook(path, func() {
			if renameErr := os.Rename(directory, originalDirectory); renameErr != nil {
				t.Fatal(renameErr)
			}
			if mkdirErr := os.Mkdir(directory, 0o700); mkdirErr != nil {
				t.Fatal(mkdirErr)
			}
			replacement := filepath.Join(directory, "acme.json")
			writeFixture(t, replacement, "outside!")
			if chmodErr := os.Chmod(replacement, 0o640); chmodErr != nil {
				t.Fatal(chmodErr)
			}
		})
		if err == nil {
			t.Fatal("ACME storage-parent replacement was accepted")
		}
		replacementInfo, statErr := os.Lstat(filepath.Join(directory, "acme.json"))
		if statErr != nil {
			t.Fatal(statErr)
		}
		if replacementInfo.Mode().Perm() != 0o640 {
			t.Fatal("replacement-parent ACME file was mutated")
		}
	})
}
