extends TestCase

## Steering arrives from clients, and the server multiplies it straight by
## `PLAYER_MOVE_SPEED`. Every case here is something a modified client can actually
## send, and the length clamp in particular is the whole of the speed-hack defence.


func test_a_unit_direction_passes_through_untouched() -> void:
	var direction := Vector2(0.6, 0.8)
	assert_eq(
		NetProtocol.sanitize_direction(direction), direction, "honest input is not bent"
	)


func test_standing_still_stays_standing_still() -> void:
	assert_eq(
		NetProtocol.sanitize_direction(Vector2.ZERO),
		Vector2.ZERO,
		"a released button must not become movement"
	)


func test_an_oversized_direction_is_clamped_to_one() -> void:
	# The speed hack: without this, a length-50 vector is fifty times move speed.
	var hacked := NetProtocol.sanitize_direction(Vector2(50.0, 0.0))
	assert_almost_eq(hacked.length(), 1.0, "no client may exceed the move speed")
	assert_almost_eq(hacked.x, 1.0, "the direction it asked for is still honoured")


func test_a_short_direction_is_left_alone() -> void:
	# Walking slowly is not an exploit, and clamping up would be inventing input.
	var half := NetProtocol.sanitize_direction(Vector2(0.5, 0.0))
	assert_almost_eq(half.length(), 0.5, "a partial direction stays partial")


func test_a_non_finite_direction_becomes_no_direction() -> void:
	# NaN propagates into the position and then into every raycast that reads it, so it
	# has to die at the door rather than anywhere further in.
	assert_eq(
		NetProtocol.sanitize_direction(Vector2(NAN, 0.0)),
		Vector2.ZERO,
		"NaN steering must be dropped"
	)
	assert_eq(
		NetProtocol.sanitize_direction(Vector2(0.0, INF)),
		Vector2.ZERO,
		"infinite steering must be dropped"
	)
