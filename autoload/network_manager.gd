extends Node

func _ready() -> void:
	var scene := "res://client/client_main.tscn"
	if _is_server_role():
		scene = "res://server/server_main.tscn"
	# Deferred: the tree is still building autoloads during _ready.
	get_tree().change_scene_to_file.call_deferred(scene)


func _is_server_role() -> bool:
	if OS.has_feature("dedicated_server"):
		return true
	# Accepts both `godot --server` and `godot -- --server`.
	return "--server" in OS.get_cmdline_args() or "--server" in OS.get_cmdline_user_args()
