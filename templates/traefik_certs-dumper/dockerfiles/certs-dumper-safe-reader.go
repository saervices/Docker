// SPDX-License-Identifier: MIT
// Copyright (c) 2025 it.særvices

package main

import (
	"bytes"
	"crypto"
	cryptorand "crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unicode/utf8"
	"unsafe"
)

var (
	canonicalCertificateDomainPattern = regexp.MustCompile(`^(?:\*\.)?(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$`)
	generationNamePattern             = regexp.MustCompile(`^generation-[0-9a-f]{64}$`)
	generationStageNamePattern        = regexp.MustCompile(`^\.generation-[0-9a-f]{64}\.[0-9a-f]{32}$`)
	privateCleanupNamePattern         = regexp.MustCompile(`^\.cleanup\.[0-9a-f]{32}$`)
	currentStageNamePattern           = regexp.MustCompile(`^\.current\.[0-9a-f]{32}$`)
	syncCurrentDirectory              = syscall.Fsync
	currentPublicationAfterSyncHook   func() error
	currentBeforeRenameHook           func(int)
	generationBeforeRenameHook        func(int, string) error
	generationAfterRenameHook         func(int, string) error
	cleanupAfterPreflightHook         func()
	privateFileAfterMetadataHook      func(string)
	nestedDirectoryBeforeFinalHook    func(string)
	publishedStateBeforeFinalHook     func(int)
	prepareSSHStateBeforeFinalHook    func()
	destinationBeforeFinalHook        func(string)
	destinationAfterReadHook          func(string)
	syncStateDescriptor               = syscall.Fsync
)

const (
	dnsTokenMaximumBytes        = 4096
	sshKeyMaximumBytes          = 65536
	knownHostsMaximumBytes      = 1048576
	acmeStoreMaximumBytes       = 16 * 1024 * 1024
	dumpedCertificateMaxBytes   = 4 * 1024 * 1024
	supervisorReadyMaximumBytes = 256
	childTerminationTime        = 5 * time.Second

	certsDumperRuntimeDirectory = "/run/certs-dumper"
	certsDumperSnapshotPath     = "/run/certs-dumper/acme.snapshot.json"
	certsDumperVendorOutputPath = "/run/certs-dumper/vendor-output"
	certsDumperHookSnapshotPath = "/run/certs-dumper/post-hook.sh"
	certsDumperReadyPath        = "/run/certs-dumper/ready"
	certsDumperOutputRoot       = "/data/files"
	certsDumperPostHookSource   = "/config/post-hook.sh"
	certsDumperPollInterval     = time.Second
)

type childExitError struct {
	status int
}

func (current childExitError) Error() string {
	return fmt.Sprintf("supervised hook exited with status %d", current.status)
}

type sourceKind struct {
	maximumBytes     int64
	allowEmpty       bool
	validateMetadata func(fileSnapshot) error
	validate         func([]byte) error
}

type acmeDomain struct {
	Main string   `json:"main"`
	SANs []string `json:"sans"`
}

type acmeCertificate struct {
	Domain      acmeDomain `json:"domain"`
	Certificate []byte     `json:"certificate"`
	Key         []byte     `json:"key"`
}

type acmeAccount struct {
	PrivateKey []byte `json:"PrivateKey"`
}

type acmeStoredData struct {
	Account      *acmeAccount      `json:"Account"`
	Certificates []acmeCertificate `json:"Certificates"`
}

type expectedCertificatePair struct {
	certificate []byte
	key         []byte
}

type expectedDumpTree struct {
	pairs              map[string]expectedCertificatePair
	accountPrivateKeys [][]byte
}

type dumperSupervisorConfig struct {
	sourcePath       string
	runtimeDirectory string
	snapshotPath     string
	vendorOutputPath string
	hookSourcePath   string
	hookSnapshotPath string
	readyPath        string
	outputRoot       string
	vendorExecutable string
	pollInterval     time.Duration
}

type outputCommitPrecondition struct {
	root          fileSnapshot
	current       string
	hasCurrent    bool
	currentRecord fileSnapshot
}

type fileSnapshot struct {
	device      uint64
	inode       uint64
	mode        uint32
	links       uint64
	size        int64
	uid         uint32
	gid         uint32
	modifiedSec int64
	modifiedNS  int64
	changedSec  int64
	changedNS   int64
}

func snapshot(info *syscall.Stat_t) fileSnapshot {
	return fileSnapshot{
		device:      uint64(info.Dev),
		inode:       info.Ino,
		mode:        info.Mode,
		links:       uint64(info.Nlink),
		size:        info.Size,
		uid:         info.Uid,
		gid:         info.Gid,
		modifiedSec: info.Mtim.Sec,
		modifiedNS:  info.Mtim.Nsec,
		changedSec:  info.Ctim.Sec,
		changedNS:   info.Ctim.Nsec,
	}
}

func statDescriptor(fd int) (fileSnapshot, error) {
	var info syscall.Stat_t
	if err := syscall.Fstat(fd, &info); err != nil {
		return fileSnapshot{}, err
	}
	return snapshot(&info), nil
}

func statPathNoFollow(path string) (fileSnapshot, error) {
	var info syscall.Stat_t
	if err := syscall.Lstat(path, &info); err != nil {
		return fileSnapshot{}, err
	}
	return snapshot(&info), nil
}

func validateDNSToken(content []byte) error {
	if len(content) == 0 {
		return errors.New("DNS token is empty")
	}
	if !utf8.Valid(content) {
		return errors.New("DNS token is not valid UTF-8")
	}
	if string(content) == "CHANGE_ME" {
		return errors.New("DNS token is still the placeholder")
	}
	for _, character := range content {
		if character < 0x21 || character > 0x7e {
			return errors.New("DNS token contains bytes outside printable non-whitespace ASCII")
		}
	}
	return nil
}

func parseExpectedDumpTree(content []byte) (expectedDumpTree, error) {
	stores := map[string]*acmeStoredData{}
	if err := json.Unmarshal(content, &stores); err != nil {
		return expectedDumpTree{}, errors.New("ACME store is not valid JSON")
	}
	if len(stores) == 0 {
		return expectedDumpTree{}, errors.New("ACME store contains no resolver data")
	}
	expected := expectedDumpTree{pairs: map[string]expectedCertificatePair{}}
	for _, store := range stores {
		if store == nil {
			return expectedDumpTree{}, errors.New("ACME store contains a null resolver")
		}
		if store.Account != nil && len(store.Account.PrivateKey) > 0 {
			expected.accountPrivateKeys = append(expected.accountPrivateKeys, append([]byte(nil), store.Account.PrivateKey...))
		}
		for _, certificate := range store.Certificates {
			domain := certificate.Domain.Main
			if len(domain) > 253 || !canonicalCertificateDomainPattern.MatchString(domain) || filepath.Base(domain) != domain {
				return expectedDumpTree{}, errors.New("ACME certificate has an unsafe main domain")
			}
			if len(certificate.Certificate) == 0 || len(certificate.Key) == 0 {
				return expectedDumpTree{}, errors.New("ACME certificate or private key is empty")
			}
			if len(certificate.Certificate) > dumpedCertificateMaxBytes || len(certificate.Key) > dumpedCertificateMaxBytes {
				return expectedDumpTree{}, errors.New("ACME certificate or private key is oversized")
			}
			if _, exists := expected.pairs[domain]; exists {
				return expectedDumpTree{}, errors.New("ACME store contains duplicate main domains")
			}
			if err := validateCertificateKeyPair(certificate.Certificate, certificate.Key, domain); err != nil {
				return expectedDumpTree{}, err
			}
			expected.pairs[domain] = expectedCertificatePair{
				certificate: append([]byte(nil), certificate.Certificate...),
				key:         append([]byte(nil), certificate.Key...),
			}
		}
	}
	if len(expected.pairs) == 0 {
		return expectedDumpTree{}, errors.New("ACME store contains no certificates")
	}
	return expected, nil
}

func validateACMEStore(content []byte) error {
	_, err := parseExpectedDumpTree(content)
	return err
}

func validateSupervisorReady(content []byte) error {
	parts := strings.Fields(string(content))
	if len(parts) != 2 || len(parts[0]) != sha256.Size*2 || !strings.HasPrefix(parts[1], "generation-") || len(parts[1]) != len("generation-")+sha256.Size*2 {
		return errors.New("supervisor readiness record is malformed")
	}
	for _, value := range []string{parts[0], strings.TrimPrefix(parts[1], "generation-")} {
		if _, err := strconv.ParseUint(value[:16], 16, 64); err != nil {
			return errors.New("supervisor readiness digest is malformed")
		}
		for _, character := range value {
			if (character < '0' || character > '9') && (character < 'a' || character > 'f') {
				return errors.New("supervisor readiness digest is malformed")
			}
		}
	}
	return nil
}

func validatePostHookOptIn(content []byte) error {
	enabled := os.Getenv("MAILCOW_ENABLED")
	if enabled == "" {
		enabled = "false"
	}
	if enabled != "true" && enabled != "false" {
		return errors.New("MAILCOW_ENABLED must be exactly true or false")
	}
	activeCount := 0
	commentedCount := 0
	for _, line := range strings.Split(string(content), "\n") {
		switch line {
		case "if true; then mailcow; fi":
			activeCount++
		case "# if true; then mailcow; fi":
			commentedCount++
		}
	}
	if enabled == "true" && (activeCount != 1 || commentedCount != 0) {
		return errors.New("enabled Mailcow requires one exact active hook line")
	}
	if enabled == "false" && (activeCount != 0 || commentedCount != 1) {
		return errors.New("disabled Mailcow requires one exact commented hook line")
	}
	return nil
}

func parseLeafCertificate(certificatePEM []byte) (*x509.Certificate, error) {
	block, _ := pem.Decode(certificatePEM)
	if block == nil || block.Type != "CERTIFICATE" {
		return nil, errors.New("dumped certificate is not PEM encoded")
	}
	certificate, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil, errors.New("dumped certificate is invalid")
	}
	return certificate, nil
}

func certificatePublicKey(certificatePEM []byte) ([]byte, error) {
	certificate, err := parseLeafCertificate(certificatePEM)
	if err != nil {
		return nil, err
	}
	encoded, err := x509.MarshalPKIXPublicKey(certificate.PublicKey)
	if err != nil {
		return nil, errors.New("dumped certificate public key is invalid")
	}
	return encoded, nil
}

func privateKeyPublicKey(privateKeyPEM []byte) ([]byte, error) {
	block, _ := pem.Decode(privateKeyPEM)
	if block == nil {
		return nil, errors.New("dumped private key is not PEM encoded")
	}
	var parsed any
	var err error
	switch block.Type {
	case "RSA PRIVATE KEY":
		parsed, err = x509.ParsePKCS1PrivateKey(block.Bytes)
	case "EC PRIVATE KEY":
		parsed, err = x509.ParseECPrivateKey(block.Bytes)
	case "PRIVATE KEY":
		parsed, err = x509.ParsePKCS8PrivateKey(block.Bytes)
	default:
		return nil, errors.New("dumped private-key type is unsupported")
	}
	if err != nil {
		return nil, errors.New("dumped private key is invalid")
	}
	signer, ok := parsed.(crypto.Signer)
	if !ok {
		return nil, errors.New("dumped private key has no public-key projection")
	}
	encoded, err := x509.MarshalPKIXPublicKey(signer.Public())
	if err != nil {
		return nil, errors.New("dumped private-key public key is invalid")
	}
	return encoded, nil
}

func validateCertificateKeyPair(certificatePEM []byte, privateKeyPEM []byte, expectedMain string) error {
	certificate, err := parseLeafCertificate(certificatePEM)
	if err != nil {
		return err
	}
	hasExpectedMain := false
	for _, dnsName := range certificate.DNSNames {
		if strings.EqualFold(dnsName, expectedMain) {
			hasExpectedMain = true
			break
		}
	}
	if !hasExpectedMain {
		return errors.New("dumped certificate does not contain its exact ACME main domain")
	}
	certificateKey, err := certificatePublicKey(certificatePEM)
	if err != nil {
		return err
	}
	privateKey, err := privateKeyPublicKey(privateKeyPEM)
	if err != nil {
		return err
	}
	if !bytes.Equal(certificateKey, privateKey) {
		return errors.New("dumped certificate and private key do not match")
	}
	return nil
}

func validatePrivateDirectorySnapshot(current fileSnapshot) error {
	if current.mode&syscall.S_IFMT != syscall.S_IFDIR {
		return errors.New("state directory is not a directory")
	}
	if int(current.uid) != os.Geteuid() || int(current.gid) != os.Getegid() {
		return errors.New("state directory is not owned by the runtime user")
	}
	return nil
}

func hardenDirectoryWithHook(path string, afterInspect func()) error {
	pathBefore, err := statPathNoFollow(path)
	if errors.Is(err, syscall.ENOENT) {
		if mkdirErr := syscall.Mkdir(path, 0o700); mkdirErr != nil && !errors.Is(mkdirErr, syscall.EEXIST) {
			return fmt.Errorf("create state directory: %w", mkdirErr)
		}
		pathBefore, err = statPathNoFollow(path)
	}
	if err != nil {
		return fmt.Errorf("inspect state directory: %w", err)
	}
	if err := validatePrivateDirectorySnapshot(pathBefore); err != nil {
		return err
	}
	if afterInspect != nil {
		afterInspect()
	}

	fd, err := syscall.Open(path, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return fmt.Errorf("open state directory safely: %w", err)
	}
	defer syscall.Close(fd)
	descriptorBefore, err := statDescriptor(fd)
	if err != nil {
		return fmt.Errorf("inspect opened state directory: %w", err)
	}
	if descriptorBefore != pathBefore {
		return errors.New("state directory identity changed while it was opened")
	}
	if err := validatePrivateDirectorySnapshot(descriptorBefore); err != nil {
		return err
	}
	if err := syscall.Fchmod(fd, 0o700); err != nil {
		return fmt.Errorf("harden state directory descriptor: %w", err)
	}
	descriptorAfter, err := statDescriptor(fd)
	if err != nil {
		return fmt.Errorf("reinspect opened state directory: %w", err)
	}
	pathAfter, err := statPathNoFollow(path)
	if err != nil {
		return fmt.Errorf("reinspect state directory path: %w", err)
	}
	if descriptorAfter != pathAfter || descriptorAfter.device != descriptorBefore.device || descriptorAfter.inode != descriptorBefore.inode {
		return errors.New("state directory path changed while it was hardened")
	}
	if err := validatePrivateDirectorySnapshot(descriptorAfter); err != nil {
		return err
	}
	if descriptorAfter.mode&0o777 != 0o700 {
		return errors.New("state directory is not mode 0700")
	}
	return nil
}

func hardenDirectory(path string) error {
	parentPath, name := filepath.Split(path)
	parentPath = filepath.Clean(parentPath)
	if parentPath == "." || name == "" || filepath.Base(name) != name {
		return errors.New("private directory path must include one safe basename")
	}
	parentBefore, err := statPathNoFollow(parentPath)
	if err != nil || parentBefore.mode&syscall.S_IFMT != syscall.S_IFDIR {
		return errors.New("private directory parent is not a directory")
	}
	parentFD, err := syscall.Open(parentPath, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return err
	}
	defer syscall.Close(parentFD)
	parentDescriptor, err := statDescriptor(parentFD)
	if err != nil || !sameDirectoryBinding(parentBefore, parentDescriptor) {
		return errors.New("private directory parent changed while it was opened")
	}
	directoryFD, _, err := openAndHardenDirectoryAt(parentFD, name)
	if err != nil {
		return err
	}
	syscall.Close(directoryFD)
	parentAfter, err := statPathNoFollow(parentPath)
	parentDescriptorAfter, descriptorErr := statDescriptor(parentFD)
	if err != nil || descriptorErr != nil || !sameDirectoryBinding(parentDescriptor, parentAfter) || !sameDirectoryBinding(parentDescriptor, parentDescriptorAfter) {
		return errors.New("private directory parent binding changed during hardening")
	}
	return nil
}

func validatePrivateStateFileSnapshot(current fileSnapshot) error {
	if current.mode&syscall.S_IFMT != syscall.S_IFREG {
		return errors.New("state file is not a regular file")
	}
	if current.links != 1 {
		return errors.New("state file must have exactly one link")
	}
	if int(current.uid) != os.Geteuid() || int(current.gid) != os.Getegid() {
		return errors.New("state file is not owned by the runtime user")
	}
	return nil
}

