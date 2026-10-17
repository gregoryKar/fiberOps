extends Node
## Session-wide state: the active level and what the player's input currently drives.

enum Mode {
	GAMEPLAY,  ## Walking around, tools active.
	MINIGAME,  ## Splicing or mounting minigame has focus.
	UI,        ## A menu or screen (OTDR, splice tray) has focus.
}

var current_level_id: StringName = &""
var mode: Mode = Mode.GAMEPLAY


func set_mode(new_mode: Mode) -> void:
	if new_mode == mode:
		return
	mode = new_mode
	Events.input_mode_changed.emit(mode)
