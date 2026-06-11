#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SUMMARY_JSON="$ROOT_DIR/dist/stage7-summary.json"
CONFIGURATION="release"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --configuration)
            CONFIGURATION="$2"
            shift 2
            ;;
        --summary-json)
            SUMMARY_JSON="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 64
            ;;
    esac
done

mkdir -p "$(dirname "$SUMMARY_JSON")"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ "${MACWATCH_TEST_SKIP_BUILD:-0}" != "1" ]]; then
    scripts/package_app.sh --configuration "$CONFIGURATION" >/dev/null
fi

BUNDLE_PATH="$ROOT_DIR/dist/MacWatch.app"
BUNDLE_BINARY="$BUNDLE_PATH/Contents/MacOS/MacWatchApp"

write_result() {
    local name="$1"
    local status="$2"
    local payload_file="$3"
    local output_file="$4"

    python3 - "$name" "$status" "$payload_file" "$output_file" <<'PY'
import json
import pathlib
import sys

name, status, payload_path, output_path = sys.argv[1:]
payload = json.loads(pathlib.Path(payload_path).read_text())
pathlib.Path(output_path).write_text(json.dumps({
    "name": name,
    "status": status,
    "report": payload
}, sort_keys=True))
PY
}

run_acceptance_report() {
    local scenario="$1"
    local output_file="$2"

    if [[ "${MACWATCH_TEST_MOCK_ACCEPTANCE:-0}" == "1" ]]; then
        cat > "$output_file" <<EOF
{"durationMs":12.5,"failures":[],"metrics":{"mock":"true","scenario":"$scenario"},"passed":true,"scenario":"$scenario","startedAt":"2026-06-10T00:00:00.000Z"}
EOF
        return
    fi

    "$BUNDLE_BINARY" --acceptance-run "$scenario" > "$output_file"
}

run_resource_probe() {
    local output_file="$1"

    if [[ "${MACWATCH_TEST_MOCK_RESOURCE_SAMPLES+x}" == "x" ]]; then
        python3 - "$MACWATCH_TEST_MOCK_RESOURCE_SAMPLES" "$output_file" "$CONFIGURATION" <<'PY'
import json
import sys

raw_samples, output_path, configuration = sys.argv[1:]
samples = []
for line in raw_samples.splitlines():
    parts = line.split()
    if len(parts) < 2:
        continue
    try:
        rss_mb = float(parts[1]) / 1024.0
        footprint_mb = rss_mb
        if len(parts) >= 3:
            raw_memory = parts[2]
            multiplier = 1.0
            if raw_memory.endswith("K"):
                multiplier = 1.0 / 1024.0
                raw_memory = raw_memory[:-1]
            elif raw_memory.endswith("M"):
                raw_memory = raw_memory[:-1]
            elif raw_memory.endswith("G"):
                multiplier = 1024.0
                raw_memory = raw_memory[:-1]
            footprint_mb = float(raw_memory) * multiplier
        samples.append((float(parts[0]), rss_mb, footprint_mb))
    except ValueError:
        pass

if not samples:
    payload = {
        "status": "failed",
        "reason": "noResourceSamples",
        "configuration": configuration,
        "sampleCount": 0,
    }
else:
    avg_cpu = sum(v[0] for v in samples) / len(samples)
    peak_rss_memory = max(v[1] for v in samples)
    peak_memory = max(v[2] for v in samples)
    payload = {
        "status": "passed" if avg_cpu < 2.0 and peak_memory < 120.0 else "failed",
        "averageCpuPercent": round(avg_cpu, 2),
        "configuration": configuration,
        "memorySource": "physicalFootprint" if any(v[1] != v[2] for v in samples) else "rssFallback",
        "peakMemoryMB": round(peak_memory, 2),
        "peakRSSMemoryMB": round(peak_rss_memory, 2),
        "sampleCount": len(samples),
    }

with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, sort_keys=True)
PY
        return
    fi

    if [[ "${MACWATCH_TEST_MOCK_ACCEPTANCE:-0}" == "1" ]]; then
        cat > "$output_file" <<EOF
{"status":"passed","averageCpuPercent":0.4,"configuration":"$CONFIGURATION","peakMemoryMB":91.2,"sampleCount":5}
EOF
        return
    fi

    local warmup_seconds="${MACWATCH_RESOURCE_WARMUP_SECONDS:-8}"
    local sample_count="${MACWATCH_RESOURCE_SAMPLE_COUNT:-5}"
    local sample_interval="${MACWATCH_RESOURCE_SAMPLE_INTERVAL_SECONDS:-1}"
    local steady_duration
    steady_duration="$(python3 - "$warmup_seconds" "$sample_count" "$sample_interval" <<'PY'
