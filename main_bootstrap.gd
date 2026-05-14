extends Node3D

# Attached to main.tscn root. If the player just came from the editor
# (MapState.has_map() is true), swap the hardcoded flat Ground for an
# editor_terrain instance carrying the authored heights. Otherwise
# leave the legacy ground intact so launching straight into Play from
# the menu still works.

const EDITOR_TERRAIN := preload("res://editor_terrain.gd")
const ROAD_RENDERER := preload("res://road_renderer.gd")
const EFFECT_CATALOG := preload("res://editor_effect_catalog.gd")
const OBJECT_CATALOG := preload("res://editor_objects_catalog.gd")
const PICKUP := preload("res://pickup.gd")
const VEHICLE := preload("res://vehicle.gd")
const EDITOR_SCRIPT := preload("res://editor.gd")
const DUMMY_SCRIPT := preload("res://dummy.gd")
const DUMMY_HEAD_SCRIPT := preload("res://dummy_head.gd")
const CORPSE_SCRIPT := preload("res://corpse.gd")
const TRIGGER_RUNTIME := preload("res://trigger_runtime.gd")
const TRIGGER_BOX_SCRIPT := preload("res://editor_trigger_box.gd")
const FOLIAGE_SCRIPT := preload("res://editor_foliage.gd")
const FOLIAGE_PROFILER_SCRIPT := preload("res://editor_foliage_profiler.gd")
const NOTHING_ITEM_ID := "nothing"
# Loot rolls per actor death — drop_table_id is rolled this many times
# and each non-nothing result is shoved into the corpse container.
const CORPSE_LOOT_ROLLS := 4

# F2-toggled foliage cost overlay. Only created when a foliage tree is
# actually instantiated; null on legacy flat-ground play.
var _foliage_profiler: CanvasLayer = null

# Fixed vehicle spawn — sits a few meters off the player spawn so it's findable.
const VEHICLE_SPAWN_OFFSET := Vector3(6.0, 0.0, 0.0)
const VEHICLE_SPAWNS := [
	{"variant": "car", "name": "Vehicle", "offset": Vector3(6.0, 0.0, 0.0)},
	{"variant": "motorcycle", "name": "Motorcycle", "offset": Vector3(6.0, 0.0, 4.0)},
	{"variant": "countash", "name": "Countash", "offset": Vector3(10.0, 0.0, -2.0)},
]

