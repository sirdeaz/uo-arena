extends TestCase

## Walking a real `Fighter` past real cover, with the dead zone and `move_and_slide` both
## in the loop.
##
## `tests/test_path_steering.gd` cannot ask these questions and is right not to try: its
## `_walk` steps a bare point straight at whatever `PathSteering` answered, with no dead
## zone and nothing to bump into. Both of those are half of issue #28. The stall was a
## floor up, in `Fighter.steering_direction_toward` putting a waypoint through the
## cursor's dead zone, and it only closed into a cycle because the cover pushed the body
## back out again. A test that models neither passes while a player stands vibrating
## against a tent with the button held.
##
## So this one drives the body the way `_physics_process` does — ask `Fighter`, set
## `velocity`, `move_and_slide` — and reads the collisions the engine reports rather than
## a re-implementation of them.

## What a player covers in one physics tick at the pinned rate.
const STEP: float = Constants.PLAYER_MOVE_SPEED / 60.0

## Ten seconds. Over a 1500-walk sweep of the arena the longest walk that genuinely
## arrives takes six, so anything still going at this point is going in circles.
const PATIENCE_TICKS: int = 600

## The authored fighter scene — its collision shape lives here now, not in `_ready`, so a
## bare `Fighter.new()` would slide straight through every tent.
const FIGHTER_SCENE := preload("res://client/scenes/fighter.tscn")

var _map: ArenaMap
var _finder: PathFinder
var _fighter: Fighter

## Cover grown by the body's radius, so "can I stand here" is one point-in-polygon test.
## Built once because building it is the expensive half of picking the walks.
var _no_go: Array[PackedVector2Array] = []


func before_each() -> void:
	_map = load("res://arena/arena_map.tscn").instantiate()
	add_child(_map)
	# The arena is collided by `TileMapLayer` tiles now, and their physics bodies are
	# built on the first physics step — not synchronously on `add_child` the way the old
	# `StaticBody2D` cover was. Without this wait `move_and_slide` walks straight through
	# every tent.
	await get_tree().physics_frame
	_finder = PathFinder.new()
	_finder.build(_map)

	_no_go = []
	for polygon in PathFinder.obstacle_polygons(_map):
		var grown := PathFinder.inflate(polygon, Constants.PLAYER_RADIUS + 1.0)
		if grown.size() >= 3:
			_no_go.append(grown)

	_fighter = FIGHTER_SCENE.instantiate()
	add_child(_fighter)
	_fighter.enable_pathfinding(_finder)
	_fighter.pathfinding_enabled = true


func after_each() -> void:
	_fighter.queue_free()
	_map.queue_free()


## What one walk did, so a test can ask about it without walking it again.
class Walk:
	var arrived: bool = false
	var ticks: int = 0
	var parked_at := Vector2.ZERO

	## Every tick the assist still had a corner to round and steered straight at the cursor
	## anyway. That is the bug in one number: the straight line is the line through the
	## cover the route was solved to go round.
	var gave_up_ticks: int = 0

	## Ticks the body spent in contact with cover.
	var contact_ticks: int = 0


## Holds the move button from `from` toward `cursor` until the body arrives or runs out
## of patience, exactly as `Fighter._physics_process` would.
func _hold_toward(from: Vector2, cursor: Vector2, ticks: int = PATIENCE_TICKS) -> Walk:
	var walk := Walk.new()
	_fighter.global_position = from

	for _tick in ticks:
		if _fighter.global_position.distance_to(cursor) <= Fighter.MOUSE_DEAD_ZONE:
			walk.arrived = true
			break

		var at := _fighter.global_position
		var direction := _fighter.steering_direction_toward(cursor)
		# More than one point left means a corner is still pending: the route ends at the
		# cursor, so a route of just that is the last leg and steering straight at it is
		# the right answer, not a fallback.
		if _fighter.steering_path().size() > 1:
			if direction == Fighter.movement_direction_toward(at, cursor):
				walk.gave_up_ticks += 1

		_fighter.velocity = direction * Constants.PLAYER_MOVE_SPEED
		_fighter.move_and_slide()
		walk.ticks += 1
		if _fighter.get_slide_collision_count() > 0:
			walk.contact_ticks += 1

	walk.parked_at = _fighter.global_position
	return walk