import sys
warmup = float(sys.argv[1])
count = int(sys.argv[2])
interval = float(sys.argv[3])
print(warmup + count * interval + 1.0)
PY
)"

    local resource_report="$TMP_DIR/resource-steady-state.json"
    MACWATCH_RESOURCE_STEADY_STATE=1 \
    MACWATCH_RESOURCE_STEADY_STATE_DURATION_SECONDS="$steady_duration" \
    "$BUNDLE_BINARY" --acceptance-run resources-steady-state > "$resource_report" 2>/tmp/macwatch-stage7-runtime.err &
    local pid=$!
    sleep "$warmup_seconds"

    local samples
    samples="$(
        for _ in $(seq 1 "$sample_count"); do
            ps_values="$(ps -p "$pid" -o pcpu=,rss= 2>/dev/null || true)"
            if [[ -n "$ps_values" ]]; then
                printf '%s\n' "$ps_values"
            fi
            sleep "$sample_interval"
        done
    )"
    local resource_exit=0
    wait "$pid" 2>/dev/null || resource_exit=$?

    python3 - "$samples" "$output_file" "$CONFIGURATION" "$resource_report" "$resource_exit" <<'PY'
import json
import sys

raw_samples = sys.argv[1].splitlines()
configuration = sys.argv[3]
report_path = sys.argv[4]
resource_exit = int(sys.argv[5])
samples = []
for line in raw_samples:
    parts = line.split()
    if len(parts) != 2:
        continue
    try:
        samples.append((float(parts[0]), float(parts[1]) / 1024.0))
    except ValueError:
        pass

try:
    resource_report = json.load(open(report_path))
except Exception:
    resource_report = None

if not samples:
    payload = {
        "status": "failed",
        "reason": "noResourceSamples",
        "configuration": configuration,
        "sampleCount": 0,
    }
elif resource_report is None:
    payload = {
        "status": "failed",
        "reason": "missingResourceReport",
        "configuration": configuration,
        "sampleCount": len(samples),
    }
else:
    avg_cpu = sum(v[0] for v in samples) / len(samples)
    peak_rss_memory = max(v[1] for v in samples)
    metrics = resource_report.get("metrics", {})
    peak_memory = float(metrics.get("residentMemoryMB", "999"))
    failures = list(resource_report.get("failures", []))
    if resource_exit not in (0, 1):
        failures.append(f"resourceScenarioExited.{resource_exit}")
    payload = {
        "status": "passed" if avg_cpu < 2.0 and peak_memory < 120.0 and not failures else "failed",
        "averageCpuPercent": round(avg_cpu, 2),
        "configuration": configuration,
        "failures": failures,
        "memorySource": metrics.get("memorySource", "appResidentMemory"),
        "peakMemoryMB": round(peak_memory, 2),
        "peakRSSMemoryMB": round(peak_rss_memory, 2),
        "sampleCount": len(samples),
    }
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(payload, handle, sort_keys=True)
PY
}

run_network_probe() {
    local output_file="$1"

    if [[ "${MACWATCH_TEST_MOCK_ACCEPTANCE:-0}" == "1" ]]; then
        cat > "$output_file" <<'EOF'
{"status":"passed","socketCount":0}
EOF
        return
    fi

    "$BUNDLE_BINARY" >/tmp/macwatch-stage7-network.log 2>/tmp/macwatch-stage7-network.err &
    local pid=$!
    local max_socket_count=0
    local socket_snapshot=""
    local has_socket=0
    local deadline=$((SECONDS + 8))

    while [[ "$SECONDS" -lt "$deadline" ]]; do
        local sockets=""
        sockets="$(lsof -a -p "$pid" -n -P -i TCP -i UDP 2>/dev/null | sed -n '2,$p' || true)"
        if [[ -n "$sockets" ]]; then
            has_socket=1
            socket_snapshot="$socket_snapshot\n$sockets"
        fi

        local current_count=0
        current_count="$(awk 'NF{count += 1} END{print count+0}' <<<"$sockets")"
        if [[ "$current_count" -gt "$max_socket_count" ]]; then
            max_socket_count="$current_count"
        fi

        sleep 1
    done

    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" 2>/dev/null || true

    if [[ "$has_socket" -eq 1 ]]; then
        cat > "$output_file" <<EOF
{"status":"failed","socketCount":$max_socket_count,"evidence":"socketFoundDuringRun"}
EOF
    else
        cat > "$output_file" <<'EOF'
{"status":"passed","socketCount":0}
EOF
    fi
}

run_boundary_probe() {
    local output_file="$1"
    if scripts/verify_stats_boundary.sh > /tmp/macwatch-stage7-boundary.log 2>&1; then
        cat > "$output_file" <<'EOF'
{"status":"passed"}
EOF
    else
        cat > "$output_file" <<'EOF'
{"status":"failed","reason":"statsBoundaryVerificationFailed"}
EOF
    fi
}

