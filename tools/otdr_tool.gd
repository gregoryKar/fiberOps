class_name OtdrTool
extends Tool
## Connects the OTDR to a fiber at a box: aim at a box, pick the fiber with the scroll wheel
## and click to measure. The port nearest the crosshair that has a cable is used.

## Target under the crosshair; node &"" and port -1 when there is none.
var node_id: StringName = &""
var port := -1
## Selected fiber (0-based) of the cable on that port.
var fiber := 0


func _physics_process(_delta: float) -> void:
	update_target()


func _unhandled_input(event: InputEvent) -> void:
	if not can_act():
		return
	if event.is_action_pressed(&"scroll_up"):
		select_fiber(fiber + 1)
	elif event.is_action_pressed(&"scroll_down"):
		select_fiber(fiber - 1)
	elif event.is_action_pressed(&"primary_action"):
		open_screen()
	else:
		return
	get_viewport().set_input_as_handled()


func update_target() -> void:
	var level := level_network()
	var ray := player.interaction_ray
	node_id = &""
	port = -1
	if level == null or not ray.is_colliding():
		return
	var item := level.item_for(ray.get_collider())
	if item["kind"] != LevelNetwork.ItemKind.NODE:
		return
	var hit := level.to_local(ray.get_collision_point())
	var best := INF
	var node := level.network.get_node_by_id(item["id"])
	for candidate in node.port_count:
		if level.network.cable_at(node.id, candidate) == null:
			continue
		var distance := level.port_position(node.id, candidate).distance_to(hit)
		if distance < best:
			best = distance
			port = candidate
	if port >= 0:
		node_id = node.id
		fiber = clampi(fiber, 0, _fiber_count() - 1)


func select_fiber(index: int) -> void:
	var count := _fiber_count()
	if count > 0:
		fiber = posmod(index, count)


## Opens the OTDR screen on the targeted fiber. Returns null if nothing is targeted.
func open_screen() -> OtdrScreen:
	if node_id == &"":
		return null
	return OtdrScreen.open(level_network(), node_id, port, fiber)


func get_hud_text() -> String:
	if node_id == &"":
		return "OTDR: aim at a box with a cable plugged in"
	return "OTDR  port %d  fiber %s (%d of %d)   [Scroll] fiber   [LMB] connect and measure" % [
		port + 1, SpliceTrayModel.fiber_label(port, fiber), fiber + 1, _fiber_count()]


func _fiber_count() -> int:
	var level := level_network()
	if level == null or node_id == &"":
		return 0
	var cable := level.network.cable_at(node_id, port)
	return cable.fiber_count if cable else 0
