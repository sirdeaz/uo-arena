extends TestCase

## `client/scenes/local_test.tscn` authors its two fighters now, not `LocalTest._ready()`.
## Their `body_color` instance overrides are literal `Color`s that duplicate
## `Palette.PLAYER` / `Palette.DUMMY` — and `tests/test_palette.gd` cannot see them, because
## it walks `res://client` non-recursively and the scene lives under `client/scenes/`.
##
## This is that missing guard: the practice fighters must wear the palette's two body
## colours, so a hand-picked pair that drifts from them fails here rather than on screen.

const LOCAL_TEST_SCENE := preload("res://client/scenes/local_test.tscn")


func test_the_practice_fighters_wear_the_palette_body_colours() -> void:
	# Not added to the tree on purpose — `LocalTest._ready()` would pull in the whole
	# arena and stage. Instancing alone applies the stored instance overrides, which is
	# all this checks.
	var scene := LOCAL_TEST_SCENE.instantiate()
	var player: Fighter = scene.get_node("Player")
	var dummy: Fighter = scene.get_node("Dummy")

	assert_true(
		player.body_color.is_equal_approx(Palette.PLAYER),
		"the practice player must be Palette.PLAYER, not a literal that drifts from it"
	)
	assert_true(
		dummy.body_color.is_equal_approx(Palette.DUMMY),
		"the practice dummy must be Palette.DUMMY, not a literal that drifts from it"
	)
	assert_true(
		player.player_controlled,
		"the practice player is the one you steer — the flag is an instance override now"
	)

	scene.free()
