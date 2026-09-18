extends TestCase

## `client/scenes/fighter.tscn` is authored now, not built in `Fighter._ready()`, and it
## inherits `common/body_base.tscn` for the circle and the collision layers. These pin
## the authored nodes to the code-side source of truth — `client/art/mage_frames.tres`
## for the character's animations, `SpellFX` for the aura material, the `FighterChrome`
## script for the overhead measurements — so a change to one the scene did not follow
## fails here rather than as a fighter who hops, vanishes, or stops colliding. The shared
## body radius and layer bits are pinned once in `tests/test_body_base.gd`; this is the
## client-side twin of `tests/test_player_body.gd`.

const FIGHTER_SCENE := preload("res://client/scenes/fighter.tscn")
const FRAMES := preload("res://client/art/mage_frames.tres")
const CHROME := preload("res://client/art/fighter_chrome.tres")

var fighter: Fighter


func before_each() -> void:
	fighter = FIGHTER_SCENE.instantiate()
	add_child(fighter)


func after_each() -> void:
	fighter.queue_free()


func test_it_inherits_the_shared_body_base() -> void:
	# The circle and layer numbers are pinned in tests/test_body_base.gd. This only
	# checks the inheritance came through — an inherited-scene override that does not
	# survive re-import fails here rather than as a fighter who stops colliding.
	assert_true(fighter is Fighter, "the inherited scene must still resolve to Fighter")
	var shape_node := fighter.get_node_or_null("CollisionShape2D") as CollisionShape2D
	assert_true(
		shape_node != null and shape_node.shape is CircleShape2D,
		"the base's CollisionShape2D must come through the inheritance"
	)
	assert_eq(
		fighter.collision_mask,
		Constants.LAYER_OBSTACLES,
		"the base's collision mask must come through the inheritance"
	)


func test_the_character_is_an_animated_sprite_playing_the_authored_pack() -> void:
	var character := fighter.get_node("Character") as AnimatedSprite2D
	assert_true(character != null, "the mage must be an AnimatedSprite2D the editor can drive")
	assert_eq(
		character.sprite_frames,
		FRAMES,
		"the Character node must play the authored mage_frames.tres, not a copy"
	)
	assert_true(
		character.centered,
		"a centred, even 70x70 cell needs no manual offset and mirrors safely for flip_h"
	)
	assert_eq(
		character.offset,
		Vector2(0.0, -34.0),
		"the authored offset must stand the pack's registered feet on the body origin"
	)
	assert_eq(
		character.animation,
		&"idle",
		"a fighter that has not moved yet faces the camera, standing"
	)
	assert_eq(
		character.texture_filter,
		CanvasItem.TEXTURE_FILTER_PARENT_NODE,
		"the mage samples nearest like the rest of the game — it must not override the filter"
	)


func test_the_fx_layer_sits_at_the_chest_with_the_additive_material() -> void:
	var fx := fighter.get_node("FX") as Node2D
	assert_true(fx != null, "the aura needs its own layer above the character")
	assert_eq(
		fx.position,
		CHROME.chest,
		"the FX layer has drifted from fighter_chrome.tres chest — the aura will pool at the ankles"
	)
	var material := fx.material as CanvasItemMaterial
	assert_true(material != null, "without a material the additive glow just tints the robe")
	assert_eq(
		material.blend_mode,
		CanvasItemMaterial.BLEND_MODE_ADD,
		"the authored FX material must stay additive"
	)


func test_the_ui_layer_keeps_linear_filtering_for_the_mantra() -> void:
	var ui := fighter.get_node("UI") as Node2D
	assert_true(ui != null, "the reads need their own layer above the aura")
	assert_eq(
		ui.texture_filter,
		CanvasItem.TEXTURE_FILTER_LINEAR,
		"the mantra is downscaled Uncial — nearest sampling makes it crawl"
	)


func test_the_layers_draw_in_reading_order() -> void:
	var shadow_index := fighter.get_node("Shadow").get_index()
	var character_index := fighter.get_node("Character").get_index()
	var fx_index := fighter.get_node("FX").get_index()
	var ui_index := fighter.get_node("UI").get_index()
	assert_true(
		shadow_index < character_index,
		"the ground shadow must draw under the character, so Shadow comes first"
	)
	assert_true(
		character_index < fx_index,
		"the aura must draw over the character, so FX comes after it in the tree"
	)
	assert_true(
		fx_index < ui_index,
		"health and status must draw over the aura, so UI comes last"
	)


