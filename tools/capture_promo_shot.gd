extends Node

## Renders the arena into a still image, used for the browser build's link preview.
##
##   xvfb-run -a godot --resolution 1280x720 res://tools/capture_promo_shot.tscn \
##       -- --out build/web/og-image.png
##
## Needs a display: it captures a real rendered frame, so `--headless` will not do. CI
## wraps it in xvfb, and the deploy fails if no image comes out — a stated `og:image`
## that 404s unfurls worse than none at all.
##
## Excluded from every export (see `export_presets.cfg`) — this is build tooling, not
## part of the game. It poses the real `local_test` scene rather than mocking one up, so
## the preview image can never show something the game does not actually look like.

const WIDTH: int = 1200
const HEIGHT: int = 630
const DEFAULT_OUT := "build/web/og-image.png"

## Far enough into each cast for the progress ring, orbiting runes and mantra to all be
## on screen, and short of the release that would clear them.
const DUMMY_CAST_PROGRESS: float = 0.62
const PLAYER_CAST_PROGRESS: float = 0.38


func _ready() -> void:
	var scene: Node2D = load("res://client/scenes/local_test.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame

	_pose(scene)

	# Let the pose settle and the fighters redraw before grabbing the frame.
	for _i in 4:
		await get_tree().process_frame
	_frame_camera(scene)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	_save(_letterbox_to_target(image), _output_path())

	# Tear the posed scene down before quitting, so the run exits without complaining
	# about leaked objects.
	scene.free()
	get_tree().quit(0)


## Freeze a moment that says what the game is: the dummy two thirds of the way into a
## flamestrike with the words overhead, a lightning already in the air, and the sight
## line running between them.
func _pose(scene: Node2D) -> void:
	scene.player.position = Vector2(-330.0, 60.0)
	scene.dummy.position = Vector2(360.0, -60.0)

	_hold_cast(scene.dummy, "flamestrike", DUMMY_CAST_PROGRESS)
	_hold_cast(scene.player, "lightning", PLAYER_CAST_PROGRESS)

	# A bolt in flight, added through the same call the game uses, so the preview cannot
	# show an effect the game could not produce.
	scene._bolts.add_effect(
		scene.player.position,
		scene.dummy.position,
		load("res://common/spells/lightning.tres")
	)

	scene.player.combatant.health = 74.0
	scene.dummy.combatant.health = 52.0
	scene._last_event = "you cast Lightning — hit"

	scene.player.queue_redraw()
	scene.dummy.queue_redraw()


## In game the camera rides the local player; a promo still wants both fighters and the
## sight line between them. Stop the harness's per-frame follow and centre the shot on
## the pair, through the same clamp the game uses.
func _frame_camera(scene: Node2D) -> void:
	scene.set_process(false)
	var camera := scene.get_node("Stage/Camera2D") as Camera2D
	camera.global_position = ArenaStage.camera_target(
		(scene.player.position + scene.dummy.position) * 0.5,
		scene.map.bounds(),
		camera.get_viewport_rect().size / camera.zoom,
	)


func _hold_cast(fighter: Fighter, spell_name: String, progress: float) -> void:
	var spell: SpellData = load("res://common/spells/%s.tres" % spell_name)
	var state := fighter.combatant.entity_state
	state.try_start_cast(spell)
	state.cast_time_elapsed = spell.cast_time_seconds * progress
	# Stop the timers so the pose survives the frames spent waiting for the draw.
	state.set_process(false)
	fighter.set_physics_process(false)
	# Physics is what normally drives the sprite; call it once by hand so the mage holds
	# the cast frame for this progress instead of whatever it was last playing.
	fighter._update_character_animation()


## Crop the rendered frame to the preview's aspect ratio and scale it to size. Cropping
## before scaling keeps the arena's proportions honest instead of squashing it.
func _letterbox_to_target(image: Image) -> Image:
	var target_aspect := float(WIDTH) / float(HEIGHT)
	var width := image.get_width()
	var height := image.get_height()
	var cropped_height := int(round(float(width) / target_aspect))

	if cropped_height < height:
		image = image.get_region(
			Rect2i(0, (height - cropped_height) / 2, width, cropped_height)
		)
	elif cropped_height > height:
		var cropped_width := int(round(float(height) * target_aspect))
		image = image.get_region(
			Rect2i((width - cropped_width) / 2, 0, cropped_width, height)
		)

	image.resize(WIDTH, HEIGHT, Image.INTERPOLATE_LANCZOS)
	return image


func _output_path() -> String:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--out")
	if index >= 0 and index + 1 < args.size():
		return args[index + 1]
	return DEFAULT_OUT


func _save(image: Image, path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := image.save_png(absolute)
	if error != OK:
		push_error("Could not write %s (error %d)" % [absolute, error])
		get_tree().quit(1)
		return
	print("wrote %s (%dx%d)" % [absolute, image.get_width(), image.get_height()])
