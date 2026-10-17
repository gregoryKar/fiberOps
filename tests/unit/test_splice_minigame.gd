extends TestCase
## M6: fusion splicing — loss physics, the step flow and the tray round trip.

var _a1: FiberSpec
var _level: Node3D


func before_each() -> void:
	GameState.set_mode(GameState.Mode.GAMEPLAY)
	_a1 = FiberSpec.get_spec(&"g657a1")


func after_each() -> void:
	if SpliceMinigame.current and is_instance_valid(SpliceMinigame.current):
		SpliceMinigame.current.abort()
	if SpliceTray.current and is_instance_valid(SpliceTray.current):
		SpliceTray.current.close()
	if _level:
		_level.free()
		_level = null
	GameState.set_mode(GameState.Mode.GAMEPLAY)


## Runs a job through every step with the given quality knobs.
func _run(job: SpliceJob, wipes: int, cleave_error: float, auto_align: bool, arc_s: float, sleeve := true) -> void:
	job.complete_strip()
	for i in wipes:
		job.wipe()
	job.finish_cleaning()
	job.cleave(cleave_error)
	job.accept_cleave()
	job.cleave(cleave_error)
	job.accept_cleave()
	if auto_align:
		job.auto_align()
	job.finish_align()
	job.arc(arc_s)
	job.sleeve(sleeve)


func test_loss_terms() -> void:
	var perfect := SpliceJob.compute_loss(_a1, _a1, 0.0, 0.0, 1.3, 0.0, 0.0)
	assert_almost(perfect["total"], SpliceJob.INTRINSIC_DB, 1e-9, "perfect splice = intrinsic loss only")
	assert_almost(perfect["mfd"], 0.0, 1e-9, "same fiber type: no mode-field mismatch")
	# 1 µm offset, halved by self-alignment, on w = 5.2 µm: 4.343·(0.5/5.2)².
	var offset := SpliceJob.compute_loss(_a1, _a1, 1.0, 0.0, 1.3, 0.0, 0.0)
	assert_almost(offset["offset"], 4.343 * pow(0.5 / 5.2, 2.0), 1e-9, "offset term")
	var tilted := SpliceJob.compute_loss(_a1, _a1, 0.0, 3.0, 1.3, 0.0, 0.0)
	assert_true(tilted["tilt"] > 0.3 and tilted["tilt"] < 0.6, "3° cleaves cost ~0.4 dB: %f" % tilted["tilt"])
	var short_arc := SpliceJob.compute_loss(_a1, _a1, 0.0, 0.0, 0.5, 0.0, 0.0)
	var long_arc := SpliceJob.compute_loss(_a1, _a1, 0.0, 0.0, 2.5, 0.0, 0.0)
	assert_true(short_arc["arc"] > 0.2, "weak arc: %f" % short_arc["arc"])
	assert_true(long_arc["arc"] > 0.0 and long_arc["arc"] <= 0.2, "over-arc: %f" % long_arc["arc"])


func test_good_splice_is_low_loss() -> void:
	var job := SpliceJob.new(_a1, _a1, 4242)
	_run(job, 3, 0.0, true, 1.3)
	assert_true(job.is_done(), "done")
	assert_true(job.true_loss_db < 0.06, "good splice %f dB" % job.true_loss_db)
	assert_false(job.contaminated, "clean fiber never contaminated")
	assert_true(job.protected, "sleeved")
	assert_true(job.estimated_loss_db >= 0.01, "splicer shows at least 0.01 dB")


func test_sloppy_splice_is_lossy() -> void:
	var job := SpliceJob.new(_a1, _a1, 4242)
	_run(job, 3, 1.0, false, 0.4, false)
	assert_true(job.true_loss_db > 0.5, "bad cleaves, no alignment, short arc: %f dB" % job.true_loss_db)
	assert_false(job.protected, "no sleeve")


func test_contamination_fools_the_splicer() -> void:
	# Never cleaned: with enough tries some splice is contaminated.
	for seed_value in range(1, 40):
		var job := SpliceJob.new(_a1, _a1, seed_value)
		_run(job, 0, 0.0, true, 1.3)
		if job.contaminated:
			assert_true(job.breakdown["contamination"] >= 0.15, "bubble loss")
			assert_true(job.true_loss_db - job.estimated_loss_db > 0.1,
					"splicer misses most of it: true %f, est %f" % [job.true_loss_db, job.estimated_loss_db])
			return
	fail("no contamination in 39 uncleaned splices")


func test_cleaning_raises_cleanliness_and_caps() -> void:
	var job := SpliceJob.new(_a1, _a1, 1)
	job.complete_strip()
	for i in 5:
		job.wipe()
	assert_almost(job.cleanliness, 1.0, 1e-9, "capped at 100%")


func test_cleave_angles_and_recleave() -> void:
	var job := SpliceJob.new(_a1, _a1, 9)
	job.complete_strip()
	job.finish_cleaning()
	var bad := job.cleave(1.0)
	assert_true(bad > SpliceJob.CLEAVE_LIMIT_DEG, "edge of the window: %f°" % bad)
	job.recleave()
	assert_true(is_nan(job.cleave_left_deg), "cleave discarded")
	var good := job.cleave(0.0)
	assert_true(good < 0.25, "perfect timing: %f°" % good)
	job.accept_cleave()
	assert_eq(job.step, SpliceJob.Step.CLEAVE_RIGHT, "on to the right fiber")


