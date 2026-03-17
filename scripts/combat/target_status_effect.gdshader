shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.7, 0.2, 0.2, 1.0);
uniform float mark_intensity = 0.0;
uniform float seed_intensity = 0.0;
uniform float burn_intensity = 0.0;
uniform float freeze_intensity = 0.0;
uniform float greed_intensity = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_strength = 0.0;

float wave(float x) {
	return 0.5 + 0.5 * sin(x);
}

void fragment() {
	vec3 col = base_color.rgb;
	float t = TIME;

	float mark_mask = wave(UV.y * 34.0 + t * 8.5);
	float seed_mask = wave((UV.x + UV.y) * 20.0 + t * 5.2);
	float burn_mask = wave(UV.x * 43.0 + t * 14.0) * wave(UV.y * 31.0 + t * 11.0);
	float freeze_mask = wave(UV.y * 52.0 - t * 9.0);
	float greed_mask = wave((UV.x - UV.y) * 28.0 + t * 6.5);

	col = mix(col, vec3(0.35, 1.0, 0.45), clamp(mark_intensity * mark_mask, 0.0, 1.0));
	col = mix(col, vec3(0.25, 0.95, 0.7), clamp(seed_intensity * seed_mask, 0.0, 1.0));
	col = mix(col, vec3(1.0, 0.38, 0.18), clamp(burn_intensity * burn_mask, 0.0, 1.0));
	col = mix(col, vec3(0.45, 0.85, 1.0), clamp(freeze_intensity * freeze_mask, 0.0, 1.0));
	col = mix(col, vec3(1.0, 0.78, 0.24), clamp(greed_intensity * greed_mask, 0.0, 1.0));

	float flash_mask = 0.65 + 0.35 * wave(t * 30.0 + (UV.x + UV.y) * 24.0);
	col += flash_color.rgb * flash_strength * flash_mask * 0.72;

	ALBEDO = clamp(col, vec3(0.0), vec3(2.0));
	EMISSION = ALBEDO * (0.1 + burn_intensity * 0.25 + flash_strength * 0.9);
	ROUGHNESS = 0.65;
	METALLIC = 0.0;
}
