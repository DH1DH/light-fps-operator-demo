shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec2 virtual_resolution = vec2(960.0, 540.0);
uniform float color_levels = 36.0;
uniform float noise_strength = 0.02;
uniform float scanline_strength = 0.01;
uniform float vignette_strength = 0.18;
uniform float black_floor = 0.92;
uniform vec3 tint = vec3(0.96, 0.92, 0.78);

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

	COLOR = vec4(color, src.a);
}
