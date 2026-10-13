#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
configuration="${1:-debug}"
case "$configuration" in
  debug|release) ;;
  *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [debug|release]" >&2
  exit 2
fi

test_logs=$(mktemp -d "${TMPDIR:-/tmp}/PinboardShot-tests.XXXXXX")
trap 'rm -rf "$test_logs"' EXIT

run_phase() {
  local label="$1" expected_summaries="$2" log_file="$3"
  shift 3
  if PINBOARDSHOT_BENCHMARK=0 "$@" > "$log_file" 2>&1; then
    python3 - "$label" "$expected_summaries" "$log_file" <<'PY'
import re
import sys

label, expected, path = sys.argv[1:]
with open(path, encoding="utf-8", errors="replace") as stream:
    output = stream.read()
summaries = re.findall(r"^.*Test run with (\d+) tests? .*passed after.*$", output, re.MULTILINE)
failures = re.search(r"recorded an issue|failed after|^error:", output, re.MULTILINE)
# This toolchain can exit successfully when its AppKit main run loop stops early.
# A missing completion summary is a failed verification, regardless of exit status.
if failures or len(summaries) != int(expected):
    print(output[-6000:], file=sys.stderr)
    raise SystemExit(f"{label}: tests failed or did not report completion")
print(f"{label}: {sum(map(int, summaries))} tests completed successfully")
PY
  else
    local status=$?
    tail -n 60 "$log_file" >&2
    return "$status"
  fi
}

# AppKit fixtures share application/window state, so run them serially. Isolate
# WebKit initialization, which otherwise stops this Swift Testing host's main loop.
run_phase "App and bridge" 2 "$test_logs/app.log" \
  swift test -c "$configuration" --no-parallel --skip renderedReleaseText
run_phase "WebKit integration" 1 "$test_logs/webkit.log" \
  swift test -c "$configuration" --skip-build --no-parallel --filter renderedReleaseText
