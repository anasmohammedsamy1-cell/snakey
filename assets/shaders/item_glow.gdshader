shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 glow_color : source_color = vec4(1.0, 0.9, 0.3, 0.9);
uniform float pulse_speed : hint_range(0.0, 10.0) = 4.0;
uniform float emission_strength : hint_range(0.0, 8.0) = 4.0;
uniform float vibrance : hint_range(0.0, 2.0) = 1.35;

void fragment() {
	float t = TIME * pulse_speed;
	float pulse = sin(t) * 0.2 + 0.8;
	float alpha = clamp(glow_color.a * pulse, 0.0, 1.0);
	// Vibrance: push the glow away from grey so items pop against the arena.
	vec3 base = glow_color.rgb;
	float lum = dot(base, vec3(0.2126, 0.7152, 0.0722));
	base = clamp(mix(vec3(lum), base, vibrance), vec3(0.0), vec3(1.0));
	vec3 emission = base * emission_strength * pulse;
	ALBEDO = base;
	ALPHA = alpha;
	EMISSION = emission;
}
