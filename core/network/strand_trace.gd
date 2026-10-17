class_name StrandTrace
extends RefCounted
## The optical path of one fiber strand from a launch point to where the light ends:
## fiber spans (continuous attenuation) plus discrete loss events. Input to the OTDR and
## power meter.

enum EventKind { SPLICE, CONNECTOR, SPLITTER, BEND, OPEN_END, BREAK }
enum EndKind { OPEN_END, BREAK, LOOP }


class Event:
	var distance_m: float
	var kind: EventKind
	var loss_db: float
	## NAN for non-reflective events.
	var reflectance_db: float = NAN
	var node_id: StringName
	var cable_id: StringName
	## Bend radius for BEND events, INF otherwise.
	var radius_m: float = INF

	func is_reflective() -> bool:
		return not is_nan(reflectance_db)


## A run of fiber inside one cable.
class Span:
	var start_m: float
	var length_m: float
	var attenuation_db_per_km: float
	var cable_id: StringName
	var fiber: int
	## True when the light travels the cable from end A to end B.
	var forward: bool


var wavelength_nm := 1550
var events: Array[Event] = []
var spans: Array[Span] = []
var length_m := 0.0
var end_kind := EndKind.OPEN_END


func total_loss_db() -> float:
	var total := 0.0
	for span in spans:
		total += span.attenuation_db_per_km * span.length_m * 0.001
	for event in events:
		total += event.loss_db
	return total


func events_of_kind(kind: EventKind) -> Array[Event]:
	var result: Array[Event] = []
	result.assign(events.filter(func(e: Event) -> bool: return e.kind == kind))
	return result


func end_event() -> Event:
	return events[-1] if not events.is_empty() else null


func copy() -> StrandTrace:
	var other := StrandTrace.new()
	other.wavelength_nm = wavelength_nm
	other.events = events.duplicate()
	other.spans = spans.duplicate()
	other.length_m = length_m
	other.end_kind = end_kind
	return other
