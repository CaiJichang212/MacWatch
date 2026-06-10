#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SUMMARY_JSON="$ROOT_DIR/dist/stage7-summary.json"

while [[ $# -gt 0 ]]; do
    case "$1" in
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
    scripts/package_app.sh >/dev/null
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

    if [[ "${MACWATCH_TEST_MOCK_ACCEPTANCE:-0}" == "1" ]]; then
        cat > "$output_file" <<'EOF'
{"status":"passed","averageCpuPercent":0.4,"peakMemoryMB":91.2}
EOF
        return
    fi

    "$BUNDLE_BINARY" >/tmp/macwatch-stage7-runtime.log 2>/tmp/macwatch-stage7-runtime.err &
    local pid=$!
    sleep 3

    local samples
    samples="$(for _ in 1 2 3 4 5; do ps -p "$pid" -o pcpu=,rss=; sleep 1; done)"
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" 2>/dev/null || true

    python3 - "$samples" "$output_file" <<'PY'
import json
import sys

raw_samples = sys.argv[1].splitlines()
samples = []
for line in raw_samples:
    parts = line.split()
    if len(parts) != 2:
        continue
    samples.append((float(parts[0]), float(parts[1]) / 1024.0))

avg_cpu = sum(v[0] for v in samples) / len(samples) if samples else 999.0
peak_memory = max((v[1] for v in samples), default=999.0)
status = "passed" if avg_cpu < 2.0 and peak_memory < 120.0 else "failed"
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump({
        "status": status,
        "averageCpuPercent": round(avg_cpu, 2),
        "peakMemoryMB": round(peak_memory, 2),
    }, handle, sort_keys=True)
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
    sleep 3

    local sockets
    sockets="$(lsof -p "$pid" | grep -E ' (TCP|UDP) ' || true)"
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" 2>/dev/null || true

    if [[ -n "$sockets" ]]; then
        cat > "$output_file" <<EOF
{"status":"failed","socketCount":1,"evidence":"externalSocketDetected"}
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
