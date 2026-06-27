#!/usr/bin/env bash
set -euo pipefail

# region/output screenshots for labwc using grim + slurp.
# The Sway "window" mode is intentionally dropped: it relied on sway IPC
# (swaymsg -t get_tree), which labwc does not provide.

if [[ $# -ne 1 ]]; then
    printf 'Usage: %s {region|output}\n' "${0##*/}" >&2
    exit 2
fi

mode="$1"
screenshots_dir="$HOME/Pictures/Screenshots"
file="$screenshots_dir/$(date +%Y-%m-%d_%H-%M-%S).png"

mkdir -p "$screenshots_dir"

case "$mode" in
    region)
        region="$(slurp)"
        [[ -n "$region" ]]
        grim -g "$region" "$file"
        ;;
    output)
        output="$(slurp -o -f "%o")"
        [[ -n "$output" ]]
        grim -o "$output" "$file"
        ;;
    *)
        printf 'Unknown mode: %s\n' "$mode" >&2
        exit 2
        ;;
esac

wl-copy --type image/png < "$file"

if command -v notify-send >/dev/null 2>&1; then
    notify-send \
        -i "$file" \
        "Screenshot saved" \
        "Copied to clipboard
Saved to: $file" || true
fi
