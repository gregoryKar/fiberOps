extends TestCase
## M1: player controller, interaction ray, tool belt and HUD, run against the test floor.

const ACTIONS: Array[StringName] = [&"move_forward", &"sprint", &"crouch"]

var _level: Node3D
var _player: Player


func before_each() -> void:
	GameState.set_mode(GameState.Mode.GAMEPLAY)
	_level = load("res://levels/test_floor/test_floor.tscn").instantiate()
	tree.root.add_child(_level)
	_player = _level.get_node("Player")
	await _physics_frames(15)  # land on the floor


func after_each() -> void:
	for action in ACTIONS:
		Input.action_release(action)
	GameState.set_mode(GameState.Mode.GAMEPLAY)
	_level.free()


func _physics_frames(count: int) -> void:
	for i in count:
		await tree.physics_frame


func _horizontal_speed() -> float:
	return Vector2(_player.velocity.x, _player.velocity.z).length()


func test_player_stands_on_floor() -> void:
	assert_true(_player.is_on_floor(), "player should be on the floor")
	assert_almost(_player.global_position.y, 0.0, 0.05, "feet height")
	assert_almost(_player.head.position.y, _player.stand_height - _player.eye_offset, 1e-4, "eye height")


func test_walk_forward_moves_along_facing() -> void:
	var start := _player.global_position
	Input.action_press(&"move_forward")
	await _physics_frames(30)
	var moved := _player.global_position - start
	assert_true(moved.x > 0.5, "should walk down the corridor (+x), moved %s" % moved)
	assert_almost(moved.z, 0.0, 0.05, "no sideways drift")


func test_sprint_is_faster_than_walk() -> void:
	Input.action_press(&"move_forward")
	await _physics_frames(30)
	assert_almost(_horizontal_speed(), _player.walk_speed, 0.2, "walk speed")
	Input.action_press(&"sprint")
	await _physics_frames(30)
	assert_almost(_horizontal_speed(), _player.sprint_speed, 0.2, "sprint speed")


func test_ui_mode_blocks_movement() -> void:
	GameState.set_mode(GameState.Mode.UI)
	var start := _player.global_position
	Input.action_press(&"move_forward")
	await _physics_frames(20)
	assert_true(_player.global_position.distance_to(start) < 0.01, "player must not move in UI mode")


func test_crouch_stays_down_under_low_obstacle() -> void:
	Input.action_press(&"crouch")
	await _physics_frames(30)
	assert_true(_player.is_crouching, "crouching")
	assert_almost(_player.head.position.y, _player.crouch_height - _player.eye_offset, 1e-3, "crouched eyes")

	# Slab with its underside at 1.4 m: too low to stand up, high enough to crouch under.
	var obstacle := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(2, 0.4, 2)
	obstacle.add_child(shape)
	_level.add_child(obstacle)
	obstacle.global_position = _player.global_position + Vector3(0, 1.6, 0)
	await _physics_frames(2)

	Input.action_release(&"crouch")
	await _physics_frames(30)
	assert_true(_player.is_crouching, "must stay crouched under the obstacle")

	obstacle.free()
	await _physics_frames(30)
	assert_false(_player.is_crouching, "should stand once there is headroom")
	assert_almost(_player.head.position.y, _player.stand_height - _player.eye_offset, 1e-3, "standing eyes")


func test_look_clamps_pitch_and_turns_body() -> void:
	_player.apply_look(Vector2(0, -100))
	assert_almost(_player.head.rotation.x, deg_to_rad(_player.max_pitch_degrees), 1e-4, "pitch clamped up")
	_player.apply_look(Vector2(0, 100))
	assert_almost(_player.head.rotation.x, -deg_to_rad(_player.max_pitch_degrees), 1e-4, "pitch clamped down")
	_player.apply_look(Vector2(PI / 2, 0))
	var forward := -_player.global_basis.z
	assert_almost(forward.z, 1.0, 1e-4, "turning right from +x faces +z")


func test_interaction_ray_targets_light_switch() -> void:
	var switch := _level.get_node("LightSwitch")
	_player.global_position = Vector3(-8.5, 0, 0)
	_player.rotation = Vector3(0, PI, 0)  # face +z, towards the switch
	var eye := _player.head.global_position
	var to_switch: Vector3 = switch.global_position - eye
	_player.head.rotation.x = atan2(to_switch.y, to_switch.z)
	await _physics_frames(3)

	assert_eq(_player.interaction_ray.target, switch, "ray target")
	assert_eq(_player.interaction_ray.get_prompt(), "Turn lights off", "prompt")
	await tree.process_frame
	var prompt: Label = _player.get_node("Hud/Root/Prompt")
	assert_eq(prompt.text, "[E] Turn lights off", "HUD prompt")

	assert_true(_player.interaction_ray.interact(_player), "interact returns true")
	for light in tree.get_nodes_in_group(&"floor_lights"):
		assert_false(light.visible, "%s should be off" % light.name)

	_player.head.rotation.x = 0.0  # look down the corridor at nothing interactable
	await _physics_frames(3)
	assert_eq(_player.interaction_ray.target, null, "target cleared")
	assert_false(_player.interaction_ray.interact(_player), "nothing to interact with")


func test_tool_belt_switches_slots() -> void:
	var received: Array[StringName] = []
	var on_changed := func(tool_id: StringName) -> void: received.append(tool_id)
	Events.tool_changed.connect(on_changed)
	var belt := _player.tool_belt
	belt.select_slot(2)
	belt.select_slot(2)
	belt.select_slot(99)
	belt.select_slot(-1)
	Events.tool_changed.disconnect(on_changed)
	assert_eq(received, [&"cable"] as Array[StringName], "only one real change")
	assert_eq(belt.active_tool(), &"cable")


func test_hud_builds_hotbar() -> void:
	var hotbar := _player.get_node("Hud/Root/Hotbar")
	assert_eq(hotbar.get_child_count(), _player.tool_belt.slots.size(), "one slot per tool")


func test_approach_velocity() -> void:
	var current := Vector3(1, 0, 0)
	assert_eq(Player.approach_velocity(current, Vector3.ZERO, 10.0, 0.0), current, "zero delta keeps velocity")
	var fast := Player.approach_velocity(current, Vector3(0, 0, 5), 1000.0, 1.0)
	assert_true(fast.distance_to(Vector3(0, 0, 5)) < 1e-4, "huge rate reaches the target")
