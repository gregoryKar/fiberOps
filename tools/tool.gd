class_name Tool
extends Node
## Base class for hotbar tools. Lives under the player's ToolBelt; the belt activates the one
## whose tool_id matches the selected slot. Inactive tools don't process or take input.

@export var tool_id: StringName

var active := false
var player: Player


func _ready() -> void:
	player = owner as Player
	_set_running(false)


func activate() -> void:
	active = true
	_set_running(true)
	_on_activate()


func deactivate() -> void:
	active = false
	_set_running(false)
	_on_deactivate()


## Hint line shown above the hotbar while this tool is active.
func get_hud_text() -> String:
	return ""


## True when the tool may react to the world: active, in gameplay, with the mouse captured
## (so the click that recaptures the mouse doesn't also place or remove something).
func can_act() -> bool:
	return active and GameState.mode == GameState.Mode.GAMEPLAY \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func level_network() -> LevelNetwork:
	return LevelNetwork.find(get_tree())


func _on_activate() -> void:
	pass


func _on_deactivate() -> void:
	pass


func _set_running(running: bool) -> void:
	set_process(running)
	set_physics_process(running)
	set_process_unhandled_input(running)
