shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled, specular_disabled;

// Per-grass-instance drop shadow. MultiMesh feeds us thousands of instances;
// the vertex shader collapses any instance outside a forward-facing cone in
// front of the camera so distant or off-screen blades pay zero fragment cost.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float max_range : hint_range(0.0, 60.0) = 7.0;
// cos of the half-angle. 0.5 ≈ 60°, 0.7 ≈ 45°. Slightly wider than the
// camera FOV so blades on the edge of the view still get their shadow.
uniform float fov_cos : hint_range(-1.0, 1.0) = 0.55;
uniform float opacity : hint_range(0.0, 1.0) = 0.4;

void vertex() {
	vec3 inst_origin = MODEL_MATRIX[3].xyz;
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	// Full-3D cone check. The earlier XZ-projection version flickered when
	// the camera pitched down (horizontal cam_fwd shrinks to zero, fwd_dot
	// = noise). Range check uses XZ distance so the cull radius stays
	// independent of camera height.
	vec3 to_inst_xz = inst_origin - cam_pos;
	to_inst_xz.y = 0.0;
	float dist = length(to_inst_xz);
	vec3 to_inst_3d = inst_origin - cam_pos;
	float to_len_3d = length(to_inst_3d);
	vec3 cam_fwd = -INV_VIEW_MATRIX[2].xyz;
	float fwd_dot = 0.0;
	if (to_len_3d > 0.0001) {
		fwd_dot = dot(cam_fwd, to_inst_3d / to_len_3d);
	}
	bool cull = (dist > max_range) || (fwd_dot < fov_cos);
	vec3 world_pos;
	if (cull) {
		// Collapse all four corners onto the instance origin → zero-area
		// triangles get discarded before rasterisation.
		world_pos = inst_origin;
	} else {
		world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	}
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_pos, 1.0);
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	ALBEDO = vec3(0.0);
	ALPHA = c.a * opacity;
}
