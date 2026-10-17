class_name InteractionRay
extends RayCast3D
## Camera-forward ray used for interacting and, later, for aiming every build tool.
##
## Interactable protocol: a collider (or one of its ancestors) that implements
##   func interact(player: Player) -> void
##   func get_interaction_prompt() -> String   (optional)
## becomes the current `target`.

signal target_changed(target: Node)

## Current interactable under the crosshair, or null.
var target: Node


func _physics_process(_delta: float) -> void:
	refresh()


## Re-evaluates the target from the latest ray result.
func refresh() -> void:
	var new_target := find_interactable(get_collider() if is_colliding() else null)
	if new_target != target:
		target = new_target
		target_changed.emit(target)


## Interacts with the current target. Returns false when nothing is targeted.
func interact(player: Player) -> bool:
	if target == null:
		return false
	target.interact(player)
	return true


func get_prompt() -> String:
	if target and target.has_method(&"get_interaction_prompt"):
		return target.get_interaction_prompt()
	return ""


static func find_interactable(node: Object) -> Node:
	var current := node as Node
	while current:
		if current.has_method(&"interact"):
			return current
		current = current.get_parent()
	return null
