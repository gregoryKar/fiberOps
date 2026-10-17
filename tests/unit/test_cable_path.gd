extends TestCase
## M2: cable route geometry (straights + fillet arcs).


func _path(points: Array, radius := 0.03) -> CablePath:
	return CablePath.build(PackedVector3Array(points), radius)


func _assert_continuous(path: CablePath, step: float) -> void:
	var points := path.sample(step)
	for i in range(1, points.size()):
		var gap := points[i].distance_to(points[i - 1])
		if gap > step + 1e-6:
			fail("gap %f between samples %d and %d" % [gap, i - 1, i])
			return


func test_empty_and_single_point() -> void:
	assert_eq(_path([]).length_m, 0.0, "empty")
	assert_eq(_path([Vector3.ONE]).length_m, 0.0, "single point")
	assert_eq(_path([Vector3.ONE]).sample(0.1).size(), 0, "no samples")


func test_straight_cable() -> void:
	var path := _path([Vector3.ZERO, Vector3(10, 0, 0)])
	assert_almost(path.length_m, 10.0, 1e-9, "length")
	assert_eq(path.sections.size(), 1, "one section")
	assert_eq(path.min_radius(), INF, "no bends")
	assert_true(path.point_at(5.0).is_equal_approx(Vector3(5, 0, 0)), "midpoint")


func test_right_angle_corner() -> void:
	var r := 0.5
	var path := _path([Vector3.ZERO, Vector3(10, 0, 0), Vector3(10, 0, 10)], r)
	assert_almost(path.length_m, 20.0 - 2.0 * r + r * PI / 2.0, 1e-9, "length")
	var arcs := path.arcs()
	assert_eq(arcs.size(), 1, "one arc")
	assert_almost(arcs[0].radius_m, r, 1e-9, "radius")
	assert_almost(arcs[0].angle, PI / 2.0, 1e-9, "angle")
	var center := Vector3(10 - r, 0, r)
	assert_true(arcs[0].origin.is_equal_approx(center), "centre %s" % arcs[0].origin)
	for k in 11:
		var p := arcs[0].point_at(arcs[0].length_m * k / 10.0)
		assert_almost(p.distance_to(center), r, 1e-6, "arc point %d on circle" % k)
	assert_true(path.point_at(path.length_m).is_equal_approx(Vector3(10, 0, 10)), "ends at last waypoint")
	assert_true(arcs[0].point_at(arcs[0].length_m).is_equal_approx(Vector3(10, 0, r)), "arc meets outgoing run")
	_assert_continuous(path, 0.05)


func test_close_waypoints_force_tighter_radius() -> void:
	# U-turn with a 2 cm middle leg: each corner may only use half of it (1 cm).
	var path := _path([Vector3.ZERO, Vector3(1, 0, 0), Vector3(1, 0, 0.02), Vector3(0, 0, 0.02)], 0.03)
	assert_eq(path.arcs().size(), 2, "two corners")
	assert_almost(path.min_radius(), 0.01, 1e-9, "radius clamped to the room available")
	_assert_continuous(path, 0.005)


func test_vertical_corner_reaches_end() -> void:
	var path := _path([Vector3.ZERO, Vector3(0, 2, 0), Vector3(1, 2, 0)], 0.1)
	assert_almost(path.arcs()[0].radius_m, 0.1, 1e-9, "radius")
	assert_true(path.point_at(path.length_m).is_equal_approx(Vector3(1, 2, 0)), "end point")
	_assert_continuous(path, 0.02)


func test_collinear_and_duplicate_points() -> void:
	var path := _path([Vector3.ZERO, Vector3(5, 0, 0), Vector3(5, 0, 0), Vector3(10, 0, 0)])
	assert_eq(path.arcs().size(), 0, "no arcs")
	assert_almost(path.length_m, 10.0, 1e-9, "length")


func test_full_reversal_stays_finite() -> void:
	var path := _path([Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 0, 0)], 0.05)
	assert_true(is_finite(path.length_m), "finite length")
	for p in path.sample(0.01):
		assert_true(is_finite(p.x) and is_finite(p.y) and is_finite(p.z), "finite sample")
	assert_true(path.min_radius() < 0.001, "hairpin is extremely tight")
