extends TestCase
## M5: splice tray editing (model) and the screen opened from a box in the level.

var _net: FiberNetwork
var _bep: NetNode
var _box: NetNode
var _outlet: NetNode
var _model: SpliceTrayModel
var _level: Node3D


func before_each() -> void:
	GameState.set_mode(GameState.Mode.GAMEPLAY)
	# BEP ──12f── box ──2f── outlet; the box has two free ports left.
	_net = FiberNetwork.new()
	_bep = _net.add_node(NetNode.Type.BEP)
	_box = _net.add_node(NetNode.Type.FLOORBOX, Transform3D.IDENTITY, 4)
	_outlet = _net.add_node(NetNode.Type.OUTLET)
	_net.add_cable(_bep.id, 0, _box.id, 0, PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 0)]), &"g657a1", 12)
	_net.add_cable(_box.id, 1, _outlet.id, 0, PackedVector3Array([Vector3(10, 0, 0), Vector3(15, 0, 0)]), &"g657a1", 2)
	_model = SpliceTrayModel.new(_net, _box.id)


func after_each() -> void:
	if SpliceTray.current and is_instance_valid(SpliceTray.current):
		SpliceTray.current.close()
	if _level:
		_level.free()
		_level = null
	GameState.set_mode(GameState.Mode.GAMEPLAY)


func test_fiber_colours() -> void:
	assert_eq(FiberColors.name_for(0), "blue", "fiber 1")
	assert_eq(FiberColors.name_for(11), "aqua", "fiber 12")
	assert_eq(FiberColors.name_for(12), "blue/stripe", "fiber 13 repeats with a stripe")
	assert_true(FiberColors.has_stripe(12) and not FiberColors.has_stripe(11), "stripes from 13")
	assert_eq(FiberColors.text_color_for(5), Color.BLACK, "dark text on white")
	assert_eq(FiberColors.text_color_for(7), Color.WHITE, "light text on black")


func test_ports_and_far_ends() -> void:
	var ports := _model.ports()
	assert_eq(ports.size(), 4, "one entry per port")
	assert_eq(ports[0]["cable"].fiber_count, 12, "feeder on port 1")
	assert_eq(ports[2]["cable"], null, "port 3 empty")
	assert_true(_model.far_end_label(ports[1]["cable"]).contains("Fiber outlet"), _model.far_end_label(ports[1]["cable"]))


func test_click_two_fibers_splices_them() -> void:
	var edits := [0]
	_net.changed.connect(func() -> void: edits[0] += 1)
	assert_eq(_model.click_fiber(0, 3), null, "first click selects")
	assert_eq(_model.selected_end, Vector2i(0, 3), "selected")
	var link := _model.click_fiber(1, 0)
	assert_not_null(link, "second click splices")
	assert_eq([link.port_a, link.fiber_a, link.port_b, link.fiber_b], [0, 3, 1, 0], "ends")
	assert_eq(_model.selected_end, Vector2i(-1, -1), "selection cleared")
	assert_eq(_model.fiber_state(0, 3), SpliceTrayModel.FiberState.SPLICED, "state")
	assert_true(edits[0] > 0, "network change reported")

	var trace := StrandTracer.trace(_net, _bep.id, 0, 3)[0]
	assert_eq(trace.end_event().node_id, _outlet.id, "fiber 4 now reaches the outlet")


func test_reclick_and_already_spliced() -> void:
	_model.click_fiber(0, 0)
	_model.click_fiber(0, 0)
	assert_eq(_model.selected_end, Vector2i(-1, -1), "clicking the same fiber deselects")
	_model.click_fiber(0, 0)
	_model.click_fiber(1, 0)
	_model.click_fiber(0, 1)
	assert_eq(_model.click_fiber(1, 0), null, "target already spliced")
	assert_true(_model.message.contains("already spliced"), _model.message)
	assert_eq(_box.links.size(), 1, "still one splice")


