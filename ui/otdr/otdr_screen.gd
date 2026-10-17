class_name OtdrScreen
extends CanvasLayer
## OTDR instrument screen for one launch point (box port + fiber).
## Measure runs a short live acquisition: the trace refreshes while averaging builds up and
## the noise drops, then the event table and the pass/fail verdict appear.

const PANEL_SIZE := Vector2(1440, 820)
## Real seconds per second of averaging time, so a 60 s acquisition takes ~6 s.
const ACQUISITION_TIME_SCALE := 0.1
const MIN_ACQUISITION_S := 0.4
const REFRESH_INTERVAL_S := 0.15
const MAX_EVENT_LOSS_DB := 0.3
const MAX_REFLECTANCE_DB := -35.0
const DEFAULT_BUDGET_DB := 1.5

static var current: OtdrScreen
## Settings carry over between measurements, like on a real instrument.
static var last_settings := OtdrSettings.new()

var network: FiberNetwork
var node_id: StringName
var port := 0
var fiber := 0
var settings: OtdrSettings
var trace: OtdrTrace
var budget_db := DEFAULT_BUDGET_DB
var measuring := false

var _elapsed := 0.0
var _duration := 0.0
var _since_refresh := 0.0
var _plot: OtdrPlot
var _cursor_label: Label
var _summary: Label
var _table: GridContainer
var _branch_option: OptionButton


static func open(level: LevelNetwork, target_node: StringName, target_port: int, target_fiber: int) -> OtdrScreen:
	if current and is_instance_valid(current):
		return current
	var screen := OtdrScreen.new()
	screen.network = level.network
	screen.node_id = target_node
	screen.port = target_port
	screen.fiber = target_fiber
	screen.settings = last_settings.copy()
	screen.settings.branch = 0
	level.get_tree().root.add_child(screen)
	current = screen
	GameState.set_mode(GameState.Mode.UI)
	screen.start_measurement()
	return screen


func close() -> void:
	last_settings = settings.copy()
	if current == self:
		current = null
	GameState.set_mode(GameState.Mode.GAMEPLAY)
	queue_free()


func _ready() -> void:
	layer = 10
	_build_ui()


func _process(delta: float) -> void:
	if not measuring:
		return
	_elapsed += delta
	_since_refresh += delta
	if _elapsed >= _duration:
		measure_now()
	elif _since_refresh >= REFRESH_INTERVAL_S:
		_since_refresh = 0.0
		_show(_acquire(settings.averaging_s * _elapsed / _duration), false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"cancel") or event.is_action_pressed(&"interact"):
		close()
		get_viewport().set_input_as_handled()


## Starts a live acquisition (finishes in measure_now()).
func start_measurement() -> void:
	measuring = true
	_elapsed = 0.0
	_since_refresh = REFRESH_INTERVAL_S
	_duration = maxf(settings.averaging_s * ACQUISITION_TIME_SCALE, MIN_ACQUISITION_S)
	if _summary:
		_summary.text = "Measuring…"


## Completes the measurement immediately with the full averaging time.
func measure_now() -> OtdrTrace:
	measuring = false
	_show(_acquire(settings.averaging_s), true)
	return trace


## Problems found in the final trace; empty means PASS.
func verdict() -> PackedStringArray:
	var problems := PackedStringArray()
	if trace == null:
		return problems
	if trace.end_in_noise:
		problems.append("fiber end not reached (lost in noise): use a longer pulse or more averaging")
	elif trace.link_loss_db > budget_db:
		problems.append("link loss %.2f dB over the %.2f dB budget" % [trace.link_loss_db, budget_db])
	for event in trace.events:
		if event.kind == OtdrTrace.EventKind.END:
			continue
		if not is_nan(event.loss_db) and event.loss_db > MAX_EVENT_LOSS_DB:
			problems.append("event %d loses %.2f dB (max %.2f)" % [event.number, event.loss_db, MAX_EVENT_LOSS_DB])
		if not is_nan(event.reflectance_db) and event.reflectance_db > MAX_REFLECTANCE_DB:
			problems.append("event %d reflects %.1f dB (max %.0f)" % [event.number, event.reflectance_db, MAX_REFLECTANCE_DB])
	return problems