func _ready() -> void:
	# Apply authored sky/sun/ambient before anything else so the first
	# frame already shows the right lighting (no flash of defaults).
	if not MapState.lighting.is_empty():
		var env_node: WorldEnvironment = get_node_or_null("WorldEnvironment")
		var sun_node: DirectionalLight3D = get_node_or_null("Sun")
		EDITOR_SCRIPT.apply_lighting_to(env_node, sun_node, MapState.lighting)
	var terrain_node: Node = null
	if MapState.has_map():
		var ground := get_node_or_null("Ground")
		if ground != null:
			ground.queue_free()
		var terrain := Node3D.new()
		terrain.set_script(EDITOR_TERRAIN)
		terrain.name = "EditorTerrain"
		add_child(terrain)
		# editor_terrain._ready already created the mesh from a zeroed
		# array; overwrite + rebuild with the real heights.
		terrain.heights = MapState.heights.duplicate()
		if MapState.terrain_paint.size() == terrain.paint.size():
			terrain.paint = MapState.terrain_paint.duplicate()
		if MapState.terrain_holes.size() == terrain.holes.size():
			terrain.holes = MapState.terrain_holes.duplicate()
			terrain._holes_dirty = true
		terrain.rebuild()
		terrain_node = terrain
	# Foliage — single MultiMeshInstance3D rebuilt from authored instances.
	# Independent of terrain (already y-baked at spray time), but only useful
	# alongside an editor map; legacy flat-ground play has no foliage anyway.
	if not MapState.foliage_instances.is_empty():
		var foliage_root := Node3D.new()
		foliage_root.set_script(FOLIAGE_SCRIPT)
		foliage_root.name = "Foliage"
		add_child(foliage_root)
		foliage_root.set_state(MapState.foliage_instances)
		var w: Dictionary = MapState.foliage_wind
		if not w.is_empty():
			foliage_root.set_wind(
				Vector2(float(w.get("dir_x", 1.0)), float(w.get("dir_y", 0.0))),
				float(w.get("min", 0.04)),
				float(w.get("max", 0.18)),
				float(w.get("speed", 1.8)),
			)
		# F2 profiler overlay — mirrors the editor's. Same script reads
		# get_profile_breakdown() off the foliage node + engine Performance
		# monitors so play-mode shows the same per-preset cost table.
		_foliage_profiler = CanvasLayer.new()
		_foliage_profiler.set_script(FOLIAGE_PROFILER_SCRIPT)
		_foliage_profiler.name = "FoliageProfiler"
		add_child(_foliage_profiler)
		_foliage_profiler.call("set_foliage", foliage_root)
	# Roads — extruded slab over the authored bezier chains. Needs the
	# terrain reference so its samples match the surface the editor previewed.
	if not MapState.roads.is_empty():
		var roads_root := Node3D.new()
		roads_root.set_script(ROAD_RENDERER)
		roads_root.name = "Roads"
		add_child(roads_root)
		roads_root.build(terrain_node, MapState.roads)
	# Player spawn override: pick a random authored marker and drop the
	# Player there. Sit them slightly above the terrain so they don't
	# clip through the new mesh.
	if not MapState.player_spawns.is_empty():
		var player := get_node_or_null("Player")
		if player != null:
			var sp: Vector3 = MapState.random_player_spawn()
			var ground_h: float = sp.y
			if terrain_node != null and terrain_node.has_method("sample_height"):
				ground_h = terrain_node.sample_height(sp)
			player.global_position = Vector3(sp.x, ground_h + 1.2, sp.z)
			player.reset_physics_interpolation()
	# Rebuild placed effects + objects from the catalog. Wireframe boxes
	# stay in the editor — play mode only spawns the visual content.
	var props_root: Node3D = null
	if not MapState.placed_props.is_empty():
		props_root = Node3D.new()
		props_root.name = "PlacedProps"
		add_child(props_root)
		# Build a quick id→table lookup so container objects can find their
		# assigned loot table without scanning the array per crate.
		var tables_for_props: Dictionary = {}
		for t in MapState.item_tables:
			tables_for_props[String(t.get("id", ""))] = t
		for entry in MapState.placed_props:
			var kind: String = String(entry.get("kind", ""))
			var id: String = String(entry.get("id", ""))
			var xform: Transform3D = entry.get("xform", Transform3D.IDENTITY)
			var content: Node3D = null
			if kind == "effect":
				content = EFFECT_CATALOG.build(id)
			elif kind == "object":
				content = OBJECT_CATALOG.build(id)
			if content == null:
				continue
			props_root.add_child(content)
			content.global_transform = xform
			# Stamp prop_id so trigger_runtime can target this spawned
			# content with named events (e.g. "destroy this prop_id").
			var pid: String = String(entry.get("prop_id", ""))
			if pid != "":
				content.set_meta("prop_id", pid)
			# Per-placement object settings: disable collision shapes,
			# stamp HP metadata for downstream damage code to consume.
			if kind == "object":
				if bool(entry.get("no_collide", false)):
					_disable_collision(content)
				if bool(entry.get("destructible", false)):
					var hpmax: int = int(entry.get("hp_max", 100))
					content.set_meta("destructible", true)
					content.set_meta("hp_max", hpmax)
					content.set_meta("hp", hpmax)
				# Type-specific per-instance state (Computer Station cam
				# lists, CCTV cam_id/ptz). Catalog node opts in by
				# defining apply_state(); generic objects skip this.
				var ostate: Dictionary = entry.get("object_state", {})
				if not ostate.is_empty() and content.has_method("apply_state"):
					content.apply_state(ostate)
			# Container loot fill — roll the assigned table N times where N
			# is the crate variant's roll_count. Each successful roll is
			# fed through crate.add(), which weight-checks against the
			# crate's max_weight; once it refuses, we stop early.
			if kind == "object" and OBJECT_CATALOG.is_container(id):
				# Per-placement override > catalog default; -1 = use default.
				var override: int = int(entry.get("roll_count_override", -1))
				if override >= 0 and "roll_count" in content:
					content.roll_count = override
				var tid: String = String(entry.get("loot_table_id", ""))
				if tid != "" and tables_for_props.has(tid):
					_seed_container(content, tables_for_props[tid])
	# Item-spawn rolls. For each placed cube, look up its table, roll the
	# weighted entries (including the implicit "nothing" entry), and drop
	# a pickup if the result isn't nothing.
	if not MapState.item_spawn_points.is_empty():
		var spawn_root := Node3D.new()
		spawn_root.name = "ItemSpawns"
		add_child(spawn_root)
		var tables_by_id: Dictionary = {}
		for t in MapState.item_tables:
			tables_by_id[String(t.get("id", ""))] = t
		for sp in MapState.item_spawn_points:
			var tid: String = String(sp.get("table_id", ""))
			var pos: Vector3 = sp.get("pos", Vector3.ZERO)
			var result: Dictionary = _roll_table(tables_by_id.get(tid, {}))
			var rolled: String = String(result.get("id", ""))
			if rolled == "" or rolled == NOTHING_ITEM_ID:
				continue
			var pickup := Area3D.new()
			pickup.set_script(PICKUP)
			pickup.item_id = rolled
			pickup.count = int(result.get("count", 1))
			pickup.position = pos + Vector3(0, 0.3, 0)
			spawn_root.add_child(pickup)

	# Actor-spawn rolls. Each placed actor cube references an actor table
	# preset (HP/regen/enemy/drop_table_id/clothing). Build the body, push
	# the override values, hook death → roll drop_table for a pickup.
	if not MapState.actor_spawn_points.is_empty():
		var actors_root := Node3D.new()
		actors_root.name = "ActorSpawns"
		add_child(actors_root)
		var atables_by_id: Dictionary = {}
		for t in MapState.actor_tables:
			atables_by_id[String(t.get("id", ""))] = t
		var itables_by_id: Dictionary = {}
		for t in MapState.item_tables:
			itables_by_id[String(t.get("id", ""))] = t
		for sp in MapState.actor_spawn_points:
			var atid: String = String(sp.get("table_id", ""))
			var pos: Vector3 = sp.get("pos", Vector3.ZERO)
			var preset: Dictionary = atables_by_id.get(atid, {})
			if preset.is_empty():
				continue
			var actor_id: String = String(preset.get("actor_id", "dummy"))
			var body: Node3D = _build_actor(actor_id, preset)
			if body == null:
				continue
			actors_root.add_child(body)
			body.global_position = pos
			# Roll clothing per slot (stub — currently just logs the picks).
			_roll_clothing_for(body, preset)
			# Death → spawn a lootable corpse at the actor's last position
			# and seed it with rolls from the preset's drop_table. Empty
			# drop_table still spawns a corpse so the player gets the
			# visual feedback even with no loot.
			var preset_color: Color = preset.get("color", Color(0.6, 0.4, 0.3, 1))
			# Prefer the in-game display name; fall back to the table name
			# (and finally "Corpse") if the field was left blank.
			var label: String = String(preset.get("actor_name", "")).strip_edges()
			if label == "":
				label = String(preset.get("name", "Corpse"))
			if body.has_signal("died"):
				body.died.connect(func(drop_id: String, _xp: int):
					_spawn_corpse(actors_root, body.global_position, preset_color, label, drop_id, itables_by_id)
				)

	# Always-spawn vehicles — one per variant. Drop each near the player at
	# terrain height + clearance so they land on the ground rather than clip in.
	var player_node := get_node_or_null("Player")
	var player_pos: Vector3 = Vector3.ZERO
	if player_node != null and player_node is Node3D:
		player_pos = (player_node as Node3D).global_position
	# Trigger runtime — spawned once, watches placed triggers, applies
	# their events at fire time. Indexed by prop_id so Destroy events
	# can resolve their target nodes from the live scene tree.
	if not MapState.placed_triggers.is_empty():
		var props_by_id: Dictionary = {}
		if props_root != null:
			for c in props_root.get_children():
				if c.has_meta("prop_id"):
					props_by_id[String(c.get_meta("prop_id"))] = c
		var triggers_root := Node.new()
		triggers_root.name = "TriggerRuntime"
		triggers_root.set_script(TRIGGER_RUNTIME)
		add_child(triggers_root)
		triggers_root.setup(MapState.placed_triggers, MapState.map_events, props_by_id)
		# Spawn visual proxies for triggers whose author opted into
		# play-mode visibility. Reuses the editor box so the rendered look
		# matches the authoring view. Visuals register with the runtime so
		# they self-destruct alongside their backing trigger.
		for tr in MapState.placed_triggers:
			if not bool(tr.get("visible_in_play", false)):
				continue
			var tvis: Node3D = Node3D.new()
			tvis.set_script(TRIGGER_BOX_SCRIPT)
			add_child(tvis)
			tvis.global_transform = tr.get("xform", Transform3D.IDENTITY)
			triggers_root.register_visual(String(tr.get("trigger_id", "")), tvis)
	for spec in VEHICLE_SPAWNS:
		var v := VehicleBody3D.new()
		v.set_script(VEHICLE)
		v.variant = String(spec.get("variant", "car"))
		v.name = String(spec.get("name", "Vehicle"))
		var spawn_xz: Vector3 = player_pos + (spec.get("offset", VEHICLE_SPAWN_OFFSET) as Vector3)
		var ground_y: float = spawn_xz.y
		if terrain_node != null and terrain_node.has_method("sample_height"):
			ground_y = terrain_node.sample_height(spawn_xz)
		v.position = Vector3(spawn_xz.x, ground_y + 1.0, spawn_xz.z)
		add_child(v)