func test_select_and_cut_splice() -> void:
	_model.click_fiber(0, 0)
	_model.click_fiber(1, 0)
	_model.click_fiber(1, 0)
	assert_not_null(_model.selected_link, "clicking a spliced fiber selects its splice")
	assert_true(_model.cut_selected(), "cut")
	assert_eq(_box.links.size(), 0, "gone")
	assert_false(_model.cut_selected(), "nothing selected any more")


func test_splitter_install_and_removal() -> void:
	var splitter := _net.add_node(NetNode.Type.SPLITTER)
	_net.add_cable(_box.id, 2, splitter.id, 0, PackedVector3Array([Vector3(10, 0, 0), Vector3(11, 0, 0)]), &"g657a1", 2)
	var drop_box := _net.add_node(NetNode.Type.FLOORBOX)
	_net.add_cable(splitter.id, 1, drop_box.id, 0, PackedVector3Array([Vector3(11, 0, 0), Vector3(12, 0, 0)]), &"g657a1", 4)
	var model := SpliceTrayModel.new(_net, splitter.id)
	assert_eq(model.available_splitter_ratios(), [] as Array[int], "needs a selected input fiber")
	model.click_fiber(0, 0)
	assert_eq(model.available_splitter_ratios(), [2, 4] as Array[int], "output cable has 4 fibers")
	var legs := model.add_splitter(4)
	assert_eq(legs.size(), 4, "four legs")
	assert_eq(model.fiber_state(1, 3), SpliceTrayModel.FiberState.SPLITTER, "leg fibers marked")
	model.click_fiber(1, 2)
	assert_true(model.cut_selected(), "cut a leg")
	assert_eq(splitter.links.size(), 0, "the whole splitter goes")
	assert_true(model.message.contains("Splitter removed"), model.message)


func test_box_opens_tray_with_e_and_closes() -> void:
	_level = load("res://levels/test_floor/test_floor.tscn").instantiate()
	tree.root.add_child(_level)
	var player: Player = _level.get_node("Player")
	var level_network: LevelNetwork = _level.get_node("LevelNetwork")
	var basis := BuildTool.wall_basis(Vector3(0, 0, -1), 0)
	var box := level_network.place(PlaceableDef.for_node_type(NetNode.Type.FLOORBOX), Transform3D(basis, Vector3(-3.0, 1.6, 0.859)))
	var other := level_network.place(PlaceableDef.for_node_type(NetNode.Type.OUTLET), Transform3D(basis, Vector3(-2.0, 0.5, 0.884)))
	level_network.network.add_cable(box.id, 0, other.id, 0,
			PackedVector3Array([level_network.port_position(box.id, 0), level_network.port_position(other.id, 0)]), &"g657a1", 12)
	player.global_position = Vector3(-3.0, 0, 0)
	player.rotation = Vector3(0, PI, 0)
	player.head.rotation.x = 0.0
	for i in 10:
		await tree.physics_frame

	assert_true(player.interaction_ray.target is NetNodeBody, "box is interactable")
	assert_true(player.interaction_ray.get_prompt().begins_with("Open splice tray (BMO floorbox"), player.interaction_ray.get_prompt())
	player.interaction_ray.interact(player)
	var tray := SpliceTray.current
	assert_not_null(tray, "tray open")
	assert_eq(GameState.mode, GameState.Mode.UI, "UI mode while the tray is open")
	await tree.process_frame
	assert_not_null(tray.fiber_button(0, 11), "12 fiber buttons for the cable")
	assert_eq(tray.fiber_button(1, 0), null, "empty port has no buttons")

	tray.fiber_button(0, 0).pressed.emit()
	assert_eq(tray.model.selected_end, Vector2i(0, 0), "button click selects")
	tray.close()
	assert_eq(GameState.mode, GameState.Mode.GAMEPLAY, "back to gameplay")
	assert_eq(SpliceTray.current, null, "closed")
