class_name NetLink
extends Resource
## A fiber-to-fiber connection inside a node: side A (port, fiber) ↔ side B (port, fiber).
## Light can travel either way. Splitter legs share their A side (the combined input).

enum Kind { FUSION_SPLICE, MECHANICAL_SPLICE, CONNECTOR, SPLITTER_LEG }

@export var kind := Kind.FUSION_SPLICE
@export var port_a := 0
@export var fiber_a := 0
@export var port_b := 0
@export var fiber_b := 0
@export var loss_db := LossModel.DEFAULT_FUSION_SPLICE_DB
## Only meaningful for connectors.
@export var reflectance_db := LossModel.UPC_REFLECTANCE_DB
## What the fusion splicer reported (NAN if not made with the splicer). The true loss
## above is what the light, and the OTDR, actually sees.
@export var estimated_loss_db := NAN
## False when the splice was left without a heat-shrink sleeve.
@export var protected := true


## The loss a technician can read without an OTDR: the splicer estimate when there is one.
func displayed_loss_db() -> float:
	return loss_db if is_nan(estimated_loss_db) else estimated_loss_db


static func create(link_kind: Kind, pa: int, fa: int, pb: int, fb: int, loss := NAN) -> NetLink:
	var link := NetLink.new()
	link.kind = link_kind
	link.port_a = pa
	link.fiber_a = fa
	link.port_b = pb
	link.fiber_b = fb
	link.loss_db = loss if not is_nan(loss) else default_loss(link_kind)
	return link


static func default_loss(link_kind: Kind) -> float:
	match link_kind:
		Kind.MECHANICAL_SPLICE:
			return LossModel.DEFAULT_MECHANICAL_SPLICE_DB
		Kind.CONNECTOR:
			return LossModel.DEFAULT_CONNECTOR_DB
		_:
			return LossModel.DEFAULT_FUSION_SPLICE_DB


func touches(port: int, fiber: int) -> bool:
	return touches_a(port, fiber) or touches_b(port, fiber)


func touches_a(port: int, fiber: int) -> bool:
	return port_a == port and fiber_a == fiber


func touches_b(port: int, fiber: int) -> bool:
	return port_b == port and fiber_b == fiber


## The (port, fiber) on the opposite side from the given one, or (-1, -1) if not part of this link.
func other_side(port: int, fiber: int) -> Vector2i:
	if touches_a(port, fiber):
		return Vector2i(port_b, fiber_b)
	if touches_b(port, fiber):
		return Vector2i(port_a, fiber_a)
	return Vector2i(-1, -1)


func is_reflective() -> bool:
	return kind == Kind.CONNECTOR
