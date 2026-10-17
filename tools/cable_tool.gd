class_name CableTool
extends Tool
## Routes cables between box ports, Satisfactory style. The live preview is coloured by bend
## radius and the HUD shows length and estimated loss while routing.
##   LMB  pick a start port / add a waypoint on a wall, floor or ceiling / finish on a port
##   RMB or Backspace  remove the last waypoint (cancels at the start)   Esc  cancel
##   Scroll  corner radius   R  fiber type   G  fiber count
##
## Waypoints snap to a 5 cm grid and sit just off the surface. A segment may not pass through
## a wall, so routes have to go around corners and through doorways.

const CORNER_RADII_MM: Array[float] = [5.0, 7.5, 10.0, 15.0, 20.0, 30.0, 50.0]
const SPECS: Array[StringName] = [&"g657a2", &"g657a1", &"g652d"]
const FIBER_COUNTS: Array[int] = [2, 4, 12, 24]
const GRID := 0.05
const SURFACE_OFFSET := 0.008
## Cables leave a port straight out of the box for this distance before turning.
const PORT_EXIT := 0.08
const WALL_MASK := 1
const PREVIEW_STEP := 0.05
const PREVIEW_RADIUS := 0.006
const ESTIMATE_WAVELENGTH := 1550

enum State { IDLE, ROUTING }
enum HoverKind { NONE, SURFACE, PORT }


## What clicking right now would do.
class Hover:
	var kind := HoverKind.NONE
	var valid := false
	var reason := ""
	## Waypoint or port position in network coordinates.
	var point := Vector3.ZERO
	var node_id: StringName = &""
	var port := -1


var state := State.IDLE
var start_node: StringName = &""
var start_port := -1
## Route so far in network coordinates: start port, its exit point, then the waypoints.
var points := PackedVector3Array()
var hover := Hover.new()
var radius_index := 3
var spec_index := 1
var fiber_index := 2
## Geometry of the cable as it would be if the current hover were clicked.
var preview_route: CablePath

var _preview: MeshInstance3D
var _markers: Node3D
var _preview_key := ""


func corner_radius() -> float:
	return CORNER_RADII_MM[radius_index] * 0.001


func spec_id() -> StringName:
	return SPECS[spec_index]


func fiber_count() -> int:
	return FIBER_COUNTS[fiber_index]


func _on_activate() -> void:
	if _preview == null:
		_preview = MeshInstance3D.new()
		_preview.name = "CablePreview"
		_preview.top_level = true
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_preview.material_override = material
		add_child(_preview)
		_markers = Node3D.new()
		_markers.name = "CableMarkers"
		_markers.top_level = true
		add_child(_markers)
	_preview_key = ""


func _on_deactivate() -> void:
	cancel()
	if _preview:
		_preview.mesh = null
		for child in _markers.get_children():
			child.queue_free()


func _physics_process(_delta: float) -> void:
	update_hover()
	_update_preview()


func _unhandled_input(event: InputEvent) -> void:
	if not can_act():
		return
	if event.is_action_pressed(&"primary_action"):
		click()
	elif event.is_action_pressed(&"secondary_action") or event.is_action_pressed(&"undo_point"):
		undo()
	elif event.is_action_pressed(&"cancel") and state == State.ROUTING:
		cancel()
	elif event.is_action_pressed(&"scroll_up"):
		radius_index = mini(radius_index + 1, CORNER_RADII_MM.size() - 1)
	elif event.is_action_pressed(&"scroll_down"):
		radius_index = maxi(radius_index - 1, 0)
	elif event.is_action_pressed(&"rotate"):
		spec_index = (spec_index + 1) % SPECS.size()
	elif event.is_action_pressed(&"toggle_snap"):
		fiber_index = (fiber_index + 1) % FIBER_COUNTS.size()
	else:
		return
	get_viewport().set_input_as_handled()


## Acts on the current hover. Returns the new cable when this click finished one.
func click() -> Cable:
	if not hover.valid:
		return null
	if state == State.IDLE:
		if hover.kind == HoverKind.PORT:
			_start(hover.node_id, hover.port)
		return null
	if hover.kind == HoverKind.SURFACE:
		points.append(hover.point)
		return null
	if hover.kind == HoverKind.PORT:
		return _finish(hover.node_id, hover.port)
	return null


