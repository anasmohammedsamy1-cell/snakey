// Outline pass for character recolor materials.
// Attached as a second pass via ShaderMaterial.set_next_pass(): culls front faces
// so only the back faces of the expanded hull remain visible behind the character.
// Vertices are pushed along their normal by 0.012 * outline_width.
// Only used on MEDIUM / HIGH graphics presets (LOW skips the outline).
shader_type spatial;
render_mode cull_front;

uniform float outline_width = 1.0;
uniform vec4 dark_color : source_color = vec4(0.05, 0.05, 0.08, 1.0);

void vertex() {
	// push the vertex outward along its surface normal by 0.012 * outline_width
	if (outline_width > 0.0) {
		VERTEX += NORMAL * (0.012 * outline_width);
	}
}

void fragment() {
	ALBEDO = dark_color.rgb;
	ALPHA = 1.0;
}
