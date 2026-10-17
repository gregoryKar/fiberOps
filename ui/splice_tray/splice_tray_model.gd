class_name SpliceTrayModel
extends RefCounted
## Editing logic behind the splice tray screen, kept apart from the UI so it can be tested.
## The player clicks a fiber end to select it, then another to splice the two. Clicking a
## spliced fiber selects its splice so it can be cut. With use_splicer on, the second click
## asks for the splicing minigame instead (splice_requested); its result comes back through
## complete_splice().

signal changed
## The player picked two fibers to splice and the splicer should run.
signal splice_requested(from: Vector2i, to: Vector2i)

enum FiberState { FREE, SPLICED, SPLITTER }

const SPLITTER_RATIOS: Array[int] = [2, 4, 8, 16, 32]

var network: FiberNetwork
var node: NetNode
## Selected free fiber end (port, fiber); (-1, -1) when none.
var selected_end := Vector2i(-1, -1)
## Splice selected for cutting, or null.
var selected_link: NetLink
## Feedback line for the player.
var message := ""
## Splices go through the splicing minigame (the tray screen turns this on).
var use_splicer := false


func _init(target_network: FiberNetwork, node_id: StringName) -> void:
	network = target_network
	node = network.get_node_by_id(node_id)
	message = "Click a fiber, then the fiber to splice it to."


## One entry per port: {"port": int, "cable": Cable or null}.
func ports() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for port in node.port_count:
		result.append({"port": port, "cable": network.cable_at(node.id, port)})
	return result


func link_at(port: int, fiber: int) -> NetLink:
	var links := node.links_at(port, fiber)
	return links[0] if not links.is_empty() else null


func fiber_state(port: int, fiber: int) -> FiberState:
	var link := link_at(port, fiber)
	if link == null:
		return FiberState.FREE
	return FiberState.SPLITTER if link.kind == NetLink.Kind.SPLITTER_LEG else FiberState.SPLICED


## Handles a click on a fiber end. Returns the new splice when the click made one.
func click_fiber(port: int, fiber: int) -> NetLink:
	var existing := link_at(port, fiber)
	if selected_end.x < 0:
		if existing:
			selected_link = existing
			message = describe(existing)
		else:
			selected_end = Vector2i(port, fiber)
			selected_link = null
			message = "%s selected. Click the fiber to splice it to." % fiber_label(port, fiber)
		changed.emit()
		return null

	if selected_end == Vector2i(port, fiber):
		clear_selection()
		return null
	if existing:
		message = "%s is already spliced." % fiber_label(port, fiber)
		changed.emit()
		return null

	var from := selected_end
	selected_end = Vector2i(-1, -1)
	if use_splicer:
		message = "Splicing %s to %s…" % [fiber_label(from.x, from.y), fiber_label(port, fiber)]
		changed.emit()
		splice_requested.emit(from, Vector2i(port, fiber))
		return null
	var link := node.add_splice(from.x, from.y, port, fiber)
	if link:
		message = "Spliced %s to %s (%.2f dB)." % [fiber_label(from.x, from.y), fiber_label(port, fiber), link.loss_db]
		_network_edited()
	else:
		message = "Can't splice those fibers."
	changed.emit()
	return link


## Stores the splice made in the splicer between two fiber ends.
func complete_splice(from: Vector2i, to: Vector2i, job: SpliceJob) -> NetLink:
	var link := node.add_splice(from.x, from.y, to.x, to.y, job.true_loss_db)
	if link == null:
		message = "Can't splice those fibers."
		changed.emit()
		return null
	link.estimated_loss_db = job.estimated_loss_db
	link.protected = job.protected
	message = "Spliced %s to %s. Splicer estimate %.2f dB%s." % [fiber_label(from.x, from.y),
			fiber_label(to.x, to.y), job.estimated_loss_db, "" if job.protected else ", NO SLEEVE"]
	_network_edited()
	changed.emit()
	return link


