extends TestCase

## `client/scenes/fighter.tscn` is authored now, not built in `Fighter._ready()`. These
## pin the authored numbers to the code-side source of truth — `common/constants.gd` for
## the body, `client/art/wizard.tres` for where the sprite sits, `SpellFX` for the aura
## material, the `FighterChrome` script for the overhead measurements — so a change to one
## the scene did not follow fails here rather than as a fighter who hops, vanishes, or
## stops colliding. It is the client-side twin of `tests/test_player_body.gd`.

const FIGHTER_SCENE := preload("res://client/scenes/fighter.tscn")
const SPRITE := preload("res://client/art/wizard.tres")
const CHROME := preload("res://client/art/fighter_chrome.tres")

var fighter: Fighter


func before_each() -> void:
	fighter = FIGHTER_SCENE.instantiate()
	add_child(fighter)


func after_each() -> void:
	fighter.queue_free()


func test_it_sits_on_the_players_layer_and_collides_only_with_obstacles() -> void:
	assert_eq(
		fighter.collision_layer,
		Constants.LAYER_PLAYERS,
		"the client body must be on the players layer, the same as server/player_body.tscn"
	)
	assert_eq(
		fighter.collision_mask,
		Constants.LAYER_OBSTACLES,
		"it must collide with cover only — players pass through each other and block no spell"
	)


func test_its_circle_is_exactly_the_shared_player_radius() -> void:
	var shape_node := fighter.get_node("CollisionShape2D") as CollisionShape2D
	assert_true(shape_node != null, "the authored fighter needs a CollisionShape2D child")
	var circle := shape_node.shape as CircleShape2D
	assert_true(circle != null, "the footprint should be a circle, like the server body")
	assert_almost_eq(
		circle.radius,
		Constants.PLAYER_RADIUS,
		"the authored radius has drifted from Constants.PLAYER_RADIUS"
	)


func test_the_character_node_stands_frame_zero_where_the_atlas_says() -> void:
	var character := fighter.get_node("Character") as Sprite2D
	assert_true(character != null, "the mage must be a Sprite2D the editor can select")
	assert_false(
		character.centered,
		"a centred 79x65 cell lands the feet on a half-pixel and blurs the pixel art"
	)
	assert_true(character.region_enabled, "the Sprite2D shows one cell out of the strip")
	assert_eq(
		character.region_rect,
		SPRITE.region_for(0),
		"the authored cell has drifted from wizard.tres frame 0"
	)
	assert_eq(
		character.offset,
		-SPRITE.anchor(FighterSprite.Facing.DOWN),
		"the authored offset must stand frame 0's feet on the body origin"
	)
	assert_eq(
		character.texture_filter,
		CanvasItem.TEXTURE_FILTER_PARENT_NODE,
		"the mage samples nearest like the rest of the game — it must not override the filter"
	)
	assert_eq(
		character.texture,
		SPRITE.texture,
		"the authored atlas should be the texture wizard.tres itself points at"
	)


func test_the_fx_layer_sits_at_the_chest_with_the_additive_material() -> void:
	var fx := fighter.get_node("FX") as Node2D
	assert_true(fx != null, "the aura needs its own layer above the character")
	assert_eq(
		fx.position,
		SPRITE.chest,
		"the FX layer has drifted from wizard.tres chest — the aura will pool at the ankles"
	)
	var material := fx.material as CanvasItemMaterial
	assert_true(material != null, "without a material the additive glow just tints the robe")
	assert_eq(
		material.blend_mode,
		SpellFX.additive_material().blend_mode,
		"the authored FX material must stay the additive one SpellFX defines"
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


func test_a_sceneless_fighter_still_stands_up() -> void:
	var bare := Fighter.new()
	add_child(bare)
	assert_true(
		bare.sprite != null,
		"a bare Fighter.new() must still load the default atlas"
	)
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
