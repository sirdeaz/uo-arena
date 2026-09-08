extends Node2D
class_name ArenaClient

## The client's view of a match the server owns.
##
## Built imperatively, deliberately shaped like `local_test.gd` — same arena, same view,
## same camera, same cast bar — because the whole point is that a networked fight looks
## and reads exactly like the practice one. What differs is where the truth comes from:
## nothing here decides anything. Snapshots arrive and are written into mirror
## combatants; the three ways a cast can end arrive as announced events; the only things
## this sends back are "I am steering this way" and "I would like to cast that".
##
## It knows nothing about RPCs either. It emits `input_changed` and `cast_requested`,
## and `autoload/network_manager.gd` is what turns those into packets — which is what
## lets all of this be tested without a socket.

signal input_changed(direction: Vector2)
signal cast_requested(spell_id: int, target_peer: int)

## How near a click has to land to pick somebody. Generous relative to the 18 px body,
## because missing your target selection in a ten-player brawl is worse than
## occasionally selecting the wrong neighbour.
const TARGET_PICK_RADIUS: float = 44.0

## Steering is sent on change, plus this often regardless. Input goes unreliably, so the
## packet that says "I let go of the button" is exactly the one that can go missing.
const INPUT_HEARTBEAT_SECONDS: float = 0.1

## A scene rather than `Fighter.new()` so the character atlas comes wired from
## `client/art/wizard.tres` and can be swapped in the editor.
const FIGHTER_SCENE := preload("res://client/scenes/fighter.tscn")

## Which peer this client is playing. Set before adding the node to the tree.
var local_peer_id: int = 0

## Painted-and-collided arena, authored in `res://arena/arena.tscn` and instanced as a
## child here. The server loads the same scene.
@onready var map: ArenaMap = $Arena

## The camera, the sight-line layer, the bolt layer, the audio node, the HUD and the
## debug overlay all live in `client/scenes/arena_stage.tscn`, shared verbatim with the
## practice harness — the "looks exactly like the practice one" promise is one authored
## scene now, not two `_ready()` methods kept identical by hand.
@onready var hud: ArenaHud = $Stage/ArenaHud

## Used for the sight line only. The server does its own raycasting and this one has no
## authority over anything — it exists so you can see the shot you are being told about.
@onready var resolver: CombatResolver = $Stage/Resolver

@onready var audio: SpellAudio = $Stage/Audio
@onready var _sight_line: Node2D = $Stage/SightLine
@onready var _bolts: BoltLayer = $Stage/Bolts

var _fighters: Dictionary = {}
var _target_peer: int = 0
var _last_event: String = ""

var _last_sent_input: Vector2 = Vector2.ZERO
var _seconds_since_input_sent: float = 0.0


func _ready() -> void:
	($Stage/ArenaView as ArenaView).setup(map)

	# Fixed at the origin: at 0.85 zoom a 1280×720 window shows 1506×847, and the arena
	# is 1200×800, so all ten players are always on screen and nothing has to follow.
	($Stage/Camera2D as Camera2D).make_current()

	_sight_line.draw.connect(_draw_sight_line)


# ── What the server tells us ──────────────────────────────────────────────────────


## The full roster, resent on every join and leave. Idempotent on purpose: working out
## incremental adds and removes would be one more thing that can drift out of step.
##
## The server sends slot numbers, not colours — what a slot looks like is decided here,
## which is why `server/` never has to know what rose means.
func apply_roster(peer_ids: PackedInt32Array, slots: PackedInt32Array) -> void:
	var present := {}
	for index in peer_ids.size():
		var peer_id := peer_ids[index]
		present[peer_id] = true
		var slot := slots[index] if index < slots.size() else index
		var color := _color_for(peer_id, slot)
		if _fighters.has(peer_id):
			_fighters[peer_id].body_color = color
		else:
			_add_fighter(peer_id, color)

	for peer_id in _fighters.keys():
		if not present.has(peer_id):
			_remove_fighter(peer_id)

	if not _fighters.has(_target_peer):
		_target_peer = 0


func apply_snapshot(records: Array) -> void:
	for record in records:
		if record.size() != NetProtocol.RECORD_SIZE:
			continue
		var peer_id := NetProtocol.peer_of(record)
		# A record can arrive for somebody whose roster entry has not landed yet. Drop
		# it rather than inventing a fighter with no colour and no place in the HUD.
		if not _fighters.has(peer_id):
			continue
		var fighter: Fighter = _fighters[peer_id]
		if NetProtocol.apply_record(record, fighter.combatant):
			fighter.server_position = fighter.combatant.position


func apply_cast_event(peer_id: int, event: EntityState.Event, spell_id: int) -> void:
	if not _fighters.has(peer_id):
		return
	_fighters[peer_id].combatant.entity_state.emit_remote_event(
		event, SpellBook.spell_for(spell_id)
	)


