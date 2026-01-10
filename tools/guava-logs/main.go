package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

type LokiResponse struct {
	Status string `json:"status"`
	Data   struct {
		ResultType string `json:"resultType"`
		Result     []struct {
			Stream map[string]string `json:"stream"`
			Values [][]string        `json:"values"`
		} `json:"result"`
	} `json:"data"`
}

type LogEntry struct {
	Timestamp time.Time
	App       string
	Line      string
}

func main() {
	var (
		component  = flag.String("component", "all", "Component to fetch logs for: server, solver, or all")
		since      = flag.String("since", "1h", "Fetch logs from this duration ago (e.g., 1h, 30m, 2h30m)")
		from       = flag.String("from", "", "Start time (RFC3339 format, e.g., 2024-01-09T10:00:00Z)")
		to         = flag.String("to", "", "End time (RFC3339 format, defaults to now)")
		limit      = flag.Int("limit", 1000, "Maximum number of log lines to fetch")
		lokiAddr   = flag.String("loki", "", "Loki address (default: auto port-forward to cluster)")
		noColor    = flag.Bool("no-color", false, "Disable colored output")
		showLabels = flag.Bool("labels", false, "Show log labels (app, pod)")
	)
	flag.Parse()

	// Determine time range
	var startTime, endTime time.Time
	endTime = time.Now()

	if *from != "" {
		var err error
		startTime, err = time.Parse(time.RFC3339, *from)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error parsing --from: %v\n", err)
			os.Exit(1)
		}
		if *to != "" {
			endTime, err = time.Parse(time.RFC3339, *to)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error parsing --to: %v\n", err)
				os.Exit(1)
			}
		}
	} else {
		duration, err := time.ParseDuration(*since)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error parsing --since: %v\n", err)
			os.Exit(1)
		}
		startTime = endTime.Add(-duration)
	}

	// Build LogQL query based on component
	var query string
	switch *component {
	case "server":
		query = `{namespace="guava", app="guava-server"}`
	case "solver":
		query = `{namespace="guava", app="guava-solver"}`
	case "all":
		query = `{namespace="guava"}`
	default:
		fmt.Fprintf(os.Stderr, "Unknown component: %s (use: server, solver, or all)\n", *component)
		os.Exit(1)
	}

	// Set up Loki connection
	lokiURL := *lokiAddr
	var portForwardCmd *exec.Cmd

	if lokiURL == "" {
		// Check if kubectl is available
		if _, err := exec.LookPath("kubectl"); err != nil {
			fmt.Fprintln(os.Stderr, "Error: kubectl not found in PATH")
			fmt.Fprintln(os.Stderr, "Install kubectl or specify --loki URL directly")
			os.Exit(1)
		}

		// Start port-forward
		fmt.Fprintln(os.Stderr, "Starting port-forward to Loki...")
		portForwardCmd = exec.Command("kubectl", "port-forward", "-n", "observability", "svc/loki", "3100:3100")
		portForwardCmd.Stderr = nil // Suppress kubectl stderr

		if err := portForwardCmd.Start(); err != nil {
			fmt.Fprintf(os.Stderr, "Error: failed to start kubectl port-forward: %v\n", err)
			os.Exit(1)
		}
		defer func() {
			if portForwardCmd.Process != nil {
				portForwardCmd.Process.Kill()
			}
		}()

		// Wait for port-forward to be ready
		lokiURL = "http://localhost:3100"
		ready := false
		for i := 0; i < 50; i++ {
			// Check if port-forward process died
			if portForwardCmd.ProcessState != nil && portForwardCmd.ProcessState.Exited() {
				fmt.Fprintln(os.Stderr, "Error: kubectl port-forward exited unexpectedly")
				fmt.Fprintln(os.Stderr, "Check that you have access to the cluster: kubectl get pods -n observability")
				os.Exit(1)
			}

			resp, err := http.Get(lokiURL + "/ready")
			if err == nil {
				resp.Body.Close()
				if resp.StatusCode == 200 {
					ready = true
					break
				}
			}
			time.Sleep(100 * time.Millisecond)
		}

		if !ready {
			fmt.Fprintln(os.Stderr, "Error: timed out waiting for Loki port-forward to be ready")
			fmt.Fprintln(os.Stderr, "Check cluster connectivity: kubectl get svc -n observability loki")
			os.Exit(1)
		}
	}

	// Query Loki
	entries, err := queryLoki(lokiURL, query, startTime, endTime, *limit)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error querying Loki: %v\n", err)
		os.Exit(1)
	}

	if len(entries) == 0 {
		fmt.Fprintln(os.Stderr, "No logs found for the specified time range")
		os.Exit(0)
	}

	// Print logs
	for _, entry := range entries {
		printEntry(entry, *showLabels, !*noColor)
	}

	fmt.Fprintf(os.Stderr, "\n--- Fetched %d log entries ---\n", len(entries))
}

