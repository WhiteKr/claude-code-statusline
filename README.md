# Claude Code Statusline

A custom statusline for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that displays model, project, git status, context window, and rate limit usage. Pick a 1-, 2-, or 3-line layout at install time.

**3-line (default)** — context bar gets its own line, rate limits with countdowns:
```
Claude Opus 4.7 │ my-project │ main ✎3 ↑2
CTX ━━━━━━━━━━━━━───────────────── 045%
5H ━━━━━━──── 062% ↻03h15m │ 7D ━━──────── 028% ↻04d18h
```

**2-line** — header, then combined gauges:
```
Claude Opus 4.7 │ my-project │ main ✎3 ↑2
CTX ━━━━━━───────── 045% │ 5H ━━━━──── 062% │ 7D ━━────── 028%
```

**1-line** — everything on one line, with mini bars:
```
Claude Opus 4.7 │ my-project │ main ✎3 ↑2 │ CTX ━━─── 045% │ 5H ━━━── 062% │ 7D ━──── 028%
```

## Features

- **Choose your layout** — 1, 2, or 3 lines, picked interactively during install
- **Unicode progress bars** — `━` filled / `─` empty, every layout shows bars (5/15/30 chars depending on layout)
- **Context window** — bar + percent on every layout
- **5-hour & 7-day rate limits** — bars + percent; countdowns shown in 3-line mode
- **Git branch** — current branch with dirty file count (`✎N`) and upstream divergence (`↑ahead ↓behind`)
- **Dim leading zeros** — fixed-width numerics with leading zeros dimmed for visual stability
- **Zero external calls** — rate limit data read directly from Claude Code's stdin JSON

## Requirements

- `bash`
- `jq` — JSON parsing
- `git` — optional, for branch display
- Claude Code recent enough to provide `.rate_limits` in the statusline JSON

### Platform support

| Platform | Status |
|----------|--------|
| macOS | Works out of the box (install `jq` via `brew install jq`) |
| Linux | Works out of the box (install `jq` via your package manager) |
| Windows + WSL | Works (treated as Linux) |
| Windows native (Git for Windows installed) | Works — Claude Code on Windows runs statusLine commands through Git Bash automatically |
| Windows native (no Git Bash) | Not supported — install [Git for Windows](https://git-scm.com/download/win) to enable |

## Install

One-liner (downloads the installer + statusline script from the latest GitHub release):

```bash
curl -fsSL https://github.com/whitekr/claude-code-statusline/releases/latest/download/install.sh | bash
```

The installer prompts you to pick a 1-, 2-, or 3-line layout (with rendered previews) and writes the chosen layout into `~/.claude/settings.json`. To skip the prompt — for example in CI — set `STATUSLINE_LINES`:

```bash
curl -fsSL https://github.com/whitekr/claude-code-statusline/releases/latest/download/install.sh | STATUSLINE_LINES=2 bash
```

### Changing layout later

Re-run the installer (it detects your current choice and offers it as the default), or edit `~/.claude/settings.json` directly and change the trailing `1`/`2`/`3` argument on `.statusLine.command`.

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
