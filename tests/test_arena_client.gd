extends TestCase

## The client fed by hand: rosters and snapshots go in, fighters and drawable state come
## out. No socket and no server — `ArenaClient` never touches `MultiplayerAPI`, so it can
## be driven directly with exactly the records the wire would have carried.

const LOCAL := 2
const OTHER := 3

## The client is an authored scene now — camera, HUD and the view layers come from
## `arena_stage.tscn`. `network_manager.gd` instances it the same way in a real match.
const CLIENT_SCENE := preload("res://client/scenes/arena_client.tscn")

var client: ArenaClient
var source: Combatant


func before_each() -> void:
	client = CLIENT_SCENE.instantiate()
	client.local_peer_id = LOCAL
	add_child(client)

	# Stands in for the server's authoritative combatant when building records.
	source = Combatant.new()
	add_child(source)


func after_each() -> void:
	client.queue_free()
	source.queue_free()


func _roster(peer_ids: Array, nicknames: Array = []) -> void:
	var ids := PackedInt32Array(peer_ids)
	var slots := PackedInt32Array()
	for index in peer_ids.size():
		slots.append(index)
	client.apply_roster(ids, slots, PackedStringArray(nicknames))


func _fighter(peer_id: int) -> Fighter:
	return client.fighter_of(peer_id)


# ── Roster ────────────────────────────────────────────────────────────────────────


func test_a_roster_builds_a_fighter_for_everyone() -> void:
	_roster([LOCAL, OTHER])
	assert_true(_fighter(LOCAL) != null, "you should be in the arena")
	assert_true(_fighter(OTHER) != null, "and so should the other player")


func test_only_your_own_fighter_reads_your_input() -> void:
	_roster([LOCAL, OTHER])
	assert_true(_fighter(LOCAL).player_controlled, "you steer yourself")
	assert_false(_fighter(OTHER).player_controlled, "you do not steer anyone else")


func test_every_fighter_is_server_driven() -> void:
	# If one were not, it would run the real rules locally and start ticking poison of
	# its own invention.
	_roster([LOCAL, OTHER])
	assert_true(_fighter(LOCAL).server_driven, "your own body is still the server's")
	assert_true(_fighter(OTHER).server_driven, "and so is everyone else's")


func test_a_player_leaving_takes_their_fighter_with_them() -> void:
	_roster([LOCAL, OTHER])
	_roster([LOCAL])
	assert_eq(_fighter(OTHER), null, "a player who left should stop being drawn")
	assert_true(_fighter(LOCAL) != null, "and you should still be here")


func test_you_are_blue_and_nobody_else_is() -> void:
	# The first read in a ten-player brawl is "is that me", and it should cost nothing.
	_roster([LOCAL, OTHER, 4])
	assert_eq(_fighter(LOCAL).body_color, Palette.PLAYER, "you are always the blue one")
	assert_false(
		_fighter(OTHER).body_color == Palette.PLAYER, "an opponent must not wear your colour"
	)
	assert_false(
		_fighter(OTHER).body_color == _fighter(4).body_color,
		"two opponents in different slots should be told apart"
	)


func test_a_repeated_roster_does_not_rebuild_your_fighter() -> void:
	# Rebuilding it would silently detach the cast bar, which is bound once for the life
	# of the connection.
	_roster([LOCAL, OTHER])
	var before := _fighter(LOCAL)
	_roster([LOCAL, OTHER, 4])
	assert_eq(_fighter(LOCAL), before, "the same fighter should survive a roster resend")


# ── Steering to the server ────────────────────────────────────────────────────────


func test_input_is_sent_every_tick_even_while_unchanged() -> void:
	# #118: a held keyboard direction is bit-identical tick to tick, so a send gated on
	# "did it change" leans entirely on a sparse heartbeat over an unreliable channel —
	# one dropped packet then costs a full heartbeat interval of stale server input.
	# Sending every tick regardless is what gives a lossy channel another chance next
	# tick, the way continuously-recomputed mouse steering already got for free.
	_roster([LOCAL])
	var sends: Array = []
	client.input_changed.connect(
		func(direction: Vector2, sequence: int) -> void: sends.append([direction, sequence])
	)

	for _tick in 5:
		client._send_input()

	assert_eq(sends.size(), 5, "an unchanging direction must still be resent every tick")


