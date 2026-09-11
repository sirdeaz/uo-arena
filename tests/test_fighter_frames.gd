extends TestCase

## `client/art/wizard_frames.tres` is the `SpriteFrames` the `Character` `AnimatedSprite2D`
## plays. It is authored in the editor now, so these re-measure it against the committed
## `wizard.png` — swap the pack in the inspector and this file re-checks whatever the
## `.tres` points at, the way `test_fighter_sprite.gd` used to for the old atlas resource.
##
## The failure each one guards is invisible to a test of the drawing code: a set that
## reads off the end of the strip makes a fighter vanish mid-spell; a left set that keeps
## its 3.6 px offset makes a fighter hop sideways every time it turns; a cast set that
## loops turns the wind-up into a spinning animation instead of a read on progress.

const IDLE := Fighter.Anim.IDLE
const WALK := Fighter.Anim.WALK
const CAST := Fighter.Anim.CAST
const HEADINGS := [
	Fighter.Facing.DOWN, Fighter.Facing.UP,
	Fighter.Facing.LEFT, Fighter.Facing.RIGHT,
]

const ALPHA_FLOOR: float = 16.0 / 255.0
const HEM_ROWS: int = 16

## How far a heading's measured standing point may sit from the others. A cast set leans
## into the spell by a pixel or two on purpose; a set drawn from the wrong registration is
## out by three or more.
const REGISTRATION_TOLERANCE: float = 2.5

## The first channel frame. The pack's staff-raised channel set (frames 40-45) is
## deliberately unused — the game already announces a cast with the mantra and an aura in
## the spell's own colour. No animation the client can play may reach into it.
const CHANNEL_FIRST_FRAME: int = 40

var _frames: SpriteFrames
var _png: Image


func before_each() -> void:
	_frames = load("res://client/art/wizard_frames.tres")
	_png = (load("res://client/art/wizard.png") as Texture2D).get_image()


func _frame_atlas(anim: StringName, index: int) -> AtlasTexture:
	return _frames.get_frame_texture(anim, index) as AtlasTexture


## The standing point of one frame, in the coordinates the AnimatedSprite2D draws it in:
## the hem centroid of the atlas region, shifted by the AtlasTexture margin that corrects
## a heading's registration.
func _standing_x(at: AtlasTexture) -> float:
	var region := at.region
	var bottom := -1
	for y in int(region.size.y):
		for x in int(region.size.x):
			var a := _png.get_pixel(int(region.position.x) + x, int(region.position.y) + y).a
			if a > ALPHA_FLOOR:
				bottom = maxi(bottom, y)
	if bottom < 0:
		return -1.0
	var sum := 0.0
	var count := 0
	for y in range(maxi(0, bottom - HEM_ROWS + 1), bottom + 1):
		for x in int(region.size.x):
			var a := _png.get_pixel(int(region.position.x) + x, int(region.position.y) + y).a
			if a > ALPHA_FLOOR:
				sum += float(x)
				count += 1
	return sum / float(count) + at.margin.position.x


func test_every_posture_and_heading_the_client_can_play_exists() -> void:
	for anim in [IDLE, WALK, CAST]:
		for facing in HEADINGS:
			var name := Fighter.animation_name(anim, facing)
			assert_true(
				_frames.has_animation(name),
				"wizard_frames.tres has no animation '%s' — the fighter would play nothing" % name
			)


func test_walk_and_idle_run_six_frames_and_a_cast_runs_four() -> void:
	for facing in HEADINGS:
		assert_eq(
			_frames.get_frame_count(Fighter.animation_name(WALK, facing)), 6,
			"a walk set is six frames in this pack"
		)
		assert_eq(
			_frames.get_frame_count(Fighter.animation_name(IDLE, facing)), 6,
			"idle plays the same six frames as the walk"
		)
		assert_eq(
			_frames.get_frame_count(Fighter.animation_name(CAST, facing)), 4,
			"a cast set is four frames"
		)


func test_no_frame_reads_off_the_atlas() -> void:
	var size := _png.get_size()
	for anim in _frames.get_animation_names():
		for index in _frames.get_frame_count(anim):
			var region := _frame_atlas(anim, index).region
			assert_true(
				region.end.x <= size.x and region.end.y <= size.y,
				"animation '%s' frame %d reads past the edge of the atlas" % [anim, index]
			)


func test_no_frame_the_client_can_play_is_blank() -> void:
	# Reading past the end of a set would land on transparent atlas and the fighter would
	# vanish mid-walk or mid-spell.
	for anim in [IDLE, WALK, CAST]:
		for facing in HEADINGS:
			var name := Fighter.animation_name(anim, facing)
			for index in _frames.get_frame_count(name):
				assert_true(
					_standing_x(_frame_atlas(name, index)) >= 0.0,
					"animation '%s' frame %d is blank" % [name, index]
				)


func test_every_heading_stands_in_the_same_place() -> void:
	# The measurement that matters: with the per-heading margin applied, every walk set's
	# feet land at the same x, so a fighter does not hop sideways when it turns. Walk
	# frames only — a staff or a flame dipping below the hem of a cast frame makes its
	# lowest row something other than the feet.
	var reference := _standing_x(_frame_atlas(Fighter.animation_name(WALK, HEADINGS[0]), 0))
	for facing in HEADINGS:
		var name := Fighter.animation_name(WALK, facing)
		for index in _frames.get_frame_count(name):
			var standing := _standing_x(_frame_atlas(name, index))
			assert_true(
				absf(standing - reference) <= REGISTRATION_TOLERANCE,
				"'%s' frame %d stands at x=%.1f, not near %.1f — fighters will hop when they turn" % [
					name, index, standing, reference
				]
			)


func test_the_left_set_carries_its_own_correction() -> void:
	# The one adjustment in the pack. If a refactor drops the margin on the left frames
	# this fails, and the left-facing walk starts hopping again.
	var left := _frame_atlas(Fighter.animation_name(WALK, Fighter.Facing.LEFT), 0)
	var down := _frame_atlas(Fighter.animation_name(WALK, Fighter.Facing.DOWN), 0)
	assert_true(
		left.margin.position.x > 0.0,
		"the left set sits ~3.6px left in its cells and needs a margin to pull it back"
	)
	assert_almost_eq(
		down.margin.position.x, 0.0,
		"the other headings register within a pixel and take no correction"
	)


func test_the_channel_frames_are_left_alone() -> void:
	for anim in _frames.get_animation_names():
		for index in _frames.get_frame_count(anim):
			var region := _frame_atlas(anim, index).region
			var frame := int(round(region.position.x / region.size.x))
			assert_true(
				frame < CHANNEL_FIRST_FRAME,
				"animation '%s' frame %d reaches into the unused channel set" % [anim, index]
			)


func test_idle_plays_slower_than_walk() -> void:
	for facing in HEADINGS:
		assert_true(
			_frames.get_animation_speed(Fighter.animation_name(IDLE, facing))
			< _frames.get_animation_speed(Fighter.animation_name(WALK, facing)),
			"idle should tick over gently — a paced walk, not a frozen frame"
		)


func test_a_cast_set_does_not_loop() -> void:
	# A finished cast has to hold its last frame — the mage leaning into a spell that is
	# about to land — not restart the wind-up.
	for facing in HEADINGS:
		assert_false(
			_frames.get_animation_loop(Fighter.animation_name(CAST, facing)),
			"a cast set that loops turns the wind-up into a spin"
		)
