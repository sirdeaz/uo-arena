extends Node2D

## Local single-player harness — no networking. Runs the authoritative pieces
## (`Combatant`, `CombatResolver`, `ArenaMap`) in-process so cover-dodging, fizzling
## and interrupts can be felt before any of it goes over the wire.
##
##   RIGHT MOUSE  walk toward the cursor (WASD also works, for testing)
##   1-6          magic arrow / poison / lightning / flamestrike / paralyze / cure
##   R            reset the round
##   M            mute
##   P            route around cover instead of walking into it

const DUMMY_THINK_SECONDS: float = 0.9

## A scene rather than `Fighter.new()` so the character atlas comes wired from
## `client/art/wizard.tres` and can be swapped in the editor.
const FIGHTER_SCENE := preload("res://client/scenes/fighter.tscn")

var map: ArenaMap
var resolver: CombatResolver
var player: Fighter
var dummy: Fighter
var hud: ArenaHud
var audio: SpellAudio

var _dummy_think_timer: float = 0.0
var _last_event: String = ""

## Drawn above the arena floor — this node draws itself before its children, so the
## sight line has to live on a layer of its own or the floor paints over it.
var _sight_line: Node2D

## Bolts and impacts for spells that connected. Blocked spells add nothing at all,
## matching UO, where a spell you have no line to simply never goes off.
var _bolts: BoltLayer


func _ready() -> void:
	resolver = CombatResolver.new()
	add_child(resolver)

	map = load("res://server/arena_map.tscn").instantiate()
	add_child(map)

	var view := ArenaView.new()
	add_child(view)
	view.setup(map)

	var camera := Camera2D.new()
	camera.zoom = Vector2(0.85, 0.85)
	add_child(camera)
	camera.make_current()

	var spawns := map.get_spawn_positions()

	player = FIGHTER_SCENE.instantiate()
	player.player_controlled = true
	player.body_color = Palette.PLAYER
	player.position = spawns[0]
	add_child(player)

	# Built once from the map that was just added — the arena's geometry is fixed at load
	# and nothing ever moves it. Off until you press P.
	var finder := PathFinder.new()
	finder.build(map)
	player.enable_pathfinding(finder)

	dummy = FIGHTER_SCENE.instantiate()
	dummy.body_color = Palette.DUMMY
	dummy.position = spawns[1]
	add_child(dummy)

	_sight_line = Node2D.new()
	_sight_line.z_index = 5
	add_child(_sight_line)
	_sight_line.draw.connect(_draw_sight_line)

	# Spell bolts get their own additive layer so they glow rather than tint.
	_bolts = BoltLayer.new()
	add_child(_bolts)

	audio = SpellAudio.new()
	add_child(audio)
	_connect_audio(player)
	_connect_audio(dummy)

	_connect_combat(player, dummy)
	_connect_combat(dummy, player)

	hud = ArenaHud.new()
	add_child(hud)
	hud.bind_cast_bar(player.combatant.entity_state)


## Both fighters are audible. Hearing the enemy start a cast is the read the mantras
## give you visually, and hearing your own fizzle is the point of the whole system —
## it happens while you are watching the sight line, not your own feet.
func _connect_audio(fighter: Fighter) -> void:
	var state := fighter.combatant.entity_state
	state.cast_started.connect(func(_spell: SpellData) -> void: audio.play(SpellAudio.Cue.CAST_START))
	state.cast_completed.connect(func(_spell: SpellData) -> void: audio.play(SpellAudio.Cue.CAST_RELEASE))
	state.cast_fizzled.connect(
		func(_spell: SpellData, _reason: String) -> void: audio.play(SpellAudio.Cue.FIZZLE)
	)
	state.cast_interrupted.connect(
		func(_spell: SpellData) -> void: audio.play(SpellAudio.Cue.INTERRUPT)
	)


func _connect_combat(from: Fighter, to: Fighter) -> void:
	from.combatant.entity_state.cast_completed.connect(
		func(spell: SpellData) -> void: _on_cast_completed(from, to, spell)
	)


func _on_cast_completed(from: Fighter, to: Fighter, spell: SpellData) -> void:
	# A self-cast spell (Cure) lands on the caster, not on the fixed opponent this
	# connection was bound to.
	var recipient := from if spell.is_self_cast() else to
	var connected := resolver.resolve_cast(from.combatant, recipient.combatant, spell)
	var who := "you" if from == player else "dummy"
	_last_event = "%s cast %s — %s" % [
		who, spell.spell_name, "hit" if connected else "blocked by cover"
	]
	if connected:
		# Only a spell that lands makes a sound, the same rule the bolt and impact ring
		# already follow: a blocked spell is silent and invisible, because in UO it
		# simply never went off.
		audio.play(SpellAudio.Cue.IMPACT)
		_bolts.add_effect(from.position, recipient.position, spell)


func _process(delta: float) -> void:
	_run_dummy(delta)
	_update_aim()
	_update_hud()
	_sight_line.queue_redraw()


## Both fighters know exactly who they are throwing at here, so both turn to face it.
## Offline that is free — there is one opponent each — and it is what makes the practice
## harness show the same heading a real duel will.
func _update_aim() -> void:
	player.aim_at(dummy.position)
	dummy.aim_at(player.position)


