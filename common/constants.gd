extends Node
class_name Constants

const DEFAULT_PORT: int = 24567
const MAX_PLAYERS: int = 2

const PLAYER_MAX_HEALTH: float = 100.0
const PLAYER_MOVE_SPEED: float = 225.0

# Physics layer bits, mirroring project.godot's layer_names.
const LAYER_PLAYERS: int = 1 << 0
const LAYER_OBSTACLES: int = 1 << 1
const LAYER_PROJECTILES: int = 1 << 2

# Grace period after a cast completes before another may start.
const GLOBAL_CAST_RECOVERY_SECONDS: float = 0.25
