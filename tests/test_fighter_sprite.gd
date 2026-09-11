extends TestCase

## Which animation the fighter's sprite should be playing — heading and posture — and
## nothing about the frames themselves. Those live in `client/art/wizard_frames.tres` and
## are checked by `tests/test_fighter_frames.gd`; this file only exercises the pure
## decisions on `Fighter`, the way the codebase tests every decision it pulls out
## into a static function.
##
## **Heading.** The pack draws four of them. Getting it backwards points every mage the
## wrong way, and the arena is symmetric enough that a mirrored heading looks plausible
## until you watch someone walk into a tent they are facing away from.
##
## **Posture.** Idle, walk, cast. Casting wins over walking (you can do both at once, and
## the spell is the read); a snapshot nudge is not a walk.
##
## **What the art is allowed to say.** Nothing a player reads under pressure — ten fighters
## wear this one robe, so health, status, whose body it is and which spell is coming all
## stay `_draw()` calls in palette colours.

const IDLE := Fighter.Anim.IDLE
const WALK := Fighter.Anim.WALK
const CAST := Fighter.Anim.CAST

const DOWN := Fighter.Facing.DOWN
const UP := Fighter.Facing.UP
const LEFT := Fighter.Facing.LEFT
const RIGHT := Fighter.Facing.RIGHT


# ── Heading ───────────────────────────────────────────────────────────────────────


func test_each_way_of_walking_faces_that_way() -> void:
	# Godot's y grows downward, so a positive y is toward the bottom of the screen.
	assert_eq(Fighter.facing_for(Vector2(0, 40), UP), DOWN, "walking down faces down")
	assert_eq(Fighter.facing_for(Vector2(0, -40), DOWN), UP, "walking up faces up")
	assert_eq(Fighter.facing_for(Vector2(40, 0), UP), RIGHT, "walking right faces right")
	assert_eq(Fighter.facing_for(Vector2(-40, 0), UP), LEFT, "walking left faces left")


func test_standing_still_keeps_the_heading_you_had() -> void:
	# Otherwise a fighter snaps back to a default the moment they stop, and every duel
	# ends with both mages facing the same arbitrary way.
	assert_eq(
		Fighter.facing_for(Vector2.ZERO, LEFT), LEFT,
		"letting go of the move button must not turn you around"
	)


func test_a_hair_of_movement_is_not_a_turn() -> void:
	# A fighter pinned against a tent slides a fraction of a pixel a frame. Reading that
	# as a heading spins them on the spot.
	assert_eq(
		Fighter.facing_for(Vector2(0.1, -0.2), RIGHT), RIGHT,
		"sub-pixel drift must not change which way someone is pointing"
	)


func test_a_diagonal_is_drawn_along_the_lane() -> void:
	# The duel lane runs east-west and so does almost every shot fired down it, so an
	# exact diagonal reads better sideways than up or down.
	assert_eq(
		Fighter.facing_for(Vector2(30, 30), UP), RIGHT,
		"a 45 degree walk should face along the lane, not across it"
	)
	assert_eq(
		Fighter.facing_for(Vector2(-30, -30), UP), LEFT, "and the same mirrored"
	)


# ── Heading, once aim is in the picture ───────────────────────────────────────────


func test_a_caster_turns_toward_what_they_are_casting_at() -> void:
	# Standing still and throwing a flamestrike over your shoulder reads as a bug.
	assert_eq(
		Fighter.heading_for(true, Vector2(400, 0), Vector2.ZERO, Vector2.ZERO, LEFT),
		RIGHT,
		"a caster should face their target even when their feet are not moving"
	)


func test_aim_beats_travel_while_casting() -> void:
	# The deliberate act wins: a mage side-stepping behind a tent while throwing a spell
	# down the lane is pointing at the spell, not at the tent.
	assert_eq(
		Fighter.heading_for(
			true, Vector2(-400, 0), Vector2.ZERO, Vector2(0, 40), DOWN
		),
		LEFT,
		"walking one way while casting another should point at the spell"
	)


func test_aim_says_nothing_when_you_are_not_casting() -> void:
	assert_eq(
		Fighter.heading_for(
			false, Vector2(-400, 0), Vector2.ZERO, Vector2(0, 40), UP
		),
		DOWN,
		"having a target selected must not turn you while you are simply walking"
	)


func test_a_fighter_with_no_target_falls_back_to_where_it_is_going() -> void:
	# Every remote body is this case: a snapshot carries positions and state, never who
	# anyone is aiming at.
	assert_eq(
		Fighter.heading_for(true, null, Vector2.ZERO, Vector2(0, -40), DOWN),
		UP,
		"a fighter nobody named a target to should still face the way it travels"
	)


func test_casting_at_your_own_feet_does_not_spin_you() -> void:
	# Targets and casters overlap when two mages close; a zero-length aim says nothing.
	assert_eq(
		Fighter.heading_for(
			true, Vector2(80, 80), Vector2(80, 80), Vector2.ZERO, RIGHT
		),
		RIGHT,
		"a target standing on top of you must not decide which way you point"
	)


# ── Posture ───────────────────────────────────────────────────────────────────────


func test_a_fighter_standing_still_is_idle() -> void:
	assert_eq(
		Fighter.animation_for(EntityState.State.IDLE, 0.0), IDLE,
		"a fighter who is not moving is not walking"
	)


func test_a_fighter_at_running_speed_is_walking() -> void:
	assert_eq(
		Fighter.animation_for(EntityState.State.IDLE, Constants.PLAYER_MOVE_SPEED),
		WALK,
		"a fighter crossing the arena should be walking"
	)


func test_a_nudge_is_not_a_walk() -> void:
	# A server correction shifts a standing player a few pixels. Reading that as walking
	# leaves every stationary opponent moonwalking on the spot.
	assert_eq(
		Fighter.animation_for(
			EntityState.State.IDLE, Fighter.WALK_SPEED_THRESHOLD - 1.0
		),
		IDLE,
		"a snapshot nudge must not look like walking"
	)


func test_casting_beats_walking() -> void:
	assert_eq(
		Fighter.animation_for(
			EntityState.State.CASTING, Constants.PLAYER_MOVE_SPEED
		),
		CAST,
		"you can walk while casting, and the spell is what the opponent needs to see"
	)


func test_recovery_is_not_a_cast() -> void:
	assert_eq(
		Fighter.animation_for(EntityState.State.RECOVERING, 0.0), IDLE,
		"recovery is the pause after a spell, not a wind-up"
	)


# ── The animation name handed to AnimatedSprite2D.play ────────────────────────────


func test_the_animation_name_is_posture_then_heading() -> void:
	assert_eq(
		Fighter.animation_name(WALK, LEFT), &"walk_left",
		"the name is <posture>_<heading>, matching the sets in wizard_frames.tres"
	)
	assert_eq(
		Fighter.animation_name(CAST, UP), &"cast_up",
		"a cast set is named the same way"
	)


func test_idle_and_walk_are_told_apart_by_name() -> void:
	# The pack draws no standing pose — idle and walk share frames — but they are two
	# animations at different speeds, so the name has to distinguish them.
	assert_true(
		Fighter.animation_name(IDLE, DOWN) != Fighter.animation_name(WALK, DOWN),
		"idle and walk must resolve to different animations so idle can play slower"
	)


func test_every_posture_and_heading_has_a_name() -> void:
	var seen := {}
	for anim in [IDLE, WALK, CAST]:
		for facing in [DOWN, UP, LEFT, RIGHT]:
			seen[Fighter.animation_name(anim, facing)] = true
	assert_eq(
		seen.size(), 12,
		"three postures across four headings must name twelve distinct animations"
	)
