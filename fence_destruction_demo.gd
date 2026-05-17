extends Node3D

# Headless capture: builds one picket run + one tall-brown run, then
# fires simulated bullet hits at pickets in sequence so the recording
# shows debris, decay, segment breach, and respawn behaviour.

const FENCES_SCRIPT := preload("res://editor_fences.gd")

const RUN_LEN: float = 9.0
const ROW_GAP: float = 3.5
const FIRE_INTERVAL: float = 0.28
const PRE_DELAY: float = 1.0
# Long enough to capture: every picket killed -> segment collapses ->
# (RESPAWN_TIME) -> whole segment comes back -> POST_DELAY tail.
const POST_DELAY: float = 8.0
const RESPAWN_TIME: float = 4.0
const VARIANTS: Array = ["picket", "tall_brown"]

@onready var cam: Camera3D = $CameraRig/Camera3D
@onready var rig: Node3D = $CameraRig

var fences: Node3D
var terrain: Node3D
var elapsed: float = 0.0
var fire_idx: int = 0
var next_fire_t: float = PRE_DELAY
var pickets: Array = []
var done: bool = false
var quit_t: float = -1.0
var ready_done: bool = false

func _ready() -> void:
	terrain = $TerrainStub
	fences = Node3D.new()
	fences.set_script(FENCES_SCRIPT)
	add_child(fences)
	fences.setup(terrain)
	fences.enable_collision(true)
	_build_runs()
	# Collect destructible pickets in placement order (interleave rows
	# so the camera sees breach happen on the near run first, then far).
	await get_tree().process_frame
	await get_tree().process_frame
	var by_row: Array = [[], []]
	for n in get_tree().get_nodes_in_group("fence_picket_destructible"):
		if not (n is StaticBody3D):
			continue
		var fi: int = int(n.get_meta("fence_idx", -1))
		if fi >= 0 and fi < by_row.size():
			by_row[fi].append(n)
	# Order pickets within each row left-to-right by world X.
	for row in by_row:
		row.sort_custom(func(a, b): return a.global_position.x < b.global_position.x)
	# Interleave: front row first picket, back row first picket, etc.
	# Only take every 3rd picket per row — the segment is dense enough that
	# 33% coverage already trips the 40% breach threshold and keeps the
	# clip short enough to send.
	var max_len: int = max(by_row[0].size(), by_row[1].size())
	for i in range(max_len):
		if i % 3 != 0:
			continue
		for row in by_row:
			if i < row.size():
				pickets.append(row[i])
	ready_done = true

func _build_runs() -> void:
	for i in range(VARIANTS.size()):
		var z: float = float(i) * ROW_GAP
		fences.set_variant(VARIANTS[i])
		fences.begin_drag(Vector3(0, 0, z), false, false, 2.36)
		fences.commit_drag(Vector3(RUN_LEN, 0, z), false, false, 2.36)
		# Shorten respawn so the demo can show the segment coming back.
		fences.set_segment_prop(i, 0, "respawn_time", RESPAWN_TIME)

func _process(delta: float) -> void:
	if not ready_done:
		return
	elapsed += delta
	# Fixed camera angle: slight side-front so debris fans toward camera.
	var t: float = clampf(elapsed / 8.0, 0.0, 1.0)
	var cx: float = lerpf(-1.5, RUN_LEN + 1.5, smoothstep(0.0, 1.0, t))
	rig.position = Vector3(cx, 1.6, -3.0)
	cam.look_at(Vector3(RUN_LEN * 0.5, 0.7, ROW_GAP * 0.5), Vector3.UP)
	# Sequential picket destruction.
	if not done and elapsed >= next_fire_t and fire_idx < pickets.size():
		var body: StaticBody3D = pickets[fire_idx]
		if is_instance_valid(body) and body.visible:
			var hit_pos: Vector3 = body.global_position + Vector3(0, 0.6, 0)
			var hit_norm: Vector3 = Vector3(0, 0.2, -1).normalized()
			fences.notify_picket_hit(body, hit_pos, hit_norm)
		fire_idx += 1
		next_fire_t = elapsed + FIRE_INTERVAL
	if not done and fire_idx >= pickets.size():
		done = true
		quit_t = elapsed + POST_DELAY
	if done and elapsed >= quit_t:
		get_tree().quit()
