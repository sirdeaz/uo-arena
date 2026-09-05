extends TestCase

## The client fed by hand: rosters and snapshots go in, fighters and drawable state come
## out. No socket and no server — `ArenaClient` never touches `MultiplayerAPI`, so it can
## be driven directly with exactly the records the wire would have carried.

const LOCAL := 2
const OTHER := 3

var client: ArenaClient
var source: Combatant


func before_each() -> void:
	client = ArenaClient.new()
	client.local_peer_id = LOCAL
	add_child(client)

	# Stands in for the server's authoritative combatant when building records.
	source = Combatant.new()
	add_child(source)


func after_each() -> void:
	client.queue_free()
	source.queue_free()


func _roster(peer_ids: Array) -> void:
	var ids := PackedInt32Array(peer_ids)
	var slots := PackedInt32Array()
	for index in peer_ids.size():
		slots.append(index)
	client.apply_roster(ids, slots)


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