func test_no_local_fighter_sends_nothing() -> void:
	# Before your own roster entry lands there is nothing to steer — this must not
	# crash reaching for a fighter that is not there yet.
	var sends: Array = []
	client.input_changed.connect(func(_direction: Vector2, _sequence: int) -> void: sends.append(1))
	client._send_input()
	assert_eq(sends.size(), 0, "no fighter means nothing to say")


# ── Snapshots ─────────────────────────────────────────────────────────────────────


func test_a_snapshot_moves_and_wounds_the_right_fighter() -> void:
	_roster([LOCAL, OTHER])
	source.position = Vector2(140.0, -60.0)
	source.take_damage(25.0)
	client.apply_snapshot([NetProtocol.encode_combatant(OTHER, source)])

	var fighter := _fighter(OTHER)
	assert_eq(fighter.server_position, Vector2(140.0, -60.0), "the server said go here")
	assert_almost_eq(fighter.combatant.health, 75.0, "and that they are hurt")
	assert_almost_eq(
		_fighter(LOCAL).combatant.health,
		Constants.PLAYER_MAX_HEALTH,
		"without touching anybody else"
	)


func test_a_snapshot_for_a_stranger_is_ignored() -> void:
	# Records can outrun the roster that explains them. Dropping one is correct;
	# crashing on it is not.
	_roster([LOCAL])
	client.apply_snapshot([NetProtocol.encode_combatant(404, source)])
	assert_eq(_fighter(404), null, "no fighter should be conjured from a lone record")


func test_a_malformed_record_is_dropped() -> void:
	_roster([LOCAL, OTHER])
	client.apply_snapshot([[OTHER, Vector2.ZERO]])
	assert_almost_eq(
		_fighter(OTHER).combatant.health,
		Constants.PLAYER_MAX_HEALTH,
		"a truncated record must not half-apply"
	)


func test_a_cast_in_a_snapshot_is_drawn() -> void:
	_roster([LOCAL, OTHER])
	source.entity_state.try_start_cast(SpellBook.by_name("flamestrike"))
	source.entity_state.tick(0.8)
	client.apply_snapshot([NetProtocol.encode_combatant(OTHER, source)])

	var state := _fighter(OTHER).combatant.entity_state
	assert_eq(state.current_state, EntityState.State.CASTING, "the aura needs this")
	assert_eq(state.current_spell.mantra, "Kal Vas Flam", "and the mantra needs this")


# ── Death overlay (#136) ────────────────────────────────────────────────────────


func test_dying_shows_the_overlay_with_the_servers_own_countdown() -> void:
	_roster([LOCAL, OTHER])
	source.take_damage(Constants.PLAYER_MAX_HEALTH)
	client.apply_snapshot([NetProtocol.encode_combatant(LOCAL, source, 0, 2.5)])
	client._update_hud()
	assert_true(client.hud.death_overlay.visible, "dying should show the overlay")


func test_reviving_hides_the_overlay() -> void:
	_roster([LOCAL, OTHER])
	source.take_damage(Constants.PLAYER_MAX_HEALTH)
	client.apply_snapshot([NetProtocol.encode_combatant(LOCAL, source, 0, 2.5)])
	client._update_hud()

	source.revive(Vector2.ZERO)
	client.apply_snapshot([NetProtocol.encode_combatant(LOCAL, source)])
	client._update_hud()
	assert_false(client.hud.death_overlay.visible, "reviving should hide the overlay")


func test_someone_elses_death_does_not_show_your_overlay() -> void:
	_roster([LOCAL, OTHER])
	source.take_damage(Constants.PLAYER_MAX_HEALTH)
	client.apply_snapshot([NetProtocol.encode_combatant(OTHER, source, 0, 2.5)])
	client._update_hud()
	assert_false(
		client.hud.death_overlay.visible, "an opponent dying is not your death"
	)


# ── Snapshot delivery cadence (#132) ────────────────────────────────────────────────
#
# `snapshot_gap_is_notable` is the decision behind `_log_snapshot_gap`'s console line,
# pulled out static the same way `Fighter.prediction_error` was for reconciliation
# (#133) — this is the other half of that same "measure first" question: whether
# snapshots themselves arrive unevenly, independent of whether a given gap goes on to
# need a correction.


func test_a_gap_at_the_nominal_interval_is_not_notable() -> void:
	assert_false(
		ArenaClient.snapshot_gap_is_notable(1.0 / Constants.SNAPSHOT_HZ),
		"an evenly-arriving connection must print nothing at all"
	)


