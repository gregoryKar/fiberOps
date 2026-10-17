class_name SpliceJob
extends RefCounted
## State and physics of one fusion splice, step by step. The minigame screen drives it; the
## outcome is the splice's true loss (what the OTDR will see) and the splicer's estimate
## (what the technician is shown).
##
## Loss terms (fiber optics standard formulas, Gaussian mode approximation):
##   core offset d:      4.343·(d/w)², reduced by surface-tension self-alignment during fusion
##   end-face tilt θ:    4.343·(π·n·w·θ/λ)², mostly forgiven by fusion
##   mode-field mismatch: −20·log10(2·w1·w2 / (w1² + w2²))
##   contamination:      a bubble or inclusion, 0.15–0.6 dB, nearly invisible to the splicer
##   arc time:           too short → weak, lossy joint; too long → thinned fiber

signal changed

enum Step { STRIP, CLEAN, CLEAVE_LEFT, CLEAVE_RIGHT, ALIGN, ARC, SLEEVE, DONE }

const STEP_NAMES: Array[String] = [
	"Strip coating", "Clean with alcohol", "Cleave left fiber", "Cleave right fiber",
	"Align cores", "Fuse (arc)", "Heat-shrink sleeve", "Done",
]
const WAVELENGTH_UM := 1.55
const GROUP_INDEX := 1.468
## Fraction of the core offset left after fusion pulls the fibers together.
const SELF_ALIGNMENT := 0.5
## Fraction of the tilt loss left after the glass flows during fusion.
const TILT_FORGIVENESS := 0.15
const CLEAVE_BEST_DEG := 0.1
const CLEAVE_WORST_DEG := 3.0
## Splicers ask for a re-cleave above this.
const CLEAVE_LIMIT_DEG := 1.5
const ARC_IDEAL_S := Vector2(1.0, 1.6)
const ARC_MIN_S := 0.3
const INITIAL_OFFSET_UM := 6.0
const CLEAN_START := 0.2
const CLEAN_PER_WIPE := 0.3
## Chance of contamination at zero cleanliness.
const MAX_CONTAMINATION_CHANCE := 0.6
const INTRINSIC_DB := 0.01

var step := Step.STRIP
var spec_left: FiberSpec
var spec_right: FiberSpec
var cleanliness := CLEAN_START
var cleave_left_deg := NAN
var cleave_right_deg := NAN
## Lateral core offset of the right fiber against the left, in µm (x and y views).
var offset_um := Vector2.ZERO
var arc_s := NAN
var protected := false
var contaminated := false
var strip_breaks := 0
var true_loss_db := NAN
var estimated_loss_db := NAN
## Per-term breakdown of the true loss (for the summary and tests).
var breakdown: Dictionary = {}

var rng := RandomNumberGenerator.new()


func _init(left: FiberSpec, right: FiberSpec, seed_value := 0) -> void:
	spec_left = left
	spec_right = right
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	offset_um = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * INITIAL_OFFSET_UM


func step_name() -> String:
	return STEP_NAMES[step]


func complete_strip() -> void:
	_expect(Step.STRIP)
	_advance(Step.CLEAN)


## Records that the stripper was pulled too fast and snapped the fiber: start the strip over.
func snap_fiber() -> void:
	_expect(Step.STRIP)
	strip_breaks += 1
	changed.emit()


func wipe() -> void:
	_expect(Step.CLEAN)
	cleanliness = minf(1.0, cleanliness + CLEAN_PER_WIPE)
	changed.emit()


func finish_cleaning() -> void:
	_expect(Step.CLEAN)
	_advance(Step.CLEAVE_LEFT)


## Cleaves the current fiber. `timing_error` is how far from perfect the player hit the
## cleave window, 0 (perfect) to 1 (edge). Returns the end-face angle in degrees.
func cleave(timing_error: float) -> float:
	var error := clampf(absf(timing_error), 0.0, 1.0)
	var angle := CLEAVE_BEST_DEG + (CLEAVE_WORST_DEG - CLEAVE_BEST_DEG) * pow(error, 1.5) \
			+ rng.randf_range(0.0, 0.1)
	if step == Step.CLEAVE_LEFT:
		cleave_left_deg = angle
	elif step == Step.CLEAVE_RIGHT:
		cleave_right_deg = angle
	else:
		push_error("cleave() outside a cleave step")
	changed.emit()
	return angle


func current_cleave_deg() -> float:
	return cleave_left_deg if step == Step.CLEAVE_LEFT else cleave_right_deg


