extends TestCase

## `ArenaHud` is the chrome both clients share, and the thing worth pinning about it is
## *when* the cast bar may be bound.
##
## The practice harness has its player before the UI exists, so it binds straight away.
## `ArenaClient` cannot: the local fighter only appears with the server's first roster,
## so its binding happens much later. A HUD that bound during `_ready()` would look
## perfect offline and show a dead cast bar in every networked fight — and nothing on
## screen distinguishes a bar that was never bound from one whose caster is simply idle.

var hud: ArenaHud
var caster: Combatant


func before_each() -> void:
	hud = ArenaHud.new()
	caster = Combatant.new()
	add_child(caster)


func after_each() -> void:
	hud.queue_free()
	caster.queue_free()


func _state() -> EntityState:
	return caster.entity_state


# ── Binding ───────────────────────────────────────────────────────────────────────


func test_a_cast_bar_bound_after_the_hud_is_built_is_really_bound() -> void:
	# The multiplayer path: HUD first, caster later.
	add_child(hud)
	hud.bind_cast_bar(_state())
	assert_eq(
		hud.cast_bar.bound_state(),
		_state(),
		"a cast bar bound after the HUD exists should be showing that caster"
	)


func test_binding_before_the_hud_enters_the_tree_still_lands() -> void:
	# A caller holding a HUD it has not added yet should not silently lose the binding.
	hud.bind_cast_bar(_state())
	add_child(hud)
	assert_eq(
		hud.cast_bar.bound_state(),
		_state(),
		"a binding asked for before the HUD was in the tree should survive into it"
	)


func test_binding_the_same_caster_twice_connects_it_only_once() -> void:
	# `CastBarUI.bind` connects four signals, and Godot errors on a duplicate connection.
	add_child(hud)
	hud.bind_cast_bar(_state())
	hud.bind_cast_bar(_state())
	assert_eq(
		_state().cast_started.get_connections().size(),
		1,
		"binding the same caster twice should not stack a second set of handlers"
	)


func test_rebinding_follows_the_new_caster() -> void:
	# A peer that leaves and rejoins arrives with a fresh state; the bar has to move to
	# it, or it keeps showing a fighter that no longer exists.
	add_child(hud)
	hud.bind_cast_bar(_state())

	var replacement := Combatant.new()
	add_child(replacement)
	hud.bind_cast_bar(replacement.entity_state)

	assert_eq(
		hud.cast_bar.bound_state(),
		replacement.entity_state,
		"the bar should follow the caster it was last given"
	)
	replacement.queue_free()


func test_binding_nothing_leaves_the_bar_alone() -> void:
	# Draw code runs before a roster arrives; a null must not clear a live binding.
	add_child(hud)
	hud.bind_cast_bar(_state())
	hud.bind_cast_bar(null)
	assert_eq(
		hud.cast_bar.bound_state(), _state(), "a null binding should not unbind the bar"
	)


# ── Layout ────────────────────────────────────────────────────────────────────────


## The project stretches with `aspect="keep"`, so the logical viewport is 1280×720
## whatever the window does — measured, not assumed. That is why the old absolute y of
## 640 never visibly broke, and it is also why asserting against the real viewport would
## prove nothing: 640 simply *is* 720 minus the gap.
##
## So these put the HUD in a viewport of a deliberately different size. That is the only
## way to tell a bar that is anchored from one that happens to be sitting in the right
## place.
const PROBE_SIZE := Vector2i(800, 400)


func _in_probe_viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = PROBE_SIZE
	add_child(viewport)
	viewport.add_child(hud)
	return viewport


func test_the_cast_bar_hangs_off_the_bottom_left_corner() -> void:
	var viewport := _in_probe_viewport()
	await get_tree().process_frame

	var expected_top := (
		float(PROBE_SIZE.y) - ArenaHud.CAST_BAR_BOTTOM_GAP - ArenaHud.CAST_BAR_SIZE.y
	)
	assert_almost_eq(
		hud.cast_bar.position.y,
		expected_top,
		"the cast bar should hold its gap above the bottom edge in a viewport of any height",
		0.5
	)
	assert_almost_eq(
		hud.cast_bar.position.x,
		ArenaHud.MARGIN,
		"and stay one shared margin in from the left",
		0.5
	)
	viewport.queue_free()


func test_the_cast_bar_keeps_the_size_it_was_given() -> void:
	# Anchoring to a corner must not stretch the bar toward it.
	var viewport := _in_probe_viewport()
	await get_tree().process_frame
	assert_almost_eq(
		hud.cast_bar.size.x, ArenaHud.CAST_BAR_SIZE.x, "the bar's width is its own", 0.5
	)
	assert_almost_eq(
		hud.cast_bar.size.y, ArenaHud.CAST_BAR_SIZE.y, "and so is its height", 0.5
	)
	viewport.queue_free()


func test_the_readout_starts_at_the_same_margin_as_the_bar() -> void:
	# The two rows share one left edge; that is the whole reason `MARGIN` is a constant
	# rather than a number typed twice.
	var viewport := _in_probe_viewport()
	await get_tree().process_frame
	assert_almost_eq(
		hud.readout.position.x,
		hud.cast_bar.position.x,
		"the readout and the cast bar should line up down one margin",
		0.5
	)
	viewport.queue_free()


# ── Readout ───────────────────────────────────────────────────────────────────────


func test_the_readout_shows_what_it_is_given() -> void:
	# The HUD holds no opinion about the text: each client reports different things, and
	# sharing the copy as well as the chrome would mean one builder serving two games.
	add_child(hud)
	hud.set_readout("line of sight: BLOCKED")
	assert_eq(
		hud.readout.text,
		"line of sight: BLOCKED",
		"the readout should carry exactly the text the client composed"
	)
