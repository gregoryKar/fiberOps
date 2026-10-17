@tool
class_name GreyboxFloor
extends Node3D
## Builds a greybox building floor (slab, ceiling, walls with door gaps, lights) from layout data.
## Every surface is a StaticBody3D on the "world" physics layer, tagged with its surface material
## in the "surface_material" meta. Build tools read it for wall-mount checks and the drilling
## minigame reads it for drill speed.

const DOOR_WIDTH := 0.9
const DOOR_HEIGHT := 2.1
const SURFACE_META := &"surface_material"
const MOUNTABLE_SURFACES: Array[StringName] = [&"concrete", &"brick", &"drywall"]
const SURFACE_COLORS: Dictionary[StringName, Color] = {
	&"concrete": Color(0.55, 0.55, 0.56),
	&"brick": Color(0.62, 0.38, 0.32),
	&"drywall": Color(0.9, 0.89, 0.84),
	&"floor": Color(0.36, 0.36, 0.38),
	&"ceiling": Color(0.82, 0.82, 0.8),
}

## Walls in floor-plan coordinates (Vector2 = world x, z). Walls must be axis aligned.
## "doors" holds door centre positions as distances from "a" along the wall.
const LAYOUT: Array[Dictionary] = [
	# Outer shell.
	{"a": Vector2(-10, 6), "b": Vector2(10, 6), "surface": &"concrete", "doors": []},
	{"a": Vector2(-10, -6), "b": Vector2(10, -6), "surface": &"concrete", "doors": []},
	{"a": Vector2(-10, -6), "b": Vector2(-10, 6), "surface": &"concrete", "doors": []},
	{"a": Vector2(10, -6), "b": Vector2(10, 6), "surface": &"concrete", "doors": []},
	# Corridor walls, one apartment door each side of the divider.
	{"a": Vector2(-10, 1), "b": Vector2(10, 1), "surface": &"brick", "doors": [5.0, 15.0]},
	{"a": Vector2(-10, -1), "b": Vector2(10, -1), "surface": &"brick", "doors": [5.0, 15.0]},
	# Apartment dividers.
	{"a": Vector2(0, 1), "b": Vector2(0, 6), "surface": &"brick", "doors": []},
	{"a": Vector2(0, -6), "b": Vector2(0, -1), "surface": &"brick", "doors": []},
	# Interior partitions.
	{"a": Vector2(-7, 1), "b": Vector2(-7, 6), "surface": &"drywall", "doors": [2.5]},
	{"a": Vector2(7, -6), "b": Vector2(7, -1), "surface": &"drywall", "doors": [2.5]},
]

## Ceiling light positions in floor-plan coordinates.
const LIGHTS: Array[Vector2] = [
	Vector2(-6, 0), Vector2(0, 0), Vector2(6, 0),
	Vector2(-8.5, 3.5), Vector2(-3.5, 3.5), Vector2(5, 3.5),
	Vector2(-5, -3.5), Vector2(3.5, -3.5), Vector2(8.5, -3.5),
]

@export var size := Vector2(20.0, 12.0)
@export var wall_height := 3.0
@export var wall_thickness := 0.2
@export var slab_thickness := 0.25
@export var build_ceiling := true
@export_tool_button("Rebuild") var rebuild_action := rebuild

var _materials: Dictionary[StringName, StandardMaterial3D] = {}


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	var old := get_node_or_null("Generated")
	if old:
		remove_child(old)
		old.queue_free()

	var root := Node3D.new()
	root.name = "Generated"
	add_child(root)

	var slab_size := Vector3(size.x + wall_thickness, slab_thickness, size.y + wall_thickness)
	_add_box(root, "Floor", Vector3(0, -slab_thickness * 0.5, 0), slab_size, &"floor")
	if build_ceiling:
		_add_box(root, "Ceiling", Vector3(0, wall_height + slab_thickness * 0.5, 0), slab_size, &"ceiling")

	for i in LAYOUT.size():
		_add_wall(root, i, LAYOUT[i])

	for i in LIGHTS.size():
		var light := OmniLight3D.new()
		light.name = "Light%d" % i
		light.position = Vector3(LIGHTS[i].x, wall_height - 0.3, LIGHTS[i].y)
		light.omni_range = 7.0
		light.light_energy = 1.2
		light.shadow_enabled = true
		light.add_to_group(&"floor_lights")
		root.add_child(light)


func _add_wall(parent: Node3D, index: int, wall: Dictionary) -> void:
	var a: Vector2 = wall["a"]
	var b: Vector2 = wall["b"]
	assert(is_equal_approx(a.x, b.x) or is_equal_approx(a.y, b.y), "Greybox walls must be axis aligned")
	var surface: StringName = wall["surface"]
	var length := a.distance_to(b)
	var doors: Array = wall["doors"].duplicate()
	doors.sort()

	var cursor := 0.0
	var part := 0
	for door: float in doors:
		var gap_start := door - DOOR_WIDTH * 0.5
		var gap_end := door + DOOR_WIDTH * 0.5
		_add_wall_part(parent, "Wall%d_%d" % [index, part], a, b, cursor, gap_start, 0.0, wall_height, surface)
		_add_wall_part(parent, "Wall%d_%d" % [index, part + 1], a, b, gap_start, gap_end, DOOR_HEIGHT, wall_height, surface)
		part += 2
		cursor = gap_end
	_add_wall_part(parent, "Wall%d_%d" % [index, part], a, b, cursor, length, 0.0, wall_height, surface)


## Adds the wall piece between distances t0..t1 along a→b and heights y0..y1.
func _add_wall_part(parent: Node3D, part_name: String, a: Vector2, b: Vector2,
		t0: float, t1: float, y0: float, y1: float, surface: StringName) -> void:
	if t1 - t0 <= 0.001:
		return
	var dir := (b - a).normalized()
	var mid := a + dir * (t0 + t1) * 0.5
	var along_x := is_equal_approx(a.y, b.y)
	var box_size := Vector3(t1 - t0, y1 - y0, wall_thickness) if along_x \
			else Vector3(wall_thickness, y1 - y0, t1 - t0)
	_add_box(parent, part_name, Vector3(mid.x, (y0 + y1) * 0.5, mid.y), box_size, surface)


func _add_box(parent: Node3D, box_name: String, center: Vector3, box_size: Vector3, surface: StringName) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta(SURFACE_META, surface)
	body.add_to_group(&"cable_surface")
	if surface in MOUNTABLE_SURFACES:
		body.add_to_group(&"mountable_wall")

	var mesh := BoxMesh.new()
	mesh.size = box_size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material_for(surface)
	body.add_child(mesh_instance)

	var shape := BoxShape3D.new()
	shape.size = box_size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)

	parent.add_child(body)
	return body


func _material_for(surface: StringName) -> StandardMaterial3D:
	if not _materials.has(surface):
		var material := StandardMaterial3D.new()
		material.albedo_color = SURFACE_COLORS.get(surface, Color.MAGENTA)
		material.roughness = 0.9
		_materials[surface] = material
	return _materials[surface]
