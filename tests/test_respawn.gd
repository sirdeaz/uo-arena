extends TestCase

## Dying and standing back up. The arena is persistent — there are no rounds yet — so a
## respawn has to leave nothing behind: not the poison that killed you, not the paralyze
## you were under, and not the spell you had queued behind a fizzle.

var server: ArenaServer


func before_each() -> void:
	server = ArenaServer.new()
	add_child(server)


func after_each() -> void:
	server.queue_free()


func _place(peer_id: int, at: Vector2) -> void:
	server.body_of(peer_id).global_position = at
	server.combatant_of(peer_id).position = at


func _duel() -> void:
	server.add_player(2)
	server.add_player(3)
	_place(2, Vector2(-500.0, 0.0))
	_place(3, Vector2(500.0, 0.0))
	await get_tree().physics_frame


func _run(seconds: float) -> void:
	var step := 1.0 / 60.0
	var elapsed := 0.0
	while elapsed < seconds:
		server.step(step)
		elapsed += step


# ── Dying ─────────────────────────────────────────────────────────────────────────


func test_dying_is_announced_once_however_long_the_poison_runs() -> void:
	# Poison keeps arriving after the killing tick. Announcing death on each one would
	# schedule a fresh respawn every second until the poison ran out.
	var combatant := Combatant.new()
	add_child(combatant)
	# Counted in an array rather than an int: a lambda captures locals by value, so an
	# incremented int would stay zero out here.
	var deaths: Array = []
	combatant.died.connect(func() -> void: deaths.append(true))

	combatant.take_damage(Constants.PLAYER_MAX_HEALTH - 1.0)
	combatant.apply_poison(8.0, 3.0)
	combatant.tick_status(5.0)
	assert_eq(deaths.size(), 1, "a player dies once")

	combatant.tick_status(3.0)
	assert_eq(deaths.size(), 1, "and does not keep dying")
	combatant.queue_free()


func test_a_corpse_does_not_finish_the_spell_it_had_queued() -> void:
	var combatant := Combatant.new()
	add_child(combatant)
	combatant.entity_state.try_start_cast(SpellBook.by_name("flamestrike"))
	# Recasting queues the lightning behind a recovery.
	combatant.entity_state.try_start_cast(SpellBook.by_name("lightning"))
	combatant.take_damage(Constants.PLAYER_MAX_HEALTH)

	combatant.tick(5.0)
	assert_eq(
		combatant.entity_state.current_state,
		EntityState.State.RECOVERING,
		"time stops for the dead rather than carrying the chain on"
	)
	combatant.queue_free()


# ── Standing back up ──────────────────────────────────────────────────────────────


func test_a_corpse_stays_down_for_the_full_count() -> void:
	await _duel()
	server.combatant_of(3).take_damage(Constants.PLAYER_MAX_HEALTH)
	await _run(Constants.RESPAWN_SECONDS - 0.2)
	assert_false(server.combatant_of(3).is_alive(), "still down a moment before the count")


func test_respawning_returns_you_whole_and_empty_handed() -> void:
	await _duel()
	var victim := server.combatant_of(3)
	victim.apply_poison(8.0, 3.0)
	victim.apply_paralyze(4.0)
	victim.entity_state.try_start_cast(SpellBook.by_name("flamestrike"))
	victim.entity_state.try_start_cast(SpellBook.by_name("lightning"))
	victim.take_damage(Constants.PLAYER_MAX_HEALTH)

	await _run(Constants.RESPAWN_SECONDS + 0.2)

	assert_almost_eq(victim.health, Constants.PLAYER_MAX_HEALTH, "back to full health")
	assert_eq(victim.poison_seconds_remaining, 0.0, "poison does not follow you back")
	assert_false(victim.is_paralyzed(), "and neither does paralyze")
	assert_eq(
		victim.entity_state.current_state, EntityState.State.IDLE, "standing up idle"
	)
	assert_eq(
		victim.entity_state.pending_spell,
		null,
		"and not already casting whatever was queued when you died"
	)


func test_you_come_back_on_a_spawn_point() -> void:
	await _duel()
	server.combatant_of(3).take_damage(Constants.PLAYER_MAX_HEALTH)
	await _run(Constants.RESPAWN_SECONDS + 0.2)

	assert_true(
		server.map.get_spawn_positions().has(server.combatant_of(3).position),
		"a respawn puts you on a spawn marker, not where you fell"
	)


func test_you_do_not_come_back_next_to_your_killer() -> void:
	await _duel()
	# The killer stands on the spawn the victim last used, so coming back "somewhere
	# else" has to mean somewhere genuinely far, not merely a different marker.
	_place(2, Vector2(500.0, 0.0))
	server.combatant_of(3).take_damage(Constants.PLAYER_MAX_HEALTH)
	await _run(Constants.RESPAWN_SECONDS + 0.2)

	var apart := server.combatant_of(3).position.distance_to(Vector2(500.0, 0.0))
	assert_true(
		apart > Constants.PLAYER_MOVE_SPEED,
		"respawned %.0f px from the killer — under a second's walk" % apart
	)


func test_the_body_moves_with_the_respawn() -> void:
	# The collision body and the combatant have to agree, or the corpse's physics stays
	# where it fell and blocks nothing while the player is drawn elsewhere.
	await _duel()
	server.combatant_of(3).take_damage(Constants.PLAYER_MAX_HEALTH)
	await _run(Constants.RESPAWN_SECONDS + 0.2)

	assert_eq(
		server.body_of(3).global_position,
		server.combatant_of(3).position,
		"body and combatant must respawn together"
	)
