#!/bin/bash
input=$(cat)
LINES="${1:-3}"

eval "$(echo "$input" | jq -r '
  @sh "J_MODEL=\(.model.display_name // "?")",
  @sh "J_PROJECT_DIR=\(.workspace.project_dir // .cwd // "")",
  @sh "J_USED=\(.context_window.used_percentage // -1)",
  @sh "J_H5_PCT=\(.rate_limits.five_hour.used_percentage // "null")",
  @sh "J_H5_RESET=\(.rate_limits.five_hour.resets_at // "null")",
  @sh "J_D7_PCT=\(.rate_limits.seven_day.used_percentage // "null")",
  @sh "J_D7_RESET=\(.rate_limits.seven_day.resets_at // "null")"
' 2>/dev/null)"

# Fallbacks if the jq parse failed entirely.
: "${J_MODEL:=?}" "${J_PROJECT_DIR:=$PWD}" "${J_USED:=-1}"
: "${J_H5_PCT:=null}" "${J_H5_RESET:=null}"
: "${J_D7_PCT:=null}" "${J_D7_RESET:=null}"

now=$(date +%s)

# Hot-path helpers set globals (_color/_bar/_pad/_rem/_seg) instead of echoing,
# to keep this script fork-light — it runs on every Claude Code render.

bar_color() {
    if [ "$1" -lt 50 ]; then _color='\033[32m'
    elif [ "$1" -lt 80 ]; then _color='\033[33m'
    else _color='\033[31m'
    fi
}

dim_pad() {
    local num="$1" w="$2" padded
    printf -v padded "%0${w}d" "$num"
    local pad_len=$(( ${#padded} - ${#num} ))
    if [ "$pad_len" -gt 0 ]; then
        printf -v _pad '\033[2;90m%s\033[0m%s' "${padded:0:$pad_len}" "$num"
    else
        _pad="$padded"
    fi
}

draw_bar() {
    local pct=$1 w=$2 fill empty
    local f=$(( pct * w / 100 ))
    [ "$f" -gt "$w" ] && f=$w
    local e=$(( w - f ))
    printf -v fill "%${f}s" ""; fill="${fill// /━}"
    printf -v empty "%${e}s" ""; empty="${empty// /─}"
    _bar="${fill}${empty}"
}

format_remaining() {
    local diff=$(( $1 - now ))
    if [ "$diff" -le 0 ]; then _rem="now"; return; fi
    local days=$(( diff / 86400 ))
    local hours=$(( (diff % 86400) / 3600 ))
    local mins=$(( (diff % 3600) / 60 ))
    if [ "$days" -gt 0 ]; then
        dim_pad "$days" 2; local d="$_pad"
        dim_pad "$hours" 2; _rem="${d}d${_pad}h"
    elif [ "$hours" -gt 0 ]; then
        dim_pad "$hours" 2; local h="$_pad"
        dim_pad "$mins" 2; _rem="${h}h${_pad}m"
    else
        dim_pad "$mins" 2; _rem="${_pad}m"
    fi
}

# render_seg <label> <pct_raw> <resets_raw_or_empty> <bar_w>
# pct_raw of "null"/""/negative → "<label> --". resets="" suppresses the countdown.
render_seg() {
    local label="$1" pct_raw="$2" resets="$3" bar_w="$4"
    case "$pct_raw" in null|""|-*) _seg="${label} --"; return ;; esac
    local i; printf -v i "%.0f" "$pct_raw"
    bar_color "$i"
    local bar_part=""
    if [ "$bar_w" -gt 0 ]; then
        draw_bar "$i" "$bar_w"
        bar_part="${_color}${_bar}\033[0m "
    fi
    dim_pad "$i" 3
    local pct_str="$_pad" cd=""
    if [ -n "$resets" ] && [ "$resets" != "null" ]; then
        format_remaining "$resets"
        cd=" ↻$_rem"
    fi
    _seg="${label} ${bar_part}${pct_str}%${cd}"
}

# Header — single `git status` reads branch + dirty + ahead/behind.
project_name=$(basename "$J_PROJECT_DIR")
status_out=$(git -C "$J_PROJECT_DIR" status --porcelain=v2 --branch 2>/dev/null)
branch_str=""
if [ -n "$status_out" ]; then
    git_branch=""; ahead=0; behind=0; dirty_count=0
    while IFS= read -r line; do
        case "$line" in
            "# branch.head "*) git_branch="${line#\# branch.head }" ;;
            "# branch.ab "*)
                ab="${line#\# branch.ab }"
                a="${ab%% *}"; ahead="${a#+}"
                b="${ab##* }"; behind="${b#-}"
                ;;
            "#"*|"") ;;
            *) dirty_count=$(( dirty_count + 1 )) ;;
        esac
    done <<< "$status_out"
    if [ -n "$git_branch" ] && [ "$git_branch" != "(detached)" ]; then
        branch_str=" $git_branch"
        [ "$dirty_count" -gt 0 ] && branch_str="${branch_str} ✎${dirty_count}"
        [ "$ahead" -gt 0 ] && branch_str="${branch_str} ↑${ahead}"
        [ "$behind" -gt 0 ] && branch_str="${branch_str} ↓${behind}"
    fi
fi
header="$J_MODEL │ $project_name │${branch_str}"

# Layout dispatch — bar widths and printf format per layout.
case "$LINES" in
    1) ctx_w=5;  rate_w=5;  fmt='%b │ %b │ %b │ %b\n' ;;
    2) ctx_w=15; rate_w=8;  fmt='%b\n%b │ %b │ %b\n' ;;
    *) ctx_w=30; rate_w=10; fmt='%b\n%b\n%b │ %b\n' ;;
esac

render_seg "CTX" "$J_USED" "" "$ctx_w"; ctx="$_seg"
render_seg "5H" "$J_H5_PCT" "$J_H5_RESET" "$rate_w"; seg5="$_seg"
render_seg "7D" "$J_D7_PCT" "$J_D7_RESET" "$rate_w"; seg7="$_seg"
printf "$fmt" "$header" "$ctx" "$seg5" "$seg7"
