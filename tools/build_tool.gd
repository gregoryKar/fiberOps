class_name BuildTool
extends Tool
## Places network hardware with a Satisfactory-style ghost that follows the crosshair.
##   LMB place   Scroll choose item   R rotate 90°   G toggle 5 cm grid snap
##
## A placement is valid when the box sits on a mountable wall, the wall backs all four
## corners (no overhang into door openings), and nothing else occupies the space.

const GRID := 0.05
## Gap kept between the box and the wall so the overlap test doesn't hit the wall itself.
const WALL_GAP := 0.001
## Walls only: the surface normal must be this close to horizontal.
const MAX_WALL_NORMAL_Y := 0.3
const OVERLAP_SHRINK := 0.98
const BLOCKING_MASK := 1 | 4 | 8  ## world, network_nodes, cables
const VALID_COLOR := Color(0.2, 0.9, 0.35, 0.45)
const INVALID_COLOR := Color(1.0, 0.2, 0.15, 0.45)

## Result of evaluating where the current item would go.
class Placement:
	var valid := false
	var reason := ""
	var transform := Transform3D.IDENTITY
	var has_surface := false


var selected := 0
var rotation_steps := 0
var snap_enabled := true
var placement := Placement.new()

var _ghost: MeshInstance3D
var _ghost_material: StandardMaterial3D


func current_def() -> PlaceableDef:
	return PlaceableDef.all()[selected]


func _on_activate() -> void:
	if _ghost == null:
		_ghost_material = StandardMaterial3D.new()
		_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ghost = MeshInstance3D.new()
		_ghost.name = "BuildGhost"
		_ghost.top_level = true
		_ghost.material_override = _ghost_material
		add_child(_ghost)
		_refresh_ghost_mesh()
	_ghost.visible = false


func _on_deactivate() -> void:
	if _ghost:
		_ghost.visible = false


func _physics_process(_delta: float) -> void:
	update_placement()


func _unhandled_input(event: InputEvent) -> void:
	if not can_act():
		return
	if event.is_action_pressed(&"scroll_up"):
		select_item(selected - 1)
	elif event.is_action_pressed(&"scroll_down"):
		select_item(selected + 1)
	elif event.is_action_pressed(&"rotate"):
		rotation_steps = (rotation_steps + 1) % 4
	elif event.is_action_pressed(&"toggle_snap"):
		snap_enabled = not snap_enabled
	elif event.is_action_pressed(&"primary_action"):
		try_place()
	else:
		return
	get_viewport().set_input_as_handled()


func select_item(index: int) -> void:
	selected = posmod(index, PlaceableDef.all().size())
	_refresh_ghost_mesh()


## Re-evaluates the placement from the player's interaction ray and moves the ghost.
func update_placement() -> void:
	var ray := player.interaction_ray
	if ray.is_colliding():
		placement = evaluate(ray.get_collision_point(), ray.get_collision_normal(), ray.get_collider())
	else:
		placement = Placement.new()
		placement.reason = "Aim at a wall"
	if _ghost:
		_ghost.visible = placement.has_surface
		_ghost.global_transform = placement.transform
		_ghost_material.albedo_color = VALID_COLOR if placement.valid else INVALID_COLOR


## Places the current item if the placement is valid. Returns the new network node or null.
func try_place() -> NetNode:
	var level := level_network()
	if level == null or not placement.valid:
		return null
	var node := level.place(current_def(), placement.transform)
	update_placement()
	return node


func evaluate(point: Vector3, normal: Vector3, collider: Object) -> Placement:
	var result := Placement.new()
	var def := current_def()
	if absf(normal.y) > MAX_WALL_NORMAL_Y:
		result.reason = "%s mounts on walls" % def.display_name
		return result
	var basis := wall_basis(normal, rotation_steps)
	var anchor := snap_to_grid(point, normal) if snap_enabled else point
	result.transform = Transform3D(basis, anchor + basis.z * (def.size.z * 0.5 + WALL_GAP))
	result.has_surface = true

	if not _is_mountable(collider):
		result.reason = "Can't mount on this surface"
		return result
	if not _wall_behind_corners(result.transform, def.size):
		result.reason = "Needs flat wall behind the whole box"
		return result
	if _is_blocked(result.transform, def.size):
		result.reason = "Something is in the way"
		return result
	result.valid = true
	return result


func get_hud_text() -> String:
	var text := "%s   [Scroll] item  [R] rotate  [G] snap %s" % [
		current_def().display_name, "on" if snap_enabled else "off"]
	if placement.has_surface and not placement.valid:
		text += "\n" + placement.reason
	return text


## Basis for a wall-mounted box: local z out of the wall, local y as close to world up as
## possible, then rotated about the wall normal in 90° steps.
static func wall_basis(normal: Vector3, steps: int) -> Basis:
	var z := normal.normalized()
	var x := Vector3.UP.cross(z).normalized()
	var y := z.cross(x)
	return Basis(z, steps * PI * 0.5) * Basis(x, y, z)


## Snaps a point on a wall to the grid without pulling it off the wall plane.
static func snap_to_grid(point: Vector3, normal: Vector3) -> Vector3:
	var on_grid := point.snapped(Vector3.ONE * GRID)
	return on_grid - normal * (on_grid - point).dot(normal)


func _is_mountable(collider: Object) -> bool:
	return collider is Node and (collider as Node).is_in_group(&"mountable_wall")


func _wall_behind_corners(xform: Transform3D, size: Vector3) -> bool:
	var space := player.get_world_3d().direct_space_state
	var back := -size.z * 0.5
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var local := Vector3(corner.x * size.x * 0.5, corner.y * size.y * 0.5, back)
		var start := xform * local + xform.basis.z * 0.01
		var query := PhysicsRayQueryParameters3D.create(start, start - xform.basis.z * 0.03, 1)
		var hit := space.intersect_ray(query)
		if hit.is_empty() or not _is_mountable(hit["collider"]):
			return false
	return true


func _is_blocked(xform: Transform3D, size: Vector3) -> bool:
	var shape := BoxShape3D.new()
	shape.size = size * OVERLAP_SHRINK
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = xform
	query.collision_mask = BLOCKING_MASK
	return not player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _refresh_ghost_mesh() -> void:
	if _ghost:
		var mesh := BoxMesh.new()
		mesh.size = current_def().size
		_ghost.mesh = mesh
