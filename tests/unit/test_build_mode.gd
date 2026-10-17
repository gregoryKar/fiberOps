extends TestCase
## M3: placing and removing hardware in the test floor.

const BUILD_SLOT := 1
const DECONSTRUCT_SLOT := 3

var _level: Node3D
var _player: Player
var _network: LevelNetwork
var _build: BuildTool
var _deconstruct: DeconstructTool


func before_each() -> void:
	GameState.set_mode(GameState.Mode.GAMEPLAY)
	_level = load("res://levels/test_floor/test_floor.tscn").instantiate()
	tree.root.add_child(_level)
	_player = _level.get_node("Player")
	_network = _level.get_node("LevelNetwork")
	_build = _player.tool_belt.tool_node(&"build")
	_deconstruct = _player.tool_belt.tool_node(&"deconstruct")
	await _frames(10)


func after_each() -> void:
	_level.free()


func _frames(count: int) -> void:
	for i in count:
		await tree.physics_frame


## Stands the player in the corridor at x, looking straight at the north corridor wall.
func _face_north_wall(x: float, pitch := 0.0) -> void:
	_player.global_position = Vector3(x, 0, 0)
	_player.rotation = Vector3(0, PI, 0)
	_player.head.rotation.x = pitch
	await _frames(3)


func test_catalog_loads() -> void:
	var all := PlaceableDef.all()
	assert_eq(all.size(), PlaceableDef.CATALOG.size(), "every catalog entry loads")
	assert_eq(PlaceableDef.for_node_type(NetNode.Type.FLOORBOX).id, &"floorbox", "floorbox lookup")
	for def in all:
		assert_true(def.size.x > 0 and def.size.y > 0 and def.size.z > 0, "%s has a size" % def.id)


func test_wall_basis_and_snapping() -> void:
	var basis := BuildTool.wall_basis(Vector3(0, 0, -1), 0)
	assert_true(basis.z.is_equal_approx(Vector3(0, 0, -1)), "z out of the wall")
	assert_true(basis.y.is_equal_approx(Vector3.UP), "upright")
	var turned := BuildTool.wall_basis(Vector3(0, 0, -1), 1)
	assert_true(turned.z.is_equal_approx(Vector3(0, 0, -1)), "rotation keeps it on the wall")
	assert_almost(absf(turned.x.y), 1.0, 1e-6, "rotated 90° about the normal")
	var snapped := BuildTool.snap_to_grid(Vector3(1.234, 1.618, 0.9), Vector3(0, 0, -1))
	assert_true(snapped.is_equal_approx(Vector3(1.25, 1.6, 0.9)), "snapped in the wall plane: %s" % snapped)


func test_place_floorbox_on_wall() -> void:
	_player.tool_belt.select_slot(BUILD_SLOT)
	await _face_north_wall(-3.0)
	assert_true(_build.placement.valid, "valid on a brick wall: %s" % _build.placement.reason)
	var node := _build.try_place()
	assert_not_null(node, "placed")
	if node == null:
		return
	assert_eq(node.type, NetNode.Type.FLOORBOX, "type")
	assert_eq(node.port_count, 6, "ports from the definition")
	var expected := Vector3(-3.0, 1.65, 0.9 - 0.04 - BuildTool.WALL_GAP)
	assert_true(node.transform.origin.is_equal_approx(expected), "flush on the wall: %s" % node.transform.origin)
	assert_eq(_network.network.nodes.size(), 1, "in the level network")
	assert_eq(NetworkRegistry.get_network(&"test_floor"), _network.network, "registered")
	assert_not_null(_network.body_for(node.id), "physical body created")

	await _frames(3)
	assert_false(_build.placement.valid, "can't stack on the new box")
	assert_eq(_build.try_place(), null, "second placement refused")


