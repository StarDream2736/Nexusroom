// nexusroom-wg-helper: WireGuard helper process for NexusRoom Desktop client.
//
// Subcommands:
//
//	genkey              — Generate a WireGuard key pair (JSON to stdout)
//	up                  — Start a WireGuard tunnel
//
// The "up" subcommand keeps the process alive.  IPC can use either:
//   - stdin/stdout (default) — when launched directly
//   - TCP 127.0.0.1          — when launched elevated via --port <N>
//
// The Flutter parent launches this binary elevated (UAC) via PowerShell
// Start-Process -Verb RunAs, passing --port so both sides communicate
// over a localhost TCP socket (stdin/stdout cannot cross elevation boundaries).
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/signal"
	"strconv"
	"syscall"

	"nexusroom-wg-helper/keygen"
	"nexusroom-wg-helper/tunnel"
)

// jsonMsg is the envelope for IPC communication.
type jsonMsg struct {
	Action string          `json:"action"`
	Data   json.RawMessage `json:"data,omitempty"`
	Error  string          `json:"error,omitempty"`
}

func main() {
	log.SetFlags(log.LstdFlags | log.Lshortfile)

	// Find the subcommand — skip flags and path-like args.
	subcommand := ""
	for _, arg := range os.Args[1:] {
		switch arg {
		case "genkey", "up":
			subcommand = arg
		}
	}

	if subcommand == "" {
		usage()
		os.Exit(1)
	}

	switch subcommand {
	case "genkey":
		cmdGenKey()
	case "up":
		cmdUp()
	default:
		usage()
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "Usage: nexusroom-wg.exe <genkey|up> [--port N]")
	fmt.Fprintln(os.Stderr, "  genkey        Generate a WireGuard key pair (JSON to stdout)")
	fmt.Fprintln(os.Stderr, "  up            Start tunnel (reads config JSON)")
	fmt.Fprintln(os.Stderr, "    --port N    Use TCP 127.0.0.1:N for IPC instead of stdin/stdout")
}

// cmdGenKey generates a key pair and prints JSON to stdout, then exits.
func cmdGenKey() {
	kp, err := keygen.Generate()
	if err != nil {
		writeErrorTo(os.Stdout, fmt.Sprintf("key generation failed: %v", err))
		os.Exit(1)
	}
	writeJSONTo(os.Stdout, "genkey", kp)
}

// parsePort scans os.Args for "--port N" and returns N, or 0 if absent.
func parsePort() int {
	for i, arg := range os.Args {
		if arg == "--port" && i+1 < len(os.Args) {
			if p, err := strconv.Atoi(os.Args[i+1]); err == nil && p > 0 {
				return p
			}
		}
	}
	return 0
}

// cmdUp reads a tunnel config, brings the tunnel up, then waits for
// a "down" command or signal to tear it down.
func cmdUp() {
	port := parsePort()

	var reader *bufio.Scanner
	var writer io.Writer
	var tcpConn net.Conn

	if port > 0 {
		// TCP mode: connect back to the parent's local TCP server.
		var err error
		tcpConn, err = net.Dial("tcp", fmt.Sprintf("127.0.0.1:%d", port))
		if err != nil {
			log.Fatalf("Failed to connect to parent on port %d: %v", port, err)
		}
		defer tcpConn.Close()
		reader = bufio.NewScanner(tcpConn)
		writer = tcpConn
		log.Printf("Connected to parent via TCP port %d", port)
	} else {
		// Stdin/stdout mode (direct invocation, no elevation boundary).
		reader = bufio.NewScanner(os.Stdin)
		writer = os.Stdout
	}

	// First message must be the tunnel config.
	if !reader.Scan() {
		writeErrorTo(writer, "expected tunnel config on input")
		os.Exit(1)
	}

	var cfg tunnel.Config
	if err := json.Unmarshal(reader.Bytes(), &cfg); err != nil {
		writeErrorTo(writer, fmt.Sprintf("invalid config JSON: %v", err))
		os.Exit(1)
	}

	log.Printf("Starting tunnel %q ...", cfg.InterfaceName)
	tun, err := tunnel.Up(&cfg)
	if err != nil {
		writeErrorTo(writer, fmt.Sprintf("tunnel up failed: %v", err))
		os.Exit(1)
	}

	writeJSONTo(writer, "up", map[string]string{
		"status":    "ok",
		"interface": tun.Name(),
	})

	// Handle graceful shutdown.
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	doneCh := make(chan struct{})
	go func() {
		for reader.Scan() {
			var msg jsonMsg
			if err := json.Unmarshal(reader.Bytes(), &msg); err != nil {
				continue
			}
			if msg.Action == "down" {
				close(doneCh)
				return
			}
		}
		// Input closed.
		close(doneCh)
	}()

	select {
	case <-sigCh:
		log.Println("Received signal, shutting down tunnel")
	case <-doneCh:
		log.Println("Received down command, shutting down tunnel")
	}

	tun.Down()
	writeJSONTo(writer, "down", map[string]string{"status": "ok"})
}

// ── IPC helpers ────────────────────────────────────────────────────────────

func writeJSONTo(w io.Writer, action string, data interface{}) {
	raw, _ := json.Marshal(data)
	msg := jsonMsg{Action: action, Data: raw}
	out, _ := json.Marshal(msg)
	fmt.Fprintln(w, string(out))
}

func writeErrorTo(w io.Writer, errMsg string) {
	msg := jsonMsg{Action: "error", Error: errMsg}
	out, _ := json.Marshal(msg)
	fmt.Fprintln(w, string(out))
}
