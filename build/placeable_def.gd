class_name PlaceableDef
extends Resource
## A piece of hardware the build tool can place, and how it looks in the world.
## Definitions live in build/placeables/*.tres; CATALOG sets their order in the build menu.

enum Mount { WALL }

const CATALOG: Array[String] = [
	"res://build/placeables/floorbox.tres",
	"res://build/placeables/splice_closure.tres",
	"res://build/placeables/outlet.tres",
	"res://build/placeables/bep.tres",
	"res://build/placeables/splitter.tres",
]

static var _all: Array[PlaceableDef] = []

@export var id: StringName
@export var display_name := ""
@export var node_type := NetNode.Type.FLOORBOX
@export var port_count := 4
## Box size: x = width, y = height, z = depth out of the wall.
@export var size := Vector3(0.3, 0.35, 0.08)
@export var color := Color.WHITE
@export var mount := Mount.WALL


## Ports sit on the bottom edge (first half, rounded up) and the top edge (the rest),
## spread across the width. Cables leave a port straight down or up.
func port_local_position(port: int) -> Vector3:
	var bottom := _bottom_port_count()
	var on_bottom := port < bottom
	var count := bottom if on_bottom else port_count - bottom
	var slot := port if on_bottom else port - bottom
	var x := ((slot + 0.5) / count - 0.5) * size.x * 0.8
	return Vector3(x, (-0.5 if on_bottom else 0.5) * size.y, 0.0)


func port_exit_direction(port: int) -> Vector3:
	return Vector3.DOWN if port < _bottom_port_count() else Vector3.UP


func _bottom_port_count() -> int:
	return ceili(port_count / 2.0)


static func all() -> Array[PlaceableDef]:
	if _all.is_empty():
		for path in CATALOG:
			_all.append(load(path))
	return _all


static func for_node_type(type: NetNode.Type) -> PlaceableDef:
	for def in all():
		if def.node_type == type:
			return def
	return null