func hardenStateFileWithHook(path string, afterInspect func()) error {
	pathBefore, err := statPathNoFollow(path)
	created := false
	var fd int
	if errors.Is(err, syscall.ENOENT) {
		fd, err = syscall.Open(
			path,
			syscall.O_RDWR|syscall.O_CREAT|syscall.O_EXCL|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC,
			0o600,
		)
		if err != nil {
			return fmt.Errorf("create state file safely: %w", err)
		}
		created = true
		pathBefore, err = statPathNoFollow(path)
	} else if err == nil {
		if err := validatePrivateStateFileSnapshot(pathBefore); err != nil {
			return err
		}
		if afterInspect != nil {
			afterInspect()
		}
		fd, err = syscall.Open(path, syscall.O_RDWR|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	}
	if err != nil {
		return fmt.Errorf("open state file safely: %w", err)
	}
	defer syscall.Close(fd)
	descriptorBefore, err := statDescriptor(fd)
	if err != nil {
		return fmt.Errorf("inspect opened state file: %w", err)
	}
	if descriptorBefore != pathBefore {
		return errors.New("state file identity changed while it was opened")
	}
	if err := validatePrivateStateFileSnapshot(descriptorBefore); err != nil {
		return err
	}
	if err := syscall.Fchmod(fd, 0o600); err != nil {
		return fmt.Errorf("harden state file descriptor: %w", err)
	}
	descriptorAfter, err := statDescriptor(fd)
	if err != nil {
		return fmt.Errorf("reinspect opened state file: %w", err)
	}
	pathAfter, err := statPathNoFollow(path)
	if err != nil {
		return fmt.Errorf("reinspect state file path: %w", err)
	}
	if descriptorAfter != pathAfter || descriptorAfter.device != descriptorBefore.device || descriptorAfter.inode != descriptorBefore.inode {
		return errors.New("state file path changed while it was hardened")
	}
	if err := validatePrivateStateFileSnapshot(descriptorAfter); err != nil {
		return err
	}
	if descriptorAfter.mode&0o777 != 0o600 {
		return errors.New("state file is not mode 0600")
	}
	if created && descriptorAfter.size != 0 {
		return errors.New("new state file is unexpectedly non-empty")
	}
	return nil
}

func hardenStateFile(path string) error {
	parentPath, name := filepath.Split(path)
	parentPath = filepath.Clean(parentPath)
	if parentPath == "." || name == "" || filepath.Base(name) != name {
		return errors.New("private state-file path must include one safe basename")
	}
	parentBefore, err := statPathNoFollow(parentPath)
	if err != nil || parentBefore.mode&syscall.S_IFMT != syscall.S_IFDIR {
		return errors.New("private state-file parent is not a directory")
	}
	parentFD, err := syscall.Open(parentPath, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return err
	}
	defer syscall.Close(parentFD)
	parentDescriptor, err := statDescriptor(parentFD)
	if err != nil || !sameDirectoryBinding(parentBefore, parentDescriptor) {
		return errors.New("private state-file parent changed while it was opened")
	}
	fileFD, _, err := openAndHardenStateFileAt(parentFD, name, true)
	if err != nil {
		return err
	}
	syscall.Close(fileFD)
	parentAfter, err := statPathNoFollow(parentPath)
	parentDescriptorAfter, descriptorErr := statDescriptor(parentFD)
	if err != nil || descriptorErr != nil || !sameDirectoryBinding(parentDescriptor, parentAfter) || !sameDirectoryBinding(parentDescriptor, parentDescriptorAfter) {
		return errors.New("private state-file parent binding changed during hardening")
	}
	return nil
}

func sameDirectoryBinding(first fileSnapshot, second fileSnapshot) bool {
	return first.device == second.device &&
		first.inode == second.inode &&
		first.mode == second.mode &&
		first.uid == second.uid &&
		first.gid == second.gid
}

func validatePrivateDirectoryDescriptor(path string, fd int) (fileSnapshot, error) {
	descriptor, err := statDescriptor(fd)
	if err != nil {
		return fileSnapshot{}, err
	}
	pathSnapshot, err := statPathNoFollow(path)
	if err != nil {
		return fileSnapshot{}, err
	}
	if descriptor != pathSnapshot {
		return fileSnapshot{}, errors.New("directory path does not match its held descriptor")
	}
	if err := validatePrivateDirectorySnapshot(descriptor); err != nil {
		return fileSnapshot{}, err
	}
	if descriptor.mode&0o777 != 0o700 {
		return fileSnapshot{}, errors.New("private directory is not mode 0700")
	}
	return descriptor, nil
}

func openAndHardenDirectoryAtWithHook(parentFD int, name string, afterInspect func()) (int, fileSnapshot, error) {
	if name == "" || name == "." || name == ".." || strings.Contains(name, "/") {
		return -1, fileSnapshot{}, errors.New("private directory child name is invalid")
	}
	path := fmt.Sprintf("/proc/self/fd/%d/%s", parentFD, name)
	pathBefore, err := statPathNoFollow(path)
	if errors.Is(err, syscall.ENOENT) {
		if mkdirErr := syscall.Mkdir(path, 0o700); mkdirErr != nil && !errors.Is(mkdirErr, syscall.EEXIST) {
			return -1, fileSnapshot{}, fmt.Errorf("create private child directory: %w", mkdirErr)
		}
		pathBefore, err = statPathNoFollow(path)
	}
	if err != nil {
		return -1, fileSnapshot{}, fmt.Errorf("inspect private child directory: %w", err)
	}
	if err := validatePrivateDirectorySnapshot(pathBefore); err != nil {
		return -1, fileSnapshot{}, err
	}
	if afterInspect != nil {
		afterInspect()
	}
	fd, err := syscall.Openat(parentFD, name, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return -1, fileSnapshot{}, fmt.Errorf("open private child directory: %w", err)
	}
	descriptorBefore, err := statDescriptor(fd)
	if err != nil || descriptorBefore != pathBefore {
		syscall.Close(fd)
		return -1, fileSnapshot{}, errors.New("private child directory changed while it was opened")
	}
	if err := syscall.Fchmod(fd, 0o700); err != nil {
		syscall.Close(fd)
		return -1, fileSnapshot{}, fmt.Errorf("harden private child directory: %w", err)
	}
	descriptorAfter, err := statDescriptor(fd)
	if err != nil {
		syscall.Close(fd)
		return -1, fileSnapshot{}, err
	}
	pathAfter, err := statPathNoFollow(path)
	if err != nil || descriptorAfter != pathAfter || descriptorAfter.device != descriptorBefore.device || descriptorAfter.inode != descriptorBefore.inode {
		syscall.Close(fd)
		return -1, fileSnapshot{}, errors.New("private child directory changed while it was hardened")
	}
	if err := validatePrivateDirectorySnapshot(descriptorAfter); err != nil || descriptorAfter.mode&0o777 != 0o700 {
		syscall.Close(fd)
		return -1, fileSnapshot{}, errors.New("private child directory has unsafe metadata")
	}
	return fd, descriptorAfter, nil
}

func openAndHardenDirectoryAt(parentFD int, name string) (int, fileSnapshot, error) {
	return openAndHardenDirectoryAtWithHook(parentFD, name, nil)
}

func openPrivateDirectoryAt(parentFD int, name string) (int, fileSnapshot, error) {
	if name == "" || name == "." || name == ".." || strings.Contains(name, "/") {
		return -1, fileSnapshot{}, errors.New("private directory child name is invalid")
	}
	path := fmt.Sprintf("/proc/self/fd/%d/%s", parentFD, name)
	pathBefore, err := statPathNoFollow(path)
	if err != nil {
		return -1, fileSnapshot{}, err
	}
	if err := validatePrivateDirectorySnapshot(pathBefore); err != nil || pathBefore.mode&0o777 != 0o700 {
		return -1, fileSnapshot{}, errors.New("existing private child directory has unsafe metadata")
	}
	fd, err := syscall.Openat(parentFD, name, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return -1, fileSnapshot{}, err
	}
	descriptor, descriptorErr := statDescriptor(fd)
	pathAfter, pathErr := statPathNoFollow(path)
	if descriptorErr != nil || pathErr != nil || descriptor != pathBefore || pathAfter != pathBefore {
		syscall.Close(fd)
		return -1, fileSnapshot{}, errors.New("existing private child directory changed while it was opened")
	}
	return fd, descriptor, nil
}

func createPrivateDirectoryAtExclusive(parentFD int, name string) (int, fileSnapshot, error) {
	if name == "" || name == "." || name == ".." || strings.Contains(name, "/") {
		return -1, fileSnapshot{}, errors.New("exclusive private directory child name is invalid")
	}
	if err := syscall.Mkdirat(parentFD, name, 0o700); err != nil {
		return -1, fileSnapshot{}, fmt.Errorf("create exclusive private child directory: %w", err)
	}
	path := fmt.Sprintf("/proc/self/fd/%d/%s", parentFD, name)
	pathSnapshot, err := statPathNoFollow(path)
	if err != nil {
		return -1, fileSnapshot{}, err
	}
	fd, err := syscall.Openat(parentFD, name, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return -1, fileSnapshot{}, err
	}
	descriptor, descriptorErr := statDescriptor(fd)
	pathAfter, pathErr := statPathNoFollow(path)
	if descriptorErr != nil || pathErr != nil || descriptor != pathSnapshot || pathAfter != pathSnapshot || descriptor.mode&0o777 != 0o700 {
		syscall.Close(fd)
		return -1, fileSnapshot{}, errors.New("exclusive private child directory changed while it was opened")
	}
	if err := validatePrivateDirectorySnapshot(descriptor); err != nil {
		syscall.Close(fd)
		return -1, fileSnapshot{}, err
	}
	return fd, descriptor, nil
}

func openAndHardenStateFileAtWithHook(parentFD int, name string, closeOnExec bool, afterInspect func()) (int, fileSnapshot, error) {
	if name == "" || name == "." || name == ".." || strings.Contains(name, "/") {
		return -1, fileSnapshot{}, errors.New("private state-file child name is invalid")
	}
	path := fmt.Sprintf("/proc/self/fd/%d/%s", parentFD, name)
	pathBefore, err := statPathNoFollow(path)
	flags := syscall.O_RDWR | syscall.O_NOFOLLOW | syscall.O_NONBLOCK
	if closeOnExec {
		flags |= syscall.O_CLOEXEC
	}
	if errors.Is(err, syscall.ENOENT) {
		fd, openErr := syscall.Openat(parentFD, name, flags|syscall.O_CREAT|syscall.O_EXCL, 0o600)
		if openErr != nil {
			return -1, fileSnapshot{}, fmt.Errorf("create private state file: %w", openErr)
		}
		pathBefore, err = statPathNoFollow(path)
		if err != nil {
			syscall.Close(fd)
			return -1, fileSnapshot{}, err
		}
		descriptor, statErr := statDescriptor(fd)
		if statErr != nil || descriptor != pathBefore {
			syscall.Close(fd)
			return -1, fileSnapshot{}, errors.New("created state file does not match its descriptor")
		}
		if err := syscall.Fchmod(fd, 0o600); err != nil {
			syscall.Close(fd)
			return -1, fileSnapshot{}, err
		}
		descriptor, statErr = statDescriptor(fd)
		pathAfter, pathErr := statPathNoFollow(path)
		if statErr != nil || pathErr != nil || descriptor != pathAfter {
			syscall.Close(fd)
			return -1, fileSnapshot{}, errors.New("created state file changed during hardening")
		}
		if err := validatePrivateStateFileSnapshot(descriptor); err != nil || descriptor.mode&0o777 != 0o600 || descriptor.size != 0 {
			syscall.Close(fd)
			return -1, fileSnapshot{}, errors.New("created state file has unsafe metadata")
		}
		return fd, descriptor, nil
	}
	if err != nil {
		return -1, fileSnapshot{}, err
	}
	if err := validatePrivateStateFileSnapshot(pathBefore); err != nil {
		return -1, fileSnapshot{}, err
	}
	if afterInspect != nil {
		afterInspect()
	}
	fd, err := syscall.Openat(parentFD, name, flags, 0)
	if err != nil {
		return -1, fileSnapshot{}, fmt.Errorf("open private state file: %w", err)
	}
	descriptorBefore, err := statDescriptor(fd)
	if err != nil || descriptorBefore != pathBefore {
		syscall.Close(fd)
		return -1, fileSnapshot{}, errors.New("private state file changed while it was opened")
	}
	if err := syscall.Fchmod(fd, 0o600); err != nil {
		syscall.Close(fd)
		return -1, fileSnapshot{}, err
	}
	descriptorAfter, err := statDescriptor(fd)
	pathAfter, pathErr := statPathNoFollow(path)
	if err != nil || pathErr != nil || descriptorAfter != pathAfter || descriptorAfter.device != descriptorBefore.device || descriptorAfter.inode != descriptorBefore.inode {
		syscall.Close(fd)
		return -1, fileSnapshot{}, errors.New("private state file changed while it was hardened")
	}
	if err := validatePrivateStateFileSnapshot(descriptorAfter); err != nil || descriptorAfter.mode&0o777 != 0o600 {
		syscall.Close(fd)
		return -1, fileSnapshot{}, errors.New("private state file has unsafe metadata")
	}
	return fd, descriptorAfter, nil
}

func openAndHardenStateFileAt(parentFD int, name string, closeOnExec bool) (int, fileSnapshot, error) {
	return openAndHardenStateFileAtWithHook(parentFD, name, closeOnExec, nil)
}

func prepareSSHStateWithHook(rootPath string, rootFD int, beforeFinal func()) error {
	rootBefore, err := validatePrivateDirectoryDescriptor(rootPath, rootFD)
	if err != nil {
		return fmt.Errorf("validate inherited state root: %w", err)
	}
	sshFD, _, err := openAndHardenDirectoryAt(rootFD, ".ssh")
	if err != nil {
		return err
	}
	defer syscall.Close(sshFD)
	knownHostsFD, knownHostsBefore, err := openAndHardenStateFileAt(sshFD, "known_hosts", true)
	if err != nil {
		return err
	}
	defer syscall.Close(knownHostsFD)
	sshBefore, err := statDescriptor(sshFD)
	sshPathBefore, sshPathErr := statPathNoFollow(fmt.Sprintf("/proc/self/fd/%d/.ssh", rootFD))
	if err != nil || sshPathErr != nil || sshBefore != sshPathBefore {
		return errors.New("SSH state directory changed after preparation")
	}
	if err := syncStateDescriptor(knownHostsFD); err != nil {
		return fmt.Errorf("sync known_hosts state file: %w", err)
	}
	if err := syncStateDescriptor(sshFD); err != nil {
		return fmt.Errorf("sync SSH state directory: %w", err)
	}
	if err := syncStateDescriptor(rootFD); err != nil {
		return fmt.Errorf("sync state root: %w", err)
	}
	if beforeFinal != nil {
		beforeFinal()
	}
	if prepareSSHStateBeforeFinalHook != nil {
		prepareSSHStateBeforeFinalHook()
	}
	knownHostsAfter, knownHostsDescriptorErr := statDescriptor(knownHostsFD)
	knownHostsPathAfter, knownHostsPathErr := statPathNoFollow(fmt.Sprintf("/proc/self/fd/%d/known_hosts", sshFD))
	sshErr := validatePrivateDirectoryFinal(rootFD, ".ssh", sshFD, sshBefore, map[string]fileSnapshot{"known_hosts": knownHostsBefore})
	rootAfter, err := validatePrivateDirectoryDescriptor(rootPath, rootFD)
	if knownHostsDescriptorErr != nil || knownHostsPathErr != nil || knownHostsAfter != knownHostsBefore || knownHostsPathAfter != knownHostsBefore || sshErr != nil || err != nil || !sameDirectoryBinding(rootBefore, rootAfter) {
		return errors.New("inherited state root changed during SSH-state preparation")
	}
	return nil
}

func prepareSSHState(rootPath string, rootFD int) error {
	return prepareSSHStateWithHook(rootPath, rootFD, nil)
}

func syncKnownHostsState(path string) error {
	cleanPath := filepath.Clean(path)
	sshPath, fileName := filepath.Split(cleanPath)
	sshPath = filepath.Clean(sshPath)
	rootPath, sshName := filepath.Split(sshPath)
	rootPath = filepath.Clean(rootPath)
	if fileName != "known_hosts" || sshName != ".ssh" || rootPath == "." {
		return errors.New("known_hosts sync path must be one fixed child below a state-root .ssh directory")
	}
	rootBefore, err := statPathNoFollow(rootPath)
	if err != nil || rootBefore.mode&syscall.S_IFMT != syscall.S_IFDIR {
		return errors.New("known_hosts state root is unsafe")
	}
	rootFD, err := syscall.Open(rootPath, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return err
	}
	defer syscall.Close(rootFD)
	rootDescriptor, err := validatePrivateDirectoryDescriptor(rootPath, rootFD)
	if err != nil || rootDescriptor != rootBefore {
		return errors.New("known_hosts state root changed while it was opened")
	}
	sshFD, sshBefore, err := openPrivateDirectoryAt(rootFD, sshName)
	if err != nil {
		return err
	}
	defer syscall.Close(sshFD)
	filePath := fmt.Sprintf("/proc/self/fd/%d/%s", sshFD, fileName)
	fileBefore, err := statPathNoFollow(filePath)
	if err != nil || validatePrivateStateFileSnapshot(fileBefore) != nil || fileBefore.mode&0o777 != 0o600 {
		return errors.New("known_hosts state file has unsafe metadata")
	}
	fileFD, err := syscall.Openat(sshFD, fileName, syscall.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return err
	}
	defer syscall.Close(fileFD)
	fileDescriptor, err := statDescriptor(fileFD)
	if err != nil || fileDescriptor != fileBefore {
		return errors.New("known_hosts state file changed while it was opened for sync")
	}
	if err := syncStateDescriptor(fileFD); err != nil {
		return fmt.Errorf("sync known_hosts state file: %w", err)
	}
	if err := syncStateDescriptor(sshFD); err != nil {
		return fmt.Errorf("sync known_hosts parent directory: %w", err)
	}
	if err := syncStateDescriptor(rootFD); err != nil {
		return fmt.Errorf("sync known_hosts state root: %w", err)
	}
	fileAfter, descriptorErr := statDescriptor(fileFD)
	filePathAfter, pathErr := statPathNoFollow(filePath)
	sshErr := validatePrivateDirectoryFinal(rootFD, sshName, sshFD, sshBefore, map[string]fileSnapshot{fileName: fileBefore})
	rootAfter, rootErr := validatePrivateDirectoryDescriptor(rootPath, rootFD)
	if descriptorErr != nil || pathErr != nil || sshErr != nil || rootErr != nil || fileAfter != fileBefore || filePathAfter != fileBefore || rootAfter != rootDescriptor {
		return errors.New("known_hosts state changed while durability was established")
	}
	return nil
}

func validateStateLockContext(lockPath string, rootFD int, lockFD int) error {
	rootPath, lockName := filepath.Split(lockPath)
	rootPath = filepath.Clean(rootPath)
	if lockName == "" || filepath.Base(lockName) != lockName {
		return errors.New("state-lock path is invalid")
	}
	if _, err := validatePrivateDirectoryDescriptor(rootPath, rootFD); err != nil {
		return err
	}
	lockDescriptor, err := statDescriptor(lockFD)
	if err != nil {
		return err
	}
	if err := validatePrivateStateFileSnapshot(lockDescriptor); err != nil || lockDescriptor.mode&0o777 != 0o600 {
		return errors.New("inherited state lock has unsafe metadata")
	}
	lockPathThroughRoot := fmt.Sprintf("/proc/self/fd/%d/%s", rootFD, lockName)
	lockPathSnapshot, err := statPathNoFollow(lockPathThroughRoot)
	if err != nil || lockPathSnapshot != lockDescriptor {
		return errors.New("inherited state lock does not match its pinned path")
	}
	if err := syscall.Flock(lockFD, syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		return errors.New("inherited state lock is not held by this process")
	}
	return nil
}

type processIdentity struct {
	pid       int
	parentPID int
	startTime string
}

func readProcessIdentity(pid int) (processIdentity, error) {
	content, err := os.ReadFile(fmt.Sprintf("/proc/%d/stat", pid))
	if err != nil {
		return processIdentity{}, err
	}
	closingParenthesis := strings.LastIndexByte(string(content), ')')
	if closingParenthesis < 0 || closingParenthesis+2 >= len(content) {
		return processIdentity{}, errors.New("process stat record is malformed")
	}
	fields := strings.Fields(string(content[closingParenthesis+2:]))
	if len(fields) < 20 {
		return processIdentity{}, errors.New("process stat record is incomplete")
	}
	parentPID, err := strconv.Atoi(fields[1])
	if err != nil {
		return processIdentity{}, err
	}
	return processIdentity{pid: pid, parentPID: parentPID, startTime: fields[19]}, nil
}

func snapshotProcessDescendants(rootPID int) []processIdentity {
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return nil
	}
	processes := make([]processIdentity, 0, len(entries))
	for _, entry := range entries {
		pid, conversionErr := strconv.Atoi(entry.Name())
		if conversionErr != nil {
			continue
		}
		identity, identityErr := readProcessIdentity(pid)
		if identityErr == nil {
			processes = append(processes, identity)
		}
	}
	descendantPIDs := map[int]bool{rootPID: true}
	changed := true
	for changed {
		changed = false
		for _, identity := range processes {
			if !descendantPIDs[identity.pid] && descendantPIDs[identity.parentPID] {
				descendantPIDs[identity.pid] = true
				changed = true
			}
		}
	}
	descendants := make([]processIdentity, 0)
	for _, identity := range processes {
		if identity.pid != rootPID && descendantPIDs[identity.pid] {
			descendants = append(descendants, identity)
		}
	}
	return descendants
}

