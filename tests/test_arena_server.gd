extends TestCase

## Everything a client can ask the server to do, including the things a modified client
## would ask. Runs against a real `ArenaServer` with real physics and no socket — the
## simulation never touches `MultiplayerAPI`, which is precisely what makes this
## testable at all.

const ARROW := 0
const FLAMESTRIKE := 3
const CURE := 5

var server: ArenaServer
var resolutions: Array = []


func before_each() -> void:
	server = preload("res://server/arena_server.tscn").instantiate()
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


# ── Input buffering: bounded catch-up, since #139 ───────────────────────────────────
#
# #132: `set_input` used to write straight into `player.input`, so however many
# `submit_input` packets a burst of ordinary jitter delivered between two physics
# steps, only the last one ever actually got simulated. #134 fixed that with an
# unbounded-feeling queue (bounded only by `INPUT_TIMEOUT_SECONDS`, 30 ticks) and was
# reverted (#137) after a live test showed the backlog routinely growing that large,
# turning into a chronic half-second lag — worse than the bug it fixed. These pin the
# narrower fix: a small cluster still gets each entry its own tick, in order, but a
# burst bigger than `MAX_QUEUED_INPUTS` can never make the server fall behind by more
# than that many ticks, however large the burst actually was.


func test_a_burst_of_input_is_drained_one_tick_at_a_time_not_collapsed() -> void:
	server.add_player(2)
	_place(2, Vector2.ZERO)
	# Two packets landing before this player's next physics step at all — the exact
	# jitter-bunching #132 diagnosed, well within the bounded cap.
	server.set_input(2, Vector2.RIGHT, 0)
	server.set_input(2, Vector2.UP, 1)

	server.step(1.0 / 60.0)
	var after_first := server.combatant_of(2).position
	assert_true(after_first.x > 0.0, "the oldest queued direction must still get its own tick")
	assert_almost_eq(
		after_first.y, 0.0, "not blended with or skipped in favour of the newer arrival", 0.01
	)

	server.step(1.0 / 60.0)
	var after_second := server.combatant_of(2).position
	assert_true(
		after_second.y < after_first.y,
		"the newer queued direction gets its own following tick too, not lost"
	)


func test_the_ack_reflects_the_entry_actually_stepped_not_the_latest_arrival() -> void:
	server.add_player(2)
	_place(2, Vector2.ZERO)
	server.set_input(2, Vector2.RIGHT, 5)
	server.set_input(2, Vector2.UP, 6)

	server.step(1.0 / 60.0)
	var record: Array = server.build_snapshot()[0]
	assert_eq(
		NetProtocol.input_ack_of(record), 5,
		"only sequence 5 has actually been simulated so far, even though 6 already arrived"
	)


func test_a_burst_larger_than_the_cap_only_keeps_the_newest_entries() -> void:
	server.add_player(2)
	_place(2, Vector2.ZERO)
	# Far more than MAX_QUEUED_INPUTS packets landing before this player's next physics
	# step at all — #134's own failure mode. A burst this large must never be queued in
	# full and patiently drained; the oldest entries have to already be gone.
	var burst_size := 20
	for sequence in burst_size:
		server.set_input(2, Vector2.RIGHT, sequence)

	server.step(1.0 / 60.0)
	var record: Array = server.build_snapshot()[0]
	assert_eq(
		NetProtocol.input_ack_of(record),
		burst_size - ArenaServer.MAX_QUEUED_INPUTS,
		"only the newest MAX_QUEUED_INPUTS entries of an oversized burst survive to be stepped"
	)


func test_a_burst_larger_than_the_cap_still_catches_up_within_the_cap_worth_of_ticks() -> void:
	server.add_player(2)
	_place(2, Vector2.ZERO)
	var burst_size := 20
	for sequence in burst_size:
		server.set_input(2, Vector2.RIGHT, sequence)

	for _tick in ArenaServer.MAX_QUEUED_INPUTS:
		server.step(1.0 / 60.0)

	var record: Array = server.build_snapshot()[0]
	assert_eq(
		NetProtocol.input_ack_of(record),
		burst_size - 1,
		"draining the bounded backlog must catch all the way up to the latest arrival " +
		"within MAX_QUEUED_INPUTS ticks, however large the burst behind it actually was"
	)


