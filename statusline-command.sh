#!/bin/bash

# Claude Code Custom Statusline
# Shows: directory, git branch, context bar, 5h/7d rate limits, model-specific 7d, extra usage

input=$(cat)
cwd=$(pwd)
NOW=$(date +%s)

# ── Shared helpers ──────────────────────────────
is_valid_util() {
    [ "$1" != "-1" ] && [ "$1" != "null" ] && [ -n "$1" ]
}

pct_color() {
    local pct="$1"
    if [ "$pct" -ge 90 ]; then echo '\033[31m'
    elif [ "$pct" -ge 70 ]; then echo '\033[33m'
    elif [ "$pct" -ge 50 ]; then echo '\033[36m'
    else echo '\033[32m'; fi
}

draw_bar() {
    local pct="$1" width="$2"
    local f=$((pct * width / 100))
    [ "$f" -gt "$width" ] && f=$width
    local e=$((width - f))
    local bar=""
    [ "$f" -gt 0 ] && bar=$(printf "%${f}s" | tr ' ' '#')
    [ "$e" -gt 0 ] && bar="${bar}$(printf "%${e}s" | tr ' ' '-')"
    echo "$bar"
}

file_age() {
    echo $(( NOW - $(stat -c %Y "$1" 2>/dev/null || echo 0) ))
}

# ── Parse all JSON fields at once (single jq call) ──
eval "$(echo "$input" | jq -r '
  @sh "J_MODEL=\(.model.display_name // "?")",
  @sh "J_MODEL_ID=\(.model.id // "")",
  @sh "J_USED=\(.context_window.used_percentage // 0 | floor)",
  @sh "J_CTX_SIZE=\(.context_window.context_window_size // 200000)",
  @sh "J_CUR_INPUT=\(.context_window.current_usage.input_tokens // 0)",
  @sh "J_CUR_CC=\(.context_window.current_usage.cache_creation_input_tokens // 0)",
  @sh "J_CUR_CR=\(.context_window.current_usage.cache_read_input_tokens // 0)",
  @sh "J_COST=\(.cost.total_cost_usd // 0)",
  @sh "J_DURATION=\(.cost.total_duration_ms // 0)"
' 2>/dev/null | tr ',' '\n')"

: "${J_MODEL:=?}" "${J_MODEL_ID:=}" "${J_USED:=0}" "${J_CTX_SIZE:=200000}"
: "${J_CUR_INPUT:=0}" "${J_CUR_CC:=0}" "${J_CUR_CR:=0}" "${J_COST:=0}" "${J_DURATION:=0}"

# ── Session duration (pure bash) ────────────────
total_s=$((J_DURATION / 1000))
dur_h=$((total_s / 3600))
dur_m=$(( (total_s % 3600) / 60 ))
if [ "$dur_h" -gt 0 ]; then SESSION_DUR="${dur_h}h${dur_m}m"
elif [ "$dur_m" -gt 0 ]; then SESSION_DUR="${dur_m}m"
else SESSION_DUR="<1m"; fi

# ── Git branch (cached 5s, sentinel for no-repo) ─
GIT_CACHE="/tmp/.claude-git-cache"
GIT_CACHE_TTL=5
GIT_CACHED=0

if [ -f "$GIT_CACHE" ]; then
    [ "$(file_age "$GIT_CACHE")" -lt "$GIT_CACHE_TTL" ] && { GIT_INFO=$(cat "$GIT_CACHE"); GIT_CACHED=1; }
fi

if [ "$GIT_CACHED" -eq 0 ]; then
    BRANCH=$(git -C "$cwd" branch --show-current 2>/dev/null)
    if [ -n "$BRANCH" ]; then
        DIRTY=$(git -C "$cwd" status --porcelain 2>/dev/null | head -1)
        GIT_INFO=" [${BRANCH}${DIRTY:+*}]"
    else
        GIT_INFO=""
    fi
    printf '%s' "$GIT_INFO" > "$GIT_CACHE" 2>/dev/null
fi

