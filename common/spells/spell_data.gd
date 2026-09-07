extends Resource
class_name SpellData

## Append only. `poison.tres` and `paralyze.tres` store their effect as a bare int
## (`1`, `2`), so inserting a value anywhere but the end silently repoints them.
enum EffectType { DAMAGE, POISON, PARALYZE, CURE }

@export var spell_name: String = ""
## Words spoken overhead while casting. This is the opponent's only warning of what is
## coming, so it is gameplay information, not decoration.
@export var mantra: String = ""
@export var cast_time_seconds: float = 1.0
## CURRENTLY UNUSED. Recasting now abandons the spell in progress at any point in the
## cast, not only inside an opening window, so nothing reads this. Kept rather than
## deleted in case the window earns a different role — but it controls nothing today,
## and editing it will not change how the game plays.
@export var fizzle_window_seconds: float = 0.25
@export var damage: float = 0.0
@export var effect_type: EffectType = EffectType.DAMAGE
@export var effect_duration_seconds: float = 0.0  # used for poison/paralyze
@export var requires_line_of_sight: bool = true


## Whether this spell resolves on the caster rather than on someone they aimed at.
## Pulled into one predicate so `ArenaServer.request_cast` and both clients ask the
## same question. Keyed off `effect_type` because CURE is the only self-cast effect
## there is — the day a self-cast spell arrives that is not a cure (a heal, say), this
## wants to become a `target` field on the resource instead.
func is_self_cast() -> bool:
	return effect_type == EffectType.CURE
