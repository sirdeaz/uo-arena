extends Resource
class_name SpellData

enum EffectType { DAMAGE, POISON, PARALYZE }

@export var spell_name: String = ""
## Words spoken overhead while casting. This is the opponent's only warning of what is
## coming, so it is gameplay information, not decoration.
@export var mantra: String = ""
@export var cast_time_seconds: float = 1.0
@export var fizzle_window_seconds: float = 0.25  # window after cast starts where a new cast attempt fizzles this one
@export var damage: float = 0.0
@export var effect_type: EffectType = EffectType.DAMAGE
@export var effect_duration_seconds: float = 0.0  # used for poison/paralyze
@export var requires_line_of_sight: bool = true