func processIdentityStillExists(expected processIdentity) bool {
	current, err := readProcessIdentity(expected.pid)
	return err == nil && current.startTime == expected.startTime
}

func signalPinnedProcesses(processes []processIdentity, signal syscall.Signal) {
	for _, identity := range processes {
		if processIdentityStillExists(identity) {
			_ = syscall.Kill(identity.pid, signal)
		}
	}
}

func signalPinnedProcessesOutsideGroup(processes []processIdentity, processGroup int, signal syscall.Signal) {
	for _, identity := range processes {
		if !processIdentityStillExists(identity) {
			continue
		}
		group, err := syscall.Getpgid(identity.pid)
		if err == nil && group != processGroup {
			_ = syscall.Kill(identity.pid, signal)
		}
	}
}

func signalDetachedAdoptedProcesses(processes []processIdentity, managedProcessGroup int, signal syscall.Signal) {
	byPID := make(map[int]processIdentity, len(processes))
	managedRoots := make(map[int]bool)
	for _, identity := range processes {
		byPID[identity.pid] = identity
		group, err := syscall.Getpgid(identity.pid)
		if err == nil && group == managedProcessGroup {
			managedRoots[identity.pid] = true
		}
	}
	for _, identity := range processes {
		if !processIdentityStillExists(identity) {
			continue
		}
		group, err := syscall.Getpgid(identity.pid)
		if err == nil && group == managedProcessGroup {
			continue
		}
		managedByNestedSupervisor := false
		for parentPID := identity.parentPID; parentPID > 1; {
			if managedRoots[parentPID] {
				managedByNestedSupervisor = true
				break
			}
			parent, exists := byPID[parentPID]
			if !exists {
				break
			}
			parentPID = parent.parentPID
		}
		if !managedByNestedSupervisor {
			_ = syscall.Kill(identity.pid, signal)
		}
	}
}

func processIdentityKey(identity processIdentity) string {
	return fmt.Sprintf("%d:%s", identity.pid, identity.startTime)
}

func excludePinnedProcesses(processes []processIdentity, excluded []processIdentity) []processIdentity {
	excludedIdentities := make(map[string]bool, len(excluded))
	for _, identity := range excluded {
		excludedIdentities[processIdentityKey(identity)] = true
	}
	result := make([]processIdentity, 0, len(processes))
	for _, identity := range processes {
		if !excludedIdentities[processIdentityKey(identity)] {
			result = append(result, identity)
		}
	}
	return result
}

func waitForPinnedProcesses(processes []processIdentity) {
	for {
		reapExitedAdoptedChildren()
		remaining := false
		for _, identity := range processes {
			if processIdentityStillExists(identity) {
				remaining = true
				break
			}
		}
		if !remaining {
			return
		}
		time.Sleep(25 * time.Millisecond)
	}
}

func waitForSupervisedHookWithHook(command []string, rootFile *os.File, lockFile *os.File, beforeStart func()) error {
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGHUP, syscall.SIGINT, syscall.SIGTERM)
	defer signal.Stop(signals)
	if beforeStart != nil {
		beforeStart()
	}
	select {
	case received := <-signals:
		return childExitError{status: 128 + int(received.(syscall.Signal))}
	default:
	}

	child := exec.Command(command[0], command[1:]...)
	child.Env = os.Environ()
	child.ExtraFiles = []*os.File{rootFile, lockFile}
	child.Stdin = os.Stdin
	child.Stdout = os.Stdout
	child.Stderr = os.Stderr
	// Keep the locked shell outside the top-level hook process group. The outer
	// service supervisor signæls the lock wræpper exæctly once; this inner
	// supervisor ælone forwærds thæt signæl to the locked trænsæction.
	child.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := child.Start(); err != nil {
		return fmt.Errorf("start locked Mailcow hook: %w", err)
	}
	waitResult := make(chan error, 1)
	go func() { waitResult <- child.Wait() }()

	select {
	case err := <-waitResult:
		return childStatusError(err, child.ProcessState)
	case received := <-signals:
		descendants := snapshotProcessDescendants(child.Process.Pid)
		childGroup := child.Process.Pid
		_ = syscall.Kill(-childGroup, received.(syscall.Signal))
		// Æ deliberætely detæched descendænt is outside the locked shell's
		// process group. Pin it by PID/start-time ænd signæl it once æs well.
		signalPinnedProcessesOutsideGroup(descendants, childGroup, received.(syscall.Signal))
		err := <-waitResult
		for {
			remaining := make([]processIdentity, 0)
			for _, identity := range descendants {
				if processIdentityStillExists(identity) {
					remaining = append(remaining, identity)
				}
			}
			if len(remaining) == 0 {
				break
			}
			time.Sleep(50 * time.Millisecond)
		}
		return childStatusError(err, child.ProcessState)
	}
}

func waitForSupervisedHook(command []string, rootFile *os.File, lockFile *os.File) error {
	return waitForSupervisedHookWithHook(command, rootFile, lockFile, nil)
}

func childStatusError(waitError error, state *os.ProcessState) error {
	if waitError == nil {
		return nil
	}
	if state == nil {
		return waitError
	}
	waitStatus, ok := state.Sys().(syscall.WaitStatus)
	if !ok {
		return waitError
	}
	if waitStatus.Exited() {
		return childExitError{status: waitStatus.ExitStatus()}
	}
	if waitStatus.Signaled() {
		return childExitError{status: 128 + int(waitStatus.Signal())}
	}
	return waitError
}

func runWithStateLockWithHooks(lockPath string, command []string, afterRootHarden func(), afterLockInspect func()) error {
	if len(command) != 3 || command[0] != "/bin/sh" || !filepath.IsAbs(command[1]) || command[2] != "--mailcow-locked" {
		return errors.New("state-lock wrapper command is not the fixed Mailcow hook form")
	}
	rootPath, lockName := filepath.Split(lockPath)
	rootPath = filepath.Clean(rootPath)
	if lockName == "" || filepath.Base(lockName) != lockName {
		return errors.New("state-lock path is invalid")
	}
	rootParentPath, rootName := filepath.Split(rootPath)
	rootParentPath = filepath.Clean(rootParentPath)
	if rootParentPath == "." || rootName == "" || filepath.Base(rootName) != rootName {
		return errors.New("state-root path must include one safe basename")
	}
	rootParentBefore, err := statPathNoFollow(rootParentPath)
	if err != nil || rootParentBefore.mode&syscall.S_IFMT != syscall.S_IFDIR {
		return errors.New("state-root parent is not a directory")
	}
	rootParentFD, err := syscall.Open(rootParentPath, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return fmt.Errorf("open state-root parent: %w", err)
	}
	defer syscall.Close(rootParentFD)
	rootParentDescriptor, err := statDescriptor(rootParentFD)
	if err != nil || !sameDirectoryBinding(rootParentBefore, rootParentDescriptor) {
		return errors.New("state-root parent changed while it was opened")
	}
	rootFD, _, err := openAndHardenDirectoryAtWithHook(rootParentFD, rootName, afterRootHarden)
	if err != nil {
		return fmt.Errorf("open and harden state root: %w", err)
	}
	defer syscall.Close(rootFD)
	if _, err := validatePrivateDirectoryDescriptor(rootPath, rootFD); err != nil {
		return err
	}
	rootParentAfter, pathErr := statPathNoFollow(rootParentPath)
	rootParentDescriptorAfter, descriptorErr := statDescriptor(rootParentFD)
	if pathErr != nil || descriptorErr != nil ||
		!sameDirectoryBinding(rootParentDescriptor, rootParentAfter) ||
		!sameDirectoryBinding(rootParentDescriptor, rootParentDescriptorAfter) {
		return errors.New("state-root parent binding changed during lock preparation")
	}
	lockFD, _, err := openAndHardenStateFileAtWithHook(rootFD, lockName, false, afterLockInspect)
	if err != nil {
		return err
	}
	defer syscall.Close(lockFD)
	if err := syscall.Flock(lockFD, syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		return errors.New("another Mailcow/DANE certificate roll-over is already active")
	}
	if err := validateStateLockContext(lockPath, rootFD, lockFD); err != nil {
		return err
	}
	rootCopy, err := syscall.Dup(rootFD)
	if err != nil {
		return err
	}
	rootFile := os.NewFile(uintptr(rootCopy), "locked-state-root")
	defer rootFile.Close()
	lockCopy, err := syscall.Dup(lockFD)
	if err != nil {
		return err
	}
	lockFile := os.NewFile(uintptr(lockCopy), "locked-state-file")
	defer lockFile.Close()
	return waitForSupervisedHook(command, rootFile, lockFile)
}

func runWithStateLock(lockPath string, command []string) error {
	return runWithStateLockWithHooks(lockPath, command, nil, nil)
}

func sameDirectoryCleanupState(first fileSnapshot, second fileSnapshot) bool {
	return first.device == second.device &&
		first.inode == second.inode &&
		first.mode == second.mode &&
		first.uid == second.uid &&
		first.gid == second.gid
}

func removePrivateFileWithHook(path string, identity string, parentIdentity string, beforeQuarantine func()) error {
	device, inode, err := parseDestinationIdentity(identity)
	if err != nil {
		return err
	}
	parentDevice, parentInode, err := parseDestinationIdentity(parentIdentity)
	if err != nil {
		return err
	}
	parentPath, baseName := filepath.Split(path)
	parentPath = filepath.Clean(parentPath)
	if parentPath == "." || baseName == "" || baseName == "." || baseName == ".." || strings.Contains(baseName, "/") {
		return errors.New("private cleanup path must include one safe basename")
	}
	parentBefore, err := statPathNoFollow(parentPath)
	if err != nil {
		return fmt.Errorf("inspect cleanup parent: %w", err)
	}
	if parentBefore.mode&syscall.S_IFMT != syscall.S_IFDIR {
		return errors.New("cleanup parent is not a directory")
	}
	if parentBefore.device != parentDevice || parentBefore.inode != parentInode {
		return errors.New("cleanup parent identity changed")
	}
	parentFD, err := syscall.Open(parentPath, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return fmt.Errorf("open cleanup parent safely: %w", err)
	}
	defer syscall.Close(parentFD)
	parentDescriptor, err := statDescriptor(parentFD)
	if err != nil {
		return fmt.Errorf("inspect cleanup parent descriptor: %w", err)
	}
	if !sameDirectoryCleanupState(parentDescriptor, parentBefore) {
		return errors.New("cleanup parent changed while it was opened")
	}

	fileFD, err := syscall.Openat(parentFD, baseName, syscall.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return fmt.Errorf("open private cleanup file safely: %w", err)
	}
	defer syscall.Close(fileFD)
	fileDescriptor, err := statDescriptor(fileFD)
	if err != nil {
		return fmt.Errorf("inspect private cleanup descriptor: %w", err)
	}
	if err := validateDestinationSnapshot(fileDescriptor, device, inode); err != nil {
		return err
	}
	pathThroughParent := fmt.Sprintf("/proc/self/fd/%d/%s", parentFD, baseName)
	pathSnapshot, err := statPathNoFollow(pathThroughParent)
	if err != nil {
		return fmt.Errorf("inspect private cleanup path through pinned parent: %w", err)
	}
	if pathSnapshot != fileDescriptor {
		return errors.New("private cleanup path does not match its held descriptor")
	}
	parentAfter, err := statDescriptor(parentFD)
	if err != nil || !sameDirectoryCleanupState(parentAfter, parentDescriptor) {
		return errors.New("cleanup parent descriptor changed before removal")
	}
	parentPathAfter, err := statPathNoFollow(parentPath)
	if err != nil || !sameDirectoryCleanupState(parentPathAfter, parentDescriptor) {
		return errors.New("cleanup parent path changed before removal")
	}
	fileBeforeRemoval, err := statDescriptor(fileFD)
	if err != nil || fileBeforeRemoval != fileDescriptor {
		return errors.New("private cleanup descriptor changed before removal")
	}
	pathBeforeRemoval, err := statPathNoFollow(pathThroughParent)
	if err != nil || pathBeforeRemoval != fileDescriptor {
		return errors.New("private cleanup path changed before removal")
	}
	quarantineName, quarantined, err := quarantinePrivateEntry(parentFD, baseName, fileDescriptor, beforeQuarantine)
	if err != nil {
		return fmt.Errorf("quarantine private file through pinned parent: %w", err)
	}
	quarantinePath := fmt.Sprintf("/proc/self/fd/%d/%s", parentFD, quarantineName)
	fileBeforeUnlink, descriptorErr := statDescriptor(fileFD)
	pathBeforeUnlink, pathErr := statPathNoFollow(quarantinePath)
	if descriptorErr != nil || pathErr != nil || fileBeforeUnlink != quarantined || pathBeforeUnlink != quarantined {
		return errors.New("private cleanup quarantine does not match its held descriptor")
	}
	if _, sourceErr := statPathNoFollow(pathThroughParent); !errors.Is(sourceErr, syscall.ENOENT) {
		return errors.New("private cleanup source path exists after quarantine")
	}
	if err := unlinkAt(parentFD, quarantineName, 0); err != nil {
		return fmt.Errorf("unlink quarantined private file: %w", err)
	}
	fileAfterRemoval, err := statDescriptor(fileFD)
	if err != nil {
		return fmt.Errorf("reinspect removed private file descriptor: %w", err)
	}
	if fileAfterRemoval.device != device || fileAfterRemoval.inode != inode || fileAfterRemoval.links != 0 {
		return errors.New("private cleanup did not unlink the expected held file")
	}
	if _, err := statPathNoFollow(quarantinePath); !errors.Is(err, syscall.ENOENT) {
		return errors.New("private cleanup quarantine path still exists after removal")
	}
	if _, err := statPathNoFollow(pathThroughParent); !errors.Is(err, syscall.ENOENT) {
		return errors.New("private cleanup source path was recreated during removal")
	}
	parentAfterRemoval, err := statDescriptor(parentFD)
	if err != nil || !sameDirectoryCleanupState(parentAfterRemoval, parentDescriptor) {
		return errors.New("cleanup parent descriptor changed during removal")
	}
	parentPathAfterRemoval, err := statPathNoFollow(parentPath)
	if err != nil || !sameDirectoryCleanupState(parentPathAfterRemoval, parentDescriptor) {
		return errors.New("cleanup parent path changed during removal")
	}
	return syscall.Fsync(parentFD)
}

func removePrivateFile(path string, identity string, parentIdentity string) error {
	return removePrivateFileWithHook(path, identity, parentIdentity, nil)
}

