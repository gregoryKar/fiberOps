extends TestCase
## M2: tracing fiber strands through the network.
##
## Reference network:  BEP:0 ──50 m straight── 0:FLOORBOX:1 ──10 m, 90° corner, 10 m── 0:OUTLET
## The floorbox splices fiber 0 of port 0 to fiber 0 of port 1.

const CORNER_RADIUS := 0.008
const SPLICE_DB := 0.05

var _net: FiberNetwork
var _bep: NetNode
var _box: NetNode
var _outlet: NetNode
var _drop: Cable


func before_each() -> void:
	_net = FiberNetwork.new()
	_bep = _net.add_node(NetNode.Type.BEP)
	_box = _net.add_node(NetNode.Type.FLOORBOX)
	_outlet = _net.add_node(NetNode.Type.OUTLET)
	_net.add_cable(_bep.id, 0, _box.id, 0, PackedVector3Array([Vector3.ZERO, Vector3(50, 0, 0)]))
	_drop = _net.add_cable(_box.id, 1, _outlet.id, 0,
			PackedVector3Array([Vector3(50, 0, 0), Vector3(60, 0, 0), Vector3(60, 0, 10)]),
			&"g657a1", 12, CORNER_RADIUS)
	_box.add_splice(0, 0, 1, 0, SPLICE_DB)


func _expected_bend_db(wavelength := 1550) -> float:
	var spec := FiberSpec.get_spec(&"g657a1")
	return LossModel.bend_loss_db(spec, CORNER_RADIUS, CORNER_RADIUS * PI / 2.0, wavelength)


func _expected_length() -> float:
	return 50.0 + 20.0 - 2.0 * CORNER_RADIUS + CORNER_RADIUS * PI / 2.0


func test_trace_through_splice_and_bend() -> void:
	var traces := StrandTracer.trace(_net, _bep.id, 0, 0)
	assert_eq(traces.size(), 1, "one path")
	var trace := traces[0]
	assert_almost(trace.length_m, _expected_length(), 1e-9, "length")
	assert_eq(trace.end_kind, StrandTrace.EndKind.OPEN_END, "ends open at the outlet")

	var kinds: Array = trace.events.map(func(e: StrandTrace.Event) -> int: return e.kind)
	assert_eq(kinds, [StrandTrace.EventKind.SPLICE, StrandTrace.EventKind.BEND, StrandTrace.EventKind.OPEN_END], "event order")
	assert_almost(trace.events[0].distance_m, 50.0, 1e-9, "splice position")
	assert_eq(trace.events[0].node_id, _box.id, "splice node")
	var bend_at := 50.0 + 10.0 - CORNER_RADIUS + CORNER_RADIUS * PI / 4.0
	assert_almost(trace.events[1].distance_m, bend_at, 1e-9, "bend position")
	assert_almost(trace.events[1].radius_m, CORNER_RADIUS, 1e-9, "bend radius")
	assert_eq(trace.events[2].node_id, _outlet.id, "end node")
	assert_almost(trace.events[2].reflectance_db, LossModel.FRESNEL_OPEN_END_DB, 1e-9, "Fresnel end")

	var expected := 0.22 * _expected_length() / 1000.0 + SPLICE_DB + _expected_bend_db()
	assert_almost(trace.total_loss_db(), expected, 1e-9, "total loss")


func test_bend_hurts_more_at_1625_than_1310() -> void:
	var at_1310 := StrandTracer.trace(_net, _bep.id, 0, 0, 1310)[0]
	var at_1625 := StrandTracer.trace(_net, _bep.id, 0, 0, 1625)[0]
	var bend_1310 := at_1310.events_of_kind(StrandTrace.EventKind.BEND)[0].loss_db
	var bend_1625 := at_1625.events_of_kind(StrandTrace.EventKind.BEND)[0].loss_db
	assert_almost(bend_1310, _expected_bend_db(1310), 1e-9, "1310 bend")
	assert_true(bend_1625 > bend_1310 * 5.0, "1625 bend %f vs 1310 %f" % [bend_1625, bend_1310])


func test_trace_is_reciprocal() -> void:
	var forward := StrandTracer.trace(_net, _bep.id, 0, 0)[0]
	var backward := StrandTracer.trace(_net, _outlet.id, 0, 0)[0]
	assert_almost(backward.total_loss_db(), forward.total_loss_db(), 1e-9, "same loss both ways")
	assert_almost(backward.length_m, forward.length_m, 1e-9, "same length")
	assert_eq(backward.end_event().node_id, _bep.id, "ends at the BEP")
	var bend_from_outlet := 10.0 - CORNER_RADIUS + CORNER_RADIUS * PI / 4.0
	assert_almost(backward.events[0].distance_m, bend_from_outlet, 1e-9, "bend seen first from the outlet")


