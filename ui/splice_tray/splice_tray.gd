class_name SpliceTray
extends CanvasLayer
## Splice tray screen for one network node. Every port with a cable shows its fibers as
## colour-coded buttons; lines connect spliced fibers. Esc or E closes it.

const FIBER_BUTTON_SIZE := Vector2(46, 34)
const FIBERS_PER_ROW := 12
const PANEL_SIZE := Vector2(1180, 680)
const LINE_WIDTH := 3.0

## The open tray, if any (only one at a time).
static var current: SpliceTray

var model: SpliceTrayModel

var _ports_box: VBoxContainer
var _scroll: ScrollContainer
var _splices_box: VBoxContainer
var _side_actions: VBoxContainer
var _message: Label
var _lines: Control
var _fiber_buttons: Dictionary[Vector2i, Button] = {}


## Opens the tray for a node of the level's network and puts the game in UI mode.
static func open(level: LevelNetwork, node_id: StringName) -> SpliceTray:
	if current and is_instance_valid(current):
		return current
	var tray := SpliceTray.new()
	tray.model = SpliceTrayModel.new(level.network, node_id)
	level.get_tree().root.add_child(tray)
	current = tray
	GameState.set_mode(GameState.Mode.UI)
	return tray


func close() -> void:
	if current == self:
		current = null
	GameState.set_mode(GameState.Mode.GAMEPLAY)
	queue_free()


func _ready() -> void:
	layer = 10
	model.use_splicer = true
	model.splice_requested.connect(_start_splicer)
	_build_ui()
	model.changed.connect(_refresh)
	_refresh()


## Hides the tray while the splicing minigame runs, then stores (or drops) its result.
func _start_splicer(from: Vector2i, to: Vector2i) -> SpliceMinigame:
	var specs := model.specs_for(from, to)
	var title := "%s  →  %s" % [SpliceTrayModel.fiber_label(from.x, from.y), SpliceTrayModel.fiber_label(to.x, to.y)]
	var minigame := SpliceMinigame.open(get_parent(), SpliceJob.new(specs[0], specs[1]), from.y, to.y, title)
	visible = false
	minigame.finished.connect(func(job: SpliceJob) -> void:
		visible = true
		model.complete_splice(from, to, job))
	minigame.cancelled.connect(func() -> void:
		visible = true
		model.message = "Splice aborted."
		_refresh())
	return minigame

func _process(_delta: float) -> void:
	_lines.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"cancel") or event.is_action_pressed(&"interact"):
		close()
		get_viewport().set_input_as_handled()


## The button for a fiber end, or null (for tests and the line overlay).
func fiber_button(port: int, fiber: int) -> Button:
	return _fiber_buttons.get(Vector2i(port, fiber))


func _build_ui() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_theme_stylebox_override(&"panel", _style(Color(0.1, 0.12, 0.16, 0.97), 8, 14))
	root.add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override(&"separation", 10)
	panel.add_child(layout)

	var def := PlaceableDef.for_node_type(model.node.type)
	var title := Label.new()
	title.text = "%s  ·  %s  ·  splice tray" % [def.display_name if def else "Node", model.node.id]
	title.add_theme_font_size_override(&"font_size", 22)
	layout.add_child(title)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 14)
	layout.add_child(body)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	_ports_box = VBoxContainer.new()
	_ports_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ports_box.add_theme_constant_override(&"separation", 12)
	_scroll.add_child(_ports_box)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(330, 0)
	side.add_theme_constant_override(&"separation", 8)
	body.add_child(side)
	var splices_title := Label.new()
	splices_title.text = "Splices"
	splices_title.add_theme_font_size_override(&"font_size", 18)
	side.add_child(splices_title)
	var splices_scroll := ScrollContainer.new()
	splices_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(splices_scroll)
	_splices_box = VBoxContainer.new()
	_splices_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	splices_scroll.add_child(_splices_box)
	_side_actions = VBoxContainer.new()
	side.add_child(_side_actions)

	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_message)
	var help := Label.new()
	help.text = "Click a fiber, then another to splice them.  Click a spliced fiber to select its splice.  [Esc] / [E] close"
	help.modulate = Color(1, 1, 1, 0.6)
	layout.add_child(help)

	_lines = Control.new()
	_lines.name = "SpliceLines"
	_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.draw.connect(_draw_lines)
	root.add_child(_lines)


