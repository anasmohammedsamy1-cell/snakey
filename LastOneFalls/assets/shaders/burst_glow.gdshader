shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 glow_color : source_color = vec4(1.0, 0.9, 0.3, 0.9);
uniform float emission_strength : hint_range(0.0, 8.0) = 4.0;
uniform float pulse_speed : hint_range(0.0, 10.0) = 6.0;
uniform float vibrance : hint_range(0.0, 2.0) = 1.35;

void fragment() {
	// COLOR comes from the particle system (per-particle color + alpha over lifetime)
	float alpha = COLOR.a * glow_color.a;
	alpha = clamp(alpha, 0.0, 1.0);

	// Subtle shimmer on each particle
	float shimmer = sin(TIME * pulse_speed + COLOR.r * 10.0) * 0.15 + 0.85;

	// Vibrance: push each particle (and the base tint) away from grey so the
	// bursts read as saturated sparks instead of pale dust.
	vec3 tinted = glow_color.rgb * COLOR.rgb;
	float lum = dot(tinted, vec3(0.2126, 0.7152, 0.0722));
	tinted = clamp(mix(vec3(lum), tinted, vibrance), vec3(0.0), vec3(1.0));

	vec3 emission = tinted * emission_strength * shimmer;

	ALBEDO = tinted;
	ALPHA = alpha;
	EMISSION = emission;
}
