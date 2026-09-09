extends TestCase

## The steering layer answers "where do I aim right now", and the goal it is aiming at is
## the live cursor — it moves every frame. That is what makes this worth testing on its
## own: a route that is individually correct every tick can still wobble, flip sides, or
## never actually arrive.
##
## The walking tests below are a plain kinematic simulation — no physics server, no
## rendering — which is the whole reason this was built out of geometry rather than a
## navigation mesh.

## What a player covers in one physics tick at the pinned rate.
const STEP: float = Constants.PLAYER_MOVE_SPEED / 60.0

const NORTH_OF_THE_TENTS := Vector2(0.0, -300.0)
const SOUTH_OF_THE_TENTS := Vector2(0.0, 300.0)

var map: ArenaMap
var finder: PathFinder
var steering: PathSteering


func before_each() -> void:
	map = load("res://arena/arena_map.tscn").instantiate()
	add_child(map)
	finder = PathFinder.new()
	finder.build(map)
	steering = PathSteering.new(finder)


func after_each() -> void:
	map.queue_free()


## Walks toward `cursor` a tick at a time, reporting every position it stood in.
func _walk(from: Vector2, cursor: Vector2, ticks: int) -> Array[Vector2]:
	var visited: Array[Vector2] = [from]
	var at := from
	for _tick in ticks:
		if at.distance_to(cursor) <= Fighter.MOUSE_DEAD_ZONE:
			break
		var aim := steering.waypoint_toward(at, cursor)
		var offset := aim - at
		if offset.is_zero_approx():
			break
		at += offset.normalized() * STEP
		visited.append(at)
	return visited


# ── The straight line is untouched ────────────────────────────────────────────────


func test_a_clear_cursor_comes_back_exactly_as_it_went_in() -> void:
	# Returned by identity, so the caller can tell "nothing to add" from "go here" and
	# fall through to the very same call it has always made.
	var cursor := Vector2(400.0, 0.0)
	assert_eq(
		steering.waypoint_toward(Vector2(-400.0, 0.0), cursor),
		cursor,
		"with a clear lane the cursor must come back untouched"
	)


func test_a_clear_cursor_leaves_no_route_behind() -> void:
	steering.waypoint_toward(Vector2(-400.0, 0.0), Vector2(400.0, 0.0))
	assert_true(
		steering.path().is_empty(), "nothing to draw when steering is already straight"
	)


func test_a_blocked_cursor_aims_somewhere_else() -> void:
	var aim := steering.waypoint_toward(NORTH_OF_THE_TENTS, SOUTH_OF_THE_TENTS)
	assert_false(
		aim == SOUTH_OF_THE_TENTS, "with two tents in the way, aim must leave the line"
	)
	assert_false(steering.path().is_empty(), "and there should be a route to draw")


# ── Walking it ────────────────────────────────────────────────────────────────────


func test_walking_the_route_actually_arrives() -> void:
	var visited := _walk(NORTH_OF_THE_TENTS, SOUTH_OF_THE_TENTS, 600)
	var arrived: Vector2 = visited[visited.size() - 1]
	assert_true(
		arrived.distance_to(SOUTH_OF_THE_TENTS) <= Fighter.MOUSE_DEAD_ZONE + STEP,
		"following the aim tick by tick has to end up at the cursor"
	)


func test_walking_the_route_never_clips_cover() -> void:
	# The real test of the inflation: the body, not just its centre, has to stay out.
	# Checked against the un-inflated shapes so this cannot pass by agreeing with itself.
	var margins: Array[PackedVector2Array] = []
	for polygon in PathFinder.obstacle_polygons(map):
		var margin := PathFinder.inflate(polygon, Constants.PLAYER_RADIUS - 2.0)
		if margin.size() >= 3:
			margins.append(margin)

	for point in _walk(NORTH_OF_THE_TENTS, SOUTH_OF_THE_TENTS, 600):
		for margin in margins:
			assert_false(
				Geometry2D.is_point_in_polygon(point, margin),
				"the body clipped cover at %s" % point
			)


func test_walking_the_route_does_not_wander() -> void:
	var visited := _walk(NORTH_OF_THE_TENTS, SOUTH_OF_THE_TENTS, 600)
	var walked := float(visited.size() - 1) * STEP
	assert_true(
		walked < NORTH_OF_THE_TENTS.distance_to(SOUTH_OF_THE_TENTS) * 2.0,
		"a detour around two tents should not cost double the straight line"
	)


