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


# ── Pathfinding ───────────────────────────────────────────────────────────────────
# The six tests above are deliberately untouched: they pin the straight-line contract,
# and their still passing is what says the assist changed nothing underneath it.


var _map: ArenaMap
var _fighter: Fighter


func before_each() -> void:
	_map = load("res://server/arena_map.tscn").instantiate()
	add_child(_map)

	var finder := PathFinder.new()
	finder.build(_map)

	_fighter = Fighter.new()
	add_child(_fighter)
	_fighter.enable_pathfinding(finder)
	# North of the tents, with the far side of both of them as the destination.
	_fighter.global_position = Vector2(0.0, -300.0)


func after_each() -> void:
	_fighter.queue_free()
	_map.queue_free()


func test_pathfinding_starts_switched_off() -> void:
	assert_false(
		_fighter.pathfinding_enabled,
		"manual steering is the game; the assist is opt-in"
	)


func test_the_toggle_reports_the_state_it_switched_to() -> void:
	assert_true(_fighter.toggle_pathfinding(), "first press turns it on")
	assert_false(_fighter.toggle_pathfinding(), "second press turns it off again")


func test_with_the_assist_off_a_blocked_cursor_steers_straight_at_it() -> void:
	var cursor := Vector2(0.0, 300.0)
	assert_eq(
		_fighter.steering_direction_toward(cursor),
		Fighter.movement_direction_toward(_fighter.global_position, cursor),
		"off has to be the old behaviour exactly, not something equivalent to it"
	)


func test_a_clear_cursor_steers_identically_with_the_assist_on() -> void:
	# Nothing in the way means nothing to add, and the vector must be the same one down
	# to the bit — this is what makes the toggle safe to leave on.
	_fighter.global_position = Vector2(-500.0, 0.0)
	_fighter.pathfinding_enabled = true
	var cursor := Vector2(500.0, 0.0)
	assert_eq(
		_fighter.steering_direction_toward(cursor),
		Fighter.movement_direction_toward(_fighter.global_position, cursor),
		"a clear lane must steer exactly as it always has"
	)


func test_a_blocked_cursor_steers_off_the_straight_line() -> void:
	_fighter.pathfinding_enabled = true
	var cursor := Vector2(0.0, 300.0)
	var routed := _fighter.steering_direction_toward(cursor)

	assert_false(
		routed == Fighter.movement_direction_toward(_fighter.global_position, cursor),
		"with two tents in the way the assist should pick a different direction"
	)
	assert_almost_eq(routed.length(), 1.0, "and still walk at full speed")


func test_the_dead_zone_still_wins_with_the_assist_on() -> void:
	_fighter.pathfinding_enabled = true
	assert_eq(
		_fighter.steering_direction_toward(_fighter.global_position + Vector2(5.0, 0.0)),
		Vector2.ZERO,
		"a cursor on your own feet must not move you, routed or not"
	)


func test_a_fighter_with_no_route_finder_just_walks_straight() -> void:
	# Every remote body is in this state, and so is every test that never asked for the
	# assist. It must cost them nothing.
	var plain := Fighter.new()
	add_child(plain)
	plain.global_position = Vector2(0.0, -300.0)
	plain.pathfinding_enabled = true

	var cursor := Vector2(0.0, 300.0)
	assert_eq(
		plain.steering_direction_toward(cursor),
		Fighter.movement_direction_toward(plain.global_position, cursor),
		"no finder means no routing, not a crash"
	)
	plain.queue_free()
