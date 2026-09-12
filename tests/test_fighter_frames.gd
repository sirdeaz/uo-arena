extends TestCase

## `client/art/mage_frames.tres` is the `SpriteFrames` the `Character` `AnimatedSprite2D`
## plays. It is authored in the editor now, so these re-measure it against the committed
## art — swap the pack in the inspector and this file re-checks whatever the `.tres`
## points at, the way it has since the pack was still `wizard_frames.tres`.
##
## Since #93 each animation has its own texture rather than sharing one atlas — there is
## no `walk_left` (`Fighter.animation_name` hands back `walk_right`'s name for `LEFT`,
## mirrored by `Fighter.should_flip_h`) and no `cast_*` art at all yet (see `Anim.CAST`'s
## doc comment on `Fighter`). The failure each check guards is invisible to a test of the
## drawing code: a set that reads off the end of its own strip makes a fighter vanish
## mid-walk; a heading that stands somewhere wildly different from the others makes a
## fighter hop when it turns.

## The four animations this pack actually defines. `Anim.CAST` names four more
## (`cast_down`/`cast_up`/`cast_right`/`cast_left`) that `mage_frames.tres` deliberately
## does not carry yet — there is nothing here to measure until it does.
const ANIMATIONS: Array[StringName] = [&"idle", &"walk_down", &"walk_right", &"walk_up"]
const WALK_ANIMATIONS: Array[StringName] = [&"walk_down", &"walk_right", &"walk_up"]

const ALPHA_FLOOR: float = 16.0 / 255.0
const HEM_ROWS: int = 16

## How far a heading's measured standing point may sit from the reference heading
## (`walk_down`). Wider than the old pack's 2.5px: that pack sliced one strip where every
## heading was drawn to align by construction, so any spread at all meant a slicing bug.
## This pack is three independently drawn poses — a stepping stride naturally plants the
## feet a few pixels differently facing right than facing down — so some spread is the
## art, not a defect. What this still catches is a frame that reads from the wrong place
## entirely (blank, or off the end of the strip), which stands wildly further off than
## any real stride does.
const REGISTRATION_TOLERANCE: float = 5.0

var _frames: SpriteFrames


func before_each() -> void:
	_frames = load("res://client/art/mage_frames.tres")


func _frame_atlas(anim: StringName, index: int) -> AtlasTexture:
	return _frames.get_frame_texture(anim, index) as AtlasTexture


## The standing point of one frame, in the coordinates the `AnimatedSprite2D` draws it
## in: the hem centroid of the atlas region, read straight off that frame's own atlas
## texture rather than a shared strip.
func _standing_x(at: AtlasTexture) -> float:
	var region := at.region
	var image := at.atlas.get_image()
	var bottom := -1
	for y in int(region.size.y):
		for x in int(region.size.x):
			var a := image.get_pixel(int(region.position.x) + x, int(region.position.y) + y).a
			if a > ALPHA_FLOOR:
				bottom = maxi(bottom, y)
	if bottom < 0:
		return -1.0
	var sum := 0.0
	var count := 0
	for y in range(maxi(0, bottom - HEM_ROWS + 1), bottom + 1):
		for x in int(region.size.x):
			var a := image.get_pixel(int(region.position.x) + x, int(region.position.y) + y).a
			if a > ALPHA_FLOOR:
				sum += float(x)
				count += 1
	return sum / float(count) + at.margin.position.x


func test_every_animation_the_client_can_play_exists() -> void:
	for anim in ANIMATIONS:
		assert_true(
			_frames.has_animation(anim),
			"mage_frames.tres has no animation '%s' — the fighter would play nothing" % anim
		)


func test_every_animation_runs_eight_frames() -> void:
	for anim in ANIMATIONS:
		assert_eq(
			_frames.get_frame_count(anim), 8,
			"'%s' should be the full eight-frame strip" % anim
		)


func test_no_frame_reads_off_its_own_atlas() -> void:
	for anim in ANIMATIONS:
		var size := _frame_atlas(anim, 0).atlas.get_image().get_size()
		for index in _frames.get_frame_count(anim):
			var region := _frame_atlas(anim, index).region
			assert_true(
				region.end.x <= size.x and region.end.y <= size.y,
				"animation '%s' frame %d reads past the edge of its atlas" % [anim, index]
			)


func test_no_frame_the_client_can_play_is_blank() -> void:
	# Reading past the end of a set, or the wrong region, would land on transparent
	# atlas and the fighter would vanish mid-walk.
	for anim in ANIMATIONS:
		for index in _frames.get_frame_count(anim):
			assert_true(
				_standing_x(_frame_atlas(anim, index)) >= 0.0,
				"animation '%s' frame %d is blank" % [anim, index]
			)


func test_every_walk_heading_stands_near_the_others() -> void:
	# The measurement that matters: every walk heading's feet land near the same x, so a
	# fighter does not hop sideways when it turns. Walk frames only — idle is a separate,
	# non-directional set with nothing to compare across headings.
	var reference := _standing_x(_frame_atlas(&"walk_down", 0))
	for anim in WALK_ANIMATIONS:
		for index in _frames.get_frame_count(anim):
			var standing := _standing_x(_frame_atlas(anim, index))
			assert_true(
				absf(standing - reference) <= REGISTRATION_TOLERANCE,
				"'%s' frame %d stands at x=%.1f, not near %.1f — fighters will hop when they turn" % [
					anim, index, standing, reference
				]
			)


func test_idle_plays_slower_than_every_walk() -> void:
	var idle_speed := _frames.get_animation_speed(&"idle")
	for anim in WALK_ANIMATIONS:
		assert_true(
			idle_speed < _frames.get_animation_speed(anim),
			"idle should tick over gently — a paced walk, not a frozen frame"
		)


func test_every_animation_loops() -> void:
	# Unlike the old pack's cast sets, nothing here holds a final pose — idle and walk
	# both cycle for as long as the posture lasts.
	for anim in ANIMATIONS:
		assert_true(
			_frames.get_animation_loop(anim),
			"'%s' should loop — nothing in this pack holds a last frame" % anim
		)