func test_the_authored_chrome_matches_the_script_defaults() -> void:
	var defaults := FighterChrome.new()
	assert_almost_eq(
		CHROME.health_bar_width,
		defaults.health_bar_width,
		"fighter_chrome.tres health_bar_width has drifted from the FighterChrome default"
	)
	assert_almost_eq(
		CHROME.overhead_gap,
		defaults.overhead_gap,
		"fighter_chrome.tres overhead_gap has drifted from the FighterChrome default"
	)
	assert_almost_eq(
		CHROME.footing_rim_width,
		defaults.footing_rim_width,
		"fighter_chrome.tres footing_rim_width has drifted from the FighterChrome default"
	)
	assert_almost_eq(
		CHROME.head_top,
		defaults.head_top,
		"fighter_chrome.tres head_top has drifted from the FighterChrome default"
	)
	assert_eq(
		CHROME.chest,
		defaults.chest,
		"fighter_chrome.tres chest has drifted from the FighterChrome default"
	)


func test_a_sceneless_fighter_still_stands_up() -> void:
	var bare := Fighter.new()
	add_child(bare)
	assert_true(
		bare.chrome != null,
		"a bare Fighter.new() must still load the default chrome"
	)
	await get_tree().physics_frame
	assert_true(
		is_instance_valid(bare),
		"a sceneless fighter must survive a frame without its authored child nodes"
	)
	bare.queue_free()


# ── corrected_position: remote fighters only since #113 ─────────────────────────────
#
# Static, so the remote-fighter reconciliation curve is checked directly rather than by
# puppeting a scene tree through a fake network round trip. The local player no longer
# goes through this at all — see the reconciliation-replay section further down.


func test_a_remote_fighter_tracks_even_the_smallest_drift() -> void:
	# Nobody predicts a remote fighter, so there is no dead zone to sit still inside — it
	# is always easing toward the last snapshot, however small the step.
	var current := Vector2(100.0, 100.0)
	var target := current + Vector2(1.0, 0.0)
	var corrected := Fighter.corrected_position(current, target, 1.0 / 60.0)
	assert_true(
		corrected != current, "a remote fighter must smooth toward even a tiny drift"
	)


func test_a_lost_stop_packet_alone_does_not_trip_the_teleport_snap() -> void:
	# The exact worst case `server/arena_server.gd`'s own input timeout already admits
	# to and tolerates as normal — see MAX_HONEST_DRIFT's doc comment. Before #89 this
	# sat past TELEPORT_THRESHOLD (120.0) and hard-snapped on every ordinary WAN hiccup.
	var current := Vector2(100.0, 100.0)
	var target := current + Vector2(Fighter.MAX_HONEST_DRIFT, 0.0)
	var corrected := Fighter.corrected_position(current, target, 1.0 / 60.0)
	assert_true(
		corrected != target,
		"the server's own documented worst-case drift must not read as a teleport"
	)


func test_past_teleport_threshold_snaps_outright() -> void:
	var current := Vector2(100.0, 100.0)
	var target := current + Vector2(Fighter.TELEPORT_THRESHOLD + 1.0, 0.0)
	assert_eq(
		Fighter.corrected_position(current, target, 1.0 / 60.0),
		target,
		"a respawn-sized jump must snap outright, not slide the body across the arena"
	)


# ── Reconciliation replay: the local player's own path since #113 ───────────────────
#
# `inputs_to_replay`/`trim_input_history` are the decisions, pulled out static so they
# are checkable the same way `movement_direction_toward`/`facing_for` are — no scene
# tree, no fake network round trip.


func test_inputs_at_or_before_the_ack_are_not_replayed() -> void:
	var history: Array[Dictionary] = [
		{"sequence": 0, "direction": Vector2.RIGHT, "can_move": true},
		{"sequence": 1, "direction": Vector2.RIGHT, "can_move": true},
	]
	assert_eq(
		Fighter.inputs_to_replay(history, 1),
		[],
		"the server has already folded everything up to and including the ack"
	)


func test_inputs_after_the_ack_are_replayed_in_order() -> void:
	var history: Array[Dictionary] = [
		{"sequence": 0, "direction": Vector2.RIGHT, "can_move": true},
		{"sequence": 1, "direction": Vector2.UP, "can_move": true},
		{"sequence": 2, "direction": Vector2.DOWN, "can_move": true},
	]
	var replay := Fighter.inputs_to_replay(history, 0)
	assert_eq(replay.size(), 2, "only what came after the ack needs replaying")
	assert_eq(replay[0]["sequence"], 1, "replay must not reorder the buffered history")
	assert_eq(replay[1]["sequence"], 2, "replay must not reorder the buffered history")


func test_no_ack_yet_replays_the_entire_buffer() -> void:
	# -1 is what a fighter starts with before its first snapshot ever names an ack — see
	# `_server_input_ack`'s own doc comment. Nothing is confirmed yet, so nothing is
	# dropped.
	var history: Array[Dictionary] = [
		{"sequence": 0, "direction": Vector2.RIGHT, "can_move": true},
	]
	assert_eq(
		Fighter.inputs_to_replay(history, -1).size(),
		1,
		"with no ack yet, the whole buffer is still unconfirmed"
	)


