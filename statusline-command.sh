#!/bin/bash
input=$(cat)

# Layout: 1, 2, or 3 lines (default 3). Set by install.sh via the command arg.
LINES="${1:-3}"
case "$LINES" in 1|2|3) ;; *) LINES=3 ;; esac

# ── Parse JSON ────────────────────────────────
eval "$(echo "$input" | jq -r '
  @sh "J_MODEL=\(.model.display_name // "?")",
  @sh "J_PROJECT_DIR=\(.workspace.project_dir // .cwd // "")",
  @sh "J_USED=\(.context_window.used_percentage // -1)",
  @sh "J_H5_PCT=\(.rate_limits.five_hour.used_percentage // "null")",
  @sh "J_H5_RESET=\(.rate_limits.five_hour.resets_at // "null")",
  @sh "J_D7_PCT=\(.rate_limits.seven_day.used_percentage // "null")",
  @sh "J_D7_RESET=\(.rate_limits.seven_day.resets_at // "null")"
' 2>/dev/null)"

: "${J_MODEL:=?}" "${J_PROJECT_DIR:=$PWD}" "${J_USED:=-1}"
: "${J_H5_PCT:=null}" "${J_H5_RESET:=null}"
: "${J_D7_PCT:=null}" "${J_D7_RESET:=null}"

# ── Helpers ───────────────────────────────────
bar_color() {
    if [ "$1" -lt 50 ]; then _color='\033[32m'
    elif [ "$1" -lt 80 ]; then _color='\033[33m'
    else _color='\033[31m'
    fi
}

dim_pad() {
    local num="$1" w="$2"
    local padded; padded=$(printf "%0${w}d" "$num")
    local len=${#padded}
    local num_str="$num"
    local num_len=${#num_str}
    local pad_len=$(( len - num_len ))
    if [ "$pad_len" -gt 0 ]; then
        printf '\033[2;90m%s\033[0m%s' "${padded:0:$pad_len}" "$num_str"
    else
        printf '%s' "$padded"
    fi
}

draw_bar() {
    local pct=$1 w=$2
    local f=$(( pct * w / 100 ))
    [ "$f" -gt "$w" ] && f=$w
    local e=$(( w - f ))
    _bar=""
    local i
    for i in $(seq 1 $f); do _bar="${_bar}━"; done
    for i in $(seq 1 $e); do _bar="${_bar}─"; done
}

format_remaining() {
    local resets_at="$1"
    local now; now=$(date +%s)
    local diff=$(( resets_at - now ))
    [ "$diff" -le 0 ] && echo "now" && return
    local days=$(( diff / 86400 ))
    local hours=$(( (diff % 86400) / 3600 ))
    local mins=$(( (diff % 3600) / 60 ))
    if [ "$days" -gt 0 ]; then printf "%s%s%s" "$(dim_pad "$days" 2)" "d" "$(dim_pad "$hours" 2)h"
    elif [ "$hours" -gt 0 ]; then printf "%s%s%s" "$(dim_pad "$hours" 2)" "h" "$(dim_pad "$mins" 2)m"
    else printf "%s%s" "$(dim_pad "$mins" 2)" "m"
    fi
}

# render_ctx_seg <bar_width>   bar_width=0 → no bar, just percent
render_ctx_seg() {
    local bar_w=$1
    if [ "$(echo "$J_USED" | awk '{print ($1 >= 0) ? 1 : 0}')" = "1" ]; then
        local ctx_int; ctx_int=$(printf "%.0f" "$J_USED")
        bar_color "$ctx_int"; local color="$_color"
        local bar_part=""
        if [ "$bar_w" -gt 0 ]; then
            draw_bar "$ctx_int" "$bar_w"
            bar_part="${color}${_bar}\033[0m "
        fi
        local pct_str; pct_str=$(dim_pad "$ctx_int" 3)
        _ctx="CTX ${bar_part}${pct_str}%"
    else
        _ctx="CTX --"
    fi
}

# render_rate_seg <label> <pct_raw> <resets_raw> <bar_width> <show_countdown 0|1>
render_rate_seg() {
    local label="$1" pct_raw="$2" resets_raw="$3" bar_w="$4" show_cd="$5"
    if [ "$pct_raw" = "null" ] || [ -z "$pct_raw" ]; then
        _seg="${label} --"
        return
    fi
    local pct_int; pct_int=$(printf "%.0f" "$pct_raw")
    bar_color "$pct_int"; local color="$_color"
    local bar_part=""
    if [ "$bar_w" -gt 0 ]; then
        draw_bar "$pct_int" "$bar_w"
        bar_part="${color}${_bar}\033[0m "
    fi
    local pct_str; pct_str=$(dim_pad "$pct_int" 3)
    local countdown=""
    if [ "$show_cd" = "1" ] && [ "$resets_raw" != "null" ] && [ -n "$resets_raw" ]; then
        countdown=" ↻$(format_remaining "$resets_raw")"
    fi
    _seg="${label} ${bar_part}${pct_str}%${countdown}"
}

# ── Header (model | project | branch) ─────────
project_name=$(basename "$J_PROJECT_DIR")
git_branch=$(git -C "$J_PROJECT_DIR" branch --show-current 2>/dev/null)
branch_str=""
if [ -n "$git_branch" ]; then
    branch_str=" $git_branch"
    dirty=$(git -C "$J_PROJECT_DIR" status --porcelain 2>/dev/null)
    if [ -n "$dirty" ]; then
        dirty_count=$(echo "$dirty" | wc -l | tr -d ' ')
        branch_str="${branch_str} ✎${dirty_count}"
    fi
    upstream_counts=$(git -C "$J_PROJECT_DIR" rev-list --left-right --count @{upstream}...HEAD 2>/dev/null)
    if [ -n "$upstream_counts" ]; then
        behind=$(echo "$upstream_counts" | awk '{print $1}')
        ahead=$(echo "$upstream_counts" | awk '{print $2}')
        [ "$ahead" -gt 0 ] 2>/dev/null && branch_str="${branch_str} ↑${ahead}"
        [ "$behind" -gt 0 ] 2>/dev/null && branch_str="${branch_str} ↓${behind}"
    fi
fi
header="$J_MODEL │ $project_name │${branch_str}"

# ── Assemble output by layout ─────────────────
case "$LINES" in
    3)
        render_ctx_seg 30; ctx="$_ctx"
        render_rate_seg "5H" "$J_H5_PCT" "$J_H5_RESET" 10 1; seg5="$_seg"
        render_rate_seg "7D" "$J_D7_PCT" "$J_D7_RESET" 10 1; seg7="$_seg"
        printf "%b\n%b\n%b │ %b\n" "$header" "$ctx" "$seg5" "$seg7"
        ;;
    2)
        render_ctx_seg 15; ctx="$_ctx"
        render_rate_seg "5H" "$J_H5_PCT" "$J_H5_RESET" 8 0; seg5="$_seg"
        render_rate_seg "7D" "$J_D7_PCT" "$J_D7_RESET" 8 0; seg7="$_seg"
        printf "%b\n%b │ %b │ %b\n" "$header" "$ctx" "$seg5" "$seg7"
        ;;
    1)
        render_ctx_seg 5; ctx="$_ctx"
        render_rate_seg "5H" "$J_H5_PCT" "$J_H5_RESET" 5 0; seg5="$_seg"
        render_rate_seg "7D" "$J_D7_PCT" "$J_D7_RESET" 5 0; seg7="$_seg"
        printf "%b │ %b │ %b │ %b\n" "$header" "$ctx" "$seg5" "$seg7"
        ;;
esac
