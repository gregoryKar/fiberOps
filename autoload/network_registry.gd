extends Node
## Holds the fiber network of every building level, keyed by level id.
## Persistence comes in M9.

var _networks: Dictionary[StringName, FiberNetwork] = {}


func register_network(level_id: StringName, network: FiberNetwork) -> void:
	network.level_id = level_id
	_networks[level_id] = network


func get_network(level_id: StringName) -> FiberNetwork:
	return _networks.get(level_id)


func has_network(level_id: StringName) -> bool:
	return _networks.has(level_id)
