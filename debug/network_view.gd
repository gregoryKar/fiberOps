class_name NetworkView
extends Node3D
## Debug renderer for a FiberNetwork: boxes for nodes, tubes for cables (coloured by bend
## radius), and markers for the events of one StrandTrace.

const NODE_SIZES: Dictionary[int, Vector3] = {
	NetNode.Type.BEP: Vector3(0.4, 0.5, 0.12),
	NetNode.Type.RISER_STUB: Vector3(0.2, 0.2, 0.1),
	NetNode.Type.FLOORBOX: Vector3(0.3, 0.35, 0.08),
	NetNode.Type.SPLICE_CLOSURE: Vector3(0.35, 0.15, 0.12),
	NetNode.Type.SPLITTER: Vector3(0.15, 0.1, 0.05),
	NetNode.Type.OUTLET: Vector3(0.08, 0.08, 0.03),
}
const NODE_COLORS: Dictionary[int, Color] = {
	NetNode.Type.BEP: Color(0.25, 0.35, 0.6),
	NetNode.Type.RISER_STUB: Color(0.5, 0.5, 0.5),
	NetNode.Type.FLOORBOX: Color(0.85, 0.85, 0.8),
	NetNode.Type.SPLICE_CLOSURE: Color(0.15, 0.15, 0.15),
	NetNode.Type.SPLITTER: Color(0.3, 0.6, 0.9),
	NetNode.Type.OUTLET: Color(0.95, 0.95, 0.95),
}
const EVENT_COLORS: Dictionary[int, Color] = {
	StrandTrace.EventKind.SPLICE: Color(0.3, 0.8, 1.0),
	StrandTrace.EventKind.CONNECTOR: Color(0.8, 0.4, 1.0),
	StrandTrace.EventKind.SPLITTER: Color(0.3, 0.5, 1.0),
	StrandTrace.EventKind.BEND: Color(1.0, 0.5, 0.1),
	StrandTrace.EventKind.OPEN_END: Color(1.0, 1.0, 1.0),
	StrandTrace.EventKind.BREAK: Color(1.0, 0.1, 0.1),
}
const EVENT_NAMES: Dictionary[int, String] = {
	StrandTrace.EventKind.SPLICE: "Splice",
	StrandTrace.EventKind.CONNECTOR: "Connector",
	StrandTrace.EventKind.SPLITTER: "Splitter",
	StrandTrace.EventKind.BEND: "Bend",
	StrandTrace.EventKind.OPEN_END: "End",
	StrandTrace.EventKind.BREAK: "BREAK",
}
## Only bends at least this lossy get a marker.
const MIN_MARKED_BEND_DB := 0.01

@export var cable_radius := 0.012
@export var sample_step := 0.05

var network: FiberNetwork:
	set(value):
		network = value
		rebuild()

var _static_root: Node3D
var _marker_root: Node3D


func rebuild() -> void:
	for root in [_static_root, _marker_root]:
		if root:
			root.queue_free()
	_static_root = _new_root("Network")
	_marker_root = _new_root("Markers")
	if network == null:
		return
	for node: NetNode in network.nodes.values():
		_add_node(node)
	for cable: Cable in network.cables.values():
		_add_cable(cable)


## Puts a marker on every event of the trace (and clears the previous trace's markers).
func show_trace(trace: StrandTrace) -> void:
	if _marker_root:
		_marker_root.queue_free()
	_marker_root = _new_root("Markers")
	if trace == null:
		return
	for event in trace.events:
		if event.kind == StrandTrace.EventKind.BEND and event.loss_db < MIN_MARKED_BEND_DB:
			continue
		var position := event_position(trace, event)
		var marker := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.03
		sphere.height = 0.06
		marker.mesh = sphere
		marker.material_override = _unshaded(EVENT_COLORS[event.kind])
		marker.position = position
		_marker_root.add_child(marker)
		_marker_root.add_child(_label(event_label(event), position + Vector3(0, 0.12, 0), EVENT_COLORS[event.kind]))


## World position of a trace event: the node for node events, else the point on the cable.
func event_position(trace: StrandTrace, event: StrandTrace.Event) -> Vector3:
	var on_cable := event.kind == StrandTrace.EventKind.BEND or event.kind == StrandTrace.EventKind.BREAK
	if not on_cable and network.nodes.has(event.node_id):
		return network.nodes[event.node_id].transform.origin
	for span in trace.spans:
		if span.cable_id == event.cable_id \
				and event.distance_m >= span.start_m - 1e-6 and event.distance_m <= span.start_m + span.length_m + 1e-6:
			var route := network.cables[span.cable_id].route()
			var local := event.distance_m - span.start_m
			return route.point_at(local if span.forward else route.length_m - local)
	return Vector3.ZERO


static func event_label(event: StrandTrace.Event) -> String:
	var text := EVENT_NAMES[event.kind]
	if event.kind == StrandTrace.EventKind.BEND:
		text += " R%.1f mm" % (event.radius_m * 1000.0)
	text += "\n%.2f m" % event.distance_m
	if event.loss_db > 0.0:
		text += "  %.3f dB" % event.loss_db
	return text


func _add_node(node: NetNode) -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = NODE_SIZES[node.type]
	mesh_instance.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = NODE_COLORS[node.type]
	mesh_instance.material_override = material
	mesh_instance.transform = node.transform
	_static_root.add_child(mesh_instance)
	var title := "%s\n%s" % [NetNode.Type.keys()[node.type], node.id]
	var top := node.transform.origin + Vector3(0, NODE_SIZES[node.type].y * 0.5 + 0.1, 0)
	_static_root.add_child(_label(title, top, Color(0.9, 0.9, 0.9)))


func _add_cable(cable: Cable) -> void:
	var route := cable.route()
	var spec := cable.spec()
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	# The whole tube takes the colour of its worst bend: a 6 mm corner is only ~1 cm long.
	var color := CableMesh.bend_color(spec, route.min_radius(), CableMesh.bend_color(spec, 1.0))
	for d in route.sample_distances(sample_step):
		points.append(route.point_at(d))
		colors.append(color)
	var mesh := CableMesh.build(points, colors, cable_radius)
	if mesh == null:
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.6
	mesh_instance.material_override = material
	_static_root.add_child(mesh_instance)


func _new_root(root_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = root_name
	add_child(root)
	return root


func _label(text: String, position: Vector3, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = position
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0008
	label.font_size = 28
	label.outline_size = 8
	return label


static func _unshaded(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	return material
