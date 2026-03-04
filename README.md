# Claude Code Statusline

A custom statusline for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that displays real-time rate limit usage, context window, and session info.

```
~ [main*] (Opus) $1.58 1h30m
ctx ##################---------- 65% (120K/200K)  5h ####- 98% ~28m  7d #---- 35% ~2d0h
```

## Features

- **Context window** — responsive progress bar with token count (current/max)
- **5-hour rate limit** — usage % with time until reset
- **7-day rate limit** — model-specific (Opus/Sonnet) when available
- **Extra usage** — shown only when actively consuming extra credits ($used/$limit)
- **Git branch** — current branch with dirty indicator, cached for performance
- **Session info** — model name, cumulative cost, session duration
- **Responsive** — bar widths adapt to terminal width, compact mode for narrow terminals
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

| Element | Description |
|---------|-------------|
| `~/P/Z/BE.Main` | Shortened working directory |
| `[main*]` | Git branch (* = uncommitted changes) |
| `(Opus)` | Current model |
| `$1.58` | Session cost |
| `1h30m` | Session duration |
| `ctx ###---` | Context window usage bar |
| `65% (120K/200K)` | Context % and tokens |
| `5h ####- 98% ~28m` | 5-hour rate limit with reset time |
| `7d #---- 35% ~2d0h` | 7-day rate limit with reset time |
| `+$1.85/$20` | Extra usage (only when consuming) |

## Color Coding

| Color | Threshold |
|-------|-----------|
| Green | < 50% |
| Cyan | 50–69% |
| Yellow | 70–89% |
| Red | 90%+ |

## How It Works

Claude Code pipes JSON with session data to the statusline script via stdin. The script:

1. Parses context window, model, and cost from the JSON (single `jq` call)
2. Reads cached rate limit data from `/tmp/.claude-rate-limits-cache`
3. If cache is stale (>60s), triggers a background API call to `api.anthropic.com/api/oauth/usage`
4. Renders two lines with ANSI colors and responsive bar widths

No credentials are stored in the script — OAuth tokens are read at runtime from `~/.claude/.credentials.json` (managed by Claude Code).

## License

MIT
