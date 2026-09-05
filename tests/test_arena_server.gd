extends TestCase

## Everything a client can ask the server to do, including the things a modified client
## would ask. Runs against a real `ArenaServer` with real physics and no socket — the
## simulation never touches `MultiplayerAPI`, which is precisely what makes this
## testable at all.

const ARROW := 0
const FLAMESTRIKE := 3

var server: ArenaServer
var resolutions: Array = []


func before_each() -> void:
	server = ArenaServer.new()
	add_child(server)
	server.spell_resolved.connect(
		func(caster: int, target: int, spell_id: int, connected: bool) -> void:
			resolutions.append(
				{"caster": caster, "target": target, "spell": spell_id, "hit": connected}
			)
	)


func after_each() -> void:
	server.queue_free()


## Both fighters need placing explicitly: which spawn the arena hands out depends on the
## map, and these tests want a known clear shot down the lane.
func _place(peer_id: int, at: Vector2) -> void:
	server.body_of(peer_id).global_position = at
	server.combatant_of(peer_id).position = at


func _duel() -> void:
	server.add_player(2)
	server.add_player(3)
	_place(2, Vector2(-500.0, 0.0))
	_place(3, Vector2(500.0, 0.0))
	# Bodies have to settle before the resolver can raycast between them.
	await get_tree().physics_frame


## Long enough for a magic arrow to land, stepped in physics-sized slices.
func _run(seconds: float) -> void:
	var step := 1.0 / 60.0
	var elapsed := 0.0
	while elapsed < seconds:
		server.step(step)
		elapsed += step


# ── Roster ────────────────────────────────────────────────────────────────────────


func test_both_sides_step_at_the_same_physics_rate() -> void:
	# Movement is `move_and_slide`, which integrates at the engine's physics rate on
	# whichever machine it happens to run on. A client and a server that disagreed about
	# that rate would compute different travel from identical input, and prediction would
	# drift continuously instead of settling.
	#
	# It is pinned here rather than in project.godot because Godot drops any setting that
	# equals the engine default when it rewrites that file, so an entry there does not
	# survive the next import. This does.
	assert_eq(
		Engine.physics_ticks_per_second,
		60,
		"changing the physics rate desyncs prediction unless both ends change together"
	)


func test_players_join_until_the_arena_is_full() -> void:
	for index in Constants.MAX_PLAYERS:
		assert_true(server.add_player(index + 2), "player %d should get in" % index)
	assert_false(server.add_player(999), "the arena is full")
	assert_eq(server.player_count(), Constants.MAX_PLAYERS, "and stays full")


func test_the_same_peer_cannot_join_twice() -> void:
	assert_true(server.add_player(2), "the first join is fine")
	assert_false(server.add_player(2), "the second is not")
	assert_eq(server.player_count(), 1, "and did not add a second body")


func test_everyone_gets_their_own_slot() -> void:
	# The server hands out numbers and stops there — what a slot looks like is the
	# client's business, which is how `server/` stays free of rendering.
	for index in Constants.MAX_PLAYERS:
		server.add_player(index + 2)
	var seen := {}
	for slot in server.slots():
		assert_false(seen.has(slot), "two players hold slot %d" % slot)
		seen[slot] = true


func test_a_slot_is_reused_once_its_player_leaves() -> void:
	server.add_player(2)
	server.add_player(3)
	server.remove_player(2)
	server.add_player(4)
	assert_eq(server.slots().size(), 2, "two players, two slots")
	var seen := {}
	for slot in server.slots():
		assert_false(seen.has(slot), "a freed slot was handed out twice over")
		seen[slot] = true


func test_leaving_removes_the_player() -> void:
	server.add_player(2)
	server.remove_player(2)
	assert_false(server.has_player(2), "a peer that left is gone")
	assert_eq(server.combatant_of(2), null, "and takes its combatant with it")


# ── Cast requests a modified client could send ────────────────────────────────────


func test_a_stranger_cannot_cast() -> void:
	await _duel()
	assert_false(
		server.request_cast(404, ARROW, 3), "a peer not in the roster casts nothing"
	)


