@tool
extends Node3D
## A fixed three-mesh flagpin. Wind is one vertex shader, not cloth physics.

const BREEZE = preload("res://assets/flagpin/flag_breeze.gdshader")

@export var animate_flag := true:
	set(value):
		animate_flag = value
		_apply_material()
@export_range(0.0, 0.10) var wind_strength := 0.025:
	set(value):
		wind_strength = value
		_apply_material()
@export_range(0.0, 3.0) var wind_speed := 0.75:
	set(value):
		wind_speed = value
		_apply_material()
@export var flag_color := Color("ed4223"):
	set(value):
		flag_color = value
		_apply_material()

var _cloth: Array[ShaderMaterial] = []

func _ready() -> void:
	_apply_material()

func _apply_material() -> void:
	if not is_inside_tree():
		return
	var flag := find_child("Flag", true, false) as MeshInstance3D
	if flag == null:
		return
	while _cloth.size() < flag.mesh.get_surface_count():
		var material := ShaderMaterial.new()
		material.shader = BREEZE
		_cloth.append(material)
	for index in range(_cloth.size()):
		var material := _cloth[index]
		# Primitive 0 is the cloth, primitive 1 is its darker sleeve/hem/stitching.
		var color := flag_color if index == 0 else Color(flag_color.r * 0.836, flag_color.g * 0.803, flag_color.b * 0.800, flag_color.a)
		material.set_shader_parameter("cloth_color", color)
		material.set_shader_parameter("wind_strength", wind_strength if animate_flag else 0.0)
		material.set_shader_parameter("wind_speed", wind_speed)
		flag.set_surface_override_material(index, material)
	flag.extra_cull_margin = 0.15
