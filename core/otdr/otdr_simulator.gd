class_name OtdrSimulator
extends RefCounted
## Synthesises an OTDR trace from strand traces and derives the event table from it.
##
## Levels are displayed one-way dB (5·log10 of the returned power), 0 dB at the launch.
##  1. Backscatter: each branch falls with fiber attenuation and steps at every lossy event.
##     After a splitter the branches' powers add up, so a 1:N split shows a step of about
##     split loss − 5·log10(N), as on a real instrument.
##  2. The pulse smears every step over one pulse length (trailing average).
##  3. Reflections add a spike of one pulse length plus an exponential recovery tail; these
##     are the event and attenuation dead zones.
##  4. Gaussian receiver noise sets the floor at −dynamic range.
##  5. Events are measured like an OTDR does: least-squares lines either side of each event,
##     spike height for reflectance. Events closer than the pulse merge; small ones vanish
##     into noise; everything past where the trace meets the noise is lost.

const FRONT_REFLECTANCE_DB := -45.0
const LAUNCH_CONNECTOR_LOSS_DB := 0.25
const LAUNCH_CONNECTOR_REFLECTANCE_DB := -50.0
const LAUNCH_SPEC := &"g657a1"
## Receiver saturation: spikes are clipped here.
const SATURATION_DB := 30.0
const FIT_WINDOW_M := 10.0
const MIN_FIT_SAMPLES := 4
const MIN_SPIKE_DB := 1.0
## Events this close to the noise floor are lost.
const NOISE_MARGIN_DB := 3.0
const RECOVERY_BASE_M := 0.1
const RECOVERY_PER_PULSE_M := 0.08


## A strand path prepared for synthesis: launch cord prepended, events with plain fields.
class Branch:
	## {distance, loss, reflectance (NAN if none), source (StrandTrace.Event or null), end, launch}
	var events: Array[Dictionary] = []
	## {start, length, att (dB/km), key}
	var spans: Array[Dictionary] = []
	var end_m := 0.0
	## Sorted distances where this branch parts from each other branch.
	var divergences := PackedFloat64Array()


## Measures the fiber launched into `fiber` of the cable on (node_id, port).
static func simulate(network: FiberNetwork, node_id: StringName, port: int, fiber: int,
		settings: OtdrSettings, rng: RandomNumberGenerator = null) -> OtdrTrace:
	var traces := StrandTracer.trace(network, node_id, port, fiber, settings.wavelength_nm)
	return simulate_traces(traces, settings, rng)


static func simulate_traces(traces: Array[StrandTrace], settings: OtdrSettings,
		rng: RandomNumberGenerator = null) -> OtdrTrace:
	if rng == null:
		rng = RandomNumberGenerator.new()
		if settings.noise_seed != 0:
			rng.seed = settings.noise_seed
		else:
			rng.randomize()

	var branches: Array[Branch] = []
	for trace in traces:
		branches.append(_branch_from(trace, settings))
	if branches.is_empty():
		branches.append(_branch_from(StrandTrace.new(), settings))
	_compute_divergences(branches)

	var longest := 0.0
	for branch in branches:
		longest = maxf(longest, branch.end_m)
	var result := OtdrTrace.new()
	result.settings = settings
	result.branch_count = branches.size()
	result.range_m = settings.range_m if settings.range_m > 0.0 else OtdrSettings.auto_range_m(longest)
	result.spacing_m = settings.sample_spacing_m(result.range_m)
	var dz := result.spacing_m
	var n := int(result.range_m / dz) + 1

	# 1. Backscatter, with stretches shared by several branches counted once.
	var backscatter := PackedFloat64Array()
	backscatter.resize(n)
	for branch in branches:
		var levels := _levels(branch, n, dz)
		var next_divergence := 0
		for i in n:
			if is_inf(levels[i]):
				break
			var z := i * dz
			while next_divergence < branch.divergences.size() and branch.divergences[next_divergence] <= z:
				next_divergence += 1
			var share := 1 + branch.divergences.size() - next_divergence
			backscatter[i] += pow(10.0, levels[i] / 5.0) / share

	# 2. Pulse smoothing.
	var power := _trailing_average(backscatter, maxi(1, roundi(settings.pulse_length_m() / dz)))

	# 3. Reflections.
	var coefficient := settings.backscatter_coefficient_db()
	_add_reflection(power, 0.0, 0.0, FRONT_REFLECTANCE_DB, coefficient, settings, dz, 1.0)
	for branch in branches:
		for event in branch.events:
			if is_nan(event["reflectance"]):
				continue
			var z: float = event["distance"]
			_add_reflection(power, z, _level_before(branch, z), event["reflectance"], coefficient,
					settings, dz, 1.0 / _share(branch, z))

	# 4. Noise.
	var dynamic_range := settings.dynamic_range_db()
	result.noise_floor_db = -dynamic_range
	var sigma := pow(10.0, -dynamic_range / 5.0)
	result.samples.resize(n)
	for i in n:
		var p := power[i] + rng.randfn(0.0, sigma)
		result.samples[i] = minf(_db(absf(p) + sigma * 1e-3), SATURATION_DB)

	# 5. Event table along the selected branch.
	_analyse(result, branches[clampi(settings.branch, 0, branches.size() - 1)], power, settings)
	return result


