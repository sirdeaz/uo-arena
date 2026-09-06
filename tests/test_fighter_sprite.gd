extends TestCase

## The character art, and the two things that can go wrong with it.
##
## **Registration.** The pack these frames came from is not registered: the attack
## frames sit on a wider canvas than the rest, and each animation puts the character
## somewhere else on it. `tools/pack_character_sprites.py` corrects that on the way in,
## and the test below re-measures the committed atlas rather than trusting it — because
## the failure is a fighter that jumps sideways when it stops walking, which no test of
## the drawing code would ever notice.
##
## **What the art is allowed to say.** Nothing a player reads under pressure. Ten
## fighters wear this one hooded robe, so health, status, whose body it is and which
## spell is coming all stay `_draw()` calls in palette colours. The sprite carries
## posture, and the tests here only ever ask it for posture.

const IDLE := FighterSprite.Anim.IDLE
const WALK := FighterSprite.Anim.WALK
const CAST := FighterSprite.Anim.CAST

## How far a frame's standing point may sit from `ANCHOR` before the animation is
## visibly unregistered. Measured in atlas pixels; the pack's own drift is 2 px of
## deliberate bob and lean, and the drift this catches — a re-pack that skipped the
## anchoring — is 4 px and up.
const REGISTRATION_TOLERANCE: float = 3.0

const ALPHA_FLOOR: float = 16.0 / 255.0
const HEM_ROWS: int = 16


# ── Posture ───────────────────────────────────────────────────────────────────────


func test_a_fighter_standing_still_is_idle() -> void:
	assert_eq(
		FighterSprite.animation_for(EntityState.State.IDLE, 0.0),
		IDLE,
		"nothing happening should look like nothing happening"
	)


func test_a_fighter_at_running_speed_is_walking() -> void:
	assert_eq(
		FighterSprite.animation_for(EntityState.State.IDLE, Constants.PLAYER_MOVE_SPEED),
		WALK,
		"a fighter crossing the arena should move their feet"
	)


func test_a_nudge_is_not_a_walk() -> void:
	# Server corrections push a standing player around by a few pixels a second. If that
	# counted as walking, every idle opponent would moonwalk on every snapshot.
	assert_eq(
		FighterSprite.animation_for(EntityState.State.IDLE, 2.0),
		IDLE,
		"a correction-sized nudge must not start the walk cycle"
	)


func test_casting_beats_walking() -> void:
	# You can walk while casting in this game — that is the whole premise — and what an
	# opponent needs off the silhouette is that a spell is coming, not that feet moved.
	assert_eq(
		FighterSprite.animation_for(
			EntityState.State.CASTING, Constants.PLAYER_MOVE_SPEED
		),
		CAST,
		"a running caster should still read as a caster"
	)


func test_recovery_is_not_a_cast() -> void:
	assert_eq(
		FighterSprite.animation_for(EntityState.State.RECOVERING, 0.0),
		IDLE,
		"the dead time after a spell is over, and should look it"
	)


# ── Frames ────────────────────────────────────────────────────────────────────────


func test_idle_loops_rather_than_running_off_the_end() -> void:
	var seen := {}
	for step in 40:
		var frame := FighterSprite.frame_for(IDLE, float(step) * 0.1, 0.0)
		assert_true(frame >= 0 and frame < 4, "idle frame %d is off the row" % frame)
		seen[frame] = true
	assert_eq(seen.size(), 4, "a four-frame loop should use all four frames")


func test_walking_animates_faster_than_standing() -> void:
	assert_true(
		FighterSprite.WALK_FRAME_SECONDS < FighterSprite.IDLE_FRAME_SECONDS,
		"feet move faster than breathing"
	)


func test_a_cast_pose_tracks_the_spell_rather_than_the_clock() -> void:
	# The wind-up is a read on how close the spell is to landing, the same way the aura
	# is. A one-second spell and a four-second one then look different at the same
	# moment, which is the point of not looping it.
	var early := FighterSprite.frame_for(CAST, 0.0, 0.0)
	var late := FighterSprite.frame_for(CAST, 0.0, 0.99)
	assert_eq(early, 0, "a cast should start at the first frame")
	assert_true(late > early, "a cast should be further along near the end")


