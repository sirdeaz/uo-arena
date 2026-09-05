extends RefCounted
class_name Palette

## The art direction, in one place.
##
## Every colour in the game is a `_draw()` argument — there are no textures, sprites or
## shaders in the repo — so this module *is* the art. Kept in `client/` rather than
## `common/` for the same reason `SpellVisuals` is: the server resolves spells without
## ever needing to know what colour a flamestrike is, and `server/` has to stay free of
## rendering concerns so the Dedicated Server export stays clean.
##
## Grouped by role rather than by hue, because the grouping is the rule: **one meaning
## per colour**. Reading an opponent at a glance is the whole skill of this game, and
## every one of those reads — cast progress, mantra, status, line of sight — is a colour
## read. A hue that carries two unrelated meanings at once costs one of them.
##
## Where two entries do share a value it is deliberate and said so at the definition:
## the thing that hit you is the thing on you.
##
## `tests/test_palette.gd` pins both halves of that rule.


# ── Backdrop ──────────────────────────────────────────────────────────────────────
# Everything signals are drawn *over*: the arena itself, and UI chrome. These are
# deliberately close to one another and low in contrast; nothing here is a read.

const FLOOR := Color("#1b1f2a")
const WALL := Color("#2b2f3a")
const COVER_FILL := Color("#4a4234")
const COVER_EDGE := Color("#8a7a5c")

## Backing for the cast bar, and the hairline around it.
const UI_PANEL := Color("#11141c")
const UI_BORDER := Color("#3a4050")

## HUD body text.
const UI_TEXT := Color("#c8d0e0")

## Near-black behind overhead text and bars, so they survive any floor under them.
const OUTLINE := Color("#0d1017")

## The empty part of a health bar. Deliberately the arena's own slate — an unfilled bar
## should recede into the scene rather than read as a second, darker bar.
const BAR_TRACK := WALL


# ── Identity ──────────────────────────────────────────────────────────────────────
# Who is who. Blue is you — body, steering cursor, and the fill of your own cast bar,
# which is your cast and so wears your colour.

const PLAYER := Color("#6ec6ff")

## The practice dummy, and later the opponent. Rose rather than red: red has one job
## here, and it is telling you that you are about to die.
const DUMMY := Color("#e07ea8")

## The spoken mantra overhead — the opponent's read on what is coming.
const MANTRA := Color("#dcd0ff")

## How many opponents `opponent_body` can tell apart before it starts repeating.
const OPPONENT_VARIANTS: int = 10

## How far either side of the rose the ramp swings, and how much lightness it trades
## across that swing. Neighbours differ on two channels rather than one, which is what
## makes ten of them separable inside a single hue family.
const OPPONENT_HUE_SPREAD: float = 0.15
const OPPONENT_VALUE_SPREAD: float = 0.42


## An opponent's body, for a `slot` the server handed out.
##
## Derived from `DUMMY` rather than listed as ten named constants, and that is the whole
## point. Ten flat hues would have to come from somewhere, and there is nowhere left to
## take them from: green is poison, orange is interrupted, yellow is paralyzed, teal is
## a released cast, red is dying. Spending those on "which player is that" would cost a
## read that actually decides fights.
##
## So the ramp says one thing — *not you* — ten slightly different ways. You are always
## `PLAYER` blue on your own screen, so the first read, the one that matters at speed,
## is a single glance at hue family; telling two opponents apart is the slower second
## read, and a lightness step is enough for it.
static func opponent_body(slot: int) -> Color:
	var t := float(posmod(slot, OPPONENT_VARIANTS)) / float(OPPONENT_VARIANTS - 1)
	var color := DUMMY
	color.h = fposmod(color.h + (t - 0.5) * OPPONENT_HUE_SPREAD, 1.0)
	color.v = clampf(color.v - (t - 0.5) * OPPONENT_VALUE_SPREAD, 0.3, 1.0)
	return color


# ── Cast feedback ─────────────────────────────────────────────────────────────────
# How a cast ended, on the cast bar and as the burst around the caster. The two always
# agree; a fizzle you see at your feet and a fizzle you see on the bar are one event.

## Released. Teal rather than green — green belongs to poison.
const CAST_SUCCEEDED := Color("#4fd6c0")

## Came to nothing, either by recasting over it or by losing the line at resolution.
const CAST_FIZZLED := Color("#8a8f9c")

## Broken by incoming damage or a paralyze landing.
const CAST_INTERRUPTED := Color("#ffa447")

## The dead time after any of the above, when nothing is castable.
const CAST_RECOVERING := Color("#5a6172")


# ── Health ────────────────────────────────────────────────────────────────────────
# Red owns exactly one meaning in this game and this is it. Full health carries no hue
# at all, so the drop to red is the only thing on the bar that ever demands attention.

const HEALTH_HEALTHY := Color("#9fb0c9")
const HEALTH_HURT := Color("#e2574c")

## Fraction of maximum health below which the bar turns.
const HEALTH_HURT_FRACTION: float = 0.35


# ── Status ────────────────────────────────────────────────────────────────────────
# Rings around a body. Each one is the colour of the spell that put it there — the ring
# is not a separate vocabulary to learn, it is the spell, still on you. `SpellVisuals`
# pulls poison and paralyze straight from here so the two can never drift apart.

const STATUS_POISONED := Color("#7ee081")
const STATUS_PARALYZED := Color("#ffd166")


# ── Sight line ────────────────────────────────────────────────────────────────────
# Whether there is a shot is a spatial fact, so it is drawn spatially: one neutral
# colour, solid when the line is live and dashed when cover has broken it. It used to
# be green-versus-red, which put it in direct competition with health and status for
# the two most loaded colours on screen.

const SIGHT_LINE := Color("#aeb8cc")
const SIGHT_LINE_CLEAR_ALPHA: float = 0.55
const SIGHT_LINE_BLOCKED_ALPHA: float = 0.28

## Dash length, in pixels, for a broken line.
const SIGHT_LINE_DASH: float = 9.0

## The line from your feet to the cursor while the move button is held.
const STEER_LINE_ALPHA: float = 0.22
const STEER_CURSOR_ALPHA: float = 0.7


# ── Spells ────────────────────────────────────────────────────────────────────────
# The bolt, the charging aura and the impact ring of each spell. Distinctness here is
# what makes the cast animation a read at all — `tests/test_spell_visuals.gd` pins it.
#
# Poison and paralyze are the status entries above, not copies of them. A spell that
# leaves something on you is drawn in the colour of the thing it leaves: what hit you
# is what is on you.

const SPELL_MAGIC_ARROW := Color("#9fd8ff")
const SPELL_POISON := STATUS_POISONED
const SPELL_LIGHTNING := Color("#fff2a8")
const SPELL_FLAMESTRIKE := Color("#ff8a4c")
const SPELL_PARALYZE := STATUS_PARALYZED

## For a spell added without a colour of its own. Deliberately drab: an unstyled spell
## should look unfinished rather than quietly pass for a real one.
const SPELL_UNKNOWN := Color("#d8d8d8")
