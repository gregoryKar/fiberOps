class_name DeconstructTool
extends Tool
## Removes network hardware and cables: aim and hold LMB. Removing a box also removes the
## cables plugged into it; removing a cable cuts the splices on its ports.

const HOLD_TIME := 0.4
const HIGHLIGHT_COLOR := Color(1.0, 0.25, 0.15, 0.45)
const HIGHLIGHT_GROW := 0.004

## Item under the crosshair: kind (LevelNetwork.ItemKind) and id (&"" when none).
var target_kind := LevelNetwork.ItemKind.NONE
var target_id: StringName = &""
## 0..1 progress of the current hold.
var progress := 0.0

var _highlight: MeshInstance3D


func _on_activate() -> void:
	if _highlight == null:
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = HIGHLIGHT_COLOR
		material.grow = true
		material.grow_amount = HIGHLIGHT_GROW
		_highlight = MeshInstance3D.new()
		_highlight.name = "DeconstructHighlight"
		_highlight.top_level = true
		_highlight.material_override = material
		add_child(_highlight)
	_highlight.visible = false


func _on_deactivate() -> void:
	_set_target(LevelNetwork.ItemKind.NONE, &"")
	if _highlight:
		_highlight.visible = false


func _physics_process(delta: float) -> void:
	update_target()
	if target_id != &"" and can_act() and Input.is_action_pressed(&"primary_action"):
		progress += delta / HOLD_TIME
		if progress >= 1.0:
			remove_target()
	else:
		progress = 0.0


func update_target() -> void:
	var level := level_network()
	var ray := player.interaction_ray
	var item := {"kind": LevelNetwork.ItemKind.NONE, "id": &""}
	if level and ray.is_colliding():
		item = level.item_for(ray.get_collider())
	_set_target(item["kind"], item["id"])
	_update_highlight(level)


## Removes the targeted item right away. Returns false if nothing is targeted.
func remove_target() -> bool:
	var level := level_network()
	if level == null or target_id == &"":
		return false
	level.remove_item(target_kind, target_id)
	_set_target(LevelNetwork.ItemKind.NONE, &"")
	_update_highlight(level)
	return true


func get_hud_text() -> String:
	if target_id == &"":
		return "Aim at hardware or a cable to remove it"
	var text := "Hold [LMB] to remove %s" % _target_label()
	if progress > 0.0:
		text += "  %d%%" % int(progress * 100.0)
	return text


func _set_target(kind: LevelNetwork.ItemKind, id: StringName) -> void:
	if kind != target_kind or id != target_id:
		target_kind = kind
		target_id = id
		progress = 0.0


func _target_label() -> String:
	var level := level_network()
	if level == null:
		return String(target_id)
	if target_kind == LevelNetwork.ItemKind.CABLE:
		var cable: Cable = level.network.cables.get(target_id)
		if cable:
			return "cable (%s, %d fibers, %.2f m)" % [cable.spec().display_name, cable.fiber_count, cable.route().length_m]
	var node := level.network.get_node_by_id(target_id)
	var def: PlaceableDef = PlaceableDef.for_node_type(node.type) if node else null
	return def.display_name if def else String(target_id)


func _update_highlight(level: LevelNetwork) -> void:
	if _highlight == null:
		return
	var body: StaticBody3D = null
	if level and target_id != &"":
		body = level.body_for(target_id) if target_kind == LevelNetwork.ItemKind.NODE else level.cable_body_for(target_id)
	_highlight.visible = body != null
	if body:
		_highlight.mesh = (body.get_child(0) as MeshInstance3D).mesh
		_highlight.global_transform = body.global_transform
