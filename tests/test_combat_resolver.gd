extends TestCase

## Hit resolution: what happens when a cast completes. Uses real Combatant and
## EntityState instances against a real physics world — the interesting behaviour is
## the interaction between them, which a mock would only assert away.

var resolver: CombatResolver
var world: Node2D
var caster: Combatant
var target: Combatant


func before_each() -> void:
	world = Node2D.new()
	add_child(world)
	resolver = CombatResolver.new()
	add_child(resolver)

	caster = Combatant.new()
	caster.position = Vector2(0, 0)
	world.add_child(caster)

	target = Combatant.new()
	target.position = Vector2(200, 0)
	world.add_child(target)


func after_each() -> void:
	world.queue_free()
	resolver.queue_free()


func _add_wall_between() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = Constants.LAYER_OBSTACLES
	body.collision_mask = 0
	body.position = Vector2(100, 0)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40, 200)
	shape.shape = rect
	body.add_child(shape)
	world.add_child(body)


func _spell(name: String) -> SpellData:
	return load("res://common/spells/%s.tres" % name)


# ── effect application, independent of LOS ────────────────────────────────────

func test_damage_effect_reduces_target_health() -> void:
	var before := target.health
	resolver.apply_spell_effect(_spell("lightning"), target)
	assert_almost_eq(target.health, before - 20.0, "lightning should deal its 20 damage")


func test_health_does_not_fall_below_zero() -> void:
	target.health = 5.0
	resolver.apply_spell_effect(_spell("flamestrike"), target)
	assert_almost_eq(target.health, 0.0, "overkill should clamp health at zero")


func test_poison_effect_applies_its_duration() -> void:
	resolver.apply_spell_effect(_spell("poison"), target)
	assert_almost_eq(
		target.poison_seconds_remaining, 8.0, "poison should apply an 8s duration"
	)


func test_paralyze_effect_applies_its_duration() -> void:
	resolver.apply_spell_effect(_spell("paralyze"), target)
	assert_almost_eq(
		target.paralyze_seconds_remaining, 4.0, "paralyze should apply a 4s duration"
	)


func test_paralyze_deals_no_direct_damage() -> void:
	var before := target.health
	resolver.apply_spell_effect(_spell("paralyze"), target)
	assert_almost_eq(target.health, before, "paralyze is control, not damage")


# ── full resolution: LOS gate + effect ────────────────────────────────────────

func test_unobstructed_cast_damages_target() -> void:
	await get_tree().physics_frame
	var before := target.health
	var connected := resolver.resolve_cast(caster, target, _spell("magic_arrow"))
	assert_true(connected, "clear shot should report a connection")
	assert_almost_eq(target.health, before - 12.0, "magic arrow should land")


func test_obstructed_cast_deals_no_damage() -> void:
	_add_wall_between()
	await get_tree().physics_frame
	var before := target.health
	var connected := resolver.resolve_cast(caster, target, _spell("magic_arrow"))
	assert_false(connected, "cover should stop the spell connecting")
	assert_almost_eq(target.health, before, "spell behind cover deals nothing")


func test_connecting_spell_interrupts_targets_cast() -> void:
	await get_tree().physics_frame
	target.entity_state.try_start_cast(_spell("flamestrike"))
	resolver.resolve_cast(caster, target, _spell("magic_arrow"))
	assert_eq(
		target.entity_state.current_state,
		EntityState.State.INTERRUPTED,
		"taking a hit mid-cast should interrupt"
	)


func test_obstructed_spell_does_not_interrupt_targets_cast() -> void:
	_add_wall_between()
	await get_tree().physics_frame
	target.entity_state.try_start_cast(_spell("flamestrike"))
	resolver.resolve_cast(caster, target, _spell("magic_arrow"))
	assert_eq(
		target.entity_state.current_state,
		EntityState.State.CASTING,
		"a spell stopped by cover must not interrupt the target"
	)


func test_spell_ignoring_line_of_sight_connects_through_cover() -> void:
	_add_wall_between()
	await get_tree().physics_frame
	var spell := _spell("magic_arrow").duplicate() as SpellData
	spell.requires_line_of_sight = false
	var before := target.health
	assert_true(
		resolver.resolve_cast(caster, target, spell),
		"a spell flagged as not needing LOS should connect anyway"
	)
	assert_almost_eq(target.health, before - 12.0, "and still deal its damage")
