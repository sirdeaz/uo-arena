extends TestCase

## The character art, and the three things that can go wrong with it.
##
## **Heading.** The pack draws four of them, so a fighter now has one — the first thing
## in this game that does. Getting it backwards points every mage the wrong way, and
## the arena is symmetric enough that a mirrored heading looks plausible until you watch
## someone walk into a tent they are facing away from.
##
## **Registration.** Every set in the pack lands its feet within a pixel except the
## left-facing walk, which sits about 3.6 px left inside its cells; drawn from one
## anchor a fighter hops sideways each time it turns. The anchors below are per heading
## and the tests re-measure the committed atlas rather than trusting the constants,
## because the failure is a hop no test of the drawing code would ever notice.
##
## **What the art is allowed to say.** Nothing a player reads under pressure. Ten
## fighters wear this one robe, so health, status, whose body it is and which spell is
## coming all stay `_draw()` calls in palette colours. The sprite carries posture and
## heading, and the tests here only ever ask it for those.

const IDLE := FighterSprite.Anim.IDLE
const WALK := FighterSprite.Anim.WALK
const CAST := FighterSprite.Anim.CAST

const DOWN := FighterSprite.Facing.DOWN
const UP := FighterSprite.Facing.UP
const LEFT := FighterSprite.Facing.LEFT
const RIGHT := FighterSprite.Facing.RIGHT

const HEADINGS := [DOWN, UP, LEFT, RIGHT]

## How far a set's measured standing point may sit from its declared anchor. A cast set
## leans into the spell by a pixel or two on purpose; an anchor copied from the wrong
## heading is out by three or more.
const REGISTRATION_TOLERANCE: float = 2.5

const ALPHA_FLOOR: float = 16.0 / 255.0
const HEM_ROWS: int = 16


# ── Heading ───────────────────────────────────────────────────────────────────────


func test_each_way_of_walking_faces_that_way() -> void:
	# Godot's y grows downward, so a positive y is toward the bottom of the screen.
	assert_eq(FighterSprite.facing_for(Vector2(0, 40), UP), DOWN, "walking down faces down")
	assert_eq(FighterSprite.facing_for(Vector2(0, -40), DOWN), UP, "walking up faces up")
	assert_eq(FighterSprite.facing_for(Vector2(40, 0), UP), RIGHT, "walking right faces right")
	assert_eq(FighterSprite.facing_for(Vector2(-40, 0), UP), LEFT, "walking left faces left")


func test_standing_still_keeps_the_heading_you_had() -> void:
	# Otherwise a fighter snaps back to a default the moment they stop, and every duel
	# ends with both mages facing the same arbitrary way.
	assert_eq(
		FighterSprite.facing_for(Vector2.ZERO, LEFT), LEFT,
		"letting go of the move button must not turn you around"
	)


func test_a_hair_of_movement_is_not_a_turn() -> void:
	# A fighter pinned against a tent slides a fraction of a pixel a frame. Reading that
	# as a heading spins them on the spot.
	assert_eq(
		FighterSprite.facing_for(Vector2(0.1, -0.2), RIGHT), RIGHT,
		"sub-pixel drift must not change which way someone is pointing"
	)


func test_a_diagonal_is_drawn_along_the_lane() -> void:
	# The duel lane runs east-west and so does almost every shot fired down it, so an
	# exact diagonal reads better sideways than up or down.
	assert_eq(
		FighterSprite.facing_for(Vector2(30, 30), UP), RIGHT,
		"a 45 degree walk should face along the lane, not across it"
	)
	assert_eq(
		FighterSprite.facing_for(Vector2(-30, -30), UP), LEFT, "and the same mirrored"
	)


# ── Heading, once aim is in the picture ───────────────────────────────────────────


