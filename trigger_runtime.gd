extends Node

# Play-mode evaluator for authored trigger volumes. Ticks on _process so
# we never block physics; per-trigger eval is cheap (just AABB
# containment checks on the player + a handful of item/actor positions).
# When a trigger's compound condition resolves true, it fires its event
# list with delays/repeats. Fired events look up their target prop_ids
# in _props_by_id and apply the event's kind (currently only Destroy).

const NOTHING_ITEM_ID := "nothing"

# Snapshot of authored data — set by bootstrap before we enter the tree.
var triggers: Array = []   # Array of dicts mirroring MapState.placed_triggers
var events: Array = []     # Array of dicts mirroring MapState.map_events
var props_by_id: Dictionary = {}  # prop_id → Node3D
# Player reference resolved lazily (might not exist yet on _ready if
# bootstrap order changes).
var _player_ref: Node3D = null
# Per-trigger runtime state. Keyed by trigger_id.
#   { armed: bool,         # condition currently true
#     fires_done: int,     # how many times this trigger has fired
#     last_fire_t: float } # secs since trigger fire (for cooldown)
var _state: Dictionary = {}
# Dead triggers don't tick anymore. Populated when a trigger with
# destroy_after_fire fires, or when a Destroy event targets a trigger's
# prop_id (self or otherwise). Using a flag instead of mutating the
# triggers array keeps the per-frame for-loop safe against concurrent
# changes from event callbacks (including self-targeting fires).
var _dead: Dictionary = {}  # trigger_id → true
# prop_id → trigger_id lookup so Destroy events can resolve trigger
# targets (which never exist as live runtime nodes, so they wouldn't
# show up in props_by_id).
var _trigger_pid_to_tid: Dictionary = {}
var _t_global: float = 0.0

func setup(p_triggers: Array, p_events: Array, p_props_by_id: Dictionary) -> void:
	triggers = p_triggers
	events = p_events
	props_by_id = p_props_by_id
	for tr in triggers:
		_state[String(tr.get("trigger_id", ""))] = {"armed": false, "fires_done": 0, "last_fire_t": -1e9}
		var pid: String = String(tr.get("prop_id", ""))
		if pid != "":
			_trigger_pid_to_tid[pid] = String(tr.get("trigger_id", ""))

func _process(delta: float) -> void:
	_t_global += delta
	if _player_ref == null:
		_player_ref = get_tree().get_root().find_child("Player", true, false) as Node3D
	for tr in triggers:
		_tick_trigger(tr)

func _tick_trigger(tr: Dictionary) -> void:
	var tid: String = String(tr.get("trigger_id", ""))
	if _dead.get(tid, false):
		return
	var st: Dictionary = _state.get(tid, {})
	if st.is_empty():
		return
	# Skip evaluating triggers that have exhausted their repeat budget so
	# we don't keep re-running condition checks once they're dead.
	var mode: String = String(tr.get("repeat_mode", "once"))
	var fires_done: int = int(st.get("fires_done", 0))
	if mode == "once" and fires_done >= 1:
		return
	if mode == "n" and fires_done >= int(tr.get("repeat_count", 1)):
		return
	var aabb: AABB = _trigger_world_aabb(tr)
	var truthy: bool = _eval_conditions(tr, aabb)
	# Cooldown gate — once a trigger fires, suppress re-fires until the
	# user-set cooldown elapses, regardless of whether the condition
	# stayed true. Without this, an infinite-repeat trigger would loop
	# every frame while the player stands inside.
	var cd: float = float(tr.get("repeat_cooldown", 1.0))
	if truthy and (_t_global - float(st.get("last_fire_t", -1e9))) >= cd:
		st["last_fire_t"] = _t_global
		st["fires_done"] = fires_done + 1
		_fire_trigger(tr)
		# Self-destruct flag — even if an event the trigger fires also
		# targets the trigger, this just sets the same flag twice. Mark
		# AFTER _fire_trigger so synchronous self-fire still gets to run.
		if bool(tr.get("destroy_after_fire", false)):
			_dead[tid] = true
	_state[tid] = st

func _trigger_world_aabb(tr: Dictionary) -> AABB:
	# Reconstruct the same AABB editor_trigger_box uses (anchored at
	# origin + extending up by SIZE.y). We don't have a live node here
	# (triggers are editor-only visuals); rebuild the world AABB from
	# the stored xform applied to a unit AABB.
	var xf: Transform3D = tr.get("xform", Transform3D.IDENTITY)
	# editor_trigger_box.SIZE = (4,4,4) and the wire is centred above the
	# origin (y in [0..4]). Use that as the canonical local AABB.
	var local := AABB(Vector3(-2, 0, -2), Vector3(4, 4, 4))
	return xf * local

