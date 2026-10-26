extends CanvasLayer
## Samples the existing UI-free viewport; separate canvas prevents feedback.
var image := TextureRect.new()
var tint := ShaderMaterial.new()

func setup(viewport: SubViewport) -> void:
	layer = 1
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; uniform float strength = 0.0; void fragment(){ COLOR = vec4(vec3(1.0), texture(TEXTURE,UV).a * strength); }"
	tint.shader = shader
	image.texture = viewport.get_texture()
	image.material = tint
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(image)
	image.hide()

func apply(amount: float, pixels: Vector2) -> void:
	image.size = pixels
	image.visible = amount > 0.0001
	tint.set_shader_parameter("strength",amount)
