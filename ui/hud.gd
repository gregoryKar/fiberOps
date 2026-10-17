class_name Hud
extends CanvasLayer
## In-game HUD: crosshair, interaction prompt and the tool hotbar.

const SLOT_SIZE := Vector2(96, 56)
const SLOT_COLOR := Color(0.08, 0.1, 0.14, 0.75)
const SLOT_ACTIVE_BORDER := Color(1.0, 0.8, 0.2)

@export var player: Player

var _crosshair: Crosshair
var _prompt: Label
var _hint: Label
var _slots: Array[PanelContainer] = []


func _ready() -> void:
	# Children are ready before their parent, so the player's @onready refs aren't set yet.
	if player and not player.is_node_ready():
		await player.ready

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_crosshair = Crosshair.new()
	_crosshair.name = "Crosshair"
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_crosshair)

	_prompt = Label.new()
	_prompt.name = "Prompt"
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.position.y += 28.0
	_prompt.add_theme_constant_override(&"outline_size", 4)
	_prompt.add_theme_color_override(&"font_outline_color", Color.BLACK)
	root.add_child(_prompt)

	_hint = Label.new()
	_hint.name = "ToolHint"
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.position.y -= SLOT_SIZE.y + 28.0
	_hint.add_theme_constant_override(&"outline_size", 4)
	_hint.add_theme_color_override(&"font_outline_color", Color.BLACK)
	root.add_child(_hint)

	_build_hotbar(root)
	Events.tool_changed.connect(func(_tool_id: StringName) -> void: _refresh_hotbar())
	_refresh_hotbar()


func _process(_delta: float) -> void:
	if _crosshair == null:
		return
	var prompt := player.interaction_ray.get_prompt() if player else ""
	_crosshair.highlighted = player != null and player.interaction_ray.target != null
	_prompt.text = "[E] %s" % prompt if prompt != "" else ""
	var tool: Tool = player.tool_belt.active_tool_node() if player else null
	_hint.text = tool.get_hud_text() if tool else ""


func _build_hotbar(root: Control) -> void:
	var bar := HBoxContainer.new()
	bar.name = "Hotbar"
	bar.add_theme_constant_override(&"separation", 6)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.position.y -= 16.0
	root.add_child(bar)
	if player == null:
		return
	for i in player.tool_belt.slots.size():
		var slot := PanelContainer.new()
		slot.custom_minimum_size = SLOT_SIZE
		var label := Label.new()
		label.text = "%d\n%s" % [i + 1, ToolBelt.display_name(player.tool_belt.slots[i])]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_child(label)
		bar.add_child(slot)
		_slots.append(slot)


func _refresh_hotbar() -> void:
	for i in _slots.size():
		var style := StyleBoxFlat.new()
		style.bg_color = SLOT_COLOR
		style.set_corner_radius_all(6)
		if player and i == player.tool_belt.active_slot:
			style.border_color = SLOT_ACTIVE_BORDER
			style.set_border_width_all(2)
		_slots[i].add_theme_stylebox_override(&"panel", style)
