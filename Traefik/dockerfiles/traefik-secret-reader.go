// SPDX-License-Identifier: MIT
// Copyright (c) 2025 it.særvices

package main

import (
	"bytes"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/netip"
	"os"
	"path/filepath"
	"syscall"
	"unicode/utf8"
)

var (
	runtimeSecretBeforeFinalHook func(string)
	runtimeSecretAfterReadHook   func(string)
	secretCopyBeforeFinalHook    func(string)
	secretCopyAfterReadHook      func(string)
)

const (
	maximumSecretBytes = 4096
	runtimeDirectory   = "/run/traefik-secrets"
	runtimeFilename    = "DNS_API_TOKEN"
)

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

func validateSourceSnapshot(current fileSnapshot) error {
	if current.mode&syscall.S_IFMT != syscall.S_IFREG {
		return errors.New("source is not a regular file")
	}
	if current.links != 1 {
		return errors.New("source must have exactly one link")
	}
	if current.size < 1 || current.size > maximumSecretBytes {
		return errors.New("source size is outside the accepted range")
	}
	return nil
}

func validateSecretContent(secret []byte, allowPlaceholder bool) error {
	if len(secret) < 1 || len(secret) > maximumSecretBytes {
		return errors.New("secret length is outside the accepted range")
	}
	if !utf8.Valid(secret) {
		return errors.New("secret is not valid UTF-8")
	}
	if string(secret) == "CHANGE_ME" && !allowPlaceholder {
		return errors.New("secret is still the placeholder")
	}
	for _, character := range secret {
		if character < 0x21 || character > 0x7e {
			return errors.New("secret contains bytes outside printable non-whitespace ASCII")
		}
	}
	return nil
}

func validateForwardedHeaderSource(candidate string) error {
	if candidate == "" {
		return errors.New("forwarded-header source is empty")
	}
	if prefix, err := netip.ParsePrefix(candidate); err == nil {
		address := prefix.Addr()
		if address.Zone() != "" || prefix.Bits() < 1 || prefix != prefix.Masked() || prefix.String() != candidate {
			return errors.New("forwarded-header CIDR is not canonical")
		}
		return nil
	}
	address, err := netip.ParseAddr(candidate)
	if err != nil || address.Zone() != "" || address.String() != candidate {
		return errors.New("forwarded-header address is invalid or non-canonical")
	}
	return nil
}

func readSecretWithHook(path string, afterOpen func(), allowPlaceholder bool) ([]byte, error) {
	pathBefore, err := statPathNoFollow(path)
	if err != nil {
		return nil, fmt.Errorf("inspect source path: %w", err)
	}
	if err := validateSourceSnapshot(pathBefore); err != nil {
		return nil, err
	}

	fd, err := syscall.Open(path, syscall.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return nil, fmt.Errorf("open source safely: %w", err)
	}
	file := os.NewFile(uintptr(fd), "dns-api-token")
	defer file.Close()

	descriptorBefore, err := statDescriptor(fd)
	if err != nil {
		return nil, fmt.Errorf("inspect opened source: %w", err)
	}
	if err := validateSourceSnapshot(descriptorBefore); err != nil {
		return nil, err
	}
	if pathBefore != descriptorBefore {
		return nil, errors.New("source identity changed while it was opened")
	}
	if afterOpen != nil {
		afterOpen()
	}

	secret, err := io.ReadAll(io.LimitReader(file, maximumSecretBytes+1))
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
	if int64(len(secret)) != descriptorBefore.size {
		return nil, errors.New("source length changed while it was read")
	}
	if err := validateSecretContent(secret, allowPlaceholder); err != nil {
		return nil, err
	}
	return secret, nil
}

func readSecret(path string) ([]byte, error) {
	return readSecretWithHook(path, nil, false)
}

func validatePlaceholder(path string) error {
	secret, err := readSecretWithHook(path, nil, true)
	if err != nil {
		return err
	}
	if string(secret) != "CHANGE_ME" {
		return errors.New("secret is not the exact placeholder")
	}
	return nil
}