static func _branch_from(trace: StrandTrace, settings: OtdrSettings) -> Branch:
	var branch := Branch.new()
	var offset := settings.launch_cord_m
	if offset > 0.0:
		var launch_spec := FiberSpec.get_spec(LAUNCH_SPEC)
		branch.spans.append({"start": 0.0, "length": offset,
				"att": launch_spec.attenuation_at(settings.wavelength_nm), "key": "launch"})
		branch.events.append({"distance": offset, "loss": LAUNCH_CONNECTOR_LOSS_DB,
				"reflectance": LAUNCH_CONNECTOR_REFLECTANCE_DB, "source": null, "end": false, "launch": true})
	for span in trace.spans:
		branch.spans.append({"start": span.start_m + offset, "length": span.length_m,
				"att": span.attenuation_db_per_km, "key": "%s:%d:%s" % [span.cable_id, span.fiber, span.forward]})
	for event in trace.events:
		var is_end := event.kind == StrandTrace.EventKind.OPEN_END or event.kind == StrandTrace.EventKind.BREAK
		branch.events.append({"distance": event.distance_m + offset, "loss": event.loss_db,
				"reflectance": event.reflectance_db, "source": event, "end": is_end, "launch": false})
	branch.end_m = trace.length_m + offset
	if trace.events.is_empty():
		# Nothing traced (no cable on the port): light ends at the launch connector.
		branch.events.append({"distance": offset, "loss": 0.0, "reflectance": LossModel.FRESNEL_OPEN_END_DB,
				"source": null, "end": true, "launch": false})
	return branch


static func _compute_divergences(branches: Array[Branch]) -> void:
	for branch in branches:
		var distances := PackedFloat64Array()
		for other in branches:
			if other != branch:
				distances.append(_divergence(branch, other))
		distances.sort()
		branch.divergences = distances


## Distance at which branch a stops sharing its path with branch b (INF if never).
static func _divergence(a: Branch, b: Branch) -> float:
	var common := mini(a.spans.size(), b.spans.size())
	for i in common:
		if a.spans[i]["key"] != b.spans[i]["key"]:
			return a.spans[i]["start"]
	if a.spans.size() > common:
		return a.spans[common]["start"]
	if b.spans.size() > common:
		return a.end_m
	return INF


static func _share(branch: Branch, z: float) -> int:
	var count := 1
	for d in branch.divergences:
		if d > z:
			count += 1
	return count


## Backscatter level of a branch at every sample; -INF past its end.
static func _levels(branch: Branch, n: int, dz: float) -> PackedFloat64Array:
	var levels := PackedFloat64Array()
	levels.resize(n)
	var event_index := 0
	var event_loss := 0.0
	var span_index := 0
	var attenuation_done := 0.0
	for i in n:
		var z := i * dz
		if z > branch.end_m + 1e-9:
			levels[i] = -INF
			continue
		while event_index < branch.events.size() and branch.events[event_index]["distance"] < z:
			event_loss += branch.events[event_index]["loss"]
			event_index += 1
		while span_index < branch.spans.size() \
				and branch.spans[span_index]["start"] + branch.spans[span_index]["length"] <= z:
			attenuation_done += branch.spans[span_index]["att"] * branch.spans[span_index]["length"] * 0.001
			span_index += 1
		var partial := 0.0
		if span_index < branch.spans.size() and z > branch.spans[span_index]["start"]:
			partial = branch.spans[span_index]["att"] * (z - branch.spans[span_index]["start"]) * 0.001
		levels[i] = -(attenuation_done + partial + event_loss)
	return levels


