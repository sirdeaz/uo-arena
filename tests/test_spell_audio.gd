extends TestCase

## The audio exists to make a fizzle noticeable while your eyes are elsewhere, so what
## is worth pinning is not "a sound plays" but that the cues are actually different
## sounds — a fizzle that resembles a successful release would defeat the point of
## having any audio at all.

const ALL_CUES := [
	SpellAudio.Cue.CAST_START,
	SpellAudio.Cue.CAST_RELEASE,
	SpellAudio.Cue.FIZZLE,
	SpellAudio.Cue.INTERRUPT,
	SpellAudio.Cue.IMPACT,
]

const AUDIO_SCENE := preload("res://client/scenes/spell_audio.tscn")

var audio: SpellAudio


func before_each() -> void:
	# The voice pool is authored now, so the cue-playing tests need the scene, not a
	# bare `SpellAudio.new()` (which has no voices).
	audio = AUDIO_SCENE.instantiate()
	add_child(audio)


func after_each() -> void:
	# Stop every voice before tearing down: a player still mixing at exit keeps its
	# playback alive and shows up as a leaked object.
	audio.set_muted(true)
	audio.queue_free()


## Mean absolute sample value: a rough loudness, enough to compare two cues.
func _energy(stream: AudioStreamWAV) -> float:
	var data := stream.data
	var frames := data.size() / 2
	if frames == 0:
		return 0.0
	var total := 0.0
	for i in frames:
		total += absf(float(data.decode_s16(i * 2)) / 32768.0)
	return total / float(frames)


# ── every cue is a real sound ─────────────────────────────────────────────────

func test_every_cue_renders_audible_pcm() -> void:
	for cue in ALL_CUES:
		var stream := audio.stream_for(cue)
		assert_true(stream != null, "cue %d has no stream" % cue)
		assert_true(stream.data.size() > 0, "cue %d rendered no samples" % cue)
		assert_true(
			_energy(stream) > 0.01,
			"cue %d rendered near-silence, which is the same as not having it" % cue
		)


func test_cues_are_short_enough_not_to_trail_into_the_next_cast() -> void:
	# The fizzle chain fires release, fizzle and start within a few hundred ms.
	for cue in ALL_CUES:
		var stream := audio.stream_for(cue)
		var seconds := float(stream.data.size() / 2) / float(stream.mix_rate)
		assert_true(
			seconds > 0.05 and seconds < 0.75,
			"cue %d is %.2fs, outside the range a combat cue can occupy" % [cue, seconds]
		)


func test_streams_are_mono_16_bit_at_the_declared_rate() -> void:
	for cue in ALL_CUES:
		var stream := audio.stream_for(cue)
		assert_eq(stream.format, AudioStreamWAV.FORMAT_16_BITS, "cue %d format" % cue)
		assert_eq(stream.mix_rate, SpellAudio.SAMPLE_RATE, "cue %d mix rate" % cue)
		assert_false(stream.stereo, "cue %d should be mono" % cue)


# ── the fizzle is the one that has to stand out ───────────────────────────────

func test_no_two_cues_sound_the_same() -> void:
	for i in ALL_CUES.size():
		for j in range(i + 1, ALL_CUES.size()):
			assert_true(
				audio.stream_for(ALL_CUES[i]).data != audio.stream_for(ALL_CUES[j]).data,
				"cues %d and %d are the same sound" % [ALL_CUES[i], ALL_CUES[j]]
			)


func test_a_fizzle_does_not_sound_like_a_successful_release() -> void:
	# They fire from the same button press a quarter of a second apart. If they are
	# close in length and loudness the player cannot tell the feint from the real cast.
	var fizzle := audio.stream_for(SpellAudio.Cue.FIZZLE)
	var release := audio.stream_for(SpellAudio.Cue.CAST_RELEASE)
	assert_true(
		fizzle.data.size() > release.data.size(),
		"the fizzle should last longer than the release it replaces"
	)
	assert_true(
		_energy(fizzle) > _energy(release),
		"the fizzle should be the louder of the two — it is the one you must not miss"
	)


func test_a_fizzle_falls_in_pitch_and_a_cast_start_rises() -> void:
	# Direction of travel is what makes them recognisable without looking.
	var fizzle: Dictionary = SpellAudio.CUES[SpellAudio.Cue.FIZZLE]
	assert_true(fizzle["to_hz"] < fizzle["from_hz"], "a fizzle falls away")
	var start: Dictionary = SpellAudio.CUES[SpellAudio.Cue.CAST_START]
	assert_true(start["to_hz"] > start["from_hz"], "a cast gathers")


func test_only_the_fizzle_sputters() -> void:
	# The amplitude wobble is what makes it read as a failure rather than a note.
	for cue in ALL_CUES:
		var has_tremolo: bool = SpellAudio.CUES[cue].get("tremolo_hz", 0.0) > 0.0
		assert_eq(
			has_tremolo,
			cue == SpellAudio.Cue.FIZZLE,
			"cue %d tremolo" % cue
		)


# ── the envelope ──────────────────────────────────────────────────────────────

func test_every_cue_starts_and_ends_at_silence() -> void:
	# A cue that begins or ends mid-waveform clicks, and a click in every cue is worse
	# than no audio.
	for cue in ALL_CUES:
		var data := audio.stream_for(cue).data
		var frames := data.size() / 2
		assert_eq(data.decode_s16(0), 0, "cue %d starts with a click" % cue)
		assert_true(
			absf(float(data.decode_s16((frames - 1) * 2))) < 1200.0,
			"cue %d ends abruptly enough to click" % cue
		)


func test_the_envelope_opens_and_closes() -> void:
	assert_almost_eq(SpellAudio.envelope(0.0, 0.2, 2.0), 0.0, "silent at the attack's start")
	assert_almost_eq(SpellAudio.envelope(0.2, 0.2, 2.0), 1.0, "full at the attack's end")
	assert_almost_eq(SpellAudio.envelope(1.0, 0.2, 2.0), 0.0, "silent by the end")


# ── mute ──────────────────────────────────────────────────────────────────────

func test_muting_stops_cues_from_playing() -> void:
	assert_false(audio.is_muted(), "audio is on by default")
	assert_true(audio.play(SpellAudio.Cue.FIZZLE), "an unmuted fizzle plays")
	audio.set_muted(true)
	assert_false(audio.play(SpellAudio.Cue.FIZZLE), "a muted fizzle does not play")


func test_mute_toggles_back_on() -> void:
	assert_true(audio.toggle_muted(), "first toggle mutes")
	assert_false(audio.toggle_muted(), "second toggle unmutes")
	assert_true(audio.play(SpellAudio.Cue.IMPACT), "and cues play again")


func test_overlapping_cues_do_not_cut_each_other_off() -> void:
	# A fizzle chain fires three cues in quick succession; each needs its own voice.
	assert_true(
		SpellAudio.VOICE_COUNT >= 3,
		"a fizzle chain overlaps release, fizzle and start"
	)
	for i in SpellAudio.VOICE_COUNT:
		assert_true(audio.play(SpellAudio.Cue.CAST_START), "voice %d should be available" % i)
