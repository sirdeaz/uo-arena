extends TestCase

## Routing around cover only helps if the route is one the body actually fits through.
## That is what the inflation is for, and it is where this can go wrong in two directions
## at once: inflate too little and a path clips a tent corner, inflate too much and a gap
## the player really fits through is sealed and the arena quietly falls apart.
##
## These run against the real `arena_map.tscn`, so the numbers below are the arena's own.

const CLEARANCE: float = Constants.PLAYER_RADIUS + PathFinder.CLEARANCE_MARGIN

## The two tents, at |y| in 85..195, leave a lane 170px tall between them. Inflation eats
## `CLEARANCE` off each side of it.
const LANE_CLEAR_Y: float = 60.0
const LANE_BLOCKED_Y: float = 104.0

## The narrowest real gap in the arena: a corner rock stops at |y| = 305 and the wall face
## is at |y| = 400.
const NARROWEST_GAP: float = 95.0

var map: ArenaMap
var finder: PathFinder


func before_each() -> void:
	map = load("res://arena/arena.tscn").instantiate()
	add_child(map)
	finder = PathFinder.new()
	finder.build(map)


func after_each() -> void:
	map.queue_free()


func _square(half: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half),
	])


# ── Inflation ─────────────────────────────────────────────────────────────────────


func test_inflating_a_square_grows_it_on_every_side() -> void:
	var grown := PathFinder.inflate(_square(50.0), 10.0)
	assert_true(grown.size() >= 4, "a square should still be a polygon after inflating")
	assert_true(
		absf(PathFinder.polygon_area(grown)) > absf(PathFinder.polygon_area(_square(50.0))),
		"inflating must grow the shape, not shrink it"
	)
	for point in grown:
		assert_true(
			absf(point.x) > 50.0 or absf(point.y) > 50.0,
			"every corner should have moved outward"
		)


func test_inflation_does_not_depend_on_which_way_the_polygon_is_wound() -> void:
	# Godot's offset follows the ring's winding, and a convex polygon shape carries
	# whatever order its author gave it. If this is wrong, obstacles silently shrink and
	# routes run straight through tents.
	var clockwise := _square(50.0)
	var counter := _square(50.0)
	counter.reverse()

	var a := absf(PathFinder.polygon_area(PathFinder.inflate(clockwise, 10.0)))
	var b := absf(PathFinder.polygon_area(PathFinder.inflate(counter, 10.0)))
	assert_almost_eq(a, b, "winding must not change the result", 1.0)
	assert_true(a > absf(PathFinder.polygon_area(clockwise)), "and both must grow")


func test_a_shape_too_small_to_be_a_polygon_inflates_to_nothing() -> void:
	assert_eq(
		PathFinder.inflate(PackedVector2Array([Vector2.ZERO, Vector2.ONE]), 5.0).size(),
		0,
		"two points are not a shape and must not become one"
	)


# ── Clearance ─────────────────────────────────────────────────────────────────────


func test_a_segment_along_a_face_is_clear() -> void:
	# Graph corners sit on these outlines, so a route that hugs one has to be allowed —
	# otherwise every edge is rejected as a collision with the thing it goes around and no
	# path is ever found.
	var polygons: Array[PackedVector2Array] = [_square(50.0)]
	assert_true(
		PathFinder.segment_is_clear(Vector2(-50, -50), Vector2(50, -50), polygons),
		"running along an edge between two of its own corners must be allowed"
	)


func test_a_segment_across_the_middle_is_blocked() -> void:
	var polygons: Array[PackedVector2Array] = [_square(50.0)]
	assert_false(
		PathFinder.segment_is_clear(Vector2(-50, -50), Vector2(50, 50), polygons),
		"a diagonal between opposite corners goes through the inside"
	)
	assert_false(
		PathFinder.segment_is_clear(Vector2(-200, 0), Vector2(200, 0), polygons),
		"and so does a line straight through it"
	)


func test_a_line_that_grazes_a_tent_is_blocked_once_the_body_is_accounted_for() -> void:
	# This is the whole point of inflating. A ray is a zero-width line, so it calls this
	# clear; an eighteen-pixel body clips the corner.
	var just_past := 100.0 + Constants.PLAYER_RADIUS * 0.5
	assert_false(
		finder.segment_is_walkable(Vector2(just_past, -300.0), Vector2(just_past, 0.0)),
		"passing within half a body width of a tent corner is not walkable"
	)


func test_clearance_stays_well_under_the_narrowest_gap() -> void:
	# A tripwire for anyone tempted to raise the margin "just a bit". Two lots of
	# clearance have to fit inside the tightest gap in the arena, with room to spare.
	assert_true(
		2.0 * CLEARANCE < NARROWEST_GAP,
		"clearance on both sides must fit through the rock-to-wall gap"
	)


