#!/bin/bash

# Package Cursor session databases for the current repo into gzipped copies.
#
# Cursor stores conversation history in SQLite databases (state.vscdb):
#   - Per-workspace: <CURSOR_BASE>/workspaceStorage/<hash>/state.vscdb
#     (workspace.json in each dir maps to the project folder)
#   - Global (composer/agent mode): <CURSOR_BASE>/globalStorage/state.vscdb

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${1:-$REPO_ROOT/dist}"

# Detect platform
case "$(uname -s)" in
    Darwin)
        CURSOR_BASE="${CURSOR_BASE:-$HOME/Library/Application Support/Cursor/User}"
        ;;
    Linux)
        CURSOR_BASE="${CURSOR_BASE:-$HOME/.config/Cursor/User}"
        ;;
    *)
        echo "Unsupported platform: $(uname -s)"
        exit 1
        ;;
esac

if [ ! -d "$CURSOR_BASE" ]; then
    echo "Cursor data directory not found at $CURSOR_BASE"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

packaged=0

# Find workspace state.vscdb matching this repo
WORKSPACE_DIR="$CURSOR_BASE/workspaceStorage"
if [ -d "$WORKSPACE_DIR" ]; then
    for ws in "$WORKSPACE_DIR"/*/workspace.json; do
        [ -f "$ws" ] || continue
        ws_dir="$(dirname "$ws")"
        # workspace.json contains {"folder": "file:///path/to/project"}
        # Extract the folder URI and strip the file:// prefix
        folder="$(grep -o '"folder":"[^"]*"' "$ws" 2>/dev/null | head -1 | sed 's/"folder":"//; s/"$//; s|^file://||')" || true
        if [ "$folder" = "$REPO_ROOT" ] && [ -f "$ws_dir/state.vscdb" ]; then
            echo "Found matching workspace: $ws_dir"
            gzip -c "$ws_dir/state.vscdb" > "$OUTPUT_DIR/cursor-workspace-sessions-$TIMESTAMP.vscdb.gz"
            echo "Created: $OUTPUT_DIR/cursor-workspace-sessions-$TIMESTAMP.vscdb.gz"
            packaged=1
            break
        fi
    done
fi

# Also check globalStorage state.vscdb (composer/agent data in newer Cursor).
# Only package if it contains sessions referencing this repo.
GLOBAL_DB="$CURSOR_BASE/globalStorage/state.vscdb"
if [ -f "$GLOBAL_DB" ] && command -v sqlite3 &>/dev/null; then
    match_count="$(sqlite3 "$GLOBAL_DB" "SELECT COUNT(*) FROM cursorDiskKV WHERE cast(value as text) LIKE '%${REPO_ROOT}%';" 2>/dev/null || echo 0)"
    if [ "$match_count" -gt 0 ]; then
        echo "Packaging global Cursor state ($match_count rows match repo)..."
        gzip -c "$GLOBAL_DB" > "$OUTPUT_DIR/cursor-global-sessions-$TIMESTAMP.vscdb.gz"
        echo "Created: $OUTPUT_DIR/cursor-global-sessions-$TIMESTAMP.vscdb.gz"
        packaged=1
    else
        echo "Skipping global Cursor state (no sessions found for this repo)"
    fi
fi

if [ "$packaged" -eq 0 ]; then
    echo "No Cursor AI sessions found for repo $REPO_ROOT (skipping)"
    exit 0
fi

echo "Done packaging Cursor sessions."