func _acquire(averaging_s: float) -> OtdrTrace:
	var acquisition := settings.copy()
	acquisition.averaging_s = maxf(averaging_s, 0.05)
	return OtdrSimulator.simulate(network, node_id, port, fiber, acquisition)


func _show(new_trace: OtdrTrace, final: bool) -> void:
	trace = new_trace
	if _plot == null:
		return
	_plot.trace = trace
	_update_cursor_label()
	if final:
		_fill_table()
		_update_summary()
		_update_branch_option()
	else:
		_summary.text = "Measuring…  %d%%" % int(100.0 * _elapsed / _duration)


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.1, 0.13, 0.98)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override(&"panel", style)
	root.add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override(&"separation", 8)
	panel.add_child(layout)

	var title := Label.new()
	title.text = "OTDR  ·  %s port %d  ·  fiber %s" % [node_id, port + 1, SpliceTrayModel.fiber_label(port, fiber)]
	title.add_theme_font_size_override(&"font_size", 20)
	layout.add_child(title)

	_plot = OtdrPlot.new()
	_plot.custom_minimum_size = Vector2(0, 420)
	_plot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_plot.cursors_changed.connect(_update_cursor_label)
	layout.add_child(_plot)

	_cursor_label = Label.new()
	layout.add_child(_cursor_label)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override(&"separation", 10)
	layout.add_child(controls)
	_add_option(controls, "λ", OtdrSettings.WAVELENGTHS.map(func(w: int) -> String: return "%d nm" % w),
			OtdrSettings.WAVELENGTHS.find(settings.wavelength_nm),
			func(i: int) -> void: settings.wavelength_nm = OtdrSettings.WAVELENGTHS[i])
	_add_option(controls, "Pulse", OtdrSettings.PULSE_WIDTHS_NS.map(func(p: float) -> String: return "%d ns" % p),
			OtdrSettings.PULSE_WIDTHS_NS.find(settings.pulse_width_ns),
			func(i: int) -> void: settings.pulse_width_ns = OtdrSettings.PULSE_WIDTHS_NS[i])
	_add_option(controls, "Averaging", OtdrSettings.AVERAGING_S.map(func(a: float) -> String: return "%d s" % a),
			OtdrSettings.AVERAGING_S.find(settings.averaging_s),
			func(i: int) -> void: settings.averaging_s = OtdrSettings.AVERAGING_S[i])
	_add_option(controls, "Launch cord", OtdrSettings.LAUNCH_CORDS_M.map(func(l: float) -> String: return "%d m" % l),
			OtdrSettings.LAUNCH_CORDS_M.find(settings.launch_cord_m),
			func(i: int) -> void: settings.launch_cord_m = OtdrSettings.LAUNCH_CORDS_M[i])
	_branch_option = _add_option(controls, "Branch", ["1"], 0, func(i: int) -> void: settings.branch = i)

	var budget_label := Label.new()
	budget_label.text = "Budget dB"
	controls.add_child(budget_label)
	var budget := SpinBox.new()
	budget.min_value = 0.1
	budget.max_value = 40.0
	budget.step = 0.1
	budget.value = budget_db
	budget.value_changed.connect(func(value: float) -> void:
		budget_db = value
		_update_summary())
	controls.add_child(budget)

	var measure := Button.new()
	measure.text = "  Measure  "
	measure.pressed.connect(start_measurement)
	controls.add_child(measure)
	var fit := Button.new()
	fit.text = "Fit view"
	fit.pressed.connect(func() -> void: _plot.fit_view())
	controls.add_child(fit)

	var table_scroll := ScrollContainer.new()
	table_scroll.custom_minimum_size = Vector2(0, 150)
	layout.add_child(table_scroll)
	_table = GridContainer.new()
	_table.columns = 6
	_table.add_theme_constant_override(&"h_separation", 28)
	table_scroll.add_child(_table)

	_summary = Label.new()
	_summary.add_theme_font_size_override(&"font_size", 17)
	layout.add_child(_summary)
	var help := Label.new()
	help.text = "LMB / RMB set cursors A / B   Wheel zoom (Ctrl: dB)   Middle-drag pan   [Esc] / [E] close"
	help.modulate = Color(1, 1, 1, 0.55)
	layout.add_child(help)
	if trace:
		_show(trace, not measuring)