func queryLoki(baseURL, query string, start, end time.Time, limit int) ([]LogEntry, error) {
	params := url.Values{}
	params.Set("query", query)
	params.Set("start", strconv.FormatInt(start.UnixNano(), 10))
	params.Set("end", strconv.FormatInt(end.UnixNano(), 10))
	params.Set("limit", strconv.Itoa(limit))
	params.Set("direction", "forward")

	reqURL := fmt.Sprintf("%s/loki/api/v1/query_range?%s", baseURL, params.Encode())

	resp, err := http.Get(reqURL)
	if err != nil {
		if strings.Contains(err.Error(), "connection refused") {
			return nil, fmt.Errorf("cannot connect to Loki at %s (connection refused)", baseURL)
		}
		if strings.Contains(err.Error(), "no such host") {
			return nil, fmt.Errorf("cannot resolve Loki host: %s", baseURL)
		}
		return nil, fmt.Errorf("request to Loki failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("loki returned %d: %s", resp.StatusCode, string(body))
	}

	var lokiResp LokiResponse
	if err := json.NewDecoder(resp.Body).Decode(&lokiResp); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	if lokiResp.Status != "success" {
		return nil, fmt.Errorf("loki query failed with status: %s", lokiResp.Status)
	}

	var entries []LogEntry
	for _, stream := range lokiResp.Data.Result {
		app := stream.Stream["app"]
		if app == "" {
			app = stream.Stream["container"]
		}

		for _, value := range stream.Values {
			if len(value) < 2 {
				continue
			}

			tsNano, err := strconv.ParseInt(value[0], 10, 64)
			if err != nil {
				continue
			}

			entries = append(entries, LogEntry{
				Timestamp: time.Unix(0, tsNano),
				App:       app,
				Line:      strings.TrimSpace(value[1]),
			})
		}
	}

	// Sort by timestamp (Loki returns in order per stream, but we may have multiple streams)
	for i := 0; i < len(entries)-1; i++ {
		for j := i + 1; j < len(entries); j++ {
			if entries[i].Timestamp.After(entries[j].Timestamp) {
				entries[i], entries[j] = entries[j], entries[i]
			}
		}
	}

	return entries, nil
}

func printEntry(entry LogEntry, showLabels, useColor bool) {
	ts := entry.Timestamp.Local().Format("15:04:05.000")

	var appLabel string
	if showLabels {
		if useColor {
			appLabel = fmt.Sprintf(" \033[36m[%s]\033[0m", entry.App)
		} else {
			appLabel = fmt.Sprintf(" [%s]", entry.App)
		}
	}

	line := entry.Line

	// Colorize log levels if color is enabled
	if useColor {
		line = colorizeLogLevel(line)
	}

	if useColor {
		fmt.Printf("\033[90m%s\033[0m%s %s\n", ts, appLabel, line)
	} else {
		fmt.Printf("%s%s %s\n", ts, appLabel, line)
	}
}

func colorizeLogLevel(line string) string {
	// Handle structured logs like: level=INFO or level=ERROR
	replacements := []struct {
		old, new string
	}{
		{"level=ERROR", "\033[31mlevel=ERROR\033[0m"},
		{"level=WARN", "\033[33mlevel=WARN\033[0m"},
		{"level=WARNING", "\033[33mlevel=WARNING\033[0m"},
		{"level=INFO", "\033[32mlevel=INFO\033[0m"},
		{"level=DEBUG", "\033[34mlevel=DEBUG\033[0m"},
	}

	for _, r := range replacements {
		if strings.Contains(line, r.old) {
			return strings.Replace(line, r.old, r.new, 1)
		}
	}

	return line
}
