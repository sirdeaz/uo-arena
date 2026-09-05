extends RefCounted
class_name SpellVisuals

## Client-side look of each spell. Kept out of `common/` on purpose: the server
## resolves spells without ever needing to know what colour a flamestrike is.

## The face a caster speaks in. The mantra is diegetic — a character saying the words
## overhead — so it gets a display face, while the cast bar caption stays in the UI font
## because that is interface, not speech. Bundled and subset; see `client/fonts/`.
const MANTRA_FONT: Font = preload("res://client/fonts/UncialAntiqua-Regular.ttf")

const FALLBACK_COLOR := Color("#d8d8d8")

const COLORS := {
	"Magic Arrow": Color("#9fd8ff"),
	"Poison": Color("#7ee081"),
	"Lightning": Color("#fff2a8"),
	"Flamestrike": Color("#ff8a4c"),
	"Paralyze": Color("#ffd166"),
}


static func color_for(spell: SpellData) -> Color:
	if spell == null:
		return FALLBACK_COLOR
	return COLORS.get(spell.spell_name, FALLBACK_COLOR)
