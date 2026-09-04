extends TestCase

## UO-style steering: hold the right mouse button and you walk toward the cursor. The
## dead zone matters — without it, a cursor resting on your own feet produces a
## direction that flips every frame and the character vibrates in place.


func test_cursor_far_away_gives_a_unit_direction() -> void:
	var direction := Fighter.movement_direction_toward(Vector2.ZERO, Vector2(300, 0))
	assert_almost_eq(direction.length(), 1.0, "direction should be normalised")


func test_movement_points_at_the_cursor() -> void:
	var direction := Fighter.movement_direction_toward(Vector2(100, 100), Vector2(100, 400))
	assert_almost_eq(direction.x, 0.0, "no sideways drift when the cursor is straight down")
	assert_almost_eq(direction.y, 1.0, "should walk straight down toward the cursor")


func test_diagonal_cursor_gives_a_diagonal_direction() -> void:
	var direction := Fighter.movement_direction_toward(Vector2.ZERO, Vector2(200, 200))
	assert_almost_eq(direction.x, direction.y, "a 45 degree cursor walks at 45 degrees")
	assert_almost_eq(direction.length(), 1.0, "and still at full speed, not 1.41x")


func test_cursor_inside_the_dead_zone_does_not_move_you() -> void:
	var direction := Fighter.movement_direction_toward(Vector2.ZERO, Vector2(5, 0))
	assert_eq(direction, Vector2.ZERO, "a cursor on your own feet must not move you")


func test_cursor_exactly_on_the_character_does_not_move_you() -> void:
	var direction := Fighter.movement_direction_toward(Vector2(50, 50), Vector2(50, 50))
	assert_eq(direction, Vector2.ZERO, "a zero-length offset must not be normalised")


func test_just_outside_the_dead_zone_does_move_you() -> void:
	var just_outside := Fighter.MOUSE_DEAD_ZONE + 1.0
	var direction := Fighter.movement_direction_toward(Vector2.ZERO, Vector2(just_outside, 0))
	assert_almost_eq(direction.x, 1.0, "past the dead zone you should walk normally")
