#!/bin/bash

input=$(cat)
cwd=$(pwd)
printf -v NOW '%(%s)T' -1

RED='\033[31m'
GREEN='\033[32m'
CYAN='\033[36m'
YELLOW='\033[33m'
DIM='\033[2m'
DIM_NUM='\033[38;5;237m'
RST='\033[0m'

is_valid_util() { [ "$1" != "-1" ] && [ "$1" != "null" ] && [ -n "$1" ]; }

# threshold_color <value> <red_at> <yellow_at> <cyan_at> → sets _tc
threshold_color() {
    if [ "$1" -ge "$2" ]; then _tc=$RED
    elif [ "$1" -ge "$3" ]; then _tc=$YELLOW
    elif [ "$1" -ge "$4" ]; then _tc=$CYAN
    else _tc=$GREEN; fi
}

# draw_bar <pct> <width> → sets _bar
draw_bar() {
    local pct=$1 w=$2
    local f=$((pct * w / 100)) e filled empty
    [ "$f" -gt "$w" ] && f=$w
    e=$((w - f))
    printf -v filled '%*s' "$f" ''; filled="${filled// /━}"
    printf -v empty '%*s' "$e" ''; empty="${empty// /─}"
    _bar="${filled}${empty}"
}

# pad_dim_zeros <value> <width> [restore_color] → sets _pad_result
pad_dim_zeros() {
    local val="$1" width="$2" restore="${3:-\033[39m}"
    local len=${#val}
    local pad=$((width - len))
    if [ "$pad" -gt 0 ]; then
        local z="00000000"
        _pad_result="${DIM_NUM}${z:0:$pad}${restore}${val}"
    else
        _pad_result="$val"
    fi
}

# file_age <path> → sets _file_age
file_age() { _file_age=$(( NOW - $(stat -c %Y "$1" 2>/dev/null || echo 0) )); }

# time_until <epoch> → sets _time_str
time_until() {
    local epoch="$1" diff h m
    _time_str=""
    [ -z "$epoch" ] || [ "$epoch" = "-1" ] && return
    diff=$(( epoch - NOW ))
    [ "$diff" -le 0 ] && { _time_str="now"; return; }
    h=$((diff / 3600)); m=$(( (diff % 3600) / 60 ))
    if [ "$h" -gt 24 ]; then _time_str="$((h/24))d$((h%24))h"
    elif [ "$h" -gt 0 ]; then _time_str="${h}h${m}m"
    else _time_str="${m}m"; fi
}

calc_pct() {
    if is_valid_util "$1"; then
        _pct_num=$(printf "%.0f" "$1")
        _pct_valid=1
    else
        _pct_num=0; _pct_valid=0
    fi
}

# format_rate_pct <valid> <pct_num> → sets _rate_color, _rate_display
format_rate_pct() {
    if [ "$1" = 1 ]; then
        threshold_color "$2" 90 70 50; _rate_color=$_tc
        pad_dim_zeros "$2" 3 "$_rate_color"; _rate_display="${_pad_result}%"
    else
        _rate_color=$DIM; _rate_display="--%"
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
' 2>/dev/null)"

: "${J_MODEL:=?}" "${J_MODEL_ID:=}" "${J_USED:=0}" "${J_CTX_SIZE:=200000}"
: "${J_CUR_INPUT:=0}" "${J_CUR_CC:=0}" "${J_CUR_CR:=0}" "${J_COST:=0}" "${J_DURATION:=0}"

# ── Derived values ────────────────────────────
total_s=$((J_DURATION / 1000))
dur_h=$((total_s / 3600)); dur_m=$(( (total_s % 3600) / 60 )); dur_s=$((total_s % 60))
if [ "$dur_h" -gt 0 ]; then DUR_STR="${dur_h}h${dur_m}m"
elif [ "$dur_m" -gt 0 ]; then DUR_STR="${dur_m}m${dur_s}s"
else DUR_STR="${dur_s}s"; fi

cur_tokens=$((J_CUR_INPUT + J_CUR_CC + J_CUR_CR))
if [ "$cur_tokens" -ge 1000000 ]; then tok_display="$((cur_tokens / 100000))"; tok_display="${tok_display:0:-1}.${tok_display: -1}M"
elif [ "$cur_tokens" -ge 1000 ]; then tok_display="$((cur_tokens / 1000))K"
else tok_display="0K"; fi
ctx_display="$((J_CTX_SIZE / 1000))K"

printf -v cost_display '$%.2f' "$J_COST"

# ── Git branch ─────────────────────────────────
GIT_BRANCH=$(git -C "$cwd" branch --show-current 2>/dev/null)
if [ -n "$GIT_BRANCH" ]; then
    git -C "$cwd" diff-index --quiet HEAD -- 2>/dev/null || GIT_BRANCH+="*"
fi

DIR_NAME="${cwd%/*}"; DIR_NAME="${DIR_NAME##*/}/${cwd##*/}"
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
    if echo "$RESP" | jq -e '.five_hour' >/dev/null 2>&1; then
        echo "$RESP" > "$CACHE_FILE" 2>/dev/null
    fi
    rm -f "$CACHE_LOCK" 2>/dev/null
}

RATE_DATA=""
_lock_mtime=$(stat -c %Y "$CACHE_LOCK" 2>/dev/null) && [ $(( NOW - _lock_mtime )) -ge 120 ] && rm -f "$CACHE_LOCK"
if [ -f "$CACHE_FILE" ]; then
    RATE_DATA=$(<"$CACHE_FILE")
    file_age "$CACHE_FILE"
    if [ "$_file_age" -ge 60 ] && [ ! -f "$CACHE_LOCK" ]; then
        touch "$CACHE_LOCK" 2>/dev/null; fetch_rate_limits &
    fi
elif [ ! -f "$CACHE_LOCK" ]; then
    touch "$CACHE_LOCK" 2>/dev/null; fetch_rate_limits &
fi

if [ -n "$RATE_DATA" ]; then
    eval "$(echo "$RATE_DATA" | jq -r '
        def epoch: if type == "string" and length > 0 then fromdateiso8601 else -1 end;
        @sh "h5_util=\(.five_hour.utilization // -1)",
        @sh "d7_util=\(.seven_day.utilization // -1)",
        @sh "h5_reset_epoch=\(.five_hour.resets_at | epoch)",
        @sh "d7_reset_epoch=\(.seven_day.resets_at | epoch)",
        @sh "d7_opus_util=\(.seven_day_opus.utilization // -1)",
        @sh "d7_opus_reset_epoch=\(.seven_day_opus.resets_at | epoch)",
        @sh "d7_sonnet_util=\(.seven_day_sonnet.utilization // -1)",
        @sh "d7_sonnet_reset_epoch=\(.seven_day_sonnet.resets_at | epoch)",
        @sh "extra_enabled=\(.extra_usage.is_enabled // false)",
        @sh "extra_used=\(.extra_usage.used_credits // 0)",
        @sh "extra_limit=\(.extra_usage.monthly_limit // 0)"
    ' 2>/dev/null)"
else
    h5_util=-1; d7_util=-1; h5_reset_epoch=-1; d7_reset_epoch=-1
    d7_opus_util=-1; d7_opus_reset_epoch=-1; d7_sonnet_util=-1; d7_sonnet_reset_epoch=-1
    extra_enabled=false; extra_used=0; extra_limit=0
fi

# Model-specific 7d
d7_display_util="$d7_util"; d7_display_reset_epoch="$d7_reset_epoch"; d7_label="7d"
case "$J_MODEL_ID" in
    *opus*)  is_valid_util "$d7_opus_util" && { d7_display_util="$d7_opus_util"; d7_display_reset_epoch="$d7_opus_reset_epoch"; d7_label="7d:Op"; } ;;
    *sonnet*) is_valid_util "$d7_sonnet_util" && { d7_display_util="$d7_sonnet_util"; d7_display_reset_epoch="$d7_sonnet_reset_epoch"; d7_label="7d:So"; } ;;
