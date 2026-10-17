class_name Cable
extends Resource
## A routed multi-fiber cable between two node ports. Its geometry (and therefore its bend
## loss) comes from the waypoints and corner radius; see CablePath.

@export var id: StringName
@export var spec_id := &"g657a1"
@export var fiber_count := 12
@export var node_a: StringName
@export var port_a := 0
@export var node_b: StringName
@export var port_b := 0
## World-space route from end A to end B, including both end points.
@export var waypoints := PackedVector3Array():
	set(value):
		waypoints = value
		_route = null
## Requested fillet radius at each waypoint corner, in metres.
@export var corner_radius := 0.03:
	set(value):
		corner_radius = value
		_route = null

var _route: CablePath


## Cached geometry; rebuilt after waypoints or corner_radius change.
func route() -> CablePath:
	if _route == null:
		_route = CablePath.build(waypoints, corner_radius)
	return _route


func spec() -> FiberSpec:
	return FiberSpec.get_spec(spec_id)


func is_end_a(node_id: StringName, port: int) -> bool:
	return node_a == node_id and port_a == port


func attaches(node_id: StringName, port: int) -> bool:
	return is_end_a(node_id, port) or (node_b == node_id and port_b == port)


func touches_node(node_id: StringName) -> bool:
	return node_a == node_id or node_b == node_id
