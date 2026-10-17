class_name OtdrTrace
extends RefCounted
## Result of an OTDR measurement: the sampled trace (displayed dB against distance) and the
## event table the instrument derived from it.

enum EventKind { NON_REFLECTIVE, REFLECTIVE, END }


class Event:
	var number := 0
	var distance_m := 0.0
	var kind := EventKind.NON_REFLECTIVE
	## Measured insertion loss; NAN when the events around it are too close to measure.
	var loss_db := NAN
	## Measured reflectance; NAN for non-reflective events.
	var reflectance_db := NAN
	## Trace level just before the event, as loss from the launch (positive dB).
	var cumulative_db := 0.0
	## The network events this one stands for (several when they fall inside one dead zone).
	var sources: Array[StrandTrace.Event] = []

	func kind_label() -> String:
		match kind:
			EventKind.REFLECTIVE:
				return "Reflective"
			EventKind.END:
				return "End"
		return "Non-refl." if is_nan(loss_db) or loss_db >= 0.0 else "Gain"


var settings: OtdrSettings
var samples := PackedFloat32Array()
var spacing_m := 0.0
var range_m := 0.0
var events: Array[Event] = []
## Displayed level of the RMS noise floor.
var noise_floor_db := 0.0
## Loss from the launch point (incl. its connector) to the fiber end; NAN if the end
## was lost in noise.
var link_loss_db := NAN
## Fiber length after the launch cord, up to the detected end.
var fiber_length_m := 0.0
var end_in_noise := false
var branch_count := 1


func distance_at(index: int) -> float:
	return index * spacing_m


func index_at(distance_m: float) -> int:
	return clampi(roundi(distance_m / spacing_m), 0, samples.size() - 1)


## Linear interpolation of the trace at a distance.
func level_at(distance_m: float) -> float:
	if samples.is_empty():
		return NAN
	var x := clampf(distance_m / spacing_m, 0.0, samples.size() - 1.0)
	var i := floori(x)
	var j := mini(i + 1, samples.size() - 1)
	return lerpf(samples[i], samples[j], x - i)


func end_event() -> Event:
	for event in events:
		if event.kind == EventKind.END:
			return event
	return null
