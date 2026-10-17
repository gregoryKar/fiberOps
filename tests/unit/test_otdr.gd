extends TestCase
## M7: OTDR trace synthesis, event analysis, tool and screen.

const SEED := 12345

var _net: FiberNetwork
var _bep: NetNode
var _box: NetNode
var _outlet: NetNode
var _level: Node3D


func before_each() -> void:
	GameState.set_mode(GameState.Mode.GAMEPLAY)


func after_each() -> void:
	if OtdrScreen.current and is_instance_valid(OtdrScreen.current):
		OtdrScreen.current.close()
	if _level:
		_level.free()
		_level = null
	GameState.set_mode(GameState.Mode.GAMEPLAY)


## BEP ──feeder_m── box (splice) ──drop_m── outlet, straight G.657.A1 cables.
func _build(feeder_m: float, drop_m: float, splice_db: float, drop_waypoints := PackedVector3Array(),
		drop_spec := &"g657a1", corner_radius := 0.03) -> void:
	_net = FiberNetwork.new()
	_bep = _net.add_node(NetNode.Type.BEP)
	_box = _net.add_node(NetNode.Type.FLOORBOX)
	_outlet = _net.add_node(NetNode.Type.OUTLET)
	_net.add_cable(_bep.id, 0, _box.id, 0, PackedVector3Array([Vector3.ZERO, Vector3(feeder_m, 0, 0)]))
	var drop := drop_waypoints if not drop_waypoints.is_empty() \
			else PackedVector3Array([Vector3(feeder_m, 0, 0), Vector3(feeder_m + drop_m, 0, 0)])
	_net.add_cable(_box.id, 1, _outlet.id, 0, drop, drop_spec, 12, corner_radius)
	_box.add_splice(0, 0, 1, 0, splice_db)


func _settings(pulse_ns := 5.0, averaging_s := 60.0, wavelength := 1550, launch_m := 20.0) -> OtdrSettings:
	var settings := OtdrSettings.new()
	settings.pulse_width_ns = pulse_ns
	settings.averaging_s = averaging_s
	settings.wavelength_nm = wavelength
	settings.launch_cord_m = launch_m
	settings.noise_seed = SEED
	return settings


func _measure(settings: OtdrSettings) -> OtdrTrace:
	return OtdrSimulator.simulate(_net, _bep.id, 0, 0, settings)


func _event_near(trace: OtdrTrace, distance: float, tolerance := 0.5) -> OtdrTrace.Event:
	for event in trace.events:
		if absf(event.distance_m - distance) <= tolerance:
			return event
	return null


func _fit_slope(trace: OtdrTrace, from_m: float, to_m: float) -> float:
	return OtdrSimulator._fit(trace, from_m, to_m)["slope"]


func test_settings_derived_values() -> void:
	var s := _settings(10.0, 10.0)
	assert_almost(s.dynamic_range_db(), OtdrSettings.REFERENCE_DYNAMIC_RANGE_DB, 1e-6, "reference DR")
	assert_true(_settings(100.0, 10.0).dynamic_range_db() > s.dynamic_range_db(), "longer pulse reaches further")
	assert_true(_settings(10.0, 60.0).dynamic_range_db() > s.dynamic_range_db(), "averaging lowers the noise")
	assert_almost(s.pulse_length_m(), 1.02, 1e-6, "10 ns ≈ 1 m")
	assert_eq(OtdrSettings.auto_range_m(60.0), 100.0, "short fiber → 100 m range")
	assert_eq(OtdrSettings.auto_range_m(300.0), 500.0, "300 m → 500 m range")


func test_slope_matches_fiber_attenuation() -> void:
	_build(1000.0, 10.0, 0.05)
	var trace := _measure(_settings(30.0, 60.0, 1550, 0.0))
	var slope_db_per_km := -_fit_slope(trace, 200.0, 800.0) * 1000.0
	assert_almost(slope_db_per_km, 0.22, 0.02, "1550 nm slope")
	var at_1310 := _measure(_settings(30.0, 60.0, 1310, 0.0))
	assert_almost(-_fit_slope(at_1310, 200.0, 800.0) * 1000.0, 0.35, 0.02, "1310 nm slope")


