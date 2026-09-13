# Plain green bushes

Three original, flower-free 3D assets: `rounded`, `spreading`, and `upright`.

- Drag a `green_bush_*.tscn` into a Godot scene. Its origin is at ground level.
- Use the matching `.glb` in Blender or another engine. Materials and vertex colors are embedded; no texture files are required.
- The `.res` files are shared meshes used by the course's MultiMesh batches.
- Godot scenes use 15,616 triangles below 14 m (individual leaves and branches), 5,248 at 14?35 m, and 576 at 35?100 m. The GLB contains the detailed model. Foliage is opaque, with no collisions or per-bush scripts.
- Godot scenes disappear beyond 100 m. Course planting batches each tier on an 8 m grid and disables their shadows.

`preview.png` shows all three under the same lighting. Rebuild assets with:

```powershell
& 'C:\Program Files\Godot\Godot.exe.exe' --headless --path . --script tools/make_green_bushes.gd
```

Render the preview with `tools/preview_green_bushes.gd` using the same command without `--headless`. The course uses these for approximately 72% of shrub selections; existing flowering plants remain as accents.
