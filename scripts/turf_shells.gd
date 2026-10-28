class_name TurfShells
extends RefCounted
## Short living turf near the camera (shaders/turf_shell.gdshader): SHELLS slices chained as
## next_pass materials of a separate tile overlay, sharing the exact terrain mesh.
## Entire distant overlays are culled before any of their twelve passes are submitted.
## GOLF_TURF_SHELLS=0 turns them off.

const SHADER := preload("res://shaders/turf_shell.gdshader")
const SHELLS := 12
const MAX_H := 0.1
const MAX_DISTANCE := 26.0
const MATERIAL_META := &"turf_shell_material"
## Each building plot's paving mask gets a PAD_SLOT square slot in one texture (four slots, top
## to bottom), so the shells stop where the plot is paved.
const PAD_SLOT := 384


static func enabled() -> bool:
	return OS.get_environment("GOLF_TURF_SHELLS") != "0" and not PerformanceSettings.low()


## Store one shared shell chain for the hole, separate from its base terrain pass.
static func attach(terrain_mat: Material, layout: CourseLayout) -> void:
	if terrain_mat == null:
		return
	if terrain_mat.has_meta(MATERIAL_META):
		terrain_mat.remove_meta(MATERIAL_META)
	if not enabled():
		return
	if layout.sdf_texture == null or layout.mask_texture == null:
		return
	layout.ensure_straw()
	var pads := PackedVector4Array()
	var pad_rot := PackedFloat32Array()
	var list := layout.pads().slice(0, 4)
	for pad in list:
		var foot: Vector2 = pad.get("foot", pad["half"])
		pads.append(Vector4(pad["pos"].x, pad["pos"].y, foot.x, foot.y))
		pad_rot.append(float(pad["rot"]))
	var pad_mask := _pad_masks(list) if not list.is_empty() else null
	var prev: Material
	for i in range(SHELLS):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.render_priority = clampi(i - SHELLS / 2, -64, 64)  # bottom slice first
		m.set_shader_parameter("shell_t", (i + 1.0) / SHELLS)
		m.set_shader_parameter("max_h", MAX_H)
		m.set_shader_parameter("max_dist", MAX_DISTANCE)
		m.set_shader_parameter("turf_sdf", layout.sdf_texture)
		m.set_shader_parameter("sdf_origin", layout.bounds.position)
		m.set_shader_parameter("sdf_size", layout.sdf_texture_size())
		m.set_shader_parameter("feature_mask", layout.mask_texture)
		m.set_shader_parameter("mask_size", Vector2(layout.mask_image.get_width(), layout.mask_image.get_height()) * CourseLayout.MASK_CELL)
		m.set_shader_parameter("straw_mask", layout.straw_texture)
		m.set_shader_parameter("straw_size", layout.straw_texture_size())
		m.set_shader_parameter("sdf_range", CourseLayout.SDF_RANGE)
		m.set_shader_parameter("first_cut", CourseLayout.FIRST_CUT_WIDTH)
		m.set_shader_parameter("fringe", CourseLayout.FRINGE_WIDTH)
		if not pads.is_empty():
			m.set_shader_parameter("pad_count", pads.size())
			m.set_shader_parameter("pads", pads)
			m.set_shader_parameter("pad_rot", pad_rot)
			m.set_shader_parameter("pad_mask", pad_mask)
		if prev == null:
			terrain_mat.set_meta(MATERIAL_META, m)
		else:
			prev.next_pass = m
		prev = m


## The plots' paving masks, one PAD_SLOT slot each (a plot that isn't built on stays clear).
static func _pad_masks(list: Array) -> ImageTexture:
	var atlas := Image.create(PAD_SLOT, PAD_SLOT * 4, false, Image.FORMAT_L8)
	for i in range(list.size()):
		var mask: Image = (list[i] as Dictionary).get("mask")
		if mask == null:
			continue
		var m := mask.duplicate() as Image
		m.resize(PAD_SLOT, PAD_SLOT, Image.INTERPOLATE_NEAREST)
		atlas.blit_rect(m, Rect2i(0, 0, PAD_SLOT, PAD_SLOT), Vector2i(0, i * PAD_SLOT))
	return ImageTexture.create_from_image(atlas)


static func add_to_tile(tile: MeshInstance3D, terrain_mat: Material) -> void:
	if terrain_mat == null or not terrain_mat.has_meta(MATERIAL_META):
		return
	var overlay := MeshInstance3D.new()
	overlay.name = "TurfShells"
	overlay.mesh = tile.mesh
	overlay.material_override = terrain_mat.get_meta(MATERIAL_META)
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay.layers = PerformanceSettings.DETAIL_LAYER
	overlay.extra_cull_margin = MAX_H
	# Visibility ranges measure from the AABB centre. Include the full tile radius
	# so shells near an edge never disappear while the camera is still beside them.
	overlay.visibility_range_end = tile.mesh.get_aabb().size.length() * 0.5 + MAX_DISTANCE + MAX_H + 6.0
	overlay.visibility_range_end_margin = 2.0
	overlay.add_to_group("turf_shells")
	tile.add_child(overlay)
