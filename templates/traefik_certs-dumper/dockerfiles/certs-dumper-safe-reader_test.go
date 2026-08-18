// SPDX-License-Identifier: MIT
// Copyright (c) 2025 it.særvices

package main

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func testCertificatePair(t *testing.T, domain string, serial int64) ([]byte, []byte) {
	t.Helper()
	privateKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	template := &x509.Certificate{
		SerialNumber: big.NewInt(serial),
		Subject:      pkix.Name{CommonName: domain},
		DNSNames:     []string{domain},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature,
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &privateKey.PublicKey, privateKey)
	if err != nil {
		t.Fatal(err)
	}
	keyDER, err := x509.MarshalECPrivateKey(privateKey)
	if err != nil {
		t.Fatal(err)
	}
	return pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER})
}

func testACMEStore(t *testing.T, domain string, certificate []byte, key []byte) []byte {
	t.Helper()
	content, err := json.Marshal(map[string]*acmeStoredData{
		"default": {
			Certificates: []acmeCertificate{{
				Domain:      acmeDomain{Main: domain},
				Certificate: certificate,
				Key:         key,
			}},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	return content
}

func waitForFile(t *testing.T, path string, timeout time.Duration) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for {
		if _, err := os.Lstat(path); err == nil {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("timed out waiting for %s", path)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func setTestEnvironment(t *testing.T, values map[string]string) {
	t.Helper()
	for name, value := range values {
		previous, existed := os.LookupEnv(name)
		if err := os.Setenv(name, value); err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() {
			if existed {
				_ = os.Setenv(name, previous)
			} else {
				_ = os.Unsetenv(name)
			}
		})
	}
}

func mustWriteFile(t *testing.T, path string, content []byte, mode os.FileMode) {
	t.Helper()
	if err := os.WriteFile(path, content, mode); err != nil {
		t.Fatal(err)
	}
}

func destinationIdentity(t *testing.T, path string) string {
	t.Helper()
	info, err := os.Lstat(path)
	if err != nil {
		t.Fatal(err)
	}
	stat := info.Sys().(*syscall.Stat_t)
	return fmt.Sprintf("%d:%d", stat.Dev, stat.Ino)
}

func parentIdentity(t *testing.T, path string) string {
	t.Helper()
	return destinationIdentity(t, filepath.Dir(path))
}

func TestStableSourcesAndDestination(t *testing.T) {
	directory := t.TempDir()
	for _, testCase := range []struct {
		name    string
		kind    string
		content []byte
	}{
		{name: "dns-token", kind: "dns-token", content: []byte("token-._~123")},
		{name: "ssh-key", kind: "ssh-key", content: []byte("not-yet-format-validated")},
		{name: "empty-known-hosts", kind: "known-hosts", content: nil},
	} {
		t.Run(testCase.name, func(t *testing.T) {
			source := filepath.Join(directory, testCase.name+".source")
			destination := filepath.Join(directory, testCase.name+".destination")
			mustWriteFile(t, source, testCase.content, 0o600)
			mustWriteFile(t, destination, []byte("old"), 0o600)
			kind, err := kindByName(testCase.kind)
			if err != nil {
				t.Fatal(err)
			}
			content, err := readStableSource(source, kind)
			if err != nil {
				t.Fatal(err)
			}
			if err := writeStableDestination(destination, destinationIdentity(t, destination), content); err != nil {
				t.Fatal(err)
			}
			actual, err := os.ReadFile(destination)
			if err != nil {
				t.Fatal(err)
			}
			if string(actual) != string(testCase.content) {
				t.Fatalf("copied content mismatch: %q", actual)
			}
		})
	}
}

func TestDNSTokenRejectsMalformedContent(t *testing.T) {
	for _, content := range [][]byte{
		{},
		[]byte("CHANGE_ME"),
		[]byte("token value"),
		[]byte("token\n"),
		[]byte("tökén"),
		{0xff, 0xfe},
		{0x7f},
	} {
		if err := validateDNSToken(content); err == nil {
			t.Fatalf("malformed DNS token accepted: %x", content)
		}
	}
}

func TestSourceRejectsSymlinkHardlinkAndFIFO(t *testing.T) {
	directory := t.TempDir()
	kind, err := kindByName("dns-token")
	if err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(directory, "target")
	mustWriteFile(t, target, []byte("token"), 0o600)
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
		if _, err := readStableSource(path, kind); err == nil {
			t.Fatalf("unsafe source accepted: %s", path)
		}
	}
}

func TestSourceRejectsSameSizeAndPathRaces(t *testing.T) {
	kind, err := kindByName("dns-token")
	if err != nil {
		t.Fatal(err)
	}
	t.Run("same-size", func(t *testing.T) {
		directory := t.TempDir()
		path := filepath.Join(directory, "source")
		mustWriteFile(t, path, []byte("token-one"), 0o600)
		_, err := readStableSourceWithHook(path, kind, func() {
			mustWriteFile(t, path, []byte("token-two"), 0o600)
		})
		if err == nil {
			t.Fatal("same-size in-place mutation was accepted")
		}
	})
	t.Run("path-replacement", func(t *testing.T) {
		directory := t.TempDir()
		path := filepath.Join(directory, "source")
		original := filepath.Join(directory, "original")
		replacement := filepath.Join(directory, "replacement")
		mustWriteFile(t, path, []byte("token-one"), 0o600)
		mustWriteFile(t, replacement, []byte("token-two"), 0o600)
		_, err := readStableSourceWithHook(path, kind, func() {
			if renameErr := os.Rename(path, original); renameErr != nil {
				t.Fatal(renameErr)
			}
			if renameErr := os.Rename(replacement, path); renameErr != nil {
				t.Fatal(renameErr)
			}
		})
		if err == nil {
			t.Fatal("source path replacement was accepted")
		}
	})
}

func TestSourceSizeBounds(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "known-hosts")
	mustWriteFile(t, path, make([]byte, knownHostsMaximumBytes+1), 0o600)
	kind, err := kindByName("known-hosts")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := readStableSource(path, kind); err == nil {
		t.Fatal("oversized known_hosts source was accepted")
	}
}

func TestDestinationRejectsIdentityAndModeDrift(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "destination")
	mustWriteFile(t, path, nil, 0o600)
	identity := destinationIdentity(t, path)
	if err := os.Chmod(path, 0o640); err != nil {
		t.Fatal(err)
	}
	if err := writeStableDestination(path, identity, []byte("secret")); err == nil {
		t.Fatal("unsafe destination mode was accepted")
	}
	if err := os.Chmod(path, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := writeStableDestination(path, "0:0", []byte("secret")); err == nil {
		t.Fatal("wrong destination identity was accepted")
	}
}

func TestDestinationRejectsSameLengthRewriteAfterSync(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "destination")
	mustWriteFile(t, path, nil, 0o600)
	identity := destinationIdentity(t, path)
	originalHook := destinationBeforeFinalHook
	t.Cleanup(func() { destinationBeforeFinalHook = originalHook })
	destinationBeforeFinalHook = func(destination string) {
		if err := os.WriteFile(destination, []byte("bad-secret"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	if err := writeStableDestination(path, identity, []byte("new-secret")); err == nil {
		t.Fatal("same-length destination rewrite was accepted")
	}
	destinationBeforeFinalHook = originalHook
}

func TestDestinationRejectsRewriteAfterDescriptorReadback(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "destination")
	mustWriteFile(t, path, nil, 0o600)
	identity := destinationIdentity(t, path)
	originalHook := destinationAfterReadHook
	t.Cleanup(func() { destinationAfterReadHook = originalHook })
	destinationAfterReadHook = func(destination string) {
		if err := os.WriteFile(destination, []byte("bad-secret"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	if err := writeStableDestination(path, identity, []byte("new-secret")); err == nil {
		t.Fatal("destination rewrite after descriptor readback was accepted")
	}
	destinationAfterReadHook = originalHook
}

func TestDestinationRejectsPathAndParentSwapsWithoutBlockingOrMutation(t *testing.T) {
	for _, replacementKind := range []string{"regular", "symlink", "fifo"} {
		t.Run(replacementKind, func(t *testing.T) {
			directory := t.TempDir()
			path := filepath.Join(directory, "destination")
			original := filepath.Join(directory, "destination.original")
			outside := filepath.Join(directory, "outside")
			mustWriteFile(t, path, []byte("private-stage"), 0o600)
			mustWriteFile(t, outside, []byte("outside-unchanged"), 0o600)
			identity := destinationIdentity(t, path)
			done := make(chan error, 1)
			var hookErr error
			go func() {
				done <- writeStableDestinationWithHook(path, identity, []byte("new-secret"), func() {
					if err := os.Rename(path, original); err != nil {
						hookErr = err
						return
					}
					switch replacementKind {
					case "regular":
						hookErr = os.WriteFile(path, []byte("replacement-unchanged"), 0o600)
					case "symlink":
						if err := os.Symlink(outside, path); err != nil {
							hookErr = err
						}
					case "fifo":
						if err := syscall.Mkfifo(path, 0o600); err != nil {
							hookErr = err
						}
					}
				})
			}()
			select {
			case err := <-done:
				if err == nil {
					t.Fatal("destination replacement was accepted")
				}
			case <-time.After(time.Second):
				t.Fatal("destination replacement validation blocked")
			}
			if hookErr != nil {
				t.Fatal(hookErr)
			}
			outsideContent, err := os.ReadFile(outside)
			if err != nil || string(outsideContent) != "outside-unchanged" {
				t.Fatal("destination replacement mutated the outside file")
			}
			if replacementKind == "regular" {
				replacementContent, err := os.ReadFile(path)
				if err != nil || string(replacementContent) != "replacement-unchanged" {
					t.Fatal("regular destination replacement was mutated")
				}
			}
		})
	}

	t.Run("parent", func(t *testing.T) {
		root := t.TempDir()
		parent := filepath.Join(root, "private")
		originalParent := filepath.Join(root, "private.original")
		if err := os.Mkdir(parent, 0o700); err != nil {
			t.Fatal(err)
		}
		path := filepath.Join(parent, "destination")
		mustWriteFile(t, path, []byte("private-stage"), 0o600)
		identity := destinationIdentity(t, path)
		err := writeStableDestinationWithHook(path, identity, []byte("new-secret"), func() {
			if renameErr := os.Rename(parent, originalParent); renameErr != nil {
				t.Fatal(renameErr)
			}
			if mkdirErr := os.Mkdir(parent, 0o700); mkdirErr != nil {
				t.Fatal(mkdirErr)
			}
			mustWriteFile(t, path, []byte("replacement-unchanged"), 0o600)
		})
		if err == nil {
			t.Fatal("destination parent replacement was accepted")
		}
		replacementContent, readErr := os.ReadFile(path)
		if readErr != nil || string(replacementContent) != "replacement-unchanged" {
			t.Fatal("destination parent replacement was mutated")
		}
	})
}

func TestKnownHostsDigest(t *testing.T) {
	directory := t.TempDir()
	source := filepath.Join(directory, "known-hosts")
	content := []byte("mail.internal ssh-ed25519 AAAATEST\n")
	mustWriteFile(t, source, content, 0o600)
	expected := fmt.Sprintf("%x", sha256.Sum256(content))
	actual := fmt.Sprintf("%x", sha256.Sum256(content))
	if actual != expected {
		t.Fatalf("digest mismatch: %s", actual)
	}
	kind, err := kindByName("known-hosts")
	if err != nil {
		t.Fatal(err)
	}
	stable, err := readStableSource(source, kind)
	if err != nil {
		t.Fatal(err)
	}
	if fmt.Sprintf("%x", sha256.Sum256(stable)) != expected {
		t.Fatal("stable digest input changed")
	}
}

func TestHardenStateNodesCreatesAndNormalizes(t *testing.T) {
	directory := filepath.Join(t.TempDir(), ".ssh")
	if err := hardenDirectory(directory); err != nil {
		t.Fatal(err)
	}
	stateFile := filepath.Join(directory, "known_hosts")
	if err := hardenStateFile(stateFile); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(stateFile, []byte("mail.internal ssh-ed25519 AAAATEST\n"), 0o660); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(directory, 0o770); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(stateFile, 0o660); err != nil {
		t.Fatal(err)
	}
	if err := hardenDirectory(directory); err != nil {
		t.Fatal(err)
	}
	if err := hardenStateFile(stateFile); err != nil {
		t.Fatal(err)
	}
	directoryInfo, err := os.Lstat(directory)
	if err != nil {
		t.Fatal(err)
	}
	fileInfo, err := os.Lstat(stateFile)
	if err != nil {
		t.Fatal(err)
	}
	if directoryInfo.Mode().Perm() != 0o700 || fileInfo.Mode().Perm() != 0o600 {
		t.Fatal("state-node modes were not normalized")
	}
	content, err := os.ReadFile(stateFile)
	if err != nil {
		t.Fatal(err)
	}
	if string(content) != "mail.internal ssh-ed25519 AAAATEST\n" {
		t.Fatal("state-file content changed during hardening")
	}
}

func TestHardenStateNodesRejectUnsafeNodesWithoutBlocking(t *testing.T) {
	t.Run("directory", func(t *testing.T) {
		root := t.TempDir()
		target := filepath.Join(root, "target")
		if err := os.Mkdir(target, 0o700); err != nil {
			t.Fatal(err)
		}
		symlink := filepath.Join(root, "symlink")
		if err := os.Symlink(target, symlink); err != nil {
			t.Fatal(err)
		}
		fifo := filepath.Join(root, "fifo")
		if err := syscall.Mkfifo(fifo, 0o600); err != nil {
			t.Fatal(err)
		}
		for _, path := range []string{symlink, fifo} {
			done := make(chan error, 1)
			go func(candidate string) { done <- hardenDirectory(candidate) }(path)
			select {
			case err := <-done:
				if err == nil {
					t.Fatalf("unsafe state directory accepted: %s", path)
				}
			case <-time.After(time.Second):
				t.Fatalf("state-directory validation blocked: %s", path)
			}
		}
	})

	t.Run("file", func(t *testing.T) {
		root := t.TempDir()
		target := filepath.Join(root, "target")
		mustWriteFile(t, target, []byte("unchanged"), 0o600)
		symlink := filepath.Join(root, "symlink")
		if err := os.Symlink(target, symlink); err != nil {
			t.Fatal(err)
		}
		hardlink := filepath.Join(root, "hardlink")
		if err := os.Link(target, hardlink); err != nil {
			t.Fatal(err)
		}
		fifo := filepath.Join(root, "fifo")
		if err := syscall.Mkfifo(fifo, 0o600); err != nil {
			t.Fatal(err)
		}
		for _, path := range []string{symlink, hardlink, fifo} {
			done := make(chan error, 1)
			go func(candidate string) { done <- hardenStateFile(candidate) }(path)
			select {
			case err := <-done:
				if err == nil {
					t.Fatalf("unsafe state file accepted: %s", path)
				}
			case <-time.After(time.Second):
				t.Fatalf("state-file validation blocked: %s", path)
			}
		}
	})
}

func TestHardenStateNodesRejectAtomicReplacement(t *testing.T) {
	t.Run("directory-to-fifo", func(t *testing.T) {
		root := t.TempDir()
		path := filepath.Join(root, ".ssh")
		original := filepath.Join(root, ".ssh.original")
		if err := os.Mkdir(path, 0o700); err != nil {
			t.Fatal(err)
		}
		err := hardenDirectoryWithHook(path, func() {
			if renameErr := os.Rename(path, original); renameErr != nil {
				t.Fatal(renameErr)
			}
			if fifoErr := syscall.Mkfifo(path, 0o600); fifoErr != nil {
				t.Fatal(fifoErr)
			}
		})
		if err == nil {
			t.Fatal("directory-to-FIFO replacement was accepted")
		}
	})

	t.Run("file-to-symlink", func(t *testing.T) {
		root := t.TempDir()
		path := filepath.Join(root, "known_hosts")
		original := filepath.Join(root, "known_hosts.original")
		target := filepath.Join(root, "target")
		mustWriteFile(t, path, []byte("original"), 0o600)
		mustWriteFile(t, target, []byte("outside"), 0o644)
		err := hardenStateFileWithHook(path, func() {
			if renameErr := os.Rename(path, original); renameErr != nil {
				t.Fatal(renameErr)
			}
			if symlinkErr := os.Symlink(target, path); symlinkErr != nil {
				t.Fatal(symlinkErr)
			}
		})
		if err == nil {
			t.Fatal("file-to-symlink replacement was accepted")
		}
		content, readErr := os.ReadFile(target)
		if readErr != nil {
			t.Fatal(readErr)
		}
		if string(content) != "outside" {
			t.Fatal("replacement symlink target was mutated")
		}
	})
}

func TestRemovePrivateFileUsesPinnedParentAndIdentity(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "temporary")
	mustWriteFile(t, path, []byte("temporary"), 0o600)
	identity := destinationIdentity(t, path)
	if err := removePrivateFile(path, identity, parentIdentity(t, path)); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Lstat(path); !os.IsNotExist(err) {
		t.Fatal("identity-pinned private file still exists after cleanup")
	}
}

func TestRemovePrivateFileRejectsWrongIdentityAndUnsafeNodes(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "temporary")
	mustWriteFile(t, path, []byte("temporary"), 0o600)
	if err := removePrivateFile(path, "0:0", parentIdentity(t, path)); err == nil {
		t.Fatal("wrong cleanup identity was accepted")
	}
	if _, err := os.Lstat(path); err != nil {
		t.Fatal("wrong-identity cleanup removed the file")
	}
	target := filepath.Join(directory, "target")
	mustWriteFile(t, target, []byte("outside"), 0o600)
	symlink := filepath.Join(directory, "symlink")
	if err := os.Symlink(target, symlink); err != nil {
		t.Fatal(err)
	}
	if err := removePrivateFile(symlink, destinationIdentity(t, target), parentIdentity(t, symlink)); err == nil {
		t.Fatal("symlink cleanup target was accepted")
	}
	content, err := os.ReadFile(target)
	if err != nil {
		t.Fatal(err)
	}
	if string(content) != "outside" {
		t.Fatal("unsafe cleanup changed a foreign target")
	}
}

func TestRemovePrivateFileAllowsUnrelatedParentChurn(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "temporary")
	mustWriteFile(t, path, []byte("temporary"), 0o600)
	done := make(chan struct{})
	go func() {
		defer close(done)
		for index := 0; index < 200; index++ {
			churnPath := filepath.Join(directory, fmt.Sprintf("churn-%d", index))
			_ = os.WriteFile(churnPath, []byte("x"), 0o600)
			_ = os.Remove(churnPath)
		}
	}()
	if err := removePrivateFile(path, destinationIdentity(t, path), parentIdentity(t, path)); err != nil {
		t.Fatal(err)
	}
	<-done
}

func TestRemovePrivateFileQuarantineRejectsLastWindowReplacementWithoutDeletingIt(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "temporary")
	original := filepath.Join(directory, "temporary.original")
	mustWriteFile(t, path, []byte("expected-private-file"), 0o600)
	identity := destinationIdentity(t, path)
	parent := parentIdentity(t, path)

	err := removePrivateFileWithHook(path, identity, parent, func() {
		if renameErr := os.Rename(path, original); renameErr != nil {
			t.Fatal(renameErr)
		}
		mustWriteFile(t, path, []byte("replacement-sentinel"), 0o600)
	})
	if err == nil {
		t.Fatal("last-window private-file replacement was accepted")
	}
	replacement, readErr := os.ReadFile(path)
	if readErr != nil || string(replacement) != "replacement-sentinel" {
		t.Fatal("last-window replacement was deleted or changed")
	}
	originalContent, readErr := os.ReadFile(original)
	if readErr != nil || string(originalContent) != "expected-private-file" {
		t.Fatal("held original private file was deleted or changed after replacement")
	}
	matches, globErr := filepath.Glob(filepath.Join(directory, ".cleanup.*"))
	if globErr != nil || len(matches) != 0 {
		t.Fatalf("private-file cleanup left quarantine artifacts: %v", matches)
	}
}

func TestPrepareSSHStateBelowPinnedRoot(t *testing.T) {
	root := filepath.Join(t.TempDir(), "state")
	if err := os.Mkdir(root, 0o700); err != nil {
		t.Fatal(err)
	}
	rootFD, err := syscall.Open(root, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer syscall.Close(rootFD)
	if err := prepareSSHState(root, rootFD); err != nil {
		t.Fatal(err)
	}
	sshInfo, err := os.Lstat(filepath.Join(root, ".ssh"))
	if err != nil {
		t.Fatal(err)
	}
	knownHostsInfo, err := os.Lstat(filepath.Join(root, ".ssh", "known_hosts"))
	if err != nil {
		t.Fatal(err)
	}
	if sshInfo.Mode().Perm() != 0o700 || knownHostsInfo.Mode().Perm() != 0o600 {
		t.Fatal("pinned-root SSH state has unsafe modes")
	}
}

func TestPrepareSSHStateRejectsFinalSSHDirectoryReplacement(t *testing.T) {
	root := filepath.Join(t.TempDir(), "state")
	if err := os.Mkdir(root, 0o700); err != nil {
		t.Fatal(err)
	}
	rootFD, err := syscall.Open(root, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer syscall.Close(rootFD)
	original := filepath.Join(root, ".ssh.original")
	replacement := filepath.Join(root, ".ssh")
	err = prepareSSHStateWithHook(root, rootFD, func() {
		if renameErr := os.Rename(replacement, original); renameErr != nil {
			t.Fatal(renameErr)
		}
		if mkdirErr := os.Mkdir(replacement, 0o700); mkdirErr != nil {
			t.Fatal(mkdirErr)
		}
		mustWriteFile(t, filepath.Join(replacement, "known_hosts"), []byte("replacement\n"), 0o600)
		mustWriteFile(t, filepath.Join(replacement, "sentinel"), []byte("outside\n"), 0o600)
	})
	if err == nil {
		t.Fatal("final-window SSH-directory replacement was accepted")
	}
	content, readErr := os.ReadFile(filepath.Join(replacement, "sentinel"))
	if readErr != nil || string(content) != "outside\n" {
		t.Fatal("failed SSH-state validation changed the replacement directory")
	}
}

func TestKnownHostsDurabilityBarrierAndSyncFailure(t *testing.T) {
	root := filepath.Join(t.TempDir(), "state")
	if err := os.Mkdir(root, 0o700); err != nil {
		t.Fatal(err)
	}
	rootFD, err := syscall.Open(root, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		t.Fatal(err)
	}
	if err := prepareSSHState(root, rootFD); err != nil {
		syscall.Close(rootFD)
		t.Fatal(err)
	}
	syscall.Close(rootFD)
	knownHosts := filepath.Join(root, ".ssh", "known_hosts")
	mustWriteFile(t, knownHosts, []byte("mail.example.test ssh-ed25519 AAAATEST\n"), 0o600)
	if err := syncKnownHostsState(knownHosts); err != nil {
		t.Fatal(err)
	}
	originalSync := syncStateDescriptor
	t.Cleanup(func() { syncStateDescriptor = originalSync })
	syncCalls := 0
	syncStateDescriptor = func(int) error {
		syncCalls++
		return errors.New("injected state durability failure")
	}
	if err := syncKnownHostsState(knownHosts); err == nil || syncCalls != 1 {
		t.Fatal("known_hosts sync failure was not propagated before parent-state acknowledgement")
	}
	syncStateDescriptor = originalSync
	if content, err := os.ReadFile(knownHosts); err != nil || string(content) != "mail.example.test ssh-ed25519 AAAATEST\n" {
		t.Fatal("failed durability barrier changed known_hosts bytes")
	}
}

func TestPinnedParentStatePreparationRejectsUnsafeAndRacedNodes(t *testing.T) {
	t.Run("directory-race-to-fifo", func(t *testing.T) {
		root := t.TempDir()
		rootFD, err := syscall.Open(root, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
		if err != nil {
			t.Fatal(err)
		}
		defer syscall.Close(rootFD)
		path := filepath.Join(root, ".ssh")
		original := filepath.Join(root, ".ssh.original")
		if err := os.Mkdir(path, 0o700); err != nil {
			t.Fatal(err)
		}
		fd, _, hardenErr := openAndHardenDirectoryAtWithHook(rootFD, ".ssh", func() {
			if renameErr := os.Rename(path, original); renameErr != nil {
				t.Fatal(renameErr)
			}
			if fifoErr := syscall.Mkfifo(path, 0o600); fifoErr != nil {
				t.Fatal(fifoErr)
			}
		})
		if fd >= 0 {
			syscall.Close(fd)
		}
		if hardenErr == nil {
			t.Fatal("directory-to-FIFO swap below pinned root was accepted")
		}
	})

	t.Run("file-nodes-and-race", func(t *testing.T) {
		root := t.TempDir()
		rootFD, err := syscall.Open(root, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
		if err != nil {
			t.Fatal(err)
		}
		defer syscall.Close(rootFD)
		target := filepath.Join(root, "target")
		mustWriteFile(t, target, []byte("outside"), 0o600)
		for _, name := range []string{"symlink", "hardlink", "fifo"} {
			path := filepath.Join(root, name)
			switch name {
			case "symlink":
				if err := os.Symlink(target, path); err != nil {
					t.Fatal(err)
				}
			case "hardlink":
				if err := os.Link(target, path); err != nil {
					t.Fatal(err)
				}
			case "fifo":
				if err := syscall.Mkfifo(path, 0o600); err != nil {
					t.Fatal(err)
				}
			}
			done := make(chan error, 1)
			go func(candidate string) {
				fd, _, openErr := openAndHardenStateFileAt(rootFD, candidate, true)
				if fd >= 0 {
					syscall.Close(fd)
				}
				done <- openErr
			}(name)
			select {
			case openErr := <-done:
				if openErr == nil {
					t.Fatalf("unsafe pinned-parent state file accepted: %s", name)
				}
			case <-time.After(time.Second):
				t.Fatalf("pinned-parent state-file validation blocked: %s", name)
			}
		}

		path := filepath.Join(root, "known_hosts")
		original := filepath.Join(root, "known_hosts.original")
		mustWriteFile(t, path, []byte("original"), 0o600)
		fd, _, openErr := openAndHardenStateFileAtWithHook(rootFD, "known_hosts", true, func() {
			if renameErr := os.Rename(path, original); renameErr != nil {
				t.Fatal(renameErr)
			}
			if symlinkErr := os.Symlink(target, path); symlinkErr != nil {
				t.Fatal(symlinkErr)
			}
		})
		if fd >= 0 {
			syscall.Close(fd)
		}
		if openErr == nil {
			t.Fatal("state-file symlink swap below pinned parent was accepted")
		}
		content, readErr := os.ReadFile(target)
		if readErr != nil || string(content) != "outside" {
			t.Fatal("state-file swap mutated the outside target")
		}
	})
}

func TestStateLockWrapperProcess(t *testing.T) {
	if os.Getenv("CERTS_DUMPER_LOCK_WRAPPER_PROCESS") != "1" {
		return
	}
	lockPath := os.Getenv("CERTS_DUMPER_LOCK_PATH")
	hookScript := os.Getenv("CERTS_DUMPER_LOCK_HOOK_SCRIPT")
	hookMode := os.Getenv("CERTS_DUMPER_LOCK_RACE_HOOK")
	rootHook := func() {}
	lockHook := func() {}
	if hookMode == "root-replacement" {
		rootHook = func() {
			rootPath := filepath.Dir(lockPath)
			_ = os.Rename(rootPath, rootPath+".original")
			_ = os.Mkdir(rootPath, 0o700)
		}
	}
	if hookMode != "" && hookMode != "root-replacement" {
		lockHook = func() {
			original := lockPath + ".original"
			_ = os.Rename(lockPath, original)
			switch hookMode {
			case "lock-regular-swap":
				_ = os.WriteFile(lockPath, []byte("replacement-unchanged"), 0o600)
			case "lock-symlink-swap":
				_ = os.Symlink(os.Getenv("CERTS_DUMPER_LOCK_OUTSIDE"), lockPath)
			case "lock-fifo-swap":
				_ = syscall.Mkfifo(lockPath, 0o600)
			}
		}
	}
	if err := runWithStateLockWithHooks(
		lockPath,
		[]string{"/bin/sh", hookScript, "--mailcow-locked"},
		rootHook,
		lockHook,
	); err != nil {
		var supervisedExit childExitError
		if errors.As(err, &supervisedExit) {
			os.Exit(supervisedExit.status)
		}
		fmt.Fprintln(os.Stderr, err)
		os.Exit(91)
	}
	os.Exit(0)
}

func TestStateLockChildProcess(t *testing.T) {
	if os.Getenv("CERTS_DUMPER_LOCK_CHILD_PROCESS") != "1" {
		return
	}
	if err := validateStateLockContext(os.Getenv("CERTS_DUMPER_LOCK_PATH"), 3, 4); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(92)
	}
	marker := os.Getenv("CERTS_DUMPER_LOCK_MARKER")
	if marker != "" {
		if err := os.WriteFile(marker, []byte("locked"), 0o600); err != nil {
			os.Exit(93)
		}
	}
	release := os.Getenv("CERTS_DUMPER_LOCK_RELEASE")
	if release != "" {
		deadline := time.Now().Add(5 * time.Second)
		for {
			if _, err := os.Lstat(release); err == nil {
				break
			}
			if time.Now().After(deadline) {
				os.Exit(94)
			}
			time.Sleep(10 * time.Millisecond)
		}
	}
	os.Exit(0)
}

func TestStateLockExecContextAndMutualExclusion(t *testing.T) {
	fixture := t.TempDir()
	stateRoot := filepath.Join(fixture, "state")
	lockPath := filepath.Join(stateRoot, "mailcow-rollover.lock")
	hookScript := filepath.Join(fixture, "locked-hook.sh")
	marker := filepath.Join(fixture, "first.locked")
	release := filepath.Join(fixture, "first.release")
	mustWriteFile(t, hookScript, []byte("#!/bin/sh\nexec \"$CERTS_DUMPER_TEST_BINARY\" -test.run=^TestStateLockChildProcess$\n"), 0o700)
	baseEnvironment := append(os.Environ(),
		"CERTS_DUMPER_LOCK_WRAPPER_PROCESS=1",
		"CERTS_DUMPER_LOCK_CHILD_PROCESS=1",
		"CERTS_DUMPER_LOCK_PATH="+lockPath,
		"CERTS_DUMPER_LOCK_HOOK_SCRIPT="+hookScript,
		"CERTS_DUMPER_TEST_BINARY="+os.Args[0],
	)
	first := exec.Command(os.Args[0], "-test.run=^TestStateLockWrapperProcess$")
	first.Env = append(baseEnvironment,
		"CERTS_DUMPER_LOCK_MARKER="+marker,
		"CERTS_DUMPER_LOCK_RELEASE="+release,
	)
	if err := first.Start(); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(3 * time.Second)
	for {
		if _, err := os.Lstat(marker); err == nil {
			break
		}
		if time.Now().After(deadline) {
			_ = first.Process.Kill()
			t.Fatal("first helper-owned lock did not reach the validated child context")
		}
		time.Sleep(10 * time.Millisecond)
	}
	second := exec.Command(os.Args[0], "-test.run=^TestStateLockWrapperProcess$")
	second.Env = baseEnvironment
	secondDone := make(chan error, 1)
	go func() { secondDone <- second.Run() }()
	select {
	case err := <-secondDone:
		if err == nil {
			t.Fatal("concurrent state-lock wrapper unexpectedly succeeded")
		}
	case <-time.After(time.Second):
		_ = second.Process.Kill()
		t.Fatal("concurrent state-lock wrapper blocked instead of failing closed")
	}
	mustWriteFile(t, release, []byte("release"), 0o600)
	if err := first.Wait(); err != nil {
		t.Fatal(err)
	}
	lockInfo, err := os.Lstat(lockPath)
	if err != nil {
		t.Fatal(err)
	}
	if !lockInfo.Mode().IsRegular() || lockInfo.Mode().Perm() != 0o600 || lockInfo.Sys().(*syscall.Stat_t).Nlink != 1 {
		t.Fatal("helper-owned state lock has unsafe final metadata")
	}
}

func TestStateLockSupervisorCooperativelyTerminatesForegroundChildBeforeHookRollback(t *testing.T) {
	fixture := t.TempDir()
	stateRoot := filepath.Join(fixture, "state")
	lockPath := filepath.Join(stateRoot, "mailcow-rollover.lock")
	hookScript := filepath.Join(fixture, "locked-hook.sh")
	stubbornScript := filepath.Join(fixture, "stubborn-child.sh")
	childPIDPath := filepath.Join(fixture, "child.pid")
	rollbackPath := filepath.Join(fixture, "rollback.complete")
	lateMutationPath := filepath.Join(fixture, "late-mutation")
	mustWriteFile(t, stubbornScript, []byte(`#!/bin/sh
trap 'exit 143' TERM
printf '%s' "$$" >"$CERTS_DUMPER_STUBBORN_PID"
while :; do sleep 30; done
printf late >"$CERTS_DUMPER_LATE_MUTATION"
`), 0o700)
	mustWriteFile(t, hookScript, []byte(`#!/bin/sh
trap 'printf rollback >"$CERTS_DUMPER_ROLLBACK_COMPLETE"; exit 143' TERM
"$CERTS_DUMPER_STUBBORN_CHILD"
`), 0o700)
	command := exec.Command(os.Args[0], "-test.run=^TestStateLockWrapperProcess$")
	command.Env = append(os.Environ(),
		"CERTS_DUMPER_LOCK_WRAPPER_PROCESS=1",
		"CERTS_DUMPER_LOCK_PATH="+lockPath,
		"CERTS_DUMPER_LOCK_HOOK_SCRIPT="+hookScript,
		"CERTS_DUMPER_STUBBORN_CHILD="+stubbornScript,
		"CERTS_DUMPER_STUBBORN_PID="+childPIDPath,
		"CERTS_DUMPER_ROLLBACK_COMPLETE="+rollbackPath,
		"CERTS_DUMPER_LATE_MUTATION="+lateMutationPath,
	)
	if err := command.Start(); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(3 * time.Second)
	for {
		if _, err := os.Lstat(childPIDPath); err == nil {
			break
		}
		if time.Now().After(deadline) {
			_ = command.Process.Kill()
			t.Fatal("cooperative foreground child did not start")
		}
		time.Sleep(10 * time.Millisecond)
	}
	started := time.Now()
	if err := command.Process.Signal(syscall.SIGTERM); err != nil {
		t.Fatal(err)
	}
	waitError := command.Wait()
	if time.Since(started) > childTerminationTime+3*time.Second {
		t.Fatal("supervisor did not terminate and reap the foreground child promptly")
	}
	exitError, ok := waitError.(*exec.ExitError)
	if !ok || exitError.ExitCode() != 143 {
		t.Fatalf("supervised hook exit status = %v, want 143", waitError)
	}
	if content, err := os.ReadFile(rollbackPath); err != nil || string(content) != "rollback" {
		t.Fatal("hook rollback did not complete after foreground-child termination")
	}
	pidBytes, err := os.ReadFile(childPIDPath)
	if err != nil {
		t.Fatal(err)
	}
	childPID, err := strconv.Atoi(string(pidBytes))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Lstat(fmt.Sprintf("/proc/%d", childPID)); !os.IsNotExist(err) {
		t.Fatal("terminated foreground child survived the supervised hook")
	}
	if _, err := os.Lstat(lateMutationPath); !os.IsNotExist(err) {
		t.Fatal("terminated foreground child performed a late mutation")
	}
}

func TestTopLevelSupervisorSignalsLockedTransactionExactlyOnce(t *testing.T) {
	if err := enableChildSubreaper(); err != nil {
		t.Fatal(err)
	}
	fixture := t.TempDir()
	stateRoot := filepath.Join(fixture, "state")
	lockPath := filepath.Join(stateRoot, "mailcow-rollover.lock")
	outerHook := filepath.Join(fixture, "outer-hook.sh")
	lockedHook := filepath.Join(fixture, "locked-hook.sh")
	started := filepath.Join(fixture, "locked.started")
	signalsSeen := filepath.Join(fixture, "locked.signals")
	rollbackComplete := filepath.Join(fixture, "rollback.complete")
	mustWriteFile(t, lockedHook, []byte(`#!/bin/sh
on_term() {
  printf 'term\n' >>"$CERTS_DUMPER_LOCKED_SIGNALS"
  sleep 1
  printf 'rollback\n' >"$CERTS_DUMPER_ROLLBACK_COMPLETE"
  exit 143
}
trap on_term TERM
: >"$CERTS_DUMPER_LOCKED_STARTED"
while :; do sleep 30; done
`), 0o700)
	mustWriteFile(t, outerHook, []byte(`#!/bin/sh
"$CERTS_DUMPER_TEST_BINARY" -test.run=^TestStateLockWrapperProcess$
`), 0o700)
	environment := append(os.Environ(),
		"CERTS_DUMPER_LOCK_WRAPPER_PROCESS=1",
		"CERTS_DUMPER_LOCK_PATH="+lockPath,
		"CERTS_DUMPER_LOCK_HOOK_SCRIPT="+lockedHook,
		"CERTS_DUMPER_TEST_BINARY="+os.Args[0],
		"CERTS_DUMPER_LOCKED_STARTED="+started,
		"CERTS_DUMPER_LOCKED_SIGNALS="+signalsSeen,
		"CERTS_DUMPER_ROLLBACK_COMPLETE="+rollbackComplete,
	)
	supervisorSignals := make(chan os.Signal, 1)
	result := make(chan struct {
		interrupted bool
		err         error
	}, 1)
	go func() {
		interrupted, err := runSupervisedServiceChild([]string{"/bin/sh", outerHook}, environment, supervisorSignals)
		result <- struct {
			interrupted bool
			err         error
		}{interrupted: interrupted, err: err}
	}()
	waitForFile(t, started, 3*time.Second)
	supervisorSignals <- syscall.SIGTERM
	select {
	case outcome := <-result:
		if !outcome.interrupted || outcome.err != nil {
			t.Fatalf("top-level termination result = interrupted:%t error:%v", outcome.interrupted, outcome.err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("top-level supervisor did not wait for locked rollback")
	}
	if content, err := os.ReadFile(rollbackComplete); err != nil || string(content) != "rollback\n" {
		t.Fatal("locked rollback did not complete before top-level shutdown")
	}
	if content, err := os.ReadFile(signalsSeen); err != nil || string(content) != "term\n" {
		t.Fatalf("locked transaction signal record = %q, want exactly one TERM", content)
	}
	lockFD, err := syscall.Open(lockPath, syscall.O_RDWR|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer syscall.Close(lockFD)
	if err := syscall.Flock(lockFD, syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		t.Fatal("state lock remained held after supervised rollback")
	}
}

func TestDetachedServiceDescendantProcess(t *testing.T) {
	if os.Getenv("CERTS_DUMPER_DETACHED_DESCENDANT_PROCESS") != "1" {
		return
	}
	if _, err := syscall.Setsid(); err != nil {
		t.Fatal(err)
	}
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGTERM)
	defer signal.Stop(signals)
	if err := os.WriteFile(os.Getenv("CERTS_DUMPER_DETACHED_STARTED"), []byte(strconv.Itoa(os.Getpid())), 0o600); err != nil {
		t.Fatal(err)
	}
	<-signals
	if err := os.WriteFile(os.Getenv("CERTS_DUMPER_DETACHED_STOPPED"), []byte("term\n"), 0o600); err != nil {
		t.Fatal(err)
	}
}

func TestTopLevelSupervisorCooperativelySignalsAdoptedDetachedDescendant(t *testing.T) {
	if err := enableChildSubreaper(); err != nil {
		t.Fatal(err)
	}
	fixture := t.TempDir()
	parentScript := filepath.Join(fixture, "parent.sh")
	started := filepath.Join(fixture, "detached.started")
	stopped := filepath.Join(fixture, "detached.stopped")
	mustWriteFile(t, parentScript, []byte(`#!/bin/sh
trap 'exit 143' TERM
"$CERTS_DUMPER_TEST_BINARY" -test.run=^TestDetachedServiceDescendantProcess$ &
wait
`), 0o700)
	environment := append(os.Environ(),
		"CERTS_DUMPER_DETACHED_DESCENDANT_PROCESS=1",
		"CERTS_DUMPER_DETACHED_STARTED="+started,
		"CERTS_DUMPER_DETACHED_STOPPED="+stopped,
		"CERTS_DUMPER_TEST_BINARY="+os.Args[0],
	)
	supervisorSignals := make(chan os.Signal, 1)
	result := make(chan struct {
		interrupted bool
		err         error
	}, 1)
	go func() {
		interrupted, err := runSupervisedServiceChild([]string{"/bin/sh", parentScript}, environment, supervisorSignals)
		result <- struct {
			interrupted bool
			err         error
		}{interrupted: interrupted, err: err}
	}()
	waitForFile(t, started, 3*time.Second)
	pinnedPIDBytes, err := os.ReadFile(started)
	if err != nil {
		t.Fatal(err)
	}
	pinnedPID, err := strconv.Atoi(string(pinnedPIDBytes))
	if err != nil {
		t.Fatal(err)
	}
	supervisorSignals <- syscall.SIGTERM
	select {
	case outcome := <-result:
		if !outcome.interrupted || outcome.err != nil {
			t.Fatalf("detached-descendant termination result = interrupted:%t error:%v", outcome.interrupted, outcome.err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("top-level supervisor did not cooperatively retire the detached descendant")
	}
	if content, err := os.ReadFile(stopped); err != nil || string(content) != "term\n" {
		t.Fatal("detached descendant did not receive the cooperative TERM")
	}
	if _, err := os.Lstat(fmt.Sprintf("/proc/%d", pinnedPID)); !os.IsNotExist(err) {
		t.Fatal("detached descendant survived top-level supervisor shutdown")
	}
}

func TestSupervisorCapturesSignalBeforeChildStart(t *testing.T) {
	fixture := t.TempDir()
	marker := filepath.Join(fixture, "unexpected-child")
	script := filepath.Join(fixture, "must-not-run.sh")
	mustWriteFile(t, script, []byte("#!/bin/sh\n: >\"$CERTS_DUMPER_PRESTART_MARKER\"\n"), 0o700)
	rootFile, err := os.Open(fixture)
	if err != nil {
		t.Fatal(err)
	}
	defer rootFile.Close()
	lockPath := filepath.Join(fixture, "lock")
	mustWriteFile(t, lockPath, nil, 0o600)
	lockFile, err := os.OpenFile(lockPath, os.O_RDWR, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer lockFile.Close()
	previousMarker := os.Getenv("CERTS_DUMPER_PRESTART_MARKER")
	if err := os.Setenv("CERTS_DUMPER_PRESTART_MARKER", marker); err != nil {
		t.Fatal(err)
	}
	defer func() { _ = os.Setenv("CERTS_DUMPER_PRESTART_MARKER", previousMarker) }()
	err = waitForSupervisedHookWithHook(
		[]string{"/bin/sh", script, "--mailcow-locked"},
		rootFile,
		lockFile,
		func() {
			if signalErr := syscall.Kill(os.Getpid(), syscall.SIGTERM); signalErr != nil {
				t.Error(signalErr)
			}
			time.Sleep(50 * time.Millisecond)
		},
	)
	var supervisedExit childExitError
	if !errors.As(err, &supervisedExit) || supervisedExit.status != 143 {
		t.Fatalf("pre-start signal result = %v, want supervised exit 143", err)
	}
	if _, err := os.Lstat(marker); !os.IsNotExist(err) {
		t.Fatal("signal captured before Start still launched the hook child")
	}
}

func TestStateLockRejectsUnsafeNodesAndAtomicSwaps(t *testing.T) {
	for _, testCase := range []struct {
		name     string
		node     string
		raceHook string
	}{
		{name: "symlink", node: "symlink"},
		{name: "hardlink", node: "hardlink"},
		{name: "fifo", node: "fifo"},
		{name: "regular-swap", node: "regular", raceHook: "lock-regular-swap"},
		{name: "symlink-swap", node: "regular", raceHook: "lock-symlink-swap"},
		{name: "fifo-swap", node: "regular", raceHook: "lock-fifo-swap"},
		{name: "root-replacement", node: "regular", raceHook: "root-replacement"},
	} {
		t.Run(testCase.name, func(t *testing.T) {
			fixture := t.TempDir()
			stateRoot := filepath.Join(fixture, "state")
			if err := os.Mkdir(stateRoot, 0o700); err != nil {
				t.Fatal(err)
			}
			lockPath := filepath.Join(stateRoot, "mailcow-rollover.lock")
			outside := filepath.Join(fixture, "outside")
			mustWriteFile(t, outside, []byte("outside-unchanged"), 0o600)
			switch testCase.node {
			case "regular":
				mustWriteFile(t, lockPath, []byte("lock-unchanged"), 0o600)
			case "symlink":
				if err := os.Symlink(outside, lockPath); err != nil {
					t.Fatal(err)
				}
			case "hardlink":
				if err := os.Link(outside, lockPath); err != nil {
					t.Fatal(err)
				}
			case "fifo":
				if err := syscall.Mkfifo(lockPath, 0o600); err != nil {
					t.Fatal(err)
				}
			}
			hookScript := filepath.Join(fixture, "must-not-run.sh")
			marker := filepath.Join(fixture, "unexpected-child")
			mustWriteFile(t, hookScript, []byte("#!/bin/sh\n: >\"$CERTS_DUMPER_LOCK_MARKER\"\n"), 0o700)
			command := exec.Command(os.Args[0], "-test.run=^TestStateLockWrapperProcess$")
			command.Env = append(os.Environ(),
				"CERTS_DUMPER_LOCK_WRAPPER_PROCESS=1",
				"CERTS_DUMPER_LOCK_PATH="+lockPath,
				"CERTS_DUMPER_LOCK_HOOK_SCRIPT="+hookScript,
				"CERTS_DUMPER_LOCK_MARKER="+marker,
				"CERTS_DUMPER_LOCK_OUTSIDE="+outside,
				"CERTS_DUMPER_LOCK_RACE_HOOK="+testCase.raceHook,
			)
			done := make(chan error, 1)
			go func() { done <- command.Run() }()
			select {
			case err := <-done:
				if err == nil {
					t.Fatal("unsafe or raced state lock was accepted")
				}
			case <-time.After(time.Second):
				_ = command.Process.Kill()
				t.Fatal("unsafe or raced state-lock validation blocked")
			}
			if _, err := os.Lstat(marker); !os.IsNotExist(err) {
				t.Fatal("unsafe state lock reached the wrapped child")
			}
			outsideContent, err := os.ReadFile(outside)
			if err != nil || string(outsideContent) != "outside-unchanged" {
				t.Fatal("unsafe state-lock handling mutated an outside target")
			}
		})
	}
}

func waitForCondition(t *testing.T, timeout time.Duration, description string, condition func() bool) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for !condition() {
		if time.Now().After(deadline) {
			t.Fatalf("timed out waiting for %s", description)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func TestACMEStoreSemanticsAndReadySourceSafety(t *testing.T) {
	certificate, privateKey := testCertificatePair(t, "mailcow.example.test", 1001)
	validContent := testACMEStore(t, "mailcow.example.test", certificate, privateKey)

	t.Run("valid-and-empty-first-boot", func(t *testing.T) {
		directory := t.TempDir()
		path := filepath.Join(directory, "acme.json")
		mustWriteFile(t, path, nil, 0o600)
		if _, _, ready, err := readReadyACMESource(path); err != nil || ready {
			t.Fatalf("safe empty first-boot store = ready %v, error %v", ready, err)
		}
		mustWriteFile(t, path, validContent, 0o600)
		content, expected, ready, err := readReadyACMESource(path)
		if err != nil || !ready || !bytes.Equal(content, validContent) || len(expected.pairs) != 1 {
			t.Fatalf("valid ACME store was not ready: ready=%v err=%v", ready, err)
		}
	})

	t.Run("semantic-rejections", func(t *testing.T) {
		secondCertificate, secondKey := testCertificatePair(t, "mailcow.example.test", 1002)
		_ = secondCertificate
		cases := map[string][]byte{
			"invalid-json":     []byte(`{"broken":`),
			"certificate-free": []byte(`{"default":{"Certificates":[]}}`),
			"null-resolver":    []byte(`{"bad":null}`),
		}
		unsafeStore, err := json.Marshal(map[string]*acmeStoredData{
			"default": {Certificates: []acmeCertificate{{
				Domain: acmeDomain{Main: "../../data/files/escape"}, Certificate: certificate, Key: privateKey,
			}}},
		})
		if err != nil {
			t.Fatal(err)
		}
		cases["path-traversal"] = unsafeStore
		mismatchStore, err := json.Marshal(map[string]*acmeStoredData{
			"default": {Certificates: []acmeCertificate{{
				Domain: acmeDomain{Main: "mailcow.example.test"}, Certificate: certificate, Key: secondKey,
			}}},
		})
		if err != nil {
			t.Fatal(err)
		}
		cases["mismatched-key"] = mismatchStore
		for name, content := range cases {
			t.Run(name, func(t *testing.T) {
				if _, err := parseExpectedDumpTree(content); err == nil {
					t.Fatal("unsafe or vendor-incompatible ACME store was accepted")
				}
			})
		}
	})

	t.Run("unsafe-nodes-metadata-and-size", func(t *testing.T) {
		directory := t.TempDir()
		target := filepath.Join(directory, "target")
		mustWriteFile(t, target, validContent, 0o600)
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
		wrongMode := filepath.Join(directory, "wrong-mode")
		mustWriteFile(t, wrongMode, validContent, 0o640)
		oversized := filepath.Join(directory, "oversized")
		mustWriteFile(t, oversized, make([]byte, acmeStoreMaximumBytes+1), 0o600)
		paths := []string{symlink, hardlink, fifo, wrongMode, oversized}
		if os.Geteuid() == 0 {
			wrongOwner := filepath.Join(directory, "wrong-owner")
			mustWriteFile(t, wrongOwner, validContent, 0o600)
			if err := os.Chown(wrongOwner, 1, 1); err != nil {
				t.Fatal(err)
			}
			paths = append(paths, wrongOwner)
		}
		for _, path := range paths {
			done := make(chan error, 1)
			go func(candidate string) {
				_, _, _, err := readReadyACMESource(candidate)
				done <- err
			}(path)
			select {
			case err := <-done:
				if err == nil {
					t.Fatalf("unsafe ACME source was accepted: %s", path)
				}
			case <-time.After(time.Second):
				t.Fatalf("unsafe ACME source blocked: %s", path)
			}
		}
	})

	t.Run("same-size-and-parent-races", func(t *testing.T) {
		kind := sourceKind{maximumBytes: acmeStoreMaximumBytes, allowEmpty: true, validateMetadata: validateACMESourceMetadata}
		root := t.TempDir()
		parent := filepath.Join(root, "data")
		if err := os.Mkdir(parent, 0o700); err != nil {
			t.Fatal(err)
		}
		path := filepath.Join(parent, "acme.json")
		mustWriteFile(t, path, validContent, 0o600)
		mutated := append([]byte(nil), validContent...)
		mutated[len(mutated)-1] ^= 1
		if _, err := readStableChildSourceWithHook(parent, "acme.json", kind, func() {
			mustWriteFile(t, path, mutated, 0o600)
		}); err == nil {
			t.Fatal("same-size ACME mutation was accepted")
		}
		mustWriteFile(t, path, validContent, 0o600)
		originalParent := filepath.Join(root, "data.original")
		if _, err := readStableChildSourceWithHook(parent, "acme.json", kind, func() {
			if renameErr := os.Rename(parent, originalParent); renameErr != nil {
				t.Fatal(renameErr)
			}
			if mkdirErr := os.Mkdir(parent, 0o700); mkdirErr != nil {
				t.Fatal(mkdirErr)
			}
			mustWriteFile(t, filepath.Join(parent, "acme.json"), validContent, 0o600)
		}); err == nil {
			t.Fatal("ACME parent replacement was accepted")
		}
	})
}

func TestSupervisorReadyMetadataIsPrivateAndNonBlocking(t *testing.T) {
	directory := t.TempDir()
	digest := strings.Repeat("a", sha256.Size*2)
	content := []byte(fmt.Sprintf("%s generation-%s\n", digest, digest))
	kind, err := kindByName("supervisor-ready")
	if err != nil {
		t.Fatal(err)
	}
	valid := filepath.Join(directory, "ready")
	mustWriteFile(t, valid, content, 0o600)
	if _, err := readStableSource(valid, kind); err != nil {
		t.Fatal(err)
	}
	wrongMode := filepath.Join(directory, "wrong-mode")
	mustWriteFile(t, wrongMode, content, 0o640)
	target := filepath.Join(directory, "target")
	mustWriteFile(t, target, content, 0o600)
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
	for _, path := range []string{wrongMode, symlink, hardlink, fifo} {
		done := make(chan error, 1)
		go func(candidate string) {
			_, err := readStableSource(candidate, kind)
			done <- err
		}(path)
		select {
		case err := <-done:
			if err == nil {
				t.Fatalf("unsafe readiness record was accepted: %s", path)
			}
		case <-time.After(time.Second):
			t.Fatalf("unsafe readiness record blocked: %s", path)
		}
	}
}

func TestGenerationCommitRollbackAndStrictValidation(t *testing.T) {
	certificateA, keyA := testCertificatePair(t, "a.example.test", 2001)
	certificateB, keyB := testCertificatePair(t, "b.example.test", 2002)
	contentA := testACMEStore(t, "a.example.test", certificateA, keyA)
	contentB := testACMEStore(t, "b.example.test", certificateB, keyB)
	expectedA, err := parseExpectedDumpTree(contentA)
	if err != nil {
		t.Fatal(err)
	}
	expectedB, err := parseExpectedDumpTree(contentB)
	if err != nil {
		t.Fatal(err)
	}
	output := filepath.Join(t.TempDir(), "files")
	if err := os.Mkdir(output, 0o700); err != nil {
		t.Fatal(err)
	}
	nameA := fmt.Sprintf("generation-%x", sha256.Sum256(contentA))
	nameB := fmt.Sprintf("generation-%x", sha256.Sum256(contentB))
	if _, created, err := publishGeneration(output, nameA, expectedA); err != nil || !created {
		t.Fatalf("publish generation A: created=%v err=%v", created, err)
	}
	if _, _, err := setCurrentGeneration(output, nameA); err != nil {
		t.Fatal(err)
	}
	if _, created, err := publishGeneration(output, nameB, expectedB); err != nil || !created {
		t.Fatalf("publish generation B: created=%v err=%v", created, err)
	}

	originalSync := syncCurrentDirectory
	t.Cleanup(func() { syncCurrentDirectory = originalSync })
	failedOnce := false
	syncCurrentDirectory = func(fd int) error {
		if !failedOnce {
			failedOnce = true
			return errors.New("injected current fsync failure")
		}
		return syscall.Fsync(fd)
	}
	if _, _, err := setCurrentGeneration(output, nameB); err == nil {
		t.Fatal("injected post-rename fsync failure was ignored")
	}
	syncCurrentDirectory = originalSync
	rootFD, err := openOutputRoot(output)
	if err != nil {
		t.Fatal(err)
	}
	current, exists, err := currentGenerationTarget(rootFD)
	syscall.Close(rootFD)
	if err != nil || !exists || current != nameA {
		t.Fatalf("current pointer was not rolled back to generation A: %q %v", current, err)
	}
	if err := validatePublishedGeneration(filepath.Join(output, nameA), expectedA); err != nil {
		t.Fatal(err)
	}
	if err := validatePublishedGeneration(filepath.Join(output, nameB), expectedB); err != nil {
		t.Fatal(err)
	}

	originalAfterSyncHook := currentPublicationAfterSyncHook
	t.Cleanup(func() { currentPublicationAfterSyncHook = originalAfterSyncHook })
	currentPublicationAfterSyncHook = func() error { return errors.New("injected final current validation failure") }
	if _, _, err := setCurrentGeneration(output, nameB); err == nil {
		t.Fatal("injected post-fsync validation failure was ignored")
	}
	currentPublicationAfterSyncHook = originalAfterSyncHook
	rootFD, err = openOutputRoot(output)
	if err != nil {
		t.Fatal(err)
	}
	current, exists, err = currentGenerationTarget(rootFD)
	syscall.Close(rootFD)
	if err != nil || !exists || current != nameA {
		t.Fatalf("post-fsync failure did not restore generation A: %q %v", current, err)
	}

	if err := cleanupGenerationArtifacts(output, map[string]bool{}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Lstat(filepath.Join(output, nameA)); err != nil {
		t.Fatal("cleanup removed the generation referenced by current")
	}
	if _, err := os.Lstat(filepath.Join(output, nameB)); !os.IsNotExist(err) {
		t.Fatal("cleanup retained an unreferenced generation")
	}
	if _, created, err := publishGeneration(output, nameB, expectedB); err != nil || !created {
		t.Fatalf("republish generation B for rollback-failure test: created=%v err=%v", created, err)
	}
	syncCurrentDirectory = func(int) error { return errors.New("injected commit and rollback fsync failure") }
	_, _, rollbackFailure := setCurrentGeneration(output, nameB)
	syncCurrentDirectory = originalSync
	if rollbackFailure == nil || !strings.Contains(rollbackFailure.Error(), "pointer rollback failed") {
		t.Fatalf("double fsync failure did not report combined commit/rollback error: %v", rollbackFailure)
	}
	rootFD, err = openOutputRoot(output)
	if err != nil {
		t.Fatal(err)
	}
	current, exists, err = currentGenerationTarget(rootFD)
	syscall.Close(rootFD)
	if err != nil || !exists || (current != nameA && current != nameB) {
		t.Fatalf("rollback failure left an invalid current pointer: %q %v", current, err)
	}
	if _, err := os.Lstat(filepath.Join(output, current)); err != nil {
		t.Fatal("rollback failure left current dangling")
	}
	if err := validatePublishedGeneration(filepath.Join(output, nameA), expectedA); err != nil {
		t.Fatal("rollback failure removed or changed prior generation")
	}
	if err := validatePublishedGeneration(filepath.Join(output, nameB), expectedB); err != nil {
		t.Fatal("rollback failure removed or changed new generation")
	}

	for _, replacementKind := range []string{"symlink", "regular"} {
		t.Run("current-cas-preserves-"+replacementKind+"-replacement", func(t *testing.T) {
			casOutput := filepath.Join(t.TempDir(), "files")
			if err := os.Mkdir(casOutput, 0o700); err != nil {
				t.Fatal(err)
			}
			if _, _, err := publishGeneration(casOutput, nameA, expectedA); err != nil {
				t.Fatal(err)
			}
			if _, _, err := publishGeneration(casOutput, nameB, expectedB); err != nil {
				t.Fatal(err)
			}
			if _, _, err := setCurrentGeneration(casOutput, nameA); err != nil {
				t.Fatal(err)
			}
			currentPath := filepath.Join(casOutput, "current")
			savedPath := filepath.Join(casOutput, "current.saved")
			originalBefore, err := os.Lstat(currentPath)
			if err != nil {
				t.Fatal(err)
			}
			originalHook := currentBeforeRenameHook
			t.Cleanup(func() { currentBeforeRenameHook = originalHook })
			currentBeforeRenameHook = func(int) {
				if err := os.Rename(currentPath, savedPath); err != nil {
					t.Error(err)
					return
				}
				if replacementKind == "symlink" {
					if err := os.Symlink(nameA, currentPath); err != nil {
						t.Error(err)
					}
				} else {
					mustWriteFile(t, currentPath, []byte("foreign-current"), 0o600)
				}
			}
			if _, _, err := setCurrentGeneration(casOutput, nameB); err == nil {
				t.Fatal("current compare-and-swap accepted a final-window replacement")
			}
			currentBeforeRenameHook = originalHook
			replacementAfter, err := os.Lstat(currentPath)
			if err != nil {
				t.Fatal("current replacement was removed")
			}
			if replacementKind == "symlink" {
				target, err := os.Readlink(currentPath)
				if err != nil || target != nameA || replacementAfter.Sys().(*syscall.Stat_t).Ino == originalBefore.Sys().(*syscall.Stat_t).Ino {
					t.Fatal("replacement current symlink was not preserved exactly")
				}
			} else if content, err := os.ReadFile(currentPath); err != nil || string(content) != "foreign-current" {
				t.Fatal("replacement current regular file was not preserved")
			}
			originalAfter, err := os.Lstat(savedPath)
			if err != nil || originalAfter.Sys().(*syscall.Stat_t).Ino != originalBefore.Sys().(*syscall.Stat_t).Ino {
				t.Fatal("original current symlink was changed outside its raced path")
			}
		})
	}

	driftRoot := filepath.Join(t.TempDir(), "generation")
	if err := os.Mkdir(driftRoot, 0o700); err != nil {
		t.Fatal(err)
	}
	driftDomain := filepath.Join(driftRoot, "a.example.test")
	if err := os.Mkdir(driftDomain, 0o750); err != nil {
		t.Fatal(err)
	}
	before, err := os.Lstat(driftDomain)
	if err != nil {
		t.Fatal(err)
	}
	if err := validatePublishedGeneration(driftRoot, expectedA); err == nil {
		t.Fatal("drifted existing generation directory was accepted")
	}
	after, err := os.Lstat(driftDomain)
	if err != nil || after.Mode().Perm() != before.Mode().Perm() {
		t.Fatal("strict generation validation mutated a drifted directory")
	}
}

func TestGenerationCleanupIsTwoPhaseAndReplacementSafe(t *testing.T) {
	certificate, privateKey := testCertificatePair(t, "a.example.test", 3001)
	content := testACMEStore(t, "a.example.test", certificate, privateKey)
	expected, err := parseExpectedDumpTree(content)
	if err != nil {
		t.Fatal(err)
	}
	output := filepath.Join(t.TempDir(), "files")
	if err := os.Mkdir(output, 0o700); err != nil {
		t.Fatal(err)
	}
	name := fmt.Sprintf("generation-%x", sha256.Sum256(content))
	if _, _, err := publishGeneration(output, name, expected); err != nil {
		t.Fatal(err)
	}
	generationInfo, err := os.Lstat(filepath.Join(output, name))
	if err != nil {
		t.Fatal(err)
	}
	foreign := filepath.Join(output, "legacy.example.test")
	mustWriteFile(t, foreign, []byte("foreign-unchanged"), 0o600)
	if err := cleanupGenerationArtifacts(output, map[string]bool{}); err == nil {
		t.Fatal("foreign output entry did not abort cleanup")
	}
	generationAfter, err := os.Lstat(filepath.Join(output, name))
	if err != nil || generationAfter.Sys().(*syscall.Stat_t).Ino != generationInfo.Sys().(*syscall.Stat_t).Ino {
		t.Fatal("two-phase cleanup mutated a recognized generation before rejecting foreign state")
	}
	if actual, err := os.ReadFile(foreign); err != nil || string(actual) != "foreign-unchanged" {
		t.Fatal("two-phase cleanup mutated the foreign entry")
	}

	parent := filepath.Join(t.TempDir(), "parent")
	if err := os.Mkdir(parent, 0o700); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(parent, "target")
	original := filepath.Join(parent, "target.original")
	replacement := filepath.Join(parent, "replacement")
	if err := os.Mkdir(target, 0o700); err != nil {
		t.Fatal(err)
	}
	mustWriteFile(t, filepath.Join(target, "owned"), []byte("owned"), 0o600)
	if err := os.Mkdir(replacement, 0o700); err != nil {
		t.Fatal(err)
	}
	mustWriteFile(t, filepath.Join(replacement, "foreign"), []byte("replacement-unchanged"), 0o600)
	parentFD, err := syscall.Open(parent, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		t.Fatal(err)
	}
	err = removePrivateTreeAtWithHook(parentFD, "target", nil, func() {
		if renameErr := os.Rename(target, original); renameErr != nil {
			t.Fatal(renameErr)
		}
		if renameErr := os.Rename(replacement, target); renameErr != nil {
			t.Fatal(renameErr)
		}
	})
	syscall.Close(parentFD)
	if err == nil {
		t.Fatal("cleanup accepted a last-moment directory replacement")
	}
	if actual, readErr := os.ReadFile(filepath.Join(target, "foreign")); readErr != nil || string(actual) != "replacement-unchanged" {
		t.Fatal("cleanup deleted or changed the replacement directory")
	}
	if actual, readErr := os.ReadFile(filepath.Join(original, "owned")); readErr != nil || string(actual) != "owned" {
		t.Fatal("cleanup changed the pinned original directory after replacement")
	}

	raceRoot := filepath.Join(t.TempDir(), "files")
	if err := os.Mkdir(raceRoot, 0o700); err != nil {
		t.Fatal(err)
	}
	raceName := "generation-" + strings.Repeat("c", sha256.Size*2)
	racePath := filepath.Join(raceRoot, raceName)
	raceOriginal := filepath.Join(filepath.Dir(raceRoot), "race-original")
	raceReplacement := filepath.Join(filepath.Dir(raceRoot), "race-replacement")
	if err := os.Mkdir(racePath, 0o700); err != nil {
		t.Fatal(err)
	}
	mustWriteFile(t, filepath.Join(racePath, "owned"), []byte("owned"), 0o600)
	if err := os.Mkdir(raceReplacement, 0o700); err != nil {
		t.Fatal(err)
	}
	mustWriteFile(t, filepath.Join(raceReplacement, "foreign"), []byte("replacement-unchanged"), 0o600)
	originalCleanupHook := cleanupAfterPreflightHook
	cleanupAfterPreflightHook = func() {
		if err := os.Rename(racePath, raceOriginal); err != nil {
			t.Error(err)
			return
		}
		if err := os.Rename(raceReplacement, racePath); err != nil {
			t.Error(err)
		}
	}
	t.Cleanup(func() { cleanupAfterPreflightHook = originalCleanupHook })
	if err := cleanupGenerationArtifacts(raceRoot, map[string]bool{}); err == nil {
		t.Fatal("cleanup accepted a generation swap after global preflight")
	}
	cleanupAfterPreflightHook = originalCleanupHook
	if actual, readErr := os.ReadFile(filepath.Join(racePath, "foreign")); readErr != nil || string(actual) != "replacement-unchanged" {
		t.Fatal("cleanup deleted the post-preflight replacement")
	}
	if actual, readErr := os.ReadFile(filepath.Join(raceOriginal, "owned")); readErr != nil || string(actual) != "owned" {
		t.Fatal("cleanup changed the preflight-pinned original")
	}
}

func TestGenerationPublicationKeepsDescriptorIdentityAcrossRename(t *testing.T) {
	certificate, privateKey := testCertificatePair(t, "a.example.test", 3501)
	content := testACMEStore(t, "a.example.test", certificate, privateKey)
	expected, err := parseExpectedDumpTree(content)
	if err != nil {
		t.Fatal(err)
	}
	generationName := fmt.Sprintf("generation-%x", sha256.Sum256(content))

	t.Run("pre-rename-stage-swap", func(t *testing.T) {
		output := filepath.Join(t.TempDir(), "files")
		if err := os.Mkdir(output, 0o700); err != nil {
			t.Fatal(err)
		}
		var stageName string
		originalHook := generationBeforeRenameHook
		generationBeforeRenameHook = func(rootFD int, name string) error {
			stageName = name
			stagePath := fmt.Sprintf("/proc/self/fd/%d/%s", rootFD, name)
			if err := os.Rename(stagePath, filepath.Join(output, ".saved-stage")); err != nil {
				return err
			}
			if err := os.Mkdir(filepath.Join(output, name), 0o700); err != nil {
				return err
			}
			return os.WriteFile(filepath.Join(output, name, "foreign"), []byte("replacement-unchanged"), 0o600)
		}
		t.Cleanup(func() { generationBeforeRenameHook = originalHook })
		if _, _, err := publishGeneration(output, generationName, expected); err == nil {
			t.Fatal("publication accepted a whole-stage swap before rename")
		}
		generationBeforeRenameHook = originalHook
		if actual, err := os.ReadFile(filepath.Join(output, stageName, "foreign")); err != nil || string(actual) != "replacement-unchanged" {
			t.Fatal("failed stage publication deleted the replacement sentinel")
		}
		if err := validatePublishedGeneration(filepath.Join(output, ".saved-stage"), expected); err != nil {
			t.Fatal("held original stage changed during the rejected swap")
		}
	})

	t.Run("post-rename-final-swap", func(t *testing.T) {
		output := filepath.Join(t.TempDir(), "files")
		if err := os.Mkdir(output, 0o700); err != nil {
			t.Fatal(err)
		}
		originalHook := generationAfterRenameHook
		generationAfterRenameHook = func(rootFD int, name string) error {
			publishedPath := fmt.Sprintf("/proc/self/fd/%d/%s", rootFD, name)
			if err := os.Rename(publishedPath, filepath.Join(output, ".saved-final")); err != nil {
				return err
			}
			if err := os.Mkdir(filepath.Join(output, name), 0o700); err != nil {
				return err
			}
			return os.WriteFile(filepath.Join(output, name, "foreign"), []byte("replacement-unchanged"), 0o600)
		}
		t.Cleanup(func() { generationAfterRenameHook = originalHook })
		if _, _, err := publishGeneration(output, generationName, expected); err == nil {
			t.Fatal("publication accepted a final-generation swap after rename")
		}
		generationAfterRenameHook = originalHook
		if actual, err := os.ReadFile(filepath.Join(output, generationName, "foreign")); err != nil || string(actual) != "replacement-unchanged" {
			t.Fatal("failed final publication deleted the replacement sentinel")
		}
		if err := validatePublishedGeneration(filepath.Join(output, ".saved-final"), expected); err != nil {
			t.Fatal("held published generation changed during the rejected swap")
		}
	})
}

func TestNestedGenerationValidationPinsActualFilesAndDirectories(t *testing.T) {
	certificate, privateKey := testCertificatePair(t, "a.example.test", 3601)
	content := testACMEStore(t, "a.example.test", certificate, privateKey)
	expected, err := parseExpectedDumpTree(content)
	if err != nil {
		t.Fatal(err)
	}
	createGeneration := func(t *testing.T) string {
		t.Helper()
		root := filepath.Join(t.TempDir(), "generation")
		domain := filepath.Join(root, "a.example.test")
		if err := os.Mkdir(root, 0o700); err != nil {
			t.Fatal(err)
		}
		if err := os.Mkdir(domain, 0o700); err != nil {
			t.Fatal(err)
		}
		mustWriteFile(t, filepath.Join(domain, "certificate.pem"), certificate, 0o600)
		mustWriteFile(t, filepath.Join(domain, "privatekey.pem"), privateKey, 0o600)
		return root
	}

	t.Run("same-bytes-unsafe-mode-swap-before-open", func(t *testing.T) {
		root := createGeneration(t)
		fired := false
		originalHook := privateFileAfterMetadataHook
		privateFileAfterMetadataHook = func(path string) {
			if fired || !strings.HasSuffix(path, "/certificate.pem") {
				return
			}
			fired = true
			if err := os.Rename(path, path+".original"); err != nil {
				t.Error(err)
				return
			}
			if err := os.WriteFile(path, certificate, 0o644); err != nil {
				t.Error(err)
			}
		}
		t.Cleanup(func() { privateFileAfterMetadataHook = originalHook })
		if err := validatePublishedGeneration(root, expected); err == nil || !fired {
			t.Fatal("nested validator accepted an unsafe same-bytes file swap")
		}
		privateFileAfterMetadataHook = originalHook
		info, err := os.Lstat(filepath.Join(root, "a.example.test", "certificate.pem"))
		if err != nil || info.Mode().Perm() != 0o644 {
			t.Fatal("nested validator mutated the unsafe replacement")
		}
	})

	t.Run("file-replacement-after-read", func(t *testing.T) {
		root := createGeneration(t)
		fired := false
		originalHook := nestedDirectoryBeforeFinalHook
		nestedDirectoryBeforeFinalHook = func(name string) {
			if fired || name != "a.example.test" {
				return
			}
			fired = true
			path := filepath.Join(root, name, "privatekey.pem")
			if err := os.Rename(path, path+".original"); err != nil {
				t.Error(err)
				return
			}
			if err := os.WriteFile(path, privateKey, 0o600); err != nil {
				t.Error(err)
			}
		}
		t.Cleanup(func() { nestedDirectoryBeforeFinalHook = originalHook })
		if err := validatePublishedGeneration(root, expected); err == nil || !fired {
			t.Fatal("nested validator accepted a post-read file replacement")
		}
		nestedDirectoryBeforeFinalHook = originalHook
		if actual, err := os.ReadFile(filepath.Join(root, "a.example.test", "privatekey.pem")); err != nil || !bytes.Equal(actual, privateKey) {
			t.Fatal("nested validator changed the post-read replacement")
		}
	})
}

type supervisorFixture struct {
	config       dumperSupervisorConfig
	source       string
	contentA     []byte
	contentB     []byte
	expectedA    expectedDumpTree
	expectedB    expectedDumpTree
	vendorLog    string
	hookLog      string
	preflightLog string
	hookStarted  string
	hookRelease  string
	rollback     string
	lateMutation string
}

func newSupervisorFixture(t *testing.T, hookAction string) supervisorFixture {
	t.Helper()
	root := t.TempDir()
	runtimeDirectory := filepath.Join(root, "run")
	outputRoot := filepath.Join(root, "files")
	if err := os.Mkdir(outputRoot, 0o700); err != nil {
		t.Fatal(err)
	}
	certificateA, keyA := testCertificatePair(t, "a.example.test", 4001)
	certificateB, keyB := testCertificatePair(t, "b.example.test", 4002)
	contentA := testACMEStore(t, "a.example.test", certificateA, keyA)
	contentB := testACMEStore(t, "b.example.test", certificateB, keyB)
	expectedA, err := parseExpectedDumpTree(contentA)
	if err != nil {
		t.Fatal(err)
	}
	expectedB, err := parseExpectedDumpTree(contentB)
	if err != nil {
		t.Fatal(err)
	}
	source := filepath.Join(root, "acme.json")
	mustWriteFile(t, source, nil, 0o600)
	certificateAPath := filepath.Join(root, "a-certificate.pem")
	keyAPath := filepath.Join(root, "a-privatekey.pem")
	certificateBPath := filepath.Join(root, "b-certificate.pem")
	keyBPath := filepath.Join(root, "b-privatekey.pem")
	mustWriteFile(t, certificateAPath, certificateA, 0o600)
	mustWriteFile(t, keyAPath, keyA, 0o600)
	mustWriteFile(t, certificateBPath, certificateB, 0o600)
	mustWriteFile(t, keyBPath, keyB, 0o600)
	vendorLog := filepath.Join(root, "vendor.log")
	vendorScript := filepath.Join(root, "vendor.sh")
	mustWriteFile(t, vendorScript, []byte(`#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$CERTS_DUMPER_TEST_VENDOR_LOG"
[ "$1" = file ]
shift
source_path=''
dest_path=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --source) source_path="$2"; shift 2 ;;
    --dest) dest_path="$2"; shift 2 ;;
    --domain-subdir|--crt-ext=.pem|--key-ext=.pem|--version|v3|--clean=true) shift ;;
    *) exit 81 ;;
  esac
done
[ -n "$source_path" ] && [ -n "$dest_path" ]
find "$dest_path" -mindepth 1 -maxdepth 1 -exec rm -rf -- '{}' ';'
if grep -Fq '"main":"b.example.test"' "$source_path"; then
  domain='b.example.test'
  certificate="$CERTS_DUMPER_TEST_CERT_B"
  private_key="$CERTS_DUMPER_TEST_KEY_B"
else
  domain='a.example.test'
  certificate="$CERTS_DUMPER_TEST_CERT_A"
  private_key="$CERTS_DUMPER_TEST_KEY_A"
fi
mkdir -p "$dest_path/$domain" "$dest_path/private"
chmod 0700 "$dest_path" "$dest_path/$domain" "$dest_path/private"
cp "$certificate" "$dest_path/$domain/certificate.pem"
cp "$private_key" "$dest_path/$domain/privatekey.pem"
chmod 0600 "$dest_path/$domain/certificate.pem" "$dest_path/$domain/privatekey.pem"
`), 0o700)
	hookLog := filepath.Join(root, "hook.log")
	preflightLog := filepath.Join(root, "preflight.log")
	hookSource := filepath.Join(root, "post-hook.sh")
	hookScript := `#!/bin/sh
set -eu
# if true; then mailcow; fi
case "${1:-}" in
  --preflight) printf 'preflight\n' >>"$CERTS_DUMPER_TEST_PREFLIGHT_LOG"; exit 0 ;;
  '') ;;
  *) exit 82 ;;
esac
` + hookAction + "\n"
	mustWriteFile(t, hookSource, []byte(hookScript), 0o700)
	fixture := supervisorFixture{
		config: dumperSupervisorConfig{
			sourcePath: source, runtimeDirectory: runtimeDirectory,
			snapshotPath:     filepath.Join(runtimeDirectory, "acme.snapshot.json"),
			vendorOutputPath: filepath.Join(runtimeDirectory, "vendor-output"),
			hookSourcePath:   hookSource,
			hookSnapshotPath: filepath.Join(runtimeDirectory, "post-hook.sh"),
			readyPath:        filepath.Join(runtimeDirectory, "ready"), outputRoot: outputRoot,
			vendorExecutable: vendorScript, pollInterval: 10 * time.Millisecond,
		},
		source: source, contentA: contentA, contentB: contentB,
		expectedA: expectedA, expectedB: expectedB,
		vendorLog: vendorLog, hookLog: hookLog, preflightLog: preflightLog,
		hookStarted: filepath.Join(root, "hook.started"), hookRelease: filepath.Join(root, "hook.release"),
		rollback: filepath.Join(root, "rollback"), lateMutation: filepath.Join(root, "late-mutation"),
	}
	setTestEnvironment(t, map[string]string{
		"MAILCOW_ENABLED":                  "false",
		"CERTS_DUMPER_TEST_VENDOR_LOG":     vendorLog,
		"CERTS_DUMPER_TEST_CERT_A":         certificateAPath,
		"CERTS_DUMPER_TEST_KEY_A":          keyAPath,
		"CERTS_DUMPER_TEST_CERT_B":         certificateBPath,
		"CERTS_DUMPER_TEST_KEY_B":          keyBPath,
		"CERTS_DUMPER_TEST_HOOK_LOG":       hookLog,
		"CERTS_DUMPER_TEST_PREFLIGHT_LOG":  preflightLog,
		"CERTS_DUMPER_TEST_HOOK_STARTED":   fixture.hookStarted,
		"CERTS_DUMPER_TEST_HOOK_RELEASE":   fixture.hookRelease,
		"CERTS_DUMPER_TEST_ROLLBACK":       fixture.rollback,
		"CERTS_DUMPER_TEST_LATE_MUTATION":  fixture.lateMutation,
		"CERTS_DUMPER_TEST_EXPECTED_STAGE": fixture.config.vendorOutputPath,
		"CERTS_DUMPER_TEST_OUTPUT_ROOT":    fixture.config.outputRoot,
	})
	return fixture
}

func atomicReplaceTestFile(t *testing.T, path string, content []byte) {
	t.Helper()
	replacement := path + ".next"
	mustWriteFile(t, replacement, content, 0o600)
	if err := os.Rename(replacement, path); err != nil {
		t.Fatal(err)
	}
}

func TestDumperSupervisorFirstBootSerializesAndCoalesces(t *testing.T) {
	fixture := newSupervisorFixture(t, `
[ "$CERTS_DUMPER_OUTPUT_GENERATION" = "$CERTS_DUMPER_TEST_EXPECTED_STAGE" ]
active="${CERTS_DUMPER_TEST_HOOK_LOG}.active"
mkdir "$active"
trap 'rmdir "$active"' EXIT HUP INT TERM
printf 'hook\n' >>"$CERTS_DUMPER_TEST_HOOK_LOG"
if [ ! -e "${CERTS_DUMPER_TEST_HOOK_LOG}.once" ]; then
  : >"${CERTS_DUMPER_TEST_HOOK_LOG}.once"
  : >"$CERTS_DUMPER_TEST_HOOK_STARTED"
  while [ ! -e "$CERTS_DUMPER_TEST_HOOK_RELEASE" ]; do sleep 1; done
fi
`)
	signals := make(chan os.Signal, 1)
	result := make(chan error, 1)
	go func() { result <- runDumperSupervisor(fixture.config, signals) }()
	waitForFile(t, fixture.preflightLog, 3*time.Second)
	time.Sleep(100 * time.Millisecond)
	select {
	case err := <-result:
		t.Fatalf("supervisor exited on safe empty first-boot store: %v", err)
	default:
	}
	readyContent, err := os.ReadFile(fixture.config.readyPath)
	if err != nil || len(readyContent) != 0 {
		t.Fatal("first-boot supervisor became ready before a valid ACME snapshot")
	}
	atomicReplaceTestFile(t, fixture.source, fixture.contentA)
	waitForFile(t, fixture.hookStarted, 5*time.Second)
	atomicReplaceTestFile(t, fixture.source, fixture.contentB)
	mustWriteFile(t, fixture.hookRelease, []byte("release"), 0o600)
	digestB := sha256.Sum256(fixture.contentB)
	nameB := fmt.Sprintf("generation-%x", digestB)
	waitForCondition(t, 8*time.Second, "second coalesced generation", func() bool {
		content, readErr := os.ReadFile(fixture.config.readyPath)
		return readErr == nil && string(content) == fmt.Sprintf("%x %s\n", digestB, nameB)
	})
	time.Sleep(150 * time.Millisecond)
	hookLog, err := os.ReadFile(fixture.hookLog)
	if err != nil || len(strings.Fields(string(hookLog))) != 2 {
		t.Fatalf("serialized hook count = %q, want exactly two", hookLog)
	}
	vendorLog, err := os.ReadFile(fixture.vendorLog)
	if err != nil {
		t.Fatal(err)
	}
	vendorLines := strings.Split(strings.TrimSpace(string(vendorLog)), "\n")
	if len(vendorLines) != 2 {
		t.Fatalf("vendor invocation count = %d, want two", len(vendorLines))
	}
	for _, line := range vendorLines {
		if strings.Contains(line, "--watch") || strings.Contains(line, "--post-hook") || !strings.Contains(line, "--clean=true") || !strings.Contains(line, "--domain-subdir") {
			t.Fatalf("unsafe vendor one-shot argv: %s", line)
		}
	}
	signals <- syscall.SIGTERM
	select {
	case err := <-result:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("idle supervisor did not stop cleanly")
	}
	nameA := fmt.Sprintf("generation-%x", sha256.Sum256(fixture.contentA))
	if err := validatePublishedGeneration(filepath.Join(fixture.config.outputRoot, nameA), fixture.expectedA); err != nil {
		t.Fatal(err)
	}
	if err := validatePublishedGeneration(filepath.Join(fixture.config.outputRoot, nameB), fixture.expectedB); err != nil {
		t.Fatal(err)
	}
	rootFD, err := openOutputRoot(fixture.config.outputRoot)
	if err != nil {
		t.Fatal(err)
	}
	current, exists, err := currentGenerationTarget(rootFD)
	syscall.Close(rootFD)
	if err != nil || !exists || current != nameB {
		t.Fatalf("current generation = %q, want %q", current, nameB)
	}
	if _, err := os.Lstat(filepath.Join(fixture.config.outputRoot, nameB, "private")); !os.IsNotExist(err) {
		t.Fatal("persistent generation retained the ACME account-private-key directory")
	}
}

func TestDumperSupervisorValidatesLastCommitWhileSourceIsNotReady(t *testing.T) {
	fixture := newSupervisorFixture(t, `printf 'hook\n' >>"$CERTS_DUMPER_TEST_HOOK_LOG"`)
	atomicReplaceTestFile(t, fixture.source, fixture.contentA)
	signals := make(chan os.Signal, 1)
	result := make(chan error, 1)
	go func() { result <- runDumperSupervisor(fixture.config, signals) }()
	digest := sha256.Sum256(fixture.contentA)
	generationName := fmt.Sprintf("generation-%x", digest)
	waitForCondition(t, 5*time.Second, "initial committed state", func() bool {
		content, err := os.ReadFile(fixture.config.readyPath)
		return err == nil && string(content) == fmt.Sprintf("%x %s\n", digest, generationName)
	})
	atomicReplaceTestFile(t, fixture.source, nil)
	time.Sleep(3 * fixture.config.pollInterval)
	certificatePath := filepath.Join(fixture.config.outputRoot, generationName, "a.example.test", "certificate.pem")
	if err := os.WriteFile(certificatePath, []byte("persistent-generation-drift"), 0o600); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-result:
		if err == nil || !strings.Contains(err.Error(), "ACME source was not ready") {
			t.Fatalf("not-ready source with committed-state drift result = %v", err)
		}
	case <-time.After(3 * time.Second):
		signals <- syscall.SIGTERM
		t.Fatal("supervisor kept a drifted committed state healthy while ACME stayed not-ready")
	}
}

func TestPublishedStateRejectsFinalWindowCurrentAndRootDrift(t *testing.T) {
	for _, scenario := range []string{"current", "root", "ready-swap", "ready-in-place"} {
		t.Run(scenario, func(t *testing.T) {
			fixture := newSupervisorFixture(t, `printf 'hook\n' >>"$CERTS_DUMPER_TEST_HOOK_LOG"`)
			atomicReplaceTestFile(t, fixture.source, fixture.contentA)
			signals := make(chan os.Signal, 1)
			result := make(chan error, 1)
			go func() { result <- runDumperSupervisor(fixture.config, signals) }()
			digest := sha256.Sum256(fixture.contentA)
			generationName := fmt.Sprintf("generation-%x", digest)
			waitForCondition(t, 5*time.Second, "initial published state", func() bool {
				content, err := os.ReadFile(fixture.config.readyPath)
				return err == nil && string(content) == fmt.Sprintf("%x %s\n", digest, generationName)
			})
			signals <- syscall.SIGTERM
			select {
			case err := <-result:
				if err != nil {
					t.Fatal(err)
				}
			case <-time.After(3 * time.Second):
				t.Fatal("fixture supervisor did not stop")
			}
			originalHook := publishedStateBeforeFinalHook
			t.Cleanup(func() { publishedStateBeforeFinalHook = originalHook })
			publishedStateBeforeFinalHook = func(rootFD int) {
				switch scenario {
				case "current":
					currentPath := fmt.Sprintf("/proc/self/fd/%d/current", rootFD)
					replacedPath := fmt.Sprintf("/proc/self/fd/%d/current.replaced", rootFD)
					if err := os.Rename(currentPath, replacedPath); err != nil {
						t.Fatal(err)
					}
					if err := os.Symlink(generationName, currentPath); err != nil {
						t.Fatal(err)
					}
				case "root":
					mustWriteFile(t, fmt.Sprintf("/proc/self/fd/%d/foreign", rootFD), []byte("drift"), 0o600)
				case "ready-swap":
					replacement := fixture.config.readyPath + ".replacement"
					mustWriteFile(t, replacement, []byte(fmt.Sprintf("%x %s\n", digest, generationName)), 0o600)
					if err := os.Rename(replacement, fixture.config.readyPath); err != nil {
						t.Fatal(err)
					}
				case "ready-in-place":
					if err := os.WriteFile(fixture.config.readyPath, []byte(fmt.Sprintf("%x %s\n", digest, generationName)), 0o600); err != nil {
						t.Fatal(err)
					}
				}
			}
			err := validatePublishedState(fixture.config, generationName, fixture.expectedA, digest)
			publishedStateBeforeFinalHook = originalHook
			if err == nil {
				t.Fatalf("final-window %s drift passed published-state validation", scenario)
			}
		})
	}
}

func TestDumperSupervisorRevalidatesEntireStateAfterPublishingReady(t *testing.T) {
	fixture := newSupervisorFixture(t, `printf 'hook\n' >>"$CERTS_DUMPER_TEST_HOOK_LOG"`)
	atomicReplaceTestFile(t, fixture.source, fixture.contentA)
	originalHook := publishedStateBeforeFinalHook
	t.Cleanup(func() { publishedStateBeforeFinalHook = originalHook })
	publishedStateBeforeFinalHook = func(rootFD int) {
		currentPath := fmt.Sprintf("/proc/self/fd/%d/current", rootFD)
		replacedPath := fmt.Sprintf("/proc/self/fd/%d/current.replaced", rootFD)
		if err := os.Rename(currentPath, replacedPath); err != nil {
			t.Fatal(err)
		}
		if err := os.Symlink("generation-"+strings.Repeat("f", 64), currentPath); err != nil {
			t.Fatal(err)
		}
	}
	err := runDumperSupervisor(fixture.config, make(chan os.Signal, 1))
	publishedStateBeforeFinalHook = originalHook
	if err == nil || !strings.Contains(err.Error(), "post-readiness validation") {
		t.Fatalf("post-readiness full-state drift result = %v", err)
	}
}

func TestDumperSupervisorPublicationFailurePrecedesHook(t *testing.T) {
	fixture := newSupervisorFixture(t, `printf 'hook\n' >>"$CERTS_DUMPER_TEST_HOOK_LOG"`)
	atomicReplaceTestFile(t, fixture.source, fixture.contentA)
	originalHook := generationBeforeRenameHook
	t.Cleanup(func() { generationBeforeRenameHook = originalHook })
	generationBeforeRenameHook = func(int, string) error { return errors.New("injected generation publication failure") }
	err := runDumperSupervisor(fixture.config, make(chan os.Signal, 1))
	generationBeforeRenameHook = originalHook
	if err == nil {
		t.Fatal("injected generation publication failure was ignored")
	}
	if _, err := os.Lstat(fixture.hookLog); !os.IsNotExist(err) {
		t.Fatal("external hook ran before persistent generation publication succeeded")
	}
	entries, err := os.ReadDir(fixture.config.outputRoot)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 0 {
		t.Fatalf("failed generation publication left artifacts: %v", entries)
	}
}

func TestDumperSupervisorRejectsPersistentGenerationDriftAfterHook(t *testing.T) {
	fixture := newSupervisorFixture(t, `
generation=''
for candidate in "$CERTS_DUMPER_TEST_OUTPUT_ROOT"/generation-*; do
  [ -d "$candidate" ] || continue
  generation="$candidate"
done
[ -n "$generation" ]
printf 'externally-drifted' >"$generation/a.example.test/certificate.pem"
printf 'hook\n' >>"$CERTS_DUMPER_TEST_HOOK_LOG"
`)
	atomicReplaceTestFile(t, fixture.source, fixture.contentA)
	err := runDumperSupervisor(fixture.config, make(chan os.Signal, 1))
	if err == nil || !strings.Contains(err.Error(), "drifted while the external hook ran") {
		t.Fatalf("persistent generation drift result = %v", err)
	}
	if _, err := os.Lstat(fixture.hookLog); err != nil {
		t.Fatal("test hook did not reach its deterministic generation-drift injection")
	}
	rootFD, err := openOutputRoot(fixture.config.outputRoot)
	if err != nil {
		t.Fatal(err)
	}
	_, hasCurrent, currentErr := currentGenerationTarget(rootFD)
	syscall.Close(rootFD)
	if currentErr != nil || hasCurrent {
		t.Fatal("drifted persistent generation became current")
	}
	ready, readErr := os.ReadFile(fixture.config.readyPath)
	if readErr != nil || len(ready) != 0 {
		t.Fatal("drifted persistent generation became ready")
	}
}

func TestDumperSupervisorTermDuringHookRollsBackAndExitsCleanly(t *testing.T) {
	fixture := newSupervisorFixture(t, `
trap 'printf rollback >"$CERTS_DUMPER_TEST_ROLLBACK"; exit 143' HUP INT TERM
: >"$CERTS_DUMPER_TEST_HOOK_STARTED"
while :; do sleep 30; done
printf late >"$CERTS_DUMPER_TEST_LATE_MUTATION"
`)
	atomicReplaceTestFile(t, fixture.source, fixture.contentA)
	signals := make(chan os.Signal, 1)
	result := make(chan error, 1)
	go func() { result <- runDumperSupervisor(fixture.config, signals) }()
	waitForFile(t, fixture.hookStarted, 5*time.Second)
	started := time.Now()
	signals <- syscall.SIGTERM
	select {
	case err := <-result:
		if err != nil {
			t.Fatalf("top-level supervisor TERM result = %v, want clean exit", err)
		}
	case <-time.After(4 * time.Second):
		t.Fatal("top-level supervisor did not reap the interrupted hook")
	}
	if time.Since(started) > 4*time.Second {
		t.Fatal("top-level supervisor exceeded the cooperative stop bound")
	}
	if actual, err := os.ReadFile(fixture.rollback); err != nil || string(actual) != "rollback" {
		t.Fatal("interrupted hook did not complete its rollback trap")
	}
	if _, err := os.Lstat(fixture.lateMutation); !os.IsNotExist(err) {
		t.Fatal("interrupted hook performed a late mutation")
	}
	entries, err := os.ReadDir(fixture.config.outputRoot)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 0 {
		t.Fatalf("interrupted hook left an uncommitted generation: %v", entries)
	}
	ready, err := os.ReadFile(fixture.config.readyPath)
	if err != nil || len(ready) != 0 {
		t.Fatal("interrupted hook published readiness")
	}
}
