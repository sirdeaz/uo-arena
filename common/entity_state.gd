extends Node
class_name EntityState

## Cast timing, shared verbatim by client and server. The server's copy is
## authoritative; the client's mirrors it for local feedback and gets corrected on
## desync. No line-of-sight logic lives here — that belongs in `combat_resolver.gd`
## at the moment a spell connects, not in the timing machine.
##
## Recasting inside the current spell's fizzle window fizzles the *in-progress* spell,
## costs a fixed recovery, and then starts the spell you chained into. That chain is a
## real tool: a stream of cast-starts that never resolve baits an opponent into
## breaking line of sight or committing early. It also means spam-casting lands
## nothing at all, which is the intended punishment.
##
## There is no cast queueing. Recasting after the fizzle window has passed is denied
## outright rather than buffered.

enum State { IDLE, CASTING, RECOVERING, INTERRUPTED }

signal cast_started(spell: SpellData)
signal cast_completed(spell: SpellData)
signal cast_fizzled(spell: SpellData, reason: String)
signal cast_interrupted(spell: SpellData)
signal state_changed(new_state: State)

var current_state: State = State.IDLE
var current_spell: SpellData = null
var cast_time_elapsed: float = 0.0

## Spell waiting out the post-fizzle recovery before it begins casting.
var pending_spell: SpellData = null
var recovery_time_elapsed: float = 0.0


func _process(delta: float) -> void:
	tick(delta)


## Advances cast and recovery timers. Split out of `_process` so the server can drive
## it on a fixed step and so tests can step exact windows.
func tick(delta: float) -> void:
	match current_state:
		State.CASTING:
			cast_time_elapsed += delta
			if cast_time_elapsed >= current_spell.cast_time_seconds:
				_complete_cast()
		State.RECOVERING:
			recovery_time_elapsed += delta
			if recovery_time_elapsed >= Constants.GLOBAL_CAST_RECOVERY_SECONDS:
				_begin_pending_cast()


func try_start_cast(spell: SpellData) -> bool:
	if current_state == State.RECOVERING:
		# Paying off a fizzle. Nothing may be cast until the recovery is done.
		return false

	if current_state == State.CASTING:
		if cast_time_elapsed >= current_spell.fizzle_window_seconds:
			# Already resolving naturally; treat as denied — no queueing for now.
			return false
		# Casting again too soon fizzles the IN-PROGRESS spell, not the new one.
		# The new one waits out the recovery instead of starting here.
		_fizzle_cast("recast_too_soon")
		pending_spell = spell
		recovery_time_elapsed = 0.0
		_set_state(State.RECOVERING)
		return true

	_begin_cast(spell)
	return true


func interrupt_cast() -> void:
	if current_state != State.CASTING:
		return
	var spell := current_spell
	_reset_cast()
	_set_state(State.INTERRUPTED)
	cast_interrupted.emit(spell)
	# INTERRUPTED is a momentary signal state, not a sticky one. Clear it next frame —
	# but only if nothing has started since, or we would cancel that new cast.
	_clear_transient_state.call_deferred(State.INTERRUPTED)


func _begin_cast(spell: SpellData) -> void:
	current_spell = spell
	cast_time_elapsed = 0.0
	_set_state(State.CASTING)
	cast_started.emit(spell)


func _begin_pending_cast() -> void:
	var spell := pending_spell
	pending_spell = null
	recovery_time_elapsed = 0.0
	if spell == null:
		_reset_cast()
		_set_state(State.IDLE)
		return
	_begin_cast(spell)


func _complete_cast() -> void:
	var spell := current_spell
	_reset_cast()
	_set_state(State.IDLE)
	cast_completed.emit(spell)


func _fizzle_cast(reason: String) -> void:
	var spell := current_spell
	_reset_cast()
	cast_fizzled.emit(spell, reason)


func _reset_cast() -> void:
	current_spell = null
	cast_time_elapsed = 0.0


func _set_state(new_state: State) -> void:
	current_state = new_state
	state_changed.emit(new_state)


## Deferred cleanup for momentary states. No-ops if the state has already moved on,
## so a cast started in the same frame survives.
func _clear_transient_state(expected: State) -> void:
	if current_state == expected:
		_set_state(State.IDLE)