## Throws away the current cleave so the fiber can be cleaved again.
func recleave() -> void:
	if step == Step.CLEAVE_LEFT:
		cleave_left_deg = NAN
	elif step == Step.CLEAVE_RIGHT:
		cleave_right_deg = NAN
	changed.emit()


## Accepts the current cleave and moves on.
func accept_cleave() -> void:
	if step == Step.CLEAVE_LEFT and not is_nan(cleave_left_deg):
		_advance(Step.CLEAVE_RIGHT)
	elif step == Step.CLEAVE_RIGHT and not is_nan(cleave_right_deg):
		_advance(Step.ALIGN)


func move_core(delta_um: Vector2) -> void:
	_expect(Step.ALIGN)
	offset_um += delta_um
	changed.emit()


## The splicer's automatic alignment: good but not perfect.
func auto_align() -> void:
	_expect(Step.ALIGN)
	offset_um = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.15, 0.45)
	changed.emit()


func finish_align() -> void:
	_expect(Step.ALIGN)
	_advance(Step.ARC)


## Fuses the fibers with an arc of the given duration and computes the result.
func arc(duration_s: float) -> void:
	_expect(Step.ARC)
	arc_s = duration_s
	var contamination_chance := (1.0 - cleanliness) * MAX_CONTAMINATION_CHANCE
	contaminated = rng.randf() < contamination_chance
	breakdown = compute_loss(spec_left, spec_right, offset_um.length(),
			(cleave_left_deg + cleave_right_deg) * 0.5, duration_s,
			rng.randf_range(0.15, 0.6) if contaminated else 0.0, rng.randf_range(0.0, 0.02))
	true_loss_db = breakdown["total"]
	# The splicer images the joint: it sees geometry but hardly any inclusions.
	var seen: float = breakdown["offset"] + breakdown["tilt"] + breakdown["mfd"] + breakdown["arc"]
	estimated_loss_db = maxf(0.01, snappedf(seen * rng.randf_range(0.8, 1.1) + INTRINSIC_DB * 0.5
			+ breakdown["contamination"] * 0.2, 0.01))
	_advance(Step.SLEEVE)


func sleeve(apply: bool) -> void:
	_expect(Step.SLEEVE)
	protected = apply
	_advance(Step.DONE)


func is_done() -> bool:
	return step == Step.DONE


## Splice loss terms in dB for the given geometry. Keys: offset, tilt, mfd, arc,
## contamination, intrinsic, total.
static func compute_loss(left: FiberSpec, right: FiberSpec, offset_um_value: float, tilt_deg: float,
		arc_duration_s: float, contamination_db: float, intrinsic_jitter_db: float) -> Dictionary:
	var w1: float = left.mode_field_diameter_um[1550] * 0.5
	var w2: float = right.mode_field_diameter_um[1550] * 0.5
	var w := (w1 + w2) * 0.5
	var d := offset_um_value * SELF_ALIGNMENT
	var offset := 4.343 * pow(d / w, 2.0)
	var theta := deg_to_rad(tilt_deg)
	var tilt := 4.343 * pow(PI * GROUP_INDEX * w * theta / WAVELENGTH_UM, 2.0) * TILT_FORGIVENESS
	var mfd := -20.0 * log(2.0 * w1 * w2 / (w1 * w1 + w2 * w2)) / log(10.0)
	var arc_loss := 0.0
	if arc_duration_s < ARC_IDEAL_S.x:
		arc_loss = 0.5 * (ARC_IDEAL_S.x - maxf(arc_duration_s, ARC_MIN_S)) / (ARC_IDEAL_S.x - ARC_MIN_S)
	elif arc_duration_s > ARC_IDEAL_S.y:
		arc_loss = minf(0.2, 0.1 * (arc_duration_s - ARC_IDEAL_S.y))
	var intrinsic := INTRINSIC_DB + intrinsic_jitter_db
	return {
		"offset": offset, "tilt": tilt, "mfd": mfd, "arc": arc_loss,
		"contamination": contamination_db, "intrinsic": intrinsic,
		"total": offset + tilt + mfd + arc_loss + contamination_db + intrinsic,
	}


func _expect(expected: Step) -> void:
	if step != expected:
		push_error("SpliceJob: expected step %s, at %s" % [STEP_NAMES[expected], STEP_NAMES[step]])


func _advance(next: Step) -> void:
	step = next
	changed.emit()
