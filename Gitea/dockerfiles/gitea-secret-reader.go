// SPDX-License-Identifier: MIT
// Copyright (c) 2025 it.særvices
//
// Giteæ descriptor-bæsed Docker-secret reæder.
package main

import (
	"bytes"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"unicode"
	"unicode/utf8"
)

const (
	defaultSecretDirectory = "/run/secrets"
	maximumSecretBytes     = 4096
)

type fileIdentity struct {
	device     uint64
	inode      uint64
	mode       uint32
	linkCount  uint64
	size       int64
	uid        uint32
	gid        uint32
	modifySec  int64
	modifyNsec int64
	changeSec  int64
	changeNsec int64
}

func identityFromStat(stat *syscall.Stat_t) fileIdentity {
	return fileIdentity{
		device:     uint64(stat.Dev),
		inode:      stat.Ino,
		mode:       stat.Mode,
		linkCount:  uint64(stat.Nlink),
		size:       stat.Size,
		uid:        stat.Uid,
		gid:        stat.Gid,
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

func statPathNoFollow(path string) (fileIdentity, error) {
	var stat syscall.Stat_t
	if err := syscall.Lstat(path, &stat); err != nil {
		return fileIdentity{}, err
	}
	return identityFromStat(&stat), nil
}

func statDescriptor(fileDescriptor int) (fileIdentity, error) {
	var stat syscall.Stat_t
	if err := syscall.Fstat(fileDescriptor, &stat); err != nil {
		return fileIdentity{}, err
	}
	return identityFromStat(&stat), nil
}

func openStableDirectory(path string) (int, fileIdentity, error) {
	pathIdentity, err := statPathNoFollow(path)
	if err != nil {
		return -1, fileIdentity{}, errors.New("cannot inspect secret directory")
	}
	if pathIdentity.mode&syscall.S_IFMT != syscall.S_IFDIR {
		return -1, fileIdentity{}, errors.New("secret directory is not a directory")
	}
	directoryDescriptor, err := syscall.Open(
		path,
		syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC,
		0,
	)
	if err != nil {
		return -1, fileIdentity{}, errors.New("cannot open secret directory safely")
	}
	openedIdentity, err := statDescriptor(directoryDescriptor)
	if err != nil {
		syscall.Close(directoryDescriptor)
		return -1, fileIdentity{}, errors.New("cannot inspect opened secret directory")
	}
	if openedIdentity != pathIdentity || openedIdentity.mode&syscall.S_IFMT != syscall.S_IFDIR {
		syscall.Close(directoryDescriptor)
		return -1, fileIdentity{}, errors.New("secret directory changed while it was opened")
	}
	return directoryDescriptor, openedIdentity, nil
}

func openRegularAt(directoryDescriptor int, name string) (int, fileIdentity, error) {
	fileDescriptor, err := syscall.Openat(
		directoryDescriptor,
		name,
		syscall.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC,
		0,
	)
	if err != nil {
		return -1, fileIdentity{}, errors.New("cannot open secret safely")
	}
	identity, err := statDescriptor(fileDescriptor)
	if err != nil {
		syscall.Close(fileDescriptor)
		return -1, fileIdentity{}, errors.New("cannot inspect opened secret")
	}
	if identity.mode&syscall.S_IFMT != syscall.S_IFREG {
		syscall.Close(fileDescriptor)
		return -1, fileIdentity{}, errors.New("secret is not a regular file")
	}
	if identity.linkCount != 1 {
		syscall.Close(fileDescriptor)
		return -1, fileIdentity{}, errors.New("secret must have exactly one hard link")
	}
	if identity.size < 1 || identity.size > maximumSecretBytes {
		syscall.Close(fileDescriptor)
		return -1, fileIdentity{}, errors.New("secret has an invalid length")
	}
	return fileDescriptor, identity, nil
}

func validateSecretValue(value []byte) error {
	if len(value) == 0 || len(value) > maximumSecretBytes {
		return errors.New("secret has an invalid length")
	}
	if bytes.Equal(value, []byte("CHANGE_ME")) {
		return errors.New("secret still contains the placeholder")
	}
	if !utf8.Valid(value) {
		return errors.New("secret is not valid UTF-8")
	}
	for _, character := range string(value) {
		if unicode.IsControl(character) || unicode.In(character, unicode.Zl, unicode.Zp) {
			return errors.New("secret contains control or line-separator characters")
		}
	}
	return nil
}

func readStableSecret(secretDirectory, name string) ([]byte, error) {
	return readStableSecretWithHook(secretDirectory, name, nil)
}

func readStableSecretWithHook(secretDirectory, name string, afterRead func()) ([]byte, error) {
	if name == "" || name != filepath.Base(name) || strings.ContainsRune(name, '/') || name == "." || name == ".." {
		return nil, errors.New("invalid secret name")
	}

	directoryDescriptor, directoryIdentity, err := openStableDirectory(secretDirectory)
	if err != nil {
		return nil, err
	}
	defer syscall.Close(directoryDescriptor)

	fileDescriptor, beforeIdentity, err := openRegularAt(directoryDescriptor, name)
	if err != nil {
		return nil, err
	}
	file := os.NewFile(uintptr(fileDescriptor), name)
	if file == nil {
		syscall.Close(fileDescriptor)
		return nil, errors.New("cannot bind secret descriptor")
	}
	defer file.Close()

	value, err := io.ReadAll(io.LimitReader(file, maximumSecretBytes+1))
	if err != nil {
		wipe(value)
		return nil, errors.New("cannot read secret safely")
	}
	if afterRead != nil {
		afterRead()
	}
	if int64(len(value)) != beforeIdentity.size || len(value) > maximumSecretBytes {
		wipe(value)
		return nil, errors.New("secret changed while it was read")
	}

	afterIdentity, err := statDescriptor(fileDescriptor)
	if err != nil || afterIdentity != beforeIdentity {
		wipe(value)
		return nil, errors.New("secret identity changed while it was read")
	}
	afterDirectoryIdentity, err := statDescriptor(directoryDescriptor)
	if err != nil || afterDirectoryIdentity != directoryIdentity {
		wipe(value)
		return nil, errors.New("secret directory changed while it was read")
	}
	afterPathIdentity, err := statPathNoFollow(secretDirectory)
	if err != nil || afterPathIdentity != directoryIdentity {
		wipe(value)
		return nil, errors.New("secret directory path changed while it was read")
	}

	verificationDescriptor, verificationIdentity, err := openRegularAt(directoryDescriptor, name)
	if err != nil {
		wipe(value)
		return nil, errors.New("cannot verify secret path after reading")
	}
	syscall.Close(verificationDescriptor)
	if verificationIdentity != beforeIdentity {
		wipe(value)
		return nil, errors.New("secret path changed while it was read")
	}
	if err := validateSecretValue(value); err != nil {
		wipe(value)
		return nil, err
	}
	return value, nil
}

func run(arguments []string, standardOutput io.Writer, standardError io.Writer) int {
	flags := flag.NewFlagSet("gitea-secret-reader", flag.ContinueOnError)
	flags.SetOutput(standardError)
	secretDirectory := flags.String("directory", defaultSecretDirectory, "Docker secret directory")
	if err := flags.Parse(arguments); err != nil || flags.NArg() != 1 {
		fmt.Fprintln(standardError, "gitea-secret-reader: expected exactly one secret name")
		return 2
	}
	name := flags.Arg(0)
	value, err := readStableSecret(*secretDirectory, name)
	if err != nil {
		fmt.Fprintf(standardError, "gitea-secret-reader: %s: %v\n", name, err)
		return 1
	}
	defer wipe(value)
	if _, err := standardOutput.Write(value); err != nil {
		fmt.Fprintf(standardError, "gitea-secret-reader: %s: cannot write validated secret\n", name)
		return 1
	}
	return 0
}

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}
