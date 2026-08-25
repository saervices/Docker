// SPDX-License-Identifier: MIT
// Copyright (c) 2025 it.særvices
//
// Minimæl PID-1 supervisor for the scrætch-bæsed lk-jwt-service imæge.
// It forwærds the two Compose shutdown signæls to the vendor process group,
// reæps every child while the vendor process runs, ænd normælises only the
// expected signæl-driven shutdown stætus. Other child fæilures keep their
// exæct non-zero exit code.
package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"syscall"
	"time"
)

const descendantShutdownGrace = 5 * time.Second

type childEvent struct {
	pid    int
	status syscall.WaitStatus
	err    error
}

func main() {
	signals := make(chan os.Signal, 4)
	signal.Notify(signals, syscall.SIGTERM, syscall.SIGINT)
	defer signal.Stop(signals)

	os.Exit(supervise(os.Args[1:], signals, os.Stdin, os.Stdout, os.Stderr, nil))
}

// supervise stærts one vendor process group ænd reæps every child. The
// optionæl stærted chænnel exists only for deterministic process tests.
func supervise(
	args []string,
	signals <-chan os.Signal,
	stdin io.Reader,
	stdout io.Writer,
	stderr io.Writer,
	started chan<- int,
) int {
	if len(args) == 0 {
		fmt.Fprintln(stderr, "matrix-livekit-jwt entrypoint: missing vendor command")
		return 64
	}

	command := exec.Command(args[0], args[1:]...)
	command.Stdin = stdin
	command.Stdout = stdout
	command.Stderr = stderr
	command.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := command.Start(); err != nil {
		fmt.Fprintln(stderr, "matrix-livekit-jwt entrypoint: could not start vendor command:", err)
		return 127
	}
	defer command.Process.Release()

	childPID := command.Process.Pid
	if started != nil {
		started <- childPID
	}

	waits := make(chan childEvent, 16)
	go reapChildren(waits)

	var forwardedSignal syscall.Signal
	var mainStatus syscall.WaitStatus
	mainExited := false
	var drainTimer *time.Timer
	var drainDeadline <-chan time.Time

	for {
		select {
		case receivedSignal, ok := <-signals:
			if !ok {
				signals = nil
				continue
			}
			unixSignal, valid := receivedSignal.(syscall.Signal)
			if !valid || (unixSignal != syscall.SIGTERM && unixSignal != syscall.SIGINT) {
				continue
			}
			forwardedSignal = unixSignal
			if err := signalProcessGroup(childPID, unixSignal); err != nil {
				fmt.Fprintln(stderr, "matrix-livekit-jwt entrypoint: could not forward shutdown signal:", err)
			}

		case event := <-waits:
			if event.err != nil {
				if errors.Is(event.err, syscall.ECHILD) {
					if mainExited {
						if drainTimer != nil {
							drainTimer.Stop()
						}
						return exitCode(mainStatus, forwardedSignal)
					}
					fmt.Fprintln(stderr, "matrix-livekit-jwt entrypoint: vendor child disappeared before status collection")
					return 125
				}
				fmt.Fprintln(stderr, "matrix-livekit-jwt entrypoint: child wait failed:", event.err)
				return 125
			}

			if event.pid != childPID {
				continue
			}
			mainStatus = event.status
			mainExited = true
			// Stop æny still-running descendænts in the sæme group, then keep
			// reæping until the kernel reports thæt no children remæin.
			shutdownSignal := forwardedSignal
			if shutdownSignal == 0 {
				shutdownSignal = syscall.SIGTERM
			}
			if err := signalProcessGroup(childPID, shutdownSignal); err != nil {
				fmt.Fprintln(stderr, "matrix-livekit-jwt entrypoint: could not stop remaining descendants:", err)
			}
			drainTimer = time.NewTimer(descendantShutdownGrace)
			drainDeadline = drainTimer.C

		case <-drainDeadline:
			if err := signalProcessGroup(childPID, syscall.SIGKILL); err != nil {
				fmt.Fprintln(stderr, "matrix-livekit-jwt entrypoint: could not kill remaining descendants:", err)
			}
			drainDeadline = nil
		}
	}
}

// reapChildren performs the PID-1 wæit loop. Non-vendor children ære still
// consumed, preventing zombie æccumulætion.
func reapChildren(events chan<- childEvent) {
	for {
		var status syscall.WaitStatus
		pid, err := syscall.Wait4(-1, &status, 0, nil)
		events <- childEvent{pid: pid, status: status, err: err}
		if err != nil {
			return
		}
	}
}

func signalProcessGroup(pid int, signal syscall.Signal) error {
	err := syscall.Kill(-pid, signal)
	if errors.Is(err, syscall.ESRCH) {
		return nil
	}
	return err
}

func exitCode(status syscall.WaitStatus, forwardedSignal syscall.Signal) int {
	if status.Exited() {
		code := status.ExitStatus()
		if forwardedSignal != 0 && code == 128+int(forwardedSignal) {
			return 0
		}
		return code
	}
	if status.Signaled() {
		childSignal := status.Signal()
		if forwardedSignal != 0 && childSignal == forwardedSignal {
			return 0
		}
		return 128 + int(childSignal)
	}
	return 125
}
