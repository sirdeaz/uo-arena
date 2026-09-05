extends Node
class_name SpellAudio

## The ear half of the cast read. Classic UO magery is heavily ear-driven — you learn to
## hear a cast start, a spell land and a fizzle without watching the caster — and this
## game needs that more than most, because the mechanic it is built around is the one
## with the weakest visual.
##
## A fizzle is a grey ring collapsing inward at the caster's feet, and it happens at the
## exact moment the opponent is watching the sight line and their own footing instead. A
## sound does not care where you are looking, which is why the fizzle cue is the loudest,
## longest and most obviously *wrong* of the five.
##
## Every cue is synthesised at load into an `AudioStreamWAV`: no audio files, nothing
## added to the download, and the same everything-is-generated approach the rest of the
## client takes. Swapping in recorded samples later means changing `CUES` and nothing
## else.
##
## Blocked spells stay silent, matching the existing rule that they draw nothing at all —
## in UO a spell with no line simply never goes off.

enum Cue { CAST_START, CAST_RELEASE, FIZZLE, INTERRUPT, IMPACT }

const SAMPLE_RATE: int = 22050

## Cues overlap constantly — a fizzle chain fires release, fizzle and start inside a few
## hundred milliseconds — so they get a small pool of players rather than cutting each
## other off.
const VOICE_COUNT: int = 6

const MASTER_VOLUME_DB: float = -8.0

## Each cue is a short shaped tone. Sweeping downward reads as failure and upward as
## gathering, so the two halves of the cast are told apart by shape rather than pitch
## alone — which is what makes them recognisable while your eyes are elsewhere.
##
##   from_hz/to_hz  pitch sweep across the sound
##   attack         fraction of the length spent fading in; near zero is percussive
##   curve          how sharply it decays; higher is more of a hit than a note
##   noise          how much white noise is blended in, for impacts and hits
##   tremolo_hz     amplitude wobble, which is what makes the fizzle sputter
const CUES := {
	Cue.CAST_START: {
		"duration": 0.30, "from_hz": 190.0, "to_hz": 300.0,
		"attack": 0.35, "curve": 1.2, "gain": 0.22,
	},
	Cue.CAST_RELEASE: {
		"duration": 0.34, "from_hz": 540.0, "to_hz": 300.0,
		"attack": 0.02, "curve": 2.2, "gain": 0.30,
	},
	# The one that has to survive not being looked at: long, falling, and sputtering.
	Cue.FIZZLE: {
		"duration": 0.46, "from_hz": 310.0, "to_hz": 105.0,
		"attack": 0.01, "curve": 0.9, "gain": 0.52,
		"noise": 0.22, "tremolo_hz": 26.0,
	},
	Cue.INTERRUPT: {
		"duration": 0.20, "from_hz": 250.0, "to_hz": 85.0,
		"attack": 0.005, "curve": 3.6, "gain": 0.40, "noise": 0.5,
	},
	Cue.IMPACT: {
		"duration": 0.36, "from_hz": 165.0, "to_hz": 55.0,
		"attack": 0.004, "curve": 2.6, "gain": 0.45, "noise": 0.35,
	},
}

var _streams := {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _muted: bool = false


func _init() -> void:
	for cue in CUES:
		_streams[cue] = render(CUES[cue])


func _ready() -> void:
	for i in VOICE_COUNT:
		var player := AudioStreamPlayer.new()
		player.volume_db = MASTER_VOLUME_DB
		add_child(player)
		_voices.append(player)


## Plays a cue, returning whether it actually started. Nothing here waits on a browser's
## audio context: on the web the first cues can land before the player has clicked
## anything and are simply dropped, which is silent rather than broken.
func play(cue: Cue) -> bool:
	if _muted or _voices.is_empty() or not _streams.has(cue):
		return false
	var player := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	player.stream = _streams[cue]
	player.play()
	return true


func set_muted(muted: bool) -> void:
	_muted = muted
	for player in _voices:
		if muted:
			player.stop()


func is_muted() -> bool:
	return _muted


func toggle_muted() -> bool:
	set_muted(not _muted)
	return _muted


func stream_for(cue: Cue) -> AudioStreamWAV:
	return _streams.get(cue)


## Renders one cue spec to 16-bit mono PCM.
##
## Phase is accumulated sample by sample rather than recomputed from the current
## frequency, which is the difference between a pitch that glides and one that warbles.
static func render(spec: Dictionary) -> AudioStreamWAV:
	var duration: float = spec["duration"]
	var frames := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(frames * 2)

	# Seeded, so a cue sounds identical every time it plays and between runs.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec["from_hz"]) * 1000 + int(spec["to_hz"])

	var noise: float = spec.get("noise", 0.0)
	var tremolo: float = spec.get("tremolo_hz", 0.0)
	var gain: float = spec.get("gain", 0.3)
	var attack: float = spec.get("attack", 0.05)
	var curve: float = spec.get("curve", 2.0)

	var phase := 0.0
	for i in frames:
		var progress := float(i) / float(frames)
		var frequency: float = lerpf(spec["from_hz"], spec["to_hz"], progress)
		phase += TAU * frequency / float(SAMPLE_RATE)

		var value := sin(phase)
		if noise > 0.0:
			value = lerpf(value, rng.randf_range(-1.0, 1.0), noise)
		if tremolo > 0.0:
			value *= 0.55 + 0.45 * sin(TAU * tremolo * progress * duration)

		value *= envelope(progress, attack, curve) * gain
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream


## Fade in over `attack` (as a fraction of the sound), then decay to silence. A higher
## `curve` drops away faster, which is what separates a hit from a held note.
static func envelope(progress: float, attack: float, curve: float) -> float:
	if attack > 0.0 and progress < attack:
		return progress / attack
	var tail := (progress - attack) / maxf(1.0 - attack, 0.0001)
	return pow(maxf(1.0 - tail, 0.0), curve)