func kindByName(name string) (sourceKind, error) {
	switch name {
	case "dns-token":
		return sourceKind{maximumBytes: dnsTokenMaximumBytes, validate: validateDNSToken}, nil
	case "ssh-key":
		return sourceKind{maximumBytes: sshKeyMaximumBytes}, nil
	case "known-hosts":
		return sourceKind{maximumBytes: knownHostsMaximumBytes, allowEmpty: true}, nil
	case "acme-store":
		return sourceKind{maximumBytes: acmeStoreMaximumBytes, allowEmpty: true, validateMetadata: validateACMESourceMetadata, validate: validateACMEStore}, nil
	case "supervisor-ready":
		return sourceKind{maximumBytes: supervisorReadyMaximumBytes, validateMetadata: validatePrivateReadyMetadata, validate: validateSupervisorReady}, nil
	default:
		return sourceKind{}, errors.New("unsupported source kind")
	}
}

func validateSourceSnapshot(current fileSnapshot, kind sourceKind) error {
	if current.mode&syscall.S_IFMT != syscall.S_IFREG {
		return errors.New("source is not a regular file")
	}
	if current.links != 1 {
		return errors.New("source must have exactly one link")
	}
	minimumBytes := int64(1)
	if kind.allowEmpty {
		minimumBytes = 0
	}
	if current.size < minimumBytes || current.size > kind.maximumBytes {
		return errors.New("source size is outside the accepted range")
	}
	if kind.validateMetadata != nil {
		if err := kind.validateMetadata(current); err != nil {
			return err
		}
	}
	return nil
}

func readStableSourceWithHook(path string, kind sourceKind, afterOpen func()) ([]byte, error) {
	pathBefore, err := statPathNoFollow(path)
	if err != nil {
		return nil, fmt.Errorf("inspect source path: %w", err)
	}
	if err := validateSourceSnapshot(pathBefore, kind); err != nil {
		return nil, err
	}

	fd, err := syscall.Open(path, syscall.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return nil, fmt.Errorf("open source safely: %w", err)
	}
	file := os.NewFile(uintptr(fd), "bounded-source")
	defer file.Close()

	descriptorBefore, err := statDescriptor(fd)
	if err != nil {
		return nil, fmt.Errorf("inspect opened source: %w", err)
	}
	if err := validateSourceSnapshot(descriptorBefore, kind); err != nil {
		return nil, err
	}
	if descriptorBefore != pathBefore {
		return nil, errors.New("source identity changed while it was opened")
	}
	if afterOpen != nil {
		afterOpen()
	}

	content, err := io.ReadAll(io.LimitReader(file, kind.maximumBytes+1))
	if err != nil {
		return nil, fmt.Errorf("read opened source: %w", err)
	}
	descriptorAfter, err := statDescriptor(fd)
	if err != nil {
		return nil, fmt.Errorf("reinspect opened source: %w", err)
	}
	pathAfter, err := statPathNoFollow(path)
	if err != nil {
		return nil, fmt.Errorf("reinspect source path: %w", err)
	}
	if descriptorAfter != descriptorBefore || pathAfter != descriptorBefore {
		return nil, errors.New("source metadata changed while it was read")
	}
	if int64(len(content)) != descriptorBefore.size {
		return nil, errors.New("source length changed while it was read")
	}
	if kind.validate != nil {
		if err := kind.validate(content); err != nil {
			return nil, err
		}
	}
	return content, nil
}

func readStableSource(path string, kind sourceKind) ([]byte, error) {
	return readStableSourceWithHook(path, kind, nil)
}

func parseDestinationIdentity(value string) (uint64, uint64, error) {
	parts := strings.Split(value, ":")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return 0, 0, errors.New("destination identity must be device:inode")
	}
	device, err := strconv.ParseUint(parts[0], 10, 64)
	if err != nil {
		return 0, 0, errors.New("destination device is invalid")
	}
	inode, err := strconv.ParseUint(parts[1], 10, 64)
	if err != nil {
		return 0, 0, errors.New("destination inode is invalid")
	}
	return device, inode, nil
}

func validateDestinationSnapshot(current fileSnapshot, device uint64, inode uint64) error {
	if current.device != device || current.inode != inode {
		return errors.New("destination identity changed")
	}
	if current.mode&syscall.S_IFMT != syscall.S_IFREG || current.links != 1 {
		return errors.New("destination is not a regular single-link file")
	}
	if current.mode&0o777 != 0o600 || int(current.uid) != os.Geteuid() || int(current.gid) != os.Getegid() {
		return errors.New("destination is not a private owned mode-0600 file")
	}
	return nil
}

func writeStableDestinationWithHook(path string, identity string, content []byte, afterInspect func()) error {
	device, inode, err := parseDestinationIdentity(identity)
	if err != nil {
		return err
	}
	pathBefore, err := statPathNoFollow(path)
	if err != nil {
		return fmt.Errorf("inspect destination path: %w", err)
	}
	if err := validateDestinationSnapshot(pathBefore, device, inode); err != nil {
		return err
	}
	if afterInspect != nil {
		afterInspect()
	}

	fd, err := syscall.Open(path, syscall.O_RDWR|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return fmt.Errorf("open destination safely: %w", err)
	}
	file := os.NewFile(uintptr(fd), "private-stage")
	defer file.Close()

	descriptorBefore, err := statDescriptor(fd)
	if err != nil {
		return fmt.Errorf("inspect opened destination: %w", err)
	}
	if descriptorBefore != pathBefore {
		return errors.New("destination identity changed while it was opened")
	}
	if err := validateDestinationSnapshot(descriptorBefore, device, inode); err != nil {
		return err
	}
	if err := syscall.Ftruncate(fd, 0); err != nil {
		return fmt.Errorf("truncate destination: %w", err)
	}
	written := 0
	for written < len(content) {
		count, writeErr := file.Write(content[written:])
		if writeErr != nil {
			return fmt.Errorf("write destination: %w", writeErr)
		}
		if count == 0 {
			return io.ErrShortWrite
		}
		written += count
	}
	if err := file.Sync(); err != nil {
		return fmt.Errorf("sync destination: %w", err)
	}
	writeCompleteSnapshot, err := statDescriptor(fd)
	writeCompletePath, pathErr := statPathNoFollow(path)
	if err != nil || pathErr != nil || writeCompleteSnapshot != writeCompletePath {
		return errors.New("destination changed when its write completed")
	}
	if err := validateDestinationSnapshot(writeCompleteSnapshot, device, inode); err != nil || writeCompleteSnapshot.size != int64(len(content)) {
		return errors.New("destination has unsafe completed-write metadata")
	}
	if destinationBeforeFinalHook != nil {
		destinationBeforeFinalHook(path)
	}
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return fmt.Errorf("rewind destination for verification: %w", err)
	}
	writtenContent, err := io.ReadAll(io.LimitReader(file, int64(len(content))+1))
	if err != nil || !bytes.Equal(writtenContent, content) {
		return errors.New("destination bytes do not match copied content")
	}
	if destinationAfterReadHook != nil {
		destinationAfterReadHook(path)
	}
	descriptorAfter, err := statDescriptor(fd)
	if err != nil {
		return fmt.Errorf("reinspect opened destination: %w", err)
	}
	pathAfter, err := statPathNoFollow(path)
	if err != nil {
		return fmt.Errorf("reinspect destination path: %w", err)
	}
	if descriptorAfter != writeCompleteSnapshot || pathAfter != writeCompleteSnapshot {
		return errors.New("destination path changed while it was written")
	}
	if err := validateDestinationSnapshot(descriptorAfter, device, inode); err != nil {
		return err
	}
	if descriptorAfter.size != int64(len(content)) {
		return errors.New("destination size does not match copied content")
	}
	return nil
}

func writeStableDestination(path string, identity string, content []byte) error {
	return writeStableDestinationWithHook(path, identity, content, nil)
}

func readStableChildSourceWithHook(parentPath string, name string, kind sourceKind, afterInspect func()) ([]byte, error) {
	if name == "" || name == "." || name == ".." || filepath.Base(name) != name {
		return nil, errors.New("bounded child source name is invalid")
	}
	parentBefore, err := statPathNoFollow(parentPath)
	if err != nil || parentBefore.mode&syscall.S_IFMT != syscall.S_IFDIR {
		return nil, errors.New("bounded source parent is not a directory")
	}
	parentFD, err := syscall.Open(parentPath, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return nil, fmt.Errorf("open bounded source parent: %w", err)
	}
	defer syscall.Close(parentFD)
	parentDescriptor, err := statDescriptor(parentFD)
	if err != nil || !sameDirectoryBinding(parentBefore, parentDescriptor) {
		return nil, errors.New("bounded source parent changed while it was opened")
	}
	pathThroughParent := fmt.Sprintf("/proc/self/fd/%d/%s", parentFD, name)
	pathBefore, err := statPathNoFollow(pathThroughParent)
	if err != nil {
		return nil, err
	}
	if err := validateSourceSnapshot(pathBefore, kind); err != nil {
		return nil, err
	}
	if afterInspect != nil {
		afterInspect()
	}
	fd, err := syscall.Openat(parentFD, name, syscall.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return nil, fmt.Errorf("open bounded child source: %w", err)
	}
	file := os.NewFile(uintptr(fd), "bounded-child-source")
	defer file.Close()
	descriptorBefore, err := statDescriptor(fd)
	if err != nil || descriptorBefore != pathBefore {
		return nil, errors.New("bounded child source changed while it was opened")
	}
	content, err := io.ReadAll(io.LimitReader(file, kind.maximumBytes+1))
	if err != nil || int64(len(content)) > kind.maximumBytes {
		return nil, errors.New("bounded child source could not be read within its limit")
	}
	descriptorAfter, descriptorErr := statDescriptor(fd)
	pathAfter, pathErr := statPathNoFollow(pathThroughParent)
	parentAfter, parentErr := statPathNoFollow(parentPath)
	parentDescriptorAfter, parentDescriptorErr := statDescriptor(parentFD)
	if descriptorErr != nil || pathErr != nil || descriptorAfter != descriptorBefore || pathAfter != descriptorBefore {
		return nil, errors.New("bounded child source changed while it was read")
	}
	if parentErr != nil || parentDescriptorErr != nil || !sameDirectoryBinding(parentDescriptor, parentAfter) || !sameDirectoryBinding(parentDescriptor, parentDescriptorAfter) {
		return nil, errors.New("bounded source parent changed while its child was read")
	}
	if int64(len(content)) != descriptorBefore.size {
		return nil, errors.New("bounded child source length changed while it was read")
	}
	if kind.validate != nil {
		if err := kind.validate(content); err != nil {
			return nil, err
		}
	}
	return content, nil
}

func readStableChildSource(parentPath string, name string, kind sourceKind) ([]byte, error) {
	return readStableChildSourceWithHook(parentPath, name, kind, nil)
}

func validateACMESourceMetadata(current fileSnapshot) error {
	if current.mode&syscall.S_IFMT != syscall.S_IFREG || current.links != 1 {
		return errors.New("ACME source must be a regular single-link file")
	}
	if current.mode&0o777 != 0o600 || int(current.uid) != os.Geteuid() || int(current.gid) != os.Getegid() {
		return errors.New("ACME source must be an owned mode-0600 file")
	}
	if current.size < 0 || current.size > acmeStoreMaximumBytes {
		return errors.New("ACME source size is outside the accepted range")
	}
	return nil
}

func validatePrivateReadyMetadata(current fileSnapshot) error {
	if current.mode&syscall.S_IFMT != syscall.S_IFREG || current.links != 1 {
		return errors.New("supervisor readiness record must be a regular single-link file")
	}
	if current.mode&0o777 != 0o600 || int(current.uid) != os.Geteuid() || int(current.gid) != os.Getegid() {
		return errors.New("supervisor readiness record must be an owned mode-0600 file")
	}
	return nil
}

func readReadyACMESource(path string) ([]byte, expectedDumpTree, bool, error) {
	parentPath, name := filepath.Split(filepath.Clean(path))
	parentPath = filepath.Clean(parentPath)
	if !filepath.IsAbs(path) || parentPath == "." || name == "" || filepath.Base(name) != name {
		return nil, expectedDumpTree{}, false, errors.New("ACME source path is invalid")
	}
	metadata, err := statPathNoFollow(path)
	if errors.Is(err, syscall.ENOENT) {
		return nil, expectedDumpTree{}, false, nil
	}
	if err != nil {
		return nil, expectedDumpTree{}, false, err
	}
	if err := validateACMESourceMetadata(metadata); err != nil {
		return nil, expectedDumpTree{}, false, err
	}
	kind := sourceKind{maximumBytes: acmeStoreMaximumBytes, allowEmpty: true, validateMetadata: validateACMESourceMetadata}
	content, err := readStableChildSource(parentPath, name, kind)
	if err != nil {
		return nil, expectedDumpTree{}, false, nil
	}
	if len(content) == 0 {
		return nil, expectedDumpTree{}, false, nil
	}
	expected, err := parseExpectedDumpTree(content)
	if err != nil {
		return nil, expectedDumpTree{}, false, nil
	}
	return content, expected, true, nil
}

func privateFileIdentity(path string) (string, error) {
	metadata, err := statPathNoFollow(path)
	if err != nil {
		return "", err
	}
	if err := validatePrivateStateFileSnapshot(metadata); err != nil || metadata.mode&0o777 != 0o600 {
		return "", errors.New("private file has unsafe metadata")
	}
	return fmt.Sprintf("%d:%d", metadata.device, metadata.inode), nil
}

func preparePrivateSnapshot(path string, content []byte) (fileSnapshot, error) {
	if err := hardenStateFile(path); err != nil {
		return fileSnapshot{}, err
	}
	identity, err := privateFileIdentity(path)
	if err != nil {
		return fileSnapshot{}, err
	}
	if err := writeStableDestination(path, identity, content); err != nil {
		return fileSnapshot{}, err
	}
	metadata, err := statPathNoFollow(path)
	if err != nil {
		return fileSnapshot{}, err
	}
	return metadata, nil
}

func verifyPrivateSnapshot(path string, expectedMetadata fileSnapshot, expectedContent []byte, kind sourceKind) error {
	content, err := readStableSource(path, kind)
	if err != nil {
		return err
	}
	metadata, err := statPathNoFollow(path)
	if err != nil || metadata != expectedMetadata || !bytes.Equal(content, expectedContent) {
		return errors.New("private snapshot changed while it was consumed")
	}
	return nil
}

func listDirectoryNames(fd int) ([]string, error) {
	copyFD, err := syscall.Openat(fd, ".", syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return nil, err
	}
	file := os.NewFile(uintptr(copyFD), "private-directory-list")
	defer file.Close()
	entries, err := file.ReadDir(-1)
	if err != nil {
		return nil, err
	}
	names := make([]string, 0, len(entries))
	for _, entry := range entries {
		names = append(names, entry.Name())
	}
	return names, nil
}

func exactNameSet(actual []string, expected map[string]bool) bool {
	if len(actual) != len(expected) {
		return false
	}
	for _, name := range actual {
		if !expected[name] {
			return false
		}
	}
	return true
}

func validatePrivateTreeFileSnapshot(metadata fileSnapshot, maximumBytes int64) error {
	if metadata.mode&syscall.S_IFMT != syscall.S_IFREG || metadata.links != 1 || metadata.mode&0o777 != 0o600 || int(metadata.uid) != os.Geteuid() || int(metadata.gid) != os.Getegid() || metadata.size < 1 || metadata.size > maximumBytes {
		return errors.New("private tree file has unsafe metadata")
	}
	return nil
}

func readPrivateFileAt(parentFD int, name string, maximumBytes int64) ([]byte, fileSnapshot, error) {
	path := fmt.Sprintf("/proc/self/fd/%d/%s", parentFD, name)
	metadata, err := statPathNoFollow(path)
	if err != nil {
		return nil, fileSnapshot{}, err
	}
	if err := validatePrivateTreeFileSnapshot(metadata, maximumBytes); err != nil {
		return nil, fileSnapshot{}, err
	}
	if privateFileAfterMetadataHook != nil {
		privateFileAfterMetadataHook(path)
	}
	fd, err := syscall.Openat(parentFD, name, syscall.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return nil, fileSnapshot{}, err
	}
	file := os.NewFile(uintptr(fd), "private-tree-file")
	defer file.Close()
	descriptorBefore, err := statDescriptor(fd)
	if err != nil || descriptorBefore != metadata {
		return nil, fileSnapshot{}, errors.New("private tree file changed while it was opened")
	}
	if err := validatePrivateTreeFileSnapshot(descriptorBefore, maximumBytes); err != nil {
		return nil, fileSnapshot{}, err
	}
	content, err := io.ReadAll(io.LimitReader(file, maximumBytes+1))
	if err != nil || int64(len(content)) != descriptorBefore.size {
		return nil, fileSnapshot{}, errors.New("private tree file could not be read within its bound")
	}
	descriptorAfter, descriptorErr := statDescriptor(fd)
	pathAfter, pathErr := statPathNoFollow(path)
	if descriptorErr != nil || pathErr != nil || descriptorAfter != descriptorBefore || pathAfter != descriptorBefore {
		return nil, fileSnapshot{}, errors.New("private tree file changed while it was read")
	}
	return content, descriptorBefore, nil
}

