shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled, specular_disabled;

// Custom grass shader: billboards Y-axis around the camera (mirrors
// BaseMaterial3D.BILLBOARD_FIXED_Y) AND sways the blade tip in world-space
// wind direction so a uniform global gust looks coherent across a field.
//
// MultiMesh feeds us per-instance MODEL_MATRIX; the instance origin doubles
// as a phase seed so neighbouring blades don't bend in lockstep.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 albedo_tint : source_color = vec4(0.7, 1.0, 0.7, 1.0);
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.5;
// World-space horizontal wind direction (xz). Length is informational only;
// amplitude is wind_min/wind_max so the dir vector should be normalised.
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform float wind_min : hint_range(0.0, 1.0) = 0.04;
uniform float wind_max : hint_range(0.0, 2.0) = 0.18;
uniform float wind_speed : hint_range(0.0, 8.0) = 1.8;
// Phase scatter — multiplied into the per-instance xz seed so different
// fields can have different "weather feel" without retuning.
uniform float phase_scatter : hint_range(0.0, 2.0) = 1.0;

void vertex() {
	// Pull instance origin + uniform scale out of the model matrix. We
	// ignore any rotation baked into MODEL_MATRIX because we're rebuilding
	// the basis to face the camera horizontally below.
	vec3 inst_origin = MODEL_MATRIX[3].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = cam_pos - inst_origin;
	to_cam.y = 0.0;
	// Degenerate when the camera is exactly above; fall back to world +Z so
	// the blade doesn't collapse to a zero-length basis.
	if (length(to_cam) < 0.0001) {
		to_cam = vec3(0.0, 0.0, 1.0);
	}
	to_cam = normalize(to_cam);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 world_pos = inst_origin
		+ right * VERTEX.x * sx
		+ up * VERTEX.y * sy;
	// Wind sway. UV.y=0 sits at the tip of the QuadMesh (top edge), UV.y=1
	// at the root, so top_factor maps tip→1 and root→0; the root stays
	// planted while the tip bends.
	float top_factor = 1.0 - UV.y;
	float seed = (inst_origin.x * 0.21 + inst_origin.z * 0.17) * phase_scatter;
	float pulse = 0.5 + 0.5 * sin(TIME * wind_speed + seed);
	float amp = mix(wind_min, wind_max, pulse);
	world_pos += vec3(wind_dir.x, 0.0, wind_dir.y) * amp * top_factor;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_pos, 1.0);
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	// Mipmap alpha-coverage compensation. As distance grows the box-filtered
	// mip chain averages blade alpha against empty pixels, so the silhouette
	// fades below the scissor and the field melts into ground. Boost alpha
	// proportional to the active LOD so distant patches keep their density.
	float lod = textureQueryLod(albedo_tex, UV).y;
	c.a = clamp(c.a * (1.0 + 0.35 * lod), 0.0, 1.0);
	c *= albedo_tint;
	if (c.a < alpha_scissor) {
		discard;
	}
	ALBEDO = c.rgb;
	ALPHA = 1.0;
}
