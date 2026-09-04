extends TestCase

## The arena's job is to make positioning matter. These tests assert that as a
## property of the layout rather than trusting the eye: cover must actually break
## line of sight from reachable ground, and it must do so within a couple of seconds
## of movement, or it is decoration.

const SECONDS_OF_MOVEMENT := 2.0

var map: ArenaMap
var resolver: CombatResolver


func before_each() -> void:
	map = load("res://server/arena_map.tscn").instantiate()
	add_child(map)
	resolver = CombatResolver.new()
	add_child(resolver)


func after_each() -> void:
	map.queue_free()
	resolver.queue_free()


func _space_state() -> PhysicsDirectSpaceState2D:
	return map.get_world_2d().direct_space_state


## Positions on a ring the player could reach in `SECONDS_OF_MOVEMENT`, discarding any
## that are inside a wall or outside the arena.
func _reachable_ring(origin: Vector2) -> Array[Vector2]:
	var radius := Constants.PLAYER_MOVE_SPEED * SECONDS_OF_MOVEMENT
	var reachable: Array[Vector2] = []
	for step in 72:
		var angle := TAU * float(step) / 72.0
		var point := origin + Vector2(radius, 0).rotated(angle)
		if not map.is_inside_bounds(point):
			continue
		var query := PhysicsPointQueryParameters2D.new()
		query.position = point
		query.collision_mask = Constants.LAYER_OBSTACLES
		if not _space_state().intersect_point(query).is_empty():
			continue  # standing inside a tent
		reachable.append(point)
	return reachable


# ── structure ─────────────────────────────────────────────────────────────────

func test_map_has_two_spawn_points() -> void:
	assert_eq(map.get_spawn_positions().size(), 2, "1v1 needs exactly two spawns")


func test_cover_pieces_are_within_the_planned_count() -> void:
	var count := map.get_cover_pieces().size()
	assert_true(count >= 3 and count <= 5, "expected 3-5 cover pieces, got %d" % count)


func test_every_cover_piece_sits_on_the_obstacles_layer() -> void:
	for piece in map.get_cover_pieces():
		assert_eq(
			piece.collision_layer & Constants.LAYER_OBSTACLES,
			Constants.LAYER_OBSTACLES,
			"%s must be on the obstacles layer or the raycast ignores it" % piece.name
		)


func test_arena_is_walled_in() -> void:
	await get_tree().physics_frame
	var centre := Vector2.ZERO
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		assert_false(
			resolver.has_line_of_sight(_space_state(), centre, centre + direction * 5000.0),
			"the arena should be enclosed towards %s" % direction
		)


# ── the layout actually plays ─────────────────────────────────────────────────

func test_spawns_can_see_each_other_at_the_start() -> void:
	await get_tree().physics_frame
	var spawns := map.get_spawn_positions()
	assert_true(
		resolver.has_line_of_sight(_space_state(), spawns[0], spawns[1]),
		"the duel should open with a shot available"
	)


func test_spawns_are_far_enough_apart_to_need_movement() -> void:
	var spawns := map.get_spawn_positions()
	var crossing_seconds := spawns[0].distance_to(spawns[1]) / Constants.PLAYER_MOVE_SPEED
	assert_true(
		crossing_seconds >= 4.0,
		"crossing the arena should take a few seconds, takes %.1f" % crossing_seconds
	)


func test_each_player_can_break_line_of_sight_within_two_seconds() -> void:
	await get_tree().physics_frame
	var spawns := map.get_spawn_positions()
	for i in spawns.size():
		var enemy: Vector2 = spawns[1 - i]
		var found_cover := false
		for point in _reachable_ring(spawns[i]):
			if not resolver.has_line_of_sight(_space_state(), point, enemy):
				found_cover = true
				break
		assert_true(
			found_cover,
			"spawn %d must be able to reach cover from the enemy in %ss" % [
				i, SECONDS_OF_MOVEMENT
			]
		)


func test_cover_blocks_from_both_sides_symmetrically() -> void:
	# A 1v1 map that favours one spawn is a broken 1v1 map.
	await get_tree().physics_frame
	var spawns := map.get_spawn_positions()
	var blocked_from_first := 0
	for point in _reachable_ring(spawns[0]):
		if not resolver.has_line_of_sight(_space_state(), point, spawns[1]):
			blocked_from_first += 1
	var blocked_from_second := 0
	for point in _reachable_ring(spawns[1]):
		if not resolver.has_line_of_sight(_space_state(), point, spawns[0]):
			blocked_from_second += 1
	assert_eq(
		blocked_from_first,
		blocked_from_second,
		"both spawns should have the same amount of cover available"
	)


func test_the_centre_lane_is_open_but_stepping_off_it_is_not() -> void:
	# The opening duel lane: a clear shot straight down the middle, with cover a
	# short step away on either side.
	await get_tree().physics_frame
	var spawns := map.get_spawn_positions()
	assert_true(
		resolver.has_line_of_sight(_space_state(), spawns[0], spawns[1]),
		"the lane itself is open"
	)
	var stepped_aside := spawns[0] + Vector2(0, 200)
	assert_false(
		resolver.has_line_of_sight(_space_state(), stepped_aside, spawns[1]),
		"stepping off the lane should immediately break the shot"
	)