func test_end_launch_connector_and_link_loss() -> void:
	_build(40.0, 20.0, 0.05)
	var trace := _measure(_settings())
	var end := trace.end_event()
	assert_not_null(end, "end found")
	assert_almost(end.distance_m, 80.0, 0.1, "end after 20 m launch + 60 m fiber")
	assert_almost(trace.fiber_length_m, 60.0, 0.1, "fiber length excludes the launch cord")
	assert_almost(end.reflectance_db, LossModel.FRESNEL_OPEN_END_DB, 2.0, "Fresnel end reflectance")
	var launch := trace.events[0]
	assert_eq(launch.kind, OtdrTrace.EventKind.REFLECTIVE, "port connector is reflective")
	assert_almost(launch.distance_m, 20.0, 0.1, "at the end of the launch cord")
	assert_almost(launch.reflectance_db, OtdrSimulator.LAUNCH_CONNECTOR_REFLECTANCE_DB, 3.0, "connector reflectance")
	assert_almost(launch.loss_db, OtdrSimulator.LAUNCH_CONNECTOR_LOSS_DB, 0.02, "connector loss")
	var truth := OtdrSimulator.LAUNCH_CONNECTOR_LOSS_DB + 0.05 + 0.22 * 60.0 / 1000.0
	assert_almost(trace.link_loss_db, truth, 0.03, "link loss incl. the port connector")
	assert_false(trace.end_in_noise, "end visible")


func test_gentle_bends_do_not_hide_connector_loss() -> void:
	# Drop leaves the box with 30 mm corners right after the launch connector (≈0.0001 dB each).
	var drop := PackedVector3Array([Vector3(0, 0, 0), Vector3(0.1, 0, 0), Vector3(0.1, 1, 0), Vector3(3, 1, 0), Vector3(30, 1, 0)])
	_net = FiberNetwork.new()
	_bep = _net.add_node(NetNode.Type.BEP)
	_outlet = _net.add_node(NetNode.Type.OUTLET)
	_net.add_cable(_bep.id, 0, _outlet.id, 0, drop, &"g652d", 12, 0.03)
	var launch := _measure(_settings()).events[0]
	assert_false(is_nan(launch.loss_db), "connector loss measured despite nearby gentle bends")
	assert_almost(launch.loss_db, OtdrSimulator.LAUNCH_CONNECTOR_LOSS_DB, 0.02, "connector loss")


func test_splice_loss_measured() -> void:
	_build(40.0, 20.0, 0.3)
	var splice := _event_near(_measure(_settings()), 60.0)
	assert_not_null(splice, "splice found at 60 m")
	if splice:
		assert_eq(splice.kind, OtdrTrace.EventKind.NON_REFLECTIVE, "non-reflective")
		assert_almost(splice.loss_db, 0.3, 0.02, "measured loss")
		assert_eq(splice.sources[0].kind, StrandTrace.EventKind.SPLICE, "maps to the splice")


func test_small_splice_below_threshold() -> void:
	_build(40.0, 20.0, 0.01)
	var trace := _measure(_settings())
	assert_eq(_event_near(trace, 60.0), null, "0.01 dB splice is not listed")
	assert_eq(trace.events.size(), 2, "only connector and end")


func test_bend_is_worse_at_1550_than_1310() -> void:
	# Drop with a 6 mm corner on G.652.D, 10 m after the box.
	var drop := PackedVector3Array([Vector3(40, 0, 0), Vector3(50, 0, 0), Vector3(50, 0, 10)])
	_build(40.0, 0.0, 0.02, drop, &"g652d", 0.006)
	var at_1550 := _event_near(_measure(_settings(5.0, 60.0, 1550)), 70.0)
	var at_1310 := _event_near(_measure(_settings(5.0, 60.0, 1310)), 70.0)
	assert_not_null(at_1550, "bend seen at 1550")
	if at_1550 == null:
		return
	var at_1310_loss := at_1310.loss_db if at_1310 else 0.0
	assert_true(at_1550.loss_db > 3.0 * at_1310_loss, "1550 %.3f dB vs 1310 %.3f dB" % [at_1550.loss_db, at_1310_loss])
	assert_eq(at_1550.sources[0].kind, StrandTrace.EventKind.BEND, "maps to the bend")


func test_close_events_merge_with_long_pulse() -> void:
	# Two 0.2 dB splices 1.5 m apart (extra closure on the drop).
	_build(40.0, 20.0, 0.2)
	var closure := _net.add_node(NetNode.Type.SPLICE_CLOSURE)
	_net.remove_cable(_net.cable_at(_box.id, 1).id)
	_box.add_splice(0, 0, 1, 0, 0.2)
	_net.add_cable(_box.id, 1, closure.id, 0, PackedVector3Array([Vector3(40, 0, 0), Vector3(41.5, 0, 0)]))
	_net.add_cable(closure.id, 1, _outlet.id, 0, PackedVector3Array([Vector3(41.5, 0, 0), Vector3(60, 0, 0)]))
	closure.add_splice(0, 0, 1, 0, 0.2)

	var short_pulse := _measure(_settings(3.0))
	assert_not_null(_event_near(short_pulse, 60.0, 0.2), "3 ns: first splice")
	assert_not_null(_event_near(short_pulse, 61.5, 0.2), "3 ns: second splice")
	var long_pulse := _measure(_settings(30.0))
	var merged := _event_near(long_pulse, 60.0, 0.2)
	assert_not_null(merged, "30 ns: one event")
	assert_eq(_event_near(long_pulse, 61.5, 0.2), null, "second splice hidden in the dead zone")
	if merged:
		assert_eq(merged.sources.size(), 2, "stands for both splices")