esac

calc_pct "$h5_util"; h5_pct_num=$_pct_num; h5_valid=$_pct_valid
calc_pct "$d7_display_util"; d7_pct_num=$_pct_num; d7_valid=$_pct_valid
time_until "$h5_reset_epoch"; h5_time_str=$_time_str
time_until "$d7_display_reset_epoch"; d7_time_str=$_time_str

# Extra usage
extra_text=""
if [ "$extra_enabled" = "true" ] && [ "$extra_used" -gt 0 ] 2>/dev/null; then
    extra_dollars=$((extra_used / 100))
    extra_cents=$((extra_used % 100))
    extra_limit_fmt="$((extra_limit / 100))"
    printf -v extra_text '+$%d.%02d/$%s' "$extra_dollars" "$extra_cents" "$extra_limit_fmt"
fi

# ── Bar widths (L2 aligned to L3 core) ───────
# L3: "5h "(3) + bar(W) + " "(1) + pct(4) + " | "(3) + label(len) + " "(1) + bar(W) + " "(1) + pct(4) = 17 + 2W + len
# L2: bar(W) + " "(1) + pct(4) + " "(1) + tok(len) + "/"(1) + ctx(len) = 7 + 2*len(ctx)
RATE_BAR_W=10
L3_CORE_W=$((17 + 2 * RATE_BAR_W + ${#d7_label}))
CTX_BAR_W=$((L3_CORE_W - 7 - 2 * ${#ctx_display}))
[ "$CTX_BAR_W" -lt 15 ] && CTX_BAR_W=15
[ "$CTX_BAR_W" -gt 40 ] && CTX_BAR_W=40

# ── Line 1: dir branch [model] uptime ─────────
L1="${DIR_NAME}"
[ -n "$GIT_BRANCH" ] && L1+="  ${YELLOW}${GIT_BRANCH}${RST}"
L1+="  ${CYAN}[${MODEL_SHORT}]${RST}  ${DIM}${DUR_STR}${RST}"
printf "%b\n" "$L1"

# ── Line 2: ctx-bar (cost) ───────────────────
threshold_color "$J_USED" 75 55 30; BAR_COLOR=$_tc
pad_dim_zeros "$J_USED" 3 "$BAR_COLOR"
draw_bar "$J_USED" "$CTX_BAR_W"
L2="${BAR_COLOR}${_bar} ${_pad_result}%${RST}"
pad_dim_zeros "$tok_display" "${#ctx_display}"
L2+=" ${_pad_result}${DIM}/${ctx_display}${RST}"
L2+=" ${DIM}(${cost_display})${RST}"
[ -n "$extra_text" ] && L2+=" ${YELLOW}${extra_text}${RST}"
printf "%b\n" "$L2"

# ── Line 3: 5h bar pct ~reset | 7d bar pct ~reset ─
format_rate_pct "$h5_valid" "$h5_pct_num"; h5c=$_rate_color; h5_pct_display=$_rate_display
format_rate_pct "$d7_valid" "$d7_pct_num"; d7c=$_rate_color; d7_pct_display=$_rate_display
rate_hint=""
if [ "$h5_valid" = 0 ] && [ "$d7_valid" = 0 ]; then
    if [ -z "$RATE_DATA" ]; then
        if [ -f "$CACHE_LOCK" ]; then rate_hint="loading…"
        else rate_hint="OAuth required"; fi
    else rate_hint="unavailable"; fi
fi
draw_bar "$h5_pct_num" "$RATE_BAR_W"; h5_bar=$_bar
draw_bar "$d7_pct_num" "$RATE_BAR_W"; d7_bar=$_bar
L3="${h5c}5h ${h5_bar} ${h5_pct_display}${RST}"
[ -n "$h5_time_str" ] && L3+=" ${DIM}~${h5_time_str}${RST}"
L3+=" ${DIM}|${RST} ${d7c}${d7_label} ${d7_bar} ${d7_pct_display}${RST}"
[ -n "$d7_time_str" ] && L3+=" ${DIM}~${d7_time_str}${RST}"
[ -n "$rate_hint" ] && L3+="  ${DIM}(${rate_hint})${RST}"
printf "%b\n" "$L3"
