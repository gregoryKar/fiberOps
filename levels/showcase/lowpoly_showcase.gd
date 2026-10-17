@tool
class_name LowPolyShowcase
extends Node3D
## Standalone low-poly diorama: technicians, a cat, a helper robot, boxes, ladders and tools,
## all built from primitive meshes so it shows up in the editor too. Four look-dev styles can be
## switched live (keys 1-4 / Tab at runtime, or the "style" export in the inspector).

enum Style { FLAT, TOON, CLAY, MAQUETTE }

const STYLES: Array[Dictionary] = [
	{"name": "Low-Poly Flat", "toon": false, "faceted": true, "outline": false,
		"sky_top": Color("5fa8e0"), "sky_horizon": Color("d6ecf5"), "ground_bottom": Color("6d8f6a"),
		"sun_color": Color("fff1dc"), "sun_energy": 1.0, "ambient": 0.55, "ssao": true, "fog": 0.0},
	{"name": "Toon / Cel", "toon": true, "faceted": false, "outline": true,
		"sky_top": Color("6cc4ff"), "sky_horizon": Color("f2fbff"), "ground_bottom": Color("8fcf7a"),
		"sun_color": Color("ffffff"), "sun_energy": 0.85, "ambient": 0.35, "ssao": false, "fog": 0.0},
	{"name": "Soft Clay", "toon": false, "faceted": false, "outline": false,
		"sky_top": Color("f3cdbd"), "sky_horizon": Color("fbefe7"), "ground_bottom": Color("e5d3c3"),
		"sun_color": Color("ffe4c8"), "sun_energy": 0.75, "ambient": 0.55, "ssao": true, "fog": 0.008},
	{"name": "Maquette", "toon": false, "faceted": true, "outline": false,
		"sky_top": Color("dcdcd8"), "sky_horizon": Color("f2f2ef"), "ground_bottom": Color("cfcfcb"),
		"sun_color": Color("ffffff"), "sun_energy": 0.75, "ambient": 0.5, "ssao": true, "fog": 0.0},
]

const PALETTE: Dictionary[StringName, Color] = {
	&"skin_a": Color("f2c29b"), &"skin_b": Color("c68863"), &"skin_c": Color("8d5a3b"),
	&"eyes": Color("2b2b33"),
	&"vest": Color("ff7a1a"), &"vest_alt": Color("c8e632"), &"stripe": Color("e8ecef"),
	&"helmet": Color("ffd23f"), &"helmet_alt": Color("f4f4f4"), &"helmet_blue": Color("3d8bfd"),
	&"shirt": Color("2f4b7c"), &"shirt_alt": Color("5c6b73"), &"pants": Color("394049"),
	&"boots": Color("5a3d2b"),
	&"cardboard": Color("c9a26b"), &"tape": Color("8a6b43"),
	&"crate": Color("b5835a"), &"crate_dark": Color("8b5e3c"), &"wood": Color("a0703f"),
	&"aluminium": Color("b8c2cc"), &"fiberglass": Color("f29e38"), &"metal": Color("8d99a6"),
	&"dark": Color("30343b"), &"tool_yellow": Color("f5c518"), &"tool_red": Color("e04646"),
	&"screen": Color("4fe3a0"), &"cable": Color("f7d84a"),
	&"wall": Color("aeb4b8"), &"cabinet": Color("d7dcd9"), &"cone": Color("ff6b2b"),
	&"white": Color("f4f4f0"), &"mat": Color("3a6ea5"),
	&"cat": Color("f0a04b"), &"cat_light": Color("fbe3c2"), &"robot": Color("5ec4d6"),
	&"ground": Color("8cc084"), &"ground_pad": Color("c8c5bd"),
	&"trunk": Color("7a5236"), &"leaf": Color("4f9d69"), &"leaf_alt": Color("7cbf6b"),
	&"rock": Color("9aa0a6"),
}
## Roles that keep their colour in the Maquette style.
const MAQUETTE_ACCENTS: Array[StringName] = [&"vest", &"vest_alt", &"cone", &"screen", &"cable"]
const METALLIC_ROLES: Array[StringName] = [&"aluminium", &"metal"]
const EMISSIVE_ROLES: Array[StringName] = [&"screen"]
const NO_OUTLINE_ROLES: Array[StringName] = [&"eyes", &"stripe", &"tape", &"screen", &"ground", &"ground_pad"]

const CAMERA_TARGET := Vector3(0.0, 0.9, -0.6)
const WALK_MIN_X := -2.4
const WALK_MAX_X := 1.2
const WALK_SPEED := 0.8
const ROBOT_RADIUS := 5.7

const LIT_SHADER := """
shader_type spatial;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness = 0.85;
uniform float metallic = 0.0;
uniform float emission = 0.0;
uniform bool faceted = true;

void fragment() {
	if (faceted) {
		vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
		NORMAL = dot(n, VIEW) < 0.0 ? -n : n;
	}
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = albedo.rgb * emission;
}
"""

