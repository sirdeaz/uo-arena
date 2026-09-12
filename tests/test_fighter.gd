extends TestCase

## `client/scenes/fighter.tscn` is authored now, not built in `Fighter._ready()`, and it
## inherits `common/body_base.tscn` for the circle and the collision layers. These pin
## the authored nodes to the code-side source of truth — `client/art/wizard_frames.tres`
## for the character's animations, `SpellFX` for the aura material, the `FighterChrome`
## script for the overhead measurements — so a change to one the scene did not follow
## fails here rather than as a fighter who hops, vanishes, or stops colliding. The shared
## body radius and layer bits are pinned once in `tests/test_body_base.gd`; this is the
## client-side twin of `tests/test_player_body.gd`.

const FIGHTER_SCENE := preload("res://client/scenes/fighter.tscn")
const FRAMES := preload("res://client/art/wizard_frames.tres")
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
		"the Character node must play the authored wizard_frames.tres, not a copy"
	)
	assert_false(
		character.centered,
		"a centred 79x65 cell lands the feet on a half-pixel and blurs the pixel art"
	)
	assert_eq(
		character.offset,
		Vector2(-31.0, -49.0),
		"the authored offset must stand the pack's registered feet on the body origin"
	)
	assert_eq(
		character.animation,
		&"idle_down",
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
	var character_index := fighter.get_node("Character").get_index()
	var fx_index := fighter.get_node("FX").get_index()
	var ui_index := fighter.get_node("UI").get_index()
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


# ── corrected_position ──────────────────────────────────────────────────────────────
#
# Static, so the reconciliation curve is checked directly rather than by puppeting a
# scene tree through a fake network round trip.


func test_player_controlled_does_not_fight_honest_lag_below_the_dead_zone() -> void:
	var current := Vector2(100.0, 100.0)
	var target := current + Vector2(Fighter.CORRECTION_THRESHOLD - 1.0, 0.0)
	assert_eq(
		Fighter.corrected_position(current, target, 1.0 / 60.0, true),
		current,
		"drift under CORRECTION_THRESHOLD must be left alone, or honest lag gets nagged at"
	)


func test_player_controlled_lerps_rather_than_snaps_past_the_dead_zone() -> void:
	var current := Vector2(100.0, 100.0)
	var target := current + Vector2(Fighter.CORRECTION_THRESHOLD + 10.0, 0.0)
	var corrected := Fighter.corrected_position(current, target, 1.0 / 60.0, true)
	assert_true(
		corrected != current and corrected != target,
		"past the dead zone this must ease toward the server, not sit still or snap"
	)


func test_a_lost_stop_packet_alone_does_not_trip_the_teleport_snap() -> void:
	# The exact worst case `server/arena_server.gd`'s own input timeout already admits
	# to and tolerates as normal — see MAX_HONEST_DRIFT's doc comment. Before #89 this
	# sat past TELEPORT_THRESHOLD (120.0) and hard-snapped on every ordinary WAN hiccup.
	var current := Vector2(100.0, 100.0)
	var target := current + Vector2(Fighter.MAX_HONEST_DRIFT, 0.0)
	var corrected := Fighter.corrected_position(current, target, 1.0 / 60.0, true)
	assert_true(
		corrected != target,
		"the server's own documented worst-case drift must not read as a teleport"
	)


func test_past_teleport_threshold_snaps_outright() -> void:
	var current := Vector2(100.0, 100.0)
	var target := current + Vector2(Fighter.TELEPORT_THRESHOLD + 1.0, 0.0)
	assert_eq(
		Fighter.corrected_position(current, target, 1.0 / 60.0, true),
		target,
		"a respawn-sized jump must snap outright, not slide the body across the arena"
	)


func test_a_remote_fighter_tracks_even_drift_under_the_dead_zone() -> void:
	# Nobody predicts a remote fighter, so unlike the local player it has no dead zone —
	# it is always easing toward the last snapshot, however small the step.
	var current := Vector2(100.0, 100.0)
	var target := current + Vector2(Fighter.CORRECTION_THRESHOLD - 1.0, 0.0)
	var corrected := Fighter.corrected_position(current, target, 1.0 / 60.0, false)
	assert_true(
		corrected != current,
		"a remote fighter must smooth toward drift a local player would ignore"
	)