## A spell finished. Only the caster is ever told about one that was blocked, so a
## `connected` of false here is news about your own shot and nobody else's.
func apply_spell_resolved(
	caster_peer: int, target_peer: int, spell_id: int, connected: bool
) -> void:
	var spell := SpellBook.spell_for(spell_id)
	if spell == null:
		return

	if caster_peer == local_peer_id:
		_last_event = "you cast %s — %s" % [
			spell.spell_name, "hit" if connected else "blocked by cover"
		]
	elif target_peer == local_peer_id:
		_last_event = "%s hit you" % spell.spell_name

	# A spell stopped by cover draws nothing at all, exactly as in the practice harness.
	if not connected:
		return
	if not _fighters.has(caster_peer) or not _fighters.has(target_peer):
		return
	# Only a spell that lands makes a sound, the same rule the bolt follows.
	audio.play(SpellAudio.Cue.IMPACT)
	_bolts.add_effect(
		_fighters[caster_peer].position, _fighters[target_peer].position, spell
	)


func note(message: String) -> void:
	_last_event = message


func fighter_of(peer_id: int) -> Fighter:
	return _fighters.get(peer_id)


func player_count() -> int:
	return _fighters.size()


func peer_ids() -> Array:
	return _fighters.keys()


## The line at the bottom of the HUD — the last thing worth telling you about.
func last_event() -> String:
	return _last_event


# ── What we tell the server ───────────────────────────────────────────────────────


func _physics_process(delta: float) -> void:
	_send_input(delta)
	_update_aim()
	_update_hud()
	_sight_line.queue_redraw()


## Turns you toward whoever you have selected. Only the local client knows its own
## target — a snapshot carries positions and state, never intent — so this is set here,
## and every remote fighter falls back to facing the way it is travelling.
func _update_aim() -> void:
	var fighter := _local_fighter()
	if fighter == null:
		return
	if _fighters.has(_target_peer):
		var target: Fighter = _fighters[_target_peer]
		fighter.aim_at(target.position)
	else:
		fighter.aim_at(null)


func _send_input(delta: float) -> void:
	_seconds_since_input_sent += delta

	var fighter := _local_fighter()
	# Steering intent is sent raw. Whether it is allowed — paralyzed, dead — is the
	# server's ruling, and it makes it again on its own side every step.
	var direction := fighter.input_direction() if fighter != null else Vector2.ZERO

	var changed := not direction.is_equal_approx(_last_sent_input)
	if not changed and _seconds_since_input_sent < INPUT_HEARTBEAT_SECONDS:
		return

	_last_sent_input = direction
	_seconds_since_input_sent = 0.0
	input_changed.emit(direction)


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return

	var picked := _peer_near(get_global_mouse_position())
	# Clicking empty ground leaves your selection alone. There is no use for having no
	# target, and losing one mid-fight to a stray click would be its own kind of misery.
	if picked != 0:
		_target_peer = picked


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return

	if key.keycode == KEY_M:
		audio.toggle_muted()
		return

	var spell_id := SpellBook.spell_id_for_hotkey(key.physical_keycode)
	if spell_id < 0:
		return

	var spell := SpellBook.spell_for(spell_id)

	# Cure resolves on you: no target to pick, no line of sight to check. The server
	# forces the target to yourself anyway — this just spares the "no target" nag.
	if spell != null and spell.is_self_cast():
		cast_requested.emit(spell_id, local_peer_id)
		return

	if _target_peer == 0 or not _fighters.has(_target_peer):
		_last_event = "no target — click someone first"
		return

	# The server refuses a shot into cover silently — a refusal costs nothing, so it
	# announces nothing — which would leave a pressed key doing nothing with no
	# explanation. Say so locally. The request still goes: the server is the authority
	# on what you can see, and its answer overwrites this line either way.
	if not _has_line_of_sight_to_target() and spell != null:
		_last_event = "%s — no line of sight" % spell.spell_name

	cast_requested.emit(spell_id, _target_peer)


# ── Internals ─────────────────────────────────────────────────────────────────────


## You are always blue; everyone else wears their slot. Keeping "blue is you" true is
## worth more mid-fight than giving yourself a unique colour would be — the first read
## is always "is that me", and it should cost nothing.
func _color_for(peer_id: int, slot: int) -> Color:
	if peer_id == local_peer_id:
		return Palette.PLAYER
	return Palette.opponent_body(slot)


func _add_fighter(peer_id: int, color: Color) -> void:
	var fighter: Fighter = FIGHTER_SCENE.instantiate()
	fighter.body_color = color
	fighter.server_driven = true
	fighter.player_controlled = peer_id == local_peer_id
	add_child(fighter)
	_fighters[peer_id] = fighter
	_connect_audio(fighter)

	if peer_id == local_peer_id:
		# Bound once, for the life of the connection. Dying moves this fighter rather
		# than replacing it, precisely so this binding survives a respawn.
		hud.bind_cast_bar(fighter.combatant.entity_state)


