#!/bin/bash
# Claude Code Statusline Installer
#
# Works in two modes:
#   1. Clone mode  — run from a cloned repo: uses the local statusline-command.sh
#   2. Curl mode   — piped from `curl ... | bash`: downloads from the latest GitHub release

set -eu

REPO="whitekr/claude-code-statusline"
RELEASE_BASE="https://github.com/${REPO}/releases/latest/download"
TARGET="$HOME/.claude/statusline-command.sh"
SETTINGS="$HOME/.claude/settings.local.json"

# Wrapped in a function so `curl | bash` won't execute a partially-downloaded script.
main() {
    echo "Installing Claude Code statusline..."

    mkdir -p "$HOME/.claude"

    # Detect clone mode by checking if statusline-command.sh sits next to this script.
    local script_dir=""
    if [ -n "${BASH_SOURCE[0]:-}" ]; then
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
    fi

    if [ -n "$script_dir" ] && [ -f "$script_dir/statusline-command.sh" ]; then
        cp "$script_dir/statusline-command.sh" "$TARGET"
        echo "  Copied local statusline-command.sh -> $TARGET"
    else
        if ! command -v curl >/dev/null 2>&1; then
            echo "Error: curl is required to download statusline-command.sh" >&2
            exit 1
        fi
        echo "  Downloading statusline-command.sh from latest release..."
        if ! curl -fsSL "$RELEASE_BASE/statusline-command.sh" -o "$TARGET"; then
            echo "Error: failed to download $RELEASE_BASE/statusline-command.sh" >&2
            exit 1
        fi
        echo "  Downloaded -> $TARGET"
    fi
    chmod +x "$TARGET"

    # Configure settings.local.json
    if [ -f "$SETTINGS" ]; then
        if ! command -v jq >/dev/null 2>&1; then
            echo "Error: jq is required to merge into existing $SETTINGS" >&2
            exit 1
        fi
        if jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
            echo "  statusLine already configured in $SETTINGS"
        else
            tmp=$(mktemp)
            jq '. + {"statusLine": {"type": "command", "command": "~/.claude/statusline-command.sh", "padding": 2}}' "$SETTINGS" > "$tmp"
            mv "$tmp" "$SETTINGS"
            echo "  Added statusLine config to $SETTINGS"
        fi
    else
        cat > "$SETTINGS" <<'EOF'
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-command.sh",
    "padding": 2
  }
}
EOF
        echo "  Created $SETTINGS with statusLine config"
    fi

    echo ""
    echo "Done! Restart Claude Code to see the statusline."
    echo ""
    echo "Requirements: jq, curl, git (optional)"
    echo "Rate limits require being logged into Claude Code (OAuth credentials)."
}

main "$@"