func _seed_container(crate: Node3D, table: Dictionary) -> void:
	var rolls: int = int(crate.get("roll_count"))
	if rolls <= 0:
		return
	# Roll up to roll_count entries; if a roll comes back as nothing/empty
	# we still consume the budget (matches how a real loot table feels —
	# unlucky crates exist). add() weight-checks; first refusal ends seeding.
	for i in range(rolls):
		var result: Dictionary = _roll_table(table)
		var rid: String = String(result.get("id", ""))
		if rid == "" or rid == NOTHING_ITEM_ID:
			continue
		var n: int = int(result.get("count", 1))
		if not crate.has_method("add"):
			break
		if not crate.add(rid, n):
			break

func _roll_table(table: Dictionary) -> Dictionary:
	if table.is_empty():
		return {"id": "", "count": 1}
	var entries: Array = table.get("entries", [])
	var has_nothing: bool = false
	var total: float = 0.0
	for e in entries:
		var w: float = float(e.get("weight", 1.0))
		if w < 0.0:
			w = 0.0
		total += w
		if String(e.get("id", "")) == NOTHING_ITEM_ID:
			has_nothing = true
	# Tables without an explicit nothing entry still get a baseline 1.0
	# nothing-weight so a table with one item at weight 0 doesn't divide
	# by zero or always spawn.
	if not has_nothing:
		total += 1.0
	if total <= 0.0:
		return {"id": "", "count": 1}
	var roll: float = randf() * total
	var acc: float = 0.0
	for e in entries:
		var w2: float = float(e.get("weight", 1.0))
		if w2 < 0.0:
			w2 = 0.0
		acc += w2
		if roll <= acc:
			var id: String = String(e.get("id", ""))
			var min_c: int = int(e.get("min_count", 1))
			var max_c: int = int(e.get("max_count", 1))
			if min_c < 1:
				min_c = 1
			if max_c < min_c:
				max_c = min_c
			var count: int = randi_range(min_c, max_c)
			return {"id": id, "count": count}
	return {"id": NOTHING_ITEM_ID, "count": 1}

