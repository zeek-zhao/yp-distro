// SPDX-License-Identifier: MIT

package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"syscall"
	"time"

	"example.com/yp/greeting"
)

const version = "0.1"

func run(args []string, stdout, stderr io.Writer) error {
	flags := flag.NewFlagSet("yp-demo-go", flag.ContinueOnError)
	flags.SetOutput(stderr)
	asJSON := flags.Bool("json", false, "print a JSON greeting")
	showVersion := flags.Bool("version", false, "print the version and exit")
	daemon := flags.Bool("daemon", false, "repeat the greeting every 10 seconds")
	if err := flags.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return nil
		}
		return err
	}
	if flags.NArg() != 0 {
		return fmt.Errorf("unexpected arguments: %v", flags.Args())
	}
	if *showVersion {
		_, err := fmt.Fprintln(stdout, "yp-demo-go "+version)
		return err
	}
	emit := func() error {
		if *asJSON {
			return json.NewEncoder(stdout).Encode(struct {
				Name    string `json:"name"`
				Version string `json:"version"`
				Message string `json:"message"`
			}{"yp-demo-go", version, greeting.Message})
		}
		_, err := fmt.Fprintln(stdout, greeting.Message)
		return err
	}
	if !*daemon {
		return emit()
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()
	for {
		if err := emit(); err != nil {
			return err
		}
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
		}
	}
}

func main() {
	if err := run(os.Args[1:], os.Stdout, os.Stderr); err != nil {
		fmt.Fprintln(os.Stderr, "yp-demo-go:", err)
		os.Exit(1)
	}
}
