shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec2 virtual_resolution = vec2(960.0, 540.0);
uniform float color_levels = 36.0;
uniform float noise_strength = 0.02;
uniform float scanline_strength = 0.01;
uniform float vignette_strength = 0.18;
uniform float black_floor = 0.92;
uniform vec3 tint = vec3(0.96, 0.92, 0.78);
uniform float highlight_protect_threshold = 0.75;
uniform float highlight_protect_strength = 0.75;
uniform float fx_protect_strength = 0.92;
uniform float fx_protect_saturation_threshold = 0.22;
uniform float fx_protect_green_bias = 0.08;
uniform float fx_protect_purple_bias = 0.08;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 viewport_size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 pixel_uv = floor(SCREEN_UV * virtual_resolution) / virtual_resolution;
	vec4 src = texture(screen_texture, pixel_uv);

	vec3 color = floor(src.rgb * color_levels) / color_levels;
	color *= tint;

	float grain = (hash(pixel_uv * viewport_size + TIME) - 0.5) * noise_strength;
	color += grain;

	float scan = sin(SCREEN_UV.y * viewport_size.y * 1.05) * scanline_strength;
	color -= scan;

	vec2 centered = SCREEN_UV * 2.0 - 1.0;
	float vignette = dot(centered, centered);
	color *= 1.0 - vignette * vignette_strength;

	color = max(color, vec3(0.0));
	color = pow(color, vec3(black_floor));

	// Preserve bright highlights (e.g., muzzle flash / tracers / impacts) from heavy post effects.
	float luma = dot(src.rgb, vec3(0.2126, 0.7152, 0.0722));
	float protect = smoothstep(highlight_protect_threshold, 1.0, luma) * highlight_protect_strength;

	// Preserve buff/debuff VFX colors (green/purple emissive particles) from heavy post distortion.
	float cmax = max(src.r, max(src.g, src.b));
	float cmin = min(src.r, min(src.g, src.b));
	float sat = cmax - cmin;
	float sat_mask = smoothstep(fx_protect_saturation_threshold, 1.0, sat);

	float green_mask = smoothstep(fx_protect_green_bias, 0.55, src.g - max(src.r, src.b));
	float purple_mask = smoothstep(fx_protect_purple_bias, 0.55, (src.r + src.b) * 0.5 - src.g);
	float fx_mask = sat_mask * max(green_mask, purple_mask) * fx_protect_strength;

	float total_protect = clamp(max(protect, fx_mask), 0.0, 1.0);
	vec3 out_rgb = mix(color, src.rgb, total_protect);

	COLOR = vec4(out_rgb, src.a);
}
