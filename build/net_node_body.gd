class_name NetNodeBody
extends StaticBody3D
## Physical body of a network node. Interacting with it (E) opens its splice tray.

var node_id: StringName
var level: LevelNetwork


func interact(_player: Player) -> void:
	SpliceTray.open(level, node_id)


func get_interaction_prompt() -> String:
	var node := level.network.get_node_by_id(node_id)
	var def: PlaceableDef = PlaceableDef.for_node_type(node.type) if node else null
	return "Open splice tray (%s)" % (def.display_name if def else String(node_id))
