extends Node2D

## Local single-player harness — no networking. Runs the authoritative pieces
## (`Combatant`, `CombatResolver`, `ArenaMap`) in-process so cover-dodging, fizzling
## and interrupts can be felt before any of it goes over the wire.
##
##   WASD    move
##   1-5     magic arrow / poison / lightning / flamestrike / paralyze
##   R       reset the round

const SPELL_KEYS := {
	KEY_1: "magic_arrow",
	KEY_2: "poison",
	KEY_3: "lightning",
	KEY_4: "flamestrike",
	KEY_5: "paralyze",
}

const DUMMY_THINK_SECONDS: float = 0.9

var map: ArenaMap
var resolver: CombatResolver
var player: Fighter
var dummy: Fighter
var cast_bar: CastBarUI
var hud: Label

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

	player = Fighter.new()
	player.player_controlled = true
	player.body_color = Palette.PLAYER
	player.position = spawns[0]
	add_child(player)

	dummy = Fighter.new()
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

	_connect_combat(player, dummy)
	_connect_combat(dummy, player)

	_build_ui()


func _connect_combat(from: Fighter, to: Fighter) -> void:
	from.combatant.entity_state.cast_completed.connect(
		func(spell: SpellData) -> void: _on_cast_completed(from, to, spell)
	)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	cast_bar = CastBarUI.new()
	cast_bar.position = Vector2(24.0, 640.0)
	cast_bar.size = Vector2(260.0, 16.0)
	layer.add_child(cast_bar)
	cast_bar.bind(player.combatant.entity_state)

	hud = Label.new()
	hud.position = Vector2(24.0, 20.0)
	hud.add_theme_color_override("font_color", Palette.UI_TEXT)
	layer.add_child(hud)


func _on_cast_completed(from: Fighter, to: Fighter, spell: SpellData) -> void:
	var connected := resolver.resolve_cast(from.combatant, to.combatant, spell)
	var who := "you" if from == player else "dummy"
	_last_event = "%s cast %s — %s" % [
		who, spell.spell_name, "hit" if connected else "blocked by cover"
	]
	if connected:
		_bolts.add_effect(from.position, to.position, spell)


func _process(delta: float) -> void:
	_run_dummy(delta)
	_update_hud()
	_sight_line.queue_redraw()


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

	if not SPELL_KEYS.has(key.keycode):
		return
	if not player.combatant.is_alive():
		return

	var spell := _spell(SPELL_KEYS[key.keycode])
	if not resolver.try_begin_cast(player.combatant, dummy.combatant, spell):
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
		"hold RIGHT MOUSE to move toward the cursor    R reset",
		"1 arrow   2 poison   3 lightning   4 flamestrike   5 paralyze",
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

	hud.text = "\n".join(lines)


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
