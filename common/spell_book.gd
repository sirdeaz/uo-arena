extends RefCounted
class_name SpellBook

## Stable integer ids for the spells, so a cast crosses the network as one small number.
##
## The index in `IDS` is the wire format — never the resource path, never `spell_name`.
## Both of those are editable text a rename can change, and two builds that disagreed
## about one would silently cast different spells at each other. The id is the contract.
##
## Order is therefore fixed: append to the end, never reorder, never remove.

const DIRECTORY := "res://common/spells"

const IDS: Array[String] = [
	"magic_arrow",
	"poison",
	"lightning",
	"flamestrike",
	"paralyze",
]

static var _by_id: Array[SpellData] = []
static var _id_by_name: Dictionary = {}


## The spell an id names, or null when the id is not one we know.
##
## Callers must read null as "refuse this request" rather than "no spell" — an id off
## the wire that resolves to nothing is a client talking nonsense.
##
## Returns the shared cached resource, as `load()` always has. Never mutate what comes
## back; `duplicate()` first.
static func spell_for(id: int) -> SpellData:
	_ensure_loaded()
	if id < 0 or id >= _by_id.size():
		return null
	return _by_id[id]


## The id of a spell, or -1 for null and for anything not in the book.
##
## Matches on `spell_name` rather than `resource_path` because `duplicate()` clears the
## path, and duplicating a spell to flip one field is a normal thing to do.
static func id_of(spell: SpellData) -> int:
	if spell == null:
		return -1
	_ensure_loaded()
	if not _id_by_name.has(spell.spell_name):
		return -1
	return _id_by_name[spell.spell_name]


## Lookup by resource filename, replacing the `load("...%s.tres")` line that had been
## copy-pasted into every caller that needed a spell by name.
static func by_name(stem: String) -> SpellData:
	return spell_for(IDS.find(stem))


static func _ensure_loaded() -> void:
	if not _by_id.is_empty():
		return
	for stem in IDS:
		var spell: SpellData = load("%s/%s.tres" % [DIRECTORY, stem])
		_id_by_name[spell.spell_name] = _by_id.size()
		_by_id.append(spell)
