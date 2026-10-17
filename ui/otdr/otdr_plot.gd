class_name OtdrPlot
extends Control
## OTDR trace display: dB against distance with event markers and two cursors.
##   LMB  place cursor A    RMB  place cursor B    Wheel  zoom distance (Ctrl: zoom dB)
##   Middle drag  pan

signal cursors_changed

const BG := Color(0.03, 0.05, 0.07)
const GRID := Color(1, 1, 1, 0.08)
const AXIS_TEXT := Color(1, 1, 1, 0.55)
const TRACE := Color(0.35, 1.0, 0.45)
const FLOOR := Color(1.0, 0.4, 0.3, 0.5)
const EVENT := Color(1.0, 0.85, 0.3, 0.6)
const CURSOR_A := Color(1.0, 0.9, 0.2)
const CURSOR_B := Color(0.3, 0.85, 1.0)
const MARGIN := Vector2(54, 22)

var trace: OtdrTrace:
	set(value):
		var first := trace == null
		trace = value
		if first:
			fit_view()
		queue_redraw()

## Visible distance range (m) and dB range (top, bottom).
var view_x := Vector2(0.0, 100.0)
var view_y := Vector2(5.0, -30.0)
var cursor_a := NAN
var cursor_b := NAN

var _panning := false


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func fit_view() -> void:
	if trace == null:
		return
	var end := trace.end_event()
	var far := end.distance_m if end else trace.range_m
	view_x = Vector2(0.0, minf(trace.range_m, far * 1.12 + 2.0))
	var top := -INF
	for i in range(0, trace.index_at(view_x.y) + 1):
		top = maxf(top, trace.samples[i])
	view_y = Vector2(ceilf(top + 2.0), floorf(trace.noise_floor_db - 4.0))
	queue_redraw()


func plot_rect() -> Rect2:
	return Rect2(MARGIN, size - MARGIN * Vector2(1.3, 2.0))


func distance_at_x(x: float) -> float:
	var r := plot_rect()
	return lerpf(view_x.x, view_x.y, (x - r.position.x) / r.size.x)


func to_screen(distance: float, db: float) -> Vector2:
	var r := plot_rect()
	return Vector2(
		r.position.x + (distance - view_x.x) / (view_x.y - view_x.x) * r.size.x,
		r.position.y + (view_y.x - db) / (view_y.x - view_y.y) * r.size.y)


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.pressed:
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				cursor_a = clampf(distance_at_x(button.position.x), 0.0, trace.range_m if trace else 0.0)
				cursors_changed.emit()
			MOUSE_BUTTON_RIGHT:
				cursor_b = clampf(distance_at_x(button.position.x), 0.0, trace.range_m if trace else 0.0)
				cursors_changed.emit()
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(button, 0.8)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(button, 1.25)
			MOUSE_BUTTON_MIDDLE:
				_panning = true
		queue_redraw()
		accept_event()
	elif button and not button.pressed and button.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = false
	elif event is InputEventMouseMotion and _panning:
		var r := plot_rect()
		var motion: Vector2 = event.relative
		var dx := -motion.x / r.size.x * (view_x.y - view_x.x)
		var dy := motion.y / r.size.y * (view_y.x - view_y.y)
		view_x += Vector2(dx, dx)
		view_y += Vector2(dy, dy)
		queue_redraw()
		accept_event()


