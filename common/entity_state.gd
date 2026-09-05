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

## The three things that end a cast. They are grouped as an enum because a client
## mirroring someone else's caster cannot tell them apart from sampled state — a fizzle
## and an interrupt leave the machine looking identical a frame later — so the server
## has to name which one happened.
enum Event { COMPLETED, FIZZLED, INTERRUPTED }

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


## Advances cast and recovery timers. Nothing calls this on its own: whoever owns this
## machine drives it on a fixed step. That used to be `_process`, which was wrong in two
## directions at once — a headless server with no vsync would have completed casts at
## thousands of hertz, and a client mirroring someone else's caster would have decided
## for itself that their spell had landed.
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
		# Casting again fizzles the IN-PROGRESS spell, not the new one, at any point in
		# the cast. The new one waits out the recovery instead of starting here.
		#
		# Abandoning late costs exactly the same as abandoning early. If a late bail-out
		# were cheaper, the strongest play would be to open every fight with a long cast
		# purely as a threat and drop it for free.
		_fizzle_cast("recast")
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


## Wipes the machine back to idle without announcing anything. Respawning is not a
## fizzle and not an interrupt — the cast simply never happened, and nothing should
## flash. Clearing `pending_spell` is the point of this existing at all: without it,
## someone who dies mid-fizzle-chain stands back up already casting whatever was queued
## behind the spell that killed them.
func reset() -> void:
	current_spell = null
	pending_spell = null
	cast_time_elapsed = 0.0
	recovery_time_elapsed = 0.0
	if current_state != State.IDLE:
		_set_state(State.IDLE)


# ── Mirroring a caster the server owns ────────────────────────────────────────────


## Moves the visible timers and nothing else. Corrections arrive at `SNAPSHOT_HZ` but
## the cast bar and the charging aura are drawn every frame, so a mirror has to fill in
## between updates — while never being allowed to reach a conclusion. Deciding that a
## cast has landed is the server's call alone, so this cannot transition and cannot
## emit. Timers stop at their limit rather than running past it, which leaves a
## finished-looking bar sitting full for the few milliseconds until the server agrees.
func advance_display_only(delta: float) -> void:
	match current_state:
		State.CASTING:
			if current_spell == null:
				return
			cast_time_elapsed = minf(
				cast_time_elapsed + delta, current_spell.cast_time_seconds
			)
		State.RECOVERING:
			recovery_time_elapsed = minf(
				recovery_time_elapsed + delta, Constants.GLOBAL_CAST_RECOVERY_SECONDS
			)


## Overwrites this machine from an authoritative snapshot. Emits `state_changed`, and
## `cast_started` when a cast begins because the cast bar keys its flash off that — but
## never the three ending events, which are announced separately by the server.
func apply_remote_state(
	state: State, spell: SpellData, cast_elapsed: float, recovery_elapsed: float
) -> void:
	# A CASTING record with no spell is a truncated or malformed snapshot. Read it as
	# idle rather than letting a null reference reach the drawing code.
	if state == State.CASTING and spell == null:
		state = State.IDLE

	var begins_cast := state == State.CASTING \
		and (current_state != State.CASTING or current_spell != spell)

	current_spell = spell
	cast_time_elapsed = cast_elapsed
	recovery_time_elapsed = recovery_elapsed

	# Only on a real transition: `state_changed` at snapshot rate would be noise.
	if state != current_state:
		_set_state(state)

	if begins_cast:
		cast_started.emit(spell)


## Replays an ending the server announced, so the cast bar's flash and the fighter's
## release / fizzle / interrupt bursts work on a mirrored caster with no change at all
## to the code that draws them.
func emit_remote_event(event: Event, spell: SpellData) -> void:
	match event:
		Event.COMPLETED:
			cast_completed.emit(spell)
		Event.FIZZLED:
			cast_fizzled.emit(spell, "recast")
		Event.INTERRUPTED:
			cast_interrupted.emit(spell)


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