func _add_option(parent: Control, label_text: String, items: Array, selected: int, on_select: Callable) -> OptionButton:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var option := OptionButton.new()
	for item in items:
		option.add_item(item)
	option.select(maxi(selected, 0))
	option.item_selected.connect(func(i: int) -> void:
		on_select.call(i)
		start_measurement())
	parent.add_child(option)
	return option


func _update_branch_option() -> void:
	if trace == null or _branch_option.item_count == trace.branch_count:
		return
	_branch_option.clear()
	for i in trace.branch_count:
		_branch_option.add_item(str(i + 1))
	_branch_option.select(clampi(settings.branch, 0, trace.branch_count - 1))


func _fill_table() -> void:
	for child in _table.get_children():
		child.queue_free()
	for header in ["#", "Type", "Distance m", "Loss dB", "Refl. dB", "Cumul. dB"]:
		_cell(header, Color(1, 1, 1, 0.6))
	for event in trace.events:
		var flagged := (not is_nan(event.loss_db) and event.loss_db > MAX_EVENT_LOSS_DB and event.kind != OtdrTrace.EventKind.END) \
				or (not is_nan(event.reflectance_db) and event.reflectance_db > MAX_REFLECTANCE_DB and event.kind != OtdrTrace.EventKind.END)
		var color := Color(1.0, 0.45, 0.35) if flagged else Color.WHITE
		_cell(str(event.number), color)
		_cell(event.kind_label(), color)
		_cell("%.2f" % event.distance_m, color)
		_cell("--" if is_nan(event.loss_db) else "%.3f" % event.loss_db, color)
		_cell("--" if is_nan(event.reflectance_db) else "%.1f" % event.reflectance_db, color)
		_cell("%.3f" % event.cumulative_db, color)


func _cell(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.modulate = color
	_table.add_child(label)


func _update_summary() -> void:
	if trace == null or measuring:
		return
	var problems := verdict()
	var head := "Fiber %.2f m   link loss %s   budget %.2f dB   " % [
		trace.fiber_length_m, "--" if is_nan(trace.link_loss_db) else "%.2f dB" % trace.link_loss_db, budget_db]
	if problems.is_empty():
		_summary.text = head + "PASS"
		_summary.modulate = Color(0.45, 1.0, 0.5)
	else:
		_summary.text = head + "FAIL: " + "; ".join(problems)
		_summary.modulate = Color(1.0, 0.5, 0.4)


func _update_cursor_label() -> void:
	if trace == null:
		_cursor_label.text = ""
		return
	var parts := PackedStringArray()
	for entry in [["A", _plot.cursor_a], ["B", _plot.cursor_b]]:
		if not is_nan(entry[1]):
			parts.append("%s %.2f m  %.2f dB" % [entry[0], entry[1], trace.level_at(entry[1])])
	if not is_nan(_plot.cursor_a) and not is_nan(_plot.cursor_b):
		var span := absf(_plot.cursor_b - _plot.cursor_a)
		var delta := trace.level_at(minf(_plot.cursor_a, _plot.cursor_b)) - trace.level_at(maxf(_plot.cursor_a, _plot.cursor_b))
		parts.append("A–B %.2f m  %.3f dB  (%.2f dB/km)" % [span, delta, delta / span * 1000.0 if span > 0.0 else 0.0])
	_cursor_label.text = "   ".join(parts) if not parts.is_empty() else "Click the trace to place cursors A (LMB) and B (RMB)."
	_cursor_label.text += "     %d nm  %d ns  %d s  range %d m  floor %.1f dB" % [
		settings.wavelength_nm, settings.pulse_width_ns, settings.averaging_s, trace.range_m, trace.noise_floor_db]
