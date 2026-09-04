extends Control
class_name CastBarUI

## Purely reactive to `EntityState` signals — it holds no timing logic of its own and
## never polls for state changes. It reads `cast_time_elapsed` only to size the fill.

const FLASH_SECONDS: float = 0.45

const CASTING_COLOR := Color("#6ec6ff")
const RECOVERY_COLOR := Color("#8a7a5c")
const COMPLETE_COLOR := Color("#7ee081")
const FIZZLE_COLOR := Color("#e2574c")
const INTERRUPT_COLOR := Color("#ffa447")

var _state: EntityState
var _flash_color := Color.TRANSPARENT
var _flash_text := ""
var _flash_remaining := 0.0


func bind(state: EntityState) -> void:
	_state = state
	state.cast_started.connect(_on_cast_started)
	state.cast_completed.connect(_on_cast_completed)
	state.cast_fizzled.connect(_on_cast_fizzled)
	state.cast_interrupted.connect(_on_cast_interrupted)


func _process(delta: float) -> void:
	_flash_remaining = maxf(0.0, _flash_remaining - delta)
	queue_redraw()


func _on_cast_started(_spell: SpellData) -> void:
	_flash_remaining = 0.0
	queue_redraw()


func _on_cast_completed(spell: SpellData) -> void:
	_flash(COMPLETE_COLOR, spell.spell_name)


func _on_cast_fizzled(_spell: SpellData, _reason: String) -> void:
	_flash(FIZZLE_COLOR, "fizzled")


func _on_cast_interrupted(_spell: SpellData) -> void:
	_flash(INTERRUPT_COLOR, "interrupted")


func _flash(color: Color, text: String) -> void:
	_flash_color = color
	_flash_text = text
	_flash_remaining = FLASH_SECONDS


func _draw() -> void:
	if _state == null:
		return

	var track := Rect2(Vector2.ZERO, size)
	var font := get_theme_default_font()
	var font_size := 15

	match _state.current_state:
		EntityState.State.CASTING:
			_draw_bar(
				track,
				_state.cast_time_elapsed / _state.current_spell.cast_time_seconds,
				CASTING_COLOR
			)
			_draw_caption(font, font_size, _state.current_spell.spell_name, CASTING_COLOR)
		EntityState.State.RECOVERING:
			_draw_bar(
				track,
				_state.recovery_time_elapsed / Constants.GLOBAL_CAST_RECOVERY_SECONDS,
				RECOVERY_COLOR
			)
			_draw_caption(font, font_size, "recovering", RECOVERY_COLOR)
		_:
			if _flash_remaining <= 0.0:
				return
			_draw_bar(track, 1.0, _flash_color * Color(1, 1, 1, _flash_alpha()))
			_draw_caption(font, font_size, _flash_text, _flash_color)


func _flash_alpha() -> float:
	return _flash_remaining / FLASH_SECONDS


func _draw_bar(track: Rect2, fraction: float, color: Color) -> void:
	draw_rect(track, Color("#11141c"))
	var filled := Rect2(track.position, Vector2(track.size.x * clampf(fraction, 0.0, 1.0), track.size.y))
	draw_rect(filled, color)
	draw_rect(track, Color("#3a4050"), false, 1.0)


func _draw_caption(font: Font, font_size: int, text: String, color: Color) -> void:
	draw_string(
		font, Vector2(0.0, -6.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color
	)