func test_trimming_keeps_the_newest_entries() -> void:
	var history: Array[Dictionary] = [
		{"sequence": 0, "direction": Vector2.ZERO, "can_move": true},
		{"sequence": 1, "direction": Vector2.ZERO, "can_move": true},
		{"sequence": 2, "direction": Vector2.ZERO, "can_move": true},
	]
	var trimmed := Fighter.trim_input_history(history, 2)
	assert_eq(trimmed.size(), 2, "a long stall must not replay an unbounded backlog")
	assert_eq(trimmed[0]["sequence"], 1, "the oldest entry is what gets dropped")
	assert_eq(trimmed[1]["sequence"], 2, "the newest entries survive the trim")


func test_trimming_under_the_bound_changes_nothing() -> void:
	var history: Array[Dictionary] = [{"sequence": 0, "direction": Vector2.ZERO, "can_move": true}]
	assert_eq(
		Fighter.trim_input_history(history, 10).size(),
		1,
		"a buffer already under the bound must not lose anything"
	)


func test_a_snapshot_resets_the_local_player_to_the_authoritative_position() -> void:
	# The end-to-end replacement for the old lerp-and-hope blend: a drifted-apart local
	# fighter resets outright on the next tick rather than easing back toward the server.
	var fighter := FIGHTER_SCENE.instantiate()
	fighter.server_driven = true
	fighter.player_controlled = true
	add_child(fighter)
	fighter.global_position = Vector2(500.0, 500.0)

	fighter.receive_server_snapshot(Vector2.ZERO, 0)
	await get_tree().physics_frame

	assert_true(
		fighter.global_position.distance_to(Vector2.ZERO) < 1.0,
		"a reconciling local player must land on the server's own position, not ease toward it"
	)
	fighter.queue_free()


# ── prediction_already_agrees: skipping a needless reset+replay since #122 ──────────
#
# Static, so the agreement check itself is checkable the same way `inputs_to_replay` is
# — no scene tree, no physics tick, no fake network round trip.


func test_a_matching_prediction_needs_no_correction() -> void:
	var history: Array[Dictionary] = [
		{"sequence": 0, "direction": Vector2.RIGHT, "can_move": true, "predicted_after": Vector2(10.0, 0.0)},
	]
	assert_true(
		Fighter.prediction_already_agrees(history, 0, Vector2(10.0, 0.0), 0.5),
		"an exact match has nothing left for a reconciliation to fix"
	)


func test_a_prediction_within_tolerance_needs_no_correction() -> void:
	var history: Array[Dictionary] = [
		{"sequence": 0, "direction": Vector2.RIGHT, "can_move": true, "predicted_after": Vector2(10.0, 0.0)},
	]
	assert_true(
		Fighter.prediction_already_agrees(history, 0, Vector2(10.4, 0.0), 0.5),
		"floating-point noise inside the tolerance is not a real misprediction"
	)


func test_a_prediction_outside_tolerance_still_needs_correcting() -> void:
	var history: Array[Dictionary] = [
		{"sequence": 0, "direction": Vector2.RIGHT, "can_move": true, "predicted_after": Vector2(10.0, 0.0)},
	]
	assert_false(
		Fighter.prediction_already_agrees(history, 0, Vector2(40.0, 0.0), 0.5),
		"a real divergence must still be caught, not waved through as noise"
	)


func test_no_stored_prediction_for_the_ack_needs_correcting() -> void:
	# A stall long enough to trim the acked entry out of history, or an ack from before
	# anything was ever recorded — either way there is nothing to compare against, so
	# the safe default is "assume a correction is needed", the same as before #122.
	var history: Array[Dictionary] = [
		{"sequence": 5, "direction": Vector2.RIGHT, "can_move": true, "predicted_after": Vector2(10.0, 0.0)},
	]
	assert_false(
		Fighter.prediction_already_agrees(history, 2, Vector2(10.0, 0.0), 0.5),
		"no stored prediction to check against must never be read as agreement"
	)
	assert_false(
		Fighter.prediction_already_agrees([], -1, Vector2.ZERO, 0.5),
		"an empty history has nothing to compare against either"
	)


# ── prediction_error: the unrounded size behind the agree/disagree call, since #132 ─
#
# `prediction_already_agrees` only ever says yes or no. Measuring how often a real
# correction fires, and how large, needed the actual distance underneath that
# threshold — this is the same lookup, unrounded.


func test_prediction_error_is_the_exact_distance_to_the_authoritative_position() -> void:
	var history: Array[Dictionary] = [
		{"sequence": 0, "direction": Vector2.RIGHT, "can_move": true, "predicted_after": Vector2(10.0, 0.0)},
	]
	assert_almost_eq(
		Fighter.prediction_error(history, 0, Vector2(40.0, 0.0)),
		30.0,
		"the error is the plain distance between the two, not thresholded against anything"
	)


