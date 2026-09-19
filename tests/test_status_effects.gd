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


## Long enough to carry eight bites at the current interval — the shape `poison.tres` is
## tuned to. Derived rather than written as a number, so retuning the interval does not
## quietly change what these tests are asserting about.
const EIGHT_BITES := 8 * Combatant.POISON_TICK_SECONDS


func test_poison_deals_no_damage_before_its_first_bite() -> void:
	combatant.apply_poison(EIGHT_BITES, 3.0)
	combatant.tick_status(Combatant.POISON_TICK_SECONDS - 0.1)
	assert_almost_eq(
		combatant.health, 100.0, "poison bites on the interval, it does not drain continuously"
	)


func test_poison_deals_its_damage_on_each_full_interval() -> void:
	combatant.apply_poison(EIGHT_BITES, 3.0)
	# Split across two calls, because the accumulator carrying partial progress between
	# them is what makes this work on a 60Hz server tick at all.
	combatant.tick_status(Combatant.POISON_TICK_SECONDS * 0.5)
	combatant.tick_status(Combatant.POISON_TICK_SECONDS * 0.5)
	assert_almost_eq(combatant.health, 97.0, "one full interval should cost 3 health")


func test_poison_bites_accumulate_over_several_intervals() -> void:
	combatant.apply_poison(EIGHT_BITES, 3.0)
	combatant.tick_status(Combatant.POISON_TICK_SECONDS * 3.0)
	assert_almost_eq(combatant.health, 91.0, "three bites is 9 damage")


## The one that has to be measured rather than reasoned about, and which earned its keep:
## with `poison.tres` set to an exact multiple of the interval, the eighth bite landed
## precisely on the expiry boundary and `tick_status`'s floating-point accumulator lost it
## — seven bites instead of eight, a silent one-eighth nerf nothing else would have caught.
## The duration carries a margin over the last bite for that reason. Advanced in 60Hz
## slices rather than one big delta, because that is where the error accumulates.
func test_the_last_bite_of_the_duration_still_lands() -> void:
	var poison: SpellData = load("res://common/spells/poison.tres")
	combatant.apply_poison(poison.effect_duration_seconds, poison.damage)

	var step := 1.0 / 60.0
	var elapsed := 0.0
	while elapsed < poison.effect_duration_seconds + 1.0:
		combatant.tick_status(step)
		elapsed += step

	var bites := int(floor(poison.effect_duration_seconds / Combatant.POISON_TICK_SECONDS))
	assert_eq(bites, 8, "poison is tuned to land eight bites; if that changed, so did its cost")
	assert_almost_eq(
		combatant.health,
		Constants.PLAYER_MAX_HEALTH - bites * poison.damage,
		"every bite the duration pays for has to land, the last one included — losing it " +
		"to float drift is a one-eighth nerf that nothing else here would catch",
		0.01
	)


func test_poison_expires_after_its_duration() -> void:
	combatant.apply_poison(EIGHT_BITES, 3.0)
	combatant.tick_status(EIGHT_BITES)
	assert_almost_eq(combatant.poison_seconds_remaining, 0.0, "poison should run out")


func test_expired_poison_deals_no_further_damage() -> void:
	combatant.apply_poison(EIGHT_BITES, 3.0)
	combatant.tick_status(EIGHT_BITES)
	var health_when_poison_ended := combatant.health
	combatant.tick_status(EIGHT_BITES)
	assert_almost_eq(
		combatant.health, health_when_poison_ended, "expired poison must stop hurting"
	)


func test_poison_does_not_tick_past_its_duration() -> void:
	# Two bites' worth of duration, then far more time than that. The cap is what stops the
	# accumulator paying out for seconds the poison never had.
	combatant.apply_poison(Combatant.POISON_TICK_SECONDS * 2.0, 3.0)
	combatant.tick_status(Combatant.POISON_TICK_SECONDS * 20.0)
	assert_almost_eq(combatant.health, 94.0, "two bites is 6 damage, however long you wait")


func test_poison_tick_interrupts_an_in_progress_cast() -> void:
	combatant.entity_state.try_start_cast(load("res://common/spells/flamestrike.tres"))
	combatant.apply_poison(EIGHT_BITES, 3.0)
	combatant.tick_status(Combatant.POISON_TICK_SECONDS)
	assert_eq(
		combatant.entity_state.current_state,
		EntityState.State.INTERRUPTED,
		"a poison bite is damage, so it should break a cast"
	)


func test_poison_between_bites_does_not_interrupt() -> void:
	# The gap between bites is now long enough to land a whole cast in, which is the
	# difference this interval makes: poison went from constant denial to a clock you can
	# play around.
	combatant.entity_state.try_start_cast(load("res://common/spells/flamestrike.tres"))
	combatant.apply_poison(EIGHT_BITES, 3.0)
	combatant.tick_status(Combatant.POISON_TICK_SECONDS - 0.1)
	assert_eq(
		combatant.entity_state.current_state,
		EntityState.State.CASTING,
		"being poisoned shouldn't block casting between bites"
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


func test_a_poison_landing_after_a_cure_owes_a_fresh_interval() -> void:
	# Most of the way to the first bite, then cured, then re-poisoned. Two part-intervals
	# either side of a cure must not add up to one.
	var most_of_the_way := Combatant.POISON_TICK_SECONDS * 0.6
	combatant.apply_poison(EIGHT_BITES, 3.0)
	combatant.tick_status(most_of_the_way)
	combatant.cure_poison()
	combatant.apply_poison(EIGHT_BITES, 3.0)
	combatant.tick_status(most_of_the_way)
	assert_almost_eq(
		combatant.health, 100.0,
		"cure resets the part-way accumulator, so 0.6 + 0.6 of an interval is not a bite"
	)


func test_a_poison_tick_interrupts_a_cure_in_progress() -> void:
	# Cure has no special immunity: it is a cast, and a bite that lands before it completes
	# breaks it like any other. The gap between bites is now wide enough to fit a cure in,
	# so this has to run the clock all the way to one to still be testing anything.
	combatant.apply_poison(EIGHT_BITES, 3.0)
	combatant.entity_state.try_start_cast(load("res://common/spells/cure.tres"))
	combatant.tick_status(Combatant.POISON_TICK_SECONDS)
	assert_eq(
		combatant.entity_state.current_state,
		EntityState.State.INTERRUPTED,
		"a poison bite mid-cure interrupts it"
	)