func validateACMEStoreSnapshot(current fileSnapshot) error {
	if current.mode&syscall.S_IFMT != syscall.S_IFREG {
		return errors.New("ACME store is not a regular file")
	}
	if current.links != 1 {
		return errors.New("ACME store must have exactly one link")
	}
	if int(current.uid) != os.Geteuid() || int(current.gid) != os.Getegid() {
		return errors.New("ACME store is not owned by the runtime user")
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

func sameACMEStoreDataState(first fileSnapshot, second fileSnapshot) bool {
	return first.device == second.device &&
		first.inode == second.inode &&
		first.mode&syscall.S_IFMT == second.mode&syscall.S_IFMT &&
		first.links == second.links &&
		first.size == second.size &&
		first.uid == second.uid &&
		first.gid == second.gid &&
		first.modifiedSec == second.modifiedSec &&
		first.modifiedNS == second.modifiedNS
}

func hardenACMEStoreWithHook(path string, afterInspect func()) error {
	parentPath, baseName := filepath.Split(path)
	parentPath = filepath.Clean(parentPath)
	if parentPath == "." || baseName == "" || baseName == "." || baseName == ".." || filepath.Base(baseName) != baseName {
		return errors.New("ACME store path must include one safe basename")
	}
	parentBefore, err := statPathNoFollow(parentPath)
	if err != nil {
		return fmt.Errorf("inspect ACME storage directory: %w", err)
	}
	if parentBefore.mode&syscall.S_IFMT != syscall.S_IFDIR || int(parentBefore.uid) != os.Geteuid() || int(parentBefore.gid) != os.Getegid() {
		return errors.New("ACME storage directory is not a real runtime-owned directory")
	}
	parentFD, err := syscall.Open(parentPath, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return fmt.Errorf("open ACME storage directory safely: %w", err)
	}
	defer syscall.Close(parentFD)
	parentDescriptorBefore, err := statDescriptor(parentFD)
	if err != nil {
		return fmt.Errorf("inspect opened ACME storage directory: %w", err)
	}
	if parentDescriptorBefore != parentBefore {
		return errors.New("ACME storage directory changed while it was opened")
	}
	pathThroughParent := fmt.Sprintf("/proc/self/fd/%d/%s", parentFD, baseName)
	pathBefore, err := statPathNoFollow(pathThroughParent)
	if errors.Is(err, syscall.ENOENT) {
		fd, openErr := syscall.Openat(
			parentFD,
			baseName,
			syscall.O_RDWR|syscall.O_CREAT|syscall.O_EXCL|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC,
			0o600,
		)
		if openErr != nil {
			return fmt.Errorf("create ACME store safely: %w", openErr)
		}
		file := os.NewFile(uintptr(fd), "acme-store")
		defer file.Close()
		descriptor, statErr := statDescriptor(fd)
		if statErr != nil {
			return fmt.Errorf("inspect created ACME store: %w", statErr)
		}
		pathAfter, statErr := statPathNoFollow(pathThroughParent)
		if statErr != nil {
			return fmt.Errorf("reinspect created ACME store: %w", statErr)
		}
		if descriptor != pathAfter {
			return errors.New("created ACME store path does not match its descriptor")
		}
		if err := validateACMEStoreSnapshot(descriptor); err != nil {
			return err
		}
		if descriptor.mode&0o777 != 0o600 {
			return errors.New("created ACME store is not mode 0600")
		}
		if err := file.Sync(); err != nil {
			return err
		}
		parentDescriptorAfter, statErr := statDescriptor(parentFD)
		if statErr != nil {
			return fmt.Errorf("reinspect opened ACME storage directory: %w", statErr)
		}
		parentPathAfter, statErr := statPathNoFollow(parentPath)
		if statErr != nil || parentPathAfter != parentDescriptorAfter || !sameDirectoryBinding(parentBefore, parentDescriptorAfter) {
			return errors.New("ACME storage directory binding changed during store creation")
		}
		return nil
	}
	if err != nil {
		return fmt.Errorf("inspect ACME store path: %w", err)
	}
	if err := validateACMEStoreSnapshot(pathBefore); err != nil {
		return err
	}
	if afterInspect != nil {
		afterInspect()
	}

	fd, err := syscall.Openat(parentFD, baseName, syscall.O_RDWR|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return fmt.Errorf("open ACME store safely: %w", err)
	}
	file := os.NewFile(uintptr(fd), "acme-store")
	defer file.Close()
	descriptorBefore, err := statDescriptor(fd)
	if err != nil {
		return fmt.Errorf("inspect opened ACME store: %w", err)
	}
	if descriptorBefore != pathBefore {
		return errors.New("ACME store identity changed while it was opened")
	}
	if err := validateACMEStoreSnapshot(descriptorBefore); err != nil {
		return err
	}
	if err := syscall.Fchmod(fd, 0o600); err != nil {
		return fmt.Errorf("harden opened ACME store: %w", err)
	}
	if err := file.Sync(); err != nil {
		return err
	}
	descriptorAfter, err := statDescriptor(fd)
	if err != nil {
		return fmt.Errorf("reinspect opened ACME store: %w", err)
	}
	pathAfter, err := statPathNoFollow(pathThroughParent)
	if err != nil {
		return fmt.Errorf("reinspect ACME store path: %w", err)
	}
	if descriptorAfter != pathAfter || !sameACMEStoreDataState(descriptorBefore, descriptorAfter) {
		return errors.New("ACME store path changed while permissions were enforced")
	}
	if err := validateACMEStoreSnapshot(descriptorAfter); err != nil {
		return err
	}
	if descriptorAfter.mode&0o777 != 0o600 {
		return errors.New("ACME store is not mode 0600")
	}
	parentDescriptorAfter, err := statDescriptor(parentFD)
	if err != nil {
		return fmt.Errorf("reinspect opened ACME storage directory: %w", err)
	}
	parentPathAfter, err := statPathNoFollow(parentPath)
	if err != nil || parentPathAfter != parentDescriptorAfter || !sameDirectoryBinding(parentBefore, parentDescriptorAfter) {
		return errors.New("ACME storage directory binding changed during store hardening")
	}
	return nil
}

func hardenACMEStore(path string) error {
	return hardenACMEStoreWithHook(path, nil)
}

func openRuntimeDirectory(path string) (int, error) {
	if err := syscall.Mkdir(path, 0o700); err != nil && !errors.Is(err, syscall.EEXIST) {
		return -1, err
	}
	fd, err := syscall.Open(path, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_CLOEXEC, 0)
	if err != nil {
		return -1, err
	}
	descriptor, err := statDescriptor(fd)
	if err != nil {
		syscall.Close(fd)
		return -1, err
	}
	pathInfo, err := statPathNoFollow(path)
	if err != nil {
		syscall.Close(fd)
		return -1, err
	}
	if descriptor != pathInfo || descriptor.mode&syscall.S_IFMT != syscall.S_IFDIR || descriptor.mode&0o777 != 0o700 || int(descriptor.uid) != os.Geteuid() || int(descriptor.gid) != os.Getegid() {
		syscall.Close(fd)
		return -1, errors.New("runtime directory is not a private owned directory")
	}
	return fd, nil
}

func publishSecret(directoryPath string, filename string, secret []byte) error {
	directoryFD, err := openRuntimeDirectory(directoryPath)
	if err != nil {
		return fmt.Errorf("open runtime directory: %w", err)
	}
	defer syscall.Close(directoryFD)

	fd, err := syscall.Openat(directoryFD, filename, syscall.O_RDWR|syscall.O_CREAT|syscall.O_EXCL|syscall.O_NOFOLLOW|syscall.O_CLOEXEC, 0o600)
	if err != nil {
		return fmt.Errorf("create runtime secret: %w", err)
	}
	file := os.NewFile(uintptr(fd), "validated-dns-api-token")
	defer file.Close()

	written := 0
	for written < len(secret) {
		count, writeErr := file.Write(secret[written:])
		if writeErr != nil {
			return fmt.Errorf("write runtime secret: %w", writeErr)
		}
		if count == 0 {
			return io.ErrShortWrite
		}
		written += count
	}
	if err := file.Sync(); err != nil {
		return fmt.Errorf("sync runtime secret: %w", err)
	}
	runtimeSecretPath := fmt.Sprintf("/proc/self/fd/%d/%s", directoryFD, filename)
	writeCompleteSnapshot, err := statDescriptor(fd)
	writeCompletePath, writeCompletePathErr := statPathNoFollow(runtimeSecretPath)
	if err != nil || writeCompletePathErr != nil || writeCompleteSnapshot != writeCompletePath {
		return errors.New("runtime secret changed when its write completed")
	}
	if writeCompleteSnapshot.mode&syscall.S_IFMT != syscall.S_IFREG || writeCompleteSnapshot.mode&0o777 != 0o600 || writeCompleteSnapshot.links != 1 || writeCompleteSnapshot.size != int64(len(secret)) || int(writeCompleteSnapshot.uid) != os.Geteuid() || int(writeCompleteSnapshot.gid) != os.Getegid() {
		return errors.New("runtime secret has unsafe completed-write metadata")
	}
	if runtimeSecretBeforeFinalHook != nil {
		runtimeSecretBeforeFinalHook(runtimeSecretPath)
	}
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return fmt.Errorf("rewind runtime secret for verification: %w", err)
	}
	writtenSecret, err := io.ReadAll(io.LimitReader(file, int64(len(secret))+1))
	if err != nil || !bytes.Equal(writtenSecret, secret) {
		return errors.New("runtime secret bytes do not match the validated source")
	}
	if runtimeSecretAfterReadHook != nil {
		runtimeSecretAfterReadHook(runtimeSecretPath)
	}
	info, err := statDescriptor(fd)
	if err != nil {
		return fmt.Errorf("inspect runtime secret: %w", err)
	}
	if info.mode&syscall.S_IFMT != syscall.S_IFREG || info.mode&0o777 != 0o600 || info.links != 1 || info.size != int64(len(secret)) || int(info.uid) != os.Geteuid() || int(info.gid) != os.Getegid() {
		return errors.New("runtime secret has unsafe metadata")
	}
	directoryAfter, err := statPathNoFollow(directoryPath)
	if err != nil {
		return fmt.Errorf("reinspect runtime directory: %w", err)
	}
	directoryDescriptor, err := statDescriptor(directoryFD)
	if err != nil {
		return fmt.Errorf("reinspect opened runtime directory: %w", err)
	}
	pathAfter, err := statPathNoFollow(runtimeSecretPath)
	if err != nil {
		return fmt.Errorf("reinspect runtime secret path: %w", err)
	}
	if directoryAfter != directoryDescriptor || info != writeCompleteSnapshot || pathAfter != writeCompleteSnapshot {
		return errors.New("runtime secret path changed while it was published")
	}
	return nil
}

func copySecretToDestination(path string, secret []byte) error {
	parentPath, baseName := filepath.Split(filepath.Clean(path))
	parentPath = filepath.Clean(parentPath)
	if parentPath == "." || baseName == "" || baseName == "." || baseName == ".." || filepath.Base(baseName) != baseName {
		return errors.New("secret-copy destination must include one safe basename")
	}
	parentBefore, err := statPathNoFollow(parentPath)
	if err != nil || parentBefore.mode&syscall.S_IFMT != syscall.S_IFDIR || int(parentBefore.uid) != os.Geteuid() || int(parentBefore.gid) != os.Getegid() {
		return errors.New("secret-copy destination parent is not a real runtime-owned directory")
	}
	parentFD, err := syscall.Open(parentPath, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return fmt.Errorf("open secret-copy destination parent: %w", err)
	}
	defer syscall.Close(parentFD)
	parentDescriptor, err := statDescriptor(parentFD)
	if err != nil || parentDescriptor != parentBefore {
		return errors.New("secret-copy destination parent changed while it was opened")
	}
	fd, err := syscall.Openat(parentFD, baseName, syscall.O_RDWR|syscall.O_CREAT|syscall.O_EXCL|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0o600)
	if err != nil {
		return fmt.Errorf("create exclusive secret-copy destination: %w", err)
	}
	file := os.NewFile(uintptr(fd), "secret-copy-destination")
	defer file.Close()
	created, err := statDescriptor(fd)
	if err != nil || created.mode&syscall.S_IFMT != syscall.S_IFREG || created.links != 1 || created.mode&0o777 != 0o600 || int(created.uid) != os.Geteuid() || int(created.gid) != os.Getegid() || created.size != 0 {
		return errors.New("secret-copy destination has unsafe initial metadata")
	}
	createdPath := fmt.Sprintf("/proc/self/fd/%d/%s", parentFD, baseName)
	createdPathSnapshot, err := statPathNoFollow(createdPath)
	if err != nil || createdPathSnapshot != created {
		return errors.New("secret-copy destination path does not match its descriptor")
	}
	for written := 0; written < len(secret); {
		count, writeErr := file.Write(secret[written:])
		if writeErr != nil {
			return fmt.Errorf("write secret-copy destination: %w", writeErr)
		}
		if count == 0 {
			return io.ErrShortWrite
		}
		written += count
	}
	if err := file.Sync(); err != nil {
		return fmt.Errorf("sync secret-copy destination: %w", err)
	}
	writeCompleteSnapshot, descriptorErr := statDescriptor(fd)
	writeCompletePath, pathErr := statPathNoFollow(createdPath)
	if descriptorErr != nil || pathErr != nil || writeCompleteSnapshot != writeCompletePath ||
		writeCompleteSnapshot.device != created.device || writeCompleteSnapshot.inode != created.inode ||
		writeCompleteSnapshot.mode&syscall.S_IFMT != syscall.S_IFREG || writeCompleteSnapshot.links != 1 || writeCompleteSnapshot.mode&0o777 != 0o600 ||
		int(writeCompleteSnapshot.uid) != os.Geteuid() || int(writeCompleteSnapshot.gid) != os.Getegid() || writeCompleteSnapshot.size != int64(len(secret)) {
		return errors.New("secret-copy destination has unsafe completed-write metadata")
	}
	if secretCopyBeforeFinalHook != nil {
		secretCopyBeforeFinalHook(createdPath)
	}
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return fmt.Errorf("rewind secret-copy destination for verification: %w", err)
	}
	writtenSecret, err := io.ReadAll(io.LimitReader(file, int64(len(secret))+1))
	if err != nil || !bytes.Equal(writtenSecret, secret) {
		return errors.New("secret-copy destination bytes do not match the validated source")
	}
	if secretCopyAfterReadHook != nil {
		secretCopyAfterReadHook(createdPath)
	}
	finalDescriptor, descriptorErr := statDescriptor(fd)
	finalPath, pathErr := statPathNoFollow(createdPath)
	parentAfter, parentDescriptorErr := statDescriptor(parentFD)
	parentPathAfter, parentPathErr := statPathNoFollow(parentPath)
	if descriptorErr != nil || pathErr != nil || parentDescriptorErr != nil || parentPathErr != nil ||
		finalDescriptor != writeCompleteSnapshot || finalPath != writeCompleteSnapshot || finalDescriptor.device != created.device || finalDescriptor.inode != created.inode ||
		finalDescriptor.mode&syscall.S_IFMT != syscall.S_IFREG || finalDescriptor.links != 1 || finalDescriptor.mode&0o777 != 0o600 ||
		int(finalDescriptor.uid) != os.Geteuid() || int(finalDescriptor.gid) != os.Getegid() || finalDescriptor.size != int64(len(secret)) ||
		!sameDirectoryBinding(parentBefore, parentAfter) || !sameDirectoryBinding(parentBefore, parentPathAfter) {
		return errors.New("secret-copy destination changed while it was published")
	}
	if err := syscall.Fsync(parentFD); err != nil {
		return fmt.Errorf("sync secret-copy destination parent: %w", err)
	}
	return nil
}

