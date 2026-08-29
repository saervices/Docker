// SPDX-License-Identifier: MIT
// Copyright (c) 2025 it.særvices

package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

func writeTestSecret(t *testing.T, path string, value []byte) {
	t.Helper()
	if err := os.WriteFile(path, value, 0o640); err != nil {
		t.Fatal(err)
	}
}

func TestReadStableSecret(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "SECRET")
	writeTestSecret(t, path, []byte("valid secret value"))
	value, err := readStableSecret(directory, "SECRET")
	if err != nil {
		t.Fatal(err)
	}
	defer wipe(value)
	if string(value) != "valid secret value" {
		t.Fatalf("unexpected secret value length: %d", len(value))
	}
}

func TestRejectsUnsafeNodesWithoutBlocking(t *testing.T) {
	directory := t.TempDir()
	target := filepath.Join(directory, "target")
	writeTestSecret(t, target, []byte("valid-secret"))
	if err := os.Symlink(target, filepath.Join(directory, "symlink")); err != nil {
		t.Fatal(err)
	}
	if err := os.Link(target, filepath.Join(directory, "hardlink")); err != nil {
		t.Fatal(err)
	}
	if err := syscall.Mkfifo(filepath.Join(directory, "fifo"), 0o640); err != nil {
		t.Fatal(err)
	}

	for _, name := range []string{"target", "symlink", "hardlink", "fifo"} {
		t.Run(name, func(t *testing.T) {
			done := make(chan error, 1)
			go func() {
				_, err := readStableSecret(directory, name)
				done <- err
			}()
			select {
			case err := <-done:
				if err == nil {
					t.Fatalf("unsafe node %s was accepted", name)
				}
			case <-time.After(time.Second):
				t.Fatalf("unsafe node %s blocked the reader", name)
			}
		})
	}
}

func TestRejectsDirectorySymlink(t *testing.T) {
	directory := t.TempDir()
	writeTestSecret(t, filepath.Join(directory, "SECRET"), []byte("valid-secret"))
	root := t.TempDir()
	link := filepath.Join(root, "secrets")
	if err := os.Symlink(directory, link); err != nil {
		t.Fatal(err)
	}
	if _, err := readStableSecret(link, "SECRET"); err == nil {
		t.Fatal("symlinked secret directory was accepted")
	}
}

func TestRejectsMalformedValues(t *testing.T) {
	for name, value := range map[string][]byte{
		"empty":          {},
		"placeholder":    []byte("CHANGE_ME"),
		"newline":        []byte("secret\n"),
		"control":        []byte("secret\x01value"),
		"invalid-utf8":   {0xff, 0xfe},
		"line-separator": []byte("secret\u2028value"),
		"oversized":      bytes.Repeat([]byte("x"), maximumSecretBytes+1),
	} {
		t.Run(name, func(t *testing.T) {
			directory := t.TempDir()
			writeTestSecret(t, filepath.Join(directory, "SECRET"), value)
			if _, err := readStableSecret(directory, "SECRET"); err == nil {
				t.Fatalf("malformed secret %s was accepted", name)
			}
		})
	}
}

func TestRejectsSameSizeMutation(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "SECRET")
	writeTestSecret(t, path, []byte("secret-one"))
	_, err := readStableSecretWithHook(directory, "SECRET", func() {
		writeTestSecret(t, path, []byte("secret-two"))
	})
	if err == nil {
		t.Fatal("same-size in-place mutation was accepted")
	}
}

func TestRejectsPathReplacement(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "SECRET")
	original := filepath.Join(directory, "SECRET.original")
	replacement := filepath.Join(directory, "SECRET.replacement")
	writeTestSecret(t, path, []byte("secret-one"))
	writeTestSecret(t, replacement, []byte("secret-two"))
	_, err := readStableSecretWithHook(directory, "SECRET", func() {
		if renameErr := os.Rename(path, original); renameErr != nil {
			t.Fatal(renameErr)
		}
		if renameErr := os.Rename(replacement, path); renameErr != nil {
			t.Fatal(renameErr)
		}
	})
	if err == nil {
		t.Fatal("secret path replacement was accepted")
	}
}

func TestRunDoesNotDiscloseSecretOnFailure(t *testing.T) {
	directory := t.TempDir()
	secret := "provider-client-secret-do-not-log"
	writeTestSecret(t, filepath.Join(directory, "SECRET"), []byte(secret+"\n"))
	var output bytes.Buffer
	var errors bytes.Buffer
	status := run([]string{"--directory", directory, "SECRET"}, &output, &errors)
	if status == 0 || output.Len() != 0 {
		t.Fatal("malformed secret unexpectedly reached stdout")
	}
	if strings.Contains(errors.String(), secret) {
		t.Fatal("secret content was disclosed in an error")
	}
}
