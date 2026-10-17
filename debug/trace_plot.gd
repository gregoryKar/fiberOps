class_name TracePlot
extends Control
## Loss budget plot of a StrandTrace: cumulative loss (dB, downwards) against distance.
## Noise-free and one-way. The real OTDR trace comes in M7.

const BG := Color(0.05, 0.07, 0.1, 0.9)
const GRID := Color(1, 1, 1, 0.1)
const LINE := Color(1.0, 0.85, 0.2)
const MARGIN := Vector2(46, 18)

var trace: StrandTrace:
	set(value):
		trace = value
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var font := get_theme_default_font()
	var plot := Rect2(MARGIN, size - MARGIN * 2.0)
	if trace == null or trace.length_m <= 0.0:
		draw_string(font, plot.position + Vector2(0, 20), "no fiber here", HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		return

	var max_db := ceilf(maxf(trace.total_loss_db(), 0.5) * 2.0) / 2.0
	var to_screen := func(distance: float, loss: float) -> Vector2:
		return plot.position + Vector2(distance / trace.length_m * plot.size.x, loss / max_db * plot.size.y)

	var db_step := 0.5 if max_db <= 3.0 else (1.0 if max_db <= 8.0 else 2.0)
	var db := 0.0
	while db <= max_db + 1e-6:
		var y: float = to_screen.call(0.0, db).y
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), GRID)
		draw_string(font, Vector2(4, y + 5), "%.1f" % db, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		db += db_step
	draw_string(font, Vector2(plot.position.x, size.y - 3), "0 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	draw_string(font, Vector2(plot.end.x - 60, size.y - 3), "%.1f m" % trace.length_m, HORIZONTAL_ALIGNMENT_RIGHT, 60, 11)
	draw_string(font, Vector2(4, 12), "dB", HORIZONTAL_ALIGNMENT_LEFT, -1, 11)

	var points := PackedVector2Array([to_screen.call(0.0, 0.0)])
	var level := 0.0
	var events := trace.events.duplicate()
	events.sort_custom(func(a: StrandTrace.Event, b: StrandTrace.Event) -> bool: return a.distance_m < b.distance_m)
	for event: StrandTrace.Event in events:
		points.append(to_screen.call(event.distance_m, level + _attenuation_until(event.distance_m)))
		level += event.loss_db
		points.append(to_screen.call(event.distance_m, level + _attenuation_until(event.distance_m)))
		var x: float = to_screen.call(event.distance_m, 0.0).x
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), NetworkView.EVENT_COLORS[event.kind] * Color(1, 1, 1, 0.35))
	draw_polyline(points, LINE, 2.0, true)


func _attenuation_until(distance: float) -> float:
	var total := 0.0
	for span in trace.spans:
		var covered := clampf(distance - span.start_m, 0.0, span.length_m)
		total += span.attenuation_db_per_km * covered * 0.001
	return total
