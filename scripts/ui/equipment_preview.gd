class_name EquipmentPreview
extends RefCounted
## Static club-icon art for the Clubhouse and HUD. Shop renders are generated from
## the equipped head and its materials by tools/render_shop_thumbnails.gd, with
## transparent backgrounds and cast shadows. Irons show mostly their backs plus
## the top line; wedges show their grooved faces and tops. Putters show their top
## and rear. Missing art falls back to ClubSilhouette.

const BASE := "res://assets/openfairway_equipment/previews/"
const SELECTED_HEAD_PREVIEWS := "res://assets/Selected_Club_Heads/previews/"
const IRON_SHOP_PREVIEWS := "res://assets/Selected_Iron_Heads/shop_thumbnails/512/"
const WEDGE_SHOP_PREVIEWS := "res://assets/Selected_Wedge_Heads/shop_thumbnails/512/"
const SUFFIXES := ["", "_back", "_full"]
const UNCOLLECTED_SHADER := preload("res://shaders/equipment_uncollected.gdshader")

static var _cache: Dictionary = {}  # model_id -> Texture2D, or "missing"
static var _uncollected_material: ShaderMaterial


## Used only by the interactive 3D inspect viewer to pick its default starting angle
## (irons/wedges open rear three-quarter so the cavity/sole reads) -- unrelated to the
## flat icon get_texture() returns, which uses each family's shop presentation.
static func prefers_back_view(model_id: String) -> bool:
	var model := ClubCatalog.model(model_id)
	return str(model.get("type", "")) in ["iron_set", "wedge"] or str(model.get("silhouette", "")) == "hybrid_iron"


static func get_uncollected_material() -> ShaderMaterial:
	if _uncollected_material == null:
		_uncollected_material = ShaderMaterial.new()
		_uncollected_material.shader = UNCOLLECTED_SHADER
	return _uncollected_material


static func get_texture(model_id: String) -> Texture2D:
	if model_id.is_empty():
		return null
	if _cache.has(model_id):
		var cached = _cache[model_id]
		return cached if cached is Texture2D else null
	var model := ClubCatalog.model(model_id)
	if str(model.get("type", "")) == "iron_set":
		var iron_path := "%sofg_%s_base_back.png" % [IRON_SHOP_PREVIEWS, model_id]
		if ResourceLoader.exists(iron_path):
			var iron_preview := load(iron_path) as Texture2D
			_cache[model_id] = iron_preview
			return iron_preview
	if str(model.get("type", "")) == "wedge":
		var wedge_path := "%sofg_%s_base_back.png" % [WEDGE_SHOP_PREVIEWS, model_id]
		if ResourceLoader.exists(wedge_path):
			var wedge_preview := load(wedge_path) as Texture2D
			_cache[model_id] = wedge_preview
			return wedge_preview
	var selected_path := "%sofg_%s.png" % [SELECTED_HEAD_PREVIEWS, model_id]
	if ResourceLoader.exists(selected_path):
		var selected := load(selected_path) as Texture2D
		_cache[model_id] = selected
		return selected
	for suffix in SUFFIXES:
		var path := "%sofg_%s%s.png" % [BASE, model_id, suffix]
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			_cache[model_id] = tex
			return tex
	_cache[model_id] = "missing"
	return null
