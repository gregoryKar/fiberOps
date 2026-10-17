class_name NetNode
extends Resource
## A piece of network hardware. Cables attach to its ports (one cable per port); its links
## route individual fibers between ports (splice tray, connectors, splitter).

enum Type { BEP, RISER_STUB, FLOORBOX, SPLICE_CLOSURE, SPLITTER, OUTLET }

const DEFAULT_PORT_COUNT: Dictionary[int, int] = {
	Type.BEP: 4,
	Type.RISER_STUB: 2,
	Type.FLOORBOX: 4,
	Type.SPLICE_CLOSURE: 4,
	Type.SPLITTER: 2,
	Type.OUTLET: 1,
}

@export var id: StringName
@export var type := Type.FLOORBOX
@export var transform := Transform3D.IDENTITY
@export var port_count := 1
@export var links: Array[NetLink] = []
## Set by the mounting minigame (M8); 1 = perfectly mounted.
@export_range(0.0, 1.0) var mounted_quality := 1.0
## RISER_STUB only: shared with the matching stub on the adjacent level (M9).
@export var riser_id: StringName


func links_at(port: int, fiber: int) -> Array[NetLink]:
	var result: Array[NetLink] = []
	for link in links:
		if link.touches(port, fiber):
			result.append(link)
	return result


## Adds a link if both of its fiber ends are free. Splitter legs may share their A side
## with other splitter legs. Returns false (and adds nothing) when the link is invalid.
func add_link(link: NetLink) -> bool:
	for port in [link.port_a, link.port_b]:
		if port < 0 or port >= port_count:
			push_error("Link port %d out of range on %s" % [port, id])
			return false
	if link.port_a == link.port_b and link.fiber_a == link.fiber_b:
		push_error("Link connects a fiber to itself on %s" % id)
		return false
	for existing in links:
		var shares_input := link.kind == NetLink.Kind.SPLITTER_LEG \
				and existing.kind == NetLink.Kind.SPLITTER_LEG \
				and existing.touches_a(link.port_a, link.fiber_a)
		if existing.touches(link.port_a, link.fiber_a) and not shares_input:
			return false
		if existing.touches(link.port_b, link.fiber_b):
			return false
	links.append(link)
	emit_changed()
	return true


func add_splice(port_a: int, fiber_a: int, port_b: int, fiber_b: int,
		loss := LossModel.DEFAULT_FUSION_SPLICE_DB) -> NetLink:
	var link := NetLink.create(NetLink.Kind.FUSION_SPLICE, port_a, fiber_a, port_b, fiber_b, loss)
	return link if add_link(link) else null


## Adds a 1:ratio splitter from (in_port, in_fiber) to fibers 0..ratio-1 of out_port.
func add_splitter(in_port: int, in_fiber: int, out_port: int, ratio: int) -> Array[NetLink]:
	var legs: Array[NetLink] = []
	var loss := LossModel.splitter_loss_db(ratio)
	for leg in ratio:
		var link := NetLink.create(NetLink.Kind.SPLITTER_LEG, in_port, in_fiber, out_port, leg, loss)
		if add_link(link):
			legs.append(link)
	return legs


func remove_link(link: NetLink) -> bool:
	var index := links.find(link)
	if index < 0:
		return false
	links.remove_at(index)
	emit_changed()
	return true


## Every splitter leg sharing the given leg's input.
func splitter_legs_of(link: NetLink) -> Array[NetLink]:
	var legs: Array[NetLink] = []
	for other in links:
		if other.kind == NetLink.Kind.SPLITTER_LEG and other.touches_a(link.port_a, link.fiber_a):
			legs.append(other)
	return legs


func remove_links_at_port(port: int) -> void:
	var before := links.size()
	links.assign(links.filter(func(l: NetLink) -> bool: return l.port_a != port and l.port_b != port))
	if links.size() != before:
		emit_changed()