func _zoom(button: InputEventMouseButton, factor: float) -> void:
	if button.ctrl_pressed:
		var r := plot_rect()
		var t := clampf((button.position.y - r.position.y) / r.size.y, 0.0, 1.0)
		var pivot := lerpf(view_y.x, view_y.y, t)
		view_y = Vector2(pivot + (view_y.x - pivot) * factor, pivot + (view_y.y - pivot) * factor)
	else:
		var pivot := distance_at_x(button.position.x)
		view_x = Vector2(pivot + (view_x.x - pivot) * factor, pivot + (view_x.y - pivot) * factor)
		view_x.x = maxf(view_x.x, -1.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var r := plot_rect()
	var font := get_theme_default_font()
	_draw_grid(r, font)
	if trace == null:
		draw_string(font, r.position + Vector2(10, 24), "No measurement", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		return

	# Noise floor.
	var floor_y := to_screen(0.0, trace.noise_floor_db).y
	if floor_y > r.position.y and floor_y < r.end.y:
		draw_dashed_line(Vector2(r.position.x, floor_y), Vector2(r.end.x, floor_y), FLOOR, 1.0, 6.0)

	# Trace: one min/max column per pixel so noise reads as fuzz, not aliasing.
	var top_points := PackedVector2Array()
	var columns := int(r.size.x)
	for col in columns:
		var d0 := lerpf(view_x.x, view_x.y, float(col) / columns)
		var d1 := lerpf(view_x.x, view_x.y, float(col + 1) / columns)
		if d1 < 0.0 or d0 > trace.range_m:
			continue
		var i0 := trace.index_at(d0)
		var i1 := maxi(i0, trace.index_at(d1))
		var low := INF
		var high := -INF
		for i in range(i0, i1 + 1):
			low = minf(low, trace.samples[i])
			high = maxf(high, trace.samples[i])
		var x := r.position.x + col
		var y_high := clampf(to_screen(0.0, high).y, r.position.y, r.end.y)
		var y_low := clampf(to_screen(0.0, low).y, r.position.y, r.end.y)
		if y_low - y_high > 1.0:
			draw_line(Vector2(x, y_high), Vector2(x, y_low), TRACE * Color(1, 1, 1, 0.6))
		top_points.append(Vector2(x, y_high))
	if top_points.size() >= 2:
		draw_polyline(top_points, TRACE, 1.5, true)

	# Events.
	for event in trace.events:
		var x := to_screen(event.distance_m, 0.0).x
		if x < r.position.x or x > r.end.x:
			continue
		draw_dashed_line(Vector2(x, r.position.y), Vector2(x, r.end.y), EVENT, 1.0, 4.0)
		draw_string(font, Vector2(x + 3, r.position.y + 13), str(event.number), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, EVENT)

	_draw_cursor(cursor_a, "A", CURSOR_A, r, font)
	_draw_cursor(cursor_b, "B", CURSOR_B, r, font)


func _draw_cursor(distance: float, label: String, color: Color, r: Rect2, font: Font) -> void:
	if is_nan(distance):
		return
	var x := to_screen(distance, 0.0).x
	if x < r.position.x or x > r.end.x:
		return
	draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), color, 1.5)
	draw_string(font, Vector2(x + 3, r.end.y - 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)


func _draw_grid(r: Rect2, font: Font) -> void:
	var x_step := _nice_step((view_x.y - view_x.x) / 8.0)
	var d := ceilf(view_x.x / x_step) * x_step
	while d <= view_x.y:
		var x := to_screen(d, 0.0).x
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), GRID)
		draw_string(font, Vector2(x - 20, r.end.y + 16), _format_distance(d, x_step), HORIZONTAL_ALIGNMENT_CENTER, 40, 11, AXIS_TEXT)
		d += x_step
	var y_step := _nice_step((view_y.x - view_y.y) / 6.0)
	var db := ceilf(view_y.y / y_step) * y_step
	while db <= view_y.x:
		var y := to_screen(0.0, db).y
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), GRID)
		draw_string(font, Vector2(4, y + 4), "%.1f" % db if y_step < 1.0 else "%d" % roundi(db), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, AXIS_TEXT)
		db += y_step
	draw_rect(r, Color(1, 1, 1, 0.25), false)
	draw_string(font, Vector2(4, 14), "dB", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, AXIS_TEXT)
	draw_string(font, Vector2(r.end.x - 20, size.y - 2), "m", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, AXIS_TEXT)


static func _nice_step(raw: float) -> float:
	var magnitude := pow(10.0, floorf(log(maxf(raw, 1e-6)) / log(10.0)))
	for multiple in [1.0, 2.0, 5.0, 10.0]:
		if raw <= multiple * magnitude:
			return multiple * magnitude
	return 10.0 * magnitude


static func _format_distance(d: float, step: float) -> String:
	return ("%.1f" % d) if step < 1.0 else ("%d" % roundi(d))