func _point_in_aabb(p: Vector3, b: AABB) -> bool:
	# Built-in AABB.has_point doesn't account for object rotation, but
	# we use it after transforming the point into local space below.
	return p.x >= b.position.x and p.x <= b.position.x + b.size.x \
		and p.y >= b.position.y and p.y <= b.position.y + b.size.y \
		and p.z >= b.position.z and p.z <= b.position.z + b.size.z

func _point_in_trigger(p: Vector3, tr: Dictionary) -> bool:
	# Rotation-correct containment: project into the trigger's local space.
	var xf: Transform3D = tr.get("xform", Transform3D.IDENTITY)
	var local: Vector3 = xf.affine_inverse() * p
	return _point_in_aabb(local, AABB(Vector3(-2, 0, -2), Vector3(4, 4, 4)))

func _eval_conditions(tr: Dictionary, _aabb: AABB) -> bool:
	var conds: Array = tr.get("conditions", [])
	if conds.is_empty():
		return false
	var results: Array = []
	for c in conds:
		var v: bool = _eval_condition(c, tr)
		if bool(c.get("negate", false)):
			v = not v
		results.append(v)
	var op: String = String(tr.get("logic_op", "and"))
	match op:
		"or":
			for v in results:
				if v:
					return true
			return false
		"xor":
			var n: int = 0
			for v in results:
				if v:
					n += 1
			return n == 1
		_:
			for v in results:
				if not v:
					return false
			return true

func _eval_condition(c: Dictionary, tr: Dictionary) -> bool:
	var ctype: String = String(c.get("type", "player_in"))
	match ctype:
		"player_in":
			if _player_ref == null:
				return false
			return _point_in_trigger(_player_ref.global_position, tr)
		"item_count":
			var min_n: int = int(c.get("min_count", 1))
			var filter: String = String(c.get("filter_id", ""))
			var hits: int = 0
			for n in get_tree().get_nodes_in_group("pickups"):
				if not n is Node3D:
					continue
				if filter != "" and "item_id" in n and String(n.item_id) != filter:
					continue
				if _point_in_trigger((n as Node3D).global_position, tr):
					hits += 1
					if hits >= min_n:
						return true
			# Fallback: pickups are Area3Ds spawned by main_bootstrap without
			# a group tag. Walk the ItemSpawns + ActorSpawns roots if no
			# group hits.
			if hits < min_n:
				hits = _count_in_subtree("ItemSpawns", tr, filter, "item_id")
			return hits >= min_n
		"actor_count":
			var min_a: int = int(c.get("min_count", 1))
			var filter_a: String = String(c.get("filter_id", ""))
			var hits_a: int = _count_in_subtree("ActorSpawns", tr, filter_a, "actor_id")
			return hits_a >= min_a
	return false

func _count_in_subtree(root_name: String, tr: Dictionary, filter_id: String, filter_field: String) -> int:
	var root: Node = get_tree().get_root().find_child(root_name, true, false)
	if root == null:
		return 0
	var n: int = 0
	for c in root.get_children():
		if not c is Node3D:
			continue
		if filter_id != "" and filter_field in c and String(c.get(filter_field)) != filter_id:
			continue
		if _point_in_trigger((c as Node3D).global_position, tr):
			n += 1
	return n

func _fire_trigger(tr: Dictionary) -> void:
	var delay: float = float(tr.get("delay", 0.0))
	var between: float = float(tr.get("inter_event_delay", 0.0))
	var fire_ids: Array = tr.get("fire_event_ids", [])
	for i in range(fire_ids.size()):
		var eid: String = String(fire_ids[i])
		var wait: float = delay + between * float(i)
		if wait > 0.0:
			get_tree().create_timer(wait).timeout.connect(func(): _apply_event(eid))
		else:
			_apply_event(eid)

func _apply_event(event_id: String) -> void:
	var ev: Dictionary = _find_event(event_id)
	if ev.is_empty():
		return
	var kind: String = String(ev.get("kind", "destroy"))
	var targets: Array = ev.get("targets", [])
	match kind:
		"destroy":
			for pid in targets:
				var spid: String = String(pid)
				var n: Node = props_by_id.get(spid, null)
				if n != null and is_instance_valid(n):
					n.queue_free()
					props_by_id.erase(spid)
				# Trigger volumes have no runtime node, so destroying one
				# means marking it dead in the eval list. Works for both
				# self-destruct (trigger targets its own prop_id) and
				# chain-destruct (trigger A kills trigger B). The _dead
				# flag short-circuits _tick_trigger before any condition
				# eval, so a self-fire that destroys self is safe — the
				# already-scheduled fire still applies, future ticks skip.
				if _trigger_pid_to_tid.has(spid):
					_dead[String(_trigger_pid_to_tid[spid])] = true

func _find_event(event_id: String) -> Dictionary:
	for ev in events:
		if String(ev.get("id", "")) == event_id:
			return ev
	return {}
