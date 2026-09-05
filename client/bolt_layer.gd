extends Node2D
class_name BoltLayer

## Spells in flight and where they landed, on their own additive layer so glow
## accumulates toward white instead of flatly tinting whatever is underneath.
##
## An effect is a snapshot taken at the moment a spell resolved: it records where the
## spell went, and does not follow the fighters afterwards. A spell that was stopped by
## cover is never added at all — in UO a spell with no line simply never goes off, and
## drawing a bolt that fizzled out against a tent would give away a shot the caster is
## entitled to have kept private.

## How long a bolt and its impact stay on screen.
const EFFECT_SECONDS: float = 0.55

var _effects: Array[Dictionary] = []
var _time: float = 0.0


func _ready() -> void:
	# Above the fighters and the sight line, which sit at 0 and 5.
	z_index = 6
	material = SpellFX.additive_material()


## Records a spell that connected, drawn from `from` to `to` for `EFFECT_SECONDS`.
func add_effect(from: Vector2, to: Vector2, spell: SpellData) -> void:
	_effects.append({
		"from": from,
		"to": to,
		"color": SpellVisuals.color_for(spell),
		"flame": SpellVisuals.style_for(spell) == SpellVisuals.Style.FLAME,
		"remaining": EFFECT_SECONDS,
	})


func _process(delta: float) -> void:
	_time += delta
	for effect in _effects:
		effect["remaining"] -= delta
	_effects = _effects.filter(func(e: Dictionary) -> bool: return e["remaining"] > 0.0)
	queue_redraw()


## The spell itself: a jagged filament with a white-hot core, and an impact that blows
## a crackling ring outward. Flame wanders; arc snaps.
func _draw() -> void:
	for effect in _effects:
		var fade: float = effect["remaining"] / EFFECT_SECONDS
		var color: Color = effect["color"]
		var from: Vector2 = effect["from"]
		var to: Vector2 = effect["to"]
		var flame: bool = effect["flame"]
		var seed := SpellFX.crackle_seed(_time)

		var amplitude := (10.0 if flame else 18.0) * fade
		var segments := 14 if flame else 20
		var path := SpellFX.bolt_path(from, to, segments, amplitude, seed)
		SpellFX.draw_glow_line(self, path, color, fade, 2.4)

		# A couple of forks off the main filament, arc spells only.
		if not flame:
			for i in 2:
				var index := path.size() / 3 + i * path.size() / 3
				var root: Vector2 = path[index]
				var tip := root + Vector2(
					(to - from).y, -(to - from).x
				).normalized() * (24.0 * fade * (1.0 if i == 0 else -1.0))
				var fork := SpellFX.bolt_path(root, tip, 4, 9.0, seed + 53 + i)
				SpellFX.draw_glow_line(self, fork, color, fade * 0.55, 0.5)

		# Impact: expanding crackling ring plus a hot core.
		var radius := 16.0 + (1.0 - fade) * 30.0
		var ring := SpellFX.ring_path(radius, 26, radius * 0.14, seed + 11)
		var shifted := PackedVector2Array()
		for point in ring:
			shifted.append(point + to)
		SpellFX.draw_glow_line(self, shifted, color, fade, 0.9, true)
		SpellFX.draw_glow_disc(self, to, radius * 1.1, color, fade)
