extends TestCase

## `ArenaStage.camera_target` is the whole of the follow camera's judgement: keep the
## local player in view, but never scroll the painted arena off the edge of the screen.
## It is a static function precisely so this can check the corners with no viewport.

## A 1280×720 window at the stage's authored 0.85 zoom shows this much world.
const VIEW := Vector2(1506.0, 847.0)

## Comfortably larger than VIEW on both axes, so there is room to pan.
const ARENA := Rect2(-2000.0, -2000.0, 4000.0, 4000.0)


func test_a_focus_well_inside_the_arena_is_followed_exactly() -> void:
	assert_eq(
		ArenaStage.camera_target(Vector2(120.0, -50.0), ARENA, VIEW),
		Vector2(120.0, -50.0),
		"with room on every side the camera sits on the player, not offset from them"
	)


func test_the_view_never_scrolls_past_the_far_walls() -> void:
	var target := ArenaStage.camera_target(Vector2(9000.0, 9000.0), ARENA, VIEW)
	assert_almost_eq(
		target.x, ARENA.end.x - VIEW.x * 0.5,
		"chasing a player east stops when the wall reaches the screen edge"
	)
	assert_almost_eq(
		target.y, ARENA.end.y - VIEW.y * 0.5, "and the same going south"
	)


func test_the_view_never_scrolls_past_the_near_walls() -> void:
	var target := ArenaStage.camera_target(Vector2(-9000.0, -9000.0), ARENA, VIEW)
	assert_almost_eq(
		target.x, ARENA.position.x + VIEW.x * 0.5,
		"the west wall holds the camera the same way the east one does"
	)
	assert_almost_eq(
		target.y, ARENA.position.y + VIEW.y * 0.5, "and the north wall"
	)


func test_an_arena_smaller_than_the_screen_is_centred_not_cornered() -> void:
	var small := Rect2(-400.0, -300.0, 800.0, 600.0)  # smaller than VIEW on both axes
	assert_eq(
		ArenaStage.camera_target(Vector2(390.0, 290.0), small, VIEW),
		small.get_center(),
		"nothing to pan to — the arena is framed whole and the player moves within it"
	)


func test_each_axis_is_decided_on_its_own() -> void:
	# Wide enough to pan left-right, too short to pan up-down.
	var letterbox := Rect2(-2000.0, -300.0, 4000.0, 600.0)
	var target := ArenaStage.camera_target(Vector2(1800.0, 250.0), letterbox, VIEW)
	assert_almost_eq(
		target.x, letterbox.end.x - VIEW.x * 0.5, "the wide axis still clamps to its wall"
	)
	assert_almost_eq(
		target.y, letterbox.get_center().y, "the short axis centres regardless of the player"
	)
