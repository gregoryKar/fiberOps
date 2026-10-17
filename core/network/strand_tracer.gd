class_name StrandTracer
extends RefCounted
## Follows a single fiber strand through a FiberNetwork: out of a node port, along the cable,
## into the far node, through its link to the next port, and so on. Splitters fan the path out,
## so the result is one StrandTrace per branch.

const MAX_BRANCHES := 256


## Traces the light launched into `fiber` of the cable on (node_id, port).
static func trace(network: FiberNetwork, node_id: StringName, port: int, fiber: int,
		wavelength_nm := 1550) -> Array[StrandTrace]:
	var results: Array[StrandTrace] = []
	var start := StrandTrace.new()
	start.wavelength_nm = wavelength_nm
	_walk(network, node_id, port, fiber, start, {}, results)
	return results


static func _walk(network: FiberNetwork, node_id: StringName, port: int, fiber: int,
		trace: StrandTrace, visited: Dictionary, results: Array[StrandTrace]) -> void:
	if results.size() >= MAX_BRANCHES:
		return
	var key := "%s:%d:%d" % [node_id, port, fiber]
	if visited.has(key):
		trace.end_kind = StrandTrace.EndKind.LOOP
		results.append(trace)
		return
	visited[key] = true

	var cable := network.cable_at(node_id, port)
	if cable == null or fiber < 0 or fiber >= cable.fiber_count:
		_end_open(trace, node_id, &"")
		results.append(trace)
		return

	if not _walk_cable(cable, node_id, port, fiber, trace):
		results.append(trace)  # broke inside the cable
		return

	var far_node_id := cable.node_b if cable.is_end_a(node_id, port) else cable.node_a
	var far_port := cable.port_b if cable.is_end_a(node_id, port) else cable.port_a
	var far_node := network.get_node_by_id(far_node_id)
	var links: Array[NetLink] = []
	if far_node:
		links = far_node.links_at(far_port, fiber)
	if links.is_empty():
		_end_open(trace, far_node_id, cable.id)
		results.append(trace)
		return

	for i in links.size():
		var link := links[i]
		var branch := trace if i == links.size() - 1 else trace.copy()
		branch.events.append(_link_event(link, far_node_id, branch.length_m))
		var next := link.other_side(far_port, fiber)
		_walk(network, far_node_id, next.x, next.y, branch, visited.duplicate(), results)


## Adds the cable's span and bend events in travel direction. Returns false if the fiber
## breaks at a bend, in which case the trace is terminated there.
static func _walk_cable(cable: Cable, from_node: StringName, from_port: int, fiber: int, trace: StrandTrace) -> bool:
	var spec := cable.spec()
	var route := cable.route()
	var forward := cable.is_end_a(from_node, from_port)
	var start_m := trace.length_m

	var arcs := route.arcs()
	if not forward:
		arcs.reverse()
	var cable_length := route.length_m
	var travelled := cable_length
	var broke := false
	var bend_events: Array[StrandTrace.Event] = []
	for arc in arcs:
		var arc_mid := arc.start_m + arc.length_m * 0.5
		var along := arc_mid if forward else cable_length - arc_mid
		if LossModel.is_broken(spec, arc.radius_m):
			travelled = along
			broke = true
			break
		var loss := LossModel.bend_loss_db(spec, arc.radius_m, arc.length_m, trace.wavelength_nm)
		var event := StrandTrace.Event.new()
		event.kind = StrandTrace.EventKind.BEND
		event.distance_m = start_m + along
		event.loss_db = loss
		event.cable_id = cable.id
		event.radius_m = arc.radius_m
		bend_events.append(event)

	var span := StrandTrace.Span.new()
	span.start_m = start_m
	span.length_m = travelled
	span.attenuation_db_per_km = spec.attenuation_at(trace.wavelength_nm)
	span.cable_id = cable.id
	span.forward = forward
	span.fiber = fiber
	trace.spans.append(span)
	trace.events.append_array(bend_events)
	trace.length_m = start_m + travelled

	if broke:
		var end := StrandTrace.Event.new()
		end.kind = StrandTrace.EventKind.BREAK
		end.distance_m = trace.length_m
		end.loss_db = 0.0
		end.reflectance_db = LossModel.BREAK_REFLECTANCE_DB
		end.cable_id = cable.id
		trace.events.append(end)
		trace.end_kind = StrandTrace.EndKind.BREAK
	return not broke


static func _link_event(link: NetLink, node_id: StringName, distance_m: float) -> StrandTrace.Event:
	var event := StrandTrace.Event.new()
	event.distance_m = distance_m
	event.loss_db = link.loss_db
	event.node_id = node_id
	match link.kind:
		NetLink.Kind.CONNECTOR:
			event.kind = StrandTrace.EventKind.CONNECTOR
			event.reflectance_db = link.reflectance_db
		NetLink.Kind.SPLITTER_LEG:
			event.kind = StrandTrace.EventKind.SPLITTER
		_:
			event.kind = StrandTrace.EventKind.SPLICE
	return event


static func _end_open(trace: StrandTrace, node_id: StringName, cable_id: StringName) -> void:
	var end := StrandTrace.Event.new()
	end.kind = StrandTrace.EventKind.OPEN_END
	end.distance_m = trace.length_m
	end.loss_db = 0.0
	end.reflectance_db = LossModel.FRESNEL_OPEN_END_DB
	end.node_id = node_id
	end.cable_id = cable_id
	trace.events.append(end)
	trace.end_kind = StrandTrace.EndKind.OPEN_END
