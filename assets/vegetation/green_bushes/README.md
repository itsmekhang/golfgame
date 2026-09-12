# Plain green bushes

Three original, flower-free 3D assets: `rounded`, `spreading`, and `upright`.

- Drag a `green_bush_*.tscn` into a Godot scene. Its origin is at ground level.
- Use the matching `.glb` in Blender or another engine. Materials and vertex colors are embedded; no texture files are required.
- The `.res` files are shared meshes used by the course's MultiMesh batches.
- Each variant has 4,352 triangles, opaque foliage, and no collision or scripts. Approximate width/height: rounded 1.91/0.97 m, spreading 2.74/0.63 m, upright 1.43/1.47 m.
- Godot scenes disappear beyond 100 m. Course planting also batches them spatially and disables their shadows.

`preview.png` shows all three under the same lighting. Rebuild assets with:

```powershell
& 'C:\Program Files\Godot\Godot.exe.exe' --headless --path . --script tools/make_green_bushes.gd
```

Render the preview with `tools/preview_green_bushes.gd` using the same command without `--headless`. The course uses these for approximately 72% of shrub selections; existing flowering plants remain as accents.
