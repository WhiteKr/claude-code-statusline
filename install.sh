#!/bin/bash
# Claude Code Statusline Installer

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="$HOME/.claude/statusline-command.sh"
SETTINGS="$HOME/.claude/settings.local.json"

echo "Installing Claude Code statusline..."

# Copy script
cp "$SCRIPT_DIR/statusline-command.sh" "$TARGET"
chmod +x "$TARGET"
echo "  Copied statusline-command.sh -> $TARGET"

# Configure settings.local.json
if [ -f "$SETTINGS" ]; then
    # Check if statusLine already configured
    if jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
        echo "  statusLine already configured in $SETTINGS"
    else
        # Add statusLine to existing settings
        tmp=$(mktemp)
        jq '. + {"statusLine": {"type": "command", "command": "~/.claude/statusline-command.sh", "padding": 2}}' "$SETTINGS" > "$tmp"
        mv "$tmp" "$SETTINGS"
        echo "  Added statusLine config to $SETTINGS"
    fi
else
    # Create new settings file
    mkdir -p "$HOME/.claude"
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