func test_unspliced_fiber_ends_at_floorbox() -> void:
	var trace := StrandTracer.trace(_net, _bep.id, 0, 3)[0]
	assert_almost(trace.length_m, 50.0, 1e-9, "stops at the box")
	assert_eq(trace.end_event().node_id, _box.id, "end node")
	assert_eq(trace.events.size(), 1, "only the open end")


func test_fiber_outside_cable_or_empty_port() -> void:
	var beyond := StrandTracer.trace(_net, _bep.id, 0, 12)[0]
	assert_eq(beyond.length_m, 0.0, "fiber 12 of a 12-fiber cable doesn't exist")
	var empty_port := StrandTracer.trace(_net, _bep.id, 3, 0)[0]
	assert_eq(empty_port.length_m, 0.0, "no cable on port 3")
	assert_eq(empty_port.end_kind, StrandTrace.EndKind.OPEN_END, "open end")


func test_too_tight_bend_breaks_fiber() -> void:
	_drop.corner_radius = 0.001  # below the 2.5 mm break radius of G.657.A1
	var trace := StrandTracer.trace(_net, _bep.id, 0, 0)[0]
	assert_eq(trace.end_kind, StrandTrace.EndKind.BREAK, "fiber broke")
	assert_eq(trace.end_event().kind, StrandTrace.EventKind.BREAK, "break event")
	assert_almost(trace.length_m, 50.0 + 10.0 - 0.001 + 0.001 * PI / 4.0, 1e-9, "break at the corner")
	assert_almost(trace.end_event().reflectance_db, LossModel.BREAK_REFLECTANCE_DB, 1e-9, "weak reflection")


func test_splitter_fans_out() -> void:
	var splitter := _net.add_node(NetNode.Type.SPLITTER)
	_net.remove_cable(_drop.id)
	_net.add_cable(_box.id, 1, splitter.id, 0, PackedVector3Array([Vector3(50, 0, 0), Vector3(55, 0, 0)]))
	var out_box := _net.add_node(NetNode.Type.FLOORBOX)
	_net.add_cable(splitter.id, 1, out_box.id, 0, PackedVector3Array([Vector3(55, 0, 0), Vector3(60, 0, 0)]))
	_box.add_splice(0, 0, 1, 0, SPLICE_DB)  # the cable removal cut the old splice
	splitter.add_splitter(0, 0, 1, 8)

	var traces := StrandTracer.trace(_net, _bep.id, 0, 0)
	assert_eq(traces.size(), 8, "one trace per leg")
	var expected := 0.22 * 60.0 / 1000.0 + SPLICE_DB + LossModel.splitter_loss_db(8)
	for trace in traces:
		assert_almost(trace.total_loss_db(), expected, 1e-9, "leg loss")
		assert_eq(trace.events_of_kind(StrandTrace.EventKind.SPLITTER).size(), 1, "one splitter event")
		assert_eq(trace.end_event().node_id, out_box.id, "legs end in the far box")


func test_loop_through_splitter_terminates() -> void:
	# BEP → C:0 ↔ C:1 → SP:1 leg0 → SP:0 → C:2 ↔ C:1 fiber 1 → SP:1 leg1 → SP:0 again.
	var net := FiberNetwork.new()
	var bep := net.add_node(NetNode.Type.BEP)
	var closure := net.add_node(NetNode.Type.SPLICE_CLOSURE)
	var splitter := net.add_node(NetNode.Type.SPLITTER)
	var line := PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0)])
	net.add_cable(bep.id, 0, closure.id, 0, line)
	net.add_cable(closure.id, 1, splitter.id, 1, line, &"g657a1", 2)
	net.add_cable(splitter.id, 0, closure.id, 2, line)
	closure.add_splice(0, 0, 1, 0)
	closure.add_splice(2, 0, 1, 1)
	splitter.add_splitter(0, 0, 1, 2)

	var traces := StrandTracer.trace(net, bep.id, 0, 0)
	var loops := traces.filter(func(t: StrandTrace) -> bool: return t.end_kind == StrandTrace.EndKind.LOOP)
	assert_true(traces.size() <= StrandTracer.MAX_BRANCHES, "bounded")
	assert_eq(loops.size(), 1, "the loop is detected")
