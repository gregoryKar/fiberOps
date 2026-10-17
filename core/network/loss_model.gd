class_name LossModel
extends RefCounted
## Optical loss formulas. All lengths in metres, losses in dB, wavelengths in nm.

const FRESNEL_OPEN_END_DB := -14.7  ## Reflectance of a clean glass/air end (cleaved fiber, open connector).
const BREAK_REFLECTANCE_DB := -35.0  ## Fractured glass reflects far less than a clean end.
const UPC_REFLECTANCE_DB := -50.0
const APC_REFLECTANCE_DB := -65.0

const DEFAULT_FUSION_SPLICE_DB := 0.05
const DEFAULT_MECHANICAL_SPLICE_DB := 0.3
const DEFAULT_CONNECTOR_DB := 0.3

## Upper limit for macrobend loss density, so near-break radii stay finite.
const MAX_BEND_DB_PER_M := 500.0


static func attenuation_db(spec: FiberSpec, length_m: float, wavelength_nm: int) -> float:
	return spec.attenuation_at(wavelength_nm) * length_m * 0.001


## Macrobend loss density α(R) in dB per metre of fiber bent at radius_m.
static func bend_db_per_m(spec: FiberSpec, radius_m: float, wavelength_nm: int) -> float:
	if is_inf(radius_m):
		return 0.0
	var coeff := spec.bend_coefficients()
	var alpha := coeff[0] * exp(-coeff[1] * radius_m) * spec.bend_factor_at(wavelength_nm)
	return minf(alpha, MAX_BEND_DB_PER_M)


static func bend_loss_db(spec: FiberSpec, radius_m: float, arc_length_m: float, wavelength_nm: int) -> float:
	return bend_db_per_m(spec, radius_m, wavelength_nm) * arc_length_m


## Insertion loss of one leg of a 1:N PLC splitter: ideal split plus typical excess loss.
static func splitter_loss_db(ratio: int) -> float:
	var log2_n := log(float(ratio)) / log(2.0)
	return 10.0 * log(float(ratio)) / log(10.0) + 0.4 + 0.27 * log2_n


static func is_broken(spec: FiberSpec, radius_m: float) -> bool:
	return radius_m < spec.break_radius_mm * 0.001
