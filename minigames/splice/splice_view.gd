class_name SpliceView
extends Control
## The splicer's workspace for the current SpliceJob step, drawn and operated with the mouse.
##   Strip   drag the stripper to the fiber tip, steadily (too fast snaps the fiber)
##   Clean   wipe across the bare glass with the alcohol pad (drag left↔right)
##   Cleave  click when the marker is in the green zone
##   Align   drag up/down in the X and Y camera views to line up the cores
##   Arc     hold the mouse button for the arc; release inside the ideal window

signal message(text: String)

const STRIP_MAX_SPEED := 900.0  ## px/s
const CLEAVE_SPEED := 2.4  ## rad/s of the timing marker
const CLEAVE_ZONE := 0.12
const PX_PER_UM := 4.0
## Drag pixels per µm of core movement (fine control).
const DRAG_PX_PER_UM := 16.0
const WIPE_SPAN := 0.55
const BG := Color(0.05, 0.06, 0.08)
const GLASS := Color(0.75, 0.85, 0.95)
const CORE := Color(0.95, 0.95, 1.0)
const ZONE := Color(0.25, 0.85, 0.35)

var job: SpliceJob
var color_left := Color.BLUE
var color_right := Color.BLUE

var strip_progress := 0.0
var strip_speed := 0.0
var cleave_marker := 0.0
var arc_holding := false
var arc_time := 0.0

var _dragging := false
var _last_mouse := Vector2.ZERO
var _last_time_us := 0
var _wipe_min := INF
var _wipe_max := -INF
var _cleave_phase := 0.0
var _dirt: PackedVector2Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 24:
		_dirt.append(Vector2(rng.randf_range(0.2, 0.8), rng.randf_range(-1.0, 1.0)))


func _process(delta: float) -> void:
	if job == null:
		return
	if _in_cleave_step() and is_nan(job.current_cleave_deg()):
		_cleave_phase += delta * CLEAVE_SPEED
		cleave_marker = sin(_cleave_phase)
	if arc_holding:
		arc_time += delta
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if job == null:
		return
	var button := event as InputEventMouseButton
	var motion := event as InputEventMouseMotion
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_press(button.position)
		else:
			_release()
		accept_event()
	elif motion and _dragging:
		_drag(motion.position)
		accept_event()


func _press(at: Vector2) -> void:
	_dragging = true
	_last_mouse = at
	_last_time_us = Time.get_ticks_usec()
	match job.step:
		SpliceJob.Step.CLEAN:
			_wipe_min = at.x
			_wipe_max = at.x
		SpliceJob.Step.CLEAVE_LEFT, SpliceJob.Step.CLEAVE_RIGHT:
			if is_nan(job.current_cleave_deg()):
				var angle := job.cleave(cleave_marker)
				message.emit("Cleave angle %.2f°%s" % [angle,
						"  (over %.1f°: re-cleave recommended)" % SpliceJob.CLEAVE_LIMIT_DEG if angle > SpliceJob.CLEAVE_LIMIT_DEG else ""])
		SpliceJob.Step.ARC:
			arc_holding = true
			arc_time = 0.0


func _release() -> void:
	_dragging = false
	match job.step:
		SpliceJob.Step.CLEAN:
			if _wipe_max - _wipe_min >= size.x * WIPE_SPAN:
				job.wipe()
				message.emit("Wiped: fiber %d%% clean" % roundi(job.cleanliness * 100.0))
		SpliceJob.Step.ARC:
			if arc_holding:
				arc_holding = false
				job.arc(arc_time)
				message.emit("Arc %.2f s. Splicer estimate %.2f dB" % [arc_time, job.estimated_loss_db])


func _drag(at: Vector2) -> void:
	var now := Time.get_ticks_usec()
	var dt := maxf((now - _last_time_us) / 1e6, 1e-4)
	var delta := at - _last_mouse
	_last_mouse = at
	_last_time_us = now
	match job.step:
		SpliceJob.Step.STRIP:
			var dx := maxf(delta.x, 0.0)
			strip_speed = lerpf(strip_speed, dx / dt, 0.35)
			if strip_speed > STRIP_MAX_SPEED:
				job.snap_fiber()
				strip_progress = 0.0
				strip_speed = 0.0
				_dragging = false
				message.emit("Too fast: the fiber snapped. Strip again, slower.")
				return
			advance_strip(dx / (size.x * 0.7))
		SpliceJob.Step.CLEAN:
			_wipe_min = minf(_wipe_min, at.x)
			_wipe_max = maxf(_wipe_max, at.x)
		SpliceJob.Step.ALIGN:
			var axis := Vector2(-delta.y / DRAG_PX_PER_UM, 0.0) if at.x < size.x * 0.5 \
					else Vector2(0.0, -delta.y / DRAG_PX_PER_UM)
			job.move_core(axis)


