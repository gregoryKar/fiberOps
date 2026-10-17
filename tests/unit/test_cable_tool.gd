extends TestCase
## M4: routing cables between boxes in the test floor.

const CABLE_SLOT := 2
const DECONSTRUCT_SLOT := 3

var _level: Node3D
var _player: Player
var _network: LevelNetwork
var _tool: CableTool
var _box_a: NetNode
var _box_b: NetNode


func before_each() -> void:
	GameState.set_mode(GameState.Mode.GAMEPLAY)
	_level = load("res://levels/test_floor/test_floor.tscn").instantiate()
	tree.root.add_child(_level)
	_player = _level.get_node("Player")
	_network = _level.get_node("LevelNetwork")
	_tool = _player.tool_belt.tool_node(&"cable")
	# Two floorboxes on the north corridor wall, 3 m apart.
	var def := PlaceableDef.for_node_type(NetNode.Type.FLOORBOX)
	var basis := BuildTool.wall_basis(Vector3(0, 0, -1), 0)
	_box_a = _network.place(def, Transform3D(basis, Vector3(-6.0, 1.6, 0.859)))
	_box_b = _network.place(def, Transform3D(basis, Vector3(-3.0, 1.6, 0.859)))
	_player.tool_belt.select_slot(CABLE_SLOT)
	await _frames(10)


func after_each() -> void:
	_level.free()


func _frames(count: int) -> void:
	for i in count:
		await tree.physics_frame


## Puts the player at (x, z) looking exactly at `target`, then lets the ray update.
func _aim(x: float, z: float, target: Vector3) -> void:
	_player.global_position = Vector3(x, 0, z)
	var d := target - Vector3(x, _player.head.position.y, z)
	_player.rotation = Vector3(0, atan2(-d.x, -d.z), 0)
	_player.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())
	await _frames(3)


## Routes box A → one waypoint on the wall → box B, returning the new cable.
func _route_a_to_b() -> Cable:
	await _aim(-4.5, -0.4, Vector3(-6.0, 1.5, 0.82))
	_tool.click()
	await _aim(-4.5, -0.4, Vector3(-4.5, 1.2, 0.9))
	_tool.click()
	await _aim(-4.5, -0.4, Vector3(-3.0, 1.5, 0.82))
	return _tool.click()


func test_port_layout() -> void:
	var box := PlaceableDef.for_node_type(NetNode.Type.FLOORBOX)
	assert_eq(box.port_exit_direction(0), Vector3.DOWN, "first half exits down")
	assert_eq(box.port_exit_direction(5), Vector3.UP, "second half exits up")
	assert_almost(box.port_local_position(1).x, 0.0, 1e-6, "middle bottom port centred")
	assert_almost(box.port_local_position(4).y, box.size.y * 0.5, 1e-6, "top port on the top edge")
	var outlet := PlaceableDef.for_node_type(NetNode.Type.OUTLET)
	assert_eq(outlet.port_local_position(0), Vector3(0, -outlet.size.y * 0.5, 0), "outlet port at the bottom")


func test_route_cable_between_boxes() -> void:
	await _aim(-4.5, -0.4, Vector3(-6.0, 1.5, 0.82))
	assert_eq(_tool.hover.kind, CableTool.HoverKind.PORT, "aiming at a box picks a port")
	assert_eq(_tool.hover.port, 1, "nearest free port (bottom middle)")
	_tool.click()
	assert_eq(_tool.state, CableTool.State.ROUTING, "routing started")

	await _aim(-4.5, -0.4, Vector3(-4.5, 1.2, 0.9))
	assert_true(_tool.hover.valid, "wall waypoint valid: %s" % _tool.hover.reason)
	assert_true(_tool.hover.point.is_equal_approx(Vector3(-4.5, 1.2, 0.9 - CableTool.SURFACE_OFFSET)), "snapped just off the wall: %s" % _tool.hover.point)
	_tool.click()
	assert_eq(_tool.points.size(), 3, "port, exit, waypoint")

	await _aim(-4.5, -0.4, Vector3(-3.0, 1.5, 0.82))
	assert_true(_tool.estimate()["length_m"] > 3.0, "preview measures the whole route")
	var cable := _tool.click()
	assert_not_null(cable, "cable created")
	if cable == null:
		return
	assert_eq(_tool.state, CableTool.State.IDLE, "back to idle")
	assert_eq([cable.node_a, cable.port_a, cable.node_b, cable.port_b], [_box_a.id, 1, _box_b.id, 1], "ends")
	assert_eq(cable.waypoints.size(), 5, "port, exit, waypoint, exit, port")
	assert_true(cable.waypoints[0].is_equal_approx(_network.port_position(_box_a.id, 1)), "starts at port A")
	assert_true(cable.waypoints[-1].is_equal_approx(_network.port_position(_box_b.id, 1)), "ends at port B")
	assert_eq(cable.spec_id, _tool.spec_id(), "chosen fiber type")
	assert_almost(cable.corner_radius, _tool.corner_radius(), 1e-9, "chosen corner radius")
	assert_not_null(_network.cable_body_for(cable.id), "cable body in the world")

	var trace := StrandTracer.trace(_network.network, _box_a.id, 1, 0)[0]
	assert_almost(trace.length_m, cable.route().length_m, 1e-9, "trace runs the cable")
	assert_eq(trace.end_event().node_id, _box_b.id, "light reaches box B")

	await _aim(-4.5, -0.4, Vector3(-6.0, 1.5, 0.82))
	assert_true(_tool.hover.port != 1, "used port is skipped")


