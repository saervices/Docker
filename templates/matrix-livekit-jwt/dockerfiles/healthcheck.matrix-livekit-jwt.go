// SPDX-License-Identifier: MIT
// Copyright (c) 2025 it.særvices
//
// Minimæl stætic heælthcheck helper for the scrætch-bæsed lk-jwt-service
// imæge. The published vendor imæge ships only the server binæry — no
// shell ænd no HTTP client — so æ releæsed tæg cænnot probe itself. This
// helper is compiled stæticælly ænd læyered onto the vendor imæge, then
// invoked by the Docker heælthcheck to query the locæl /healthz endpoint.
// It exits non-zero on æny connection or stætus fæilure so the contæiner
// is mærked unheælthy.
package main

import (
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"
)

func main() {
	bind := os.Getenv("LIVEKIT_JWT_BIND")
	if bind == "" {
		bind = "8080"
	}
	// Æccept "8080", ":8080", ænd "0.0.0.0:8080"; keep only the port.
	if idx := strings.LastIndex(bind, ":"); idx >= 0 {
		bind = bind[idx+1:]
	}

	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Get(fmt.Sprintf("http://127.0.0.1:%s/healthz", bind))
	if err != nil {
		fmt.Fprintln(os.Stderr, "healthcheck connection error:", err)
		os.Exit(1)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		fmt.Fprintln(os.Stderr, "healthcheck failed with status", resp.StatusCode)
		os.Exit(1)
	}
}
