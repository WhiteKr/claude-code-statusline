# Claude Code Statusline

A custom statusline for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that displays real-time rate limit usage, context window, and session info.

```
[Opus] BE.Main  main*  $1.58  90m0s
━━━━━━━━━━━━━━━━━━───────── 65% 120K/200K
5h ━━━━━━━━━━━━━━─ 98% ~28m | 7d:Op ━━━━━━─────────── 35% ~2d0h
```

## Features

- **3-line layout** — model/dir/branch, context bar, rate limits on separate lines
- **Unicode progress bars** — `━` filled / `─` empty for clean visuals
- **Context window** — responsive bar with token count (current/max)
- **5-hour rate limit** — usage % with time until reset
- **7-day rate limit** — model-specific (Opus/Sonnet) when available
- **Extra usage** — shown only when actively consuming extra credits ($used/$limit)
- **Git branch** — current branch with dirty indicator
- **Session info** — model name, cumulative cost, session duration
- **Fixed bar widths** — context 20, rate limits 10 each
- **Non-blocking** — rate limit API calls are cached (60s) and refreshed in the background

## Requirements

- **Linux** (uses GNU `stat -c` and `date -d`)
- `jq` — JSON parsing
- `curl` — API calls
- `git` — optional, for branch display
- Claude Code with OAuth login (for rate limit data)

## Install

```bash
git clone https://github.com/whitekr/claude-code-statusline.git
cd claude-code-statusline
./install.sh
```

Or manually:

```bash
cp statusline-command.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

Then add to `~/.claude/settings.local.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-command.sh",
    "padding": 2
  }
}
```

Restart Claude Code.

## What's Displayed

### Line 1 — Session info
| Element | Description |
|---------|-------------|
| `[Opus]` | Current model (without "Claude" prefix) |
| `BE.Main` | Current directory name |
| `main*` | Git branch (* = uncommitted changes) |
| `$1.58` | Session cost |
| `90m0s` | Session duration |

### Line 2 — Context window
| Element | Description |
|---------|-------------|
| `━━━━━━━━━───────` | Context usage bar (Unicode) |
| `65%` | Context usage percentage |
| `120K/200K` | Current tokens / max tokens |
| `+$1.85/$20` | Extra usage (only when consuming) |

### Line 3 — Rate limits
| Element | Description |
|---------|-------------|
| `5h ━━━━━━━━━━━━━━─ 98%` | 5-hour rate limit bar |
| `~28m` | Time until 5h reset |
| `7d:Op ━━━━─────── 35%` | 7-day model-specific rate limit |
| `~2d0h` | Time until 7d reset |

## Color Coding

| Color | Threshold |
|-------|-----------|
| Green | < 50% |
| Cyan | 50-69% |
| Yellow | 70-89% |
| Red | 90%+ |

## How It Works

Claude Code pipes JSON with session data to the statusline script via stdin. The script:

1. Parses context window, model, and cost from the JSON (single `jq` call)
2. Reads cached rate limit data from `/tmp/.claude-rate-limits-cache`
3. If cache is stale (>60s), triggers a background API call to `api.anthropic.com/api/oauth/usage`
4. Renders three lines with ANSI colors, Unicode bars, and context-aware color thresholds

No credentials are stored in the script — OAuth tokens are read at runtime from `~/.claude/.credentials.json` (managed by Claude Code).

## License

MIT
