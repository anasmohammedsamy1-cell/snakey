// Procedural floor detail (no textures): a soft checker, thin darker seams
// along the cell borders and a gentle noise-free sinusoidal gradient, all
// computed in the shader from the local (model-space) position. Lit by the
// scene lights through ALBEDO + ROUGHNESS only, so it behaves like the plain
// StandardMaterial3D it replaces.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(1.0);
uniform float roughness = 0.7;
uniform float cell_size = 1.5;                    // metres per pattern cell
uniform float detail_amount : hint_range(0.0, 2.0) = 1.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0; // warning flash (falling tiles)

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 grid = local_pos.xz / cell_size;
	vec2 cell = floor(grid);
	vec2 frac = fract(grid);

	// Soft checker: a subtle tone shift, never a hard line.
	float checker = mod(cell.x + cell.y, 2.0);
	float checker_tone = mix(0.93, 1.0, checker);

	// Thin darker edge: distance to the nearest cell border (the "grout").
	float edge = min(min(frac.x, 1.0 - frac.x), min(frac.y, 1.0 - frac.y));
	float seam_tone = mix(0.72, 1.0, smoothstep(0.0, 0.08, edge));

	// Noise-free gradient: two crossing sinusoids for slow tonal variety.
	float grad = 0.5 + 0.5 * sin(grid.x * 0.55 + grid.y * 0.43);
	float grad_tone = mix(1.0, 0.92 + 0.16 * grad, detail_amount);

	vec3 albedo = base_color.rgb * mix(1.0, checker_tone * seam_tone * grad_tone, detail_amount);
	// Warning flash towards white keeps the falling-tile feedback readable.
	albedo = mix(albedo, vec3(1.0), flash);
	// MultiMesh per-instance colours (the arena checker tiles) still tint.
	albedo *= COLOR.rgb;

	ALBEDO = albedo;
	ROUGHNESS = roughness;
}
