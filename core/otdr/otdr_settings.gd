class_name OtdrSettings
extends RefCounted
## Acquisition settings of the OTDR and the instrument figures derived from them.
## Levels are in the OTDR's displayed (one-way, 5·log10) dB, 0 dB at the launch.

const WAVELENGTHS: Array[int] = [1310, 1550, 1625]
const PULSE_WIDTHS_NS: Array[float] = [3.0, 5.0, 10.0, 30.0, 100.0]
const RANGES_M: Array[float] = [100.0, 250.0, 500.0, 1000.0, 2000.0]
const AVERAGING_S: Array[float] = [1.0, 5.0, 15.0, 30.0, 60.0]
const LAUNCH_CORDS_M: Array[float] = [0.0, 20.0, 50.0]

## Round-trip pulse length in the fiber per ns of pulse width (c / n_group / 2).
const PULSE_M_PER_NS := 0.102
## Dynamic range at 10 ns, 10 s averaging, 1550 nm.
const REFERENCE_DYNAMIC_RANGE_DB := 26.0
const SAMPLES_PER_RANGE := 5000.0
const MIN_SAMPLE_SPACING_M := 0.02

var wavelength_nm := 1550
var pulse_width_ns := 5.0
## 0 = pick automatically from the fiber length.
var range_m := 0.0
var averaging_s := 15.0
var launch_cord_m := 20.0
## Non-reflective events smaller than this are left out of the event table.
var detection_threshold_db := 0.05
## Which splitter branch the event table follows.
var branch := 0
## Noise seed; 0 picks a random one.
var noise_seed := 0


func copy() -> OtdrSettings:
	var other := OtdrSettings.new()
	other.wavelength_nm = wavelength_nm
	other.pulse_width_ns = pulse_width_ns
	other.range_m = range_m
	other.averaging_s = averaging_s
	other.launch_cord_m = launch_cord_m
	other.detection_threshold_db = detection_threshold_db
	other.branch = branch
	other.noise_seed = noise_seed
	return other


func pulse_length_m() -> float:
	return pulse_width_ns * PULSE_M_PER_NS


func sample_spacing_m(effective_range_m: float) -> float:
	return maxf(effective_range_m / SAMPLES_PER_RANGE, MIN_SAMPLE_SPACING_M)


## Rayleigh backscatter level of the pulse relative to the launched power, in dB.
func backscatter_coefficient_db() -> float:
	var at_1ns := -77.0 if wavelength_nm < 1500 else -79.0
	return at_1ns + 10.0 * log(pulse_width_ns) / log(10.0)


## One-way dynamic range: where the backscatter meets the RMS noise.
## Longer pulses carry more energy (+5·log10 per decade); averaging N times lowers the
## noise by √N (+2.5·log10 per decade of averaging time).
func dynamic_range_db() -> float:
	var dr := REFERENCE_DYNAMIC_RANGE_DB \
			+ 5.0 * log(pulse_width_ns / 10.0) / log(10.0) \
			+ 2.5 * log(maxf(averaging_s, 0.01) / 10.0) / log(10.0)
	return dr + (1.0 if wavelength_nm < 1500 else 0.0)


## Smallest standard range that shows the whole fiber with some room after the end.
static func auto_range_m(fiber_end_m: float) -> float:
	for candidate in RANGES_M:
		if candidate >= fiber_end_m * 1.3 + 5.0:
			return candidate
	return RANGES_M[-1]
