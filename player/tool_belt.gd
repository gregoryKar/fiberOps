class_name ToolBelt
extends Node
## Hotbar of the technician's tools, switched with keys 1-6. Child Tool nodes implement the
## slots whose tool_id they carry; slots without one (yet) do nothing when selected.

const TOOL_NAMES: Dictionary[StringName, String] = {
	&"hands": "Hands",
	&"build": "Build",
	&"cable": "Cable",
	&"deconstruct": "Deconstruct",
	&"otdr": "OTDR",
	&"power_meter": "Power meter",
}

@export var slots: Array[StringName] = [&"hands", &"build", &"cable", &"deconstruct", &"otdr", &"power_meter"]

var active_slot := 0

var _tools: Dictionary[StringName, Tool] = {}


func _ready() -> void:
	for child in get_children():
		if child is Tool:
			_tools[child.tool_id] = child
	var current := active_tool_node()
	if current:
		current.activate()


func _unhandled_input(event: InputEvent) -> void:
	if GameState.mode != GameState.Mode.GAMEPLAY:
		return
	for i in slots.size():
		if event.is_action_pressed(&"tool_%d" % (i + 1)):
			select_slot(i)
			get_viewport().set_input_as_handled()
			return


func select_slot(index: int) -> void:
	if index < 0 or index >= slots.size() or index == active_slot:
		return
	var previous := active_tool_node()
	if previous:
		previous.deactivate()
	active_slot = index
	var current := active_tool_node()
	if current:
		current.activate()
	Events.tool_changed.emit(active_tool())


func active_tool() -> StringName:
	return slots[active_slot]


## The Tool node for the selected slot, or null if that slot has no implementation yet.
func active_tool_node() -> Tool:
	return _tools.get(active_tool())


func tool_node(tool_id: StringName) -> Tool:
	return _tools.get(tool_id)


static func display_name(tool_id: StringName) -> String:
	return TOOL_NAMES.get(tool_id, String(tool_id))