## Specs of the two fibers to splice (left = from, right = to).
func specs_for(from: Vector2i, to: Vector2i) -> Array[FiberSpec]:
	var result: Array[FiberSpec] = []
	for end in [from, to]:
		var cable := network.cable_at(node.id, end.x)
		result.append(cable.spec() if cable else FiberSpec.get_spec(&"g657a1"))
	return result


## Cuts the selected splice. A splitter leg takes the whole splitter with it.
func cut_selected() -> bool:
	if selected_link == null:
		return false
	var to_remove: Array[NetLink] = [selected_link]
	if selected_link.kind == NetLink.Kind.SPLITTER_LEG:
		to_remove = node.splitter_legs_of(selected_link)
	for link in to_remove:
		node.remove_link(link)
	message = "Splitter removed." if to_remove.size() > 1 else "Splice cut."
	selected_link = null
	_network_edited()
	changed.emit()
	return true


func clear_selection() -> void:
	selected_end = Vector2i(-1, -1)
	selected_link = null
	message = "Click a fiber, then the fiber to splice it to."
	changed.emit()


## Splitter ratios that fit: input on the selected fiber, legs on fibers 1..N of another
## port's cable, all free.
func available_splitter_ratios() -> Array[int]:
	var result: Array[int] = []
	if node.type != NetNode.Type.SPLITTER or selected_end.x < 0:
		return result
	for ratio in SPLITTER_RATIOS:
		if _splitter_output_port(ratio) >= 0:
			result.append(ratio)
	return result


## Installs a 1:ratio splitter from the selected fiber. Returns the legs (empty on failure).
func add_splitter(ratio: int) -> Array[NetLink]:
	var out_port := _splitter_output_port(ratio)
	if out_port < 0:
		message = "No cable with %d free fibers for a 1:%d splitter." % [ratio, ratio]
		changed.emit()
		return [] as Array[NetLink]
	var legs := node.add_splitter(selected_end.x, selected_end.y, out_port, ratio)
	message = "1:%d splitter on %s → port %d fibers 1-%d (%.1f dB per leg)." % [
		ratio, fiber_label(selected_end.x, selected_end.y), out_port + 1, ratio, LossModel.splitter_loss_db(ratio)]
	selected_end = Vector2i(-1, -1)
	_network_edited()
	changed.emit()
	return legs


func describe(link: NetLink) -> String:
	var kind := "splitter leg" if link.kind == NetLink.Kind.SPLITTER_LEG else "fusion splice"
	return "%s ↔ %s   %s %s   [Cut] to remove" % [
		fiber_label(link.port_a, link.fiber_a), fiber_label(link.port_b, link.fiber_b), kind, loss_label(link)]


## "0.03 dB est." for splicer splices, plain loss otherwise, plus a no-sleeve warning.
static func loss_label(link: NetLink) -> String:
	var text := "%.2f dB%s" % [link.displayed_loss_db(), "" if is_nan(link.estimated_loss_db) else " est."]
	return text if link.protected else text + "  ⚠ no sleeve"


## Where the cable on a port goes: "→ Fiber outlet node_5 · 2 × G.657.A1 · 4.30 m".
func far_end_label(cable: Cable) -> String:
	var far_id := cable.node_b if cable.node_a == node.id else cable.node_a
	var far := network.get_node_by_id(far_id)
	var def: PlaceableDef = PlaceableDef.for_node_type(far.type) if far else null
	var far_name: String = def.display_name if def else String(far_id)
	return "→ %s %s · %d × %s · %.2f m" % [far_name, far_id, cable.fiber_count, cable.spec().display_name, cable.route().length_m]


static func fiber_label(port: int, fiber: int) -> String:
	return "P%d #%d %s" % [port + 1, fiber + 1, FiberColors.name_for(fiber)]


func _splitter_output_port(ratio: int) -> int:
	for port in node.port_count:
		if port == selected_end.x:
			continue
		var cable := network.cable_at(node.id, port)
		if cable == null or cable.fiber_count < ratio:
			continue
		var free := true
		for leg in ratio:
			if link_at(port, leg) != null:
				free = false
				break
		if free:
			return port
	return -1


func _network_edited() -> void:
	network.emit_changed()