# ── The map ───────────────────────────────────────────────────────────────────────


func test_every_solid_thing_in_the_arena_becomes_an_obstacle() -> void:
	# Four cover pieces and four walls. Missing the walls would let routes leave the map.
	assert_eq(
		PathFinder.obstacle_polygons(map).size(), 8, "four cover pieces and four walls"
	)


func test_the_duel_lane_is_walkable_straight_down_the_middle() -> void:
	var spawns := map.get_spawn_positions()
	assert_true(
		finder.segment_is_walkable(spawns[0], spawns[1]),
		"the opening shot down the lane must not need a detour"
	)
	assert_eq(
		finder.find_path(spawns[0], spawns[1]).size(),
		1,
		"a clear line should be one hop, straight to the destination"
	)


func test_the_duel_lane_survives_inflation() -> void:
	# Pinned from both sides on purpose. Raise the clearance and the first assertion
	# fails; drop it to nothing and the second one does.
	assert_true(
		finder.segment_is_walkable(
			Vector2(-500.0, LANE_CLEAR_Y), Vector2(500.0, LANE_CLEAR_Y)
		),
		"the lane between the tents must stay open to a real body"
	)
	assert_false(
		finder.segment_is_walkable(
			Vector2(-500.0, LANE_BLOCKED_Y), Vector2(500.0, LANE_BLOCKED_Y)
		),
		"and a line that clips a tent must not be called walkable"
	)


func test_a_route_around_a_tent_turns_a_corner_and_stays_clear() -> void:
	var from := Vector2(0.0, -300.0)
	var to := Vector2(0.0, 300.0)
	assert_false(
		finder.segment_is_walkable(from, to), "the tents are in the way of this one"
	)

	var path := finder.find_path(from, to)
	assert_true(path.size() > 1, "getting past two tents takes at least one corner")
	assert_eq(path[path.size() - 1], to, "and it has to actually end where you asked")

	var previous := from
	for point in path:
		assert_true(
			finder.segment_is_walkable(previous, point),
			"every leg of the route has to be walkable on its own"
		)
		previous = point


func test_a_detour_is_not_wildly_longer_than_the_straight_line() -> void:
	var from := Vector2(0.0, -300.0)
	var to := Vector2(0.0, 300.0)
	var path := finder.find_path(from, to)

	var length := 0.0
	var previous := from
	for point in path:
		length += previous.distance_to(point)
		previous = point

	assert_true(
		length < from.distance_to(to) * 1.6,
		"rounding the tents should cost a detour, not a tour of the arena"
	)


func test_every_pair_of_spawns_can_reach_each_other() -> void:
	# The broad guard: any future edit that seals a corridor disconnects some pair, and
	# this says so without anyone having to think about which corridor.
	var spawns := map.get_spawn_positions()
	for i in spawns.size():
		for j in range(i + 1, spawns.size()):
			assert_false(
				finder.find_path(spawns[i], spawns[j]).is_empty(),
				"spawn %d and spawn %d should be able to reach each other" % [i, j]
			)


func test_the_same_question_gives_the_same_answer() -> void:
	var from := Vector2(0.0, -300.0)
	var to := Vector2(0.0, 300.0)
	assert_eq(
		finder.find_path(from, to),
		finder.find_path(from, to),
		"a route that changed between identical queries would flicker on screen"
	)


# ── Awkward starts and ends ───────────────────────────────────────────────────────


func test_standing_against_a_tent_can_still_find_a_route() -> void:
	# Clearance is wider than the tent, so touching one puts you inside its zone. A route
	# that refused to start there would switch the assist off exactly where it is wanted.
	var hugging := Vector2(0.0, -85.0 - Constants.PLAYER_RADIUS)
	var path := finder.find_path(hugging, Vector2(0.0, 300.0))
	assert_false(path.is_empty(), "a route out of a tent's clearance zone must exist")


func test_a_destination_inside_cover_walks_you_up_to_it() -> void:
	# Clicking on a tent is a thing people do. Getting as close as the tent allows is the
	# sensible reading of it, and it is certainly better than refusing to move.
	var path := finder.find_path(Vector2(0.0, -300.0), Vector2(0.0, -140.0))
	assert_false(path.is_empty(), "clicking on a tent should still take you to it")
	var previous := Vector2(0.0, -300.0)
	for point in path:
		assert_true(
			finder.segment_is_walkable(previous, point), "and by a walkable route"
		)
		previous = point


func test_a_destination_outside_the_arena_does_not_crash_the_search() -> void:
	var path := finder.find_path(Vector2(0.0, 0.0), Vector2(9000.0, 9000.0))
	assert_true(
		path.is_empty() or finder.segment_is_walkable(Vector2(0.0, 0.0), path[0]),
		"an unreachable destination must give either nothing or a walkable first leg"
	)
