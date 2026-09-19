extends TestCase

## Which animation the fighter's sprite should be playing — heading and posture — and
## nothing about the frames themselves. Those live in `client/art/mage_frames.tres` and
## are checked by `tests/test_fighter_frames.gd`; this file only exercises the pure
## decisions on `Fighter`, the way the codebase tests every decision it pulls out
## into a static function.
##
## **Heading.** Four exist, but the pack (#93) draws only three walk poses plus a
## non-directional idle — `LEFT` mirrors `RIGHT` (`should_flip_h`) rather than getting
## its own set. Getting a heading backwards still points every mage the wrong way, and
## the arena is symmetric enough that a mirrored heading looks plausible until you watch
## someone walk into a tent they are facing away from.
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


func test_a_noisy_tick_does_not_flip_a_settled_horizontal_facing() -> void:
	# Already reading RIGHT off a walk that leans horizontal; a single tick where the
	# vertical component ticks slightly ahead must not be read as a turn — this is the
	# near-diagonal noise reported moving up across the duel lane (#120).
	assert_eq(
		Fighter.facing_for(Vector2(29, 30), RIGHT), RIGHT,
		"a hair of vertical lead must not flip a facing that already reads horizontal"
	)
	assert_eq(
		Fighter.facing_for(Vector2(-29, 30), LEFT), LEFT, "and the same mirrored"
	)


func test_a_clear_vertical_move_still_turns_a_settled_horizontal_facing() -> void:
	# Hysteresis dampens noise, it does not pin the facing in place — a real turn still
	# reads as one once the vertical component clearly overtakes the horizontal.
	assert_eq(
		Fighter.facing_for(Vector2(10, -30), RIGHT), UP,
		"a genuinely vertical move must still turn a facing that was reading horizontal"
	)


func test_a_rotating_input_crosses_the_tie_only_once() -> void:
	# A slow rotation from vertical toward horizontal, jittered right around the
	# x≈y boundary the way real per-tick movement noise is (#120). Ticks 3 and 5-6
	# straddle the exact tie line in both directions; without hysteresis every one of
	# them would flip the facing, since each is judged fresh off a bare `absf`
	# comparison. With it, only the one genuine crossing (tick 4) should count.
	# Negative y is "up" (Godot's y grows downward) — a walk that starts vertical and
	# rotates toward horizontal, same as the reported "moving up across the lane" case.
	var ticks: Array[Vector2] = [
		Vector2(10, -40),  # clearly vertical
		Vector2(20, -40),  # clearly vertical
		Vector2(30, -32),  # noise: just past vertical again, still no lock yet
		Vector2(33, -30),  # the real crossing — across finally, clearly leads
		Vector2(30, -33),  # noise: dips back past the tie line — must not flip back
		Vector2(28, -34),  # noise: dips further — still within the hysteresis margin
		Vector2(35, -20),  # settling into a genuine horizontal move
		Vector2(40, -10),  # clearly horizontal
	]
	var expected_flip_at := 3 # index of Vector2(33, -30) above

	var facing := UP
	var flips := 0
	for i in ticks.size():
		var next := Fighter.facing_for(ticks[i], facing)
		if next != facing:
			flips += 1
			assert_eq(i, expected_flip_at, "the only flip must be the real crossing, not a noisy tick either side of it")
			facing = next
	assert_eq(flips, 1, "a noisy sweep across the tie line should settle the facing once")
	assert_eq(facing, RIGHT, "and land on the axis the sweep actually ended on")


func test_casting_does_not_change_which_way_you_face() -> void:
	# #158: a caster used to turn toward its target regardless of where its feet were
	# going, which read as a bug — standing still and throwing a flamestrike over your
	# shoulder. Facing has exactly one input now: `facing_for` takes travel and nothing
	# else, so a mage casting one way while walking another faces the way they walk.
	assert_eq(
		Fighter.facing_for(Vector2(0, 40), LEFT),
		DOWN,
		"walking down while casting at a target to your left should still face down"
	)


# ── Travel speed ──────────────────────────────────────────────────────────────────


func test_a_player_controlled_fighter_is_judged_on_its_own_predicted_move() -> void:
	var was_at := Vector2(100.0, 100.0)
	var predicted_at := was_at + Vector2(2.0, 0.0)
	assert_almost_eq(
		Fighter.travel_speed_for(true, was_at, predicted_at, was_at, 1.0 / 60.0),
		was_at.distance_to(predicted_at) / (1.0 / 60.0),
		"a player-controlled fighter's speed comes from its own predicted move"
	)


