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
		["magic_arrow", "poison", "lightning", "flamestrike", "paralyze", "cure"],
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


# ── Number-row hotkeys ────────────────────────────────────────────────────────────
# The keys are matched on `physical_keycode`, not `keycode`, so the number row begins
# the same spells on every layout. On AZERTY, `keycode` reported `& é " ' (` and four
# of the five keys never matched — see the issue this file's `spell_id_for_hotkey`
# closes.


func test_the_number_row_maps_to_the_spells_in_order() -> void:
	assert_eq(SpellBook.spell_id_for_hotkey(KEY_1), 0, "1 begins magic arrow")
	assert_eq(SpellBook.spell_id_for_hotkey(KEY_2), 1, "2 begins poison")
	assert_eq(SpellBook.spell_id_for_hotkey(KEY_3), 2, "3 begins lightning")
	assert_eq(SpellBook.spell_id_for_hotkey(KEY_4), 3, "4 begins flamestrike")
	assert_eq(SpellBook.spell_id_for_hotkey(KEY_5), 4, "5 begins paralyze")
	assert_eq(SpellBook.spell_id_for_hotkey(KEY_6), 5, "6 begins cure")


func test_every_hotkey_resolves_to_a_real_spell() -> void:
	# Guards a rename in HOTKEY_STEMS drifting from IDS: a stem with no id would hand a
	# pressed key a -1 and silently do nothing, which is the bug all over again.
	for physical_keycode in SpellBook.HOTKEY_STEMS:
		var id := SpellBook.spell_id_for_hotkey(physical_keycode)
		assert_true(id >= 0, "%s maps to a stem with no wire id" % physical_keycode)
		assert_true(SpellBook.spell_for(id) != null, "%s names no spell" % physical_keycode)


func test_a_key_off_the_number_row_is_not_a_hotkey() -> void:
	assert_eq(SpellBook.spell_id_for_hotkey(KEY_0), -1, "0 is not a spell key")
	assert_eq(SpellBook.spell_id_for_hotkey(KEY_7), -1, "there is no seventh spell")
	assert_eq(SpellBook.spell_id_for_hotkey(KEY_A), -1, "a letter is not a spell key")
	assert_eq(SpellBook.spell_id_for_hotkey(0), -1, "an unreported physical keycode is not a hotkey")
