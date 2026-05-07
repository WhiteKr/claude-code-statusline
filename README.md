# Claude Code Statusline

A custom statusline for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that displays model, project, git status, context window, and rate limit usage in a compact 3-line layout.

```
 Claude Opus 4.7 │ my-project │ main ✎3 ↑2
 CTX ━━━━━━━━━━━━━───────────────── 045%
 5H ━━━━━━──── 062% ↻03h15m │ 7D ━━──────── 028% ↻04d18h
```

## Features

- **3-line layout** — model/project/branch, context bar, rate limits on separate lines
- **Unicode progress bars** — `━` filled / `─` empty for clean visuals
- **Context window** — 30-char bar with percent
- **5-hour & 7-day rate limits** — 10-char bars with percent and time-until-reset
- **Git branch** — current branch with dirty file count (`✎N`) and upstream divergence (`↑ahead ↓behind`)
- **Dim leading zeros** — fixed-width numerics with leading zeros dimmed for visual stability
- **Zero external calls** — rate limit data read directly from Claude Code's stdin JSON

## Requirements

- `bash`
- `jq` — JSON parsing
- `git` — optional, for branch display
- Claude Code recent enough to provide `.rate_limits` in the statusline JSON

## Install

One-liner (downloads the installer + statusline script from the latest GitHub release):

```bash
curl -fsSL https://github.com/whitekr/claude-code-statusline/releases/latest/download/install.sh | bash
```

Or clone and run:

```bash
git clone https://github.com/whitekr/claude-code-statusline.git
cd claude-code-statusline
./install.sh
```

Or fully manual:

```bash
curl -fsSL https://github.com/whitekr/claude-code-statusline/releases/latest/download/statusline-command.sh \
  -o ~/.claude/statusline-command.sh
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

### Line 1 — Model │ Project │ Branch
| Element | Description |
|---------|-------------|
| `Claude Opus 4.7` | Model display name |
| `my-project` | Current project directory name |
| `main` | Git branch (omitted if not in a repo) |
| `✎3` | Number of modified/untracked files |
| `↑2` / `↓1` | Commits ahead / behind upstream |

### Line 2 — Context window
| Element | Description |
|---------|-------------|
| `CTX ━━━━━━━━━━━━━─────────────────` | 30-char usage bar |
| `045%` | Usage percent (leading zero dimmed) |

Shows `CTX --` when context usage data is unavailable.

### Line 3 — Rate limits
| Element | Description |
|---------|-------------|
| `5H ━━━━━━────` | 5-hour rate limit bar (10-char) |
| `062%` | 5-hour usage percent |
| `↻03h15m` | Time until 5-hour reset |
| `7D ━━────────` | 7-day rate limit bar (10-char) |
| `028%` | 7-day usage percent |
| `↻04d18h` | Time until 7-day reset |

Shows `5H --` / `7D --` when the corresponding rate limit isn't reported.

## Color Coding

All bars share the same thresholds:

| Color  | Threshold |
|--------|-----------|
| Green  | < 50%     |
| Yellow | 50–79%    |
| Red    | 80%+      |

## How It Works

Claude Code pipes JSON with session and rate-limit data to the statusline script via stdin. The script:

1. Parses model, project dir, context usage, and rate limits in a single `jq` call
2. Renders the git branch line by shelling out to `git` for branch, dirty status, and upstream divergence
3. Draws Unicode bars and ANSI-colored percentages with dim leading zeros for fixed-width alignment

There are no API calls, no caching, and no credential reads — everything comes from stdin or local `git`.

## License

MIT
