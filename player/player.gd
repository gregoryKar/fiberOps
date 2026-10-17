class_name Player
extends CharacterBody3D
## First-person technician controller: walk, sprint, crouch, jump and mouse look.
## The camera carries the InteractionRay that every tool aims with.
##
## Mouse: Esc releases the cursor, any click recaptures it. Outside GameState.Mode.GAMEPLAY
## (minigames, UI screens) the player stops responding and the cursor is freed.

@export_group("Movement")
@export var walk_speed := 4.0
@export var sprint_speed := 6.5
@export var crouch_speed := 2.0
## Exponential smoothing rates (1/s) towards the target horizontal velocity.
@export var ground_acceleration := 14.0
@export var air_acceleration := 2.0
@export var jump_velocity := 4.5

@export_group("Body")
@export var stand_height := 1.8
@export var crouch_height := 1.2
## Distance from the top of the capsule down to the eyes.
@export var eye_offset := 0.15
## Crouch / stand transition speed in metres per second.
@export var crouch_transition_speed := 4.0

@export_group("Look")
@export var mouse_sensitivity := 0.0025
@export var max_pitch_degrees := 89.0

var is_crouching := false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interaction_ray: InteractionRay = $Head/Camera3D/InteractionRay
@onready var tool_belt: ToolBelt = $ToolBelt
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _capsule: CapsuleShape3D = $CollisionShape3D.shape


func _ready() -> void:
	# Each player instance resizes its own capsule when crouching.
	_capsule = _capsule.duplicate()
	_collision.shape = _capsule
	_set_body_height(stand_height)
	Events.input_mode_changed.connect(_on_input_mode_changed)
	_on_input_mode_changed(GameState.mode)


func _unhandled_input(event: InputEvent) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		apply_look(event.screen_relative * mouse_sensitivity)
	elif event.is_action_pressed(&"cancel") and captured:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not captured \
			and GameState.mode == GameState.Mode.GAMEPLAY:
		# Swallow the click that recaptures the mouse so tools don't act on it.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"interact") and GameState.mode == GameState.Mode.GAMEPLAY:
		if interaction_ray.interact(self):
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	var can_control := GameState.mode == GameState.Mode.GAMEPLAY
	_update_crouch(can_control and Input.is_action_pressed(&"crouch"), delta)

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif can_control and not is_crouching and Input.is_action_just_pressed(&"jump"):
		velocity.y = jump_velocity

	var input := Vector2.ZERO
	if can_control:
		input = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var target := global_basis * Vector3(input.x, 0.0, input.y) * current_speed()
	var rate := ground_acceleration if is_on_floor() else air_acceleration
	var horizontal := approach_velocity(Vector3(velocity.x, 0.0, velocity.z), target, rate, delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()


## Turns the body by delta.x (yaw) and tilts the head by delta.y (pitch), in radians.
func apply_look(delta: Vector2) -> void:
	rotate_y(-delta.x)
	var limit := deg_to_rad(max_pitch_degrees)
	head.rotation.x = clampf(head.rotation.x - delta.y, -limit, limit)


func current_speed() -> float:
	if is_crouching:
		return crouch_speed
	if Input.is_action_pressed(&"sprint"):
		return sprint_speed
	return walk_speed


## Frame-rate independent exponential approach of `current` towards `target`.
static func approach_velocity(current: Vector3, target: Vector3, rate: float, delta: float) -> Vector3:
	return current.lerp(target, 1.0 - exp(-rate * delta))


func _update_crouch(wants_crouch: bool, delta: float) -> void:
	if wants_crouch:
		is_crouching = true
	elif is_crouching and _can_stand():
		is_crouching = false
	var target_height := crouch_height if is_crouching else stand_height
	if not is_equal_approx(_capsule.height, target_height):
		_set_body_height(move_toward(_capsule.height, target_height, crouch_transition_speed * delta))


## True when there is headroom to grow back to full standing height.
func _can_stand() -> bool:
	var rise := stand_height - _capsule.height
	return rise <= 0.0 or not test_move(global_transform, Vector3.UP * rise)


func _set_body_height(height: float) -> void:
	_capsule.height = height
	_collision.position.y = height * 0.5
	head.position.y = height - eye_offset


func _on_input_mode_changed(mode: int) -> void:
	if mode == GameState.Mode.GAMEPLAY:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
