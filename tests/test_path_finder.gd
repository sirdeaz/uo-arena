extends TestCase

## Routing around cover only helps if the route is one the body actually fits through.
## That is what the inflation is for, and it is where this can go wrong in two directions
## at once: inflate too little and a path clips a tent corner, inflate too much and a gap
## the player really fits through is sealed and the arena quietly falls apart.
##
## These run against `tests/fixtures/mechanics_arena.tscn` (#123), not the real, evolving
## `arena_map.tscn` — a mechanic like inflation or corner-rounding should hold regardless
## of whatever the shipped arena's art currently looks like, and pinning these numbers to
## real hand-painted cover meant every repaint broke them for reasons that had nothing to
## do with the mechanic itself. The fixture is two plain 128×128 squares, exact mirrors of
## each other through the origin: the "north tent" spans x:[-64,64], y:[-256,-128], the
## "south tent" x:[-64,64], y:[128,256] — chosen for round numbers, not to resemble the
## real arena.

const CLEARANCE: float = Constants.PLAYER_RADIUS + PathFinder.CLEARANCE_MARGIN

## The fixture's own geometry — see the header above. Named so the tests below read as
## "the tent's edge", not a repeated magic number.
const NORTH_TENT_SOUTH_EDGE: float = -128.0
const NORTH_TENT_EAST_EDGE: float = 64.0

## A horizontal line close to the spawn line, clear of both tents. The blocked
## counterpart is read off the fixture at test time — see `_a_horizontal_line_that_clips_cover`.
const LANE_CLEAR_Y: float = 60.0

## The narrowest gap the clearance margin has to fit through in the real, shipped arena,
## with room to spare — a tripwire independent of the fixture below, since it is about
## whether `CLEARANCE_MARGIN` itself is configured safely, not about routing mechanics.
const NARROWEST_GAP: float = 95.0

var map: ArenaMap
var finder: PathFinder


func before_each() -> void:
	map = load("res://tests/fixtures/mechanics_arena.tscn").instantiate()
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
	# clear — the north tent's raw east edge sits at x=64, and `just_past` is outside
	# that — but an eighteen-pixel body clips the corner well before x=86, where the
	# inflated edge actually sits.
	var just_past := NORTH_TENT_EAST_EDGE + Constants.PLAYER_RADIUS * 0.5
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
	# Whatever is painted with collision has to reach the routing graph — a cell the
	# graph cannot see is one a route runs straight through.
	var polygons := PathFinder.obstacle_polygons(map)
	assert_true(polygons.size() >= 1, "the arena has cover, so the graph must have obstacles")
	for node in [map.get_node("Walls"), map.get_node("Cover")]:
		var layer: TileMapLayer = node
		for cell in layer.get_used_cells():
			var data := layer.get_cell_tile_data(cell)
			if data == null or data.get_collision_polygons_count(0) == 0:
				continue
			var centre := layer.to_global(layer.map_to_local(cell))
			var seen := false
			for polygon in polygons:
				if Geometry2D.is_point_in_polygon(centre, polygon):
					seen = true
					break
			assert_true(seen, "painted cell at %s reached no obstacle polygon" % centre)


## Moved from `tests/test_arena_tiles.gd` (#123): this is `obstacle_polygons()`'s own
## area-conservation property, true for any painted layout with tiles whose collision
## fills exactly their own cell — it is not a fact about the real arena's specific paint,
## so it belongs here against the fixture, not against content that keeps moving.
func test_obstacle_polygons_cover_exactly_the_painted_cells() -> void:
	var walls: TileMapLayer = map.get_node("Walls")
	var cover: TileMapLayer = map.get_node("Cover")
	var cell_area := float(walls.tile_set.tile_size.x * walls.tile_set.tile_size.y)

	var solid_cells := 0
	for layer: TileMapLayer in [walls, cover]:
		for cell in layer.get_used_cells():
			var data := layer.get_cell_tile_data(cell)
			if data != null and data.get_collision_polygons_count(0) > 0:
				solid_cells += 1
	var expected := float(solid_cells) * cell_area

	var total := 0.0
	for polygon in PathFinder.obstacle_polygons(map):
		assert_true(polygon.size() >= 3, "obstacle polygon %s has no area" % polygon)
		total += absf(PathFinder.polygon_area(polygon))

	assert_almost_eq(
		total, expected,
		"the obstacle polygons cover a different area than the painted cells", 1.0
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
	# Pinned from both sides on purpose: the opening lane admits a real body, and a
	# parallel line that runs into cover does not. Both y values are read off the arena
	# rather than hard-coded, so a repaint moves them.
	assert_true(
		finder.segment_is_walkable(
			Vector2(-500.0, LANE_CLEAR_Y), Vector2(500.0, LANE_CLEAR_Y)
		),
		"the lane between the spawns must stay open to a real body"
	)
	var blocked_y := _a_horizontal_line_that_clips_cover()
	assert_true(blocked_y != INF, "the arena has cover on the way across, so some line must clip it")
	assert_false(
		finder.segment_is_walkable(Vector2(-500.0, blocked_y), Vector2(500.0, blocked_y)),
		"a line that clips cover at y=%s must not be called walkable" % blocked_y
	)


## Sweeps horizontal lines across the arena and returns the first y whose crossing a real
## body cannot make, or INF if the way is somehow all clear.
func _a_horizontal_line_that_clips_cover() -> float:
	var extent := map.bounds()
	var y := extent.position.y + 8.0
	while y < extent.end.y:
		if not finder.segment_is_walkable(Vector2(-500.0, y), Vector2(500.0, y)):
			return y
		y += 8.0
	return INF


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
	# One pixel north of the tent's own south edge: not actually inside the solid tile,
	# but well inside the inflated clearance around it.
	var hugging := Vector2(0.0, NORTH_TENT_SOUTH_EDGE + 1.0)
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
