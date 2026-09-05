extends Node

func _ready() -> void:
	if supplies_its_own_scene(OS.get_cmdline_args(), OS.get_cmdline_user_args()):
		return

	var scene := "res://client/client_main.tscn"
	if _is_server_role():
		scene = "res://server/server_main.tscn"
	# Deferred: the tree is still building autoloads during _ready.
	get_tree().change_scene_to_file.call_deferred(scene)


## True when the caller named the scene it wants to run — the test runner, the
## screenshot tool, or anyone opening a scene directly. Routing away from it would
## silently swap out the scene they asked for, and the failure looks like the scene
## never loaded at all.
static func supplies_its_own_scene(
	args: PackedStringArray, user_args: PackedStringArray
) -> bool:
	if "--test" in args or "--test" in user_args:
		return true
	for arg in args:
		if arg.ends_with(".tscn") or arg.ends_with(".scn"):
			return true
	return false


func _is_server_role() -> bool:
	if OS.has_feature("dedicated_server"):
		return true
	# Accepts both `godot --server` and `godot -- --server`.
	return "--server" in OS.get_cmdline_args() or "--server" in OS.get_cmdline_user_args()
