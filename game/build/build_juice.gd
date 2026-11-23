class_name BuildJuice
extends Node3D
## Strictly presentation-only build feedback (B3, decisions 45a81488 and
## 593876df): pop-in scale bounce on newly placed BuildView object nodes,
## subtle floating -$cost / +$refund pops, and lightweight placement dust puffs.
## Triggered ONLY by explicit BuildMode.player_committed signals — never from
## save loads, ReferenceTerminal boot, RepairPlan, or Undo.

const POP_IN_START_SCALE := 0.78
const POP_IN_PEAK_SCALE := 1.08
const POP_IN_UP_S := 0.11
const POP_IN_SETTLE_S := 0.11

const COST_POP_DURATION_S := 0.65
const COST_POP_RISE_M := 0.75
const COST_POP_START_Y := 1.35
const COST_COLOR := Color(1.0, 0.9, 0.62)
const REFUND_COLOR := Color(0.55, 0.92, 0.62)

const PUFF_DURATION_S := 0.38
const PUFF_COUNT := 4
const PUFF_COLOR := Color(0.95, 0.91, 0.82, 0.55)
const MAX_CONCURRENT_POPS := 10
const MAX_CONCURRENT_PUFFS := 8

static var _puff_mesh: SphereMesh

var build_mode: BuildMode
var commit_count := 0

var _watched: BuildMode
var _live_pops: Array[Label3D] = []
var _live_puffs: Array[Node3D] = []


func _ready() -> void:
	name = "BuildJuice"
	if build_mode != null:
		watch(build_mode)


func _exit_tree() -> void:
	_live_pops.clear()
	_live_puffs.clear()
	if _watched != null and is_instance_valid(_watched):
		if _watched.player_committed.is_connected(_on_player_committed):
			_watched.player_committed.disconnect(_on_player_committed)
	_watched = null


func _process(delta: float) -> void:
	advance(delta)


## Connects to `mode.player_committed`. Safe to call repeatedly.
func watch(mode: BuildMode) -> void:
	if _watched == mode:
		return
	if _watched != null and is_instance_valid(_watched):
		if _watched.player_committed.is_connected(_on_player_committed):
			_watched.player_committed.disconnect(_on_player_committed)
	_watched = mode
	build_mode = mode
	if mode != null and not mode.player_committed.is_connected(_on_player_committed):
		mode.player_committed.connect(_on_player_committed)


func active_pop_count() -> int:
	return _live_pops.size()


func active_puff_count() -> int:
	return _live_puffs.size()


## Advances active floating pops and dust puffs by `seconds`, freeing finished
## effects cleanly with zero orphan nodes.
func advance(seconds: float) -> void:
	if seconds <= 0.0:
		return
	for label in _live_pops.duplicate():
		if not is_instance_valid(label):
			_live_pops.erase(label)
			continue
		var age: float = float(label.get_meta(&"age")) + seconds
		label.set_meta(&"age", age)
		var t := clampf(age / COST_POP_DURATION_S, 0.0, 1.0)
		label.position.y = float(label.get_meta(&"start_y")) + COST_POP_RISE_M * ease(t, 0.45)
		label.modulate.a = pow(1.0 - t, 1.4)
		if t >= 1.0:
			_live_pops.erase(label)
			label.queue_free()
	for puff in _live_puffs.duplicate():
		if not is_instance_valid(puff):
			_live_puffs.erase(puff)
			continue
		var age: float = float(puff.get_meta(&"age")) + seconds
		puff.set_meta(&"age", age)
		var t := clampf(age / PUFF_DURATION_S, 0.0, 1.0)
		_step_puff(puff, t)
		if t >= 1.0:
			_live_puffs.erase(puff)
			puff.queue_free()


