extends TestCase

## Which player a spell actually flies at, once there is more than one to choose from.
##
## This is the subtle one. The practice harness binds a fixed opponent at startup, so
## the question never came up; with a roster it does, and the fizzle chain makes it
## genuinely tricky — the spell that *starts* is usually not the one most recently asked
## for. The aim is committed when a cast truly begins, which is what these pin.

const ARROW := 0
const FLAMESTRIKE := 3

var server: ArenaServer


func before_each() -> void:
	server = ArenaServer.new()
	add_child(server)


func after_each() -> void:
	server.queue_free()


func _place(peer_id: int, at: Vector2) -> void:
	server.body_of(peer_id).global_position = at
	server.combatant_of(peer_id).position = at


## One caster at the west end with a clear shot at two opponents at the east end. Both
## sight lines pass either side of the centre tents rather than through them.
func _trio() -> void:
	server.add_player(2)
	server.add_player(3)
	server.add_player(4)
	_place(2, Vector2(-500.0, 0.0))
	_place(3, Vector2(500.0, 60.0))
	_place(4, Vector2(500.0, -60.0))
	await get_tree().physics_frame


func _run(seconds: float) -> void:
	var step := 1.0 / 60.0
	var elapsed := 0.0
	while elapsed < seconds:
		server.step(step)
		elapsed += step


func _health(peer_id: int) -> float:
	return server.combatant_of(peer_id).health


func test_a_chained_spell_flies_at_the_target_named_with_it() -> void:
	await _trio()

	# Open a long cast at 3, then recast at 4 partway through. The flamestrike fizzles,
	# a recovery is paid, and the arrow begins — aimed at 4, who was named with it.
	server.request_cast(2, FLAMESTRIKE, 3)
	await _run(0.5)
	assert_true(server.request_cast(2, ARROW, 4), "recasting mid-cast is allowed")

	await _run(Constants.GLOBAL_CAST_RECOVERY_SECONDS + 1.2)

	assert_true(_health(4) < Constants.PLAYER_MAX_HEALTH, "the chained arrow hit 4")
	assert_almost_eq(
		_health(3),
		Constants.PLAYER_MAX_HEALTH,
		"the fizzled spell's target must not be hit by the spell that replaced it"
	)


func test_a_refused_request_does_not_steal_the_aim() -> void:
	await _trio()
	server.request_cast(2, FLAMESTRIKE, 3)
	await _run(0.5)

	# 4 slips behind the south tent, so casting at them is refused. A refusal costs
	# nothing — and "nothing" has to include the aim of the spell already in the air.
	_place(4, Vector2(500.0, 280.0))
	await get_tree().physics_frame
	assert_false(server.request_cast(2, ARROW, 4), "there is no line to 4")

	await _run(2.2)
	assert_true(_health(3) < Constants.PLAYER_MAX_HEALTH, "the flamestrike still hit 3")
	assert_almost_eq(_health(4), Constants.PLAYER_MAX_HEALTH, "and never touched 4")


func test_switching_target_before_a_cast_starts_is_honoured() -> void:
	await _trio()
	# Nothing is in the air, so the second request simply replaces the first.
	server.request_cast(2, ARROW, 3)
	server.request_cast(2, ARROW, 4)
	await _run(Constants.GLOBAL_CAST_RECOVERY_SECONDS + 1.2)

	assert_true(_health(4) < Constants.PLAYER_MAX_HEALTH, "the arrow went to 4")
	assert_almost_eq(_health(3), Constants.PLAYER_MAX_HEALTH, "3 was never hit")


func test_a_target_dying_mid_cast_leaves_the_spell_with_nowhere_to_go() -> void:
	await _trio()
	server.request_cast(2, FLAMESTRIKE, 3)
	await _run(0.5)
	server.combatant_of(3).take_damage(Constants.PLAYER_MAX_HEALTH)

	await _run(2.2)
	assert_almost_eq(
		_health(4), Constants.PLAYER_MAX_HEALTH, "it must not wander onto someone else"
	)
	assert_eq(
		server.combatant_of(2).entity_state.current_state,
		EntityState.State.IDLE,
		"and the caster is left idle rather than stuck"
	)
