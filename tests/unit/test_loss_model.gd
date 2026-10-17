extends TestCase
## M2: fiber specs and loss formulas.

const SPEC_IDS: Array[StringName] = [&"g652d", &"g657a1", &"g657a2"]


func _one_turn_loss(spec: FiberSpec, radius_m: float, wavelength := 1550) -> float:
	return LossModel.bend_loss_db(spec, radius_m, TAU * radius_m, wavelength)


func test_specs_load() -> void:
	for spec_id in SPEC_IDS:
		var spec := FiberSpec.get_spec(spec_id)
		assert_not_null(spec, "spec %s" % spec_id)
		if spec:
			assert_eq(spec.id, spec_id, "spec id")


func test_attenuation_per_wavelength() -> void:
	var spec := FiberSpec.get_spec(&"g652d")
	assert_almost(LossModel.attenuation_db(spec, 1000.0, 1310), 0.35, 1e-9, "1 km @1310")
	assert_almost(LossModel.attenuation_db(spec, 1000.0, 1550), 0.22, 1e-9, "1 km @1550")
	assert_almost(LossModel.attenuation_db(spec, 50.0, 1550), 0.011, 1e-9, "50 m @1550")


func test_bend_fit_reproduces_reference_points() -> void:
	for spec_id in SPEC_IDS:
		var spec := FiberSpec.get_spec(spec_id)
		var r1 := spec.bend_ref_radius_1_mm * 0.001
		var r2 := spec.bend_ref_radius_2_mm * 0.001
		assert_almost(_one_turn_loss(spec, r1), spec.bend_ref_loss_1_db, 1e-9, "%s ref 1" % spec_id)
		assert_almost(_one_turn_loss(spec, r2), spec.bend_ref_loss_2_db, 1e-9, "%s ref 2" % spec_id)


func test_g657a2_meets_itu_10mm_limit() -> void:
	# ITU-T G.657.A2: one turn at R = 10 mm must stay at or below 0.1 dB @1550.
	var loss := _one_turn_loss(FiberSpec.get_spec(&"g657a2"), 0.010)
	assert_true(loss <= 0.1 and loss > 0.05, "G.657.A2 10 mm turn = %f dB" % loss)


func test_bend_loss_grows_with_wavelength() -> void:
	var spec := FiberSpec.get_spec(&"g657a1")
	var l1310 := _one_turn_loss(spec, 0.008, 1310)
	var l1550 := _one_turn_loss(spec, 0.008, 1550)
	var l1625 := _one_turn_loss(spec, 0.008, 1625)
	assert_true(l1310 < l1550 and l1550 < l1625, "1310 %f < 1550 %f < 1625 %f" % [l1310, l1550, l1625])


func test_bend_loss_falls_with_radius() -> void:
	var spec := FiberSpec.get_spec(&"g652d")
	var previous := INF
	for radius_mm in [5.0, 10.0, 15.0, 20.0, 30.0, 50.0]:
		var alpha := LossModel.bend_db_per_m(spec, radius_mm * 0.001, 1550)
		assert_true(alpha < previous, "α must drop as radius grows (R=%s mm)" % radius_mm)
		previous = alpha


func test_bend_insensitive_fiber_is_better_at_every_radius() -> void:
	# The fitted curves must never cross: G.652D ≥ G.657A1 ≥ G.657A2 for all practical radii.
	for radius_mm in [3.0, 4.0, 5.0, 7.5, 10.0, 15.0, 20.0, 30.0]:
		for wavelength in FiberSpec.WAVELENGTHS:
			var r: float = radius_mm * 0.001
			var d := _one_turn_loss(FiberSpec.get_spec(&"g652d"), r, wavelength)
			var a1 := _one_turn_loss(FiberSpec.get_spec(&"g657a1"), r, wavelength)
			var a2 := _one_turn_loss(FiberSpec.get_spec(&"g657a2"), r, wavelength)
			assert_true(d >= a1 and a1 >= a2, "R=%s mm @%d: 652D %f, A1 %f, A2 %f" % [radius_mm, wavelength, d, a1, a2])


func test_g657a1_meets_itu_10mm_limit() -> void:
	# ITU-T G.657.A1: one turn at R = 10 mm must stay at or below 0.75 dB @1550.
	assert_true(_one_turn_loss(FiberSpec.get_spec(&"g657a1"), 0.010) <= 0.75, "A1 10 mm turn")


func test_straight_and_capped_bends() -> void:
	var spec := FiberSpec.get_spec(&"g652d")
	assert_eq(LossModel.bend_db_per_m(spec, INF, 1550), 0.0, "straight fiber")
	assert_eq(LossModel.bend_db_per_m(spec, 0.0001, 1625), LossModel.MAX_BEND_DB_PER_M, "capped density")


func test_splitter_losses_match_plc_datasheets() -> void:
	assert_almost(LossModel.splitter_loss_db(2), 3.6, 0.15, "1:2")
	assert_almost(LossModel.splitter_loss_db(8), 10.3, 0.15, "1:8")
	assert_almost(LossModel.splitter_loss_db(32), 16.8, 0.2, "1:32")


func test_break_radius() -> void:
	var spec := FiberSpec.get_spec(&"g657a1")
	assert_true(LossModel.is_broken(spec, 0.002), "2 mm breaks A1")
	assert_false(LossModel.is_broken(spec, 0.005), "5 mm survives")
