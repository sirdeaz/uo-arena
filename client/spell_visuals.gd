extends RefCounted
class_name SpellVisuals

## Client-side look of each spell. Kept out of `common/` on purpose: the server
## resolves spells without ever needing to know what colour a flamestrike is.

## How a spell's energy behaves. ARC crackles in sharp angular forks; FLAME wanders in
## soft rounded tendrils. Straight from the concept art — the blue lightning and the
## orange fire read as different materials, not just different hues.
enum Style { ARC, FLAME }

const FALLBACK_COLOR := Palette.SPELL_UNKNOWN

const STYLES := {
	"Magic Arrow": Style.ARC,
	"Poison": Style.FLAME,
	"Lightning": Style.ARC,
	"Flamestrike": Style.FLAME,
	"Paralyze": Style.ARC,
}

## The colours themselves live in `Palette` so poison and paralyze can be one value
## shared with the status ring each of them leaves behind, rather than two that drift.
const COLORS := {
	"Magic Arrow": Palette.SPELL_MAGIC_ARROW,
	"Poison": Palette.SPELL_POISON,
	"Lightning": Palette.SPELL_LIGHTNING,
	"Flamestrike": Palette.SPELL_FLAMESTRIKE,
	"Paralyze": Palette.SPELL_PARALYZE,
}


static func color_for(spell: SpellData) -> Color:
	if spell == null:
		return FALLBACK_COLOR
	return COLORS.get(spell.spell_name, FALLBACK_COLOR)


static func style_for(spell: SpellData) -> Style:
	if spell == null:
		return Style.ARC
	return STYLES.get(spell.spell_name, Style.ARC)
