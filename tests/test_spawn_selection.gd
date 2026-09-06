extends TestCase

## Choosing where a player appears. Pure arithmetic, no physics — the map stays dumb
## about who is standing on it, and the server does the choosing.

const SPAWNS: Array[Vector2] = [
	Vector2(-500.0, 0.0),
	Vector2(500.0, 0.0),
	Vector2(-500.0, 280.0),
	Vector2(500.0, -280.0),
]


func test_an_empty_arena_uses_the_first_spawn() -> void:
	assert_eq(
		ArenaServer.pick_spawn(SPAWNS, []),
		SPAWNS[0],
		"with nobody about, the duel spawn is as good as any"
	)


func test_you_appear_as_far_from_everyone_as_the_map_allows() -> void:
	var occupied: Array[Vector2] = [Vector2(-500.0, 0.0)]
	var chosen := ArenaServer.pick_spawn(SPAWNS, occupied)
	assert_true(
		chosen.x > 0.0, "chose %s, which is the same side as the only other player" % chosen
	)


func test_the_choice_accounts_for_everyone_not_just_the_nearest() -> void:
	# Both eastern spawns are crowded, so the west should win even though each
	# individual westerner is further away than any single easterner.
	var occupied: Array[Vector2] = [Vector2(500.0, 0.0), Vector2(500.0, -280.0)]
	var chosen := ArenaServer.pick_spawn(SPAWNS, occupied)
	assert_true(chosen.x < 0.0, "chose %s, next to the crowd" % chosen)


func test_a_full_arena_still_returns_somewhere_to_stand() -> void:
	# Everyone alive is standing on a spawn. There is no good answer, but there must be
	# an answer — refusing to place a player would leave them at the origin.
	var occupied: Array[Vector2] = []
	for spawn in SPAWNS:
		occupied.append(spawn)
	assert_true(SPAWNS.has(ArenaServer.pick_spawn(SPAWNS, occupied)), "still a real spawn")


func test_a_map_with_no_spawns_does_not_crash() -> void:
	var none: Array[Vector2] = []
	assert_eq(ArenaServer.pick_spawn(none, none), Vector2.ZERO, "the origin is the fallback")


# ── Joining, as opposed to respawning ─────────────────────────────────────────────


func test_the_first_two_to_join_get_the_duel_lane() -> void:
	# The map is drawn around that opening. Placing joiners by distance instead would
	# put the first two arrivals diagonally opposite with a tent between them.
	var occupied: Array[Vector2] = []
	var first := ArenaServer.first_free_spawn(SPAWNS, occupied)
	occupied.append(first)
	var second := ArenaServer.first_free_spawn(SPAWNS, occupied)

	assert_eq(first, SPAWNS[0], "the first player takes the west lane spawn")
	assert_eq(second, SPAWNS[1], "and the second takes the east one, facing them")


func test_joining_skips_spawns_that_are_stood_on() -> void:
	var occupied: Array[Vector2] = [SPAWNS[0], SPAWNS[1]]
	assert_eq(
		ArenaServer.first_free_spawn(SPAWNS, occupied),
		SPAWNS[2],
		"a joiner should not land on top of someone"
	)


func test_joining_a_full_arena_still_finds_somewhere() -> void:
	var occupied: Array[Vector2] = []
	for spawn in SPAWNS:
		occupied.append(spawn)
	assert_true(
		SPAWNS.has(ArenaServer.first_free_spawn(SPAWNS, occupied)),
		"with every marker taken it falls back to the least crowded"
	)