# ── The reported walk ─────────────────────────────────────────────────────────────


func test_the_walk_from_the_issue_arrives_instead_of_parking_on_the_corner() -> void:
	# Issue #28's own case. The route is [(122, -63), (122, -217), (0, -240)] and the
	# first waypoint is the north tent's inflated south-east corner. Before the fix this
	# settled into a seven-tick cycle at about (107, -68) and stayed there for as long as
	# the button was held — 400 ticks in, still 202px from the cursor.
	var walk := _hold_toward(Vector2(40.0, -40.0), Vector2(0.0, -240.0))
	assert_true(
		walk.arrived,
		"held toward (0, -240) the body parked at %s instead of arriving" % walk.parked_at
	)


func test_that_walk_never_steers_into_the_tent_it_is_rounding() -> void:
	# Arriving eventually is not enough. Every tick the assist falls back to the straight
	# line is a tick spent walking at the tent, and the flip-flop goes on the wire — the
	# same direction `ArenaClient` sends the server — so everyone watching sees the shuffle.
	var walk := _hold_toward(Vector2(40.0, -40.0), Vector2(0.0, -240.0))
	assert_eq(
		walk.gave_up_ticks,
		0,
		"the assist held a route and steered straight at the cursor anyway"
	)


func test_that_walk_is_no_slower_than_holding_the_button_with_the_assist_off() -> void:
	# The assist is meant to be free. Issue #28's worst case was a walk that finished in
	# 3.5s unassisted and never finished at all with the assist on.
	var assisted := _hold_toward(Vector2(40.0, -40.0), Vector2(0.0, -240.0))
	_fighter.pathfinding_enabled = false
	var manual := _hold_toward(Vector2(40.0, -40.0), Vector2(0.0, -240.0))

	assert_true(assisted.arrived, "the assisted walk has to arrive at all")
	if manual.arrived:
		assert_true(
			assisted.ticks <= manual.ticks,
			"the assist took %d ticks where sliding along the tent took %d"
				% [assisted.ticks, manual.ticks]
		)


func test_a_walk_that_lands_astride_a_corner_still_gets_past_it() -> void:
	# The other half of #28, and the half no aim-only test can reach. Steering at a corner
	# correctly is not enough to round it: a body moving 3.75px a tick cannot land on a
	# point, so it steps past, turns round, steps back past, and — because nothing later
	# on the route is in sight from either side of the corner — the aim never changes.
	# This walk is the one pair in a 1500-walk sweep of the arena that does it, ping-ponging
	# between (125.5, -215.9) and (121.9, -217.0) on the north tent's north-east corner
	# for as long as the button is held, never touching the cover at all while it does.
	var walk := _hold_toward(Vector2(-260.0, -340.0), Vector2(380.0, 20.0))
	assert_true(
		walk.arrived,
		"held toward (380, 20) the body ended up astride a corner at %s" % walk.parked_at
	)


# ── Every corner in the arena, not just that one ──────────────────────────────────


## Every cover piece approached head on from eight directions, with the cursor directly
## behind it — so all sixteen corners a player actually rounds, from both sides.
##
## Not a random sample and not an even grid: the four diagonals of each piece are its
## corners, and corners are the whole of this bug. Cover is inflated with `JOIN_MITER`, so
## a waypoint sits `22·√2` = 31.1px out from a right-angled corner while an 18px body
## cannot stand closer than 18px to it — leaving a band the body can reach where a 16px
## dead zone had already given up. Every piece here is an axis-aligned rectangle, so that
## band was every one of these corners, not a quirk of one tent.
func _crossings() -> Array:
	var reach := 170.0
	var pairs := []
	for rect in _map.cover_rects():
		var centre := rect.get_center()
		for octant in 8:
			var heading := Vector2.RIGHT.rotated(TAU * octant / 8.0)
			var from: Vector2 = centre + heading * reach
			var cursor: Vector2 = centre - heading * reach
			if not _standable(from) or not _standable(cursor):
				continue
			if _finder.segment_is_walkable(from, cursor):
				continue
			pairs.append([from, cursor])
	return pairs


