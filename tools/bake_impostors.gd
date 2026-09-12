extends SceneTree
## Bakes billboard impostor atlases for the nature pack's trees and shrubs: each
## species is rendered from VIEWS azimuths (slightly above eye level) into one
## horizontal strip PNG, plus a JSON with the card size. Needs a display.
## Run: godot --path . --script tools/bake_impostors.gd

const VIEWS := 8
const TILE_W := 512
const TILE_H := 768
const ELEVATION_DEG := 8.0
const OUT_DIR := "res://assets/nature_pack/impostors/"
const SPECIES := [
	"loblolly_pine_B", "loblolly_pine_C", "longleaf_pine_B", "eastern_white_pine_B",
	"white_oak_B", "red_maple_B", "sweetgum_B", "tulip_poplar_B", "southern_magnolia_B", "live_oak_B",
	"eastern_red_cedar_B", "river_birch_B", "flowering_dogwood_white_B", "flowering_dogwood_pink_B",
	"crape_myrtle_B", "bald_cypress_B", "weeping_willow_B",
	"azalea_pink_B", "azalea_white_B", "azalea_red_A", "rhododendron_A",
]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var vp := SubViewport.new()
	vp.size = Vector2i(TILE_W, TILE_H)
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = false
	world.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.8, 0.85)
	e.ambient_light_energy = 0.9
	env.environment = e
	world.add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(cam)
	var mi := MeshInstance3D.new()
	world.add_child(mi)
	var meta := {}
	for id in SPECIES:
		# bake from the full-detail base mesh: the LOD1 crowns are visibly thinner
		var mesh := NaturePack.base_mesh_for_bake(id)
		if mesh == null:
			continue
		mi.mesh = mesh
		for k in range(3):
			await process_frame  # let the (huge) mesh upload before the first capture
		var aabb := mesh.get_aabb()
		var w := maxf(aabb.size.x, aabb.size.z) * 1.05
		var h := aabb.size.y * 1.03
		var extent := maxf(w, h * float(TILE_W) / float(TILE_H))
		var center := Vector3(aabb.position.x + aabb.size.x * 0.5, 0.0, aabb.position.z + aabb.size.z * 0.5)
		mi.position = -center
		cam.size = extent * float(TILE_H) / float(TILE_W)
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		var strip := Image.create(TILE_W * VIEWS, TILE_H, false, Image.FORMAT_RGBA8)
		for v in range(VIEWS):
			var yaw := TAU * v / VIEWS
			var dir := Vector3(cos(yaw), 0.0, sin(yaw))
			var elev := deg_to_rad(ELEVATION_DEG)
			var pos := dir * 200.0 * cos(elev) + Vector3(0.0, h * 0.5 + 200.0 * sin(elev), 0.0)
			cam.position = pos
			cam.look_at(Vector3(0.0, h * 0.5, 0.0), Vector3.UP)
			cam.near = 1.0
			cam.far = 500.0
			for k in range(3):
				await process_frame
			var img := vp.get_texture().get_image()
			strip.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(TILE_W * v, 0))
		var out := ProjectSettings.globalize_path(OUT_DIR + id + ".png")
		strip.save_png(out)
		meta[id] = {"width_m": extent, "height_m": extent * float(TILE_H) / float(TILE_W), "views": VIEWS}
		print("baked ", id, "  card %.1f x %.1f m" % [meta[id]["width_m"], meta[id]["height_m"]])
	var f := FileAccess.open(OUT_DIR + "impostors.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "  "))
	f.close()
	print("done: ", meta.size(), " impostors")
	quit(0)
