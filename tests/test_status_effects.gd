extends TestCase

## Poison and paralyze burn down on a server-driven tick. `tick_status` takes an
## explicit delta rather than relying on `_process`, so these tests can advance eight
## seconds of poison instantly instead of sleeping through it.

var combatant: Combatant


func before_each() -> void:
	combatant = Combatant.new()
	add_child(combatant)


func after_each() -> void:
	combatant.queue_free()


func test_poison_deals_no_damage_before_a_full_tick_elapses() -> void:
	combatant.apply_poison(8.0, 3.0)
	combatant.tick_status(0.5)
	assert_almost_eq(combatant.health, 100.0, "half a second in, poison hasn't ticked")


func test_poison_deals_its_damage_on_each_full_second() -> void:
	combatant.apply_poison(8.0, 3.0)
	combatant.tick_status(0.5)
	combatant.tick_status(0.5)
	assert_almost_eq(combatant.health, 97.0, "one full second should cost 3 health")


func test_poison_ticks_accumulate_over_several_seconds() -> void:
	combatant.apply_poison(8.0, 3.0)
	combatant.tick_status(3.0)
	assert_almost_eq(combatant.health, 91.0, "three seconds of poison is 9 damage")


func test_poison_expires_after_its_duration() -> void:
	combatant.apply_poison(8.0, 3.0)
	combatant.tick_status(8.0)
	assert_almost_eq(combatant.poison_seconds_remaining, 0.0, "poison should run out")


func test_expired_poison_deals_no_further_damage() -> void:
	combatant.apply_poison(8.0, 3.0)
	combatant.tick_status(8.0)
	var health_when_poison_ended := combatant.health
	combatant.tick_status(5.0)
	assert_almost_eq(
		combatant.health, health_when_poison_ended, "expired poison must stop hurting"
	)


func test_poison_does_not_tick_past_its_duration() -> void:
	combatant.apply_poison(2.0, 3.0)
	combatant.tick_status(10.0)
	assert_almost_eq(combatant.health, 94.0, "2s of poison is 6 damage, not 30")


func test_poison_tick_interrupts_an_in_progress_cast() -> void:
	combatant.entity_state.try_start_cast(load("res://common/spells/flamestrike.tres"))
	combatant.apply_poison(8.0, 3.0)
	combatant.tick_status(1.0)
	assert_eq(
		combatant.entity_state.current_state,
		EntityState.State.INTERRUPTED,
		"a poison tick is damage, so it should break a cast"
	)


func test_poison_between_ticks_does_not_interrupt() -> void:
	combatant.entity_state.try_start_cast(load("res://common/spells/flamestrike.tres"))
	combatant.apply_poison(8.0, 3.0)
	combatant.tick_status(0.5)
	assert_eq(
		combatant.entity_state.current_state,
		EntityState.State.CASTING,
		"being poisoned shouldn't block casting between ticks"
	)


func test_paralyze_expires_after_its_duration() -> void:
	combatant.apply_paralyze(4.0)
	combatant.tick_status(4.0)
	assert_false(combatant.is_paralyzed(), "paralyze should wear off")


func test_paralyze_holds_for_its_full_duration() -> void:
	combatant.apply_paralyze(4.0)
	combatant.tick_status(3.9)
	assert_true(combatant.is_paralyzed(), "paralyze shouldn't end early")


# ── Cure ─────────────────────────────────────────────────────────────────────────
# Poison is the one effect that can be answered rather than only waited out.


func test_cure_ends_the_poison_outright() -> void:
	combatant.apply_poison(8.0, 3.0)
	combatant.cure_poison()
	assert_almost_eq(
		combatant.poison_seconds_remaining, 0.0, "cure clears the whole timer, not part of it"
	)
	combatant.tick_status(5.0)
	assert_almost_eq(combatant.health, 100.0, "and a cured combatant takes no further ticks")


func test_curing_an_unpoisoned_combatant_is_a_harmless_no_op() -> void:
	combatant.cure_poison()
	combatant.tick_status(1.0)
	assert_almost_eq(combatant.health, 100.0, "curing nothing costs nothing")


func test_a_poison_landing_after_a_cure_owes_a_fresh_second() -> void:
	# Part-way to the first tick, then cured, then re-poisoned.
	combatant.apply_poison(8.0, 3.0)
	combatant.tick_status(0.6)
	combatant.cure_poison()
	combatant.apply_poison(8.0, 3.0)
	combatant.tick_status(0.6)
	assert_almost_eq(
		combatant.health, 100.0,
		"cure resets the sub-tick accumulator, so 0.6s + 0.6s is not a tick"
	)


func test_a_poison_tick_interrupts_a_cure_in_progress() -> void:
	# Cure has no special immunity: it is a cast, and a tick that lands before it
	# completes breaks it like any other. Fitting one in means starting it in the gap
	# right after a tick.
	combatant.apply_poison(8.0, 3.0)
	combatant.entity_state.try_start_cast(load("res://common/spells/cure.tres"))
	combatant.tick_status(1.0)
	assert_eq(
		combatant.entity_state.current_state,
		EntityState.State.INTERRUPTED,
		"a poison tick mid-cure interrupts it"
	)