## Everyone in the arena is audible, opponents included. A mirrored caster emits the
## same four signals a local one does — `apply_remote_state` and `emit_remote_event`
## replay them — so hearing an enemy start a cast, and hearing your own fizzle while you
## are watching the sight line rather than your feet, needs no networking of its own.
func _connect_audio(fighter: Fighter) -> void:
	var state := fighter.combatant.entity_state
	state.cast_started.connect(
		func(_spell: SpellData) -> void: audio.play(SpellAudio.Cue.CAST_START)
	)
	state.cast_completed.connect(
		func(_spell: SpellData) -> void: audio.play(SpellAudio.Cue.CAST_RELEASE)
	)
	state.cast_fizzled.connect(
		func(_spell: SpellData, _reason: String) -> void: audio.play(SpellAudio.Cue.FIZZLE)
	)
	state.cast_interrupted.connect(
		func(_spell: SpellData) -> void: audio.play(SpellAudio.Cue.INTERRUPT)
	)


func _remove_fighter(peer_id: int) -> void:
	_fighters[peer_id].queue_free()
	_fighters.erase(peer_id)


func _local_fighter() -> Fighter:
	return _fighters.get(local_peer_id)


## The nearest other player to `point`, or 0 if the click landed on open ground.
func _peer_near(point: Vector2) -> int:
	var best := 0
	var best_distance := TARGET_PICK_RADIUS
	for peer_id in _fighters:
		if peer_id == local_peer_id:
			continue
		var distance: float = _fighters[peer_id].position.distance_to(point)
		if distance <= best_distance:
			best_distance = distance
			best = peer_id
	return best


func _has_line_of_sight_to_target() -> bool:
	var fighter := _local_fighter()
	if fighter == null or not _fighters.has(_target_peer):
		return false
	return resolver.has_line_of_sight(
		get_world_2d().direct_space_state, fighter.position, _fighters[_target_peer].position
	)


func _describe(state: EntityState) -> String:
	var described: String = EntityState.State.keys()[state.current_state]
	described = described.to_lower()
	if state.current_spell != null:
		described += " " + state.current_spell.spell_name
	return described


func _update_hud() -> void:
	var lines := [
		"hold RIGHT MOUSE to move    LEFT CLICK a player to target    M %s" % (
			"unmute" if audio.is_muted() else "mute"
		),
		"1 arrow   2 poison   3 lightning   4 flamestrike   5 paralyze   6 cure",
		"",
	]

	var fighter := _local_fighter()
	if fighter == null:
		lines.append("waiting for the arena…")
		hud.set_readout("\n".join(lines))
		return

	lines.append("you %d — %s" % [
		roundi(fighter.combatant.health), _describe(fighter.combatant.entity_state)
	])

	if _fighters.has(_target_peer):
		var target: Fighter = _fighters[_target_peer]
		lines.append("target %d — %s" % [
			roundi(target.combatant.health), _describe(target.combatant.entity_state)
		])
		lines.append(
			"line of sight: %s" % ("CLEAR" if _has_line_of_sight_to_target() else "BLOCKED")
		)
	else:
		lines.append("no target")

	lines.append("players in the arena: %d" % _fighters.size())
	lines.append(_last_event)

	if not fighter.combatant.is_alive():
		lines.append("")
		lines.append("you died — back in a few seconds")

	hud.set_readout("\n".join(lines))


func _draw_sight_line() -> void:
	var fighter := _local_fighter()
	if fighter == null:
		return

	if _fighters.has(_target_peer):
		var target: Fighter = _fighters[_target_peer]
		# Whether there is a shot is a spatial fact, so it is drawn spatially — solid
		# when the line is live, dashed when cover has broken it. Same vocabulary the
		# practice harness uses.
		if _has_line_of_sight_to_target():
			_sight_line.draw_line(
				fighter.position,
				target.position,
				Color(Palette.SIGHT_LINE, Palette.SIGHT_LINE_CLEAR_ALPHA),
				2.0
			)
		else:
			_sight_line.draw_dashed_line(
				fighter.position,
				target.position,
				Color(Palette.SIGHT_LINE, Palette.SIGHT_LINE_BLOCKED_ALPHA),
				2.0,
				Palette.SIGHT_LINE_DASH
			)

		# Who you have selected, in their own body colour — the ring is that player,
		# picked out, not a new thing to learn.
		_sight_line.draw_arc(
			target.position,
			Constants.PLAYER_RADIUS + 6.0,
			0.0,
			TAU,
			24,
			target.body_color,
			2.0,
			true
		)

	# Where you are steering, while the move button is down.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var cursor := _sight_line.get_global_mouse_position()
		_sight_line.draw_arc(
			cursor, 9.0, 0.0, TAU, 20,
			Color(Palette.PLAYER, Palette.STEER_CURSOR_ALPHA), 2.0, true
		)
		_sight_line.draw_line(
			fighter.position, cursor, Color(Palette.PLAYER, Palette.STEER_LINE_ALPHA), 1.0
		)
