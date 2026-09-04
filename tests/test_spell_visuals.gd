extends TestCase

## Spell colour is client presentation, so it lives in `client/` rather than on
## `SpellData` in `common/` — the server has no business knowing what orange means.
## Distinctness is the part worth pinning: two spells sharing a colour would make the
## cast animation useless as a read, the same way a duplicated mantra would.

const SPELL_NAMES := [
	"magic_arrow", "poison", "lightning", "flamestrike", "paralyze",
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