func _spawn_corpse(parent: Node, pos: Vector3, color: Color, label: String, drop_id: String, itables_by_id: Dictionary) -> void:
	var corpse := Node3D.new()
	corpse.set_script(CORPSE_SCRIPT)
	corpse.set("corpse_color", color)
	corpse.set("label_name", label)
	parent.add_child(corpse)
	corpse.global_position = pos
	# Player walks through corpses (vehicles + bullets still collide).
	var player_node := get_node_or_null("Player")
	if player_node is CollisionObject3D and corpse.has_method("ignore_collision_with"):
		corpse.ignore_collision_with(player_node)
	if drop_id == "" or not itables_by_id.has(drop_id):
		return
	var table: Dictionary = itables_by_id[drop_id]
	# Same shape as the crate seeding loop — roll N times, push each into
	# the corpse via add(). add() weight-checks; first refusal stops seeding.
	for i in range(CORPSE_LOOT_ROLLS):
		var result: Dictionary = _roll_table(table)
		var rid: String = String(result.get("id", ""))
		if rid == "" or rid == NOTHING_ITEM_ID:
			continue
		var n: int = int(result.get("count", 1))
		if not corpse.has_method("add"):
			break
		if not corpse.add(rid, n):
			break

func _build_actor(actor_id: String, preset: Dictionary) -> Node3D:
	# Only "dummy" is wired right now. Constructed in code (not a packed
	# scene) so editor-spawned copies can carry per-preset HP/regen/etc.
	if actor_id != "dummy":
		return null
	var body := StaticBody3D.new()
	body.set_script(DUMMY_SCRIPT)
	body.hp_max = int(preset.get("hp", 500))
	body.regen_rate = float(preset.get("regen", 0.0))
	body.enemy = bool(preset.get("enemy", false))
	body.xp_reward = int(preset.get("xp", 0))
	body.drop_table_id = String(preset.get("drop_table_id", ""))
	# Display name — used by the floating HP plate above the actor.
	var display: String = String(preset.get("actor_name", "")).strip_edges()
	if display == "":
		display = String(preset.get("name", ""))
	body.actor_name = display
	# Capsule body matches main.tscn's hand-built dummy dimensions.
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.7
	var cs := CollisionShape3D.new()
	cs.shape = cap
	cs.position = Vector3(0, 0.85, 0)
	body.add_child(cs)
	var cap_mesh := CapsuleMesh.new()
	cap_mesh.radius = 0.45
	cap_mesh.height = 1.7
	var mi := MeshInstance3D.new()
	mi.mesh = cap_mesh
	var mat := StandardMaterial3D.new()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.albedo_color = preset.get("color", Color(0.85, 0.55, 0.25, 1))
	mat.roughness = 0.7
	mi.material_override = mat
	mi.position = Vector3(0, 0.85, 0)
	body.add_child(mi)
	# Head sphere — own static body w/ head script for the headshot multiplier.
	var head := StaticBody3D.new()
	head.set_script(DUMMY_HEAD_SCRIPT)
	head.position = Vector3(0, 1.95, 0)
	var head_shape := SphereShape3D.new()
	head_shape.radius = 0.28
	var head_cs := CollisionShape3D.new()
	head_cs.shape = head_shape
	head.add_child(head_cs)
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.28
	head_mesh.height = 0.56
	var head_mi := MeshInstance3D.new()
	head_mi.mesh = head_mesh
	var head_mat := StandardMaterial3D.new()
	head_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	head_mat.albedo_color = Color(0.95, 0.7, 0.4, 1)
	head_mat.roughness = 0.7
	head_mi.material_override = head_mat
	head.add_child(head_mi)
	body.add_child(head)
	return body

