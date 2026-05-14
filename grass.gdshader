shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, shadows_disabled, specular_disabled;

// Custom grass shader: billboards Y-axis around the camera (mirrors
// BaseMaterial3D.BILLBOARD_FIXED_Y) AND sways the blade tip in world-space
// wind direction so a uniform global gust looks coherent across a field.
//
// MultiMesh feeds us per-instance MODEL_MATRIX; the instance origin doubles
// as a phase seed so neighbouring blades don't bend in lockstep.

uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap;
uniform vec4 albedo_tint : source_color = vec4(0.7, 1.0, 0.7, 1.0);
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.5;
// World-space horizontal wind direction (xz). Length is informational only;
// amplitude is wind_min/wind_max so the dir vector should be normalised.
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform float wind_min : hint_range(0.0, 1.0) = 0.04;
uniform float wind_max : hint_range(0.0, 2.0) = 0.18;
uniform float wind_speed : hint_range(0.0, 8.0) = 1.8;
// Per-material sway scaler. Shrubs use ~0.4 so they breathe rather than
// thrash like blades.
uniform float sway_mult : hint_range(0.0, 2.0) = 1.0;
// Phase scatter — multiplied into the per-instance xz seed so different
// fields can have different "weather feel" without retuning.
uniform float phase_scatter : hint_range(0.0, 2.0) = 1.0;
// 1 = Y-billboard the mesh around the camera (grass blade). 0 = use the
// per-instance MODEL_MATRIX as-is (shrub crossed-quads). Wind sway applies
// to both — the difference is only in how the local basis is built.
uniform int billboard_mode : hint_range(0, 1) = 1;
// Behind-camera cull. dot(cam_fwd, to_inst) < this → collapse the instance
// to zero area. -1.0 = no culling (default). Set to about -0.2 on grass so
// blades behind the camera skip rasterisation entirely.
uniform float cull_back_dot : hint_range(-1.0, 1.0) = -1.0;

void vertex() {
	vec3 inst_origin = MODEL_MATRIX[3].xyz;
	// Behind-camera cull check. Done once per vertex but the result is the
	// same for every vertex of an instance, so the GPU collapses all four
	// corners onto inst_origin and the zero-area triangles get skipped
	// before the fragment stage.
	bool cull = false;
	if (cull_back_dot > -0.999) {
		// Full-3D check: previously we projected both vectors to XZ so the
		// cull was "is this instance behind me on the ground plane?", but
		// that falls apart when the camera pitches down — at near-vertical
		// pitch the horizontal cam_fwd shrinks to zero, fwd_dot becomes
		// noise, and instances under/behind the player flicker out.
		// Use raw 3D direction instead — cull_back_dot near -0.2 keeps a
		// ~100° forward cone regardless of camera pitch.
		vec3 cam_pos_c = INV_VIEW_MATRIX[3].xyz;
		// Sample the cone at the middle of the blade, not the root, so a
		// blade right under the camera (root behind, tip in front when
		// looking down) doesn't flip-cull on the root position alone.
		vec3 sample_pt = inst_origin + vec3(0.0, 0.2, 0.0);
		vec3 to_inst = sample_pt - cam_pos_c;
		float to_inst_len = length(to_inst);
		vec3 cam_fwd = -INV_VIEW_MATRIX[2].xyz;
		if (to_inst_len > 0.0001) {
			float fwd_dot = dot(cam_fwd, to_inst / to_inst_len);
			cull = fwd_dot < cull_back_dot;
		}
	}
	vec3 world_pos;
	if (cull) {
		world_pos = inst_origin;
	} else if (billboard_mode == 1) {
		// Pull uniform scale out so we can rebuild the basis without
		// inheriting any quad rotation baked into MODEL_MATRIX.
		float sx = length(MODEL_MATRIX[0].xyz);
		float sy = length(MODEL_MATRIX[1].xyz);
		vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
		vec3 to_cam = cam_pos - inst_origin;
		to_cam.y = 0.0;
		// Degenerate when the camera is exactly above; fall back to world +Z.
		if (length(to_cam) < 0.0001) {
			to_cam = vec3(0.0, 0.0, 1.0);
		}
		to_cam = normalize(to_cam);
		vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
		vec3 up = vec3(0.0, 1.0, 0.0);
		world_pos = inst_origin
			+ right * VERTEX.x * sx
			+ up * VERTEX.y * sy;
	} else {
		// Static meshes (crossed-quad shrubs) — keep their authored rotation
		// + uniform scale by going through the model matrix verbatim.
		world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	}
	// Wind sway. UV.y=0 sits at the top edge of the source mesh (tip),
	// UV.y=1 at the root, so top_factor maps tip→1 and root→0; the root
	// stays planted while the tip bends. Skip the bend for culled
	// instances so the collapsed origin point doesn't drift.
	if (!cull) {
		float top_factor = 1.0 - UV.y;
		float seed = (inst_origin.x * 0.21 + inst_origin.z * 0.17) * phase_scatter;
		float pulse = 0.5 + 0.5 * sin(TIME * wind_speed + seed);
		float amp = mix(wind_min, wind_max, pulse);
		world_pos += vec3(wind_dir.x, 0.0, wind_dir.y) * amp * top_factor * sway_mult;
	}
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_pos, 1.0);
}

void fragment() {
	vec4 c = texture(albedo_tex, UV) * albedo_tint;
	if (c.a < alpha_scissor) {
		discard;
	}
	ALBEDO = c.rgb;
	ALPHA = 1.0;
}
