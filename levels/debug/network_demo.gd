extends Node3D
## Debug scene: a hand-built network in the test floor, drawn by NetworkView, with the
## TraceOverlay listing what the strand tracer sees. Walk around; F1/F2/F3 change the trace.
##
## BEP (west wall) ── feeder G.652.D ──> FB (corridor wall), spliced per fiber:
##   fiber 1 → good G.657.A1 drop through the door to an apartment outlet
##   fiber 2 → G.652.D drop with 6 mm corners (lossy) to an outlet across the corridor
##   fiber 3 → not spliced
##   fiber 4 → G.657.A1 drop with a 4 mm hairpin (breaks the fiber)
##   fiber 5 → 1:4 splitter → second floorbox

@onready var view: NetworkView = $NetworkView
@onready var overlay: TraceOverlay = $TraceOverlay


func _ready() -> void:
	var built := build_demo_network()
	var network: FiberNetwork = built["network"]
	NetworkRegistry.register_network(&"demo", network)
	view.network = network
	overlay.setup(network, view, built["launches"])

	var player: Node3D = $TestFloor/Player
	player.global_position = Vector3(-4.0, 0.0, -0.3)
	player.rotation = Vector3(0, PI / 2.0, 0)


static func build_demo_network() -> Dictionary:
	var net := FiberNetwork.new()
	var on_west_wall := Basis(Vector3.UP, PI / 2.0)
	var bep := net.add_node(NetNode.Type.BEP, Transform3D(on_west_wall, Vector3(-9.84, 1.5, 0)))
	var fb := net.add_node(NetNode.Type.FLOORBOX, Transform3D(Basis.IDENTITY, Vector3(-6.0, 2.3, 0.86)), 6)
	var o_good := net.add_node(NetNode.Type.OUTLET, Transform3D(Basis.IDENTITY, Vector3(-3.5, 0.4, 1.115)))
	var o_bad := net.add_node(NetNode.Type.OUTLET, Transform3D(Basis.IDENTITY, Vector3(-6.1, 0.45, -0.885)))
	var o_kink := net.add_node(NetNode.Type.OUTLET, Transform3D(Basis.IDENTITY, Vector3(-7.2, 0.4, 0.885)))
	var splitter := net.add_node(NetNode.Type.SPLITTER, Transform3D(Basis.IDENTITY, Vector3(-7.5, 2.35, -0.875)))
	var fb2 := net.add_node(NetNode.Type.FLOORBOX, Transform3D(Basis.IDENTITY, Vector3(-8.5, 2.3, -0.86)))

	net.add_cable(bep.id, 0, fb.id, 0, _pts([
		[-9.84, 1.75, 0], [-9.84, 2.85, 0], [-9.84, 2.85, 0.88], [-6.0, 2.85, 0.88], [-6.0, 2.475, 0.88],
	]), &"g652d", 12, 0.03)
	net.add_cable(fb.id, 1, o_good.id, 0, _pts([
		[-5.9, 2.125, 0.88], [-5.9, 1.95, 0.88], [-5.0, 1.95, 0.88], [-5.0, 1.95, 1.12],
		[-3.5, 1.95, 1.12], [-3.5, 0.44, 1.12],
	]), &"g657a1", 2, 0.015)
	net.add_cable(fb.id, 2, o_bad.id, 0, _pts([
		[-6.1, 2.125, 0.88], [-6.1, 0.02, 0.88], [-6.1, 0.02, -0.88], [-6.1, 0.41, -0.88],
	]), &"g652d", 2, 0.006)
	net.add_cable(fb.id, 3, o_kink.id, 0, _pts([
		[-6.15, 2.3, 0.88], [-6.6, 2.3, 0.88], [-6.6, 1.2, 0.88], [-6.604, 1.2, 0.88],
		[-6.604, 1.5, 0.88], [-7.2, 1.5, 0.88], [-7.2, 0.44, 0.88],
	]), &"g657a1", 2, 0.01)
	net.add_cable(fb.id, 4, splitter.id, 0, _pts([
		[-5.85, 2.4, 0.88], [-5.6, 2.4, 0.88], [-5.6, 2.9, 0.88], [-5.6, 2.9, -0.88],
		[-7.5, 2.9, -0.88], [-7.5, 2.4, -0.88],
	]), &"g657a1", 12, 0.02)
	net.add_cable(splitter.id, 1, fb2.id, 0, _pts([
		[-7.5, 2.3, -0.88], [-7.5, 2.0, -0.88], [-8.5, 2.0, -0.88], [-8.5, 2.125, -0.88],
	]), &"g657a1", 4, 0.02)

	fb.add_splice(0, 0, 1, 0, 0.04)
	fb.add_splice(0, 1, 2, 0, 0.06)
	fb.add_splice(0, 3, 3, 0, 0.05)
	fb.add_splice(0, 4, 4, 0, 0.03)
	splitter.add_splitter(0, 0, 1, 4)

	var launches: Array[Dictionary] = [
		{"label": "BEP fiber 1 → apartment drop (G.657.A1)", "node": bep.id, "port": 0, "fiber": 0},
		{"label": "BEP fiber 2 → 6 mm corners on G.652.D", "node": bep.id, "port": 0, "fiber": 1},
		{"label": "BEP fiber 3 → not spliced", "node": bep.id, "port": 0, "fiber": 2},
		{"label": "BEP fiber 4 → 4 mm hairpin (break)", "node": bep.id, "port": 0, "fiber": 3},
		{"label": "BEP fiber 5 → 1:4 splitter", "node": bep.id, "port": 0, "fiber": 4},
		{"label": "Outlet 2 → back to BEP", "node": o_bad.id, "port": 0, "fiber": 0},
	]
	return {"network": net, "launches": launches}


static func _pts(points: Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for p: Array in points:
		result.append(Vector3(p[0], p[1], p[2]))
	return result
