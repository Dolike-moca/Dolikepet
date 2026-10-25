shader_type canvas_item;
uniform float charge_glow : hint_range(0.0, 1.0) = 0.0;
uniform float clock_time = 0.0;
varying vec2 art_uv;
// Separate transparent layer behind the unmodified pot and soup drawing.
void vertex() {
	vec2 extra = (UV * 2.0 - 1.0) * 72.0;
	VERTEX += extra;
	art_uv = UV + extra / vec2(1312.0, 1199.0);
}
float art_alpha(sampler2D art, vec2 uv) {
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) { return 0.0; }
	return texture(art, uv).a;
}
void fragment() {
	float halo = 0.0;
	if (charge_glow > 0.0 && art_alpha(TEXTURE, art_uv) < 0.001) {
		for (int ring = 1; ring <= 3; ring++) {
			float radius = float(ring) * 22.0;
			float reach = 0.0;
			for (int i = 0; i < 16; i++) {
				float angle = float(i)*6.2831853/16.0;
				vec2 delta = vec2(cos(angle),sin(angle))*radius*TEXTURE_PIXEL_SIZE;
				reach += art_alpha(TEXTURE, art_uv+delta)/16.0;
			}
			halo += reach * (0.8-float(ring)*0.18);
		}
	}
	float pulse = 0.88 + 0.12*sin(clock_time*22.0);
	COLOR = vec4(vec3(0.48,0.82,0.16),clamp(halo*charge_glow*pulse*1.8,0.0,0.68));
}
