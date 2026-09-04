extends TestCase

## Damage-driven interruption. In UO any damage that lands breaks a spell, so this
## lives in `take_damage` rather than only in spell resolution — that way poison ticks
## and any future damage source get the behaviour for free.

var combatant: Combatant


func before_each() -> void:
	combatant = Combatant.new()
	add_child(combatant)


func after_each() -> void:
	combatant.queue_free()


func _flamestrike() -> SpellData:
	return load("res://common/spells/flamestrike.tres")


func test_taking_damage_interrupts_an_in_progress_cast() -> void:
	combatant.entity_state.try_start_cast(_flamestrike())
	combatant.take_damage(5.0)
	assert_eq(
		combatant.entity_state.current_state,
		EntityState.State.INTERRUPTED,
		"any damage should break a cast"
	)


func test_zero_damage_does_not_interrupt_a_cast() -> void:
	combatant.entity_state.try_start_cast(_flamestrike())
	combatant.take_damage(0.0)
	assert_eq(
		combatant.entity_state.current_state,
		EntityState.State.CASTING,
		"a no-op hit must not break a cast"
	)


func test_taking_damage_while_idle_is_harmless() -> void:
	combatant.take_damage(5.0)
	assert_eq(
		combatant.entity_state.current_state,
		EntityState.State.IDLE,
		"interrupting an idle combatant should do nothing"
	)
	assert_almost_eq(combatant.health, 95.0, "damage still applies")
