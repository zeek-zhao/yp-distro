// SPDX-License-Identifier: MIT

package main

import (
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
	// 刻意不用 signal.NotifyContext：那是 Go 1.16 才有的 API，
	// dunfell(3.1) 的 Go 1.14 会报 undefined。信号通道写法 1.14 起都成立。
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(stop)
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()
	for {
		if err := emit(); err != nil {
			return err
		}
		select {
		case <-stop:
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