func test_the_route_never_doubles_back() -> void:
	# Reversing hard between ticks is what side-flipping looks like from the inside, and
	# on screen it reads as the character shuddering instead of setting off.
	var visited := _walk(NORTH_OF_THE_TENTS, SOUTH_OF_THE_TENTS, 600)
	for i in range(2, visited.size()):
		var before: Vector2 = visited[i - 1] - visited[i - 2]
		var after: Vector2 = visited[i] - visited[i - 1]
		if before.is_zero_approx() or after.is_zero_approx():
			continue
		assert_true(
			before.normalized().dot(after.normalized()) > -0.5,
			"steering swung more than 120 degrees in one tick, at step %d" % i
		)


# ── Solving no more often than needed ─────────────────────────────────────────────


func test_solving_is_throttled_rather_than_run_every_tick() -> void:
	var at := NORTH_OF_THE_TENTS
	for _tick in 120:
		var aim := steering.waypoint_toward(at, SOUTH_OF_THE_TENTS)
		var offset := aim - at
		if not offset.is_zero_approx():
			at += offset.normalized() * STEP
	assert_true(
		steering.plans_run < 120,
		"a route solved every single tick would be doing avoidable work"
	)


func test_being_asked_twice_in_one_tick_answers_the_same_twice() -> void:
	# In multiplayer the fighter and the client both ask, in the same tick. Two different
	# answers would mean predicting one route while sending another.
	var first := steering.waypoint_toward(NORTH_OF_THE_TENTS, SOUTH_OF_THE_TENTS)
	var solves := steering.plans_run
	var second := steering.waypoint_toward(NORTH_OF_THE_TENTS, SOUTH_OF_THE_TENTS)

	assert_eq(first, second, "the same question in the same tick has one answer")
	assert_eq(solves, steering.plans_run, "and must not solve the route twice over")


# ── Giving up gracefully ──────────────────────────────────────────────────────────


func test_rounding_a_corner_never_stalls_on_top_of_it() -> void:
	# A corner you are standing on is inside the dead zone, and aiming at it would stop
	# you dead there. Rounding one has to keep you moving the whole way through.
	var at := NORTH_OF_THE_TENTS
	for _tick in 600:
		if at.distance_to(SOUTH_OF_THE_TENTS) <= Fighter.MOUSE_DEAD_ZONE:
			return
		var aim := steering.waypoint_toward(at, SOUTH_OF_THE_TENTS)
		assert_false(
			(aim - at).is_zero_approx(), "steering gave up at %s" % at
		)
		at += (aim - at).normalized() * STEP
	assert_true(false, "the walk should have arrived well inside 600 ticks")


func test_a_cursor_that_is_not_a_number_is_handed_straight_back() -> void:
	# Compared component-wise because a NaN is not equal to itself, so `assert_eq` on the
	# vector would fail even when the value came back untouched.
	var aim := steering.waypoint_toward(Vector2.ZERO, Vector2(NAN, NAN))
	assert_true(
		is_nan(aim.x) and is_nan(aim.y),
		"nothing sensible can be routed to, so do not try"
	)


func test_every_position_in_the_arena_produces_an_aim_you_can_move_toward() -> void:
	# The governing rule: routing may fail to help, but it must never be the reason a
	# player cannot move. Walking into a tent is a worse route, never a wrong answer.
	var cursor := Vector2(0.0, 260.0)
	for x in range(-560, 561, 80):
		for y in range(-360, 361, 80):
			var at := Vector2(float(x), float(y))
			if at.distance_to(cursor) <= Fighter.MOUSE_DEAD_ZONE:
				continue
			var aim := steering.waypoint_toward(at, cursor)
			assert_false(
				(aim - at).is_zero_approx(),
				"standing at %s left nowhere to aim" % at
			)


func test_a_detour_picks_a_side_and_stays_on_it() -> void:
	# The cursor here sits on the tents' line of symmetry, where going round to the left
	# and going round to the right cost exactly the same. Without something to break the
	# tie the same way every time, the choice flips on each solve and the character
	# shudders on the spot instead of setting off.
	var at := NORTH_OF_THE_TENTS
	var side := 0.0

	for _tick in 600:
		if at.distance_to(SOUTH_OF_THE_TENTS) <= Fighter.MOUSE_DEAD_ZONE:
			break
		var aim := steering.waypoint_toward(at, SOUTH_OF_THE_TENTS)
		var route := steering.path()
		if not route.is_empty() and absf(route[0].x) > 1.0:
			var this_side: float = signf(route[0].x)
			if side == 0.0:
				side = this_side
			assert_eq(this_side, side, "the detour changed sides part way round")
		at += (aim - at).normalized() * STEP

	assert_false(side == 0.0, "this walk should have committed to a side at all")
