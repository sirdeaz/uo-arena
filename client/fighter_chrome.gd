extends Resource
class_name FighterChrome

## The measurements for everything drawn *around* a fighter — the health bar, the status
## rings, the mantra, the ring under its feet. Posture and heading live in `FighterSprite`;
## these are the reads layered over the top.
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
## `FighterSprite.WALK_SPEED_THRESHOLD` does — a number the netcode leans on is not a
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
