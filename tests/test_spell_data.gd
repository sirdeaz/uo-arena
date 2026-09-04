extends TestCase

## Every spell speaks its mantra overhead while being cast. Reading those words is how
## an opponent knows what is coming and whether it is worth breaking line of sight —
## it is the information the fizzle-feint exists to exploit, so the words have to be
## right and every spell has to have them.

const EXPECTED_MANTRAS := {
	"magic_arrow": "In Por Ylem",
	"poison": "In Nox",
	"lightning": "Por Ort Grav",
	"flamestrike": "Kal Vas Flam",
	"paralyze": "An Ex Por",
}


func _spell(spell_name: String) -> SpellData:
	return load("res://common/spells/%s.tres" % spell_name)


func test_every_spell_has_a_mantra() -> void:
	for spell_name in EXPECTED_MANTRAS:
		assert_false(
			_spell(spell_name).mantra.is_empty(),
			"%s must have words to speak, or there is no tell" % spell_name
		)


func test_mantras_are_the_uo_words() -> void:
	for spell_name in EXPECTED_MANTRAS:
		assert_eq(
			_spell(spell_name).mantra,
			EXPECTED_MANTRAS[spell_name],
			"%s should speak its real UO words" % spell_name
		)


func test_mantras_are_distinct() -> void:
	# Two spells sharing words would make them impossible to tell apart mid-cast.
	var seen: Array[String] = []
	for spell_name in EXPECTED_MANTRAS:
		var mantra: String = _spell(spell_name).mantra
		assert_false(seen.has(mantra), "%s reuses another spell's words" % spell_name)
		seen.append(mantra)


func test_every_spell_has_a_display_name() -> void:
	for spell_name in EXPECTED_MANTRAS:
		assert_false(
			_spell(spell_name).spell_name.is_empty(), "%s needs a name" % spell_name
		)
