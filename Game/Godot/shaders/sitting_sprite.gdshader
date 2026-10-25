shader_type canvas_item;
render_mode unshaded;

#include "sitting_coordinates.gdshaderinc"

varying vec4 modulation;
void vertex() {
	modulation = COLOR;
}
void fragment() {
	COLOR = seated_sample(TEXTURE, UV) * modulation;
}
