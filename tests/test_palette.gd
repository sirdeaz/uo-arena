extends TestCase

## The palette's rule is one meaning per colour, and this is what holds it.
##
## Reading an opponent at a glance is the whole skill of the game, and every one of
## those reads is a colour read. Green used to mean poison, healthy, poisoned, cast
## succeeded *and* line-of-sight clear; red meant hurt, fizzled, blocked and "that is
## the enemy". A poisoned player at full health drew a green ring inside a green bar
## beside a green sight line, hit by a green bolt.
##
## Two things are pinned here. Nothing that means one thing may share a value with
## something that means another — and the handful of shared values that *are* deliberate
## must stay shared, since they are the whole reason a status ring is legible without
## being learned.

## Colours grouped by the axis they speak on. Each entry appears exactly once, under the
## meaning that owns it: poison and paralyze live in `status` because their spell
## colours are those same entries by design, asserted below.
const AXES := {
	# Scenery and chrome — the things signals are drawn over. Deliberately low contrast
	# against each other; nothing in here is a read, so they are exempt from the
	# distinctness check below.
	"backdrop": {
		"floor": Palette.FLOOR,
		"wall": Palette.WALL,
		"cover fill": Palette.COVER_FILL,
		"cover edge": Palette.COVER_EDGE,
		"ui panel": Palette.UI_PANEL,
		"ui border": Palette.UI_BORDER,
		"ui text": Palette.UI_TEXT,
		"outline": Palette.OUTLINE,
		# Deliberately the wall's own slate, and on the same axis as it.
		"health bar track": Palette.BAR_TRACK,
	},
	"identity": {
		"player": Palette.PLAYER,
		"dummy": Palette.DUMMY,
		"mantra": Palette.MANTRA,
	},
	"cast feedback": {
		"succeeded": Palette.CAST_SUCCEEDED,
		"fizzled": Palette.CAST_FIZZLED,
		"interrupted": Palette.CAST_INTERRUPTED,
		"recovering": Palette.CAST_RECOVERING,
	},
	"health": {
		"healthy": Palette.HEALTH_HEALTHY,
		"hurt": Palette.HEALTH_HURT,
	},
	"status": {
		"poisoned": Palette.STATUS_POISONED,
		"paralyzed": Palette.STATUS_PARALYZED,
	},
	"sight line": {
		"sight line": Palette.SIGHT_LINE,
	},
	"spell": {
		"magic arrow": Palette.SPELL_MAGIC_ARROW,
		"lightning": Palette.SPELL_LIGHTNING,
		"flamestrike": Palette.SPELL_FLAMESTRIKE,
		"unknown spell": Palette.SPELL_UNKNOWN,
	},
}

## Axes whose entries have to be told apart at a glance, mid-fight, at the default 0.85
## camera zoom. `backdrop` is excluded on purpose — floor and wall being a shade apart
## is the point of them.
const READ_AT_A_GLANCE := ["identity", "cast feedback", "health", "status", "spell"]

## Minimum RGB separation within one of those axes. Low enough to leave room for a
## palette of this size, high enough that nothing here is a near-miss of its neighbour.
const MIN_SEPARATION: float = 0.12


func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _spell(spell_name: String) -> SpellData:
	return load("res://common/spells/%s.tres" % spell_name)


## The headline rule. A value used on two axes means one of the two reads is gone.
func test_no_colour_carries_two_unrelated_meanings() -> void:
	var claimed := {}
	for axis in AXES:
		for meaning in AXES[axis]:
			var color: Color = AXES[axis][meaning]
			var key := color.to_html()
			if claimed.has(key):
				assert_true(
					claimed[key][0] == axis,
					"%s means both '%s' (%s) and '%s' (%s)" % [
						key, claimed[key][1], claimed[key][0], meaning, axis
					]
				)
			else:
				claimed[key] = [axis, meaning]
	# Nothing collided; record the pass so the run reports real coverage.
	assert_true(claimed.size() > 0, "the palette should not be empty")


func test_meanings_on_one_axis_are_told_apart_at_a_glance() -> void:
	for axis in READ_AT_A_GLANCE:
		var entries: Dictionary = AXES[axis]
		var names: Array = entries.keys()
		for i in names.size():
			for j in range(i + 1, names.size()):
				var separation := _distance(entries[names[i]], entries[names[j]])
				assert_true(
					separation >= MIN_SEPARATION,
					"%s: '%s' and '%s' are only %.3f apart" % [
						axis, names[i], names[j], separation
					]
				)


## The one reuse that is deliberate: a status ring is the spell that put it there,
## still on you. Break the pairing and the ring becomes a second vocabulary to learn.
func test_a_status_ring_is_the_colour_of_the_spell_that_caused_it() -> void:
	assert_eq(
		SpellVisuals.color_for(_spell("poison")),
		Palette.STATUS_POISONED,
		"the poison ring should be poison's own colour"
	)
	assert_eq(
		SpellVisuals.color_for(_spell("paralyze")),
		Palette.STATUS_PARALYZED,
		"the paralyze ring should be paralyze's own colour"
	)


## Every spell resolves through the palette, so retuning the look is one file.
func test_every_spell_colour_comes_from_the_palette() -> void:
	const FROM_PALETTE := {
		"magic_arrow": Palette.SPELL_MAGIC_ARROW,
		"poison": Palette.SPELL_POISON,
		"lightning": Palette.SPELL_LIGHTNING,
		"flamestrike": Palette.SPELL_FLAMESTRIKE,
		"paralyze": Palette.SPELL_PARALYZE,
	}
	for spell_name in FROM_PALETTE:
		assert_eq(
			SpellVisuals.color_for(_spell(spell_name)),
			FROM_PALETTE[spell_name],
			"%s should draw in its palette colour" % spell_name
		)


## Health and the sight line were the two loudest offenders; these pin the fix rather
## than the specific replacements, which are free to be retuned.
func test_health_no_longer_speaks_the_language_of_poison() -> void:
	assert_false(
		Palette.HEALTH_HEALTHY == Palette.STATUS_POISONED,
		"a healthy bar must not look like a poisoned ring"
	)
	assert_false(
		Palette.HEALTH_HEALTHY == Palette.CAST_SUCCEEDED,
		"a healthy bar must not look like a cast landing"
	)


func test_the_sight_line_is_one_colour_and_reads_by_shape() -> void:
	# Clear versus blocked is a solid line versus a dashed one. If the two ever differ
	# by hue again they are back to competing with health and status.
	assert_true(
		Palette.SIGHT_LINE_CLEAR_ALPHA > Palette.SIGHT_LINE_BLOCKED_ALPHA,
		"a live line should be the brighter of the two"
	)
	assert_true(Palette.SIGHT_LINE_DASH > 0.0, "a broken line needs a dash length")


## The palette is only worth having if the client actually goes through it.
func test_the_client_holds_no_colour_literals_of_its_own() -> void:
	var dir := DirAccess.open("res://client")
	assert_true(dir != null, "res://client should be readable")
	if dir == null:
		return

	for file_name in dir.get_files():
		if not file_name.ends_with(".gd") or file_name == "palette.gd":
			continue
		var source := FileAccess.get_file_as_string("res://client/%s" % file_name)
		assert_false(
			source.contains('Color("#'),
			"%s writes a hex colour of its own instead of using Palette" % file_name
		)