## Moves the stripper along by a fraction of the strip length.
func advance_strip(fraction: float) -> void:
	strip_progress = clampf(strip_progress + fraction, 0.0, 1.0)
	if strip_progress >= 1.0 and job.step == SpliceJob.Step.STRIP:
		job.complete_strip()


func reset_for_step() -> void:
	strip_progress = 0.0
	strip_speed = 0.0
	arc_holding = false
	_dragging = false


func _in_cleave_step() -> bool:
	return job.step == SpliceJob.Step.CLEAVE_LEFT or job.step == SpliceJob.Step.CLEAVE_RIGHT


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if job == null:
		return
	match job.step:
		SpliceJob.Step.STRIP:
			_draw_strip()
		SpliceJob.Step.CLEAN:
			_draw_clean()
		SpliceJob.Step.CLEAVE_LEFT, SpliceJob.Step.CLEAVE_RIGHT:
			_draw_cleave()
		SpliceJob.Step.ALIGN:
			_draw_align()
		SpliceJob.Step.ARC:
			_draw_arc()
		_:
			_draw_joined()


func _draw_strip() -> void:
	var y := size.y * 0.5
	var x0 := size.x * 0.15
	var x1 := size.x * 0.85
	var tool_x := lerpf(x0, x1, strip_progress)
	draw_line(Vector2(0, y), Vector2(x0, y), color_left, 16.0)
	draw_line(Vector2(x0, y), Vector2(tool_x, y), GLASS, 4.0)
	draw_line(Vector2(tool_x, y), Vector2(x1, y), color_left, 16.0)
	draw_rect(Rect2(tool_x - 14, y - 40, 28, 80), Color(0.85, 0.2, 0.2))
	draw_rect(Rect2(tool_x - 14, y - 40, 28, 80), Color.BLACK, false, 2.0)
	# Speed gauge.
	var gauge := Rect2(size.x * 0.25, 30, size.x * 0.5, 16)
	draw_rect(gauge, Color(1, 1, 1, 0.1))
	var fill := clampf(strip_speed / STRIP_MAX_SPEED, 0.0, 1.0)
	draw_rect(Rect2(gauge.position, Vector2(gauge.size.x * fill, gauge.size.y)),
			ZONE.lerp(Color.RED, fill))
	_label(Vector2(gauge.position.x, gauge.position.y - 6), "pull speed")


func _draw_clean() -> void:
	var y := size.y * 0.5
	draw_line(Vector2(0, y), Vector2(size.x * 0.15, y), color_left, 16.0)
	draw_line(Vector2(size.x * 0.15, y), Vector2(size.x * 0.85, y), GLASS, 4.0)
	var specks := roundi((1.0 - job.cleanliness) * _dirt.size())
	for i in specks:
		var p := Vector2(_dirt[i].x * size.x, y + _dirt[i].y * 6.0)
		draw_circle(p, 2.5, Color(0.55, 0.45, 0.3))
	if _dragging:
		draw_rect(Rect2(_last_mouse - Vector2(30, 24), Vector2(60, 48)), Color(0.95, 0.95, 0.9, 0.85))
	_label(Vector2(20, 40), "Clean %d%%  (drag the pad across the glass)" % roundi(job.cleanliness * 100.0))


func _draw_cleave() -> void:
	var y := size.y * 0.42
	var tip := size.x * 0.6
	var color := color_left if job.step == SpliceJob.Step.CLEAVE_LEFT else color_right
	draw_line(Vector2(0, y), Vector2(size.x * 0.3, y), color, 16.0)
	var angle := job.current_cleave_deg()
	if is_nan(angle):
		draw_line(Vector2(size.x * 0.3, y), Vector2(size.x * 0.8, y), GLASS, 6.0)
		draw_line(Vector2(tip, y - 60), Vector2(tip, y - 8), Color(0.8, 0.8, 0.85), 3.0)
	else:
		# End face, tilt exaggerated ×10 so it is visible.
		var tilt := tan(deg_to_rad(angle * 10.0)) * 6.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(size.x * 0.3, y - 3), Vector2(tip + tilt, y - 3), Vector2(tip - tilt, y + 3), Vector2(size.x * 0.3, y + 3)]), GLASS)
		_label(Vector2(tip + 30, y + 6), "%.2f°" % angle)
	var bar := Rect2(size.x * 0.2, size.y * 0.75, size.x * 0.6, 22)
	draw_rect(bar, Color(1, 1, 1, 0.1))
	var zone_w := bar.size.x * CLEAVE_ZONE * 0.5
	draw_rect(Rect2(bar.get_center().x - zone_w, bar.position.y, zone_w * 2.0, bar.size.y), ZONE * Color(1, 1, 1, 0.6))
	var mx := bar.get_center().x + cleave_marker * bar.size.x * 0.5
	draw_line(Vector2(mx, bar.position.y - 6), Vector2(mx, bar.end.y + 6), Color.WHITE, 3.0)
	_label(Vector2(bar.position.x, bar.position.y - 8), "click inside the green zone to cleave")


