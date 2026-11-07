shader_type canvas_item;

uniform float saturation : hint_range(0.8, 1.5) = 1.18;
uniform float contrast : hint_range(0.8, 1.5) = 1.12;

void fragment() {
	vec4 source = texture(TEXTURE, UV) * COLOR;
	float luminance = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 vivid = mix(vec3(luminance), source.rgb, saturation);
	vivid = (vivid - vec3(0.5)) * contrast + vec3(0.5);
	COLOR = vec4(clamp(vivid, vec3(0.0), vec3(1.0)), source.a);
}