func test_a_gap_just_past_the_threshold_is_notable() -> void:
	assert_true(
		ArenaClient.snapshot_gap_is_notable(ArenaClient.SNAPSHOT_GAP_NOTABLE_SECONDS + 0.001),
		"a genuinely late or bursty arrival must be worth a line"
	)


func test_a_gap_just_under_the_threshold_is_not_notable() -> void:
	assert_false(
		ArenaClient.snapshot_gap_is_notable(ArenaClient.SNAPSHOT_GAP_NOTABLE_SECONDS - 0.001),
		"the threshold itself must not be flagged as though it were already exceeded"
	)


# ── Announced events ──────────────────────────────────────────────────────────────


func test_a_cast_event_reaches_the_fighter_that_draws_it() -> void:
	_roster([LOCAL, OTHER])
	var interrupted: Array = []
	_fighter(OTHER).combatant.entity_state.cast_interrupted.connect(
		func(spell: SpellData) -> void: interrupted.append(spell)
	)
	client.apply_cast_event(OTHER, EntityState.Event.INTERRUPTED, 0)
	assert_eq(interrupted.size(), 1, "the interrupt burst is driven by this signal")


func test_an_event_for_a_stranger_is_ignored() -> void:
	_roster([LOCAL])
	client.apply_cast_event(404, EntityState.Event.COMPLETED, 0)
	assert_eq(client.player_count(), 1, "an event for nobody conjures nobody")


func test_a_blocked_shot_is_reported_only_to_the_caster() -> void:
	# The server sends a blocked resolution to the caster alone, so one arriving here is
	# always news about your own shot — and it draws no bolt, as in UO.
	_roster([LOCAL, OTHER])
	client.apply_spell_resolved(LOCAL, OTHER, 0, false)
	assert_true(
		client.last_event().contains("blocked"), "you should be told your shot was blocked"
	)


func test_being_hit_is_reported_from_your_side_of_it() -> void:
	_roster([LOCAL, OTHER])
	client.apply_spell_resolved(OTHER, LOCAL, 0, true)
	assert_true(client.last_event().contains("hit you"), "you should be told you were hit")


func test_someone_elses_exchange_is_not_narrated_at_you() -> void:
	_roster([LOCAL, OTHER, 4])
	client.apply_spell_resolved(OTHER, 4, 0, true)
	assert_eq(client.last_event(), "", "two other players fighting is not your news")


func test_an_unknown_spell_in_a_resolution_is_ignored() -> void:
	_roster([LOCAL, OTHER])
	client.apply_spell_resolved(LOCAL, OTHER, 9999, true)
	assert_eq(client.last_event(), "", "a resolution naming no spell says nothing")


# ── Audio ─────────────────────────────────────────────────────────────────────────


## The point of the cues is being able to hear a cast you are not looking at, and in
## multiplayer the cast you are not looking at is somebody else's. Wiring them only into
## the offline harness would leave the real game silent.
func test_every_player_in_the_arena_is_audible() -> void:
	_roster([LOCAL, OTHER])
	for peer_id in [LOCAL, OTHER]:
		var state := _fighter(peer_id).combatant.entity_state
		for signal_name in [
			"cast_started", "cast_completed", "cast_fizzled", "cast_interrupted"
		]:
			assert_true(
				state.get_signal_connection_list(signal_name).size() > 0,
				"peer %d's %s reaches nothing that makes a sound" % [peer_id, signal_name]
			)


func test_a_remote_fizzle_is_heard_as_a_fizzle() -> void:
	# A mirrored caster replays its ending through `emit_remote_event`, which is what
	# lets the same signal wiring serve local and remote players alike.
	_roster([LOCAL, OTHER])
	var heard := []
	_fighter(OTHER).combatant.entity_state.cast_fizzled.connect(
		func(_spell: SpellData, _reason: String) -> void: heard.append("fizzle")
	)
	client.apply_cast_event(OTHER, EntityState.Event.FIZZLED, SpellBook.IDS.find("flamestrike"))
	assert_eq(heard.size(), 1, "an opponent's fizzle should reach the audio wiring")


func test_muting_the_client_silences_it() -> void:
	assert_false(client.audio.is_muted(), "sound is on by default")
	client.audio.set_muted(true)
	assert_false(
		client.audio.play(SpellAudio.Cue.FIZZLE),
		"a muted client should play nothing"
	)
