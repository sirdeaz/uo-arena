extends TestCase

## Encode a real combatant, decode it into a fresh one, and check the client would draw
## the same thing. The list of what is asserted here is not arbitrary — it is exactly
## the set of fields `Fighter._draw`, `CastBarUI._draw` and the HUD read every frame.
## Anything the client draws and this test does not cover is a field that can silently
## stop crossing the wire.

var source: Combatant
var mirror: Combatant


func before_each() -> void:
	source = Combatant.new()
	add_child(source)
	mirror = Combatant.new()
	add_child(mirror)


func after_each() -> void:
	source.queue_free()
	mirror.queue_free()


func _round_trip() -> bool:
	return NetProtocol.apply_record(NetProtocol.encode_combatant(7, source), mirror)


# ── What the client draws ─────────────────────────────────────────────────────────


func test_position_and_health_survive_the_trip() -> void:
	source.position = Vector2(-123.0, 45.0)
	source.take_damage(30.0)
	assert_true(_round_trip(), "a well-formed record should apply")
	assert_eq(mirror.position, Vector2(-123.0, 45.0), "position is drawn every frame")
	assert_almost_eq(mirror.health, 70.0, "the health bar reads this")


func test_the_peer_id_is_readable_without_decoding_the_rest() -> void:
	assert_eq(
		NetProtocol.peer_of(NetProtocol.encode_combatant(7, source)),
		7,
		"the client routes a record by peer before applying it"
	)


func test_status_rings_survive_as_booleans() -> void:
	source.apply_poison(8.0, 3.0)
	source.apply_paralyze(4.0)
	assert_true(_round_trip(), "a well-formed record should apply")
	assert_true(mirror.is_paralyzed(), "the paralyze ring should be lit")
	assert_true(mirror.poison_seconds_remaining > 0.0, "the poison ring should be lit")


func test_a_clean_combatant_carries_no_status() -> void:
	assert_true(_round_trip(), "a well-formed record should apply")
	assert_false(mirror.is_paralyzed(), "nothing should be lit")
	assert_eq(mirror.poison_seconds_remaining, 0.0, "nothing should be lit")


func test_a_mirror_never_carries_poison_damage() -> void:
	# If it did, and anything ever ticked the mirror, it would invent damage the server
	# never dealt — and every phantom tick would interrupt a cast too.
	source.apply_poison(8.0, 3.0)
	assert_true(_round_trip(), "a well-formed record should apply")
	assert_eq(mirror.poison_damage_per_tick, 0.0, "a mirror deals no damage of its own")


func test_a_cast_in_progress_survives_the_trip() -> void:
	source.entity_state.try_start_cast(SpellBook.by_name("flamestrike"))
	source.entity_state.tick(1.1)
	assert_true(_round_trip(), "a well-formed record should apply")

	var state := mirror.entity_state
	assert_eq(state.current_state, EntityState.State.CASTING, "the aura reads this")
	assert_eq(state.current_spell, SpellBook.by_name("flamestrike"), "the mantra reads this")
	assert_almost_eq(state.cast_time_elapsed, 1.1, "the cast bar fill reads this")


func test_recovery_survives_the_trip() -> void:
	source.entity_state.try_start_cast(SpellBook.by_name("magic_arrow"))
	source.entity_state.try_start_cast(SpellBook.by_name("poison"))
	source.entity_state.tick(0.1)
	assert_true(_round_trip(), "a well-formed record should apply")

	var state := mirror.entity_state
	assert_eq(state.current_state, EntityState.State.RECOVERING, "the embers read this")
	assert_almost_eq(state.recovery_time_elapsed, 0.1, "the recovery bar reads this")


func test_an_idle_caster_round_trips_through_no_spell() -> void:
	# Idle encodes spell id -1, and the cast bar path has to survive that decoding to
	# null rather than blowing up on a missing resource.
	assert_true(_round_trip(), "a well-formed record should apply")
	assert_eq(mirror.entity_state.current_state, EntityState.State.IDLE, "still idle")
	assert_eq(mirror.entity_state.current_spell, null, "idle carries no spell")


# ── Malformed input ───────────────────────────────────────────────────────────────


func test_a_truncated_record_is_refused() -> void:
	assert_false(
		NetProtocol.apply_record([1, Vector2.ZERO], mirror),
		"a short record must be dropped, not half-applied"
	)


func test_a_casting_record_with_no_spell_reads_as_idle() -> void:
	# A malformed snapshot must not put a null spell in front of the drawing code.
	var record := NetProtocol.encode_combatant(7, source)
	record[NetProtocol.Slot.CAST_STATE] = EntityState.State.CASTING
	record[NetProtocol.Slot.SPELL] = -1
	assert_true(NetProtocol.apply_record(record, mirror), "the record is still the right size")
	assert_eq(
		mirror.entity_state.current_state,
		EntityState.State.IDLE,
		"casting nothing is not casting"
	)
