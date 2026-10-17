extends TestCase
## M0 checks: input map, autoloads, physics layers and the greybox test floor.

const REQUIRED_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"sprint", &"crouch",
	&"interact", &"primary_action", &"secondary_action", &"scroll_up", &"scroll_down",
	&"rotate", &"toggle_snap", &"undo_point", &"cancel",
	&"tool_1", &"tool_2", &"tool_3", &"tool_4", &"tool_5", &"tool_6",
]

var _level: Node


func after_each() -> void:
	if _level:
		_level.free()


func test_input_actions_exist_with_events() -> void:
	for action in REQUIRED_ACTIONS:
		assert_true(InputMap.has_action(action), "missing input action %s" % action)
		if InputMap.has_action(action):
			assert_false(InputMap.action_get_events(action).is_empty(), "no events bound to %s" % action)


func test_move_forward_is_w_key() -> void:
	var event := InputMap.action_get_events(&"move_forward")[0] as InputEventKey
	assert_not_null(event)
	if event:
		assert_eq(event.physical_keycode, KEY_W, "move_forward key")


func test_autoloads_present() -> void:
	for autoload in ["Events", "GameState", "NetworkRegistry"]:
		assert_not_null(tree.root.get_node_or_null(autoload), "autoload %s missing" % autoload)


func test_game_state_mode_change_emits_signal() -> void:
	var game_state := tree.root.get_node("GameState")
	var received: Array[int] = []
	var on_changed := func(mode: int) -> void: received.append(mode)
	tree.root.get_node("Events").input_mode_changed.connect(on_changed)
	game_state.set_mode(game_state.Mode.UI)
	game_state.set_mode(game_state.Mode.UI)
	game_state.set_mode(game_state.Mode.GAMEPLAY)
	tree.root.get_node("Events").input_mode_changed.disconnect(on_changed)
	assert_eq(received, [game_state.Mode.UI, game_state.Mode.GAMEPLAY] as Array[int], "mode signals")


func test_physics_layer_names() -> void:
	assert_eq(ProjectSettings.get_setting("layer_names/3d_physics/layer_1"), "world")
	assert_eq(ProjectSettings.get_setting("layer_names/3d_physics/layer_4"), "cables")


func test_test_floor_builds_tagged_surfaces() -> void:
	_level = load("res://levels/test_floor/test_floor.tscn").instantiate()
	tree.root.add_child(_level)

	var generated := _level.get_node_or_null("Greybox/Generated")
	assert_not_null(generated, "greybox did not generate")
	if generated == null:
		return

	var counts: Dictionary[StringName, int] = {}
	var lights := 0
	for child in generated.get_children():
		if child is StaticBody3D:
			assert_true(child.has_meta(GreyboxFloor.SURFACE_META), "%s has no surface meta" % child.name)
			var surface: StringName = child.get_meta(GreyboxFloor.SURFACE_META)
			counts[surface] = counts.get(surface, 0) + 1
			assert_eq(child.collision_layer, 1, "%s collision layer" % child.name)
		elif child is OmniLight3D:
			lights += 1

	assert_eq(counts.get(&"floor", 0), 1, "floor count")
	assert_eq(counts.get(&"ceiling", 0), 1, "ceiling count")
	assert_eq(counts.get(&"concrete", 0), 4, "outer walls")
	# 2 corridor walls x (3 pieces + 2 lintels) + 2 dividers.
	assert_eq(counts.get(&"brick", 0), 12, "brick pieces")
	# 2 partitions x (2 pieces + 1 lintel).
	assert_eq(counts.get(&"drywall", 0), 6, "drywall pieces")
	assert_eq(lights, GreyboxFloor.LIGHTS.size(), "light count")
	assert_eq(tree.get_nodes_in_group(&"mountable_wall").size(), 22, "mountable walls")


func test_door_gap_leaves_opening() -> void:
	_level = load("res://levels/test_floor/test_floor.tscn").instantiate()
	tree.root.add_child(_level)
	var generated := _level.get_node("Greybox/Generated")
	# Corridor wall z=1 has a door centred at x=-5: no full-height piece may cover it.
	for child in generated.get_children():
		if not (child is StaticBody3D and is_equal_approx(child.position.z, 1.0)):
			continue
		var shape: BoxShape3D = child.get_child(1).shape
		var x_min: float = child.position.x - shape.size.x * 0.5
		var x_max: float = child.position.x + shape.size.x * 0.5
		var bottom: float = child.position.y - shape.size.y * 0.5
		if x_min < -5.0 and x_max > -5.0:
			assert_almost(bottom, GreyboxFloor.DOOR_HEIGHT, 1e-4, "piece over door gap should be a lintel")


func test_player_start_and_camera_face_down_corridor() -> void:
	_level = load("res://levels/test_floor/test_floor.tscn").instantiate()
	tree.root.add_child(_level)
	for node_name in ["PlayerStart", "Player"]:
		var node: Node3D = _level.get_node(node_name)
		var forward := -node.global_basis.z
		assert_almost(forward.x, 1.0, 1e-4, "%s should look along +x" % node_name)
