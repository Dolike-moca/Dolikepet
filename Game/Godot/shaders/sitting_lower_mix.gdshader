// Based on GDCubism's 2d_cubism_norm_mix.gdshader.
// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2023 MizunagiKB <mizukb@live.jp>
shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;

#include "sitting_coordinates.gdshaderinc"

uniform vec4 color_base : source_color;
uniform vec4 color_screen : source_color;
uniform vec4 color_multiply : source_color;
uniform vec4 channel : source_color;
uniform sampler2D tex_main : filter_linear_mipmap;
uniform sampler2D sit_texture : filter_linear, repeat_disable;
uniform float sit_blend = 0.0;
uniform vec3 sit_uv_x;
uniform vec3 sit_uv_y;
varying vec4 modulation;
varying vec2 canvas_point;

void vertex() {
	modulation = COLOR;
	canvas_point = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 tex = texture(tex_main, UV);
	tex.rgb *= color_multiply.rgb;
	tex.rgb = tex.rgb + color_screen.rgb - tex.rgb * color_screen.rgb;
	vec4 color = tex * color_base * modulation;
	vec3 at = vec3(canvas_point, 1.0);
	vec2 seated_uv = vec2(dot(sit_uv_x, at), dot(sit_uv_y, at));
	float seated_alpha = 0.0;
	if (all(greaterThanEqual(seated_uv, vec2(0.0))) &&
			all(lessThanEqual(seated_uv, vec2(1.0)))) {
		seated_alpha = seated_sample(sit_texture, seated_uv).a;
	}
	// Correct an over-composite into a linear premultiplied dissolve:
	// old contribution = old * (1-t), new = new * t.
	// Where both sprites are opaque, the composite stays fully opaque instead of
	// dropping to 75% at the midpoint and revealing the desktop through the legs.
	color.a *= (1.0 - sit_blend) / max(1.0 - sit_blend * seated_alpha, 0.00001);
	COLOR = vec4(color.rgb * color.a, color.a);
}
