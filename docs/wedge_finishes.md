# Wedge finishes

The four loaner wedges share one satin silver finish. Collectibles are separated
by both color and roughness, without logos, badges, text or decorative graphics:

| Wedge | Finish |
| --- | --- |
| Loaner PW / GW / SW / LW | Matching satin silver |
| Grocery Store PW | Matte charcoal |
| Bent Neck PW | Blue steel |
| Rusty Gap 52 | Pitted reddish-brown oxidation with exposed raw steel |
| Flop Master 60 | Black oxide |
| Raw Face 56 | Bright polished silver |
| Tour Grind 58 | Polished yellow gold |
| Sand Shovel SW | Dark bronze |

`assets/OpenFairway_Equipment_v1/source/wedge_finishes.py` owns the plain finish
palette. `build_textures.py` routes all wedges through it. Rusty Gap copies its
four baked maps instead of falling back to a uniform brown atlas.

## Rust authoring

The generated source tile and exact built-in image-generation prompt are saved
under `assets/OpenFairway_Equipment_v1/source/materials/rusty_gap_52/`:

- `rusted_steel_source.png`: evenly lit raw steel and fine oxidation.
- `prompt.txt`: generation prompt and tool provenance.
- `mapping_reference.glb`: fitted club before retexturing, preserving the old
  face region used to locate functional grooves and contact abrasion.
- `baked/`: reusable 1024px albedo, ORM, tangent normal and condition maps.

Run `blender --background --python tools/bake_rusty_wedge.py` from the project.
It stages a GLB under `build/wedge-distinct/models/`. It unwraps the whole head,
including the neck, projects the source tile at a 7 cm scale, and bakes correlated
roughness, metallic, pitting and condition masks. Rust exists at mint condition;
lower condition gently darkens the same corrosion regions.

Only head UVs and tangent data change. Triangle positions, smooth normals,
transforms, shafts and grips are copied unchanged. Geometry equality and nonzero
UV triangle area are checked during baking. The runtime retains the existing
equipment shader and its four map samples; no runtime procedural texture work
or additional draw calls are added.

Install the staged Rusty Gap GLB into both equipment model directories, then
run `build_textures.py` for the affected wedge IDs, copy its generated maps from
the source pack into `assets/openfairway_equipment/textures/`, and use
`tools/update_club_texture_images.py` to refresh other clubs' embedded images.
Rusty's fitted UVs and maps must be installed together; its atlas does not fit
the older procedural wedge template. Refresh the mapping reference if replacing
the physical head model before baking again.

Generate `_back.png` previews with `source/render_models.py::render`, explicitly
passing the runtime GLB as `model_path`. The runtime preview helper uses these
same images for the HUD, cabinet, bag and shop. Reimport in Godot and check the
actual inspector before exporting the Windows EXE and PCK.