func validatePrivateDirectoryFinal(parentFD int, name string, fd int, before fileSnapshot, children map[string]fileSnapshot) error {
	if nestedDirectoryBeforeFinalHook != nil {
		nestedDirectoryBeforeFinalHook(name)
	}
	names, err := listDirectoryNames(fd)
	expectedNames := map[string]bool{}
	for childName := range children {
		expectedNames[childName] = true
	}
	if err != nil || !exactNameSet(names, expectedNames) {
		return errors.New("private nested directory entries changed during validation")
	}
	for childName, expected := range children {
		actual, err := statPathNoFollow(fmt.Sprintf("/proc/self/fd/%d/%s", fd, childName))
		if err != nil || actual != expected {
			return errors.New("private nested file changed after it was read")
		}
	}
	descriptorAfter, descriptorErr := statDescriptor(fd)
	pathAfter, pathErr := statPathNoFollow(fmt.Sprintf("/proc/self/fd/%d/%s", parentFD, name))
	if descriptorErr != nil || pathErr != nil || descriptorAfter != before || pathAfter != before {
		return errors.New("private nested directory changed during validation")
	}
	return nil
}

func validateDumpTree(rootPath string, expected expectedDumpTree) error {
	rootFD, err := syscall.Open(rootPath, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return fmt.Errorf("open private dump stage: %w", err)
	}
	defer syscall.Close(rootFD)
	rootBefore, err := validatePrivateDirectoryDescriptor(rootPath, rootFD)
	if err != nil {
		return err
	}
	expectedRootNames := map[string]bool{"private": true}
	for domain := range expected.pairs {
		expectedRootNames[domain] = true
	}
	rootNames, err := listDirectoryNames(rootFD)
	if err != nil || !exactNameSet(rootNames, expectedRootNames) {
		return errors.New("private dump stage has unexpected root entries")
	}
	for domain, pair := range expected.pairs {
		domainFD, domainBefore, err := openPrivateDirectoryAt(rootFD, domain)
		if err != nil {
			return err
		}
		domainNames, listErr := listDirectoryNames(domainFD)
		if listErr != nil || !exactNameSet(domainNames, map[string]bool{"certificate.pem": true, "privatekey.pem": true}) {
			syscall.Close(domainFD)
			return errors.New("dumped certificate directory has unexpected entries")
		}
		certificate, certificateMetadata, certificateErr := readPrivateFileAt(domainFD, "certificate.pem", dumpedCertificateMaxBytes)
		privateKey, privateKeyMetadata, privateKeyErr := readPrivateFileAt(domainFD, "privatekey.pem", dumpedCertificateMaxBytes)
		if certificateErr != nil || privateKeyErr != nil || !bytes.Equal(certificate, pair.certificate) || !bytes.Equal(privateKey, pair.key) {
			syscall.Close(domainFD)
			return errors.New("dumped certificate pair differs from the validated ACME snapshot")
		}
		if err := validateCertificateKeyPair(certificate, privateKey, domain); err != nil {
			syscall.Close(domainFD)
			return err
		}
		if err := validatePrivateDirectoryFinal(rootFD, domain, domainFD, domainBefore, map[string]fileSnapshot{
			"certificate.pem": certificateMetadata,
			"privatekey.pem":  privateKeyMetadata,
		}); err != nil {
			syscall.Close(domainFD)
			return err
		}
		syscall.Close(domainFD)
	}
	privateFD, privateBefore, err := openPrivateDirectoryAt(rootFD, "private")
	if err != nil {
		return err
	}
	defer syscall.Close(privateFD)
	privateNames, err := listDirectoryNames(privateFD)
	if err != nil {
		return err
	}
	privateChildren := map[string]fileSnapshot{}
	if len(expected.accountPrivateKeys) == 0 {
		if len(privateNames) != 0 {
			return errors.New("dumped account-key directory is unexpectedly non-empty")
		}
	} else {
		if !exactNameSet(privateNames, map[string]bool{"letsencrypt.pem": true}) {
			return errors.New("dumped account-key directory has unexpected entries")
		}
		actual, actualMetadata, err := readPrivateFileAt(privateFD, "letsencrypt.pem", dumpedCertificateMaxBytes)
		if err != nil {
			return err
		}
		matches := false
		for _, privateKey := range expected.accountPrivateKeys {
			encoded := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: privateKey})
			if bytes.Equal(actual, encoded) {
				matches = true
				break
			}
		}
		if !matches {
			return errors.New("dumped account private key differs from the validated ACME snapshot")
		}
		privateChildren["letsencrypt.pem"] = actualMetadata
	}
	if err := validatePrivateDirectoryFinal(rootFD, "private", privateFD, privateBefore, privateChildren); err != nil {
		return err
	}
	rootAfter, err := statDescriptor(rootFD)
	pathAfter, pathErr := statPathNoFollow(rootPath)
	if err != nil || pathErr != nil || rootAfter != rootBefore || pathAfter != rootBefore {
		return errors.New("private dump stage changed during validation")
	}
	return nil
}

func writePrivateFileAt(parentFD int, name string, content []byte) error {
	fd, metadata, err := openAndHardenStateFileAt(parentFD, name, true)
	if err != nil {
		return err
	}
	file := os.NewFile(uintptr(fd), "private-generation-file")
	defer file.Close()
	if err := syscall.Ftruncate(fd, 0); err != nil {
		return err
	}
	written := 0
	for written < len(content) {
		count, writeErr := file.Write(content[written:])
		if writeErr != nil || count == 0 {
			return io.ErrShortWrite
		}
		written += count
	}
	if err := file.Sync(); err != nil {
		return err
	}
	after, err := statDescriptor(fd)
	pathAfter, pathErr := statPathNoFollow(fmt.Sprintf("/proc/self/fd/%d/%s", parentFD, name))
	if err != nil || pathErr != nil || after.device != metadata.device || after.inode != metadata.inode || after != pathAfter || after.size != int64(len(content)) {
		return errors.New("private generation file changed while it was written")
	}
	return nil
}

func openOutputRoot(path string) (int, error) {
	before, err := statPathNoFollow(path)
	if err != nil || before.mode&syscall.S_IFMT != syscall.S_IFDIR || int(before.uid) != os.Geteuid() || int(before.gid) != os.Getegid() || (before.mode&0o777 != 0o700 && before.mode&0o777 != 0o770) {
		return -1, errors.New("certificate output root has unsafe metadata")
	}
	fd, err := syscall.Open(path, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return -1, err
	}
	after, err := statDescriptor(fd)
	if err != nil || !sameDirectoryBinding(before, after) {
		syscall.Close(fd)
		return -1, errors.New("certificate output root changed while it was opened")
	}
	return fd, nil
}

func validatePublishedGenerationDescriptor(rootPath string, rootFD int, expected expectedDumpTree) error {
	rootBefore, err := validatePrivateDirectoryDescriptor(rootPath, rootFD)
	if err != nil {
		return err
	}
	expectedNames := map[string]bool{}
	for domain := range expected.pairs {
		expectedNames[domain] = true
	}
	actualNames, err := listDirectoryNames(rootFD)
	if err != nil || !exactNameSet(actualNames, expectedNames) {
		return errors.New("published certificate generation has unexpected entries")
	}
	for domain, pair := range expected.pairs {
		domainFD, domainBefore, err := openPrivateDirectoryAt(rootFD, domain)
		if err != nil {
			return err
		}
		names, listErr := listDirectoryNames(domainFD)
		if listErr != nil || !exactNameSet(names, map[string]bool{"certificate.pem": true, "privatekey.pem": true}) {
			syscall.Close(domainFD)
			return errors.New("published certificate directory has unexpected entries")
		}
		certificate, certificateMetadata, certificateErr := readPrivateFileAt(domainFD, "certificate.pem", dumpedCertificateMaxBytes)
		privateKey, privateKeyMetadata, privateKeyErr := readPrivateFileAt(domainFD, "privatekey.pem", dumpedCertificateMaxBytes)
		if certificateErr != nil || privateKeyErr != nil || !bytes.Equal(certificate, pair.certificate) || !bytes.Equal(privateKey, pair.key) {
			syscall.Close(domainFD)
			return errors.New("published certificate generation differs from its ACME snapshot")
		}
		if err := validatePrivateDirectoryFinal(rootFD, domain, domainFD, domainBefore, map[string]fileSnapshot{
			"certificate.pem": certificateMetadata,
			"privatekey.pem":  privateKeyMetadata,
		}); err != nil {
			syscall.Close(domainFD)
			return err
		}
		syscall.Close(domainFD)
	}
	rootAfter, descriptorErr := statDescriptor(rootFD)
	pathAfter, pathErr := statPathNoFollow(rootPath)
	if descriptorErr != nil || pathErr != nil || rootAfter != rootBefore || pathAfter != rootBefore {
		return errors.New("published certificate generation changed during validation")
	}
	return nil
}

func validatePublishedGeneration(rootPath string, expected expectedDumpTree) error {
	rootFD, err := syscall.Open(rootPath, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return err
	}
	defer syscall.Close(rootFD)
	return validatePublishedGenerationDescriptor(rootPath, rootFD, expected)
}

func unlinkAt(directoryFD int, name string, flags int) error {
	pointer, err := syscall.BytePtrFromString(name)
	if err != nil {
		return err
	}
	_, _, errno := syscall.Syscall(syscall.SYS_UNLINKAT, uintptr(directoryFD), uintptr(unsafe.Pointer(pointer)), uintptr(flags))
	if errno != 0 {
		return errno
	}
	return nil
}

func renameAt2(oldDirectoryFD int, oldName string, newDirectoryFD int, newName string, flags uintptr) error {
	oldPointer, err := syscall.BytePtrFromString(oldName)
	if err != nil {
		return err
	}
	newPointer, err := syscall.BytePtrFromString(newName)
	if err != nil {
		return err
	}
	var syscallNumber uintptr
	switch runtime.GOARCH {
	case "amd64":
		syscallNumber = 316
	case "386":
		syscallNumber = 353
	case "arm":
		syscallNumber = 382
	case "arm64", "riscv64":
		syscallNumber = 276
	case "ppc64", "ppc64le":
		syscallNumber = 357
	case "s390x":
		syscallNumber = 347
	default:
		return errors.New("renameat2 is unsupported on this architecture")
	}
	_, _, errno := syscall.Syscall6(
		syscallNumber,
		uintptr(oldDirectoryFD), uintptr(unsafe.Pointer(oldPointer)),
		uintptr(newDirectoryFD), uintptr(unsafe.Pointer(newPointer)),
		flags, 0,
	)
	if errno != 0 {
		return errno
	}
	return nil
}

func renameAtNoReplace(oldDirectoryFD int, oldName string, newDirectoryFD int, newName string) error {
	const renameNoReplace = 1
	return renameAt2(oldDirectoryFD, oldName, newDirectoryFD, newName, renameNoReplace)
}

func renameAtExchange(oldDirectoryFD int, oldName string, newDirectoryFD int, newName string) error {
	const renameExchange = 2
	return renameAt2(oldDirectoryFD, oldName, newDirectoryFD, newName, renameExchange)
}

func privateCleanupName() (string, error) {
	nonce := make([]byte, 16)
	if _, err := io.ReadFull(cryptorand.Reader, nonce); err != nil {
		return "", err
	}
	return fmt.Sprintf(".cleanup.%x", nonce), nil
}

func sameEntryAfterRename(before fileSnapshot, after fileSnapshot) bool {
	return before.device == after.device &&
		before.inode == after.inode &&
		before.mode == after.mode &&
		before.links == after.links &&
		before.size == after.size &&
		before.uid == after.uid &&
		before.gid == after.gid &&
		before.modifiedSec == after.modifiedSec &&
		before.modifiedNS == after.modifiedNS
}

func quarantinePrivateEntry(parentFD int, name string, expected fileSnapshot, afterInspect func()) (string, fileSnapshot, error) {
	if afterInspect != nil {
		afterInspect()
	}
	quarantineName, err := privateCleanupName()
	if err != nil {
		return "", fileSnapshot{}, err
	}
	if err := renameAtNoReplace(parentFD, name, parentFD, quarantineName); err != nil {
		return "", fileSnapshot{}, err
	}
	quarantinePath := fmt.Sprintf("/proc/self/fd/%d/%s", parentFD, quarantineName)
	quarantined, err := statPathNoFollow(quarantinePath)
	if err == nil && sameEntryAfterRename(expected, quarantined) {
		if _, originalErr := statPathNoFollow(fmt.Sprintf("/proc/self/fd/%d/%s", parentFD, name)); !errors.Is(originalErr, syscall.ENOENT) {
			return "", fileSnapshot{}, errors.New("private cleanup source path was recreated during quarantine")
		}
		return quarantineName, quarantined, nil
	}
	if restoreErr := renameAtNoReplace(parentFD, quarantineName, parentFD, name); restoreErr != nil {
		return "", fileSnapshot{}, errors.New("private cleanup quarantined a replacement and could not restore it")
	}
	return "", fileSnapshot{}, errors.New("private cleanup entry changed before quarantine")
}

func removePrivateRegularFileAt(parentFD int, name string, expected *fileSnapshot) error {
	path := fmt.Sprintf("/proc/self/fd/%d/%s", parentFD, name)
	before, err := statPathNoFollow(path)
	if err != nil || before.mode&syscall.S_IFMT != syscall.S_IFREG || before.links != 1 || before.mode&0o777 != 0o600 || int(before.uid) != os.Geteuid() || int(before.gid) != os.Getegid() {
		return errors.New("private tree cleanup file has unsafe metadata")
	}
	if expected != nil && before != *expected {
		return errors.New("private tree cleanup file changed after preflight")
	}
	fileFD, err := syscall.Openat(parentFD, name, syscall.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return err
	}
	defer syscall.Close(fileFD)
	descriptor, descriptorErr := statDescriptor(fileFD)
	if descriptorErr != nil || descriptor != before {
		return errors.New("private tree cleanup file changed while it was opened")
	}
	quarantineName, quarantined, err := quarantinePrivateEntry(parentFD, name, descriptor, nil)
	if err != nil {
		return err
	}
	descriptor = quarantined
	quarantinePath := fmt.Sprintf("/proc/self/fd/%d/%s", parentFD, quarantineName)
	pathBeforeRemoval, pathErr := statPathNoFollow(quarantinePath)
	fileBeforeRemoval, descriptorErr := statDescriptor(fileFD)
	if descriptorErr != nil || pathErr != nil || fileBeforeRemoval != descriptor || pathBeforeRemoval != descriptor {
		return errors.New("private tree cleanup file changed before removal")
	}
	if err := unlinkAt(parentFD, quarantineName, 0); err != nil {
		return err
	}
	afterRemoval, statErr := statDescriptor(fileFD)
	if statErr != nil || afterRemoval.links != 0 || afterRemoval.device != descriptor.device || afterRemoval.inode != descriptor.inode {
		return errors.New("private tree cleanup removed an unexpected file")
	}
	if _, statErr := statPathNoFollow(quarantinePath); !errors.Is(statErr, syscall.ENOENT) {
		return errors.New("private tree cleanup quarantine path still exists")
	}
	return syscall.Fsync(parentFD)
}

func removePrivateSymlinkAt(parentFD int, name string, expectedTarget string, expected *fileSnapshot) error {
	path := fmt.Sprintf("/proc/self/fd/%d/%s", parentFD, name)
	before, err := statPathNoFollow(path)
	if err != nil || before.mode&syscall.S_IFMT != syscall.S_IFLNK || before.links != 1 {
		return errors.New("private symlink cleanup target has unsafe metadata")
	}
	if expected != nil && before != *expected {
		return errors.New("private symlink cleanup target changed after preflight")
	}
	target, err := os.Readlink(path)
	if err != nil || target != expectedTarget {
		return errors.New("private symlink cleanup target changed")
	}
	quarantineName, quarantined, err := quarantinePrivateEntry(parentFD, name, before, nil)
	if err != nil {
		return err
	}
	before = quarantined
	quarantinePath := fmt.Sprintf("/proc/self/fd/%d/%s", parentFD, quarantineName)
	quarantined, statErr := statPathNoFollow(quarantinePath)
	quarantinedTarget, readErr := os.Readlink(quarantinePath)
	if statErr != nil || readErr != nil || quarantined != before || quarantinedTarget != expectedTarget {
		return errors.New("private symlink changed before removal")
	}
	if err := unlinkAt(parentFD, quarantineName, 0); err != nil {
		return err
	}
	if _, statErr := statPathNoFollow(quarantinePath); !errors.Is(statErr, syscall.ENOENT) {
		return errors.New("private symlink cleanup quarantine still exists")
	}
	return syscall.Fsync(parentFD)
}

