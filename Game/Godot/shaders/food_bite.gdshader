shader_type canvas_item;
render_mode unshaded;
uniform float bite_cut : hint_range(0.0, 1.0) = 0.0;
uniform vec2 bite_center = vec2(0.566, 0.220);
uniform vec2 bite_radius = vec2(0.074, 0.055);
uniform vec4 edge_color : source_color = vec4(0.25,0.105,0.047,1.0);
uniform bool meal_food = false;
uniform vec4 meal_cuts[12];
uniform int cut_index = -1;
uniform float cut_progress : hint_range(0.0,1.0) = 0.0;
uniform vec4 icon_frame = vec4(0.0,0.0,1.0,1.0);

void fragment() {
	// CanvasItem COLOR already includes the texture and instance modulation.
	vec4 food = COLOR;
	if (meal_food) {
		// Accumulate individual circular bites. No side/bottom guards and no
		// full-width clipping line: only the current rounded bite disappears.
		vec2 q = (UV-icon_frame.xy)/icon_frame.zw;
		for (int i = 0; i < 12; i++) {
			if (i > cut_index) break;
			float progress = i < cut_index ? 1.0 : cut_progress;
			if (progress <= 0.00001) continue;
			vec4 cut = meal_cuts[i];
			float d = length((q-cut.xy)/max(cut.zw*progress,vec2(0.000001)))-1.0;
			float aa = max(fwidth(d),0.004);
			food.a *= smoothstep(-aa,aa,d);
			food.rgb *= mix(0.80,1.0,smoothstep(0.01,0.035,d));
		}
	} else if (bite_cut > 0.00001) {
		vec2 radius = bite_radius * max(bite_cut,0.001);
		// A shallow, rounded notch opens from the actual food edge.
		vec2 center = bite_center - vec2(0.0,(1.0-bite_cut)*bite_radius.y);
		float distance = length((UV-center)/radius)-1.0;
		float aa = max(fwidth(distance),0.012);
		float outside = smoothstep(-aa,aa,distance);
		float edge = 1.0-smoothstep(0.06,0.13,distance);
		food.rgb = mix(food.rgb,edge_color.rgb,edge);
		food.a *= outside;
	}
	COLOR = food;
}
