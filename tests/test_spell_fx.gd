extends TestCase

## Geometry behind the crackling rings and jagged bolts. Drawing is a matter of taste,
## but the shapes have to obey rules: a bolt must actually touch the thing it hits, and
## a shape must be stable for a given seed or it strobes instead of crackling.


# ── bolts ─────────────────────────────────────────────────────────────────────

func test_bolt_starts_and_ends_exactly_on_target() -> void:
	var from := Vector2(-200, 40)
	var to := Vector2(300, -90)
	var path := SpellFX.bolt_path(from, to, 10, 18.0, 1)
	assert_eq(path[0], from, "a bolt must leave the caster")
	assert_eq(path[path.size() - 1], to, "and must land on the target")


func test_bolt_has_one_more_point_than_segments() -> void:
	var path := SpellFX.bolt_path(Vector2.ZERO, Vector2(100, 0), 8, 10.0, 1)
	assert_eq(path.size(), 9, "8 segments needs 9 points")


func test_bolt_stays_within_its_amplitude() -> void:
	var from := Vector2.ZERO
	var to := Vector2(400, 0)
	var amplitude := 20.0
	var path := SpellFX.bolt_path(from, to, 16, amplitude, 7)
	for i in path.size():
		var offset: float = absf(path[i].y)
		assert_true(
			offset <= amplitude + 0.001,
			"point %d strayed %.1f from the line, limit %.1f" % [i, offset, amplitude]
		)


func test_same_seed_gives_the_same_bolt() -> void:
	# Regenerating every frame would strobe. Crackle comes from stepping the seed at a
	# fixed rate, so a given seed has to be reproducible.
	var a := SpellFX.bolt_path(Vector2.ZERO, Vector2(200, 0), 12, 15.0, 42)
	var b := SpellFX.bolt_path(Vector2.ZERO, Vector2(200, 0), 12, 15.0, 42)
	assert_eq(a, b, "the same seed must redraw the same bolt")


func test_different_seeds_give_different_bolts() -> void:
	var a := SpellFX.bolt_path(Vector2.ZERO, Vector2(200, 0), 12, 15.0, 1)
	var b := SpellFX.bolt_path(Vector2.ZERO, Vector2(200, 0), 12, 15.0, 2)
	assert_false(a == b, "stepping the seed must actually change the shape")


func test_a_zero_length_bolt_does_not_explode() -> void:
	var path := SpellFX.bolt_path(Vector2(50, 50), Vector2(50, 50), 8, 10.0, 3)
	assert_eq(path[0], Vector2(50, 50), "degenerate bolt still starts in place")
	assert_eq(path[path.size() - 1], Vector2(50, 50), "and ends in place")


# ── rings ─────────────────────────────────────────────────────────────────────

func test_ring_has_the_requested_point_count() -> void:
	assert_eq(SpellFX.ring_path(40.0, 24, 6.0, 1).size(), 24, "24 points requested")


func test_ring_radius_stays_within_jitter() -> void:
	var radius := 40.0
	var jitter := 6.0
	for point in SpellFX.ring_path(radius, 32, jitter, 5):
		var length := point.length()
		assert_true(
			length >= radius - jitter - 0.001 and length <= radius + jitter + 0.001,
			"ring point at %.1f escaped %.1f +/- %.1f" % [length, radius, jitter]
		)


func test_ring_with_no_jitter_is_a_clean_circle() -> void:
	for point in SpellFX.ring_path(30.0, 16, 0.0, 9):
		assert_almost_eq(point.length(), 30.0, "no jitter means exact radius")


func test_same_seed_gives_the_same_ring() -> void:
	var a := SpellFX.ring_path(40.0, 20, 5.0, 11)
	var b := SpellFX.ring_path(40.0, 20, 5.0, 11)
	assert_eq(a, b, "rings must be reproducible per seed too")
