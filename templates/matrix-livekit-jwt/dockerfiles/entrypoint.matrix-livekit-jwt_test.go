// SPDX-License-Identifier: MIT
// Copyright (c) 2025 it.særvices

package main

import (
	"bytes"
	"os"
	"syscall"
	"testing"
	"time"
)

func TestExitCode(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name      string
		status    syscall.WaitStatus
		forwarded syscall.Signal
		want      int
	}{
		{name: "success", status: 0, want: 0},
		{name: "ordinary failure", status: 23 << 8, want: 23},
		{name: "forwarded term signal", status: syscall.WaitStatus(syscall.SIGTERM), forwarded: syscall.SIGTERM, want: 0},
		{name: "forwarded int shell status", status: syscall.WaitStatus((128 + int(syscall.SIGINT)) << 8), forwarded: syscall.SIGINT, want: 0},
		{name: "unexpected kill", status: syscall.WaitStatus(syscall.SIGKILL), forwarded: syscall.SIGTERM, want: 137},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			if got := exitCode(test.status, test.forwarded); got != test.want {
				t.Fatalf("exitCode() = %d, want %d", got, test.want)
			}
		})
	}
}

func TestSupervisorForwardsAndNormalizesShutdownSignals(t *testing.T) {
	for _, shutdownSignal := range []syscall.Signal{syscall.SIGTERM, syscall.SIGINT} {
		shutdownSignal := shutdownSignal
		t.Run(shutdownSignal.String(), func(t *testing.T) {
			signals := make(chan os.Signal, 1)
			started := make(chan int, 1)
			result := make(chan int, 1)
			var stderr bytes.Buffer

			go func() {
				result <- supervise(helperCommand("wait"), signals, nil, &bytes.Buffer{}, &stderr, started)
			}()
			select {
			case <-started:
			case <-time.After(5 * time.Second):
				t.Fatal("supervisor did not start helper")
			}
			signals <- shutdownSignal

			select {
			case code := <-result:
				if code != 0 {
					t.Fatalf("supervisor exit = %d, want 0; stderr=%s", code, stderr.String())
				}
			case <-time.After(5 * time.Second):
				t.Fatal("supervisor did not finish after forwarded signal")
			}
		})
	}
}

func TestSupervisorPropagatesOrdinaryFailure(t *testing.T) {
	started := make(chan int, 1)
	if got := supervise(helperCommand("exit-23"), nil, nil, &bytes.Buffer{}, &bytes.Buffer{}, started); got != 23 {
		t.Fatalf("supervisor exit = %d, want 23", got)
	}
}

func TestSupervisorPropagatesUnexpectedSignal(t *testing.T) {
	started := make(chan int, 1)
	if got := supervise(helperCommand("self-kill"), nil, nil, &bytes.Buffer{}, &bytes.Buffer{}, started); got != 137 {
		t.Fatalf("supervisor exit = %d, want 137", got)
	}
}

func helperCommand(mode string) []string {
	return []string{os.Args[0], "-test.run=^TestSupervisorHelperProcess$", "--", mode}
}

func TestSupervisorHelperProcess(t *testing.T) {
	mode := ""
	for index, argument := range os.Args {
		if argument == "--" && index+1 < len(os.Args) {
			mode = os.Args[index+1]
			break
		}
	}

	switch mode {
	case "":
		return
	case "wait":
		for {
			time.Sleep(time.Hour)
		}
	case "exit-23":
		os.Exit(23)
	case "self-kill":
		if err := syscall.Kill(os.Getpid(), syscall.SIGKILL); err != nil {
			t.Fatalf("could not signal helper: %v", err)
		}
		for {
			time.Sleep(time.Hour)
		}
	default:
		t.Fatalf("unknown helper mode %q", mode)
	}
}
