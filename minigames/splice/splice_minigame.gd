class_name SpliceMinigame
extends CanvasLayer
## Fusion splicing screen: step list, the interactive SpliceView and step actions.
## Emits `finished` with the completed job, or `cancelled` if the splice is aborted (Esc).

signal finished(job: SpliceJob)
signal cancelled

const PANEL_SIZE := Vector2(1400, 780)
## What to do, shown when a step starts (indexed by SpliceJob.Step).
const STEP_HINTS: Array[String] = [
	"Drag the red stripper to the fiber tip. Keep the pull speed out of the red or the fiber snaps.",
	"Wipe the bare glass: drag the alcohol pad across it. Dirt left behind can spoil the splice.",
	"Cleave the left fiber: click when the marker is inside the green zone.",
	"Cleave the right fiber the same way.",
	"Line up the cores: drag up/down in the X and Y views, or use Auto align.",
	"Hold the mouse button on the fibers to arc, and release inside the green window.",
	"Protect the splice with a heat-shrink sleeve (skipping leaves it fragile).",
	"Done. Place the splice in the tray. Only an OTDR shows its real loss.",
]

static var current: SpliceMinigame

var job: SpliceJob
var title_text := ""

var view: SpliceView
var _steps: VBoxContainer
var _actions: VBoxContainer
var _readout: Label
var _message: Label
var _shown_step := -1


static func open(parent: Node, new_job: SpliceJob, left_fiber: int, right_fiber: int, title := "") -> SpliceMinigame:
	var minigame := SpliceMinigame.new()
	minigame.job = new_job
	minigame.title_text = title
	parent.add_child(minigame)
	minigame.view.color_left = FiberColors.color_for(left_fiber)
	minigame.view.color_right = FiberColors.color_for(right_fiber)
	current = minigame
	return minigame


func _ready() -> void:
	layer = 11
	_build_ui()
	job.changed.connect(_refresh)
	view.message.connect(func(text: String) -> void: _message.text = text)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"cancel"):
		abort()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()


func abort() -> void:
	_close()
	cancelled.emit()


## Hands the finished splice back. Only valid once the job is done.
func place_in_tray() -> void:
	if not job.is_done():
		return
	_close()
	finished.emit(job)


func _close() -> void:
	if current == self:
		current = null
	queue_free()


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.14, 0.98)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override(&"panel", style)
	root.add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override(&"separation", 10)
	panel.add_child(layout)
	var title := Label.new()
	title.text = "Fusion splice  ·  " + title_text
	title.add_theme_font_size_override(&"font_size", 20)
	layout.add_child(title)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 14)
	layout.add_child(body)

	_steps = VBoxContainer.new()
	_steps.custom_minimum_size = Vector2(210, 0)
	body.add_child(_steps)

	view = SpliceView.new()
	view.job = job
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(view)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(260, 0)
	side.add_theme_constant_override(&"separation", 8)
	body.add_child(side)
	_readout = Label.new()
	_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_readout)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override(&"separation", 6)
	side.add_child(_actions)

	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_message)
	var help := Label.new()
	help.text = "[Esc] abort the splice"
	help.modulate = Color(1, 1, 1, 0.55)
	layout.add_child(help)


func _refresh() -> void:
	if _shown_step != job.step:
		_shown_step = job.step
		view.reset_for_step()
		_message.text = STEP_HINTS[job.step]
	for child in _steps.get_children():
		child.queue_free()
	for i in SpliceJob.STEP_NAMES.size():
		var label := Label.new()
		label.text = ("✓ " if i < job.step else ("▶ " if i == job.step else "   ")) + SpliceJob.STEP_NAMES[i]
		label.modulate = Color(0.5, 1.0, 0.55) if i < job.step else (Color.WHITE if i == job.step else Color(1, 1, 1, 0.4))
		_steps.add_child(label)

	var lines := PackedStringArray()
	lines.append("Cleanliness %d%%" % roundi(job.cleanliness * 100.0))
	if not is_nan(job.cleave_left_deg):
		lines.append("Left cleave %.2f°" % job.cleave_left_deg)
	if not is_nan(job.cleave_right_deg):
		lines.append("Right cleave %.2f°" % job.cleave_right_deg)
	if job.step >= SpliceJob.Step.ALIGN:
		lines.append("Core offset %.2f µm" % job.offset_um.length())
	if not is_nan(job.estimated_loss_db):
		lines.append("Splicer estimate %.2f dB" % job.estimated_loss_db)
	if job.strip_breaks > 0:
		lines.append("Fibers snapped: %d" % job.strip_breaks)
	_readout.text = "\n".join(lines)

	for child in _actions.get_children():
		child.queue_free()
	match job.step:
		SpliceJob.Step.CLEAN:
			_action("Done cleaning", job.finish_cleaning)
		SpliceJob.Step.CLEAVE_LEFT, SpliceJob.Step.CLEAVE_RIGHT:
			if not is_nan(job.current_cleave_deg()):
				_action("Continue", job.accept_cleave)
				_action("Re-cleave", job.recleave)
		SpliceJob.Step.ALIGN:
			_action("Auto align", job.auto_align)
			_action("Alignment done", job.finish_align)
		SpliceJob.Step.SLEEVE:
			_action("Heat-shrink sleeve", job.sleeve.bind(true))
			_action("Skip sleeve", job.sleeve.bind(false))
		SpliceJob.Step.DONE:
			_action("Place in tray", place_in_tray)
	_action("Abort splice", abort)


func _action(text: String, callable: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(func() -> void: callable.call())
	_actions.add_child(button)