func test_rejects_overhang_floor_and_overlap() -> void:
	_player.tool_belt.select_slot(BUILD_SLOT)
	# Door gap spans x -5.45..-4.55; aiming at wall 10 cm from the edge, a 30 cm box overhangs it.
	await _face_north_wall(-5.55)
	assert_false(_build.placement.valid, "overhangs the doorway")
	assert_eq(_build.placement.reason, "Needs flat wall behind the whole box", "reason")

	await _face_north_wall(-3.0, -1.2)
	assert_false(_build.placement.valid, "floor is not a wall")

	await _face_north_wall(-3.0)
	_build.try_place()
	# 20 cm to the side: the boxes (30 cm wide) would overlap, but the ray still hits the wall.
	await _face_north_wall(-2.8)
	assert_false(_build.placement.valid, "overlaps the first box")
	assert_eq(_build.placement.reason, "Something is in the way", "reason")


func test_rotation_and_item_cycling() -> void:
	_player.tool_belt.select_slot(BUILD_SLOT)
	_build.select_item(_build.selected + 1)
	assert_eq(_build.current_def().id, &"splice_closure", "next item")
	_build.select_item(-1)
	assert_eq(_build.current_def().id, PlaceableDef.all()[-1].id, "wraps around")
	_build.select_item(0)
	_build.rotation_steps = 1
	await _face_north_wall(-3.0)
	assert_true(_build.placement.valid, "rotated box still fits")
	assert_almost(absf(_build.placement.transform.basis.x.y), 1.0, 1e-6, "box turned on its side")
	assert_true(_build.get_hud_text().begins_with("BMO floorbox"), "HUD names the item")


func test_deconstruct_removes_node_and_body() -> void:
	_player.tool_belt.select_slot(BUILD_SLOT)
	await _face_north_wall(-3.0)
	var node := _build.try_place()
	_player.tool_belt.select_slot(DECONSTRUCT_SLOT)
	await _frames(3)
	assert_eq(_deconstruct.target_id, node.id, "targets the box")
	assert_true(_deconstruct.get_hud_text().contains("BMO floorbox"), "HUD names the target")

	var changed: Array[StringName] = []
	var on_changed := func(level_id: StringName) -> void: changed.append(level_id)
	Events.network_changed.connect(on_changed)
	assert_true(_deconstruct.remove_target(), "removed")
	Events.network_changed.disconnect(on_changed)
	assert_eq(_network.network.nodes.size(), 0, "gone from the network")
	assert_eq(_network.body_for(node.id), null, "body released")
	assert_true(changed.has(&"test_floor"), "network_changed emitted")
	await _frames(3)
	assert_eq(_deconstruct.target_id, &"", "nothing targeted any more")
	assert_false(_deconstruct.remove_target(), "nothing to remove")


func test_removing_node_removes_its_cables() -> void:
	var def := PlaceableDef.for_node_type(NetNode.Type.FLOORBOX)
	var a := _network.place(def, Transform3D(Basis.IDENTITY, Vector3(-3, 1.6, 0.86)))
	var b := _network.place(def, Transform3D(Basis.IDENTITY, Vector3(-2, 1.6, 0.86)))
	_network.network.add_cable(a.id, 0, b.id, 0, PackedVector3Array([Vector3(-3, 1.6, 0.86), Vector3(-2, 1.6, 0.86)]))
	_network.remove(a.id)
	assert_eq(_network.network.cables.size(), 0, "cable removed with its node")
	assert_eq(_network.network.nodes.size(), 1, "other box stays")


func test_tools_only_run_while_selected() -> void:
	assert_false(_build.active, "build tool idle on Hands")
	_player.tool_belt.select_slot(BUILD_SLOT)
	assert_true(_build.active and not _deconstruct.active, "build active")
	_player.tool_belt.select_slot(DECONSTRUCT_SLOT)
	assert_true(_deconstruct.active and not _build.active, "deconstruct active")
	assert_false(_build.get_child(0).visible, "ghost hidden when switched away")