func _run_dummy(delta: float) -> void:
	if not dummy.combatant.is_alive() or not player.combatant.is_alive():
		return
	if dummy.combatant.entity_state.current_state != EntityState.State.IDLE:
		return

	_dummy_think_timer += delta
	if _dummy_think_timer < DUMMY_THINK_SECONDS:
		return
	_dummy_think_timer = 0.0
	resolver.try_begin_cast(dummy.combatant, player.combatant, _spell("magic_arrow"))


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return

	if key.keycode == KEY_R:
		get_tree().reload_current_scene()
		return

	if key.keycode == KEY_M:
		audio.toggle_muted()
		return

	if key.keycode == KEY_P:
		_last_event = "pathing %s" % ("ON" if player.toggle_pathfinding() else "OFF")
		return

	var spell_id := SpellBook.spell_id_for_hotkey(key.physical_keycode)
	if spell_id < 0:
		return
	if not player.combatant.is_alive():
		return

	var spell := SpellBook.spell_for(spell_id)
	# Cure resolves on you; everything else flies at the dummy.
	var target: Combatant = player.combatant if spell.is_self_cast() else dummy.combatant
	if not resolver.try_begin_cast(player.combatant, target, spell):
		if not resolver.can_see(player.combatant, dummy.combatant):
			_last_event = "%s — no line of sight" % spell.spell_name


func _spell(spell_name: String) -> SpellData:
	return load("res://common/spells/%s.tres" % spell_name)


func _has_line_of_sight() -> bool:
	return resolver.has_line_of_sight(
		get_world_2d().direct_space_state, player.position, dummy.position
	)


func _describe(state: EntityState) -> String:
	var name: String = EntityState.State.keys()[state.current_state]
	var described := name.to_lower()
	if state.current_spell != null:
		described += " " + state.current_spell.spell_name
	return described


func _update_hud() -> void:
	var status := _describe(player.combatant.entity_state)

	var lines := [
		"hold RIGHT MOUSE to move toward the cursor    R reset    M %s    P pathing %s" % [
			"unmute" if audio.is_muted() else "mute",
			# The state, not the action — unlike M, whose effect you can hear. A mode you
			# can only see the consequences of should say which way it is set.
			"ON" if player.pathfinding_enabled else "OFF",
		],
		"1 arrow   2 poison   3 lightning   4 flamestrike   5 paralyze   6 cure",
		"",
		"you %d    dummy %d" % [
			roundi(player.combatant.health), roundi(dummy.combatant.health)
		],
		"line of sight: %s" % ("CLEAR" if _has_line_of_sight() else "BLOCKED"),
		"you are: %s" % status,
		"dummy is: %s" % _describe(dummy.combatant.entity_state),
		_last_event,
	]

	if not player.combatant.is_alive():
		lines.append("")
		lines.append("you died — R to reset")
	elif not dummy.combatant.is_alive():
		lines.append("")
		lines.append("dummy down — R to reset")

	hud.set_readout("\n".join(lines))


func _draw_sight_line() -> void:
	# The shot the dummy has on you, drawn exactly as the raycast sees it. Whether the
	# line is live is a spatial fact, so it is drawn spatially — solid and bright when
	# there is a shot, dashed and faint when cover has broken it. It used to be
	# green-versus-red, which meant the two most loaded colours on screen were being
	# spent here as well as on health, poison and cast feedback.
	if _has_line_of_sight():
		_sight_line.draw_line(
			player.position,
			dummy.position,
			Color(Palette.SIGHT_LINE, Palette.SIGHT_LINE_CLEAR_ALPHA),
			2.0
		)
	else:
		_sight_line.draw_dashed_line(
			player.position,
			dummy.position,
			Color(Palette.SIGHT_LINE, Palette.SIGHT_LINE_BLOCKED_ALPHA),
			2.0,
			Palette.SIGHT_LINE_DASH
		)

	# Where you are steering, while the move button is down.

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var cursor := _sight_line.get_global_mouse_position()
		_sight_line.draw_arc(
			cursor, 9.0, 0.0, TAU, 20,
			Color(Palette.PLAYER, Palette.STEER_CURSOR_ALPHA), 2.0, true
		)
		_sight_line.draw_line(
			player.position, cursor,
			Color(Palette.PLAYER, Palette.STEER_LINE_ALPHA), 1.0
		)
		_draw_route()


## The route being walked, when pathfinding is the one steering. With the assist off, or
## with a clear line to the cursor, there is no route and this draws nothing — so the
## straight steer line above is the whole picture, exactly as it was before.
func _draw_route() -> void:
	var route := player.steering_path()
	if route.is_empty():
		return

	# The leg being walked right now, brighter than the straight line it replaces.
	_sight_line.draw_line(
		player.position, route[0],
		Color(Palette.PLAYER, Palette.PATH_LINE_ALPHA), 2.0
	)

	for i in range(1, route.size()):
		_sight_line.draw_dashed_line(
			route[i - 1], route[i],
			Color(Palette.PLAYER, Palette.PATH_WAYPOINT_ALPHA), 1.0, Palette.PATH_DASH
		)

	# A ring on each corner still to be rounded, so the shape of the detour is legible.
	for i in route.size() - 1:
		_sight_line.draw_arc(
			route[i], 5.0, 0.0, TAU, 12,
			Color(Palette.PLAYER, Palette.PATH_WAYPOINT_ALPHA), 1.0, true
		)