func test_a_stale_backlog_does_not_replay_ahead_of_input_sent_after_a_long_silence() -> void:
	server.add_player(2)
	_place(2, Vector2.ZERO)
	server.set_input(2, Vector2.RIGHT, 0)
	server.set_input(2, Vector2.RIGHT, 1)
	server.set_input(2, Vector2.RIGHT, 2)

	# A single gap wide enough that the connection is given up on entirely — the three
	# RIGHT entries above are stale, not something worth honouring once play resumes.
	server.step(Constants.INPUT_TIMEOUT_SECONDS + 0.1)

	# Play resumes with a fresh direction. Without discarding the stale backlog, this
	# would queue behind the three already-stale entries and only take effect three
	# ticks later than it should.
	server.set_input(2, Vector2.UP, 3)
	server.step(1.0 / 60.0)

	var record: Array = server.build_snapshot()[0]
	assert_eq(
		NetProtocol.input_ack_of(record), 3,
		"input sent after a long silence must be applied on the very next tick, not queued behind a stale backlog"
	)


func test_trim_input_queue_keeps_the_newest_entries() -> void:
	var queue: Array[Dictionary] = [
		{"sequence": 0, "direction": Vector2.ZERO},
		{"sequence": 1, "direction": Vector2.ZERO},
		{"sequence": 2, "direction": Vector2.ZERO},
	]
	var trimmed := ArenaServer.trim_input_queue(queue, 2)
	assert_eq(trimmed.size(), 2, "a long backlog must not grow without bound")
	assert_eq(trimmed[0]["sequence"], 1, "the oldest entry is what gets dropped")
	assert_eq(trimmed[1]["sequence"], 2, "the newest entries survive the trim")


func test_trim_input_queue_under_the_bound_changes_nothing() -> void:
	var queue: Array[Dictionary] = [{"sequence": 0, "direction": Vector2.ZERO}]
	assert_eq(
		ArenaServer.trim_input_queue(queue, 10).size(), 1,
		"a queue already under the bound must not lose anything"
	)


# ── Cast requests a modified client could send ────────────────────────────────────


func test_a_stranger_cannot_cast() -> void:
	await _duel()
	assert_false(
		server.request_cast(404, ARROW, 3), "a peer not in the roster casts nothing"
	)


func test_nobody_can_cast_at_themselves() -> void:
	await _duel()
	assert_false(server.request_cast(2, ARROW, 2), "self-targeting is refused")


func test_a_self_cast_spell_is_the_exception_and_may_target_the_caster() -> void:
	await _duel()
	assert_true(
		server.request_cast(2, CURE, 2), "cure is cast on yourself, so self-targeting it is allowed"
	)


func test_a_self_cast_spell_lands_on_the_caster_whoever_was_named() -> void:
	await _duel()
	server.combatant_of(2).apply_poison(8.0, 3.0)
	server.combatant_of(3).apply_poison(8.0, 3.0)
	# Aimed at 3 on purpose: a self-cast spell must ignore that and resolve on 2.
	assert_true(server.request_cast(2, CURE, 3), "cure starts even when aimed at someone else")
	await _run(Constants.GLOBAL_CAST_RECOVERY_SECONDS + 1.0)
	assert_almost_eq(
		server.combatant_of(2).poison_seconds_remaining, 0.0, "the caster's own poison is lifted"
	)
	assert_true(
		server.combatant_of(3).poison_seconds_remaining > 0.0,
		"the named target is untouched — cure never travelled to them"
	)


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


func test_the_request_budget_rolls_over_instead_of_running_out_for_good() -> void:
	# #127: the budget is meant to be a rolling one-second window, not a lifetime cap.
	# No `server.step()` happened between requests above, so that test alone cannot
	# catch a missing rollover tick — this one spends the whole budget, lets a real
	# second of simulated time pass, and checks the next request still goes through.
	await _duel()
	for _attempt in Constants.MAX_CAST_REQUESTS_PER_SECOND:
		server.request_cast(2, ARROW, 3)
	assert_false(
		server.request_cast(2, ARROW, 3),
		"the budget should already be spent for this window"
	)

	await _run(1.1)

	assert_true(
		server.request_cast(2, ARROW, 3),
		"a full second later the budget must have rolled over, not stayed spent for the rest of the session"
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
	await _run(3.3)

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