func undo() -> void:
	if state != State.ROUTING:
		return
	if points.size() > 2:
		points.remove_at(points.size() - 1)
	else:
		cancel()


func cancel() -> void:
	state = State.IDLE
	start_node = &""
	start_port = -1
	points.clear()
	preview_route = null
	_preview_key = ""


func update_hover() -> void:
	hover = Hover.new()
	var level := level_network()
	var ray := player.interaction_ray
	if level == null or not ray.is_colliding():
		hover.reason = "Aim at a box or a surface"
		return
	var collider := ray.get_collider()
	var hit := level.to_local(ray.get_collision_point())
	var item := level.item_for(collider)

	if item["kind"] == LevelNetwork.ItemKind.NODE:
		hover.kind = HoverKind.PORT
		hover.node_id = item["id"]
		hover.port = _nearest_free_port(level, hover.node_id, hit)
		if hover.port < 0:
			hover.reason = "No free port on this box"
			return
		hover.point = level.port_position(hover.node_id, hover.port)
		if state == State.ROUTING and not segment_clear(level, points[-1], _exit_point(level, hover.node_id, hover.port)):
			hover.reason = "The cable would go through a wall"
			return
		hover.valid = true
		return

	if collider is Node and (collider as Node).is_in_group(&"cable_surface"):
		hover.kind = HoverKind.SURFACE
		var normal := (level.global_basis.inverse() * ray.get_collision_normal()).normalized()
		hover.point = BuildTool.snap_to_grid(hit, normal) + normal * SURFACE_OFFSET
		if state == State.IDLE:
			hover.reason = "Start at a port on a box"
			return
		if hover.point.distance_to(points[-1]) < GRID * 0.5:
			hover.reason = "Too close to the last point"
			return
		if not segment_clear(level, points[-1], hover.point):
			hover.reason = "The cable would go through a wall"
			return
		hover.valid = true
		return

	hover.reason = "Can't route the cable here"


## The full route if the current hover were clicked, in network coordinates.
func candidate_points() -> PackedVector3Array:
	var result := points.duplicate()
	if state != State.ROUTING or not hover.valid:
		return result
	if hover.kind == HoverKind.SURFACE:
		result.append(hover.point)
	elif hover.kind == HoverKind.PORT:
		result.append(_exit_point(level_network(), hover.node_id, hover.port))
		result.append(hover.point)
	return result


## Length, estimated loss at 1550 nm and tightest radius of the previewed cable.
func estimate() -> Dictionary:
	var result := {"length_m": 0.0, "loss_db": 0.0, "min_radius_m": INF, "broken": false}
	if preview_route == null:
		return result
	var spec := FiberSpec.get_spec(spec_id())
	var loss := LossModel.attenuation_db(spec, preview_route.length_m, ESTIMATE_WAVELENGTH)
	for arc in preview_route.arcs():
		if LossModel.is_broken(spec, arc.radius_m):
			result["broken"] = true
		loss += LossModel.bend_loss_db(spec, arc.radius_m, arc.length_m, ESTIMATE_WAVELENGTH)
	result["length_m"] = preview_route.length_m
	result["loss_db"] = loss
	result["min_radius_m"] = preview_route.min_radius()
	return result


## True if a straight cable run between two network-space points doesn't cross a wall.
func segment_clear(level: LevelNetwork, a_local: Vector3, b_local: Vector3) -> bool:
	var a := level.to_global(a_local)
	var b := level.to_global(b_local)
	if a.distance_to(b) < 1e-4:
		return true
	var query := PhysicsRayQueryParameters3D.create(a, b, WALL_MASK)
	return player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func get_hud_text() -> String:
	var spec := FiberSpec.get_spec(spec_id())
	var text := "%s %d fibers   corner R %s mm   [Scroll] radius  [R] type  [G] fibers" % [
		spec.display_name, fiber_count(), _mm(corner_radius())]
	if state == State.IDLE:
		text += "\n" + (hover.reason if hover.kind == HoverKind.PORT and not hover.valid else "Click a port on a box to start")
		return text
	var est := estimate()
	text += "\n%.2f m   ~%.2f dB @%d nm   tightest R %s" % [
		est["length_m"], est["loss_db"], ESTIMATE_WAVELENGTH,
		"-" if is_inf(est["min_radius_m"]) else _mm(est["min_radius_m"]) + " mm"]
	if est["broken"]:
		text += "   FIBER WILL BREAK"
	elif est["min_radius_m"] < spec.min_bend_radius_mm * 0.001:
		text += "   tight bend (min %s mm)" % _mm(spec.min_bend_radius_mm * 0.001)
	if not hover.valid and hover.reason != "":
		text += "\n" + hover.reason
	text += "\n[LMB] add point / finish on a port   [RMB] undo   [Esc] cancel"
	return text


