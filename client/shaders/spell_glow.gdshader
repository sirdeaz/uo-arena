shader_type canvas_item;
render_mode blend_add;

// Real falloff-based glow, replacing the three stacked flat-alpha strokes/discs
// SpellFX used to draw (#151). Every mesh SpellFX submits — a stroke strip or a
// disc's bounding quad — carries the same UV convention: a signed offset from the
// shape's own centre, one unit per axis, so `length(UV)` reads as "distance from
// the light" whichever shape it is. That is what lets one shader serve both without
// a mode switch, and it is also why the mesh-building lives in SpellFX rather than
// here: this file only turns a distance into a colour.

uniform float core_bias : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	float d = length(UV);
	float falloff = pow(clamp(1.0 - d, 0.0, 1.0), 2.2);
	vec3 rgb = mix(COLOR.rgb, vec3(1.0), falloff * falloff * core_bias);
	COLOR = vec4(rgb, COLOR.a * falloff);
}
