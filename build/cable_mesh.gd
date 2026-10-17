class_name CableMesh
extends RefCounted
## Builds a round tube mesh along a polyline, with one vertex colour per ring.
## Rings are oriented by parallel transport so the tube doesn't twist at corners.


static func build(points: PackedVector3Array, colors: PackedColorArray, radius := 0.006, sides := 8) -> ArrayMesh:
	var n := points.size()
	if n < 2:
		return null

	var tangents: Array[Vector3] = []
	for i in n:
		var t := points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)]
		tangents.append(t.normalized() if t.length_squared() > 1e-18 else (tangents[-1] if i > 0 else Vector3.FORWARD))

	var normal := tangents[0].cross(Vector3.UP)
	if normal.length_squared() < 1e-6:
		normal = tangents[0].cross(Vector3.RIGHT)
	normal = normal.normalized()

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var vertex_colors := PackedColorArray()
	for i in n:
		if i > 0:
			var axis := tangents[i - 1].cross(tangents[i])
			if axis.length_squared() > 1e-12:
				normal = normal.rotated(axis.normalized(), tangents[i - 1].angle_to(tangents[i]))
		var binormal := tangents[i].cross(normal)
		var color := colors[i] if i < colors.size() else Color.WHITE
		for s in sides:
			var a := TAU * s / sides
			var dir := normal * cos(a) + binormal * sin(a)
			vertices.append(points[i] + dir * radius)
			normals.append(dir)
			vertex_colors.append(color)

	var indices := PackedInt32Array()
	for i in n - 1:
		for s in sides:
			var a := i * sides + s
			var b := i * sides + (s + 1) % sides
			indices.append_array([a, b, a + sides, b, b + sides, a + sides])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = vertex_colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Colour for a bend: green at or above the fiber's recommended radius, amber down to half
## of it, red below that.
static func bend_color(spec: FiberSpec, radius_m: float, straight_color := Color(0.92, 0.9, 0.82)) -> Color:
	if is_inf(radius_m):
		return straight_color
	var min_r := spec.min_bend_radius_mm * 0.001
	if radius_m >= min_r:
		return Color(0.2, 0.85, 0.3)
	if radius_m >= min_r * 0.5:
		return Color(1.0, 0.7, 0.1)
	return Color(1.0, 0.15, 0.1)
