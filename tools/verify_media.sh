#!/bin/sh
# Checks that every built-in FileDataID Gale Count uses (sounds in GaleCount.lua and Themes.lua, plus the
# textures listed below) exists in the WoW: Forever client build, by asking wago.tools for the file.
# Usage: tools/verify_media.sh [build]   (default 1.60.1.70862). Needs network; not part of the offline tests.
set -e
cd "$(dirname "$0")/.."
BUILD=${1:-1.60.1.70862}
# Textures (by FileDataID): spell_nature_cyclone, ui-statusbar, ui-chatim-sizegrabber-up, ui-tooltip-background, ui-tooltip-border
TEX="136018 137012 386864 137056 137057"
IDS=$( (grep -ohE 'sound = [0-9]+|= [0-9]{6,}, *--' Themes.lua GaleCount.lua | grep -oE '[0-9]{6,}'; echo $TEX | tr ' ' '\n') | sort -un)
fail=0; n=0
for id in $IDS; do
  n=$((n+1))
  type=$(curl -s -A 'Mozilla/5.0' -o /dev/null -w '%{content_type}' --max-time 30 "https://wago.tools/api/casc/$id?version=$BUILD")
  case "$type" in application/octet-stream*) echo "OK   $id" ;; *) echo "MISS $id ($type)"; fail=1 ;; esac
done
echo "$n files checked against $BUILD"
exit $fail
