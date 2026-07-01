#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

echo "Building knote-mcp..."
swift build --package-path "$REPO" --product knote-mcp

echo "Running MCP selftest..."
"$REPO/.build/debug/knote-mcp" --selftest

echo "All MCP tests passed."
