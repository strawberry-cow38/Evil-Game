extends ColorRect

# Full-screen scope overlay. Shader paints everything outside a circular
# cutout solid black, draws a thin ring around the cutout edge, and a thin
# crosshair through the center. The interior of the circle stays transparent
# so the world (already FOV-zoomed by the camera) shows through cleanly.

const SHADER_CODE := """
shader_type canvas_item;

uniform float scope_radius : hint_range(50.0, 1200.0) = 520.0;
uniform float ring_thickness : hint_range(0.5, 10.0) = 4.0;
uniform float crosshair_thickness : hint_range(0.5, 4.0) = 1.0;
uniform vec4 mask_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec2 vp = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 c = vp * 0.5;
	vec2 p = FRAGCOORD.xy;
	float r = distance(p, c);
	if (r > scope_radius) {
		COLOR = mask_color;
	} else if (abs(r - scope_radius) < ring_thickness) {
		COLOR = mask_color;
	} else if (abs(p.x - c.x) < crosshair_thickness || abs(p.y - c.y) < crosshair_thickness) {
		COLOR = mask_color;
	} else {
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	}
}
"""

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	color = Color(1.0, 1.0, 1.0, 1.0)
	var sh := Shader.new()
	sh.code = SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = sh
	material = mat
	visible = false

func show_scope() -> void:
	visible = true

func hide_scope() -> void:
	visible = false
