class_name Crosshair
extends Control
## Centre-screen crosshair. Grows and turns accent-coloured while an interactable is targeted.

@export var color := Color(1, 1, 1, 0.85)
@export var highlight_color := Color(1.0, 0.8, 0.2)

var highlighted := false:
	set(value):
		if value != highlighted:
			highlighted = value
			queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var tint := highlight_color if highlighted else color
	var radius := 6.0 if highlighted else 2.5
	draw_circle(center, radius + 1.0, Color(0, 0, 0, 0.5), false, 1.0, true)
	if highlighted:
		draw_circle(center, radius, tint, false, 2.0, true)
	else:
		draw_circle(center, radius, tint, true, -1.0, true)