# ── Shorten directory path (pure bash) ──────────
p="${cwd/#$HOME/\~}"
IFS='/' read -ra segs <<< "$p"
if [ "${#segs[@]}" -gt 3 ]; then
    SHORT_CWD="${segs[0]}"
    last2=$(( ${#segs[@]} - 2 ))
    for ((i=1; i<${#segs[@]}; i++)); do
        if [ "$i" -ge "$last2" ]; then
            SHORT_CWD+="/${segs[$i]}"
        else
            SHORT_CWD+="/${segs[$i]:0:1}"
        fi
    done
else
    SHORT_CWD="$p"
fi

# ── Terminal width & responsive sizing ──────────
COLS=$(tput cols 2>/dev/null || echo 80)
COMPACT=0
[ "$COLS" -lt 60 ] && COMPACT=1

BAR_WIDTH=$((COLS - 52))
[ "$BAR_WIDTH" -lt 5 ] && BAR_WIDTH=5
[ "$BAR_WIDTH" -gt 50 ] && BAR_WIDTH=50

RATE_BAR_W=5
[ "$COLS" -ge 120 ] && RATE_BAR_W=8
[ "$COLS" -ge 160 ] && RATE_BAR_W=10

# ── Context progress bar ───────────────────────
BAR=$(draw_bar "$J_USED" "$BAR_WIDTH")
CTX_COLOR=$(pct_color "$J_USED")

# Token count display (hidden in compact mode)
TOK_INFO=""
if [ "$COMPACT" -eq 0 ]; then
    cur_tokens=$((J_CUR_INPUT + J_CUR_CC + J_CUR_CR))
    if [ "$cur_tokens" -ge 1000000 ]; then
        tok_display=$(awk "BEGIN {printf \"%.1fM\", $cur_tokens/1000000}")
    elif [ "$cur_tokens" -ge 1000 ]; then
        tok_display="$((cur_tokens / 1000))K"
    else
        tok_display="${cur_tokens}"
    fi
    ctx_display="$((J_CTX_SIZE / 1000))K"
    TOK_INFO=" \033[2m(${tok_display}/${ctx_display})\033[0m"
fi

CTX_LINE="${CTX_COLOR}${BAR} ${J_USED}%\033[0m${TOK_INFO}"

# ── Session cost ────────────────────────────────
cost_display=$(printf '$%.2f' "$J_COST")

# ── Rate limits (cached, non-blocking) ──────────
CACHE_FILE="/tmp/.claude-rate-limits-cache"
CACHE_LOCK="/tmp/.claude-rate-limits-lock"
CACHE_TTL=60

fetch_rate_limits() {
    CRED_FILE="$HOME/.claude/.credentials.json"
    [ ! -f "$CRED_FILE" ] && return 1
    TOKEN=$(jq -r '.claudeAiOauth.accessToken // empty' "$CRED_FILE" 2>/dev/null)
    [ -z "$TOKEN" ] && return 1
    RESP=$(curl -s --max-time 3 \
        -H "Authorization: Bearer $TOKEN" \
        -H "anthropic-beta: oauth-2025-04-20" \
        "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
    if echo "$RESP" | jq -e '.five_hour' >/dev/null 2>&1; then
        echo "$RESP" > "$CACHE_FILE" 2>/dev/null
    fi
    rm -f "$CACHE_LOCK" 2>/dev/null
}

RATE_DATA=""
if [ -f "$CACHE_FILE" ]; then
    RATE_DATA=$(cat "$CACHE_FILE")
    # Stale lock cleanup (>120s = stuck background fetch)
    if [ -f "$CACHE_LOCK" ] && [ "$(file_age "$CACHE_LOCK")" -ge 120 ]; then
        rm -f "$CACHE_LOCK" 2>/dev/null
    fi
    if [ "$(file_age "$CACHE_FILE")" -ge "$CACHE_TTL" ] && [ ! -f "$CACHE_LOCK" ]; then
        touch "$CACHE_LOCK" 2>/dev/null
        fetch_rate_limits &
    fi
else
    fetch_rate_limits
    [ -f "$CACHE_FILE" ] && RATE_DATA=$(cat "$CACHE_FILE")
fi

# Parse rate limit values (single jq call)
if [ -n "$RATE_DATA" ]; then
    eval "$(echo "$RATE_DATA" | jq -r '
        @sh "h5_util=\(.five_hour.utilization // -1)",
        @sh "d7_util=\(.seven_day.utilization // -1)",
        @sh "h5_reset=\(.five_hour.resets_at // "")",
        @sh "d7_reset=\(.seven_day.resets_at // "")",
        @sh "d7_opus_util=\(.seven_day_opus.utilization // -1)",
        @sh "d7_opus_reset=\(.seven_day_opus.resets_at // "")",
        @sh "d7_sonnet_util=\(.seven_day_sonnet.utilization // -1)",
        @sh "d7_sonnet_reset=\(.seven_day_sonnet.resets_at // "")",
        @sh "extra_enabled=\(.extra_usage.is_enabled // false)",
        @sh "extra_used=\(.extra_usage.used_credits // 0)",
        @sh "extra_limit=\(.extra_usage.monthly_limit // 0)",
        @sh "extra_util_raw=\(.extra_usage.utilization // "null")"
    ' 2>/dev/null | tr ',' '\n')"
else
    h5_util=-1; d7_util=-1; h5_reset=""; d7_reset=""
    d7_opus_util=-1; d7_opus_reset=""; d7_sonnet_util=-1; d7_sonnet_reset=""
    extra_enabled=false; extra_used=0; extra_limit=0; extra_util_raw=null
fi

# ── Detect model-specific 7d limit ──────────────
d7_display_util="$d7_util"
d7_display_reset="$d7_reset"
d7_label="7d"

case "$J_MODEL_ID" in
    *opus*)  is_valid_util "$d7_opus_util" && { d7_display_util="$d7_opus_util"; d7_display_reset="$d7_opus_reset"; d7_label="7d:Op"; } ;;
    *sonnet*) is_valid_util "$d7_sonnet_util" && { d7_display_util="$d7_sonnet_util"; d7_display_reset="$d7_sonnet_reset"; d7_label="7d:So"; } ;;
esac

# ── Time-until-reset helper ─────────────────────
time_until() {
    local iso="$1"
    [ -z "$iso" ] && return
    local reset_epoch=$(date -d "$iso" +%s 2>/dev/null)
    [ -z "$reset_epoch" ] && return
    local diff=$(( reset_epoch - NOW ))
    [ "$diff" -le 0 ] && { echo "now"; return; }
    local h=$((diff / 3600)) m=$(( (diff % 3600) / 60 ))
    if [ "$h" -gt 24 ]; then
        echo "$((h / 24))d$((h % 24))h"
    elif [ "$h" -gt 0 ]; then
        echo "${h}h${m}m"
    else
        echo "${m}m"
    fi
}

# ── Rate limit display ──────────────────────────
rate_limit_display() {
    local label="$1" util="$2" bar_w="${3:-5}" reset_iso="$4" show_reset="${5:-1}"

    if ! is_valid_util "$util"; then
        printf "\033[2m%s --%%\033[0m" "$label"
        return
    fi

    local pct=$(awk "BEGIN {printf \"%.0f\", $util}")
    local c=$(pct_color "$pct")
    local bar=$(draw_bar "$pct" "$bar_w")

    local reset_str=""
    if [ "$show_reset" -eq 1 ] && [ -n "$reset_iso" ]; then
        local t=$(time_until "$reset_iso")
        [ -n "$t" ] && reset_str=" \033[2m~${t}\033[0m"
    fi

    printf "${c}%s %s %s%%\033[0m%b" "$label" "$bar" "$pct" "$reset_str"
}

SHOW_RESET=1
[ "$COMPACT" -eq 1 ] && SHOW_RESET=0

H5_DISPLAY=$(rate_limit_display "5h" "$h5_util" "$RATE_BAR_W" "$h5_reset" "$SHOW_RESET")
D7_DISPLAY=$(rate_limit_display "$d7_label" "$d7_display_util" "$RATE_BAR_W" "$d7_display_reset" "$SHOW_RESET")

# ── Extra usage (only when actually consuming) ──
EXTRA_DISPLAY=""
if [ "$extra_enabled" = "true" ]; then
    if awk "BEGIN {exit !($extra_used > 0)}"; then
        extra_used_fmt=$(awk "BEGIN {printf \"%.2f\", $extra_used / 100}")
        extra_limit_fmt="$((extra_limit / 100))"

        if [ "$extra_util_raw" != "null" ]; then
            extra_pct=$(awk "BEGIN {printf \"%.0f\", $extra_util_raw}")
        elif [ "$extra_limit" -gt 0 ]; then
            extra_pct=$(awk "BEGIN {printf \"%.0f\", $extra_used / $extra_limit * 100}")
        else
            extra_pct=0
        fi

        EC=$(pct_color "$extra_pct")
        EXTRA_DISPLAY=$(printf "  ${EC}+\$%s/\$%s\033[0m" "$extra_used_fmt" "$extra_limit_fmt")
    fi
fi

# ── Output ──────────────────────────────────────
printf "\033[01;34m%s\033[0m\033[33m%s\033[0m \033[35m(%s)\033[0m \033[2m%s %s\033[0m\n" \
    "$SHORT_CWD" "$GIT_INFO" "$J_MODEL" "$cost_display" "$SESSION_DUR"

printf "ctx %b  %b  %b%b\n" "$CTX_LINE" "$H5_DISPLAY" "$D7_DISPLAY" "$EXTRA_DISPLAY"
