// Based on GDCubism's MIT-licensed 2d_cubism_mask_mix.gdshader.
// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2023 MizunagiKB <mizukb@live.jp>
shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;

uniform vec4 color_base : source_color;
uniform vec4 color_screen : source_color;
uniform vec4 color_multiply : source_color;
uniform vec4 channel : source_color;
uniform sampler2D tex_main : filter_linear_mipmap;
uniform sampler2D tex_mask : filter_linear_mipmap;
uniform float mask_scale;
uniform vec2 canvas_size;
uniform vec2 mesh_offset;
uniform sampler2D hungry_base : filter_linear, repeat_disable;
uniform sampler2D hungry_star : filter_linear, repeat_disable;
uniform vec3 art_uv_x;
uniform vec3 art_uv_y;
uniform vec2 star_pivot;
uniform float hungry_weight = 0.0;
uniform float star_alpha = 0.85;
uniform float star_scale = 1.0;
varying vec2 MASK_UV;
varying vec4 modulate;

void vertex() {
    vec2 mask_size = vec2(textureSize(tex_mask, 0)) / mask_scale;
    MASK_UV = (VERTEX - mesh_offset) / mask_size;
    modulate = COLOR;
}

void fragment() {
    vec4 color_tex = texture(tex_main, UV);
    vec2 art_uv = vec2(dot(art_uv_x, vec3(UV, 1.0)), dot(art_uv_y, vec3(UV, 1.0)));
    vec4 base = texture(hungry_base, art_uv);
    vec2 star_uv = (art_uv - star_pivot) / star_scale + star_pivot;
    vec4 star = texture(hungry_star, star_uv);
    float inside = step(0.0, star_uv.x) * step(star_uv.x, 1.0)
        * step(0.0, star_uv.y) * step(star_uv.y, 1.0);
    vec3 hungry = mix(base.rgb, star.rgb, star.a * star_alpha * inside);
    // Retain the original iris contour and the original animated lid mask.
    color_tex.rgb = mix(color_tex.rgb, hungry, hungry_weight);
    color_tex.rgb *= color_multiply.rgb;
    color_tex.rgb += color_screen.rgb - color_tex.rgb * color_screen.rgb;
    vec4 color_for_mask = color_tex * color_base * modulate;
    color_for_mask.rgb *= color_for_mask.a;
    vec4 clip_mask = texture(tex_mask, MASK_UV) * channel;
    color_for_mask *= clip_mask.r + clip_mask.g + clip_mask.b + clip_mask.a;
    COLOR = color_for_mask;
}