func removePrivateTreeAtWithHook(parentFD int, name string, expected *fileSnapshot, afterInspect func()) error {
	parentBefore, err := statDescriptor(parentFD)
	if err != nil || parentBefore.mode&syscall.S_IFMT != syscall.S_IFDIR {
		return errors.New("private tree cleanup parent descriptor is unsafe")
	}
	path := fmt.Sprintf("/proc/self/fd/%d/%s", parentFD, name)
	before, err := statPathNoFollow(path)
	if err != nil || before.mode&syscall.S_IFMT != syscall.S_IFDIR || int(before.uid) != os.Geteuid() || int(before.gid) != os.Getegid() || before.mode&0o777 != 0o700 {
		return errors.New("private tree cleanup target has unsafe metadata")
	}
	if expected != nil && before != *expected {
		return errors.New("private tree cleanup target changed after preflight")
	}
	fd, err := syscall.Openat(parentFD, name, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return err
	}
	defer syscall.Close(fd)
	descriptor, err := statDescriptor(fd)
	if err != nil || descriptor != before {
		return errors.New("private tree cleanup target changed while it was opened")
	}
	quarantineName, quarantined, err := quarantinePrivateEntry(parentFD, name, descriptor, afterInspect)
	if err != nil {
		return err
	}
	descriptor = quarantined
	quarantinePath := fmt.Sprintf("/proc/self/fd/%d/%s", parentFD, quarantineName)
	names, err := listDirectoryNames(fd)
	if err != nil {
		return err
	}
	for _, childName := range names {
		childPath := fmt.Sprintf("/proc/self/fd/%d/%s", fd, childName)
		child, err := statPathNoFollow(childPath)
		if err != nil {
			return err
		}
		switch child.mode & syscall.S_IFMT {
		case syscall.S_IFDIR:
			if err := removePrivateTreeAtWithHook(fd, childName, &child, nil); err != nil {
				return err
			}
		case syscall.S_IFREG:
			if err := removePrivateRegularFileAt(fd, childName, &child); err != nil {
				return err
			}
		default:
			return errors.New("private tree cleanup refuses a special node")
		}
	}
	if err := syscall.Fsync(fd); err != nil {
		return err
	}
	after, err := statDescriptor(fd)
	pathAfter, pathErr := statPathNoFollow(quarantinePath)
	parentAfter, parentErr := statDescriptor(parentFD)
	if err != nil || pathErr != nil || parentErr != nil || !sameDirectoryCleanupState(after, descriptor) || !sameDirectoryCleanupState(pathAfter, descriptor) || after.device != pathAfter.device || after.inode != pathAfter.inode || !sameDirectoryCleanupState(parentBefore, parentAfter) {
		return errors.New("private tree cleanup directory changed before removal")
	}
	const atRemovedir = 0x200
	if err := unlinkAt(parentFD, quarantineName, atRemovedir); err != nil {
		return err
	}
	descriptorAfterRemoval, descriptorErr := statDescriptor(fd)
	parentAfterRemoval, parentErr := statDescriptor(parentFD)
	if descriptorErr != nil || parentErr != nil || descriptorAfterRemoval.device != descriptor.device || descriptorAfterRemoval.inode != descriptor.inode || descriptorAfterRemoval.links != 0 || !sameDirectoryCleanupState(parentBefore, parentAfterRemoval) {
		return errors.New("private tree cleanup removed an unexpected directory")
	}
	if _, statErr := statPathNoFollow(quarantinePath); !errors.Is(statErr, syscall.ENOENT) {
		return errors.New("private tree cleanup directory quarantine still exists")
	}
	return syscall.Fsync(parentFD)
}

func removePrivateTreeAt(parentFD int, name string) error {
	return removePrivateTreeAtWithHook(parentFD, name, nil, nil)
}

