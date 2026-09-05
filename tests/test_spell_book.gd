extends TestCase

## The spell ids are a wire contract between two builds that may not be the same build.
## Everything here exists to make a change to that contract fail loudly at home rather
## than quietly in someone else's match.


func test_every_spell_round_trips_through_its_id() -> void:
	for id in SpellBook.IDS.size():
		var spell := SpellBook.spell_for(id)
		assert_eq(SpellBook.id_of(spell), id, "%s lost its id on the way back" % id)


func test_the_id_order_is_pinned() -> void:
	# Reordering this list silently repoints every spell in flight. If you are here
	# because this failed, append instead.
	assert_eq(
		SpellBook.IDS,
		["magic_arrow", "poison", "lightning", "flamestrike", "paralyze"],
		"spell ids may be appended to, never reordered"
	)


func test_every_spell_resource_has_an_id() -> void:
	# Catches the real mistake: adding a .tres and forgetting the book, which leaves a
	# spell that is castable locally and unsendable.
	var dir := DirAccess.open(SpellBook.DIRECTORY)
	assert_true(dir != null, "the spell directory should be readable")
	for file_name in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var stem := file_name.get_basename()
		assert_true(
			SpellBook.IDS.has(stem), "%s exists but has no wire id" % stem
		)


func test_an_unknown_id_resolves_to_nothing() -> void:
	# Ids arrive from clients, so out-of-range is an input case, not an impossible one.
	assert_eq(SpellBook.spell_for(-1), null, "a negative id names no spell")
	assert_eq(SpellBook.spell_for(9999), null, "an id past the end names no spell")


func test_a_null_spell_has_no_id() -> void:
	assert_eq(SpellBook.id_of(null), -1, "an idle caster carries no spell id")


func test_an_unregistered_spell_has_no_id() -> void:
	var unknown := SpellData.new()
	unknown.spell_name = "Summon Daemon"
	assert_eq(SpellBook.id_of(unknown), -1, "a spell outside the book cannot be sent")


func test_a_duplicated_spell_keeps_its_id() -> void:
	# duplicate() clears resource_path, so matching on the path would break here. Tests
	# duplicate spells routinely, and so will anything that ever buffs one.
	var original := SpellBook.by_name("flamestrike")
	var copy := original.duplicate() as SpellData
	copy.requires_line_of_sight = false
	assert_eq(
		SpellBook.id_of(copy), SpellBook.id_of(original), "a copy is still flamestrike"
	)


func test_lookup_by_name_matches_lookup_by_id() -> void:
	assert_eq(
		SpellBook.by_name("lightning"),
		SpellBook.spell_for(2),
		"the two lookups must agree"
	)
	assert_eq(SpellBook.by_name("summon_daemon"), null, "an unknown stem is null")