func test_a_caster_turns_toward_what_they_are_casting_at() -> void:
	# Standing still and throwing a flamestrike over your shoulder reads as a bug.
	assert_eq(
		FighterSprite.heading_for(true, Vector2(400, 0), Vector2.ZERO, Vector2.ZERO, LEFT),
		RIGHT,
		"a caster should face their target even when their feet are not moving"
	)


func test_aim_beats_travel_while_casting() -> void:
	# The deliberate act wins: a mage side-stepping behind a tent while throwing a spell
	# down the lane is pointing at the spell, not at the tent.
	assert_eq(
		FighterSprite.heading_for(
			true, Vector2(-400, 0), Vector2.ZERO, Vector2(0, 40), DOWN
		),
		LEFT,
		"walking one way while casting another should point at the spell"
	)


func test_aim_says_nothing_when_you_are_not_casting() -> void:
	assert_eq(
		FighterSprite.heading_for(
			false, Vector2(-400, 0), Vector2.ZERO, Vector2(0, 40), UP
		),
		DOWN,
		"having a target selected must not turn you while you are simply walking"
	)


func test_a_fighter_with_no_target_falls_back_to_where_it_is_going() -> void:
	# Every remote body is this case: a snapshot carries positions and state, never who
	# anyone is aiming at.
	assert_eq(
		FighterSprite.heading_for(true, null, Vector2.ZERO, Vector2(0, -40), DOWN),
		UP,
		"a fighter nobody named a target to should still face the way it travels"
	)


func test_casting_at_your_own_feet_does_not_spin_you() -> void:
	# Targets and casters overlap when two mages close; a zero-length aim says nothing.
	assert_eq(
		FighterSprite.heading_for(
			true, Vector2(80, 80), Vector2(80, 80), Vector2.ZERO, RIGHT
		),
		RIGHT,
		"a target standing on top of you must not decide which way you point"
	)


# ── Posture ───────────────────────────────────────────────────────────────────────


func test_a_fighter_standing_still_is_idle() -> void:
	assert_eq(
		FighterSprite.animation_for(EntityState.State.IDLE, 0.0), IDLE,
		"a fighter who is not moving is not walking"
	)


func test_a_fighter_at_running_speed_is_walking() -> void:
	assert_eq(
		FighterSprite.animation_for(EntityState.State.IDLE, Constants.PLAYER_MOVE_SPEED),
		WALK,
		"a fighter crossing the arena should be walking"
	)


func test_a_nudge_is_not_a_walk() -> void:
	# A server correction shifts a standing player a few pixels. Reading that as walking
	# leaves every stationary opponent moonwalking on the spot.
	assert_eq(
		FighterSprite.animation_for(
			EntityState.State.IDLE, FighterSprite.WALK_SPEED_THRESHOLD - 1.0
		),
		IDLE,
		"a snapshot nudge must not look like walking"
	)


func test_casting_beats_walking() -> void:
	assert_eq(
		FighterSprite.animation_for(
			EntityState.State.CASTING, Constants.PLAYER_MOVE_SPEED
		),
		CAST,
		"you can walk while casting, and the spell is what the opponent needs to see"
	)


func test_recovery_is_not_a_cast() -> void:
	assert_eq(
		FighterSprite.animation_for(EntityState.State.RECOVERING, 0.0), IDLE,
		"recovery is the pause after a spell, not a wind-up"
	)


# ── Frames ────────────────────────────────────────────────────────────────────────


func test_idle_loops_rather_than_running_off_the_end() -> void:
	var span := FighterSprite.range_for(IDLE, DOWN)
	for step in 40:
		var frame := FighterSprite.frame_for(IDLE, DOWN, float(step) * 0.1, 0.0)
		assert_true(
			frame >= span.x and frame < span.x + span.y,
			"idle frame %d left its own set" % frame
		)


func test_walking_animates_faster_than_standing() -> void:
	var seconds := FighterSprite.IDLE_FRAME_SECONDS
	assert_true(
		FighterSprite.frame_for(WALK, DOWN, seconds, 0.0)
		> FighterSprite.frame_for(IDLE, DOWN, seconds, 0.0),
		"a walk should have moved further through its set than an idle in the same time"
	)