## Level just before distance z (events at z not yet applied).
static func _level_before(branch: Branch, z: float) -> float:
	var loss := 0.0
	for event in branch.events:
		if event["distance"] < z:
			loss += event["loss"]
	for span in branch.spans:
		loss += span["att"] * clampf(z - span["start"], 0.0, span["length"]) * 0.001
	return -loss


static func _trailing_average(values: PackedFloat64Array, window: int) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(values.size())
	var running := 0.0
	for i in values.size():
		running += values[i]
		if i >= window:
			running -= values[i - window]
		result[i] = running / mini(i + 1, window)
	return result


## Recovery length after a reflection: until its tail is 1% of the backscatter.
static func _tail_length(reflectance_db: float, coefficient_db: float, settings: OtdrSettings) -> float:
	var ratio := pow(10.0, (reflectance_db - coefficient_db) / 10.0)
	var tau := RECOVERY_BASE_M + RECOVERY_PER_PULSE_M * settings.pulse_length_m()
	return tau * log(maxf(100.0 * ratio, 1.0))


static func _add_reflection(power: PackedFloat64Array, z0: float, level_db: float, reflectance_db: float,
		coefficient_db: float, settings: OtdrSettings, dz: float, weight: float) -> void:
	var ratio := pow(10.0, (reflectance_db - coefficient_db) / 10.0)
	var peak := pow(10.0, level_db / 5.0) * ratio * weight
	var pulse := settings.pulse_length_m()
	var tau := RECOVERY_BASE_M + RECOVERY_PER_PULSE_M * pulse
	var n := power.size()
	var first := roundi(z0 / dz)
	var last := roundi((z0 + pulse) / dz)
	for i in range(maxi(first, 0), mini(last, n - 1) + 1):
		power[i] += peak
	var tail_end := mini(n - 1, last + ceili(_tail_length(reflectance_db, coefficient_db, settings) / dz))
	for i in range(last + 1, tail_end + 1):
		power[i] += peak * exp(-(i - last) * dz / tau)


