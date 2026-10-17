class_name FiberNetwork
extends Resource
## The fiber network of one building level: hardware nodes and the cables between their ports.
## Pure data (no scene dependency) so it can be saved, traced and tested headless.

@export var level_id: StringName
@export var nodes: Dictionary[StringName, NetNode] = {}
@export var cables: Dictionary[StringName, Cable] = {}
@export var next_id := 1


func add_node(type: NetNode.Type, xform := Transform3D.IDENTITY, port_count := -1) -> NetNode:
	var node := NetNode.new()
	node.id = _new_id("node")
	node.type = type
	node.transform = xform
	node.port_count = port_count if port_count > 0 else NetNode.DEFAULT_PORT_COUNT[type]
	nodes[node.id] = node
	emit_changed()
	return node


## Removes the node and every cable attached to it.
func remove_node(node_id: StringName) -> void:
	if not nodes.has(node_id):
		return
	for cable_id in cables.keys():
		if cables[cable_id].touches_node(node_id):
			remove_cable(cable_id)
	nodes.erase(node_id)
	emit_changed()


## Adds a cable between two free ports. Returns null if a node is missing or a port is
## out of range or already occupied.
func add_cable(from_node: StringName, from_port: int, to_node: StringName, to_port: int,
		waypoints: PackedVector3Array, spec_id := &"g657a1", fiber_count := 12,
		corner_radius := 0.03) -> Cable:
	for end in [[from_node, from_port], [to_node, to_port]]:
		var node: NetNode = nodes.get(end[0])
		if node == null or end[1] < 0 or end[1] >= node.port_count:
			push_error("Invalid cable end %s:%d" % end)
			return null
		if cable_at(end[0], end[1]) != null:
			return null
	if from_node == to_node and from_port == to_port:
		return null

	var cable := Cable.new()
	cable.id = _new_id("cable")
	cable.spec_id = spec_id
	cable.fiber_count = fiber_count
	cable.node_a = from_node
	cable.port_a = from_port
	cable.node_b = to_node
	cable.port_b = to_port
	cable.waypoints = waypoints
	cable.corner_radius = corner_radius
	cables[cable.id] = cable
	emit_changed()
	return cable


## Removes the cable. Splices on its two ports go with it, as they would if it were cut out.
func remove_cable(cable_id: StringName) -> void:
	var cable: Cable = cables.get(cable_id)
	if cable == null:
		return
	for end in [[cable.node_a, cable.port_a], [cable.node_b, cable.port_b]]:
		var node: NetNode = nodes.get(end[0])
		if node:
			node.remove_links_at_port(end[1])
	cables.erase(cable_id)
	emit_changed()


func cable_at(node_id: StringName, port: int) -> Cable:
	for cable: Cable in cables.values():
		if cable.attaches(node_id, port):
			return cable
	return null


func get_node_by_id(node_id: StringName) -> NetNode:
	return nodes.get(node_id)


func _new_id(prefix: String) -> StringName:
	var new_id := StringName("%s_%d" % [prefix, next_id])
	next_id += 1
	return new_id