func _step_puff(puff: Node3D, t: float) -> void:
	var mat := puff.get_meta(&"mat") as StandardMaterial3D
	if mat != null:
		mat.albedo_color.a = PUFF_COLOR.a * (1.0 - t * t)
	var ease_out := 1.0 - pow(1.0 - t, 2.0)
	for child in puff.get_children():
		var mote := child as MeshInstance3D
		if mote == null or not mote.has_meta(&"dir"):
			continue
		var dir: Vector3 = mote.get_meta(&"dir")
		mote.position = dir * (0.42 * ease_out) + Vector3(0.0, 0.12 + 0.32 * t, 0.0)
		var s := lerpf(1.0, 0.35, t)
		mote.scale = Vector3.ONE * s


func _on_player_committed(info: Dictionary) -> void:
	commit_count += 1
	if not is_inside_tree():
		return
	var mode := _watched if _watched != null else build_mode
	if mode != null:
		for object_id in info.get("object_ids", []):
			_pop_in_object(mode.object_node(int(object_id)))
	var world_pos: Vector3 = info.get("world_pos", Vector3.ZERO)
	var net_cost := int(info.get("net_cost", 0))
	if net_cost != 0:
		_spawn_cost_pop(world_pos, net_cost)
	_spawn_dust_puff(world_pos)


func _pop_in_object(node: Node3D) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	if node.has_meta(&"_juice_tween"):
		var prev := node.get_meta(&"_juice_tween") as Tween
		if prev != null and prev.is_valid():
			prev.kill()
	node.scale = Vector3.ONE * POP_IN_START_SCALE
	var tween := node.create_tween()
	node.set_meta(&"_juice_tween", tween)
	(
		tween
		. tween_property(node, "scale", Vector3.ONE * POP_IN_PEAK_SCALE, POP_IN_UP_S)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tween
		. tween_property(node, "scale", Vector3.ONE, POP_IN_SETTLE_S)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)


func _spawn_cost_pop(world_pos: Vector3, net_cost: int) -> void:
	while _live_pops.size() >= MAX_CONCURRENT_POPS:
		var oldest := _live_pops.pop_front() as Label3D
		if is_instance_valid(oldest):
			oldest.queue_free()
	var label := CaptionFont.apply(Label3D.new())
	label.name = "CostPop"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 56
	label.outline_size = 14
	label.outline_modulate = Color(0.05, 0.05, 0.08)
	label.pixel_size = 0.006
	label.render_priority = 12
	label.outline_render_priority = 11
	if net_cost > 0:
		label.text = tr("-${amount}", "build juice").format({"amount": net_cost})
		label.modulate = COST_COLOR
	else:
		label.text = tr("+${amount}", "build juice").format({"amount": -net_cost})
		label.modulate = REFUND_COLOR
	var start_pos := world_pos + Vector3(0.0, COST_POP_START_Y, 0.0)
	label.position = start_pos
	label.set_meta(&"age", 0.0)
	label.set_meta(&"start_y", start_pos.y)
	add_child(label)
	_live_pops.append(label)


func _spawn_dust_puff(world_pos: Vector3) -> void:
	while _live_puffs.size() >= MAX_CONCURRENT_PUFFS:
		var oldest := _live_puffs.pop_front() as Node3D
		if is_instance_valid(oldest):
			oldest.queue_free()
	var mesh := _shared_puff_mesh()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PUFF_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var cluster := Node3D.new()
	cluster.name = "DustPuff"
	cluster.position = world_pos
	cluster.set_meta(&"age", 0.0)
	cluster.set_meta(&"mat", mat)
	for i in PUFF_COUNT:
		var angle := (float(i) / float(PUFF_COUNT)) * TAU + 0.35
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var mote := MeshInstance3D.new()
		mote.mesh = mesh
		mote.material_override = mat
		mote.position = dir * 0.12 + Vector3(0.0, 0.12, 0.0)
		mote.set_meta(&"dir", dir)
		cluster.add_child(mote)
	add_child(cluster)
	_live_puffs.append(cluster)


static func _shared_puff_mesh() -> SphereMesh:
	if _puff_mesh == null:
		_puff_mesh = SphereMesh.new()
		_puff_mesh.radius = 0.14
		_puff_mesh.height = 0.28
		_puff_mesh.radial_segments = 6
		_puff_mesh.rings = 3
	return _puff_mesh
