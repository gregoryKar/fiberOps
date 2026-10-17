class_name CablePath
extends RefCounted
## Geometry of a routed cable: straight runs between waypoints joined by circular fillet arcs.
##
## Each interior waypoint becomes an arc of the requested corner radius. When the neighbouring
## segments are too short to fit that arc, the radius shrinks to what fits — so waypoints placed
## close together, or sharp U-turns, produce tight bends and higher loss. Curvature is exact
## (1/R on arcs, 0 on straights), with no numeric differentiation.

enum SectionKind { STRAIGHT, ARC }

## Turn angles below this are treated as straight; above MAX_TURN they are clamped
## (an exact 180° reversal has no defined fillet plane).
const MIN_TURN := 1e-4
const MAX_TURN := PI - 1e-3
const MERGE_DISTANCE := 1e-4


class Section:
	var kind: SectionKind
	var start_m: float  ## Distance from the start of the path.
	var length_m: float
	var radius_m: float = INF
	## STRAIGHT: start point. ARC: circle centre.
	var origin: Vector3
	## STRAIGHT: unit direction.
	var direction: Vector3
	## ARC: centre → arc start vector, rotation axis and swept angle.
	var start_vector: Vector3
	var axis: Vector3
	var angle: float

	func point_at(local_m: float) -> Vector3:
		if kind == SectionKind.STRAIGHT:
			return origin + direction * local_m
		var t := local_m / length_m if length_m > 0.0 else 0.0
		return origin + start_vector.rotated(axis, angle * t)


var sections: Array[Section] = []
var length_m := 0.0


static func build(waypoints: PackedVector3Array, corner_radius: float) -> CablePath:
	var path := CablePath.new()
	var pts := _merge_close(waypoints)
	var n := pts.size()
	if n < 2:
		return path

	var seg_len := PackedFloat64Array()
	var dirs: Array[Vector3] = []
	for i in n - 1:
		var d := pts[i + 1] - pts[i]
		seg_len.append(d.length())
		dirs.append(d / d.length())

	# Tangent length and radius of the fillet at each interior point (index = waypoint).
	var tangent := PackedFloat64Array()
	tangent.resize(n)
	var radius := PackedFloat64Array()
	radius.resize(n)
	var turn := PackedFloat64Array()
	turn.resize(n)
	for i in range(1, n - 1):
		var theta := acos(clampf(dirs[i - 1].dot(dirs[i]), -1.0, 1.0))
		radius[i] = INF
		if theta < MIN_TURN:
			continue
		theta = minf(theta, MAX_TURN)
		var half_tan := tan(theta * 0.5)
		var avail_in := seg_len[i - 1] if i == 1 else seg_len[i - 1] * 0.5
		var avail_out := seg_len[i] if i == n - 2 else seg_len[i] * 0.5
		var t := minf(corner_radius * half_tan, minf(avail_in, avail_out))
		tangent[i] = t
		radius[i] = t / half_tan
		turn[i] = theta

	for i in n - 1:
		var straight := seg_len[i] - tangent[i] - tangent[i + 1]
		var start := pts[i] + dirs[i] * tangent[i]
		path._add_straight(start, dirs[i], straight)
		var corner := i + 1
		if corner < n - 1 and turn[corner] > 0.0:
			path._add_arc(pts[corner], dirs[i], dirs[corner], tangent[corner], radius[corner], turn[corner])
	return path


func point_at(distance_m: float) -> Vector3:
	var section := section_at(distance_m)
	if section == null:
		return Vector3.ZERO
	return section.point_at(clampf(distance_m, 0.0, length_m) - section.start_m)


func section_at(distance_m: float) -> Section:
	if sections.is_empty():
		return null
	var d := clampf(distance_m, 0.0, length_m)
	for section in sections:
		if d <= section.start_m + section.length_m:
			return section
	return sections[-1]


## Bend radius at a distance along the path (INF on straights).
func radius_at(distance_m: float) -> float:
	var section := section_at(distance_m)
	return section.radius_m if section else INF


## Points along the path at most `step` apart; every section boundary is included,
## so arcs are always represented by at least a few points.
func sample(step: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	for d in sample_distances(step):
		points.append(point_at(d))
	return points


## The distances along the path that sample() returns points for.
func sample_distances(step: float) -> PackedFloat64Array:
	var distances := PackedFloat64Array()
	if sections.is_empty():
		return distances
	distances.append(0.0)
	for section in sections:
		var count := maxi(1, ceili(section.length_m / step))
		if section.kind == SectionKind.ARC:
			count = maxi(count, ceili(section.angle / deg_to_rad(15.0)))
		for k in range(1, count + 1):
			distances.append(section.start_m + section.length_m * k / count)
	return distances


func arcs() -> Array[Section]:
	var result: Array[Section] = []
	result.assign(sections.filter(func(s: Section) -> bool: return s.kind == SectionKind.ARC))
	return result


func min_radius() -> float:
	var result := INF
	for section in sections:
		result = minf(result, section.radius_m)
	return result


func _add_straight(start: Vector3, direction: Vector3, length: float) -> void:
	if length <= MERGE_DISTANCE:
		return
	var s := Section.new()
	s.kind = SectionKind.STRAIGHT
	s.start_m = length_m
	s.length_m = length
	s.origin = start
	s.direction = direction
	sections.append(s)
	length_m += length


func _add_arc(corner: Vector3, d_in: Vector3, d_out: Vector3, tangent: float, radius: float, theta: float) -> void:
	var axis := d_in.cross(d_out)
	if axis.length_squared() < 1e-12:
		# Near-reversal: any axis perpendicular to the incoming direction works.
		axis = d_in.cross(Vector3.UP) if absf(d_in.dot(Vector3.UP)) < 0.9 else d_in.cross(Vector3.RIGHT)
	axis = axis.normalized()
	var arc_start := corner - d_in * tangent
	# The centre sits one radius from the arc start, perpendicular to d_in, on the inside of the turn.
	var inward := axis.cross(d_in).normalized()
	var s := Section.new()
	s.kind = SectionKind.ARC
	s.start_m = length_m
	s.length_m = radius * theta
	s.radius_m = radius
	s.origin = arc_start + inward * radius
	s.start_vector = arc_start - s.origin
	s.axis = axis
	s.angle = theta
	sections.append(s)
	length_m += s.length_m


static func _merge_close(waypoints: PackedVector3Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for p in waypoints:
		if result.is_empty() or result[-1].distance_to(p) > MERGE_DISTANCE:
			result.append(p)
	return result