func test_cannot_route_through_walls() -> void:
	await _aim(-4.5, -0.4, Vector3(-6.0, 1.5, 0.82))
	_tool.click()
	# Apartment floor seen through the doorway: the straight run from box A would cut the wall.
	await _aim(-5.0, -0.5, Vector3(-5.0, 0.0, 2.0))
	assert_eq(_tool.hover.kind, CableTool.HoverKind.SURFACE, "aiming at the apartment floor")
	assert_false(_tool.hover.valid, "blocked")
	assert_eq(_tool.hover.reason, "The cable would go through a wall", "reason")
	assert_true(_tool.segment_clear(_network, Vector3(-6, 1, 0), Vector3(-3, 1, 0)), "open corridor is clear")
	assert_false(_tool.segment_clear(_network, Vector3(-3, 1, 0), Vector3(-3, 1, 2)), "corridor wall blocks")


func test_undo_and_cancel() -> void:
	await _aim(-4.5, -0.4, Vector3(-6.0, 1.5, 0.82))
	_tool.click()
	await _aim(-4.5, -0.4, Vector3(-4.5, 1.2, 0.9))
	_tool.click()
	_tool.undo()
	assert_eq(_tool.points.size(), 2, "waypoint removed")
	_tool.undo()
	assert_eq(_tool.state, CableTool.State.IDLE, "undo at the start cancels")
	assert_eq(_network.network.cables.size(), 0, "nothing built")


func test_hud_warns_about_tight_bends() -> void:
	_tool.spec_index = CableTool.SPECS.find(&"g652d")
	_tool.radius_index = 0  # 5 mm on bend-sensitive fiber
	await _aim(-4.5, -0.4, Vector3(-6.0, 1.5, 0.82))
	_tool.click()
	await _aim(-4.5, -0.4, Vector3(-4.5, 1.2, 0.9))
	var text := _tool.get_hud_text()
	assert_true(text.contains("tight bend (min 30 mm)"), "HUD: %s" % text)
	assert_true(_tool.estimate()["loss_db"] > 0.5, "5 mm corners on G.652.D cost real loss")
	assert_true(_tool._markers.get_child_count() > 0, "tight corners are marked")


func test_deconstruct_cable_cuts_splices() -> void:
	var cable := await _route_a_to_b()
	_box_a.add_splice(0, 0, 1, 0)
	_player.tool_belt.select_slot(DECONSTRUCT_SLOT)
	var deconstruct: DeconstructTool = _player.tool_belt.tool_node(&"deconstruct")
	await _aim(-4.0, -0.4, cable.route().point_at(cable.route().length_m * 0.7))
	assert_eq(deconstruct.target_kind, LevelNetwork.ItemKind.CABLE, "targets the cable")
	assert_true(deconstruct.get_hud_text().contains("cable (G.657.A1"), "HUD: %s" % deconstruct.get_hud_text())
	assert_true(deconstruct.remove_target(), "removed")
	assert_eq(_network.network.cables.size(), 0, "cable gone")
	assert_eq(_box_a.links.size(), 0, "splice on its port cut")
	assert_eq(_network.network.nodes.size(), 2, "boxes stay")


func test_switching_tool_cancels_routing() -> void:
	await _aim(-4.5, -0.4, Vector3(-6.0, 1.5, 0.82))
	_tool.click()
	_player.tool_belt.select_slot(0)
	assert_eq(_tool.state, CableTool.State.IDLE, "routing dropped")
	assert_eq(_tool.points.size(), 0, "no stale points")
