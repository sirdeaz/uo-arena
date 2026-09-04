extends Node
class_name EntityState

enum State { IDLE, CASTING, FIZZLED, INTERRUPTED }

signal cast_started(spell: SpellData)
signal cast_completed(spell: SpellData)
signal cast_fizzled(spell: SpellData, reason: String)
signal cast_interrupted(spell: SpellData)
signal state_changed(new_state: State)

var current_state: State = State.IDLE
var current_spell: SpellData = null
var cast_time_elapsed: float = 0.0


func _process(delta: float) -> void:
	if current_state == State.CASTING:
		cast_time_elapsed += delta
		if cast_time_elapsed >= current_spell.cast_time_seconds:
			_complete_cast()


func try_start_cast(spell: SpellData) -> bool:
	if current_state == State.CASTING:
		# Casting again too soon fizzles the IN-PROGRESS spell, not the new one.
		if cast_time_elapsed < current_spell.fizzle_window_seconds:
			_fizzle_cast("recast_too_soon")
		else:
			# Already resolving naturally; treat as denied — no queueing for now.
			return false

	current_spell = spell
	cast_time_elapsed = 0.0
	current_state = State.CASTING
	cast_started.emit(spell)
	state_changed.emit(current_state)
	return true


func interrupt_cast() -> void:
	if current_state != State.CASTING:
		return
	var spell := current_spell
	_reset_to_idle()
	current_state = State.INTERRUPTED
	cast_interrupted.emit(spell)
	state_changed.emit(current_state)
	# Snap back to idle next frame so INTERRUPTED is a momentary signal state, not sticky.
	call_deferred("_reset_to_idle")


func _complete_cast() -> void:
	var spell := current_spell
	_reset_to_idle()
	cast_completed.emit(spell)
	state_changed.emit(current_state)


func _fizzle_cast(reason: String) -> void:
	var spell := current_spell
	_reset_to_idle()
	current_state = State.FIZZLED
	cast_fizzled.emit(spell, reason)
	state_changed.emit(current_state)
	call_deferred("_reset_to_idle")


func _reset_to_idle() -> void:
	current_state = State.IDLE
	current_spell = null
	cast_time_elapsed = 0.0
