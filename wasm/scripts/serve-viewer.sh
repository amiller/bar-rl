#!/bin/bash
# Serve the viewer + traces on a local port (with /api endpoints for browse+capture).
# Opens the scrubber at http://localhost:8765/viewer/
set -eu
exec python3 "$(dirname "$0")/serve.py" "${1:-8765}"
