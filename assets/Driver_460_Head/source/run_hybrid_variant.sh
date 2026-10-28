#!/usr/bin/env bash
# Headless Driver460 hybrid-joint pipeline: head -> insert fit -> finish -> Blender renders.
set -e
D="C:/Users/willi/Documents/FreeCAD/GolfHead/driver"
H="${DRIVER_OUT:-$D/hybrid}"
FC="/c/Program Files/FreeCAD 1.1/bin/freecadcmd.exe"
BLENDER="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
PP="C:/Users/willi/AppData/Local/Packages/PythonSoftwareFoundation.Python.3.11_qbz5n2kfra8p0/LocalCache/local-packages/Python311/site-packages"
FIT="${FIT:-C:/Users/willi/AppData/Local/Temp/claude/C--Users-willi-Documents-GolfGame--claude-worktrees-mystifying-cannon-9ca916/4f8110dd-d346-484e-8db9-f8e4b0f017a6/scratchpad/driver/fit_insert.py}"
TAG="${TAG:-run}"
rm -f "$H/head_report.json" "$H/finish_report.json"
echo "[$(date +%H:%M:%S)] head"
STAGE=head "$FC" -c "exec(open(r'$D/build_hybrid_driver.py').read())" 2>&1 | grep -E '^\{|Error|Traceback' || true
test -f "$H/head_report.json"
echo "[$(date +%H:%M:%S)] fit"
PYTHONPATH="$PP" python "$FIT" "$H/face_edge.json" "$H/insert.json" 2.5 3.5 2.8 2>&1 | tail -1
echo "[$(date +%H:%M:%S)] finish"
STAGE=finish "$FC" -c "exec(open(r'$D/build_hybrid_driver.py').read())" 2>&1 | grep -E '^\{|Error|Traceback' || true
test -f "$H/finish_report.json"
echo "[$(date +%H:%M:%S)] render"
"$BLENDER" -b --python "$D/render_driver.py" -- "$H/stl" "$H/renders_$TAG" ${VIEWS:-face front34 hosel_close heel34 top toe_close heel_under_close sole} 2>&1 | grep -E '^rendered|Error' || true
echo "[$(date +%H:%M:%S)] done"