func test_a_stationary_caster_is_not_read_as_walking_by_a_position_correction() -> void:
	# The regression this guards: a player-controlled fighter standing still must never
	# read its travel speed off wherever some other position happens to be — only its own
	# predicted move says whether it walked. Invisible before #93, because casting always
	# showed a dedicated cast pose regardless of speed; visible the moment a cast with no
	# art of its own fell back to WALK/IDLE. Before #113 that "other position" was an
	# active server-correction lerp for the local player too; it is now only ever a
	# remote fighter's, but the invariant `travel_speed_for` has to hold is unchanged.
	var was_at := Vector2(100.0, 100.0)
	var predicted_at := was_at # no input, so move_and_slide() went nowhere
	var corrected_at := was_at + Vector2(50.0, 0.0) # some other position entirely
	var speed := Fighter.travel_speed_for(true, was_at, predicted_at, corrected_at, 1.0 / 60.0)
	assert_true(
		speed <= Fighter.WALK_SPEED_THRESHOLD,
		"a position correction elsewhere must not make a genuinely stationary player read as walking"
	)


func test_a_remote_fighter_is_judged_on_the_corrected_position() -> void:
	# A remote fighter has no prediction of its own — the corrected position is the
	# only signal it has of moving at all.
	var was_at := Vector2(100.0, 100.0)
	var corrected_at := was_at + Vector2(50.0, 0.0)
	assert_almost_eq(
		Fighter.travel_speed_for(false, was_at, was_at, corrected_at, 1.0 / 60.0),
		was_at.distance_to(corrected_at) / (1.0 / 60.0),
		"a remote fighter's speed has to come from the corrected position — it has no other"
	)


func test_travel_speed_does_not_divide_by_a_zero_or_negative_delta() -> void:
	assert_eq(
		Fighter.travel_speed_for(true, Vector2.ZERO, Vector2(50, 0), Vector2(50, 0), 0.0),
		0.0,
		"a zero delta must not divide by zero"
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
		Fighter.animation_name(WALK, RIGHT), &"walk_right",
		"the name is <posture>_<heading>, matching the sets in mage_frames.tres"
	)
	assert_eq(
		Fighter.animation_name(CAST, UP), &"cast_up",
		"a cast set is named the same way, unchanged since before #93"
	)


func test_walking_left_borrows_walk_rights_name() -> void:
	# No walk_left in the pack (#93) — should_flip_h is what turns this into a mirrored
	# walk rather than a fighter who faces left but visibly walks right.
	assert_eq(
		Fighter.animation_name(WALK, LEFT), Fighter.animation_name(WALK, RIGHT),
		"left has no walk set of its own — it plays right's, mirrored"
	)


func test_only_left_is_drawn_mirrored() -> void:
	assert_true(Fighter.should_flip_h(LEFT), "left has no art of its own to mirror right into")
	for facing in [DOWN, UP, RIGHT]:
		assert_false(
			Fighter.should_flip_h(facing),
			"only left borrows another heading's animation — the rest play their own art"
		)


func test_idle_and_walk_are_told_apart_by_name() -> void:
	# Idle and walk are separate art now (#93), not two speeds over shared frames — but
	# the name still has to distinguish them, the same contract as before.
	assert_true(
		Fighter.animation_name(IDLE, DOWN) != Fighter.animation_name(WALK, DOWN),
		"idle and walk must resolve to different animations"
	)


func test_idle_does_not_care_which_way_you_are_facing() -> void:
	# The pack draws one non-directional idle (#93) — every heading names the same
	# animation, unlike walk.
	for facing in [DOWN, UP, LEFT, RIGHT]:
		assert_eq(
			Fighter.animation_name(IDLE, facing), &"idle",
			"idle has no per-heading set to pick between"
		)


func test_every_animation_the_client_can_name_totals_eight() -> void:
	var seen := {}
	for anim in [IDLE, WALK, CAST]:
		for facing in [DOWN, UP, LEFT, RIGHT]:
			seen[Fighter.animation_name(anim, facing)] = true
	assert_eq(
		seen.size(), 8,
		"one idle, three walk headings (left borrows right), and four dormant cast " +
		"headings (#93) name eight distinct animations"
	)