func test_a_cast_pose_tracks_the_spell_rather_than_the_clock() -> void:
	var span := FighterSprite.range_for(CAST, DOWN)
	assert_eq(
		FighterSprite.frame_for(CAST, DOWN, 0.0, 0.0), span.x,
		"a cast starts on its first frame"
	)
	assert_eq(
		FighterSprite.frame_for(CAST, DOWN, 0.0, 1.0), span.x + span.y - 1,
		"and finishes on its last, however long the spell took"
	)


func test_the_clock_does_not_move_a_cast_pose() -> void:
	# Two spells at the same progress look the same, whether one is a magic arrow and
	# the other a flamestrike four times as long.
	assert_eq(
		FighterSprite.frame_for(CAST, UP, 0.0, 0.5),
		FighterSprite.frame_for(CAST, UP, 9.0, 0.5),
		"a cast pose is a read on progress, not an animation that happens to be playing"
	)


func test_a_finished_cast_stays_on_its_last_frame() -> void:
	var span := FighterSprite.range_for(CAST, RIGHT)
	assert_eq(
		FighterSprite.frame_for(CAST, RIGHT, 0.0, 1.4), span.x + span.y - 1,
		"progress past the end must not read off the end of the set"
	)


func test_a_negative_clock_does_not_produce_a_negative_frame() -> void:
	var span := FighterSprite.range_for(WALK, LEFT)
	assert_true(
		FighterSprite.frame_for(WALK, LEFT, -3.0, 0.0) >= span.x,
		"a clock running backwards must not index behind the set"
	)


func test_every_heading_draws_a_different_pose() -> void:
	var seen := {}
	for facing in HEADINGS:
		seen[FighterSprite.frame_for(WALK, facing, 0.0, 0.0)] = facing
	assert_eq(
		seen.size(), HEADINGS.size(),
		"two headings sharing a frame would point two fighters the same way"
	)


# ── The atlas itself ──────────────────────────────────────────────────────────────


func _region_pixels(region: Rect2) -> Array:
	var image := FighterSprite.TEXTURE.get_image()
	var opaque := []
	for y in int(region.size.y):
		for x in int(region.size.x):
			if image.get_pixel(int(region.position.x) + x, int(region.position.y) + y).a \
					> ALPHA_FLOOR:
				opaque.append(Vector2(x, y))
	return opaque


## Where the character in this frame stands: the centroid of the robe hem, and the row
## below their feet.
func _standing_point(region: Rect2) -> Vector2:
	var opaque := _region_pixels(region)
	if opaque.is_empty():
		return Vector2(-1.0, -1.0)
	var bottom := 0.0
	for point in opaque:
		bottom = maxf(bottom, point.y)
	var hem := 0.0
	var count := 0
	for point in opaque:
		if point.y > bottom - float(HEM_ROWS):
			hem += point.x
			count += 1
	return Vector2(hem / float(count), bottom + 1.0)


func test_the_atlas_is_the_strip_the_pack_supplied() -> void:
	# Shipped exactly as handed over — no repacking step — so this pins the shape the
	# frame maths assumes rather than a shape some script produced.
	var size := FighterSprite.TEXTURE.get_size()
	assert_almost_eq(
		size.x, FighterSprite.CELL.x * float(FighterSprite.FRAME_COUNT),
		"the strip should be exactly %d frames wide" % FighterSprite.FRAME_COUNT
	)
	assert_almost_eq(size.y, FighterSprite.CELL.y, "and one frame tall")


func test_no_frame_falls_off_the_atlas() -> void:
	var size := FighterSprite.TEXTURE.get_size()
	for frame in FighterSprite.FRAME_COUNT:
		var region := FighterSprite.region_for(frame)
		assert_true(
			region.end.x <= size.x and region.end.y <= size.y,
			"frame %d reads past the edge of the atlas" % frame
		)


