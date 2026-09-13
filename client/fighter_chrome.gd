extends Resource
class_name FighterChrome

## The measurements for everything drawn *around* a fighter — the health bar, the status
## rings, the mantra, the ring under its feet. Posture and heading live on `Fighter`
## itself; these are the reads layered over the top.
##
## A `Resource`, so they tune in the inspector next to the sprite rather than as constants
## in `client/fighter.gd`. `client/art/fighter_chrome.tres` is wired into
## `client/scenes/fighter.tscn`; `Fighter` loads it as a fallback when a bare
## `Fighter.new()` in a test comes in without one.
##
## ## What is not here
##
## Hue. Every colour still comes from `client/palette.gd` — these are only sizes and
## offsets. And gameplay feel: the burst duration, the prediction thresholds and the
## dead zones stay `const` in `client/fighter.gd`, for the same reason
## `Fighter.WALK_SPEED_THRESHOLD` does — a number the netcode leans on is not a
## property of how the fighter looks.
##
## The `.tres` restates every default below so the resource opens with real values, and
## `tests/test_fighter.gd` checks the two agree.

@export_group("Health bar")
## Width of the overhead health bar, in body coordinates.
@export var health_bar_width: float = 52.0
## Height of the overhead health bar.
@export var health_bar_height: float = 6.0

@export_group("Overhead spacing")
## Gap between the top of the head and the health bar.
@export var overhead_gap: float = 6.0
## Gap between the health bar and the mantra above it.
@export var mantra_gap: float = 14.0

@export_group("Mantra")
## Point size the mantra is set in.
@export var mantra_font_size: int = 16
## Thickness of the dark halo behind the mantra, so the words read over the arena floor.
@export var mantra_outline_size: int = 3

@export_group("Status rings")
## How far outside the collision circle the paralyze ring is drawn.
@export var paralyze_ring_offset: float = 7.0
## How far outside the collision circle the poison ring is drawn.
@export var poison_ring_offset: float = 13.0

@export_group("Footing")
## Line thickness of the identity ring around the fighter's feet.
@export var footing_rim_width: float = 2.0

@export_group("Sprite anchors")
## Top of the character's head in body coordinates (negative y is up). The overhead reads
## hang off this rather than off the collision radius — the sprite is taller than the
## circle, so a bar placed above the circle would cross the mage's chest. Measured off
## `client/art/mage_idle.png`; see `client/art/README.md`.
@export var head_top: float = -61.0
## Roughly the character's middle, measured up from the feet. Body effects — the cast
## aura, the release burst — gather here rather than at the ankles, where they would read
## as a puddle. The `FX` layer in `fighter.tscn` is authored to this same point.
@export var chest: Vector2 = Vector2(0.0, -32.0)
