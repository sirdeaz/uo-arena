extends TestCase

## Spell colour is client presentation, so it lives in `client/` rather than on
## `SpellData` in `common/` — the server has no business knowing what orange means.
## Distinctness is the part worth pinning: two spells sharing a colour would make the
## cast animation useless as a read, the same way a duplicated mantra would.

const SPELL_NAMES := [
	"magic_arrow", "poison", "lightning", "flamestrike", "paralyze", "cure",
]


func _spell(spell_name: String) -> SpellData:
	return load("res://common/spells/%s.tres" % spell_name)


func test_every_spell_has_its_own_colour() -> void:
	var seen: Array[Color] = []
	for spell_name in SPELL_NAMES:
		var color := SpellVisuals.color_for(_spell(spell_name))
		assert_false(seen.has(color), "%s reuses another spell's colour" % spell_name)
		seen.append(color)


func test_colours_are_not_the_fallback() -> void:
	for spell_name in SPELL_NAMES:
		assert_false(
			SpellVisuals.color_for(_spell(spell_name)) == SpellVisuals.FALLBACK_COLOR,
			"%s should have a deliberate colour, not the fallback" % spell_name
		)


func test_an_unknown_spell_falls_back_rather_than_erroring() -> void:
	var unknown := SpellData.new()
	unknown.spell_name = "Summon Daemon"
	assert_eq(
		SpellVisuals.color_for(unknown),
		SpellVisuals.FALLBACK_COLOR,
		"a spell added without a colour should still draw"
	)


func test_a_null_spell_falls_back() -> void:
	# Draw code can race a cast ending; this must not crash the client.
	assert_eq(
		SpellVisuals.color_for(null), SpellVisuals.FALLBACK_COLOR, "null must be safe"
	)


# ── the mantra face ───────────────────────────────────────────────────────────

func test_mantras_use_the_bundled_display_face_not_the_ui_font() -> void:
	# The mantra is a character speaking; the cast bar caption is chrome. Falling back
	# to the engine's UI font would quietly undo that split.
	assert_true(SpellVisuals.MANTRA_FONT != null, "the mantra font must be bundled")
	assert_eq(
		SpellVisuals.MANTRA_FONT.get_font_name(),
		"Uncial Antiqua",
		"mantras should be spoken in the bundled display face"
	)
	assert_true(
		SpellVisuals.MANTRA_FONT != ThemeDB.fallback_font,
		"the mantra face must not be the engine's default UI font"
	)


func test_the_subset_font_can_spell_every_mantra() -> void:
	# The font ships subset. A spell added with a character the subset dropped would
	# render a blank box overhead — and the mantra is the opponent's only read.
	for spell_name in SPELL_NAMES:
		var mantra: String = _spell(spell_name).mantra
		for index in mantra.length():
			var codepoint := mantra.unicode_at(index)
			assert_true(
				SpellVisuals.MANTRA_FONT.has_char(codepoint),
				"the subset font has no glyph for '%s' in %s" % [mantra[index], mantra]
			)


func test_mantras_are_measurable_so_they_can_be_centred_overhead() -> void:
	for spell_name in SPELL_NAMES:
		var mantra: String = _spell(spell_name).mantra
		var width := SpellVisuals.MANTRA_FONT.get_string_size(
			mantra, HORIZONTAL_ALIGNMENT_LEFT, -1, Fighter.MANTRA_FONT_SIZE
		).x
		assert_true(width > 0.0, "%s should have a measurable width" % mantra)
		assert_true(
			width < 400.0,
			"%s is %.0fpx wide, too wide to hang over a %.0fpx fighter" % [
				mantra, width, Fighter.RADIUS * 2.0
			]
		)