func _roll_clothing_for(body: Node3D, preset: Dictionary) -> void:
	# Stub: roll each slot's mini loot table and stash on the actor as
	# meta. Once clothing renders, this swaps to actually equipping models.
	var clothing: Dictionary = preset.get("clothing", {})
	if clothing.is_empty():
		return
	var equipped: Dictionary = {}
	for slot_id in clothing.keys():
		var entries: Array = clothing[slot_id]
		if entries.is_empty():
			continue
		var total: float = 0.0
		for e in entries:
			var w: float = float(e.get("weight", 0.0))
			if w < 0.0:
				w = 0.0
			total += w
		if total <= 0.0:
			continue
		var roll: float = randf() * total
		var acc: float = 0.0
		for e in entries:
			var w2: float = float(e.get("weight", 0.0))
			if w2 < 0.0:
				w2 = 0.0
			acc += w2
			if roll <= acc:
				var picked: String = String(e.get("id", ""))
				if picked != "" and picked != NOTHING_ITEM_ID:
					equipped[slot_id] = picked
				break
	if not equipped.is_empty():
		body.set_meta("clothing", equipped)

func _disable_collision(root: Node) -> void:
	# Walk the spawned object subtree and turn off every CollisionShape3D
	# we find. Cheaper + safer than zeroing collision_layer on the body
	# (which would also stop area queries that may be useful later).
	for c in root.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = true
		_disable_collision(c)

func _input(event: InputEvent) -> void:
	# F9 toggles back to the editor with the current map intact.
	# Action OR raw-key, but not both — change_scene_to_file frees self.
	var is_f9: bool = event.is_action_pressed("editor_play") \
		or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9)
	if is_f9:
		get_tree().change_scene_to_file("res://editor.tscn")
	# F2 → toggle the foliage profiler if one was spawned.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		if _foliage_profiler != null:
			_foliage_profiler.call("toggle")
