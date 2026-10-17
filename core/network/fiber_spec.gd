class_name FiberSpec
extends Resource
## Optical properties of a fiber type (G.652D, G.657A1, ...).
## Tunable values live in core/network/specs/<id>.tres and are loaded through get_spec().
##
## Macrobend loss model: α(R) = A·e^(−B·R) dB per metre of bent fiber. A and B are fitted
## through two reference points given as "loss for one 360° turn at radius R" at 1550 nm,
## the way ITU-T G.652/G.657 specify bend performance.

const SPEC_DIR := "res://core/network/specs/"
const WAVELENGTHS: Array[int] = [1310, 1550, 1625]

static var _cache: Dictionary[StringName, FiberSpec] = {}

@export var id: StringName
@export var display_name := ""
## Colour of the cable jacket in the world.
@export var jacket_color := Color(0.93, 0.93, 0.9)
## Attenuation in dB/km keyed by wavelength in nm.
@export var attenuation_db_per_km: Dictionary[int, float] = {1310: 0.35, 1550: 0.22, 1625: 0.25}

@export_group("Macrobend")
@export var bend_ref_radius_1_mm := 7.5
## Loss of one full turn at bend_ref_radius_1_mm, 1550 nm.
@export var bend_ref_loss_1_db := 3.0
@export var bend_ref_radius_2_mm := 30.0
## Loss of one full turn at bend_ref_radius_2_mm, 1550 nm.
@export var bend_ref_loss_2_db := 0.0005
## Bend loss multiplier per wavelength relative to 1550 nm (long wavelengths leak more).
@export var bend_wavelength_factor: Dictionary[int, float] = {1310: 0.2, 1550: 1.0, 1625: 2.5}
## Recommended minimum installation radius; tools warn below it.
@export var min_bend_radius_mm := 30.0
## Below this radius the glass breaks.
@export var break_radius_mm := 2.5

@export_group("Splicing")
## Mode field diameter in µm keyed by wavelength (core-offset splice loss, M6).
@export var mode_field_diameter_um: Dictionary[int, float] = {1310: 9.2, 1550: 10.4, 1625: 10.5}


static func get_spec(spec_id: StringName) -> FiberSpec:
	if not _cache.has(spec_id):
		var path := SPEC_DIR + String(spec_id) + ".tres"
		var spec: FiberSpec = load(path) if ResourceLoader.exists(path) else null
		if spec == null:
			push_error("Unknown fiber spec '%s'" % spec_id)
			return null
		_cache[spec_id] = spec
	return _cache[spec_id]


func attenuation_at(wavelength_nm: int) -> float:
	return attenuation_db_per_km.get(wavelength_nm, attenuation_db_per_km[1550])


func bend_factor_at(wavelength_nm: int) -> float:
	return bend_wavelength_factor.get(wavelength_nm, 1.0)


## Fitted macrobend coefficients at 1550 nm: [A (dB/m), B (1/m)].
## (Not a Vector2: that is single precision and visibly rounds A.)
func bend_coefficients() -> PackedFloat64Array:
	var r1 := bend_ref_radius_1_mm * 0.001
	var r2 := bend_ref_radius_2_mm * 0.001
	var alpha1 := bend_ref_loss_1_db / (TAU * r1)
	var alpha2 := bend_ref_loss_2_db / (TAU * r2)
	var b := log(alpha1 / alpha2) / (r2 - r1)
	return PackedFloat64Array([alpha1 * exp(b * r1), b])
