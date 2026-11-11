shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 glow_color : source_color = vec4(0.9, 0.25, 0.9, 0.5);
uniform float swirl_speed : hint_range(0.0, 10.0) = 2.0;
uniform float pulse_speed : hint_range(0.0, 10.0) = 3.0;
uniform float emission_strength : hint_range(0.0, 5.0) = 3.0;
uniform float vibrance : hint_range(0.0, 2.0) = 1.35;

// Vibrance: push the energy field away from grey (white parts keep their hue).
vec3 vivid(vec3 c, float amount) {
	float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
	return clamp(mix(vec3(lum), c, amount), vec3(0.0), vec3(1.0));
}

void fragment() {
	// Animated UV swirl for a spinning energy field look
	vec2 uv = UV + vec2(
		sin(TIME * swirl_speed + UV.y * 4.0),
		cos(TIME * swirl_speed + UV.x * 4.0)
	) * 0.12;

	float t = TIME * pulse_speed;
	float pulse = sin(t * 0.5) * 0.25 + 0.75;

	float alpha = clamp(glow_color.a * pulse, 0.0, 1.0);

	// Brighten near the ring edges (inner/outer radius of the torus)
	float edge = 1.0 - abs(distance(uv, vec2(0.5)) * 2.0 - 1.0) * 2.0;
	edge = clamp(edge, 0.0, 1.0);

	vec3 base = vivid(glow_color.rgb, vibrance);
	vec3 emission = base * emission_strength * edge * pulse;

	ALBEDO = base;
	ALPHA = alpha;
	EMISSION = emission;
}