func test_snapped_fiber_and_step_guard() -> void:
	var job := SpliceJob.new(_a1, _a1, 3)
	job.snap_fiber()
	assert_eq(job.strip_breaks, 1, "counted")
	assert_eq(job.step, SpliceJob.Step.STRIP, "still stripping")
	var changed := [0]
	job.changed.connect(func() -> void: changed[0] += 1)
	job.complete_strip()
	assert_true(changed[0] > 0, "changes reported")


func test_auto_align_leaves_small_offset() -> void:
	var job := SpliceJob.new(_a1, _a1, 5)
	assert_true(job.offset_um.length() > 0.0, "starts misaligned")
	job.complete_strip()
	job.finish_cleaning()
	job.cleave(0.0)
	job.accept_cleave()
	job.cleave(0.0)
	job.accept_cleave()
	job.move_core(Vector2(1, 0))
	job.auto_align()
	assert_true(job.offset_um.length() <= 0.45 and job.offset_um.length() >= 0.15, "auto: %f µm" % job.offset_um.length())


func test_tray_runs_splicer_and_stores_result() -> void:
	_level = load("res://levels/test_floor/test_floor.tscn").instantiate()
	tree.root.add_child(_level)
	var level_network: LevelNetwork = _level.get_node("LevelNetwork")
	var basis := BuildTool.wall_basis(Vector3(0, 0, -1), 0)
	var bep := level_network.place(PlaceableDef.for_node_type(NetNode.Type.BEP), Transform3D(basis, Vector3(-8.0, 1.5, 0.839)))
	var box := level_network.place(PlaceableDef.for_node_type(NetNode.Type.FLOORBOX), Transform3D(basis, Vector3(-5.0, 1.6, 0.859)))
	var outlet := level_network.place(PlaceableDef.for_node_type(NetNode.Type.OUTLET), Transform3D(basis, Vector3(-3.0, 0.5, 0.884)))
	var net := level_network.network
	net.add_cable(bep.id, 0, box.id, 0, PackedVector3Array([Vector3(-8, 1, 0.8), Vector3(-5, 1, 0.8)]), &"g657a1", 12)
	net.add_cable(box.id, 1, outlet.id, 0, PackedVector3Array([Vector3(-5, 1, 0.8), Vector3(-3, 1, 0.8)]), &"g657a1", 2)

	var tray := SpliceTray.open(level_network, box.id)
	await tree.process_frame
	tray.model.click_fiber(0, 0)
	tray.model.click_fiber(1, 0)
	var minigame := SpliceMinigame.current
	assert_not_null(minigame, "second fiber starts the splicer")
	assert_false(tray.visible, "tray hidden while splicing")
	assert_eq(box.links.size(), 0, "no splice until the splicer finishes")

	# A contaminated-free, decent splice driven through the screen's own job.
	_run(minigame.job, 3, 0.1, true, 1.2)
	var true_loss := minigame.job.true_loss_db
	minigame.place_in_tray()
	assert_true(tray.visible, "tray back")
	assert_eq(box.links.size(), 1, "splice stored")
	var link := box.links[0]
	assert_almost(link.loss_db, true_loss, 1e-9, "true loss on the link")
	assert_false(is_nan(link.estimated_loss_db), "splicer estimate kept")
	assert_true(SpliceTrayModel.loss_label(link).ends_with("est."), SpliceTrayModel.loss_label(link))

	# The OTDR sees the true loss.
	var trace := StrandTracer.trace(net, bep.id, 0, 0)[0]
	assert_almost(trace.events_of_kind(StrandTrace.EventKind.SPLICE)[0].loss_db, true_loss, 1e-9, "tracer uses true loss")
	assert_eq(trace.end_event().node_id, outlet.id, "light reaches the outlet")

	# Aborting another splice leaves the network alone.
	tray.model.click_fiber(0, 1)
	tray.model.click_fiber(1, 1)
	SpliceMinigame.current.abort()
	assert_true(tray.visible, "tray back after abort")
	assert_eq(box.links.size(), 1, "aborted splice not stored")


func test_unsleeved_splice_is_flagged() -> void:
	var link := NetLink.create(NetLink.Kind.FUSION_SPLICE, 0, 0, 1, 0, 0.05)
	link.estimated_loss_db = 0.02
	link.protected = false
	assert_almost(link.displayed_loss_db(), 0.02, 1e-9, "shows the estimate")
	assert_true(SpliceTrayModel.loss_label(link).contains("no sleeve"), SpliceTrayModel.loss_label(link))


func test_minigame_screen_builds_every_step() -> void:
	var job := SpliceJob.new(_a1, _a1, 11)
	var minigame := SpliceMinigame.open(tree.root, job, 0, 1, "test")
	await tree.process_frame
	for i in SpliceJob.Step.size():
		await tree.process_frame
		match job.step:
			SpliceJob.Step.STRIP:
				minigame.view.advance_strip(1.0)
			SpliceJob.Step.CLEAN:
				job.finish_cleaning()
			SpliceJob.Step.CLEAVE_LEFT, SpliceJob.Step.CLEAVE_RIGHT:
				job.cleave(0.0)
				job.accept_cleave()
			SpliceJob.Step.ALIGN:
				job.auto_align()
				job.finish_align()
			SpliceJob.Step.ARC:
				job.arc(1.2)
			SpliceJob.Step.SLEEVE:
				job.sleeve(true)
	assert_true(job.is_done(), "walked through every step")
	var results: Array = []
	minigame.finished.connect(func(done: SpliceJob) -> void: results.append(done))
	minigame.place_in_tray()
	assert_eq(results.size(), 1, "finished emitted")
