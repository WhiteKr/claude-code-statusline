#!/bin/bash

input=$(cat)
cwd=$(pwd)
NOW=$(date +%s)

CYAN='\033[36m'
YELLOW='\033[33m'
DIM='\033[2m'
RST='\033[0m'

is_valid_util() { [ "$1" != "-1" ] && [ "$1" != "null" ] && [ -n "$1" ]; }

# threshold_color <value> <red_at> <yellow_at> <cyan_at>
threshold_color() {
    if [ "$1" -ge "$2" ]; then echo '\033[31m'
    elif [ "$1" -ge "$3" ]; then echo '\033[33m'
    elif [ "$1" -ge "$4" ]; then echo '\033[36m'
    else echo '\033[32m'; fi
}

draw_bar() {
    local pct=$1 w=$2
    local f=$((pct * w / 100)) e bar=""
    [ "$f" -gt "$w" ] && f=$w
    e=$((w - f))
    while [ "$f" -gt 0 ]; do bar+="━"; f=$((f-1)); done
    while [ "$e" -gt 0 ]; do bar+="─"; e=$((e-1)); done
    echo "$bar"
}

file_age() { echo $(( NOW - $(stat -c %Y "$1" 2>/dev/null || echo 0) )); }

time_until() {
    local iso="$1" reset_epoch diff h m
    [ -z "$iso" ] && return
    reset_epoch=$(date -d "$iso" +%s 2>/dev/null)
    [ -z "$reset_epoch" ] && return
    diff=$(( reset_epoch - NOW ))
    [ "$diff" -le 0 ] && { echo "now"; return; }
    h=$((diff / 3600)); m=$(( (diff % 3600) / 60 ))
    if [ "$h" -gt 24 ]; then echo "$((h/24))d$((h%24))h"
    elif [ "$h" -gt 0 ]; then echo "${h}h${m}m"
    else echo "${m}m"; fi
}

calc_pct() {
    local util="$1"
    if is_valid_util "$util"; then
        _pct_num=$(printf "%.0f" "$util")
        _pct_str="${_pct_num}%"
    else
        _pct_num=0; _pct_str="--%"
    fi
}

# ── Parse JSON ────────────────────────────────
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

# ── Derived values ────────────────────────────
total_s=$((J_DURATION / 1000))
dur_m=$((total_s / 60)); dur_s=$((total_s % 60))
[ "$dur_m" -gt 0 ] && DUR_STR="${dur_m}m${dur_s}s" || DUR_STR="${dur_s}s"

cur_tokens=$((J_CUR_INPUT + J_CUR_CC + J_CUR_CR))
if [ "$cur_tokens" -ge 1000000 ]; then tok_display="$((cur_tokens / 100000))"; tok_display="${tok_display:0:-1}.${tok_display: -1}M"
elif [ "$cur_tokens" -ge 1000 ]; then tok_display="$((cur_tokens / 1000))K"
else tok_display="${cur_tokens}"; fi
ctx_display="$((J_CTX_SIZE / 1000))K"

cost_display=$(printf '$%.2f' "$J_COST")

# ── Git branch ─────────────────────────────────
GIT_BRANCH=$(git -C "$cwd" branch --show-current 2>/dev/null)
if [ -n "$GIT_BRANCH" ]; then
    git -C "$cwd" diff-index --quiet HEAD -- 2>/dev/null || GIT_BRANCH+="*"
fi

DIR_NAME="${cwd##*/}"
MODEL_SHORT="${J_MODEL#Claude }"

# ── Rate limits (cached 60s, background refresh) ─
CACHE_FILE="/tmp/.claude-rate-limits-cache"
CACHE_LOCK="/tmp/.claude-rate-limits-lock"

