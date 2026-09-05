extends RefCounted
class_name SpellVisuals

## Client-side look of each spell. Kept out of `common/` on purpose: the server
## resolves spells without ever needing to know what colour a flamestrike is.

## How a spell's energy behaves. ARC crackles in sharp angular forks; FLAME wanders in
## soft rounded tendrils. Straight from the concept art — the blue lightning and the
## orange fire read as different materials, not just different hues.
enum Style { ARC, FLAME }

const FALLBACK_COLOR := Color("#d8d8d8")

const STYLES := {
	"Magic Arrow": Style.ARC,
	"Poison": Style.FLAME,
	"Lightning": Style.ARC,
	"Flamestrike": Style.FLAME,
	"Paralyze": Style.ARC,
}

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


static func style_for(spell: SpellData) -> Style:
	if spell == null:
		return Style.ARC
	return STYLES.get(spell.spell_name, Style.ARC)
