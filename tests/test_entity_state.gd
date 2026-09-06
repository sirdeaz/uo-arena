extends TestCase

## The cast state machine, including the fizzle-chain feint: recasting inside the
## fizzle window kills the in-progress spell, costs a fixed recovery, then starts the
## spell you chained into. Spamming therefore produces a stream of visible cast-starts
## that never resolve — which is the point, since it baits the opponent.
##
## Timing is driven through `tick(delta)` rather than real frames so recovery windows
## can be stepped exactly.

var state: EntityState

var started_spells: Array[SpellData] = []
var completed_spells: Array[SpellData] = []
var fizzled: Array = []
var interrupted_spells: Array[SpellData] = []


func before_each() -> void:
	state = EntityState.new()
	add_child(state)
	state.cast_started.connect(func(s): started_spells.append(s))
	state.cast_completed.connect(func(s): completed_spells.append(s))
	state.cast_fizzled.connect(func(s, reason): fizzled.append([s, reason]))
	state.cast_interrupted.connect(func(s): interrupted_spells.append(s))


func after_each() -> void:
	state.queue_free()


func _flamestrike() -> SpellData:
	return load("res://common/spells/flamestrike.tres")


func _lightning() -> SpellData:
	return load("res://common/spells/lightning.tres")


# ── baseline ──────────────────────────────────────────────────────────────────

func test_cast_starts_from_idle() -> void:
	assert_true(state.try_start_cast(_flamestrike()), "idle caster should accept a spell")
	assert_eq(state.current_state, EntityState.State.CASTING, "should be casting")


func test_cast_completes_after_its_cast_time() -> void:
	state.try_start_cast(_lightning())
	state.tick(1.75)
	assert_eq(completed_spells.size(), 1, "lightning should complete after 1.75s")
	assert_eq(state.current_state, EntityState.State.IDLE, "and return to idle")


func test_recast_late_in_a_cast_also_fizzles_and_chains() -> void:
	# You may abandon a cast at any point, not only in its first moments.
	state.try_start_cast(_flamestrike())
	state.tick(2.0)  # deep into flamestrike's 2.5s cast
	assert_true(state.try_start_cast(_lightning()), "a late recast is accepted")
	assert_eq(fizzled.size(), 1, "the abandoned spell fizzles")
	assert_eq(fizzled[0][0].spell_name, "Flamestrike", "flamestrike is what dies")
	assert_eq(state.current_state, EntityState.State.RECOVERING, "recovery is still paid")


func test_abandoning_a_cast_costs_the_same_whenever_you_do_it() -> void:
	# Bailing out late must not be cheaper than bailing out early, or the right play
	# would always be to start a long cast and abort it.
	state.try_start_cast(_flamestrike())
	state.tick(2.4)
	state.try_start_cast(_lightning())
	state.tick(Constants.GLOBAL_CAST_RECOVERY_SECONDS - 0.01)
	assert_eq(
		state.current_state,
		EntityState.State.RECOVERING,
		"recovery runs its full length however late the recast was"
	)
	state.tick(0.02)
	assert_eq(state.current_state, EntityState.State.CASTING, "then the chain starts")


# ── the fizzle chain ──────────────────────────────────────────────────────────

func test_recast_inside_the_window_fizzles_the_in_progress_spell() -> void:
	state.try_start_cast(_flamestrike())
	state.tick(0.1)
	state.try_start_cast(_lightning())
	assert_eq(fizzled.size(), 1, "the in-progress spell should fizzle")
	assert_eq(fizzled[0][0].spell_name, "Flamestrike", "flamestrike is the one that dies")
	assert_eq(fizzled[0][1], "recast", "with the recast reason")


func test_recast_inside_the_window_enters_recovery() -> void:
	state.try_start_cast(_flamestrike())
	state.tick(0.1)
	assert_true(state.try_start_cast(_lightning()), "the chained cast is accepted")
	assert_eq(state.current_state, EntityState.State.RECOVERING, "recovery comes first")


func test_chained_spell_has_not_started_during_recovery() -> void:
	state.try_start_cast(_flamestrike())
	state.tick(0.1)
	state.try_start_cast(_lightning())
	state.tick(0.2)  # inside the 0.25s recovery
	assert_eq(state.current_state, EntityState.State.RECOVERING, "still recovering")
	assert_eq(started_spells.size(), 1, "only flamestrike has started so far")


func test_chained_spell_begins_after_recovery_elapses() -> void:
	state.try_start_cast(_flamestrike())
	state.tick(0.1)
	state.try_start_cast(_lightning())
	state.tick(0.25)
	assert_eq(state.current_state, EntityState.State.CASTING, "recovery is over")
	assert_eq(state.current_spell.spell_name, "Lightning", "the chained spell is casting")
	assert_eq(started_spells.size(), 2, "lightning should have emitted cast_started")


func test_chained_spell_casts_for_its_full_time_after_recovery() -> void:
	state.try_start_cast(_flamestrike())
	state.tick(0.1)
	state.try_start_cast(_lightning())
	state.tick(0.25)  # recovery done, lightning starts fresh
	state.tick(1.74)
	assert_true(completed_spells.is_empty(), "lightning shouldn't complete early")
	state.tick(0.01)
	assert_eq(completed_spells.size(), 1, "lightning completes 1.75s after it started")


func test_casting_during_recovery_is_denied() -> void:
	state.try_start_cast(_flamestrike())
	state.tick(0.1)
	state.try_start_cast(_lightning())
	assert_false(state.try_start_cast(_flamestrike()), "no casting during recovery")
	assert_eq(fizzled.size(), 1, "and the denied press shouldn't fizzle anything extra")


func test_spamming_never_completes_a_spell() -> void:
	# The feint: every press restarts the cycle, so nothing ever resolves.
	state.try_start_cast(_flamestrike())
	for i in 5:
		state.tick(0.1)
		state.try_start_cast(_lightning())  # denied while recovering, fizzles while casting
		state.tick(0.25)
	assert_true(completed_spells.is_empty(), "spam-casting should never land a spell")


func test_spamming_late_in_long_casts_still_never_lands() -> void:
	# Now that a late recast is allowed, check the punishment survives at the other
	# extreme: pressing just before each cast would have completed.
	state.try_start_cast(_flamestrike())
	for i in 4:
		state.tick(2.4)
		state.try_start_cast(_flamestrike())
		state.tick(Constants.GLOBAL_CAST_RECOVERY_SECONDS)
	assert_true(completed_spells.is_empty(), "aborting at the last moment lands nothing")


# ── regressions: transient states must not clobber a new cast ─────────────────

func test_new_cast_survives_the_frame_after_an_interrupt() -> void:
	state.try_start_cast(_flamestrike())
	state.interrupt_cast()
	assert_true(state.try_start_cast(_lightning()), "recast after a hit is allowed")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(
		state.current_state,
		EntityState.State.CASTING,
		"the deferred interrupt cleanup must not cancel the new cast"
	)
	assert_eq(state.current_spell.spell_name, "Lightning", "and lightning is still up")


func test_interrupt_returns_to_idle_when_nothing_follows() -> void:
	state.try_start_cast(_flamestrike())
	state.interrupt_cast()
	assert_eq(state.current_state, EntityState.State.INTERRUPTED, "momentarily interrupted")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(state.current_state, EntityState.State.IDLE, "then back to idle")


func test_chained_cast_survives_the_frame_after_recovery() -> void:
	state.try_start_cast(_flamestrike())
	state.tick(0.1)
	state.try_start_cast(_lightning())
	state.tick(0.25)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(
		state.current_state, EntityState.State.CASTING, "chained cast must not be wiped"
	)