const TOON_SHADER := """
shader_type spatial;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float emission = 0.0;
uniform bool faceted = false;
uniform vec4 shadow_tint : source_color = vec4(0.55, 0.6, 0.85, 1.0);

void fragment() {
	if (faceted) {
		vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
		NORMAL = dot(n, VIEW) < 0.0 ? -n : n;
	}
	ALBEDO = albedo.rgb;
	EMISSION = albedo.rgb * emission;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float q = smoothstep(0.2, 0.23, ndl) * 0.5 + smoothstep(0.6, 0.63, ndl) * 0.5;
	DIFFUSE_LIGHT += mix(shadow_tint.rgb * 0.35, vec3(1.0), q) * LIGHT_COLOR / PI;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	DIFFUSE_LIGHT += rim * q * 0.4 * LIGHT_COLOR / PI;
	SPECULAR_LIGHT += step(0.96, dot(reflect(-LIGHT, NORMAL), VIEW)) * q * LIGHT_COLOR * 0.12;
}
"""

const OUTLINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front;
uniform vec4 color : source_color = vec4(0.12, 0.12, 0.16, 1.0);
uniform float width = 0.012;

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = color.rgb;
}
"""

@export var style := Style.FLAT:
	set(value):
		style = value
		if is_node_ready():
			_apply_style()
@export_tool_button("Rebuild") var rebuild_action := rebuild

var _world: Node3D
var _materials: Dictionary[StringName, ShaderMaterial] = {}
var _lit_shader: Shader
var _toon_shader: Shader
var _outline_material: ShaderMaterial
var _environment: Environment
var _sky_material: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _camera: Camera3D
var _label: Label

var _characters: Array[Dictionary] = []
var _waver: Dictionary
var _climber: Dictionary
var _walker: Dictionary
var _walker_dir := 1.0
var _cat_tail: Node3D
var _cat_head: Node3D
var _robot: Node3D
var _robot_ball: Node3D
var _robot_wheels: Array[Node3D] = []
var _robot_angle := 0.0
var _time := 0.0

var _yaw := 0.5
var _pitch := 0.42
var _distance := 10.0
var _dragging := false
var _auto_rotate := true


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	if _world:
		remove_child(_world)
		_world.free()
	_materials.clear()
	_characters.clear()
	_robot_wheels.clear()

	_world = Node3D.new()
	_world.name = "Generated"
	add_child(_world)

	_build_environment()
	_build_ground()
	_build_wall_and_ladders()
	_build_props()
	_build_characters()
	_build_critters()
	_build_scenery()
	if not Engine.is_editor_hint():
		_build_camera()
		_build_ui()
	_apply_style()


# --- Runtime ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _world == null:
		return
	_time += delta
	var t := _time

	for i in _characters.size():
		var body: Node3D = _characters[i]["body"]
		body.scale.y = 1.0 + sin(t * 2.2 + i * 1.7) * 0.012

	var wave_arm: Node3D = _waver["arm_l"]
	wave_arm.rotation.z = deg_to_rad(140.0 + sin(t * 7.0) * 22.0)

	var climb_l: Node3D = _climber["arm_l"]
	var climb_r: Node3D = _climber["arm_r"]
	climb_l.rotation.x = deg_to_rad(-130.0 + sin(t * 9.0) * 5.0)
	climb_r.rotation.x = deg_to_rad(-130.0 + sin(t * 9.0 + 1.5) * 5.0)

	var walker: Node3D = _walker["root"]
	walker.position.x += _walker_dir * WALK_SPEED * delta
	if walker.position.x > WALK_MAX_X:
		_walker_dir = -1.0
	elif walker.position.x < WALK_MIN_X:
		_walker_dir = 1.0
	walker.rotation.y = lerp_angle(walker.rotation.y, PI * 0.5 * _walker_dir, delta * 6.0)
	walker.position.y = absf(sin(t * 8.0)) * 0.04
	var swing := sin(t * 8.0) * deg_to_rad(28.0)
	var legs: Array[Node3D] = _walker["legs"]
	legs[0].rotation.x = swing
	legs[1].rotation.x = -swing

	_cat_tail.rotation.z = sin(t * 2.5) * 0.5
	_cat_head.rotation.z = sin(t * 0.7) * 0.15

	_robot_angle += delta * 0.3
	_robot.position = Vector3(cos(_robot_angle), 0.0, sin(_robot_angle)) * ROBOT_RADIUS
	_robot.rotation.y = atan2(-sin(_robot_angle), cos(_robot_angle))
	_robot_ball.position.y = 0.92 + sin(t * 6.0) * 0.02
	for wheel in _robot_wheels:
		wheel.rotate_object_local(Vector3.UP, delta * 0.3 * ROBOT_RADIUS / 0.1)

	if _auto_rotate and not _dragging:
		_yaw += delta * 0.12
		_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		match key.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4:
				style = (key.keycode - KEY_1) as Style
			KEY_TAB:
				style = ((style + 1) % STYLES.size()) as Style
			KEY_R:
				_auto_rotate = not _auto_rotate
			KEY_ESCAPE:
				get_tree().quit()
		return
	var button := event as InputEventMouseButton
	if button:
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_distance = maxf(_distance - 0.6, 4.0)
				_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_distance = minf(_distance + 0.6, 16.0)
				_update_camera()
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				_dragging = button.pressed
		return
	var motion := event as InputEventMouseMotion
	if motion and _dragging:
		_yaw -= motion.relative.x * 0.006
		_pitch = clampf(_pitch + motion.relative.y * 0.004, 0.08, 1.3)
		_update_camera()


func _update_camera() -> void:
	if _camera == null:
		return
	var dir := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	_camera.position = CAMERA_TARGET + dir * _distance
	_camera.look_at(CAMERA_TARGET)


# --- Styles -------------------------------------------------------------------------------------

func _apply_style() -> void:
	if _world == null:
		return
	var s: Dictionary = STYLES[style]
	for role: StringName in _materials:
		_apply_material_style(role, _materials[role])

	_sky_material.sky_top_color = s["sky_top"]
	_sky_material.sky_horizon_color = s["sky_horizon"]
	_sky_material.ground_horizon_color = s["sky_horizon"]
	_sky_material.ground_bottom_color = s["ground_bottom"]
	_environment.ambient_light_energy = s["ambient"]
	_environment.ssao_enabled = s["ssao"]
	_environment.ssao_intensity = 3.0 if style == Style.CLAY else 2.0
	var fog: float = s["fog"]
	_environment.fog_enabled = fog > 0.0
	_environment.fog_density = fog
	_environment.fog_light_color = s["sky_horizon"]
	_sun.light_color = s["sun_color"]
	_sun.light_energy = s["sun_energy"]
	_sun.shadow_blur = 3.0 if style == Style.CLAY else 1.0

	if _label:
		_label.text = "%s\n[1-4] / [Tab] switch style    drag: orbit    wheel: zoom    [R] auto-rotate" % s["name"]


func _apply_material_style(role: StringName, material: ShaderMaterial) -> void:
	var s: Dictionary = STYLES[style]
	var toon: bool = s["toon"]
	var outline: bool = s["outline"]
	var metal := role in METALLIC_ROLES
	material.shader = _get_toon_shader() if toon else _get_lit_shader()
	material.set_shader_parameter("albedo", _style_color(role))
	material.set_shader_parameter("faceted", s["faceted"])
	material.set_shader_parameter("roughness", 0.45 if metal else (1.0 if style == Style.CLAY else 0.85))
	material.set_shader_parameter("metallic", 0.4 if metal else 0.0)
	material.set_shader_parameter("emission", 1.2 if role in EMISSIVE_ROLES else 0.0)
	material.next_pass = _get_outline_material() if outline and role not in NO_OUTLINE_ROLES else null


func _style_color(role: StringName) -> Color:
	var base: Color = PALETTE.get(role, Color.MAGENTA)
	match style:
		Style.TOON:
			return Color.from_hsv(base.h, minf(base.s * 1.15, 1.0), minf(base.v * 1.05, 1.0))
		Style.CLAY:
			return Color.from_hsv(base.h, base.s * 0.55, lerpf(base.v, 1.0, 0.12))
		Style.MAQUETTE:
			if role in MAQUETTE_ACCENTS:
				return base
			var g := lerpf(0.62, 0.9, base.get_luminance())
			return Color(g, g, g * 0.98)
	return base


func _get_lit_shader() -> Shader:
	if _lit_shader == null:
		_lit_shader = Shader.new()
		_lit_shader.code = LIT_SHADER
	return _lit_shader


func _get_toon_shader() -> Shader:
	if _toon_shader == null:
		_toon_shader = Shader.new()
		_toon_shader.code = TOON_SHADER
	return _toon_shader


func _get_outline_material() -> ShaderMaterial:
	if _outline_material == null:
		var shader := Shader.new()
		shader.code = OUTLINE_SHADER
		_outline_material = ShaderMaterial.new()
		_outline_material.shader = shader
	return _outline_material


func _mat(role: StringName) -> ShaderMaterial:
	if not _materials.has(role):
		var material := ShaderMaterial.new()
		_materials[role] = material
		_apply_material_style(role, material)
	return _materials[role]


# --- Mesh helpers -------------------------------------------------------------------------------

func _part(parent: Node3D, mesh: Mesh, role: StringName, pos: Vector3,
		rot_deg := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _mat(role)
	mesh_instance.position = pos
	mesh_instance.rotation_degrees = rot_deg
	mesh_instance.scale = scl
	parent.add_child(mesh_instance)
	return mesh_instance


func _pivot(parent: Node3D, pos: Vector3, rot_deg := Vector3.ZERO) -> Node3D:
	var node := Node3D.new()
	node.position = pos
	node.rotation_degrees = rot_deg
	parent.add_child(node)
	return node


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _cyl(top: float, bottom: float, height: float, segments := 6) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 0
	return mesh


func _ball(radius: float, segments := 7, rings := 4) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = rings
	return mesh


# --- World --------------------------------------------------------------------------------------

func _build_environment() -> void:
	_sky_material = ProceduralSkyMaterial.new()
	_sky_material.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = _sky_material

	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_environment.ssao_radius = 0.8
	_environment.fog_sky_affect = 0.3

	var world_environment := WorldEnvironment.new()
	world_environment.environment = _environment
	_world.add_child(world_environment)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-52.0, 35.0, 0.0)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 30.0
	_world.add_child(_sun)


func _build_ground() -> void:
	_part(_world, _cyl(11.0, 11.4, 0.6, 14), &"ground", Vector3(0, -0.32, 0))
	_part(_world, _cyl(6.5, 6.5, 0.04, 12), &"ground_pad", Vector3(0, -0.02, 0))


func _build_wall_and_ladders() -> void:
	# A wall with a fiber termination box (BEP), conduit and a cable run.
	_part(_world, _box(Vector3(4.0, 3.2, 0.2)), &"wall", Vector3(2.2, 1.6, -3.1))
	_part(_world, _box(Vector3(4.04, 0.12, 0.24)), &"cabinet", Vector3(2.2, 3.22, -3.1))
	_part(_world, _box(Vector3(0.42, 0.52, 0.14)), &"cabinet", Vector3(3.0, 2.55, -2.93))
	_part(_world, _box(Vector3(0.008, 0.46, 0.01)), &"dark", Vector3(3.0, 2.55, -2.858))
	_part(_world, _box(Vector3(0.04, 0.06, 0.02)), &"tool_red", Vector3(3.12, 2.55, -2.855))
	_part(_world, _cyl(0.03, 0.03, 2.29, 6), &"white", Vector3(3.0, 1.145, -2.97))
	_part(_world, _cyl(0.015, 0.015, 2.6, 6), &"cable", Vector3(1.5, 2.55, -2.98), Vector3(0, 0, 90))

	# Straight ladder leaning on the wall.
	var lean := _pivot(_world, Vector3(0.9, 0, -2.2), Vector3(-16.5, 0, 0))
	for side: float in [-1.0, 1.0]:
		_part(lean, _box(Vector3(0.06, 2.85, 0.05)), &"fiberglass", Vector3(0.22 * side, 1.42, 0))
	for i in 9:
		_part(lean, _cyl(0.02, 0.02, 0.44, 6), &"aluminium", Vector3(0, 0.3 + i * 0.3, 0), Vector3(0, 0, 90))

	# Stepladder with a technician on it (character added in _build_characters).
	var step := _pivot(_world, Vector3(3.0, 0, -2.55))
	var front := _pivot(step, Vector3(0, 0, 0.32), Vector3(-12, 0, 0))
	var back := _pivot(step, Vector3(0, 0, -0.32), Vector3(12, 0, 0))
	for frame in [front, back]:
		for side: float in [-1.0, 1.0]:
			_part(frame, _box(Vector3(0.05, 1.5, 0.035)), &"aluminium", Vector3(0.24 * side, 0.75, 0))
	for h: float in [0.32, 0.64, 0.97]:
		_part(front, _box(Vector3(0.46, 0.03, 0.12)), &"metal", Vector3(0, h, 0), Vector3(12, 0, 0))
	for h: float in [0.5, 1.0]:
		_part(back, _cyl(0.012, 0.012, 0.46, 5), &"aluminium", Vector3(0, h, 0), Vector3(0, 0, 90))
	_part(step, _box(Vector3(0.56, 0.06, 0.16)), &"fiberglass", Vector3(0, 1.47, 0))


func _build_props() -> void:
	# Cardboard box stack (the cat sits on top).
	var stack := _pivot(_world, Vector3(-3.2, 0, -1.6), Vector3(0, 20, 0))
	_cardboard_box(stack, Vector3(0, 0, 0), Vector3(0.7, 0.5, 0.6), 5)
	_cardboard_box(stack, Vector3(0.75, 0, 0.1), Vector3(0.55, 0.4, 0.5), -10)
	_cardboard_box(stack, Vector3(0.05, 0.5, 0.0), Vector3(0.55, 0.4, 0.45), 15)
	_cardboard_box(stack, Vector3(0.72, 0.4, 0.08), Vector3(0.35, 0.3, 0.35), -25)
	_cardboard_box(stack, Vector3(-0.2, 0, 0.75), Vector3(0.4, 0.3, 0.4), 35)

	# Wooden crates and a fiber cable drum.
	_crate(_world, Vector3(-1.0, 0, -2.3), 0.9, 12)
	_crate(_world, Vector3(-0.15, 0, -2.5), 0.55, -8)
	var drum := _pivot(_world, Vector3(-2.2, 0, -2.6), Vector3(0, 70, 0))
	for side: float in [-1.0, 1.0]:
		_part(drum, _cyl(0.45, 0.45, 0.05, 10), &"wood", Vector3(0, 0.45, 0.22 * side), Vector3(90, 0, 0))
	_part(drum, _cyl(0.32, 0.32, 0.4, 10), &"cable", Vector3(0, 0.45, 0), Vector3(90, 0, 0))
	_part(drum, _cyl(0.06, 0.06, 0.5, 6), &"dark", Vector3(0, 0.45, 0), Vector3(90, 0, 0))

	# Fiber street cabinet.
	var cab := _pivot(_world, Vector3(-4.6, 0, 0.3), Vector3(0, 60, 0))
	_part(cab, _box(Vector3(0.85, 0.1, 0.45)), &"dark", Vector3(0, 0.05, 0))
	_part(cab, _box(Vector3(0.8, 1.2, 0.4)), &"cabinet", Vector3(0, 0.7, 0))
	_part(cab, _box(Vector3(0.88, 0.05, 0.48)), &"cabinet", Vector3(0, 1.33, 0))
	_part(cab, _box(Vector3(0.01, 1.0, 0.01)), &"dark", Vector3(0, 0.72, 0.2))
	_part(cab, _box(Vector3(0.14, 0.14, 0.01)), &"cable", Vector3(0.2, 1.05, 0.202))
	for i in 3:
		_part(cab, _box(Vector3(0.22, 0.015, 0.01)), &"dark", Vector3(-0.2, 0.3 + i * 0.05, 0.202))

	# Traffic cones, one knocked over.
	for pos: Vector3 in [Vector3(3.3, 0, 0.2), Vector3(4.0, 0, -0.6), Vector3(4.3, 0, 1.2)]:
		_cone(_world, pos, Vector3.ZERO)
	_cone(_world, Vector3(4.6, 0.18, 0.4), Vector3(0, 30, 90))

	# Tool mat with gear laid out.
	var mat := _pivot(_world, Vector3(1.9, 0, 1.0), Vector3(0, -15, 0))
	_part(mat, _box(Vector3(1.5, 0.02, 0.9)), &"mat", Vector3(0, 0.01, 0))
	var toolbox := _pivot(mat, Vector3(-0.45, 0.02, -0.15), Vector3(0, 10, 0))
	_part(toolbox, _box(Vector3(0.5, 0.22, 0.24)), &"tool_red", Vector3(0, 0.11, 0))
	_part(toolbox, _box(Vector3(0.52, 0.06, 0.26)), &"tool_red", Vector3(0, 0.25, 0))
	_part(toolbox, _box(Vector3(0.06, 0.04, 0.02)), &"metal", Vector3(0, 0.2, 0.13))
	_part(toolbox, _box(Vector3(0.3, 0.03, 0.03)), &"dark", Vector3(0, 0.34, 0))
	for side: float in [-1.0, 1.0]:
		_part(toolbox, _box(Vector3(0.03, 0.06, 0.03)), &"dark", Vector3(0.14 * side, 0.3, 0))
	var splicer := _pivot(mat, Vector3(0.1, 0.02, -0.2), Vector3(0, -20, 0))
	_part(splicer, _box(Vector3(0.36, 0.2, 0.28)), &"dark", Vector3(0, 0.1, 0))
	_part(splicer, _box(Vector3(0.37, 0.02, 0.29)), &"metal", Vector3(0, 0.2, 0))
	_part(splicer, _box(Vector3(0.16, 0.03, 0.03)), &"metal", Vector3(0, 0.23, 0))
	_otdr(mat, Vector3(0.5, 0.04, -0.1), Vector3(0, 25, 0))
	_hardhat(mat, Vector3(0.5, 0.02, 0.22), &"helmet_alt", Vector3(0, -30, 0))
	# Hammer.
	var hammer := _pivot(mat, Vector3(-0.35, 0.04, 0.25), Vector3(0, 25, 0))
	_part(hammer, _cyl(0.018, 0.018, 0.32, 6), &"wood", Vector3.ZERO, Vector3(0, 0, 90))
	_part(hammer, _box(Vector3(0.05, 0.05, 0.15)), &"metal", Vector3(0.16, 0, 0))
	# Wrench.
	var wrench := _pivot(mat, Vector3(0.0, 0.03, 0.2), Vector3(0, -40, 0))
	_part(wrench, _box(Vector3(0.25, 0.012, 0.035)), &"metal", Vector3.ZERO)
	for side: float in [-1.0, 1.0]:
		_part(wrench, _cyl(0.035, 0.035, 0.012, 6), &"metal", Vector3(0.13 * side, 0, 0))
	# Screwdriver.
	var screwdriver := _pivot(mat, Vector3(0.12, 0.04, 0.32), Vector3(0, 70, 0))
	_part(screwdriver, _cyl(0.022, 0.022, 0.1, 6), &"tool_yellow", Vector3.ZERO, Vector3(0, 0, 90))
	_part(screwdriver, _cyl(0.006, 0.006, 0.12, 5), &"metal", Vector3(0.11, 0, 0), Vector3(0, 0, 90))

	# Low crate the sitting technician uses as a seat.
	_crate(_world, Vector3(-2.0, 0, 0.45), 0.42, 25)


func _build_characters() -> void:
	# Waver: front and centre, drill in hand.
	_waver = _character(_world, Vector3(0.2, 0, 0.4), 10, &"skin_a", &"vest", &"helmet", &"shirt")
	var arm_r: Node3D = _waver["arm_r"]
	arm_r.rotation_degrees = Vector3(-75, 0, -6)
	_drill(_waver["hand_r"])

	# Climber: on the stepladder, working on the wall box.
	_climber = _character(_world, Vector3(3.0, 0.965, -2.38), 180, &"skin_c", &"vest_alt", &"helmet_alt", &"shirt_alt")
	var climb_l: Node3D = _climber["arm_l"]
	var climb_r: Node3D = _climber["arm_r"]
	climb_l.rotation_degrees = Vector3(-130, 0, 8)
	climb_r.rotation_degrees = Vector3(-130, 0, -8)

	# Walker: carries a box back and forth.
	_walker = _character(_world, Vector3(-0.5, 0, 2.3), 90, &"skin_b", &"vest", &"helmet_blue", &"shirt")
	for key: String in ["arm_l", "arm_r"]:
		var arm: Node3D = _walker[key]
		arm.rotation_degrees = Vector3(-75, 0, 0)
	_cardboard_box(_walker["body"], Vector3(0, 0.8, 0.42), Vector3(0.5, 0.4, 0.4), 0)

	# Sitter: on a low crate reading an OTDR.
	var sitter := _character(_world, Vector3(-2.0, -0.22, 0.45), 25, &"skin_b", &"vest_alt", &"helmet", &"shirt_alt")
	var sit_legs: Array[Node3D] = sitter["legs"]
	for leg in sit_legs:
		leg.rotation_degrees = Vector3(-50, 0, 0)
	var sit_l: Node3D = sitter["arm_l"]
	var sit_r: Node3D = sitter["arm_r"]
	sit_l.rotation_degrees = Vector3(-40, 0, -10)
	sit_r.rotation_degrees = Vector3(-40, 0, 10)
	_otdr(sitter["body"], Vector3(0, 0.84, 0.38), Vector3(-37, 0, 0))


func _build_critters() -> void:
	# Cat on top of the box stack.
	var cat := _pivot(_world, Vector3(-3.17, 0.9, -1.6), Vector3(0, 40, 0))
	_part(cat, _cyl(0.09, 0.14, 0.26, 6), &"cat", Vector3(0, 0.13, 0))
	for side: float in [-1.0, 1.0]:
		_part(cat, _box(Vector3(0.05, 0.04, 0.06)), &"cat_light", Vector3(0.05 * side, 0.02, 0.11))
	_cat_head = _pivot(cat, Vector3(0, 0.33, 0))
	_part(_cat_head, _ball(0.11, 6, 4), &"cat", Vector3.ZERO, Vector3.ZERO, Vector3(1.1, 0.95, 1.0))
	_part(_cat_head, _box(Vector3(0.08, 0.05, 0.04)), &"cat_light", Vector3(0, -0.025, 0.095))
	for side: float in [-1.0, 1.0]:
		_part(_cat_head, _cyl(0.0, 0.045, 0.08, 3), &"cat", Vector3(0.06 * side, 0.1, 0), Vector3(0, 0, -15 * side))
		_part(_cat_head, _box(Vector3(0.025, 0.035, 0.02)), &"eyes", Vector3(0.045 * side, 0.02, 0.1))
	_cat_tail = _pivot(cat, Vector3(0, 0.04, -0.12))
	var tail_tilt := _pivot(_cat_tail, Vector3.ZERO, Vector3(-30, 0, 0))
	_part(tail_tilt, _cyl(0.02, 0.028, 0.3, 5), &"cat", Vector3(0, 0.15, 0))

	# Little cable-laying robot patrolling the edge.
	_robot = _pivot(_world, Vector3(ROBOT_RADIUS, 0, 0))
	_part(_robot, _box(Vector3(0.4, 0.3, 0.45)), &"robot", Vector3(0, 0.3, 0))
	_part(_robot, _box(Vector3(0.3, 0.2, 0.25)), &"white", Vector3(0, 0.6, 0.02))
	for side: float in [-1.0, 1.0]:
		_part(_robot, _box(Vector3(0.06, 0.06, 0.01)), &"screen", Vector3(0.07 * side, 0.62, 0.146))
		for end: float in [-1.0, 1.0]:
			_robot_wheels.append(_part(_robot, _cyl(0.1, 0.1, 0.06, 8), &"dark",
					Vector3(0.23 * side, 0.1, 0.14 * end), Vector3(0, 0, 90)))
	_part(_robot, _cyl(0.01, 0.01, 0.2, 4), &"dark", Vector3(0, 0.8, 0))
	_robot_ball = _part(_robot, _ball(0.04, 6, 3), &"tool_red", Vector3(0, 0.92, 0))
	_part(_robot, _cyl(0.12, 0.12, 0.3, 8), &"cable", Vector3(0, 0.48, -0.17), Vector3(0, 0, 90))


func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 14:
		var angle := TAU * i / 14.0 + rng.randf_range(-0.15, 0.15)
		var radius := rng.randf_range(7.6, 9.8)
		var tree := _pivot(_world, Vector3(cos(angle) * radius, 0, sin(angle) * radius),
				Vector3(0, rng.randf_range(0, 360), 0))
		tree.scale = Vector3.ONE * rng.randf_range(0.8, 1.4)
		_part(tree, _cyl(0.08, 0.12, 0.6, 5), &"trunk", Vector3(0, 0.3, 0))
		if i % 3 == 0:
			_part(tree, _ball(0.6, 6, 3), &"leaf_alt", Vector3(0, 1.1, 0))
		else:
			_part(tree, _cyl(0.0, 0.6, 0.9, 6), &"leaf", Vector3(0, 0.95, 0))
			_part(tree, _cyl(0.0, 0.45, 0.7, 6), &"leaf", Vector3(0, 1.45, 0))
	for i in 10:
		var angle := rng.randf_range(0, TAU)
		var radius := rng.randf_range(6.8, 10.2)
		var s := rng.randf_range(0.15, 0.45)
		_part(_world, _ball(1.0, 5, 3), &"rock", Vector3(cos(angle) * radius, s * 0.3, sin(angle) * radius),
				Vector3(0, rng.randf_range(0, 360), 0), Vector3(s * 1.3, s, s))


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = 50.0
	_world.add_child(_camera)
	_camera.make_current()
	_update_camera()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	_world.add_child(layer)
	_label = Label.new()
	_label.position = Vector2(20, 16)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)


# --- Builders -----------------------------------------------------------------------------------

## Chunky technician with a big head. Faces +Z with feet at the origin. Returns the animatable
## pivots: root, body, legs (hips), arm_l / arm_r (shoulders, +X / -X side) and hand_l / hand_r.
func _character(parent: Node3D, pos: Vector3, yaw_deg: float, skin: StringName, vest: StringName,
		helmet: StringName, shirt: StringName) -> Dictionary:
	var root := _pivot(parent, pos, Vector3(0, yaw_deg, 0))
	var body := _pivot(root, Vector3.ZERO)
	var legs: Array[Node3D] = []
	for side: float in [-1.0, 1.0]:
		var hip := _pivot(body, Vector3(0.11 * side, 0.68, 0))
		_part(hip, _cyl(0.085, 0.075, 0.56, 6), &"pants", Vector3(0, -0.3, 0))
		_part(hip, _box(Vector3(0.17, 0.12, 0.27)), &"boots", Vector3(0, -0.62, 0.04))
		legs.append(hip)
	_part(body, _box(Vector3(0.38, 0.16, 0.22)), &"pants", Vector3(0, 0.72, 0))
	_part(body, _cyl(0.27, 0.22, 0.52, 4), shirt, Vector3(0, 1.04, 0), Vector3(0, 45, 0))
	_part(body, _cyl(0.29, 0.245, 0.4, 4), vest, Vector3(0, 1.0, 0), Vector3(0, 45, 0))
	_part(body, _cyl(0.272, 0.268, 0.05, 4), &"stripe", Vector3(0, 0.95, 0), Vector3(0, 45, 0))
	_part(body, _ball(0.2, 8, 4), skin, Vector3(0, 1.5, 0), Vector3.ZERO, Vector3(1, 1.05, 1))
	for side: float in [-1.0, 1.0]:
		_part(body, _box(Vector3(0.04, 0.06, 0.04)), &"eyes", Vector3(0.075 * side, 1.52, 0.18))
	_hardhat(body, Vector3(0, 1.56, 0), helmet, Vector3.ZERO)

	var arms: Array[Node3D] = []
	var hands: Array[Node3D] = []
	for side: float in [1.0, -1.0]:
		var shoulder := _pivot(body, Vector3(0.31 * side, 1.24, 0), Vector3(0, 0, 6 * side))
		_part(shoulder, _cyl(0.07, 0.06, 0.5, 6), shirt, Vector3(0, -0.25, 0))
		_part(shoulder, _ball(0.075, 6, 3), skin, Vector3(0, -0.54, 0))
		arms.append(shoulder)
		hands.append(_pivot(shoulder, Vector3(0, -0.56, 0)))

	var character := {"root": root, "body": body, "legs": legs, "arm_l": arms[0], "arm_r": arms[1],
			"hand_l": hands[0], "hand_r": hands[1]}
	_characters.append(character)
	return character


## Hard hat whose brim sits at pos.
func _hardhat(parent: Node3D, pos: Vector3, role: StringName, rot_deg: Vector3) -> void:
	var hat := _pivot(parent, pos, rot_deg)
	_part(hat, _cyl(0.27, 0.27, 0.03, 8), role, Vector3(0, 0.015, 0))
	_part(hat, _cyl(0.12, 0.225, 0.16, 8), role, Vector3(0, 0.08, 0))
	_part(hat, _box(Vector3(0.05, 0.04, 0.3)), role, Vector3(0, 0.15, 0))


## Cardboard box resting on pos, with a tape strip over the top.
func _cardboard_box(parent: Node3D, pos: Vector3, size: Vector3, yaw_deg: float) -> void:
	var box := _pivot(parent, pos, Vector3(0, yaw_deg, 0))
	_part(box, _box(size), &"cardboard", Vector3(0, size.y * 0.5, 0))
	_part(box, _box(Vector3(0.08, 0.006, size.z + 0.006)), &"tape", Vector3(0, size.y + 0.003, 0))


## Cube crate of edge length size resting on pos, with framed and braced sides.
func _crate(parent: Node3D, pos: Vector3, size: float, yaw_deg: float) -> void:
	var crate := _pivot(parent, pos, Vector3(0, yaw_deg, 0))
	_part(crate, _box(Vector3.ONE * size), &"crate", Vector3(0, size * 0.5, 0))
	var plank := size * 0.12
	for i in 4:
		var face := _pivot(crate, Vector3(0, size * 0.5, 0), Vector3(0, 90 * i, 0))
		var z := size * 0.5 + 0.01
		for sy: float in [-1.0, 1.0]:
			_part(face, _box(Vector3(size, plank, 0.02)), &"crate_dark", Vector3(0, (size - plank) * 0.5 * sy, z))
			_part(face, _box(Vector3(plank, size, 0.02)), &"crate_dark", Vector3((size - plank) * 0.5 * sy, 0, z))
		_part(face, _box(Vector3(size * 1.1, plank, 0.02)), &"crate_dark", Vector3(0, 0, z), Vector3(0, 0, 45))


func _cone(parent: Node3D, pos: Vector3, rot_deg: Vector3) -> void:
	var cone := _pivot(parent, pos, rot_deg)
	_part(cone, _box(Vector3(0.36, 0.04, 0.36)), &"cone", Vector3(0, 0.02, 0))
	_part(cone, _cyl(0.03, 0.15, 0.5, 8), &"cone", Vector3(0, 0.29, 0))
	_part(cone, _cyl(0.092, 0.115, 0.08, 8), &"white", Vector3(0, 0.3, 0))


## Handheld OTDR lying with its screen on the +Y face.
func _otdr(parent: Node3D, pos: Vector3, rot_deg: Vector3) -> void:
	var otdr := _pivot(parent, pos, rot_deg)
	_part(otdr, _box(Vector3(0.28, 0.05, 0.18)), &"tool_yellow", Vector3.ZERO)
	_part(otdr, _box(Vector3(0.17, 0.01, 0.1)), &"screen", Vector3(-0.02, 0.026, -0.01))
	for i in 3:
		_part(otdr, _box(Vector3(0.025, 0.012, 0.025)), &"dark", Vector3(0.1, 0.028, -0.05 + i * 0.045))


## Cordless drill held in a hand pivot of a forward-raised arm (barrel along -Y, grip along Z).
func _drill(hand: Node3D) -> void:
	_part(hand, _box(Vector3(0.06, 0.07, 0.18)), &"dark", Vector3(0, 0, -0.02))
	_part(hand, _box(Vector3(0.09, 0.12, 0.05)), &"dark", Vector3(0, 0, -0.12))
	_part(hand, _box(Vector3(0.08, 0.26, 0.1)), &"tool_yellow", Vector3(0, -0.06, 0.1))
	_part(hand, _cyl(0.03, 0.03, 0.06, 6), &"metal", Vector3(0, -0.22, 0.1))
	_part(hand, _cyl(0.008, 0.008, 0.12, 4), &"metal", Vector3(0, -0.3, 0.1))
