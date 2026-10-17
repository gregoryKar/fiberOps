class_name TraceOverlay
extends CanvasLayer
## Debug panel: traces a chosen launch point, lists the events and plots the loss budget.
##   F1  next launch point     F2  next wavelength     F3  next splitter branch

## Bends below this are left out of the table (their loss still counts in the total).
const MIN_LISTED_BEND_DB := 0.001

## Each launch: {"label": String, "node": StringName, "port": int, "fiber": int}
var launches: Array[Dictionary] = []
var network: FiberNetwork
var view: NetworkView

var _launch_index := 0
var _wavelength_index := 1
var _branch_index := 0
var _title: Label
var _table: Label
var _plot: TracePlot


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.14, 0.85)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override(&"panel", style)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	panel.add_child(box)
	_title = Label.new()
	box.add_child(_title)
	_plot = TracePlot.new()
	_plot.custom_minimum_size = Vector2(460, 170)
	box.add_child(_plot)
	_table = Label.new()
	_table.add_theme_font_override(&"font", _monospace())
	_table.add_theme_font_size_override(&"font_size", 13)
	box.add_child(_table)
	var help := Label.new()
	help.text = "F1 next fiber   F2 wavelength   F3 splitter branch"
	help.modulate = Color(1, 1, 1, 0.6)
	box.add_child(help)


func setup(target_network: FiberNetwork, target_view: NetworkView, launch_points: Array[Dictionary]) -> void:
	network = target_network
	view = target_view
	launches = launch_points
	refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F1:
			_launch_index = (_launch_index + 1) % maxi(launches.size(), 1)
			_branch_index = 0
		KEY_F2:
			_wavelength_index = (_wavelength_index + 1) % FiberSpec.WAVELENGTHS.size()
		KEY_F3:
			_branch_index += 1
		_:
			return
	refresh()
	get_viewport().set_input_as_handled()


func current_trace() -> StrandTrace:
	if network == null or launches.is_empty():
		return null
	var launch := launches[_launch_index]
	var traces := StrandTracer.trace(network, launch["node"], launch["port"], launch["fiber"],
			FiberSpec.WAVELENGTHS[_wavelength_index])
	if traces.is_empty():
		return null
	_branch_index %= traces.size()
	return traces[_branch_index]


func refresh() -> void:
	var trace := current_trace()
	if view:
		view.show_trace(trace)
	_plot.trace = trace
	if trace == null:
		_title.text = "No launch points"
		_table.text = ""
		return
	var launch := launches[_launch_index]
	_title.text = "[%d/%d] %s   @ %d nm" % [_launch_index + 1, launches.size(), launch["label"], trace.wavelength_nm]
	_table.text = format_table(trace)


static func format_table(trace: StrandTrace) -> String:
	var lines := PackedStringArray()
	lines.append("%-10s %9s %9s %9s" % ["event", "dist m", "loss dB", "refl dB"])
	var hidden := 0
	for event in trace.events:
		if event.kind == StrandTrace.EventKind.BEND and event.loss_db < MIN_LISTED_BEND_DB:
			hidden += 1
			continue
		var event_name: String = NetworkView.EVENT_NAMES[event.kind]
		if event.kind == StrandTrace.EventKind.BEND:
			event_name += " %.0fmm" % (event.radius_m * 1000.0)
		var refl := "%.1f" % event.reflectance_db if event.is_reflective() else "-"
		lines.append("%-10s %9.2f %9.3f %9s" % [event_name, event.distance_m, event.loss_db, refl])
	var fiber_loss := 0.0
	for span in trace.spans:
		fiber_loss += span.attenuation_db_per_km * span.length_m * 0.001
	if hidden > 0:
		lines.append("(%d gentle bends < %.3f dB not listed)" % [hidden, MIN_LISTED_BEND_DB])
	lines.append("fiber attenuation          %9.3f" % fiber_loss)
	lines.append("TOTAL %-8s %9.2f %9.3f" % [StrandTrace.EndKind.keys()[trace.end_kind], trace.length_m, trace.total_loss_db()])
	return "\n".join(lines)


static func _monospace() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Courier New", "monospace"])
	return font