func _refresh() -> void:
	for child in _ports_box.get_children():
		child.queue_free()
	for child in _splices_box.get_children():
		child.queue_free()
	for child in _side_actions.get_children():
		child.queue_free()
	_fiber_buttons.clear()

	for entry in model.ports():
		_ports_box.add_child(_port_card(entry["port"], entry["cable"]))

	for link in model.node.links:
		var row := Label.new()
		row.text = "%s ↔ %s  %s" % [
			SpliceTrayModel.fiber_label(link.port_a, link.fiber_a),
			SpliceTrayModel.fiber_label(link.port_b, link.fiber_b), SpliceTrayModel.loss_label(link)]
		if link == model.selected_link:
			row.modulate = Color(1.0, 0.85, 0.3)
		_splices_box.add_child(row)
	if model.node.links.is_empty():
		var none := Label.new()
		none.text = "No splices yet."
		none.modulate = Color(1, 1, 1, 0.5)
		_splices_box.add_child(none)

	if model.selected_link:
		_side_actions.add_child(_action_button("Cut selected splice", model.cut_selected))
	for ratio in model.available_splitter_ratios():
		_side_actions.add_child(_action_button("Install 1:%d splitter" % ratio, model.add_splitter.bind(ratio)))
	if model.selected_end.x >= 0 or model.selected_link:
		_side_actions.add_child(_action_button("Clear selection", model.clear_selection))
	_message.text = model.message


func _port_card(port: int, cable: Cable) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override(&"panel", _style(Color(0.16, 0.18, 0.23), 6, 10))
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	card.add_child(box)
	var header := Label.new()
	box.add_child(header)
	if cable == null:
		header.text = "Port %d  —  no cable" % (port + 1)
		header.modulate = Color(1, 1, 1, 0.45)
		return card
	header.text = "Port %d  %s" % [port + 1, model.far_end_label(cable)]

	var grid := GridContainer.new()
	grid.columns = FIBERS_PER_ROW
	grid.add_theme_constant_override(&"h_separation", 6)
	grid.add_theme_constant_override(&"v_separation", 6)
	box.add_child(grid)
	for fiber in cable.fiber_count:
		var button := _fiber_button(port, fiber)
		grid.add_child(button)
		_fiber_buttons[Vector2i(port, fiber)] = button
	return card


func _fiber_button(port: int, fiber: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = FIBER_BUTTON_SIZE
	button.text = str(fiber + 1)
	button.tooltip_text = SpliceTrayModel.fiber_label(port, fiber)
	var state := model.fiber_state(port, fiber)
	var selected := model.selected_end == Vector2i(port, fiber) \
			or (model.selected_link != null and model.selected_link.touches(port, fiber))
	var border := Color.WHITE if selected else (Color(1.0, 0.8, 0.2) if state != SpliceTrayModel.FiberState.FREE else Color(0, 0, 0, 0.6))
	var style := _style(FiberColors.color_for(fiber), 5, 0)
	style.border_color = border
	style.set_border_width_all(4 if selected else 2)
	if FiberColors.has_stripe(fiber):
		style.border_width_bottom = 8
		style.border_color = Color.BLACK if fiber != 19 else Color.WHITE
	for state_name in [&"normal", &"hover", &"pressed", &"focus"]:
		button.add_theme_stylebox_override(state_name, style)
	var text_color := FiberColors.text_color_for(fiber)
	for color_name in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		button.add_theme_color_override(color_name, text_color)
	button.pressed.connect(model.click_fiber.bind(port, fiber))
	return button


func _draw_lines() -> void:
	var clip := _scroll.get_global_rect()
	for link in model.node.links:
		var a: Button = fiber_button(link.port_a, link.fiber_a)
		var b: Button = fiber_button(link.port_b, link.fiber_b)
		if a == null or b == null or not a.is_inside_tree() or not b.is_inside_tree():
			continue
		var ra := a.get_global_rect()
		var rb := b.get_global_rect()
		if not clip.has_point(ra.get_center()) or not clip.has_point(rb.get_center()):
			continue
		# Run edge to edge (bottom of the upper button to top of the lower) to keep numbers readable.
		if ra.get_center().y > rb.get_center().y:
			var swap := ra
			ra = rb
			rb = swap
		var pa := Vector2(ra.get_center().x, ra.end.y)
		var pb := Vector2(rb.get_center().x, rb.position.y)
		if is_equal_approx(ra.position.y, rb.position.y):
			pa = ra.get_center()
			pb = rb.get_center()
		var color := FiberColors.color_for(link.fiber_a)
		var width := LINE_WIDTH * (2.0 if link == model.selected_link else 1.0)
		_lines.draw_line(pa, pb, Color(0, 0, 0, 0.6), width + 3.0, true)
		_lines.draw_line(pa, pb, color, width, true)


func _action_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(func() -> void: action.call())
	return button


static func _style(color: Color, radius: int, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style
