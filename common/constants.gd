extends Node
class_name Constants

const DEFAULT_PORT: int = 24567
const MAX_PLAYERS: int = 10

## Bumped whenever the shape of anything on the wire changes. A client whose number
## disagrees with the server's is refused at the door rather than left to misread
## records — a mismatched snapshot layout fails silently and confusingly otherwise.
const PROTOCOL_VERSION: int = 1

const PLAYER_MAX_HEALTH: float = 100.0
const PLAYER_MOVE_SPEED: float = 225.0

## Body radius. Lives here rather than on `Fighter` because the server needs the same
## number to build its own collision shape, and `server/` must not reach into `client/`.
const PLAYER_RADIUS: float = 18.0

# Physics layer bits, mirroring project.godot's layer_names.
const LAYER_PLAYERS: int = 1 << 0
const LAYER_OBSTACLES: int = 1 << 1
const LAYER_PROJECTILES: int = 1 << 2

# Grace period after a cast completes before another may start.
const GLOBAL_CAST_RECOVERY_SECONDS: float = 0.25

## How often the server broadcasts world state. A third of the 60 Hz physics rate:
## often enough that a 225 px/s runner only travels 11 px between updates, cheap enough
## that ten players cost well under 20 KB/s downstream each.
const SNAPSHOT_HZ: int = 20

## How long a corpse lies there before it stands back up. Long enough that dying costs
## you the fight you were in, short enough that you are not watching from the sidelines.
const RESPAWN_SECONDS: float = 4.0

## The server drops a player's steering to zero if nothing has arrived for this long.
## Input is sent unreliably, so a dropped "I let go of the button" packet would
## otherwise leave someone jogging into a wall until they pressed it again.
const INPUT_TIMEOUT_SECONDS: float = 0.5

## Ceiling on accepted cast requests per player per second. The state machine already
## denies casts during recovery, but nothing stops a modified client from asking at
## wire speed, and every request costs the server a raycast.
const MAX_CAST_REQUESTS_PER_SECOND: int = 20
