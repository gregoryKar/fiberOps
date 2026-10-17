class_name LevelNetwork
extends Node3D
## Owns the FiberNetwork of the level it sits in and keeps physical bodies in sync with it:
## a box per network node (layer "network_nodes") and a tube per cable (layer "cables").
## Tools aim at, collide with and remove these bodies. Network coordinates are local to
## this node.

const GROUP := &"level_network"
const NODE_ID_META := &"net_node_id"
const CABLE_ID_META := &"net_cable_id"
const NODE_LAYER := 4  ## physics layer 3, "network_nodes"
const CABLE_LAYER := 8  ## physics layer 4, "cables"
const CABLE_VISUAL_RADIUS := 0.005
const CABLE_SAMPLE_STEP := 0.02

enum ItemKind { NONE, NODE, CABLE }

@export var level_id := &"test_floor"
## Starts empty when unset.
@export var network: FiberNetwork

var _bodies: Dictionary[StringName, StaticBody3D] = {}
var _cable_bodies: Dictionary[StringName, StaticBody3D] = {}


static func find(tree: SceneTree) -> LevelNetwork:
	return tree.get_first_node_in_group(GROUP) as LevelNetwork


func _ready() -> void:
	add_to_group(GROUP)
	if network == null:
		network = FiberNetwork.new()
	NetworkRegistry.register_network(level_id, network)
	GameState.current_level_id = level_id
	network.changed.connect(sync)
	sync()


func place(def: PlaceableDef, xform: Transform3D) -> NetNode:
	return network.add_node(def.node_type, xform, def.port_count)


func remove(node_id: StringName) -> void:
	network.remove_node(node_id)


## What a ray hit: {"kind": ItemKind, "id": StringName}. Kind NONE for anything else.
func item_for(collider: Object) -> Dictionary:
	if collider is Node and collider.get_parent() == self:
		if collider.has_meta(NODE_ID_META):
			return {"kind": ItemKind.NODE, "id": collider.get_meta(NODE_ID_META)}
		if collider.has_meta(CABLE_ID_META):
			return {"kind": ItemKind.CABLE, "id": collider.get_meta(CABLE_ID_META)}
	return {"kind": ItemKind.NONE, "id": &""}


## Network node id for a collider hit by a ray, or &"" if it isn't a network node.
func node_id_for(collider: Object) -> StringName:
	var item := item_for(collider)
	return item["id"] if item["kind"] == ItemKind.NODE else &""


func remove_item(kind: ItemKind, id: StringName) -> void:
	match kind:
		ItemKind.NODE:
			network.remove_node(id)
		ItemKind.CABLE:
			network.remove_cable(id)


func body_for(node_id: StringName) -> StaticBody3D:
	return _bodies.get(node_id)


func cable_body_for(cable_id: StringName) -> StaticBody3D:
	return _cable_bodies.get(cable_id)


## Port position in network (local) coordinates.
func port_position(node_id: StringName, port: int) -> Vector3:
	var node := network.get_node_by_id(node_id)
	return node.transform * PlaceableDef.for_node_type(node.type).port_local_position(port)


## Direction a cable leaves the port, in network (local) coordinates.
func port_exit_direction(node_id: StringName, port: int) -> Vector3:
	var node := network.get_node_by_id(node_id)
	return node.transform.basis * PlaceableDef.for_node_type(node.type).port_exit_direction(port)


func free_ports(node_id: StringName) -> Array[int]:
	var result: Array[int] = []
	var node := network.get_node_by_id(node_id)
	if node:
		for port in node.port_count:
			if network.cable_at(node_id, port) == null:
				result.append(port)
	return result


## Creates bodies for new nodes and cables, removes bodies of deleted ones, moves nodes.
func sync() -> void:
	_drop_stale(_bodies, network.nodes)
	_drop_stale(_cable_bodies, network.cables)
	for node: NetNode in network.nodes.values():
		var body: StaticBody3D = _bodies.get(node.id)
		if body == null:
			body = _create_node_body(node)
			if body == null:
				continue
			_bodies[node.id] = body
		body.transform = node.transform
	for cable: Cable in network.cables.values():
		if not _cable_bodies.has(cable.id):
			var body := _create_cable_body(cable)
			if body:
				_cable_bodies[cable.id] = body
	Events.network_changed.emit(level_id)


func _drop_stale(bodies: Dictionary, live: Dictionary) -> void:
	for id in bodies.keys():
		if not live.has(id):
			# Stop it blocking rays and placement right away; the node itself goes at frame end.
			bodies[id].collision_layer = 0
			bodies[id].queue_free()
			bodies.erase(id)


func _create_node_body(node: NetNode) -> StaticBody3D:
	var def := PlaceableDef.for_node_type(node.type)
	if def == null:
		push_warning("No placeable definition for node type %d" % node.type)
		return null
	var body := NetNodeBody.new()
	body.node_id = node.id
	body.level = self
	_setup_body(body, String(node.id), NODE_LAYER, NODE_ID_META, node.id)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = box_mesh(def)
	body.add_child(mesh_instance)
	var shape := BoxShape3D.new()
	shape.size = def.size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	return body


func _create_cable_body(cable: Cable) -> StaticBody3D:
	var mesh := cable_mesh(cable)
	if mesh == null:
		return null
	var body := StaticBody3D.new()
	_setup_body(body, String(cable.id), CABLE_LAYER, CABLE_ID_META, cable.id)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
	return body


func _setup_body(body: StaticBody3D, body_name: String, layer: int, meta: StringName, id: StringName) -> void:
	body.name = body_name
	body.collision_layer = layer
	body.collision_mask = 0
	body.set_meta(meta, id)
	add_child(body)


static func box_mesh(def: PlaceableDef) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = def.size
	var material := StandardMaterial3D.new()
	material.albedo_color = def.color
	material.roughness = 0.5
	mesh.material = material
	return mesh


static func cable_mesh(cable: Cable) -> ArrayMesh:
	var points := cable.route().sample(CABLE_SAMPLE_STEP)
	var colors := PackedColorArray()
	colors.resize(points.size())
	colors.fill(cable.spec().jacket_color)
	var mesh := CableMesh.build(points, colors, CABLE_VISUAL_RADIUS)
	if mesh:
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 0.6
		mesh.surface_set_material(0, material)
	return mesh
