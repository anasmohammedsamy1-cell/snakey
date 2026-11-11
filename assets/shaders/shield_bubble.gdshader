shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 glow_color : source_color = vec4(0.3, 0.85, 1.0, 0.5);
uniform float pulse_speed : hint_range(0.0, 10.0) = 4.0;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.3;
uniform float rim_power : hint_range(0.0, 8.0) = 4.0;
uniform float emission_strength : hint_range(0.0, 5.0) = 3.0;
uniform float vibrance : hint_range(0.0, 2.0) = 1.35;

void fragment() {
	float t = TIME * pulse_speed;
	float pulse = sin(t) * pulse_amount;
	float alpha = clamp(glow_color.a + pulse, 0.0, 1.0);

	// Fresnel rim glow: brighter at the bubble's silhouette edge
	float fresnel = 1.0 - abs(dot(NORMAL, VIEW));
	fresnel = pow(fresnel, rim_power);

	// Vibrance: push the shield away from grey so it reads as a real energy bubble.
	vec3 base = glow_color.rgb;
	float lum = dot(base, vec3(0.2126, 0.7152, 0.0722));
	base = clamp(mix(vec3(lum), base, vibrance), vec3(0.0), vec3(1.0));

	vec3 emission = base * emission_strength * (0.5 + fresnel * 0.5 + pulse * 0.5);

	ALBEDO = base;
	ALPHA = alpha;
	EMISSION = emission;
}