func test_prediction_error_is_negative_with_nothing_to_compare_against() -> void:
	assert_true(
		Fighter.prediction_error([], -1, Vector2.ZERO) < 0.0,
		"no stored prediction reports as unmeasurable, not as a zero-size correction"
	)


# ── Which side of the server the prediction landed on, since #141 ───────────────────
#
# After #140 every live correction is exactly one physics tick, and the magnitude above
# cannot say whether the server stepped one time too few (an input it never simulated) or
# one time too many (a step it took with nothing queued). Those are opposite faults
# wanting opposite fixes, and the sign along the travel direction is what separates them.


func test_the_client_running_further_than_the_server_reads_as_negative() -> void:
	# Predicted 40 travelling right, server only got to 36.25 — one tick short, the
	# signature of an input dropped at the server's cap or lost in flight.
	var history: Array[Dictionary] = [
		{"sequence": 0, "direction": Vector2.RIGHT, "can_move": true, "predicted_after": Vector2(40.0, 0.0)},
	]
	assert_almost_eq(
		Fighter.prediction_error_along_travel(history, 0, Vector2(36.25, 0.0)),
		-3.75,
		"an input the server never stepped leaves the client ahead, and that has to read " +
		"as a different sign from the server having stepped one time too many"
	)


func test_the_server_running_further_than_the_client_reads_as_positive() -> void:
	# The other half: the server re-ran a held direction on a tick with nothing queued,
	# so it travelled a tick further than anything the client predicted.
	var history: Array[Dictionary] = [
		{"sequence": 0, "direction": Vector2.RIGHT, "can_move": true, "predicted_after": Vector2(40.0, 0.0)},
	]
	assert_almost_eq(
		Fighter.prediction_error_along_travel(history, 0, Vector2(43.75, 0.0)),
		3.75,
		"a step the server took with no input entry of its own leaves it ahead of the client"
	)


func test_the_sign_follows_travel_direction_rather_than_the_axes() -> void:
	# Travelling up, where a raw y component would report the opposite sign to the one
	# that means "the server ran further" — the projection is onto the direction, not onto
	# an axis, precisely so a log line means the same thing whichever way a player ran.
	var history: Array[Dictionary] = [
		{"sequence": 0, "direction": Vector2.UP, "can_move": true, "predicted_after": Vector2(0.0, -40.0)},
	]
	assert_almost_eq(
		Fighter.prediction_error_along_travel(history, 0, Vector2(0.0, -43.75)),
		3.75,
		"running further than predicted is positive whichever direction the running was in"
	)


func test_a_standing_tick_has_no_side_to_report() -> void:
	var history: Array[Dictionary] = [
		{"sequence": 0, "direction": Vector2.ZERO, "can_move": true, "predicted_after": Vector2.ZERO},
	]
	assert_almost_eq(
		Fighter.prediction_error_along_travel(history, 0, Vector2(5.0, 0.0)),
		0.0,
		"a tick that was not travelling has no direction to project onto, so no side — " +
		"`prediction_error` is what says whether there was anything to compare at all"
	)


# ── Reconciliation is skipped when it would be a no-op, since #122 ──────────────────


func test_a_snapshot_that_already_matches_prediction_does_not_arm_reconciliation() -> void:
	var fighter := FIGHTER_SCENE.instantiate()
	fighter.server_driven = true
	fighter.player_controlled = true
	add_child(fighter)
	fighter.global_position = Vector2(200.0, 100.0)

	# Tick 0: no input pressed in a headless test, so this fighter simply stands still
	# and records predicted_after = (200, 100) for sequence 0.
	await get_tree().physics_frame

	fighter.receive_server_snapshot(Vector2(200.0, 100.0), 0)
	assert_false(
		fighter.reconciliation_pending(),
		"an ack the client's own prediction already matches must not trigger a burst reset+replay (#122)"
	)
	fighter.queue_free()


func test_a_snapshot_that_disagrees_still_arms_and_resolves_reconciliation() -> void:
	var fighter := FIGHTER_SCENE.instantiate()
	fighter.server_driven = true
	fighter.player_controlled = true
	add_child(fighter)
	fighter.global_position = Vector2(200.0, 100.0)

	await get_tree().physics_frame

	fighter.receive_server_snapshot(Vector2(400.0, 100.0), 0)
	assert_true(
		fighter.reconciliation_pending(),
		"a real misprediction must still be caught, not skipped as if it were noise"
	)

	await get_tree().physics_frame
	assert_true(
		fighter.global_position.distance_to(Vector2(400.0, 100.0)) < 1.0,
		"the skip path must never come at the cost of #113's own convergence guarantee"
	)
	fighter.queue_free()
