#!/bin/bash
# Claude Code Statusline Installer
#
# Works in two modes:
#   1. Clone mode  — run from a cloned repo: uses the local statusline-command.sh
#   2. Curl mode   — piped from `curl ... | bash`: downloads from the latest GitHub release
#
# Layout selection:
#   - Interactive: prompts via /dev/tty (works under `curl ... | bash`)
#   - Non-interactive: set STATUSLINE_LINES=1|2|3 to skip the prompt; defaults to 3
#
# Install location: $CLAUDE_CONFIG_DIR if set, otherwise ~/.claude

set -eu

REPO="whitekr/claude-code-statusline"
RELEASE_BASE="https://github.com/${REPO}/releases/latest/download"

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CONFIG_DIR="${CONFIG_DIR%/}"
TARGET="$CONFIG_DIR/statusline-command.sh"
SETTINGS="$CONFIG_DIR/settings.json"

# Print a rendered preview for layout 1, 2, or 3.
print_preview() {
    case "$1" in
        1)
            printf "      Claude Opus 4.7 │ my-project │ main ✎3 ↑2 │ CTX \033[32m━━───\033[0m \033[2;90m0\033[0m45%% │ 5H \033[33m━━━──\033[0m \033[2;90m0\033[0m62%% ↻\033[2;90m0\033[0m3h\033[2;90m1\033[0m5m │ 7D \033[32m━────\033[0m \033[2;90m0\033[0m28%% ↻\033[2;90m0\033[0m4d\033[2;90m1\033[0m8h\n"
            ;;
        2)
            printf "      Claude Opus 4.7 │ my-project │ main ✎3 ↑2\n"
            printf "      CTX \033[32m━━━━━━─────────\033[0m \033[2;90m0\033[0m45%% │ 5H \033[33m━━━━────\033[0m \033[2;90m0\033[0m62%% ↻\033[2;90m0\033[0m3h\033[2;90m1\033[0m5m │ 7D \033[32m━━──────\033[0m \033[2;90m0\033[0m28%% ↻\033[2;90m0\033[0m4d\033[2;90m1\033[0m8h\n"
            ;;
        3)
            printf "      Claude Opus 4.7 │ my-project │ main ✎3 ↑2\n"
            printf "      CTX \033[32m━━━━━━━━━━━━━─────────────────\033[0m \033[2;90m0\033[0m45%%\n"
            printf "      5H \033[33m━━━━━━────\033[0m \033[2;90m0\033[0m62%% ↻\033[2;90m0\033[0m3h\033[2;90m1\033[0m5m │ 7D \033[32m━━────────\033[0m \033[2;90m0\033[0m28%% ↻\033[2;90m0\033[0m4d\033[2;90m1\033[0m8h\n"
            ;;
    esac
}

# Detect existing layout from current settings (returns "" if none).
detect_existing_layout() {
    [ -f "$SETTINGS" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    local cmd; cmd=$(jq -r '.statusLine.command // ""' "$SETTINGS" 2>/dev/null || echo "")
    case "$cmd" in
        *"statusline-command.sh 1"*) echo 1 ;;
        *"statusline-command.sh 2"*) echo 2 ;;
        *"statusline-command.sh 3"*) echo 3 ;;
    esac
}

choose_layout() {
    # Honor env var override (non-interactive use, e.g. CI).
    if [ -n "${STATUSLINE_LINES:-}" ]; then
        case "$STATUSLINE_LINES" in
            1|2|3) echo "$STATUSLINE_LINES"; return ;;
            *) echo "Warning: ignoring invalid STATUSLINE_LINES=$STATUSLINE_LINES" >&2 ;;
        esac
    fi

    local existing; existing=$(detect_existing_layout)
    local default_layout="${existing:-3}"

    # Open /dev/tty on fd 3 (read+write). `[ -r /dev/tty ]` isn't sufficient — some sandboxes
    # have the device entry but can't actually open it.
    if ! { exec 3<>/dev/tty; } 2>/dev/null; then
        echo "  Non-interactive shell: defaulting to ${default_layout}-line layout" >&2
        echo "$default_layout"
        return
    fi

    {
        echo ""
        echo "Choose statusline layout:"
        echo ""
        echo "  1) Single line — model · dir · git · percentages"
        print_preview 1
        echo ""
        echo "  2) Two lines — header, then combined gauges"
        print_preview 2
        echo ""
        echo "  3) Three lines — CTX bar gets its own line, full-width gauges"
        print_preview 3
        echo ""
        printf "Enter choice [1/2/3] (default: %s): " "$default_layout"
    } >&3

    local choice=""
    read -r choice <&3 || choice=""
    exec 3<&-
    case "$choice" in
        1|2|3) echo "$choice" ;;
        *)     echo "$default_layout" ;;
    esac
}

# Wrapped in a function so `curl | bash` won't execute a partially-downloaded script.
main() {
    echo "Installing Claude Code statusline..."
    echo "  Config dir: $CONFIG_DIR"

    # Fail fast on missing jq — the statusline itself is unusable without it,
    # and a silent install + broken-looking statusline is worse than a clear error here.
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq is required (the statusline parses Claude Code's stdin JSON with jq)" >&2
        echo "  Install:" >&2
        echo "    macOS:         brew install jq" >&2
        echo "    Debian/Ubuntu: apt install jq" >&2
        echo "    Windows:       winget install jqlang.jq    (or scoop/choco)" >&2
        echo "    Other:         https://jqlang.github.io/jq/download/" >&2
        exit 1
    fi

    mkdir -p "$CONFIG_DIR"

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

    local layout; layout=$(choose_layout)
    echo "  Selected: ${layout}-line layout"

    # Use ~/.claude shorthand only when installing to the default location;
    # for a custom CLAUDE_CONFIG_DIR, store the absolute path so the shell
    # doesn't expand ~ to the wrong place.
    local cmd_value
    if [ "$CONFIG_DIR" = "$HOME/.claude" ]; then
        cmd_value="~/.claude/statusline-command.sh $layout"
    else
        cmd_value="$TARGET $layout"
    fi

    # Set .statusLine.command in settings.json (creates the full statusLine block on first install).
    if [ -f "$SETTINGS" ]; then
        local tmp; tmp=$(mktemp)
        if jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
            jq --arg cmd "$cmd_value" '.statusLine.command = $cmd' "$SETTINGS" > "$tmp"
            mv "$tmp" "$SETTINGS"
            echo "  Updated statusLine.command in $SETTINGS"
        else
            jq --arg cmd "$cmd_value" '. + {"statusLine": {"type": "command", "command": $cmd, "padding": 2}}' "$SETTINGS" > "$tmp"
            mv "$tmp" "$SETTINGS"
            echo "  Added statusLine config to $SETTINGS"
        fi
    else
        cat > "$SETTINGS" <<EOF
{
  "statusLine": {
    "type": "command",
    "command": "$cmd_value",
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
    echo "To change layout later: re-run the installer, or edit"
    echo "  $SETTINGS   →   .statusLine.command"
    echo "and pass 1, 2, or 3 as the script argument."
}

main "$@"
