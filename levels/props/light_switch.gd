extends StaticBody3D
## Wall light switch: toggles every light in `light_group`. Doubles as the reference interactable.

@export var light_group := &"floor_lights"

var lights_on := true


func interact(_player: Player) -> void:
	lights_on = not lights_on
	for light in get_tree().get_nodes_in_group(light_group):
		light.visible = lights_on


func get_interaction_prompt() -> String:
	return "Turn lights off" if lights_on else "Turn lights on"