## Somewhere the body actually fits, which is not the same as somewhere inside the walls.
func _standable(point: Vector2) -> bool:
	if not _map.is_inside_bounds(point):
		return false
	for polygon in _no_go:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return false
	return true


func test_the_sweep_actually_has_walks_in_it() -> void:
	# A sweep that quietly filtered itself down to nothing would pass forever. #28 names
	# this trap by name: the assist's existing grid test passed while the stall was live.
	var crossings := _crossings()
	assert_true(
		crossings.size() >= 24,
		"only %d crossings survived the filter, out of 32 tried" % crossings.size()
	)


func test_no_crossing_leaves_you_stranded_on_a_corner() -> void:
	for pair in _crossings():
		var walk := _hold_toward(pair[0], pair[1])
		assert_true(
			walk.arrived,
			"held from %s toward %s and parked at %s" % [pair[0], pair[1], walk.parked_at]
		)


func test_no_crossing_gives_up_and_walks_at_the_cover() -> void:
	for pair in _crossings():
		var walk := _hold_toward(pair[0], pair[1])
		assert_eq(
			walk.gave_up_ticks,
			0,
			"routing from %s to %s gave up on %d ticks" % [pair[0], pair[1], walk.gave_up_ticks]
		)


func test_rounding_a_corner_does_not_mean_scraping_along_it() -> void:
	# Retiring a waypoint early is retiring a corner early, and cutting the corner is what
	# that costs — so `PathSteering.ARRIVAL_RADIUS` is the clearance margin and not a
	# pixel more. This bites: at two ticks' travel these crossings spend 18 ticks against
	# cover, and at the player's own radius, 302.
	for pair in _crossings():
		var walk := _hold_toward(pair[0], pair[1])
		assert_eq(
			walk.contact_ticks,
			0,
			"walking from %s to %s touched cover on %d ticks"
				% [pair[0], pair[1], walk.contact_ticks]
		)


# ── The two bounds the arrival radius sits between ────────────────────────────────


func test_a_waypoint_cannot_be_straddled_forever() -> void:
	# The floor, and the reason the radius exists at all. A walker cannot land on a point
	# exactly: it steps past, turns round and steps back past. Further than half a step
	# out and it must land inside the radius on one of those passes — closer than that and
	# it can hop over the point forever, which is a stall with no cover involved in it at
	# all. #28 found exactly one of those in a 1500-walk sweep, on the north tent's
	# north-east corner.
	assert_true(
		PathSteering.ARRIVAL_RADIUS > STEP / 2.0,
		"a %.2fpx radius cannot capture a walker taking %.2fpx steps"
			% [PathSteering.ARRIVAL_RADIUS, STEP]
	)


func test_standing_on_a_retired_waypoint_still_keeps_the_body_off_the_cover() -> void:
	# The ceiling, and why the radius is the clearance margin rather than anything larger.
	# Cover is inflated by `PLAYER_RADIUS + CLEARANCE_MARGIN`, so a body within the margin
	# of a waypoint is still a full body radius clear of the faces that waypoint rounds.
	# Widen the radius past the margin and retiring a corner starts cutting into it.
	assert_true(
		PathSteering.ARRIVAL_RADIUS <= PathFinder.CLEARANCE_MARGIN,
		"retiring a waypoint from %.2fpx out reaches inside the %.2fpx the inflation bought"
			% [PathSteering.ARRIVAL_RADIUS, PathFinder.CLEARANCE_MARGIN]
	)


# ── With the assist off, none of this happens ─────────────────────────────────────


func test_with_the_assist_off_the_body_still_slides_along_the_tent() -> void:
	# The old behaviour, unchanged and deliberately so: holding the button at a point
	# behind a tent walks you into the tent. Getting yourself out of that is the skill the
	# assist is optional for, and this test is what says the fix did not quietly change it.
	_fighter.pathfinding_enabled = false
	var walk := _hold_toward(Vector2(40.0, -40.0), Vector2(0.0, -240.0))
	assert_true(
		walk.contact_ticks > 0,
		"manual steering at a blocked cursor should still put you against the cover"
	)