func test_end_lost_in_noise() -> void:
	_build(40.0, 20.0, 30.0)  # a 30 dB fault drops the trace below the floor
	var trace := _measure(_settings(3.0, 1.0))
	assert_true(trace.end_in_noise, "end lost")
	assert_true(is_nan(trace.link_loss_db), "no link loss")
	var tail := 0.0
	for i in range(trace.index_at(65.0), trace.index_at(78.0)):
		tail += trace.samples[i]
	tail /= trace.index_at(78.0) - trace.index_at(65.0)
	assert_almost(tail, trace.noise_floor_db, 3.0, "trace sits at the noise floor")


func test_splitter_step_and_branches() -> void:
	_build(40.0, 5.0, 0.02)
	var splitter := _net.add_node(NetNode.Type.SPLITTER)
	_net.remove_cable(_net.cable_at(_box.id, 1).id)
	_box.add_splice(0, 0, 1, 0, 0.02)
	_net.add_cable(_box.id, 1, splitter.id, 0, PackedVector3Array([Vector3(40, 0, 0), Vector3(45, 0, 0)]))
	var far := _net.add_node(NetNode.Type.FLOORBOX)
	_net.add_cable(splitter.id, 1, far.id, 0, PackedVector3Array([Vector3(45, 0, 0), Vector3(65, 0, 0)]))
	splitter.add_splitter(0, 0, 1, 8)

	var trace := _measure(_settings())
	assert_eq(trace.branch_count, 8, "eight branches")
	var step := _event_near(trace, 65.0)
	assert_not_null(step, "splitter event")
	if step:
		var apparent := LossModel.splitter_loss_db(8) - 5.0 * log(8.0) / log(10.0)
		assert_almost(step.loss_db, apparent, 0.1, "OTDR sees split loss − 5·log10(N)")


func test_same_seed_same_trace() -> void:
	_build(40.0, 20.0, 0.1)
	assert_eq(_measure(_settings()).samples, _measure(_settings()).samples, "deterministic")


func test_otdr_tool_and_screen_in_level() -> void:
	_level = load("res://levels/test_floor/test_floor.tscn").instantiate()
	tree.root.add_child(_level)
	var player: Player = _level.get_node("Player")
	var level_network: LevelNetwork = _level.get_node("LevelNetwork")
	var basis := BuildTool.wall_basis(Vector3(0, 0, -1), 0)
	var box := level_network.place(PlaceableDef.for_node_type(NetNode.Type.FLOORBOX), Transform3D(basis, Vector3(-3.0, 1.6, 0.859)))
	var outlet := level_network.place(PlaceableDef.for_node_type(NetNode.Type.OUTLET), Transform3D(basis, Vector3(-6.0, 0.5, 0.884)))
	level_network.network.add_cable(box.id, 0, outlet.id, 0,
			PackedVector3Array([level_network.port_position(box.id, 0), level_network.port_position(outlet.id, 0)]), &"g657a1", 12)
	player.tool_belt.select_slot(4)
	var tool: OtdrTool = player.tool_belt.tool_node(&"otdr")
	player.global_position = Vector3(-3.0, 0, 0)
	player.rotation = Vector3(0, PI, 0)
	player.head.rotation.x = -0.1
	for i in 10:
		await tree.physics_frame

	assert_eq(tool.node_id, box.id, "targets the box")
	assert_eq(tool.port, 0, "the only port with a cable")
	tool.select_fiber(-1)
	assert_eq(tool.fiber, 11, "scroll wraps to fiber 12")
	tool.select_fiber(2)
	assert_true(tool.get_hud_text().contains("#3 green"), tool.get_hud_text())

	var screen := tool.open_screen()
	assert_not_null(screen, "screen open")
	assert_eq(GameState.mode, GameState.Mode.UI, "UI mode")
	var trace := screen.measure_now()
	assert_not_null(trace, "measured")
	assert_almost(trace.fiber_length_m, level_network.network.cable_at(box.id, 0).route().length_m, 0.1, "sees the cable")
	assert_true(screen.verdict().is_empty(), "short clean drop passes: %s" % [screen.verdict()])
	screen.close()
	assert_eq(GameState.mode, GameState.Mode.GAMEPLAY, "closed")
