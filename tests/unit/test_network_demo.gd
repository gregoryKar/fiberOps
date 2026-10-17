extends TestCase
## Debug network demo: the scene builds, renders and traces what it claims to.

var _demo: Node3D


func after_each() -> void:
	if _demo:
		_demo.free()


func _trace(launch_index: int) -> Array[StrandTrace]:
	var built: Dictionary = load("res://levels/debug/network_demo.gd").build_demo_network()
	var launch: Dictionary = built["launches"][launch_index]
	return StrandTracer.trace(built["network"], launch["node"], launch["port"], launch["fiber"])


func test_scene_builds_meshes_and_overlay() -> void:
	_demo = load("res://levels/debug/network_demo.tscn").instantiate()
	tree.root.add_child(_demo)
	var view: NetworkView = _demo.get_node("NetworkView")
	assert_eq(view.network.nodes.size(), 7, "nodes")
	assert_eq(view.network.cables.size(), 6, "cables")
	var meshes := view.find_children("*", "MeshInstance3D", true, false)
	assert_true(meshes.size() >= 13, "7 node boxes + 6 cable tubes, got %d" % meshes.size())
	var overlay: TraceOverlay = _demo.get_node("TraceOverlay")
	assert_not_null(overlay.current_trace(), "overlay traces the first launch")


func test_good_drop_is_cheap() -> void:
	var trace := _trace(0)[0]
	assert_eq(trace.end_kind, StrandTrace.EndKind.OPEN_END, "reaches the outlet")
	assert_true(trace.total_loss_db() < 0.2, "good drop %f dB" % trace.total_loss_db())


func test_tight_g652d_drop_is_lossy() -> void:
	var trace := _trace(1)[0]
	var lossy := trace.events_of_kind(StrandTrace.EventKind.BEND).filter(
			func(e: StrandTrace.Event) -> bool: return e.loss_db > 0.1)
	assert_eq(lossy.size(), 2, "two tight corners (the feeder's 30 mm corners are negligible)")
	assert_true(trace.total_loss_db() > 2.0, "tight drop %f dB" % trace.total_loss_db())


func test_hairpin_breaks_and_splitter_fans_out() -> void:
	assert_eq(_trace(3)[0].end_kind, StrandTrace.EndKind.BREAK, "hairpin breaks")
	assert_eq(_trace(4).size(), 4, "1:4 splitter branches")


func test_cable_mesh_and_bend_colors() -> void:
	var path := CablePath.build(PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0), Vector3(1, 1, 0)]), 0.05)
	var points := path.sample(0.1)
	assert_eq(path.sample_distances(0.1).size(), points.size(), "one distance per point")
	var mesh := CableMesh.build(points, PackedColorArray(), 0.01, 6)
	assert_not_null(mesh, "mesh built")
	if mesh:
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		assert_eq(vertices.size(), points.size() * 6, "one ring per point")
	assert_eq(CableMesh.build(PackedVector3Array([Vector3.ZERO]), PackedColorArray()), null, "needs two points")
	var spec := FiberSpec.get_spec(&"g657a1")
	assert_true(CableMesh.bend_color(spec, 0.02).g > 0.8, "20 mm on A1 is green")
	assert_true(CableMesh.bend_color(spec, 0.003).r > 0.9 and CableMesh.bend_color(spec, 0.003).g < 0.3, "3 mm is red")
	assert_almost(path.radius_at(1.0), 0.05, 1e-9, "radius at the corner")
	assert_eq(path.radius_at(0.2), INF, "straight")