probe_output="$TMP_DIR/probe-status.json"
run_acceptance_report "probe-status" "$probe_output"
write_result "probe-status" "$(python3 - "$probe_output" <<'PY'
import json, sys
print("passed" if json.load(open(sys.argv[1]))["passed"] else "failed")
PY
)" "$probe_output" "$TMP_DIR/result-probe-status.json"

dashboard_output="$TMP_DIR/dashboard-open.json"
run_acceptance_report "dashboard-open" "$dashboard_output"
write_result "dashboard-open" "$(python3 - "$dashboard_output" <<'PY'
import json, sys
print("passed" if json.load(open(sys.argv[1]))["passed"] else "failed")
PY
)" "$dashboard_output" "$TMP_DIR/result-dashboard-open.json"

popup_output="$TMP_DIR/popup-open.json"
run_acceptance_report "popup-open" "$popup_output"
write_result "popup-open" "$(python3 - "$popup_output" <<'PY'
import json, sys
print("passed" if json.load(open(sys.argv[1]))["passed"] else "failed")
PY
)" "$popup_output" "$TMP_DIR/result-popup-open.json"

first_run_output="$TMP_DIR/first-run-guide.json"
run_acceptance_report "first-run-guide" "$first_run_output"
write_result "first-run-guide" "$(python3 - "$first_run_output" <<'PY'
import json, sys
print("passed" if json.load(open(sys.argv[1]))["passed"] else "failed")
PY
)" "$first_run_output" "$TMP_DIR/result-first-run-guide.json"

launch_enabled_output="$TMP_DIR/launch-main-window-on-start-enabled.json"
run_acceptance_report "launch-main-window-on-start-enabled" "$launch_enabled_output"
write_result "launch-main-window-on-start-enabled" "$(python3 - "$launch_enabled_output" <<'PY'
import json, sys
print("passed" if json.load(open(sys.argv[1]))["passed"] else "failed")
PY
)" "$launch_enabled_output" "$TMP_DIR/result-launch-main-window-on-start-enabled.json"

launch_disabled_output="$TMP_DIR/launch-main-window-on-start-disabled.json"
run_acceptance_report "launch-main-window-on-start-disabled" "$launch_disabled_output"
write_result "launch-main-window-on-start-disabled" "$(python3 - "$launch_disabled_output" <<'PY'
import json, sys
print("passed" if json.load(open(sys.argv[1]))["passed"] else "failed")
PY
)" "$launch_disabled_output" "$TMP_DIR/result-launch-main-window-on-start-disabled.json"

trend_output="$TMP_DIR/trend-query.json"
run_acceptance_report "trend-query" "$trend_output"
write_result "trend-query" "$(python3 - "$trend_output" <<'PY'
import json, sys
print("passed" if json.load(open(sys.argv[1]))["passed"] else "failed")
PY
)" "$trend_output" "$TMP_DIR/result-trend-query.json"

sleep_output="$TMP_DIR/sleep-wake-simulated.json"
run_acceptance_report "sleep-wake-simulated" "$sleep_output"
write_result "sleep-wake-simulated" "$(python3 - "$sleep_output" <<'PY'
import json, sys
print("passed" if json.load(open(sys.argv[1]))["passed"] else "failed")
PY
)" "$sleep_output" "$TMP_DIR/result-sleep-wake.json"

resource_output="$TMP_DIR/resources.json"
run_resource_probe "$resource_output"
write_result "resources" "$(python3 - "$resource_output" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["status"])
PY
)" "$resource_output" "$TMP_DIR/result-resources.json"

network_output="$TMP_DIR/network.json"
run_network_probe "$network_output"
write_result "network" "$(python3 - "$network_output" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["status"])
PY
)" "$network_output" "$TMP_DIR/result-network.json"

boundary_output="$TMP_DIR/boundary.json"
run_boundary_probe "$boundary_output"
write_result "stats-boundary" "$(python3 - "$boundary_output" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["status"])
PY
)" "$boundary_output" "$TMP_DIR/result-boundary.json"

distribution_output="$TMP_DIR/distribution.json"
scripts/preflight_distribution.sh "$BUNDLE_PATH" > "$distribution_output"
write_result "distribution-preflight" "$(python3 - "$distribution_output" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["status"])
PY
)" "$distribution_output" "$TMP_DIR/result-distribution.json"

python3 - "$TMP_DIR" "$SUMMARY_JSON" <<'PY'
import json
import pathlib
import sys

tmp_dir = pathlib.Path(sys.argv[1])
summary_path = pathlib.Path(sys.argv[2])
results = []
for path in sorted(tmp_dir.glob("result-*.json")):
    results.append(json.loads(path.read_text()))

summary = {"passed": 0, "failed": 0, "blocked": 0}
for result in results:
    status = result["status"]
    if status not in summary:
        summary[status] = 0
    summary[status] += 1

payload = {"results": results, "summary": summary}
summary_path.write_text(json.dumps(payload, sort_keys=True))
print(json.dumps(payload, sort_keys=True))
PY
