extends Node

## Until networking lands (build step 3), the client boots straight into the local
## single-player harness.

func _ready() -> void:
	print("[client] UO Arena client booting.")
	get_tree().change_scene_to_file.call_deferred("res://client/scenes/local_test.tscn")
