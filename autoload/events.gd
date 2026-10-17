extends Node
## Global signal bus. Systems emit and listen here instead of holding direct references.

## The player's active input mode changed (see GameState.Mode).
signal input_mode_changed(mode: int)

## The player switched the active tool in the hotbar.
signal tool_changed(tool_id: StringName)

## Something changed in the fiber network of a level (node/cable added, removed or edited).
signal network_changed(level_id: StringName)