func _start(node_id: StringName, port: int) -> void:
	var level := level_network()
	state = State.ROUTING
	start_node = node_id
	start_port = port
	points = PackedVector3Array([level.port_position(node_id, port), _exit_point(level, node_id, port)])


func _finish(node_id: StringName, port: int) -> Cable:
	var level := level_network()
	var route := candidate_points()
	var cable := level.network.add_cable(start_node, start_port, node_id, port, route,
			spec_id(), fiber_count(), corner_radius())
	cancel()
	return cable


func _exit_point(level: LevelNetwork, node_id: StringName, port: int) -> Vector3:
	return level.port_position(node_id, port) + level.port_exit_direction(node_id, port) * PORT_EXIT


func _nearest_free_port(level: LevelNetwork, node_id: StringName, hit: Vector3) -> int:
	var best := -1
	var best_distance := INF
	for port in level.free_ports(node_id):
		if state == State.ROUTING and node_id == start_node and port == start_port:
			continue
		var distance := level.port_position(node_id, port).distance_to(hit)
		if distance < best_distance:
			best_distance = distance
			best = port
	return best


func _update_preview() -> void:
	var level := level_network()
	if _preview == null or level == null:
		return
	var route_points := candidate_points()
	var key := "%s|%s|%s|%s|%d|%d" % [route_points, corner_radius(), spec_id(), hover.node_id, hover.port,
			level.network.cables.size()]
	if key == _preview_key:
		return
	_preview_key = key
	_preview.global_transform = level.global_transform
	_markers.global_transform = level.global_transform
	for child in _markers.get_children():
		child.queue_free()

	var spec := FiberSpec.get_spec(spec_id())
	preview_route = CablePath.build(route_points, corner_radius()) if route_points.size() >= 2 else null
	_preview.mesh = null
	if preview_route and preview_route.length_m > 0.0:
		var sample_points := PackedVector3Array()
		var colors := PackedColorArray()
		for d in preview_route.sample_distances(PREVIEW_STEP):
			sample_points.append(preview_route.point_at(d))
			colors.append(CableMesh.bend_color(spec, preview_route.radius_at(d), spec.jacket_color))
		_preview.mesh = CableMesh.build(sample_points, colors, PREVIEW_RADIUS)
		# Tight corners are only a centimetre or two long: flag them with a marker.
		for arc in preview_route.arcs():
			if arc.radius_m < spec.min_bend_radius_mm * 0.001:
				_add_marker(arc.point_at(arc.length_m * 0.5), 0.02, CableMesh.bend_color(spec, arc.radius_m))

	if hover.node_id != &"":
		var free := level.free_ports(hover.node_id)
		var node := level.network.get_node_by_id(hover.node_id)
		for port in node.port_count:
			var color := Color(0.5, 0.5, 0.5)
			if port == hover.port:
				color = Color(1.0, 0.85, 0.2)
			elif port in free and not (hover.node_id == start_node and port == start_port):
				color = Color(0.2, 0.9, 0.35)
			_add_marker(level.port_position(hover.node_id, port), 0.012, color)


func _add_marker(position: Vector3, radius: float, color: Color) -> void:
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	marker.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	marker.material_override = material
	marker.position = position
	_markers.add_child(marker)


static func _mm(meters: float) -> String:
	var mm := meters * 1000.0
	return ("%.1f" % mm) if absf(mm - roundf(mm)) > 0.05 else ("%d" % roundi(mm))