func test_nobody_can_cast_at_themselves() -> void:
	await _duel()
	assert_false(server.request_cast(2, ARROW, 2), "self-targeting is refused")


func test_casting_at_a_stranger_is_refused() -> void:
	await _duel()
	assert_false(server.request_cast(2, ARROW, 404), "there is nobody there to hit")


func test_an_unknown_spell_id_is_refused() -> void:
	await _duel()
	assert_false(server.request_cast(2, 9999, 3), "an id past the book is nonsense")
	assert_false(server.request_cast(2, -1, 3), "and so is a negative one")


func test_the_dead_cannot_cast() -> void:
	await _duel()
	server.combatant_of(2).take_damage(Constants.PLAYER_MAX_HEALTH)
	assert_false(server.request_cast(2, ARROW, 3), "a corpse casts nothing")


func test_nobody_can_cast_at_the_dead() -> void:
	await _duel()
	server.combatant_of(3).take_damage(Constants.PLAYER_MAX_HEALTH)
	assert_false(server.request_cast(2, ARROW, 3), "a corpse is not a target")


func test_request_spam_is_capped() -> void:
	await _duel()
	# The state machine already denies casts during recovery, but nothing stops a
	# modified client asking at wire speed, and every request costs a raycast.
	var accepted := 0
	for _attempt in 200:
		if server.request_cast(2, ARROW, 3):
			accepted += 1
	assert_true(
		accepted <= Constants.MAX_CAST_REQUESTS_PER_SECOND,
		"a peer got %d requests through in one second" % accepted
	)


# ── Resolution ────────────────────────────────────────────────────────────────────


func test_a_clear_shot_lands_on_the_named_target() -> void:
	await _duel()
	assert_true(server.request_cast(2, ARROW, 3), "the lane is open")
	await _run(1.1)

	assert_true(
		server.combatant_of(3).health < Constants.PLAYER_MAX_HEALTH, "the target was hit"
	)
	assert_eq(resolutions.size(), 1, "exactly one resolution was announced")
	assert_eq(resolutions[0]["caster"], 2, "announced against the sender")
	assert_eq(resolutions[0]["target"], 3, "and the target they named")
	assert_true(resolutions[0]["hit"], "with a clear shot it connected")


func test_a_cast_is_always_charged_to_the_peer_that_sent_it() -> void:
	# There is no "who I am" field anywhere in the request — the caster comes from the
	# transport's own idea of the sender — so this is what forging one would have to
	# achieve, and cannot.
	await _duel()
	server.request_cast(2, ARROW, 3)
	await _run(1.1)

	assert_almost_eq(
		server.combatant_of(2).health,
		Constants.PLAYER_MAX_HEALTH,
		"the caster never damages themselves"
	)
	assert_true(server.combatant_of(3).health < Constants.PLAYER_MAX_HEALTH, "the target did")


func test_a_target_who_leaves_mid_cast_is_simply_not_there() -> void:
	await _duel()
	server.request_cast(2, FLAMESTRIKE, 3)
	await _run(0.5)
	server.remove_player(3)
	await _run(2.2)

	assert_eq(resolutions.size(), 0, "a spell aimed at nobody announces nothing")
	assert_eq(
		server.combatant_of(2).entity_state.current_state,
		EntityState.State.IDLE,
		"and the caster is left idle, not stuck mid-cast"
	)


func test_a_shot_into_cover_is_refused_before_it_starts() -> void:
	await _duel()
	# Behind the north tent, which spans x ∈ [-100, 100] at y ≈ -140.
	_place(3, Vector2(0.0, -300.0))
	_place(2, Vector2(0.0, 300.0))
	await get_tree().physics_frame

	assert_false(server.request_cast(2, ARROW, 3), "there is no line to them")
	assert_eq(
		server.combatant_of(2).entity_state.current_state,
		EntityState.State.IDLE,
		"a refusal costs nothing — not even recovery"
	)