func test_the_clock_does_not_move_a_cast_pose() -> void:
	assert_eq(
		FighterSprite.frame_for(CAST, 0.0, 0.5),
		FighterSprite.frame_for(CAST, 12.7, 0.5),
		"the same progress should be the same pose, whenever it happens"
	)


func test_a_finished_cast_stays_on_the_row() -> void:
	# Progress can reach exactly 1.0 on the frame a spell resolves, and a client whose
	# clock has run ahead of the server can push past it.
	for progress in [1.0, 1.5, 40.0]:
		var frame := FighterSprite.frame_for(CAST, 0.0, progress)
		assert_true(frame < 3, "progress %.1f ran off the cast row" % progress)


func test_a_negative_clock_does_not_produce_a_negative_frame() -> void:
	assert_true(
		FighterSprite.frame_for(IDLE, -1.0, 0.0) >= 0,
		"a frame index is never negative, whatever it is handed"
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


## Where the character in this frame stands, by the same measure the packer used: the
## centroid of the robe hem, and the row below their feet.
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


func test_every_frame_stands_in_the_same_place() -> void:
	for anim in [IDLE, WALK, CAST]:
		for frame in FighterSprite.FRAME_COUNTS[anim]:
			var region := FighterSprite.region_for(anim, frame)
			var standing := _standing_point(region)
			assert_true(
				standing.distance_to(FighterSprite.ANCHOR) <= REGISTRATION_TOLERANCE,
				"animation %d frame %d stands at %s, not at %s — the atlas is unregistered and fighters will jump between animations" % [
					anim, frame, standing, FighterSprite.ANCHOR
				]
			)


func test_no_frame_falls_off_the_atlas() -> void:
	var size := FighterSprite.TEXTURE.get_size()
	for anim in [IDLE, WALK, CAST]:
		for frame in FighterSprite.FRAME_COUNTS[anim]:
			var region := FighterSprite.region_for(anim, frame)
			assert_true(
				region.end.x <= size.x and region.end.y <= size.y,
				"animation %d frame %d reads past the edge of the atlas" % [anim, frame]
			)


func test_every_animation_has_a_row_of_its_own() -> void:
	var rows := {}
	for anim in [IDLE, WALK, CAST]:
		rows[FighterSprite.region_for(anim, 0).position.y] = anim
	assert_eq(rows.size(), 3, "two animations sharing a row would show the same pose")


func test_no_cell_the_client_can_ask_for_is_empty() -> void:
	# The cast row is one frame shorter than the others. Reading a fourth cast frame
	# would land on transparent atlas and the fighter would vanish mid-spell.
	for anim in [IDLE, WALK, CAST]:
		var region := FighterSprite.region_for(anim, FighterSprite.FRAME_COUNTS[anim] - 1)
		assert_true(
			not _region_pixels(region).is_empty(),
			"the last frame of animation %d is blank" % anim
		)


func test_the_feet_land_where_the_fighter_is() -> void:
	var rect := FighterSprite.rect_for(Vector2.ZERO)
	assert_almost_eq(
		rect.position.y + FighterSprite.ANCHOR.y,
		0.0,
		"the character should stand on their own position, not hover above it"
	)
	assert_almost_eq(
		rect.position.x + FighterSprite.ANCHOR.x,
		0.0,
		"and be centred on it sideways"
	)


# ── A fighter nobody is steering ──────────────────────────────────────────────────


var _fighter: Fighter


func before_each() -> void:
	_fighter = Fighter.new()
	add_child(_fighter)


func after_each() -> void:
	_fighter.queue_free()


func test_an_opponent_the_server_is_carrying_walks() -> void:
	# The trap this pins: a remote fighter has no `velocity` of its own — it is pulled
	# along by `_apply_server_correction` — so animating off `velocity` would leave every
	# opponent gliding across the arena in an idle pose.
	_fighter.server_driven = true
	_fighter.global_position = Vector2.ZERO
	_fighter.server_position = Vector2(600.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_eq(
		_fighter.current_frame_region().position.y,
		FighterSprite.region_for(WALK, 0).position.y,
		"an opponent being carried across the arena should be walking"
	)


func test_and_stands_still_once_it_arrives() -> void:
	_fighter.server_driven = true
	_fighter.global_position = Vector2.ZERO
	_fighter.server_position = Vector2.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_eq(
		_fighter.current_frame_region().position.y,
		FighterSprite.region_for(IDLE, 0).position.y,
		"a fighter standing on the spot should not be walking"
	)
