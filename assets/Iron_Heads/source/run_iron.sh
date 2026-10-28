#!/bin/bash
# Build one iron variant headless, then render it: run_iron.sh <2u|blade|cb> [tag] [views...]
set -e
V=$1; TAG=${2:-$1}; shift; shift || true
HERE="/c/Users/willi/Documents/FreeCAD/GolfHead/irons"
FC="/c/Program Files/FreeCAD 1.1/bin/freecadcmd.exe"
BL="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
export IRON_VARIANT=$V
mkdir -p "$HERE/$V"
"$FC" -c "exec(open(r'C:/Users/willi/Documents/FreeCAD/GolfHead/irons/build_irons.py', encoding='utf-8').read())" > "$HERE/$V/build.log" 2>&1
tr '\r' '\n' < "$HERE/$V/build.log" | grep -a "VALID\|BBOX\|LEADING\|ROUNDED\|MASS\|rror\|Traceback\|line [0-9]" | tail -12
"$BL" -b --python "$HERE/render_iron.py" -- "$HERE/$V/stl" "$HERE/renders/$TAG" "$@" > "$HERE/renders/$TAG.log" 2>&1
grep -a "rendered\|rror" "$HERE/renders/$TAG.log" | tr '\n' ' '; echo
