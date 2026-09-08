extends Node2D
class_name ArenaStage

## The view both clients share, authored in `arena_stage.tscn` — camera, sight-line and
## bolt layers, audio, HUD. This script is only the handful of helpers that were
## byte-identical in `arena_client.gd` and `local_test.gd`; the two clients still own the
## parts that genuinely differ (a networked target ring vs the practice route overlay).

@onready var _audio: SpellAudio = $Audio


## Wires a fighter's four cast signals to the shared audio node, so a cast you start and
## a cast you only hear both go through the same cue table. Every fighter in the arena is
## audible — see the clients for why.
func connect_fighter_audio(fighter: Fighter) -> void:
	var state := fighter.combatant.entity_state
	state.cast_started.connect(func(_s: SpellData) -> void: _audio.play(SpellAudio.Cue.CAST_START))
	state.cast_completed.connect(func(_s: SpellData) -> void: _audio.play(SpellAudio.Cue.CAST_RELEASE))
	state.cast_fizzled.connect(
		func(_s: SpellData, _r: String) -> void: _audio.play(SpellAudio.Cue.FIZZLE)
	)
	state.cast_interrupted.connect(func(_s: SpellData) -> void: _audio.play(SpellAudio.Cue.INTERRUPT))


## The cast state as one HUD line — "casting Flamestrike", "recovering", "idle". Pure, so
## a test can read it without a scene.
static func describe(state: EntityState) -> String:
	var text := (EntityState.State.keys()[state.current_state] as String).to_lower()
	if state.current_spell != null:
		text += " " + state.current_spell.spell_name
	return text


## The shot between two points, drawn spatially: a solid line when it is live, a dashed
## one when cover has broken it. Same vocabulary in both clients.
static func draw_sight_line(canvas: CanvasItem, from: Vector2, to: Vector2, clear: bool) -> void:
	if clear:
		canvas.draw_line(
			from, to, Color(Palette.SIGHT_LINE, Palette.SIGHT_LINE_CLEAR_ALPHA), 2.0
		)
	else:
		canvas.draw_dashed_line(
			from, to, Color(Palette.SIGHT_LINE, Palette.SIGHT_LINE_BLOCKED_ALPHA),
			2.0, Palette.SIGHT_LINE_DASH
		)


## Where you are steering while the move button is held: a ring on the cursor and a
## faint line to it from your feet.
static func draw_steer_cursor(canvas: CanvasItem, from: Vector2, cursor: Vector2) -> void:
	canvas.draw_arc(
		cursor, 9.0, 0.0, TAU, 20,
		Color(Palette.PLAYER, Palette.STEER_CURSOR_ALPHA), 2.0, true
	)
	canvas.draw_line(
		from, cursor, Color(Palette.PLAYER, Palette.STEER_LINE_ALPHA), 1.0
	)