func validatePrivateCleanupTreeAt(parentFD int, name string) error {
	fd, before, err := openPrivateDirectoryAt(parentFD, name)
	if err != nil {
		return err
	}
	defer syscall.Close(fd)
	names, err := listDirectoryNames(fd)
	if err != nil {
		return err
	}
	sort.Strings(names)
	for _, childName := range names {
		childPath := fmt.Sprintf("/proc/self/fd/%d/%s", fd, childName)
		child, err := statPathNoFollow(childPath)
		if err != nil {
			return err
		}
		switch child.mode & syscall.S_IFMT {
		case syscall.S_IFDIR:
			if err := validatePrivateCleanupTreeAt(fd, childName); err != nil {
				return err
			}
		case syscall.S_IFREG:
			if child.links != 1 || child.mode&0o777 != 0o600 || int(child.uid) != os.Geteuid() || int(child.gid) != os.Getegid() {
				return errors.New("private cleanup preflight found an unsafe file")
			}
			fileFD, openErr := syscall.Openat(fd, childName, syscall.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
			if openErr != nil {
				return openErr
			}
			descriptor, descriptorErr := statDescriptor(fileFD)
			pathAfter, pathErr := statPathNoFollow(childPath)
			syscall.Close(fileFD)
			if descriptorErr != nil || pathErr != nil || descriptor != child || pathAfter != child {
				return errors.New("private cleanup preflight file changed while it was opened")
			}
		default:
			return errors.New("private cleanup preflight refuses a special node")
		}
	}
	after, descriptorErr := statDescriptor(fd)
	pathAfter, pathErr := statPathNoFollow(fmt.Sprintf("/proc/self/fd/%d/%s", parentFD, name))
	if descriptorErr != nil || pathErr != nil || after != before || pathAfter != before {
		return errors.New("private cleanup preflight directory changed during inspection")
	}
	return nil
}

func cleanupGenerationArtifacts(outputRoot string, keep map[string]bool) error {
	rootFD, err := openOutputRoot(outputRoot)
	if err != nil {
		return err
	}
	defer syscall.Close(rootFD)
	rootBefore, err := statDescriptor(rootFD)
	if err != nil {
		return err
	}
	current, hasCurrent, currentErr := currentGenerationTarget(rootFD)
	if currentErr != nil {
		return currentErr
	}
	protected := map[string]bool{}
	for name, retain := range keep {
		if retain {
			protected[name] = true
		}
	}
	if hasCurrent {
		protected[current] = true
	}
	names, err := listDirectoryNames(rootFD)
	if err != nil {
		return err
	}
	sort.Strings(names)
	actions := map[string]string{}
	actionSnapshots := map[string]fileSnapshot{}
	symlinkTargets := map[string]string{}
	generationExists := map[string]bool{}
	for _, name := range names {
		path := fmt.Sprintf("/proc/self/fd/%d/%s", rootFD, name)
		if privateCleanupNamePattern.MatchString(name) {
			metadata, statErr := statPathNoFollow(path)
			if statErr != nil {
				return statErr
			}
			switch metadata.mode & syscall.S_IFMT {
			case syscall.S_IFDIR:
				if err := validatePrivateCleanupTreeAt(rootFD, name); err != nil {
					return err
				}
				metadataAfter, statAfterErr := statPathNoFollow(path)
				if statAfterErr != nil || metadataAfter != metadata {
					return errors.New("stale private cleanup directory changed during preflight")
				}
				actions[name] = "tree"
				actionSnapshots[name] = metadata
			case syscall.S_IFLNK:
				target, readErr := os.Readlink(path)
				metadataAfter, statAfterErr := statPathNoFollow(path)
				targetAfter, readAfterErr := os.Readlink(path)
				if readErr != nil || statAfterErr != nil || readAfterErr != nil || metadataAfter != metadata || targetAfter != target || !generationNamePattern.MatchString(target) {
					return errors.New("stale private cleanup symlink has an unsafe target")
				}
				actions[name] = "symlink"
				actionSnapshots[name] = metadata
				symlinkTargets[name] = target
			default:
				return errors.New("stale private cleanup artifact has an unsafe type")
			}
			continue
		}
		if generationStageNamePattern.MatchString(name) || generationNamePattern.MatchString(name) {
			metadata, statErr := statPathNoFollow(path)
			if statErr != nil {
				return statErr
			}
			if err := validatePrivateCleanupTreeAt(rootFD, name); err != nil {
				return err
			}
			metadataAfter, statAfterErr := statPathNoFollow(path)
			if statAfterErr != nil || metadataAfter != metadata {
				return errors.New("certificate generation changed during cleanup preflight")
			}
			if generationNamePattern.MatchString(name) {
				generationExists[name] = true
			}
			if generationStageNamePattern.MatchString(name) || !protected[name] {
				actions[name] = "tree"
				actionSnapshots[name] = metadata
			}
			continue
		}
		if currentStageNamePattern.MatchString(name) {
			metadata, statErr := statPathNoFollow(path)
			target, readErr := os.Readlink(path)
			metadataAfter, statAfterErr := statPathNoFollow(path)
			targetAfter, readAfterErr := os.Readlink(path)
			if statErr != nil || readErr != nil || statAfterErr != nil || readAfterErr != nil || metadata.mode&syscall.S_IFMT != syscall.S_IFLNK || metadata.links != 1 || metadataAfter != metadata || targetAfter != target || !generationNamePattern.MatchString(target) {
				return errors.New("stale current-pointer artifact is unsafe")
			}
			actions[name] = "symlink"
			actionSnapshots[name] = metadata
			symlinkTargets[name] = target
			continue
		}
		if name == "current" {
			continue
		}
		return fmt.Errorf("certificate output root contains unsupported legacy or foreign entry %q", name)
	}
	if hasCurrent && !generationExists[current] {
		return errors.New("current certificate generation pointer is dangling")
	}
	rootAfterPreflight, rootErr := statDescriptor(rootFD)
	if rootErr != nil || rootAfterPreflight != rootBefore {
		return errors.New("certificate output root changed during cleanup preflight")
	}
	if cleanupAfterPreflightHook != nil {
		cleanupAfterPreflightHook()
	}
	namesBeforeMutation, err := listDirectoryNames(rootFD)
	if err != nil {
		return err
	}
	sort.Strings(namesBeforeMutation)
	if len(namesBeforeMutation) != len(names) {
		return errors.New("certificate output root inventory changed before cleanup")
	}
	for index := range names {
		if names[index] != namesBeforeMutation[index] {
			return errors.New("certificate output root inventory changed before cleanup")
		}
	}
	rootBeforeMutation, rootErr := statDescriptor(rootFD)
	if rootErr != nil || rootBeforeMutation != rootBefore {
		return errors.New("certificate output root metadata changed before cleanup")
	}
	changed := false
	for _, name := range names {
		expected := actionSnapshots[name]
		switch actions[name] {
		case "tree":
			if err := removePrivateTreeAtWithHook(rootFD, name, &expected, nil); err != nil {
				return err
			}
			changed = true
		case "symlink":
			if err := removePrivateSymlinkAt(rootFD, name, symlinkTargets[name], &expected); err != nil {
				return err
			}
			changed = true
		}
	}
	if changed {
		if err := syscall.Fsync(rootFD); err != nil {
			return err
		}
	}
	remaining, err := listDirectoryNames(rootFD)
	if err != nil {
		return err
	}
	expectedRemaining := map[string]bool{}
	for _, name := range names {
		if actions[name] == "" {
			expectedRemaining[name] = true
		}
	}
	if !exactNameSet(remaining, expectedRemaining) {
		return errors.New("certificate output root changed during cleanup")
	}
	currentAfter, hasCurrentAfter, currentErr := currentGenerationTarget(rootFD)
	if currentErr != nil || currentAfter != current || hasCurrentAfter != hasCurrent {
		return errors.New("current generation pointer changed during cleanup")
	}
	return nil
}

func publishGeneration(outputRoot string, generationName string, expected expectedDumpTree) (publishedPath string, created bool, returnErr error) {
	rootFD, err := openOutputRoot(outputRoot)
	if err != nil {
		return "", false, err
	}
	defer syscall.Close(rootFD)
	generationPath := filepath.Join(outputRoot, generationName)
	generationPathThroughRoot := fmt.Sprintf("/proc/self/fd/%d/%s", rootFD, generationName)
	if _, statErr := statPathNoFollow(generationPathThroughRoot); statErr == nil {
		if err := validatePublishedGeneration(generationPath, expected); err != nil {
			return "", false, errors.New("existing certificate generation is incomplete or changed")
		}
		return generationPath, false, nil
	} else if !errors.Is(statErr, syscall.ENOENT) {
		return "", false, statErr
	}
	nonce := make([]byte, 16)
	if _, err := io.ReadFull(cryptorand.Reader, nonce); err != nil {
		return "", false, err
	}
	stageName := fmt.Sprintf(".%s.%x", generationName, nonce)
	generationFD, _, err := createPrivateDirectoryAtExclusive(rootFD, stageName)
	if err != nil {
		return "", false, err
	}
	stagePath := filepath.Join(outputRoot, stageName)
	cleanupStage := true
	cleanupName := stageName
	defer func() {
		cleanupExpected, cleanupStatErr := statDescriptor(generationFD)
		closeErr := syscall.Close(generationFD)
		if cleanupStage {
			var cleanupErr error
			if cleanupStatErr != nil {
				cleanupErr = cleanupStatErr
			} else {
				cleanupErr = removePrivateTreeAtWithHook(rootFD, cleanupName, &cleanupExpected, nil)
			}
			if cleanupErr != nil {
				if returnErr != nil {
					returnErr = fmt.Errorf("%v; private generation cleanup failed: %w", returnErr, cleanupErr)
				} else {
					returnErr = fmt.Errorf("private generation cleanup failed: %w", cleanupErr)
				}
			}
		}
		if closeErr != nil && returnErr == nil {
			returnErr = closeErr
		}
	}()
	for domain, pair := range expected.pairs {
		domainFD, _, err := openAndHardenDirectoryAt(generationFD, domain)
		if err != nil {
			return "", false, err
		}
		if err := writePrivateFileAt(domainFD, "certificate.pem", pair.certificate); err != nil {
			syscall.Close(domainFD)
			return "", false, err
		}
		if err := writePrivateFileAt(domainFD, "privatekey.pem", pair.key); err != nil {
			syscall.Close(domainFD)
			return "", false, err
		}
		if err := syscall.Fsync(domainFD); err != nil {
			syscall.Close(domainFD)
			return "", false, err
		}
		syscall.Close(domainFD)
	}
	if err := syscall.Fsync(generationFD); err != nil {
		return "", false, err
	}
	if err := validatePublishedGenerationDescriptor(stagePath, generationFD, expected); err != nil {
		return "", false, err
	}
	if generationBeforeRenameHook != nil {
		if err := generationBeforeRenameHook(rootFD, stageName); err != nil {
			return "", false, err
		}
	}
	stageDescriptor, descriptorErr := statDescriptor(generationFD)
	stagePathSnapshot, pathErr := statPathNoFollow(stagePath)
	if descriptorErr != nil || pathErr != nil || stageDescriptor != stagePathSnapshot {
		return "", false, errors.New("private generation stage changed before publication")
	}
	if err := renameAtNoReplace(rootFD, stageName, rootFD, generationName); err != nil {
		return "", false, err
	}
	cleanupName = generationName
	if generationAfterRenameHook != nil {
		if err := generationAfterRenameHook(rootFD, generationName); err != nil {
			return "", false, err
		}
	}
	finalDescriptor, descriptorErr := statDescriptor(generationFD)
	finalPathSnapshot, pathErr := statPathNoFollow(generationPathThroughRoot)
	if descriptorErr != nil || pathErr != nil || finalDescriptor != finalPathSnapshot || !sameEntryAfterRename(stageDescriptor, finalDescriptor) {
		return "", false, errors.New("published generation does not match its held stage descriptor")
	}
	if err := syscall.Fsync(rootFD); err != nil {
		return "", false, err
	}
	if err := validatePublishedGenerationDescriptor(generationPathThroughRoot, generationFD, expected); err != nil {
		return "", false, err
	}
	cleanupStage = false
	return generationPath, true, nil
}

func currentGenerationTarget(rootFD int) (string, bool, error) {
	path := fmt.Sprintf("/proc/self/fd/%d/current", rootFD)
	metadata, err := statPathNoFollow(path)
	if errors.Is(err, syscall.ENOENT) {
		return "", false, nil
	}
	if err != nil || metadata.mode&syscall.S_IFMT != syscall.S_IFLNK || metadata.links != 1 {
		return "", false, errors.New("current generation pointer is not a single-link symlink")
	}
	target, err := os.Readlink(path)
	if err != nil || !strings.HasPrefix(target, "generation-") || len(target) != len("generation-")+sha256.Size*2 || filepath.Base(target) != target {
		return "", false, errors.New("current generation pointer target is invalid")
	}
	for _, character := range strings.TrimPrefix(target, "generation-") {
		if (character < '0' || character > '9') && (character < 'a' || character > 'f') {
			return "", false, errors.New("current generation pointer target is invalid")
		}
	}
	metadataAfter, err := statPathNoFollow(path)
	targetAfter, targetErr := os.Readlink(path)
	if err != nil || targetErr != nil || metadataAfter != metadata || targetAfter != target {
		return "", false, errors.New("current generation pointer changed while it was inspected")
	}
	return target, true, nil
}

func currentGenerationState(rootFD int) (string, bool, fileSnapshot, error) {
	target, exists, err := currentGenerationTarget(rootFD)
	if err != nil || !exists {
		return target, exists, fileSnapshot{}, err
	}
	record, err := statPathNoFollow(fmt.Sprintf("/proc/self/fd/%d/current", rootFD))
	if err != nil {
		return "", false, fileSnapshot{}, err
	}
	targetAfter, existsAfter, err := currentGenerationTarget(rootFD)
	if err != nil || !existsAfter || targetAfter != target {
		return "", false, fileSnapshot{}, errors.New("current generation pointer changed while its identity was captured")
	}
	recordAfter, err := statPathNoFollow(fmt.Sprintf("/proc/self/fd/%d/current", rootFD))
	if err != nil || recordAfter != record {
		return "", false, fileSnapshot{}, errors.New("current generation pointer identity changed while it was captured")
	}
	return target, true, record, nil
}

func snapshotOutputCommitState(outputRoot string) (outputCommitPrecondition, error) {
	rootFD, err := openOutputRoot(outputRoot)
	if err != nil {
		return outputCommitPrecondition{}, err
	}
	defer syscall.Close(rootFD)
	root, err := statDescriptor(rootFD)
	pathRecord, pathErr := statPathNoFollow(outputRoot)
	if err != nil || pathErr != nil || root != pathRecord {
		return outputCommitPrecondition{}, errors.New("certificate output root changed while its commit state was captured")
	}
	current, hasCurrent, currentRecord, err := currentGenerationState(rootFD)
	if err != nil {
		return outputCommitPrecondition{}, err
	}
	state := outputCommitPrecondition{root: root, current: current, hasCurrent: hasCurrent, currentRecord: currentRecord}
	return state, nil
}

func validateOutputCommitState(rootFD int, outputRoot string, expected outputCommitPrecondition) error {
	root, err := statDescriptor(rootFD)
	pathRecord, pathErr := statPathNoFollow(outputRoot)
	if err != nil || pathErr != nil || root != expected.root || pathRecord != expected.root {
		return errors.New("certificate output root drifted while the external hook ran")
	}
	current, hasCurrent, currentRecord, currentErr := currentGenerationState(rootFD)
	if currentErr != nil || current != expected.current || hasCurrent != expected.hasCurrent {
		return errors.New("current generation pointer drifted while the external hook ran")
	}
	if hasCurrent {
		if currentRecord != expected.currentRecord {
			return errors.New("current generation pointer identity drifted while the external hook ran")
		}
	}
	return nil
}

func currentGenerationStateMatches(rootFD int, target string, exists bool, record fileSnapshot) bool {
	actual, actualExists, actualRecord, err := currentGenerationState(rootFD)
	return err == nil && actual == target && actualExists == exists && (!exists || actualRecord == record)
}

func currentGenerationStateMatchesAfterRename(rootFD int, target string, record fileSnapshot) (fileSnapshot, bool) {
	actual, exists, actualRecord, err := currentGenerationState(rootFD)
	return actualRecord, err == nil && exists && actual == target && sameEntryAfterRename(record, actualRecord)
}

func replaceCurrentPointer(rootFD int, target string, expectedTarget string, expectedExists bool, expectedRecord fileSnapshot, runAfterSyncHook bool) (committed bool, returnErr error) {
	nonce := make([]byte, 16)
	if _, err := io.ReadFull(cryptorand.Reader, nonce); err != nil {
		return false, err
	}
	temporaryName := fmt.Sprintf(".current.%x", nonce)
	temporaryPath := fmt.Sprintf("/proc/self/fd/%d/%s", rootFD, temporaryName)
	if _, err := statPathNoFollow(temporaryPath); !errors.Is(err, syscall.ENOENT) {
		return false, errors.New("temporary current-generation pointer already exists")
	}
	if err := os.Symlink(target, temporaryPath); err != nil {
		return false, err
	}
	temporarySnapshot, err := statPathNoFollow(temporaryPath)
	if err != nil || temporarySnapshot.mode&syscall.S_IFMT != syscall.S_IFLNK || temporarySnapshot.links != 1 {
		return false, errors.New("temporary current-generation pointer has unsafe metadata")
	}
	cleanupTemporary := true
	defer func() {
		if cleanupTemporary {
			if metadata, statErr := statPathNoFollow(temporaryPath); statErr == nil && metadata == temporarySnapshot {
				if actual, readErr := os.Readlink(temporaryPath); readErr == nil && actual == target {
					if cleanupErr := removePrivateSymlinkAt(rootFD, temporaryName, target, &temporarySnapshot); cleanupErr != nil {
						if returnErr != nil {
							returnErr = fmt.Errorf("%v; temporary current-pointer cleanup failed: %w", returnErr, cleanupErr)
						} else {
							returnErr = cleanupErr
						}
					}
				}
			}
		}
	}()
	metadataBeforeRename, statErr := statPathNoFollow(temporaryPath)
	actualBeforeRename, readErr := os.Readlink(temporaryPath)
	if statErr != nil || readErr != nil || metadataBeforeRename != temporarySnapshot || actualBeforeRename != target {
		return false, errors.New("temporary current-generation pointer changed before publication")
	}
	if !currentGenerationStateMatches(rootFD, expectedTarget, expectedExists, expectedRecord) {
		return false, errors.New("current generation pointer changed before compare-and-swap")
	}
	if currentBeforeRenameHook != nil {
		currentBeforeRenameHook(rootFD)
	}
	rollbackCommit := func(cause error) (bool, error) {
		if expectedExists {
			currentRecord, currentMatches := currentGenerationStateMatchesAfterRename(rootFD, target, temporarySnapshot)
			if !currentMatches {
				return true, fmt.Errorf("%v; current pointer changed before compare-and-swap rollback", cause)
			}
			displacedRecord, statErr := statPathNoFollow(temporaryPath)
			displacedTarget, readErr := os.Readlink(temporaryPath)
			if statErr != nil || readErr != nil || !sameEntryAfterRename(expectedRecord, displacedRecord) || displacedTarget != expectedTarget {
				return true, fmt.Errorf("%v; displaced current pointer changed before compare-and-swap rollback", cause)
			}
			if err := renameAtExchange(rootFD, "current", rootFD, temporaryName); err != nil {
				return true, fmt.Errorf("%v; current-pointer exchange rollback failed: %w", cause, err)
			}
			_, restored := currentGenerationStateMatchesAfterRename(rootFD, expectedTarget, displacedRecord)
			if !restored {
				return true, fmt.Errorf("%v; current-pointer exchange rollback restored an unexpected entry", cause)
			}
			temporaryAfter, temporaryErr := statPathNoFollow(temporaryPath)
			temporaryTarget, targetErr := os.Readlink(temporaryPath)
			if temporaryErr != nil || targetErr != nil || !sameEntryAfterRename(currentRecord, temporaryAfter) || temporaryTarget != target {
				return true, fmt.Errorf("%v; current-pointer exchange rollback lost its new temporary entry", cause)
			}
			temporarySnapshot = temporaryAfter
			cleanupTemporary = true
			if err := syncCurrentDirectory(rootFD); err != nil {
				return false, fmt.Errorf("%v; pointer rollback failed during directory sync: %w", cause, err)
			}
			return false, cause
		}
		currentRecord, currentMatches := currentGenerationStateMatchesAfterRename(rootFD, target, temporarySnapshot)
		if !currentMatches {
			return true, fmt.Errorf("%v; newly created current pointer changed before rollback", cause)
		}
		if err := removePrivateSymlinkAt(rootFD, "current", target, &currentRecord); err != nil {
			return true, fmt.Errorf("%v; newly created current-pointer rollback failed: %w", cause, err)
		}
		if err := syncCurrentDirectory(rootFD); err != nil {
			return false, fmt.Errorf("%v; pointer rollback failed during directory sync: %w", cause, err)
		}
		return false, cause
	}
	if expectedExists {
		if err := renameAtExchange(rootFD, temporaryName, rootFD, "current"); err != nil {
			return false, err
		}
		displacedRecord, statErr := statPathNoFollow(temporaryPath)
		displacedTarget, readErr := os.Readlink(temporaryPath)
		if statErr != nil || readErr != nil || !sameEntryAfterRename(expectedRecord, displacedRecord) || displacedTarget != expectedTarget {
			currentRecord, currentMatches := currentGenerationStateMatchesAfterRename(rootFD, target, temporarySnapshot)
			if !currentMatches {
				cleanupTemporary = false
				return true, errors.New("current pointer changed during compare-and-swap conflict recovery")
			}
			if err := renameAtExchange(rootFD, "current", rootFD, temporaryName); err != nil {
				cleanupTemporary = false
				return true, fmt.Errorf("current-pointer compare-and-swap conflict rollback failed: %w", err)
			}
			temporaryAfter, temporaryErr := statPathNoFollow(temporaryPath)
			temporaryTarget, targetErr := os.Readlink(temporaryPath)
			if temporaryErr != nil || targetErr != nil || !sameEntryAfterRename(currentRecord, temporaryAfter) || temporaryTarget != target {
				cleanupTemporary = false
				return true, errors.New("current-pointer compare-and-swap conflict rollback lost its new temporary entry")
			}
			temporarySnapshot = temporaryAfter
			cleanupTemporary = true
			if err := syncCurrentDirectory(rootFD); err != nil {
				return false, fmt.Errorf("current-pointer compare-and-swap conflict rollback sync failed: %w", err)
			}
			return false, errors.New("current generation pointer changed in the final compare-and-swap window")
		}
		cleanupTemporary = false
	} else {
		if err := renameAtNoReplace(rootFD, temporaryName, rootFD, "current"); err != nil {
			return false, err
		}
		cleanupTemporary = false
	}
	if err := syncCurrentDirectory(rootFD); err != nil {
		return rollbackCommit(err)
	}
	if runAfterSyncHook && currentPublicationAfterSyncHook != nil {
		if err := currentPublicationAfterSyncHook(); err != nil {
			return rollbackCommit(err)
		}
	}
	currentRecord, currentMatches := currentGenerationStateMatchesAfterRename(rootFD, target, temporarySnapshot)
	if !currentMatches {
		return true, errors.New("current generation pointer did not publish atomically")
	}
	if expectedExists {
		displacedRecord, statErr := statPathNoFollow(temporaryPath)
		if statErr != nil || !sameEntryAfterRename(expectedRecord, displacedRecord) {
			return true, errors.New("displaced current generation pointer changed before removal")
		}
		if err := removePrivateSymlinkAt(rootFD, temporaryName, expectedTarget, &displacedRecord); err != nil {
			return true, fmt.Errorf("remove displaced current generation pointer: %w", err)
		}
		if err := syncCurrentDirectory(rootFD); err != nil {
			return true, err
		}
	}
	_ = currentRecord
	return true, nil
}

func rollbackCurrentPointer(rootFD int, failedTarget string, previous string, hadPrevious bool) error {
	actual, exists, currentRecord, err := currentGenerationState(rootFD)
	if err != nil || !exists || actual != failedTarget {
		return errors.New("current generation pointer changed before commit rollback")
	}
	if hadPrevious {
		_, err := replaceCurrentPointer(rootFD, previous, actual, true, currentRecord, false)
		return err
	}
	if err := removePrivateSymlinkAt(rootFD, "current", failedTarget, &currentRecord); err != nil {
		return err
	}
	return syncCurrentDirectory(rootFD)

}

func setCurrentGeneration(outputRoot string, target string) (string, bool, error) {
	if !generationNamePattern.MatchString(target) {
		return "", false, errors.New("current generation target is invalid")
	}
	rootFD, err := openOutputRoot(outputRoot)
	if err != nil {
		return "", false, err
	}
	defer syscall.Close(rootFD)
	previous, hadPrevious, previousRecord, err := currentGenerationState(rootFD)
	if err != nil {
		return "", false, err
	}
	if hadPrevious && previous == target {
		return previous, true, nil
	}
	committed, err := replaceCurrentPointer(rootFD, target, previous, hadPrevious, previousRecord, true)
	if err == nil {
		return previous, hadPrevious, nil
	}
	if committed {
		return previous, hadPrevious, fmt.Errorf("current generation commit failed after an unrecoverable compare-and-swap state change: %w", err)
	}
	return previous, hadPrevious, err
}

func setCurrentGenerationChecked(outputRoot string, target string, expected expectedDumpTree, precondition outputCommitPrecondition) (string, bool, error) {
	if !generationNamePattern.MatchString(target) {
		return "", false, errors.New("current generation target is invalid")
	}
	rootFD, err := openOutputRoot(outputRoot)
	if err != nil {
		return "", false, err
	}
	defer syscall.Close(rootFD)
	if err := validateOutputCommitState(rootFD, outputRoot, precondition); err != nil {
		return "", false, err
	}
	targetFD, targetBefore, err := openPrivateDirectoryAt(rootFD, target)
	if err != nil {
		return "", false, err
	}
	defer syscall.Close(targetFD)
	targetPath := fmt.Sprintf("/proc/self/fd/%d/%s", rootFD, target)
	if err := validatePublishedGenerationDescriptor(targetPath, targetFD, expected); err != nil {
		return "", false, errors.New("certificate generation drifted after the external hook")
	}
	if err := validateOutputCommitState(rootFD, outputRoot, precondition); err != nil {
		return "", false, err
	}
	targetDescriptor, descriptorErr := statDescriptor(targetFD)
	targetPathRecord, pathErr := statPathNoFollow(targetPath)
	if descriptorErr != nil || pathErr != nil || targetDescriptor != targetBefore || targetPathRecord != targetBefore {
		return "", false, errors.New("certificate generation changed immediately before current-pointer commit")
	}
	previous, hadPrevious, previousRecord, err := currentGenerationState(rootFD)
	if err != nil {
		return "", false, err
	}
	if hadPrevious && previous == target {
		return previous, true, nil
	}
	committed, err := replaceCurrentPointer(rootFD, target, previous, hadPrevious, previousRecord, true)
	if err == nil {
		targetAfter, descriptorErr := statDescriptor(targetFD)
		targetPathAfter, pathErr := statPathNoFollow(targetPath)
		validationErr := validatePublishedGenerationDescriptor(targetPath, targetFD, expected)
		if descriptorErr == nil && pathErr == nil && targetAfter == targetBefore && targetPathAfter == targetBefore && validationErr == nil {
			return previous, hadPrevious, nil
		}
		err = errors.New("certificate generation drifted during current-pointer commit")
		committed = true
	}
	if !committed {
		return previous, hadPrevious, err
	}
	if rollbackErr := rollbackCurrentPointer(rootFD, target, previous, hadPrevious); rollbackErr != nil {
		return previous, hadPrevious, fmt.Errorf("current generation commit failed: %v; pointer rollback failed: %w", err, rollbackErr)
	}
	return previous, hadPrevious, err
}

func validatePublishedState(config dumperSupervisorConfig, generationName string, expected expectedDumpTree, digest [sha256.Size]byte) error {
	rootFD, err := openOutputRoot(config.outputRoot)
	if err != nil {
		return err
	}
	defer syscall.Close(rootFD)
	rootBefore, descriptorErr := statDescriptor(rootFD)
	rootPathBefore, pathErr := statPathNoFollow(config.outputRoot)
	if descriptorErr != nil || pathErr != nil || rootPathBefore != rootBefore {
		return errors.New("certificate output root changed before published-state validation")
	}
	current, exists, currentRecord, err := currentGenerationState(rootFD)
	if err != nil || !exists || current != generationName {
		return errors.New("current certificate generation pointer drifted")
	}
	generationFD, generationBefore, err := openPrivateDirectoryAt(rootFD, generationName)
	if err != nil {
		return err
	}
	defer syscall.Close(generationFD)
	generationPath := fmt.Sprintf("/proc/self/fd/%d/%s", rootFD, generationName)
	if err := validatePublishedGenerationDescriptor(generationPath, generationFD, expected); err != nil {
		return err
	}
	readyKind := sourceKind{maximumBytes: supervisorReadyMaximumBytes, validateMetadata: validatePrivateReadyMetadata, validate: validateSupervisorReady}
	readyBefore, readyStatErr := statPathNoFollow(config.readyPath)
	readyContent, err := readStableSource(config.readyPath, readyKind)
	readyAfterRead, readyAfterReadErr := statPathNoFollow(config.readyPath)
	if err != nil || string(readyContent) != fmt.Sprintf("%x %s\n", digest, generationName) {
		return errors.New("supervisor readiness record drifted")
	}
	if readyStatErr != nil || readyAfterReadErr != nil || readyAfterRead != readyBefore {
		return errors.New("supervisor readiness identity changed during published-state validation")
	}
	if publishedStateBeforeFinalHook != nil {
		publishedStateBeforeFinalHook(rootFD)
	}
	if err := validatePublishedGenerationDescriptor(generationPath, generationFD, expected); err != nil {
		return errors.New("current certificate generation drifted during published-state validation")
	}
	generationAfter, descriptorErr := statDescriptor(generationFD)
	generationPathAfter, generationPathErr := statPathNoFollow(generationPath)
	currentAfter, existsAfter, currentRecordAfter, currentErr := currentGenerationState(rootFD)
	rootAfter, rootDescriptorErr := statDescriptor(rootFD)
	rootPathAfter, rootPathErr := statPathNoFollow(config.outputRoot)
	readyContentAfter, readyReadAfterErr := readStableSource(config.readyPath, readyKind)
	readyFinal, readyFinalErr := statPathNoFollow(config.readyPath)
	if descriptorErr != nil || generationPathErr != nil || generationAfter != generationBefore || generationPathAfter != generationBefore ||
		currentErr != nil || !existsAfter || currentAfter != current || currentRecordAfter != currentRecord ||
		rootDescriptorErr != nil || rootPathErr != nil || rootAfter != rootBefore || rootPathAfter != rootBefore ||
		readyReadAfterErr != nil || readyFinalErr != nil || readyFinal != readyBefore || !bytes.Equal(readyContentAfter, readyContent) {
		return errors.New("published certificate state changed during final validation")
	}
	return nil
}

func enableChildSubreaper() error {
	const prSetChildSubreaper = 36
	_, _, errno := syscall.Syscall6(syscall.SYS_PRCTL, prSetChildSubreaper, 1, 0, 0, 0, 0)
	if errno != 0 {
		return errno
	}
	return nil
}

func reapExitedAdoptedChildren() {
	for {
		var status syscall.WaitStatus
		pid, err := syscall.Wait4(-1, &status, syscall.WNOHANG, nil)
		if pid <= 0 || err != nil {
			return
		}
	}
}

func runSupervisedServiceChild(command []string, environment []string, signals <-chan os.Signal) (bool, error) {
	select {
	case <-signals:
		return true, nil
	default:
	}
	baselineDescendants := snapshotProcessDescendants(os.Getpid())
	child := exec.Command(command[0], command[1:]...)
	child.Env = environment
	child.Stdin = os.Stdin
	child.Stdout = os.Stdout
	child.Stderr = os.Stderr
	child.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := child.Start(); err != nil {
		return false, err
	}
	waitResult := make(chan error, 1)
	go func() { waitResult <- child.Wait() }()
	select {
	case err := <-waitResult:
		adopted := excludePinnedProcesses(snapshotProcessDescendants(os.Getpid()), baselineDescendants)
		signalPinnedProcesses(adopted, syscall.SIGTERM)
		waitForPinnedProcesses(adopted)
		return false, childStatusError(err, child.ProcessState)
	case received := <-signals:
		receivedSignal := received.(syscall.Signal)
		_ = syscall.Kill(-child.Process.Pid, receivedSignal)
		<-waitResult
		// Deliberætely detæched descendænts ære repærented to this subreæper only
		// æfter their originæl supervised pærent exits. Signæl those pinned
		// PID/start-time identities once æt thæt point. Mænæged nested supervisors
		// finish their own children before they exit, so this does not double-signæl
		// æn ærmed locked trænsæction.
		adopted := excludePinnedProcesses(snapshotProcessDescendants(os.Getpid()), baselineDescendants)
		signalDetachedAdoptedProcesses(adopted, child.Process.Pid, receivedSignal)
		waitForPinnedProcesses(adopted)
		return true, nil
	}
}

func waitForSupervisorPoll(signals <-chan os.Signal, duration time.Duration) bool {
	timer := time.NewTimer(duration)
	defer timer.Stop()
	select {
	case <-signals:
		return true
	case <-timer.C:
		return false
	}
}

func productionSupervisorConfig(sourcePath string) dumperSupervisorConfig {
	return dumperSupervisorConfig{
		sourcePath:       sourcePath,
		runtimeDirectory: certsDumperRuntimeDirectory,
		snapshotPath:     certsDumperSnapshotPath,
		vendorOutputPath: certsDumperVendorOutputPath,
		hookSourcePath:   certsDumperPostHookSource,
		hookSnapshotPath: certsDumperHookSnapshotPath,
		readyPath:        certsDumperReadyPath,
		outputRoot:       certsDumperOutputRoot,
		vendorExecutable: "traefik-certs-dumper",
		pollInterval:     certsDumperPollInterval,
	}
}

func prepareSupervisorHook(config dumperSupervisorConfig, signals <-chan os.Signal) ([]byte, fileSnapshot, bool, error) {
	hookParent, hookName := filepath.Split(filepath.Clean(config.hookSourcePath))
	hookContent, err := readStableChildSource(filepath.Clean(hookParent), hookName, sourceKind{maximumBytes: 1024 * 1024})
	if err != nil || len(hookContent) == 0 {
		return nil, fileSnapshot{}, false, errors.New("post-hook source is not a stable non-empty file")
	}
	if err := validatePostHookOptIn(hookContent); err != nil {
		return nil, fileSnapshot{}, false, err
	}
	hookSnapshotMetadata, err := preparePrivateSnapshot(config.hookSnapshotPath, hookContent)
	if err != nil {
		return nil, fileSnapshot{}, false, err
	}
	interrupted, err := runSupervisedServiceChild([]string{"/bin/sh", config.hookSnapshotPath, "--preflight"}, os.Environ(), signals)
	if verifyErr := verifyPrivateSnapshot(config.hookSnapshotPath, hookSnapshotMetadata, hookContent, sourceKind{maximumBytes: 1024 * 1024}); verifyErr != nil {
		return nil, fileSnapshot{}, interrupted, verifyErr
	}
	if err != nil {
		return nil, fileSnapshot{}, interrupted, err
	}
	return hookContent, hookSnapshotMetadata, interrupted, nil
}

func runDumperPreflight(config dumperSupervisorConfig, signals <-chan os.Signal) error {
	if err := enableChildSubreaper(); err != nil {
		return err
	}
	if err := hardenDirectory(config.runtimeDirectory); err != nil {
		return err
	}
	_, _, interrupted, err := prepareSupervisorHook(config, signals)
	if interrupted {
		return childExitError{status: 143}
	}
	return err
}

func runDumperSupervisor(config dumperSupervisorConfig, signals <-chan os.Signal) error {
	if err := enableChildSubreaper(); err != nil {
		return err
	}
	if err := hardenDirectory(config.runtimeDirectory); err != nil {
		return err
	}
	if err := hardenDirectory(config.vendorOutputPath); err != nil {
		return err
	}
	hookContent, hookSnapshotMetadata, interrupted, err := prepareSupervisorHook(config, signals)
	if interrupted {
		return nil
	}
	if err != nil {
		return err
	}
	if _, err := preparePrivateSnapshot(config.readyPath, nil); err != nil {
		return err
	}
	outputRootFD, err := openOutputRoot(config.outputRoot)
	if err != nil {
		return err
	}
	currentAtStart, hasCurrentAtStart, err := currentGenerationTarget(outputRootFD)
	syscall.Close(outputRootFD)
	if err != nil {
		return err
	}
	startupKeep := map[string]bool{}
	if hasCurrentAtStart {
		startupKeep[currentAtStart] = true
	}
	if err := cleanupGenerationArtifacts(config.outputRoot, startupKeep); err != nil {
		return err
	}
	var lastPublishedDigest [sha256.Size]byte
	var lastPublishedExpected expectedDumpTree
	lastPublishedGeneration := ""
	hasPublishedDigest := false
	for {
		select {
		case <-signals:
			return nil
		default:
		}
		content, expected, ready, err := readReadyACMESource(config.sourcePath)
		if err != nil {
			return err
		}
		if !ready {
			if hasPublishedDigest {
				if err := validatePublishedState(config, lastPublishedGeneration, lastPublishedExpected, lastPublishedDigest); err != nil {
					return errors.New("last committed certificate state drifted while the ACME source was not ready")
				}
			}
			if waitForSupervisorPoll(signals, config.pollInterval) {
				return nil
			}
			continue
		}
		digest := sha256.Sum256(content)
		generationName := fmt.Sprintf("generation-%x", digest)
		if !hasPublishedDigest {
			rootFD, openErr := openOutputRoot(config.outputRoot)
			if openErr != nil {
				return openErr
			}
			current, hasCurrent, currentErr := currentGenerationTarget(rootFD)
			syscall.Close(rootFD)
			if currentErr != nil {
				return currentErr
			}
			if hasCurrent && current == generationName {
				if err := validatePublishedGeneration(filepath.Join(config.outputRoot, generationName), expected); err != nil {
					return errors.New("committed certificate generation drifted before supervisor restart")
				}
				readyContent := []byte(fmt.Sprintf("%x %s\n", digest, generationName))
				if _, err := preparePrivateSnapshot(config.readyPath, readyContent); err != nil {
					return err
				}
				if err := validatePublishedState(config, generationName, expected, digest); err != nil {
					return errors.New("restarted certificate state failed its post-readiness validation")
				}
				lastPublishedDigest = digest
				lastPublishedExpected = expected
				lastPublishedGeneration = generationName
				hasPublishedDigest = true
				if err := cleanupGenerationArtifacts(config.outputRoot, map[string]bool{generationName: true}); err != nil {
					return err
				}
				continue
			}
		}
		if hasPublishedDigest && digest == lastPublishedDigest {
			if err := validatePublishedState(config, generationName, expected, digest); err != nil {
				return err
			}
			if waitForSupervisorPoll(signals, config.pollInterval) {
				return nil
			}
			continue
		}
		snapshotMetadata, err := preparePrivateSnapshot(config.snapshotPath, content)
		if err != nil {
			return err
		}
		vendorCommand := []string{
			config.vendorExecutable, "file",
			"--domain-subdir", "--crt-ext=.pem", "--key-ext=.pem",
			"--version", "v3", "--clean=true",
			"--source", config.snapshotPath,
			"--dest", config.vendorOutputPath,
		}
		interrupted, err := runSupervisedServiceChild(vendorCommand, os.Environ(), signals)
		if interrupted {
			return nil
		}
		if err != nil {
			return err
		}
		if err := verifyPrivateSnapshot(config.snapshotPath, snapshotMetadata, content, sourceKind{maximumBytes: acmeStoreMaximumBytes, validateMetadata: validateACMESourceMetadata, validate: validateACMEStore}); err != nil {
			return err
		}
		if err := validateDumpTree(config.vendorOutputPath, expected); err != nil {
			return err
		}
		_, generationCreated, err := publishGeneration(config.outputRoot, generationName, expected)
		if err != nil {
			return err
		}
		commitPrecondition, err := snapshotOutputCommitState(config.outputRoot)
		if err != nil {
			return err
		}
		hookEnvironment := append(os.Environ(), "CERTS_DUMPER_OUTPUT_GENERATION="+config.vendorOutputPath)
		interrupted, hookErr := runSupervisedServiceChild([]string{"/bin/sh", config.hookSnapshotPath}, hookEnvironment, signals)
		hookSnapshotErr := verifyPrivateSnapshot(config.hookSnapshotPath, hookSnapshotMetadata, hookContent, sourceKind{maximumBytes: 1024 * 1024})
		vendorSnapshotErr := validateDumpTree(config.vendorOutputPath, expected)
		if interrupted || hookErr != nil {
			if hookSnapshotErr != nil {
				return hookSnapshotErr
			}
			if vendorSnapshotErr != nil {
				return vendorSnapshotErr
			}
			if generationCreated {
				rootFD, openErr := openOutputRoot(config.outputRoot)
				if openErr != nil {
					return openErr
				}
				current, hasCurrent, currentErr := currentGenerationTarget(rootFD)
				syscall.Close(rootFD)
				if currentErr != nil {
					return currentErr
				}
				keep := map[string]bool{}
				if hasCurrent {
					keep[current] = true
				}
				if err := cleanupGenerationArtifacts(config.outputRoot, keep); err != nil {
					return err
				}
			}
			if interrupted {
				return nil
			}
			return hookErr
		}
		if hookSnapshotErr != nil {
			return hookSnapshotErr
		}
		if vendorSnapshotErr != nil {
			return vendorSnapshotErr
		}
		if err := validatePublishedGeneration(filepath.Join(config.outputRoot, generationName), expected); err != nil {
			return errors.New("persistent certificate generation drifted while the external hook ran")
		}
		select {
		case <-signals:
			return nil
		default:
		}
		previous, hadPrevious, err := setCurrentGenerationChecked(config.outputRoot, generationName, expected, commitPrecondition)
		if err != nil {
			return err
		}
		readyContent := []byte(fmt.Sprintf("%x %s\n", digest, generationName))
		if _, err := preparePrivateSnapshot(config.readyPath, readyContent); err != nil {
			return err
		}
		if err := validatePublishedState(config, generationName, expected, digest); err != nil {
			return errors.New("published certificate state failed its post-readiness validation")
		}
		lastPublishedDigest = digest
		lastPublishedExpected = expected
		lastPublishedGeneration = generationName
		hasPublishedDigest = true
		retainedGenerations := map[string]bool{generationName: true}
		if hadPrevious {
			retainedGenerations[previous] = true
		}
		if err := cleanupGenerationArtifacts(config.outputRoot, retainedGenerations); err != nil {
			return err
		}
	}
}

func run(arguments []string) error {
	flags := flag.NewFlagSet("certs-dumper-safe-reader", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	kindName := flags.String("kind", "", "bounded source kind")
	source := flags.String("source", "", "source path")
	destination := flags.String("destination", "", "pre-created destination path")
	destinationIdentity := flags.String("destination-identity", "", "expected destination device:inode")
	digest := flags.Bool("digest", false, "print only the stable content digest")
	emit := flags.Bool("emit", false, "write only a validated DNS token to standard output")
	hardenDirectoryPath := flags.String("harden-directory", "", "create or harden one private state directory")
	hardenStateFilePath := flags.String("harden-state-file", "", "create or harden one private state file")
	removePrivatePath := flags.String("remove-private-file", "", "remove one identity-pinned private file")
	removePrivateIdentity := flags.String("remove-private-identity", "", "expected private-file device:inode")
	removePrivateParentIdentity := flags.String("remove-private-parent-identity", "", "expected cleanup-parent device:inode")
	withStateLock := flags.String("with-state-lock", "", "acquire one private state lock and exec the fixed hook command")
	validateStateLock := flags.String("validate-state-lock", "", "validate the inherited state-root and lock descriptors")
	prepareSSHStateRoot := flags.String("prepare-ssh-state", "", "prepare SSH state below the inherited state-root descriptor")
	syncKnownHostsPath := flags.String("sync-known-hosts", "", "durably sync one descriptor-pinned known_hosts state file")
	superviseDumperSource := flags.String("supervise-dumper-source", "", "supervise one descriptor-staged ACME source")
	preflightDumper := flags.Bool("preflight-dumper", false, "validate the staged post-hook and optional Mailcow integration")
	if err := flags.Parse(arguments); err != nil {
		return errors.New("invalid arguments")
	}
	if *superviseDumperSource != "" || *preflightDumper {
		if flags.NArg() != 0 || *kindName != "" || *source != "" || *destination != "" || *destinationIdentity != "" || *digest || *emit ||
			*hardenDirectoryPath != "" || *hardenStateFilePath != "" || *removePrivatePath != "" || *removePrivateIdentity != "" ||
			*removePrivateParentIdentity != "" || *withStateLock != "" || *validateStateLock != "" || *prepareSSHStateRoot != "" || *syncKnownHostsPath != "" ||
			(*superviseDumperSource != "" && *preflightDumper) {
			return errors.New("dumper supervision does not accept another action")
		}
		signals := make(chan os.Signal, 1)
		signal.Notify(signals, syscall.SIGHUP, syscall.SIGINT, syscall.SIGTERM)
		defer signal.Stop(signals)
		if *preflightDumper {
			return runDumperPreflight(productionSupervisorConfig(filepath.Join("/data", os.Getenv("ACME_FILENAME"))), signals)
		}
		cleanSource := filepath.Clean(*superviseDumperSource)
		if filepath.Dir(cleanSource) != "/data" || filepath.Base(cleanSource) == "." || filepath.Base(cleanSource) == ".." || cleanSource != *superviseDumperSource {
			return errors.New("supervised ACME source must be one canonical child of /data")
		}
		return runDumperSupervisor(productionSupervisorConfig(cleanSource), signals)
	}
	if *hardenDirectoryPath != "" || *hardenStateFilePath != "" {
		if flags.NArg() != 0 || (*hardenDirectoryPath == "") == (*hardenStateFilePath == "") ||
			*kindName != "" || *source != "" || *destination != "" || *destinationIdentity != "" || *digest || *emit ||
			*removePrivatePath != "" || *removePrivateIdentity != "" || *removePrivateParentIdentity != "" || *withStateLock != "" ||
			*validateStateLock != "" || *prepareSSHStateRoot != "" || *syncKnownHostsPath != "" {
			return errors.New("exactly one isolated state hardening action is required")
		}
		if *hardenDirectoryPath != "" {
			return hardenDirectory(*hardenDirectoryPath)
		}
		return hardenStateFile(*hardenStateFilePath)
	}
	if *removePrivatePath != "" || *removePrivateIdentity != "" || *removePrivateParentIdentity != "" {
		if flags.NArg() != 0 || *removePrivatePath == "" || *removePrivateIdentity == "" || *removePrivateParentIdentity == "" ||
			*kindName != "" || *source != "" || *destination != "" || *destinationIdentity != "" || *digest || *emit ||
			*hardenDirectoryPath != "" || *hardenStateFilePath != "" || *withStateLock != "" ||
			*validateStateLock != "" || *prepareSSHStateRoot != "" || *syncKnownHostsPath != "" {
			return errors.New("private cleanup requires only one path and identity")
		}
		return removePrivateFile(*removePrivatePath, *removePrivateIdentity, *removePrivateParentIdentity)
	}
	if *withStateLock != "" || *validateStateLock != "" || *prepareSSHStateRoot != "" || *syncKnownHostsPath != "" {
		selected := 0
		for _, value := range []string{*withStateLock, *validateStateLock, *prepareSSHStateRoot, *syncKnownHostsPath} {
			if value != "" {
				selected++
			}
		}
		if selected != 1 || *kindName != "" || *source != "" || *destination != "" ||
			*destinationIdentity != "" || *digest || *emit || *hardenDirectoryPath != "" ||
			*hardenStateFilePath != "" || *removePrivatePath != "" || *removePrivateIdentity != "" ||
			*removePrivateParentIdentity != "" {
			return errors.New("exactly one isolated state-lock action is required")
		}
		if *withStateLock != "" {
			return runWithStateLock(*withStateLock, flags.Args())
		}
		if flags.NArg() != 0 {
			return errors.New("state-lock validation actions do not accept positional arguments")
		}
		if *validateStateLock != "" {
			return validateStateLockContext(*validateStateLock, 3, 4)
		}
		if *prepareSSHStateRoot != "" {
			return prepareSSHState(*prepareSSHStateRoot, 3)
		}
		return syncKnownHostsState(*syncKnownHostsPath)
	}
	if *kindName == "" || *source == "" || flags.NArg() != 0 {
		return errors.New("kind and source are required without positional arguments")
	}
	kind, err := kindByName(*kindName)
	if err != nil {
		return err
	}
	if *digest && *emit {
		return errors.New("digest and emit modes are mutually exclusive")
	}
	if *digest {
		if (*kindName != "known-hosts" && *kindName != "acme-store" && *kindName != "supervisor-ready") || *destination != "" || *destinationIdentity != "" {
			return errors.New("digest mode is restricted to validated non-secret status sources")
		}
	} else if *emit {
		if *kindName != "dns-token" || *destination != "" || *destinationIdentity != "" {
			return errors.New("emit mode is restricted to DNS tokens without a destination")
		}
	} else if *destination == "" || *destinationIdentity == "" {
		return errors.New("copy mode requires a destination and its identity")
	}

	content, err := readStableSource(*source, kind)
	if err != nil {
		return err
	}
	if *digest {
		fmt.Printf("%x\n", sha256.Sum256(content))
		return nil
	}
	if *emit {
		_, err := os.Stdout.Write(content)
		return err
	}
	return writeStableDestination(*destination, *destinationIdentity, content)
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		var supervisedExit childExitError
		if errors.As(err, &supervisedExit) {
			os.Exit(supervisedExit.status)
		}
		fmt.Fprintln(os.Stderr, "certs-dumper-safe-reader: bounded file validation failed")
		os.Exit(1)
	}
}