func _draw_align() -> void:
	for view in 2:
		var panel := Rect2(view * size.x * 0.5 + 10, 40, size.x * 0.5 - 20, size.y - 60)
		draw_rect(panel, Color(0.1, 0.12, 0.14))
		draw_rect(panel, Color(1, 1, 1, 0.2), false)
		var cy := panel.get_center().y
		var mid := panel.get_center().x
		var offset := (job.offset_um.x if view == 0 else job.offset_um.y) * PX_PER_UM
		var cladding := 62.5 * PX_PER_UM * 0.5
		var core := 4.6 * PX_PER_UM
		draw_rect(Rect2(panel.position.x, cy - cladding, mid - panel.position.x - 4, cladding * 2), Color(0.45, 0.5, 0.55))
		draw_rect(Rect2(mid + 4, cy - cladding + offset, panel.end.x - mid - 4, cladding * 2), Color(0.45, 0.5, 0.55))
		draw_rect(Rect2(panel.position.x, cy - core, mid - panel.position.x - 4, core * 2), CORE)
		draw_rect(Rect2(mid + 4, cy - core + offset, panel.end.x - mid - 4, core * 2), CORE)
		_label(panel.position + Vector2(8, 18), "%s view   offset %.2f µm" % ["X" if view == 0 else "Y",
				job.offset_um.x if view == 0 else job.offset_um.y])


func _draw_arc() -> void:
	var y := size.y * 0.45
	var mid := size.x * 0.5
	draw_line(Vector2(0, y), Vector2(mid - 2, y), GLASS, 6.0)
	draw_line(Vector2(mid + 2, y), Vector2(size.x, y), GLASS, 6.0)
	draw_line(Vector2(mid, y - 120), Vector2(mid, y - 30), Color(0.6, 0.6, 0.65), 6.0)
	draw_line(Vector2(mid, y + 30), Vector2(mid, y + 120), Color(0.6, 0.6, 0.65), 6.0)
	if arc_holding:
		var glow := 12.0 + 8.0 * sin(arc_time * 40.0)
		draw_circle(Vector2(mid, y), glow + 14.0, Color(0.6, 0.7, 1.0, 0.3))
		draw_circle(Vector2(mid, y), glow, Color(0.9, 0.95, 1.0, 0.9))
	var bar := Rect2(size.x * 0.2, size.y * 0.8, size.x * 0.6, 22)
	var span_s := 3.0  # seconds across the bar
	draw_rect(bar, Color(1, 1, 1, 0.1))
	draw_rect(Rect2(bar.position.x + bar.size.x * SpliceJob.ARC_IDEAL_S.x / span_s, bar.position.y,
			bar.size.x * (SpliceJob.ARC_IDEAL_S.y - SpliceJob.ARC_IDEAL_S.x) / span_s, bar.size.y), ZONE * Color(1, 1, 1, 0.6))
	var fill := clampf(arc_time / span_s, 0.0, 1.0) if arc_holding else 0.0
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), Color(0.7, 0.8, 1.0, 0.8))
	_label(Vector2(bar.position.x, bar.position.y - 8), "hold the mouse button to arc, release in the green window")


func _draw_joined() -> void:
	var y := size.y * 0.45
	draw_line(Vector2(0, y), Vector2(size.x * 0.2, y), color_left, 16.0)
	draw_line(Vector2(size.x * 0.2, y), Vector2(size.x * 0.8, y), GLASS, 6.0)
	draw_line(Vector2(size.x * 0.8, y), Vector2(size.x, y), color_right, 16.0)
	if job.step == SpliceJob.Step.DONE and job.protected:
		draw_rect(Rect2(size.x * 0.3, y - 14, size.x * 0.4, 28), Color(0.9, 0.9, 0.85, 0.85))
	if not is_nan(job.estimated_loss_db):
		_label(Vector2(size.x * 0.5 - 90, y + 60), "Splicer estimate: %.2f dB" % job.estimated_loss_db)


func _label(at: Vector2, text: String) -> void:
	draw_string(get_theme_default_font(), at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.85))
