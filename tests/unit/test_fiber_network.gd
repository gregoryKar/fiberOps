extends TestCase
## M2: network editing rules and persistence.

const SAVE_PATH := "user://test_network.tres"

var _net: FiberNetwork


func before_each() -> void:
	_net = FiberNetwork.new()


func after_each() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _line(a: Vector3, b: Vector3) -> PackedVector3Array:
	return PackedVector3Array([a, b])


func test_add_node_assigns_ids_and_ports() -> void:
	var bep := _net.add_node(NetNode.Type.BEP)
	var outlet := _net.add_node(NetNode.Type.OUTLET)
	var custom := _net.add_node(NetNode.Type.FLOORBOX, Transform3D.IDENTITY, 8)
	assert_true(bep.id != outlet.id, "unique ids")
	assert_eq(bep.port_count, 4, "BEP ports")
	assert_eq(outlet.port_count, 1, "outlet ports")
	assert_eq(custom.port_count, 8, "custom ports")
	assert_eq(_net.nodes.size(), 3, "node count")


func test_cable_ports_are_exclusive() -> void:
	var a := _net.add_node(NetNode.Type.BEP)
	var b := _net.add_node(NetNode.Type.FLOORBOX)
	var cable := _net.add_cable(a.id, 0, b.id, 0, _line(Vector3.ZERO, Vector3(5, 0, 0)))
	assert_not_null(cable, "cable created")
	assert_eq(_net.cable_at(a.id, 0), cable, "end A lookup")
	assert_eq(_net.cable_at(b.id, 0), cable, "end B lookup")
	assert_eq(_net.add_cable(a.id, 0, b.id, 1, _line(Vector3.ZERO, Vector3.ONE)), null, "port A taken")
	assert_eq(_net.add_cable(a.id, 1, a.id, 1, _line(Vector3.ZERO, Vector3.ONE)), null, "same port twice")
	assert_not_null(_net.add_cable(a.id, 1, b.id, 1, _line(Vector3.ZERO, Vector3.ONE)), "free ports ok")


func test_remove_node_removes_its_cables() -> void:
	var a := _net.add_node(NetNode.Type.BEP)
	var b := _net.add_node(NetNode.Type.FLOORBOX)
	var c := _net.add_node(NetNode.Type.OUTLET)
	_net.add_cable(a.id, 0, b.id, 0, _line(Vector3.ZERO, Vector3.ONE))
	_net.add_cable(b.id, 1, c.id, 0, _line(Vector3.ZERO, Vector3.ONE))
	_net.remove_node(b.id)
	assert_eq(_net.cables.size(), 0, "both cables gone")
	assert_eq(_net.nodes.size(), 2, "other nodes stay")


func test_remove_cable_cuts_its_splices() -> void:
	var a := _net.add_node(NetNode.Type.BEP)
	var box := _net.add_node(NetNode.Type.FLOORBOX)
	var cable := _net.add_cable(a.id, 0, box.id, 0, _line(Vector3.ZERO, Vector3.ONE))
	box.add_splice(0, 0, 1, 0)
	box.add_splice(2, 0, 3, 0)
	_net.remove_cable(cable.id)
	assert_eq(box.links.size(), 1, "only the splice on the cut port is removed")
	assert_eq(box.links[0].port_a, 2, "unrelated splice kept")


func test_fiber_end_can_only_be_spliced_once() -> void:
	var box := _net.add_node(NetNode.Type.FLOORBOX)
	assert_not_null(box.add_splice(0, 0, 1, 0), "first splice")
	assert_eq(box.add_splice(0, 0, 1, 5), null, "fiber 0/0 already spliced")
	assert_eq(box.add_splice(2, 3, 1, 0), null, "fiber 1/0 already spliced")
	assert_not_null(box.add_splice(0, 1, 1, 1), "other fibers free")


func test_splitter_legs_share_input() -> void:
	var splitter := _net.add_node(NetNode.Type.SPLITTER)
	var legs := splitter.add_splitter(0, 0, 1, 8)
	assert_eq(legs.size(), 8, "eight legs")
	assert_eq(splitter.links_at(0, 0).size(), 8, "all on the input fiber")
	assert_eq(splitter.links_at(1, 7).size(), 1, "one per output fiber")
	assert_almost(legs[0].loss_db, LossModel.splitter_loss_db(8), 1e-9, "leg loss")


func test_save_and_load_roundtrip() -> void:
	var a := _net.add_node(NetNode.Type.BEP, Transform3D(Basis.IDENTITY, Vector3(1, 2, 3)))
	var b := _net.add_node(NetNode.Type.FLOORBOX)
	var waypoints := PackedVector3Array([Vector3.ZERO, Vector3(4, 0, 0), Vector3(4, 0, 3)])
	var cable := _net.add_cable(a.id, 0, b.id, 2, waypoints, &"g657a2", 24, 0.02)
	b.add_splice(2, 5, 3, 7, 0.07)
	_net.level_id = &"floor_0"
	assert_eq(ResourceSaver.save(_net, SAVE_PATH), OK, "save")

	var loaded: FiberNetwork = ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(loaded, "load")
	if loaded == null:
		return
	assert_eq(loaded.level_id, &"floor_0", "level id")
	assert_eq(loaded.nodes.size(), 2, "nodes")
	assert_true(loaded.nodes[a.id].transform.origin.is_equal_approx(Vector3(1, 2, 3)), "transform")
	var loaded_cable: Cable = loaded.cables[cable.id]
	assert_eq(loaded_cable.spec_id, &"g657a2", "spec")
	assert_eq(loaded_cable.fiber_count, 24, "fiber count")
	assert_eq(loaded_cable.waypoints, waypoints, "waypoints")
	assert_almost(loaded_cable.route().length_m, cable.route().length_m, 1e-9, "route length")
	var link: NetLink = loaded.nodes[b.id].links[0]
	assert_eq([link.port_a, link.fiber_a, link.port_b, link.fiber_b], [2, 5, 3, 7], "link ends")
	assert_almost(link.loss_db, 0.07, 1e-9, "link loss")
	assert_eq(loaded.next_id, _net.next_id, "id counter")
