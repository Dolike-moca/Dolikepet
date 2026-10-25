// Render-space tailoring of the existing sprite. Source PNG remains unchanged.
// The adjustment starts beyond the near knee; the waist and both boots are fixed.
vec2 seated_source_pixel(vec2 drawn) {
	vec2 source = drawn;
	if (source.x > 735.0) {
		source.x = 735.0 + (source.x - 735.0) / 0.76;
	}
	float hem = smoothstep(720.0, 800.0, source.x);
	if (source.y > 185.0) {
		source.y = 185.0 + (source.y - 185.0) / (1.0 - 0.36 * hem);
	}
	return source;
}

vec4 seated_sample(sampler2D image, vec2 drawn_uv) {
	vec2 uv = seated_source_pixel(drawn_uv * vec2(940.0, 449.0)) / vec2(940.0, 449.0);
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return vec4(0.0);
	}
	return texture(image, uv);
}