static func _analyse(result: OtdrTrace, branch: Branch, clean_power: PackedFloat64Array, settings: OtdrSettings) -> void:
	var dz := result.spacing_m
	var pulse := settings.pulse_length_m()
	var coefficient := settings.backscatter_coefficient_db()
	var noise_level := result.noise_floor_db + NOISE_MARGIN_DB

	# Events inside one pulse of each other can't be told apart.
	var groups: Array[Dictionary] = []
	for event in branch.events:
		if not groups.is_empty() and event["distance"] - groups[-1]["distance"] < pulse + 2.0 * dz:
			var group: Dictionary = groups[-1]
			group["events"].append(event)
			group["loss"] += event["loss"]
			group["end"] = group["end"] or event["end"]
			group["launch"] = group["launch"] or event["launch"]
			if not is_nan(event["reflectance"]):
				group["reflectance"] = event["reflectance"] if is_nan(group["reflectance"]) \
						else maxf(group["reflectance"], event["reflectance"])
		else:
			groups.append({"distance": event["distance"], "events": [event], "loss": event["loss"],
					"reflectance": event["reflectance"], "end": event["end"], "launch": event["launch"]})
	# Far-below-threshold events (gentle bends) are invisible: leave them out so they don't
	# cut the fit windows of their neighbours. Their loss still shows in the measured slope.
	groups.assign(groups.filter(func(group: Dictionary) -> bool:
		return group["end"] or group["launch"] or not is_nan(group["reflectance"]) \
				or group["loss"] >= settings.detection_threshold_db * 0.5))

	# Where the clean trace sinks into the noise before the fiber ends.
	var noise_z := INF
	for i in range(0, mini(result.index_at(branch.end_m), clean_power.size())):
		if _db(clean_power[i]) < noise_level:
			noise_z = i * dz
			break

	var clear_from := pulse + _tail_length(FRONT_REFLECTANCE_DB, coefficient, settings) + 2.0 * dz
	var start_level := 0.0
	for g in groups.size():
		var group: Dictionary = groups[g]
		var z: float = group["distance"]
		if z >= noise_z:
			var lost := OtdrTrace.Event.new()
			lost.kind = OtdrTrace.EventKind.END
			lost.distance_m = snappedf(noise_z, dz)
			lost.cumulative_db = -noise_level
			result.events.append(lost)
			result.end_in_noise = true
			break

		var left := _fit(result, maxf(clear_from, z - FIT_WINDOW_M), z - dz)
		var level_left := _fit_value(left, z) if not left.is_empty() else result.level_at(z - dz)
		var dead_zone := pulse + 2.0 * dz
		if not is_nan(group["reflectance"]):
			dead_zone += _tail_length(group["reflectance"], coefficient, settings)

		var event := OtdrTrace.Event.new()
		event.distance_m = snappedf(z, dz)
		event.cumulative_db = -level_left
		for source in group["events"]:
			if source["source"] != null:
				event.sources.append(source["source"])
		var spike := _max_level(result, z, z + pulse + dz) - level_left
		if group["launch"]:
			start_level = level_left

		if group["end"]:
			event.kind = OtdrTrace.EventKind.END
			if spike >= MIN_SPIKE_DB:
				event.reflectance_db = _reflectance_from_spike(spike, coefficient)
			result.events.append(event)
			result.fiber_length_m = z - settings.launch_cord_m
			result.link_loss_db = start_level - level_left
			break

		var next_z: float = groups[g + 1]["distance"] if g + 1 < groups.size() else branch.end_m
		var right := _fit(result, z + dead_zone, minf(next_z - dz, z + dead_zone + FIT_WINDOW_M))
		if not left.is_empty() and not right.is_empty():
			event.loss_db = level_left - _fit_value(right, z)
		var reflective := not is_nan(group["reflectance"]) and spike >= MIN_SPIKE_DB
		if reflective:
			event.kind = OtdrTrace.EventKind.REFLECTIVE
			event.reflectance_db = _reflectance_from_spike(spike, coefficient)
		var visible: bool = reflective \
				or (not is_nan(event.loss_db) and absf(event.loss_db) >= settings.detection_threshold_db) \
				or (is_nan(event.loss_db) and group["loss"] >= settings.detection_threshold_db)
		if visible:
			result.events.append(event)
		clear_from = z + dead_zone

	if result.end_event() == null:
		var end := OtdrTrace.Event.new()
		end.kind = OtdrTrace.EventKind.END
		end.distance_m = snappedf(branch.end_m, dz)
		end.cumulative_db = -result.level_at(branch.end_m - dz)
		result.events.append(end)
		result.fiber_length_m = branch.end_m - settings.launch_cord_m
	for i in result.events.size():
		result.events[i].number = i + 1


## Least-squares line through the trace between two distances: {slope, intercept} or {}.
static func _fit(result: OtdrTrace, from_m: float, to_m: float) -> Dictionary:
	var first := maxi(0, ceili(from_m / result.spacing_m))
	var last := mini(result.samples.size() - 1, floori(to_m / result.spacing_m))
	var count := last - first + 1
	if count < MIN_FIT_SAMPLES:
		return {}
	var sx := 0.0
	var sy := 0.0
	var sxx := 0.0
	var sxy := 0.0
	for i in range(first, last + 1):
		var x := i * result.spacing_m
		var y := result.samples[i]
		sx += x
		sy += y
		sxx += x * x
		sxy += x * y
	var denominator := count * sxx - sx * sx
	if absf(denominator) < 1e-12:
		return {}
	var slope := (count * sxy - sx * sy) / denominator
	return {"slope": slope, "intercept": (sy - slope * sx) / count}


static func _fit_value(fit: Dictionary, z: float) -> float:
	return fit["intercept"] + fit["slope"] * z


static func _max_level(result: OtdrTrace, from_m: float, to_m: float) -> float:
	var best := -INF
	for i in range(result.index_at(from_m), result.index_at(to_m) + 1):
		best = maxf(best, result.samples[i])
	return best


## Reflectance from a spike of `height_db` (displayed dB above the backscatter).
static func _reflectance_from_spike(height_db: float, coefficient_db: float) -> float:
	return coefficient_db + 10.0 * log(maxf(pow(10.0, height_db / 5.0) - 1.0, 1e-9)) / log(10.0)


static func _db(power: float) -> float:
	return 5.0 * log(maxf(power, 1e-30)) / log(10.0)