fetch_rate_limits() {
    local CRED="$HOME/.claude/.credentials.json" TOK RESP
    [ ! -f "$CRED" ] && return 1
    TOK=$(jq -r '.claudeAiOauth.accessToken // empty' "$CRED" 2>/dev/null)
    [ -z "$TOK" ] && return 1
    RESP=$(curl -s --max-time 3 -H "Authorization: Bearer $TOK" -H "anthropic-beta: oauth-2025-04-20" \
        "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
    echo "$RESP" | jq -e '.five_hour' >/dev/null 2>&1 && echo "$RESP" > "$CACHE_FILE" 2>/dev/null
    rm -f "$CACHE_LOCK" 2>/dev/null
}

RATE_DATA=""
if [ -f "$CACHE_FILE" ]; then
    RATE_DATA=$(cat "$CACHE_FILE")
    [ -f "$CACHE_LOCK" ] && [ "$(file_age "$CACHE_LOCK")" -ge 120 ] && rm -f "$CACHE_LOCK"
    if [ "$(file_age "$CACHE_FILE")" -ge 60 ] && [ ! -f "$CACHE_LOCK" ]; then
        touch "$CACHE_LOCK" 2>/dev/null; fetch_rate_limits &
    fi
else
    fetch_rate_limits &
fi

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
        @sh "extra_limit=\(.extra_usage.monthly_limit // 0)"
    ' 2>/dev/null | tr ',' '\n')"
else
    h5_util=-1; d7_util=-1; h5_reset=""; d7_reset=""
    d7_opus_util=-1; d7_opus_reset=""; d7_sonnet_util=-1; d7_sonnet_reset=""
    extra_enabled=false; extra_used=0; extra_limit=0
fi

# Model-specific 7d
d7_display_util="$d7_util"; d7_display_reset="$d7_reset"; d7_label="7d"
case "$J_MODEL_ID" in
    *opus*)  is_valid_util "$d7_opus_util" && { d7_display_util="$d7_opus_util"; d7_display_reset="$d7_opus_reset"; d7_label="7d:Op"; } ;;
    *sonnet*) is_valid_util "$d7_sonnet_util" && { d7_display_util="$d7_sonnet_util"; d7_display_reset="$d7_sonnet_reset"; d7_label="7d:So"; } ;;
esac

calc_pct "$h5_util"; h5_pct_num=$_pct_num; h5_pct_str=$_pct_str
calc_pct "$d7_display_util"; d7_pct_num=$_pct_num; d7_pct_str=$_pct_str
h5_time_str=$(time_until "$h5_reset")
d7_time_str=$(time_until "$d7_display_reset")

# Extra usage
extra_text=""
if [ "$extra_enabled" = "true" ] && [ "$extra_used" -gt 0 ] 2>/dev/null; then
    extra_dollars=$((extra_used / 100))
    extra_cents=$((extra_used % 100))
    extra_limit_fmt="$((extra_limit / 100))"
    extra_text=$(printf '+$%d.%02d/$%s' "$extra_dollars" "$extra_cents" "$extra_limit_fmt")
fi

# ── Line 1: [Model] dir  branch  $cost  time ─
L1="${CYAN}[${MODEL_SHORT}]${RST} ${DIR_NAME}"
[ -n "$GIT_BRANCH" ] && L1+="  ${YELLOW}${GIT_BRANCH}${RST}"
L1+="  ${DIM}${cost_display}  ${DUR_STR}${RST}"
printf "%b\n" "$L1"

# ── Line 2: bar pct tokens | extra ───────────
BAR_COLOR=$(threshold_color "$J_USED" 75 55 30)
L2="${BAR_COLOR}$(draw_bar "$J_USED" 20) ${J_USED}%${RST}"
L2+=" ${DIM}${tok_display}/${ctx_display}${RST}"
[ -n "$extra_text" ] && L2+=" ${DIM}|${RST} ${YELLOW}${extra_text}${RST}"
printf "%b\n" "$L2"

# ── Line 3: 5h bar pct ~reset | 7d bar pct ~reset ─
h5c=$(threshold_color "$h5_pct_num" 90 70 50); d7c=$(threshold_color "$d7_pct_num" 90 70 50)
L3="${h5c}5h $(draw_bar "$h5_pct_num" 10) ${h5_pct_str}${RST}"
[ -n "$h5_time_str" ] && L3+=" ${DIM}~${h5_time_str}${RST}"
L3+=" ${DIM}|${RST} ${d7c}${d7_label} $(draw_bar "$d7_pct_num" 10) ${d7_pct_str}${RST}"
[ -n "$d7_time_str" ] && L3+=" ${DIM}~${d7_time_str}${RST}"
printf "%b\n" "$L3"
