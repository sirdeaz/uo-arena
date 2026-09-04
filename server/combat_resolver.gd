extends Node
class_name CombatResolver

## Server-authoritative spell resolution. Never instantiated on a client.
##
## LOS checking and effect application are kept as separate public functions so each
## can be exercised on its own, and so the raycast stays out of the timing state
## machine in `EntityState`.


## True when nothing on the obstacles layer sits between `from` and `to`.
func has_line_of_sight(
	space_state: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2
) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, Constants.LAYER_OBSTACLES)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return space_state.intersect_ray(query).is_empty()


## Applies a spell's effect to `target`, with no LOS check of its own.
func apply_spell_effect(spell: SpellData, target: Combatant) -> void:
	match spell.effect_type:
		SpellData.EffectType.DAMAGE:
			target.take_damage(spell.damage)
		SpellData.EffectType.POISON:
			target.apply_poison(spell.effect_duration_seconds, spell.damage)
		SpellData.EffectType.PARALYZE:
			target.apply_paralyze(spell.effect_duration_seconds)


## Called when a cast completes on the server. Returns whether the spell connected.
## An obstructed spell fails silently with no refund — that is what makes cover real.
func resolve_cast(caster: Combatant, target: Combatant, spell: SpellData) -> bool:
	if spell.requires_line_of_sight:
		var space_state := get_viewport().get_world_2d().direct_space_state
		if not has_line_of_sight(space_state, caster.position, target.position):
			return false

	apply_spell_effect(spell, target)
	target.entity_state.interrupt_cast()
	return true
