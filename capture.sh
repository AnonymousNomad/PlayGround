#!/usr/bin/env bash
# Capture desktop + mobile screenshots of CAPTURE_URL into CAPTURE_DIR.
# Exit 75 = temporary navigation/browser infrastructure failure.
# Exit 1  = script or rendering defect. Leaves the app server running.
set -euo pipefail

time -p cd "$(dirname "$0")"
/usr/bin/time -p printf 'capture: url=%s dir=%s\n' "${CAPTURE_URL:-unset}" "${CAPTURE_DIR:-unset}"
/usr/bin/time -p test -n "${CAPTURE_URL:?Set CAPTURE_URL.}"
/usr/bin/time -p test -n "${CAPTURE_DIR:?Set CAPTURE_DIR.}"
/usr/bin/time -p mkdir -p "$CAPTURE_DIR"
/usr/bin/time -p node "${RUNTIME_DIR:?}/scripts/default-capture.mjs"
status=$?
/usr/bin/time -p ls -la "$CAPTURE_DIR"
/usr/bin/time -p test -f "$CAPTURE_DIR/final-desktop.png"
/usr/bin/time -p test -f "$CAPTURE_DIR/final-mobile.png"
exit "$status"
