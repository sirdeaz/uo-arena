extends TestCase

## `NetworkManager` decides at boot whether this process is a client or a server, and it
## does that by replacing the running scene. Anything that hands Godot a scene of its own
## — the test runner, the screenshot tool, or a developer opening a scene directly — has
## to be left alone, or the scene they asked for is silently swapped out and the failure
## looks like the scene never loaded.

func _args(values: Array) -> PackedStringArray:
	return PackedStringArray(values)


func test_the_test_runner_is_never_routed_away_from() -> void:
	assert_true(
		NetworkManager.supplies_its_own_scene(
			_args(["godot", "--headless", "res://tests/test_main.tscn"]), _args(["--test"])
		),
		"this very suite depends on not being routed away from"
	)


func test_a_scene_on_the_command_line_wins() -> void:
	assert_true(
		NetworkManager.supplies_its_own_scene(
			_args(["godot", "res://tools/capture_promo_shot.tscn"]), _args(["--out", "x.png"])
		),
		"a caller that named a scene means it"
	)
	assert_true(
		NetworkManager.supplies_its_own_scene(_args(["godot", "res://a.scn"]), _args([])),
		"binary scenes count too"
	)


func test_a_plain_launch_is_still_routed() -> void:
	assert_false(
		NetworkManager.supplies_its_own_scene(_args(["godot"]), _args([])),
		"a bare launch must still be sent to the client scene"
	)
	assert_false(
		NetworkManager.supplies_its_own_scene(_args(["godot", "--headless"]), _args(["--server"])),
		"a server launch must still be sent to the server scene"
	)