func test_every_set_the_client_can_ask_for_is_inside_the_strip() -> void:
	for anim in [IDLE, WALK, CAST]:
		for facing in HEADINGS:
			var span := FighterSprite.range_for(anim, facing)
			assert_true(
				span.x >= 0 and span.x + span.y <= FighterSprite.FRAME_COUNT,
				"animation %d heading %d runs past the end of the strip" % [anim, facing]
			)


func test_no_frame_the_client_can_ask_for_is_blank() -> void:
	# Reading past the end of a set would land on transparent atlas and the fighter
	# would vanish mid-spell.
	for anim in [WALK, CAST]:
		for facing in HEADINGS:
			var span := FighterSprite.range_for(anim, facing)
			for offset in span.y:
				assert_false(
					_region_pixels(FighterSprite.region_for(span.x + offset)).is_empty(),
					"animation %d heading %d frame %d is blank" % [anim, facing, offset]
				)


func test_no_two_sets_overlap() -> void:
	# Walking and casting are interleaved rather than blocked, so an off-by-one in the
	# table would silently show a cast pose to someone who is only walking.
	var owner := {}
	for anim in [WALK, CAST]:
		for facing in HEADINGS:
			var span := FighterSprite.range_for(anim, facing)
			for offset in span.y:
				var frame := span.x + offset
				assert_false(
					owner.has(frame),
					"frame %d belongs to two sets at once" % frame
				)
				owner[frame] = true


func test_every_heading_stands_where_its_anchor_says() -> void:
	# The measurement that matters: re-read the committed atlas and check the constants
	# against it. Walk frames only — a staff or a flame dipping below the hem makes a
	# cast frame's lowest row something other than the character's feet.
	for facing in HEADINGS:
		var span := FighterSprite.range_for(WALK, facing)
		var anchor: Vector2 = FighterSprite.ANCHORS[facing]
		for offset in span.y:
			var standing := _standing_point(FighterSprite.region_for(span.x + offset))
			assert_true(
				standing.distance_to(anchor) <= REGISTRATION_TOLERANCE,
				"heading %d frame %d stands at %s, not at its anchor %s — fighters will hop when they turn" % [
					facing, offset, standing, anchor
				]
			)


func test_the_left_anchor_really_is_different() -> void:
	# The one correction in the table. If a refactor collapses the anchors back to a
	# single value this fails, and the left-facing walk starts hopping again.
	assert_false(
		FighterSprite.ANCHORS[LEFT].is_equal_approx(FighterSprite.ANCHORS[RIGHT]),
		"the left set sits ~3.6px left in its cells and needs its own anchor"
	)


func test_the_feet_land_where_the_fighter_is() -> void:
	for facing in HEADINGS:
		var rect := FighterSprite.rect_for(Vector2.ZERO, facing)
		var anchor: Vector2 = FighterSprite.ANCHORS[facing]
		assert_almost_eq(
			rect.position.y + anchor.y, 0.0,
			"heading %d should stand on its own position, not hover above it" % facing
		)
		assert_almost_eq(
			rect.position.x + anchor.x, 0.0,
			"and be centred on it sideways" % []
		)


func test_the_channel_frames_are_left_alone() -> void:
	# Recorded as a decision rather than an oversight: the game already announces a cast
	# with the mantra and an aura in the spell's own colour, and this set is a fixed
	# yellow-and-blue flourish that would say the same thing again in the wrong colour.
	var channel := FighterSprite.CHANNEL_RANGE
	for anim in [IDLE, WALK, CAST]:
		for facing in HEADINGS:
			var span := FighterSprite.range_for(anim, facing)
			assert_true(
				span.x + span.y <= channel.x or span.x >= channel.x + channel.y,
				"animation %d heading %d reaches into the unused channel frames" % [anim, facing]
			)