func run(arguments []string) error {
	flags := flag.NewFlagSet("traefik-secret-reader", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	source := flags.String("source", "", "Docker secret source path")
	placeholder := flags.String("validate-placeholder", "", "validate an exact CHANGE_ME placeholder")
	acmeStore := flags.String("acme-store", "", "ACME store path to create or harden")
	forwardedSource := flags.String("validate-forwarded-source", "", "validate one canonical forwarded-header address or CIDR")
	copyDestination := flags.String("copy-secret-to", "", "exclusive verified migration destination for the validated source")
	if err := flags.Parse(arguments); err != nil {
		return errors.New("invalid arguments")
	}
	selected := 0
	for _, value := range []string{*source, *acmeStore, *forwardedSource, *placeholder} {
		if value != "" {
			selected++
		}
	}
	if flags.NArg() != 0 || selected != 1 || (*copyDestination != "" && *source == "") {
		return errors.New("exactly one source, ACME store path, or forwarded-header source is required")
	}
	if *forwardedSource != "" {
		return validateForwardedHeaderSource(*forwardedSource)
	}
	if *placeholder != "" {
		return validatePlaceholder(*placeholder)
	}
	if *acmeStore != "" {
		return hardenACMEStore(*acmeStore)
	}
	secret, err := readSecret(*source)
	if err != nil {
		return err
	}
	if *copyDestination != "" {
		return copySecretToDestination(*copyDestination, secret)
	}
	return publishSecret(runtimeDirectory, runtimeFilename, secret)
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "traefik-secret-reader: bounded file validation failed")
		os.Exit(1)
	}
}
