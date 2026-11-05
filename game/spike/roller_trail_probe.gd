extends SceneTree
## Windowed probe of pulled rollers passing through furniture (board 578435a7,
## phase 1: measure only). It boots main.tscn twice, on the reference terminal
## with gate seats and a gate desk: once with both cafes (CafeTestLayout, two
## tables each) and once with a lounge (ActivityTestLayout). Each run spawns
## SPAWNS passengers with one roller, one every SPAWN_EVERY ticks, in turn a
## cafe (or lounge) visitor, a gate sitter (seated, boarding staggered), and a
## walker to the gate, all kept on time. The airport's own flow adds more. The
## clock is stepped a third of a tick a frame (60 frames a second, as in the
## game) for RUN_TICKS.
##
## Every frame, for every roller drawn in the pull (carry PULL with a live axle
## follower), the roller's box (CarryOnProps.bag_box on the bag node) is tested
## against the box of every mesh of every furniture piece (BuildView's object
## nodes; doors left out). The piece in use (the seat sat on, the cafe seat,
## the lounge display) is left out while its stage uses it; after that it
## counts, and is marked own. An overlap needs both:
##   BOX: the two oriented boxes overlap (separating-axis test); its depth is
##     the least overlap over the 15 axes.
##   GEOMETRY: at least one triangle of the furniture mesh crosses the
##     roller's box (a box overlap alone can be a table's empty corner); its
##     depth is how far the mesh reaches in, in quarter steps of the box's
##     least half size (0 for a graze). The own piece also counts while walking
##     to it (a reserved cafe seat), marked own.
## Pass values are positives: the probe prints pull frames, overlap frames per
## 1000 pull frames, the worst episodes (piece, mesh, stage, move tag, depth,
## vertices inside) and totals per piece and per stage.
##
## Counterfactuals, on the same simplified box (0.36 x 0.6 x 0.5 m, its centre
## 0.2 m from the axle toward the body, at the floor):
##   DRAWN: at the drawn axle (the control: it must also find overlaps).
##   PATH_CENTRE: 1 m back along the body's own drawn path (pure breadcrumb).
##   PATH_SIDE: 1 m back along that path offset 0.3 m to the pulling side.
##   BODY: a 0.44 x 1.6 x 0.28 m box on the body (does the walker itself clip).
##
## Plates: at most PLATES_PER_WORLD overlap moments a world, each deeper than
## the last plated, close and wide, plus a contact sheet. Before a save the
## roller, the furniture mesh and the body project inside the frame with a
## margin, and twins with the roller hidden and with the piece hidden each
## differ from the plate (in frame is not visible). Otherwise PROBE_INVALID,
## exit 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/roller_trail_probe.gd [-- --seed=N]
##
## Plates go to tools/blender/out/roller-trail/.

const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/roller-trail"
const WORLDS: Array[String] = ["cafe", "lounge"]
const SPAWNS := 18
const SPAWN_EVERY := 14
const RUN_TICKS := 1500
const PLATES_PER_WORLD := 3
const PLATE_MIN_M := 0.04
const PLATE_STEP_M := 0.02
const MARGIN_PX := 8.0
const MIN_DIFF_PX := 300
const TOP_EPISODES := 14
## Frames this soon after a probe spawn (a passenger set down beside the gate
## desk) are tagged spawn and left out of the settled rate.
const SETTLE_TICKS := 40
## Frames this soon after a roll-upright tip are tagged after_tip.
const AFTER_TIP_TICKS := 60
## A probe guest's cafe dwell or lounge stay is cut to end this soon after it
## sits, so its stand-up and walk-off fall inside RUN_TICKS.
const SHORT_STAY_TICKS := 60
const USE_STAGES := [
	Passenger.Stage.SITTING_DOWN,
	Passenger.Stage.SEATED,
	Passenger.Stage.STANDING_UP,
	Passenger.Stage.CAFE_SITTING_DOWN,
	Passenger.Stage.CAFE_SEATED,
	Passenger.Stage.CAFE_STANDING_UP,
	Passenger.Stage.SHOP_BROWSE,
]
const SIMPLE_HALF := Vector3(0.18, 0.3, 0.25)
const BODY_HALF := Vector3(0.22, 0.8, 0.14)

var _seed := 0
var _out_dir := ""
var _failed := false
var _main: Node3D
var _clock: SimClock
var _mode: BuildMode
var _sim: PassengerSim
var _views: PassengerViews
var _build_view: BuildView
var _cam: Camera3D
var _sheet: Array[Image] = []
var _plates := 0
var _ours: Array[Passenger] = []
## Furniture meshes: {oid, def, name, mi, half, verts (mesh-local)}.
var _meshes: Array[Dictionary] = []
var _walked := {}
var _side_walked := {}
var _last_used := {}
var _m := {}
var _spawned_at := {}


func _initialize() -> void:
	Engine.max_fps = SimClock.TICK_RATE * 3
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_seed = randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = int(arg.get_slice("=", 1))
	print("PROBE sim_seed=%d out_dir=%s" % [_seed, _out_dir])
	_run.call_deferred()


func _run() -> void:
	# The triangle test's self-test: one through the box, one beside it.
	var half := Vector3(0.2, 0.3, 0.1)
	var through := _tri_box(Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(0, 0, 1), half)
	var beside := _tri_box(Vector3(0.3, -1, 0), Vector3(0.3, 1, 0), Vector3(0.5, 0, 1), half)
	print("TRI_SELFTEST through=%s (true) beside=%s (false)" % [through, beside])
	if not through or beside:
		_invalid("the triangle test's self-test failed")
	var totals := {"pull": 0, "hit": 0}
	for world in WORLDS:
		if await _boot(world):
			await _watch(world)
			totals["pull"] += int(_m["pull"])
			totals["hit"] += int(_m["hit"])
		_main.queue_free()
		_cam = null
		await _frames(3)
	if not _sheet.is_empty():
		_save(_contact_sheet(_sheet), "contact_sheet.png")
	var rate: float = 1000.0 * totals["hit"] / maxf(totals["pull"], 1.0)
	print(
		(
			"TRAIL_CLEAR all worlds: %d overlap frames in %d roller-pull frames = %.1f per 1000"
			% [totals["hit"], totals["pull"], rate]
		)
	)
	print("PROBE done plates=%d failed=%s" % [_plates, _failed])
	quit(1 if _failed else 0)


func _boot(world: String) -> bool:
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	_clock = _main.get_node("SimClock") as SimClock
	_clock.seed_rng(_seed)
	(_main.get_node("BuildMode") as BuildMode).starter_shell = false
	root.add_child(_main)
	_clock.set_process(false)
	_clock.set_paused(false)
	await _frames(3)
	_mode = _main.get_node("BuildMode") as BuildMode
	_mode.set_process(false)
	_mode.set_tool(BuildMode.Tool.NONE)
	(_mode.get_node("Ghost") as Node3D).visible = false
	_sim = _main.get_node("PassengerSim") as PassengerSim
	_views = _main.get_node("PassengerViews") as PassengerViews
	var ids := {}
	if world == "cafe":
		ids = CafeTestLayout.build(_mode.grid, true)
	else:
		ids = ActivityTestLayout.build(_mode.grid, &"lounge")
	if not StarterFlight.add_gate_desk(_mode.grid):
		_invalid("%s: the gate desk was refused" % world)
		return false
	_build_view = _mode.get_node("BuildView") as BuildView
	_build_view.refresh(_mode.grid)
	await _frames(4)
	_sim.cafes.refresh()
	_sim.shops.refresh()
	_sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(
		_clock, _main.get_node("FlightSim") as FlightSim, staff
	)
	print("PROBE %s ids=%s hired=%d opened tick=%d" % [world, ids, hired, _clock.tick])
	if hired == 0 or doors < 0:
		_invalid("%s: the airport did not open" % world)
		return false
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	_collect_meshes(world)
	return not _meshes.is_empty()


func _collect_meshes(world: String) -> void:
	_meshes.clear()
	var defs := {}
	for oid in _mode.grid.object_ids():
		var def := String(_mode.grid.get_object(oid)["def"])
		if def.contains("door"):
			continue
		var node := _build_view.object_node(oid)
		if node == null:
			continue
		for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null or not mi.is_visible_in_tree():
				continue
			_meshes.append(
				{
					"oid": oid,
					"def": def,
					"name": String(mi.name),
					"mi": mi,
					"verts": mi.mesh.get_faces()
				}
			)
			defs[def] = int(defs.get(def, 0)) + 1
	print("FURNITURE %s meshes=%d per piece kind %s" % [world, _meshes.size(), defs])
	if _meshes.is_empty():
		_invalid("%s: no furniture meshes" % world)


## One passenger with one roller, kept on time, in `role`.
func _spawn(world: String, role: String, k: int) -> void:
	var p: Passenger = null
	for attempt in 200:
		p = _sim.get_passenger(
			_sim.spawn_now(FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0))
		)
		if SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER:
			break
		p.carry_on = 0
	ToiletTestLayout.calm(p)
	p.carry_on = 1
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _clock.tick
	p.at = ShopTestLayout.AIRSIDE_CELL + ReferenceTerminal.offset_on(_mode.grid)
	p.clear_path()
	_ours.append(p)
	_spawned_at[p.id] = _clock.tick
	if role == "gate":
		var seats := _sim.layout.seats
		var seat: Dictionary = seats[(k * 3) % seats.size()]
		p.stage = Passenger.Stage.SEATED
		p.seat_object = seat["object_id"]
		p.seat_cell = seat["cell"]
		p.seat_front = seat["front"]
		p.at = seat["front"]
		p.boarding_tick = _clock.tick + 40 + 30 * k
	elif role == "visit" and world == "cafe":
		p.boredom = 0
		_sim.cafes.try_visit(p)
	elif role == "visit":
		p.shop_cooldown = 0
		p.hunger = 0
		p.boredom = 80
		NeedsPolicy.arbitrate(_sim, p)
	print("SPAWN %s %s id=%d tick=%d stage=%s" % [world, role, p.id, _clock.tick, _stage(p)])


func _watch(world: String) -> void:
	_ours.clear()
	_walked.clear()
	_side_walked.clear()
	_last_used.clear()
	_m = {
		"pull": 0,
		"hit": 0,
		"box_only": 0,
		"drawn": 0,
		"centre": 0,
		"side": 0,
		"body": 0,
		"episodes": {},
		"per_def": {},
		"per_stage": {},
		"per_tag": {},
		"rollers": {},
		"best_plated": 0.0,
		"plates": 0,
		"pull_stage": {},
		"tips": {},
		"spawn_pull": 0,
		"spawn_hit": 0,
	}
	var keep := func(_t: int) -> void:
		for q in _ours:
			q.late = false
	_clock.ticked.connect(keep)
	var start := _clock.tick
	var spawned := 0
	var roles := ["visit", "gate", "walker"]
	while _clock.tick < start + RUN_TICKS:
		if spawned < SPAWNS and _clock.tick >= start + spawned * SPAWN_EVERY:
			_spawn(world, roles[spawned % roles.size()], spawned / roles.size())
			spawned += 1
		_clock.advance(SimClock.STEP / 3.0)
		await _frames(1)
		await _measure(world)
	_clock.ticked.disconnect(keep)
	_summary(world)


func _measure(world: String) -> void:
	var props := _views.carry_on_props()
	for p: Passenger in _sim._passengers:
		var body := _views.node_for(p.id)
		if body == null or p.carry_on <= 0:
			continue
		_shorten(p)
		var used := _used_piece(p)
		if used >= 0:
			_last_used[p.id] = used
		_remember(p, body)
		var got: Dictionary = props.props_of(p.id)
		var bags: Array = got.get("bags", [])
		for i in bags.size():
			if got["kinds"][i] != SecurityLooks.Kind.ROLLER:
				continue
			var state := props.bag_state(p.id, i)
			if state.get("carry", -1) != SecurityLooks.Carry.PULL or not state.has("axle"):
				continue
			await _test_roller(world, p, body, bags[i], got["kinds"][i], state, used)


func _test_roller(
	world: String,
	p: Passenger,
	body: Node3D,
	bag: Node3D,
	kind: SecurityLooks.Kind,
	state: Dictionary,
	used: int
) -> void:
	_m["pull"] += 1
	_m["rollers"][p.id] = true
	var box := _obb(bag.global_transform, CarryOnProps.bag_box(kind))
	var tag := _tag(state, p.id)
	if state.has("roll_tip") and not _m["tips"].has(p.id):
		_m["tips"][p.id] = _clock.tick
	if _m["tips"].has(p.id) and _clock.tick - int(_m["tips"][p.id]) <= AFTER_TIP_TICKS:
		tag = "after_tip:" + tag
	var fresh: bool = _clock.tick - int(_spawned_at.get(p.id, -100000)) < SETTLE_TICKS
	if fresh:
		tag = "spawn:" + tag
		_m["spawn_pull"] += 1
	_m["pull_stage"][_stage(p)] = int(_m["pull_stage"].get(_stage(p), 0)) + 1
	var worst := {}
	var any_box := false
	for mesh: Dictionary in _meshes:
		if int(mesh["oid"]) == used:
			continue
		var mi: MeshInstance3D = mesh["mi"]
		var other := _obb(mi.global_transform, mi.get_aabb())
		var depth := _sat(box, other)
		if depth <= 0.0:
			continue
		any_box = true
		var local := CarryOnProps.bag_box(kind)
		var inside := _verts_inside(mesh, bag.global_transform, local)
		if inside == 0:
			continue
		depth = _core_depth(mesh, bag.global_transform, local)
		if worst.is_empty() or depth > float(worst["depth"]):
			worst = {"mesh": mesh, "depth": depth, "inside": inside}
	var floor_y := body.global_position.y
	var axle: Vector3 = state.get("drawn_axle", bag.global_position)
	var side_sign := _side_sign(body, axle)
	if _simple_hits(axle, body.global_position, floor_y, used):
		_m["drawn"] += 1
	var walked: Array = _walked.get(p.id, [])
	var back := Basis(Vector3.UP, body.rotation.y) * Vector3.FORWARD
	if (
		walked.size() > 1
		and _simple_hits(CarryOnProps.trail(walked, back), body.global_position, floor_y, used)
	):
		_m["centre"] += 1
	var side_line: Array = _side_walked.get(p.id, [])
	if side_line.size() > 1:
		var at := CarryOnProps.trail(side_line, back)
		if side_sign != 0.0 and _simple_hits(at, body.global_position, floor_y, used):
			_m["side"] += 1
	if _body_hits(body, used):
		_m["body"] += 1
	if worst.is_empty():
		if any_box:
			_m["box_only"] += 1
		return
	_m["hit"] += 1
	if fresh:
		_m["spawn_hit"] += 1
	var mesh: Dictionary = worst["mesh"]
	var oid: int = mesh["oid"]
	var own: bool = _last_used.get(p.id, -1) == oid or _used_piece(p, true) == oid
	var stage := _stage(p)
	var key := "%d:%d:%s" % [p.id, oid, mesh["name"]]
	var ep: Dictionary = _m["episodes"].get(key, {"frames": 0, "depth": 0.0})
	ep["frames"] = int(ep["frames"]) + 1
	if float(worst["depth"]) > float(ep["depth"]):
		(
			ep
			. merge(
				{
					"depth": worst["depth"],
					"inside": worst["inside"],
					"tick": _clock.tick,
					"stage": stage,
					"tag": tag,
					"def": mesh["def"],
					"mesh": mesh["name"],
					"own": own,
					"pid": p.id,
					"oid": oid,
				},
				true
			)
		)
	_m["episodes"][key] = ep
	var label := "%s%s" % [mesh["def"], " (own)" if own else ""]
	_m["per_def"][label] = int(_m["per_def"].get(label, 0)) + 1
	_m["per_stage"][stage] = int(_m["per_stage"].get(stage, 0)) + 1
	_m["per_tag"][tag] = int(_m["per_tag"].get(tag, 0)) + 1
	var depth: float = worst["depth"]
	if (
		_m["plates"] < PLATES_PER_WORLD
		and not fresh
		and depth >= PLATE_MIN_M
		and depth > float(_m["best_plated"]) + PLATE_STEP_M
	):
		_m["best_plated"] = depth
		_m["plates"] += 1
		var shot := "%s_%d_p%d_%s" % [world, _m["plates"], p.id, mesh["def"]]
		print(
			(
				"OVERLAP_PLATE %s tick %d depth %.3f inside %d mesh %s stage %s tag %s own %s"
				% [shot, _clock.tick, depth, worst["inside"], mesh["name"], stage, tag, own]
			)
		)
		await _plate(shot, body, bag, mesh, 3.0)
		await _plate(shot + "_wide", body, bag, mesh, 4.5)


## Cuts a probe guest's cafe dwell or lounge stay (SHORT_STAY_TICKS).
func _shorten(p: Passenger) -> void:
	if not _spawned_at.has(p.id):
		return
	var end := _clock.tick + SHORT_STAY_TICKS
	if p.stage == Passenger.Stage.CAFE_SEATED:
		var visit := _sim.cafes.visit_of(p.id)
		if visit != null and visit.dwell_end > end:
			visit.dwell_end = end
	elif p.stage == Passenger.Stage.SHOP_BROWSE:
		var shop := _sim.shops.visit_of(p.id)
		if shop != null and shop.deadline > end:
			shop.deadline = end


## The piece `p` uses now (its stage uses it), or -1.
func _used_piece(p: Passenger, any_stage := false) -> int:
	if not any_stage and not p.stage in USE_STAGES:
		return -1
	if (
		p.stage
		in [Passenger.Stage.SITTING_DOWN, Passenger.Stage.SEATED, Passenger.Stage.STANDING_UP]
	):
		return p.seat_object
	var shop := _sim.shops.visit_of(p.id)
	if shop != null:
		return shop.display
	var visit := _sim.cafes.visit_of(p.id)
	return int(visit.seat["object_id"]) if visit != null and not visit.seat.is_empty() else -1


## Keeps the body's drawn path and a line 0.3 m out on the pulling side.
func _remember(p: Passenger, body: Node3D) -> void:
	var at := body.global_position
	var walked: Array = _walked.get(p.id, [])
	if walked.is_empty() or (walked[-1] as Vector3).distance_to(at) > 0.01:
		walked.append(at)
		var side := 1.0
		var props := _views.carry_on_props()
		var state := props.bag_state(p.id, 0)
		if state.has("drawn_axle"):
			side = _side_sign(body, state["drawn_axle"])
		var across := Basis(Vector3.UP, body.rotation.y) * Vector3.RIGHT * side
		var line: Array = _side_walked.get(p.id, [])
		line.append(at + across * CarryOnProps.TRAIL_SIDE_M)
		_side_walked[p.id] = _trim(line)
	_walked[p.id] = _trim(walked)


static func _trim(line: Array) -> Array:
	var length := 0.0
	for i in range(line.size() - 1, 0, -1):
		length += (line[i] as Vector3).distance_to(line[i - 1])
		if length > 3.0:
			return line.slice(i - 1)
	return line


## +1 when `axle` is on the body's +x side, -1 on its -x side.
static func _side_sign(body: Node3D, axle: Vector3) -> float:
	var local := (
		Transform3D(Basis(Vector3.UP, body.rotation.y), body.global_position).affine_inverse()
		* axle
	)
	return signf(local.x)


func _tag(state: Dictionary, id: int) -> String:
	if state.get("queue", false):
		return "queue"
	if state.has("roll_tip"):
		return "roll"
	if state.get("park", false):
		return "park"
	if _views.carry_on_props().transfer_progress(id, 0) < 1.0:
		return "move"
	return "trail"


func _stage(p: Passenger) -> String:
	return Passenger.Stage.keys()[p.stage]


## Whether the simplified roller box with its axle at `axle` meets furniture.
func _simple_hits(axle: Vector3, body_at: Vector3, floor_y: float, used: int) -> bool:
	var toward := body_at - axle
	toward.y = 0.0
	if toward.length() < 0.01:
		return false
	toward = toward.normalized()
	var centre := axle + toward * 0.2
	centre.y = floor_y + SIMPLE_HALF.y
	var basis := Basis(Vector3.UP, atan2(toward.x, toward.z))
	return _box_hits(Transform3D(basis, centre), SIMPLE_HALF, used)


func _body_hits(body: Node3D, used: int) -> bool:
	var centre := body.global_position + Vector3.UP * BODY_HALF.y
	return _box_hits(Transform3D(Basis(Vector3.UP, body.rotation.y), centre), BODY_HALF, used)


func _box_hits(xf: Transform3D, half: Vector3, used: int) -> bool:
	var box := {"c": xf.origin, "u": [xf.basis.x, xf.basis.y, xf.basis.z], "e": half}
	var local := AABB(-half, half * 2.0)
	for mesh: Dictionary in _meshes:
		if int(mesh["oid"]) == used:
			continue
		var mi: MeshInstance3D = mesh["mi"]
		if _sat(box, _obb(mi.global_transform, mi.get_aabb())) <= 0.0:
			continue
		if _verts_inside(mesh, xf, local) > 0:
			return true
	return false


## An oriented box {c, u (unit axes), e (half extents)} of `aabb` under `xf`.
static func _obb(xf: Transform3D, aabb: AABB) -> Dictionary:
	var axes: Array[Vector3] = []
	var half := Vector3.ZERO
	for i in 3:
		var col: Vector3 = [xf.basis.x, xf.basis.y, xf.basis.z][i]
		var length := col.length()
		axes.append(col / maxf(length, 1e-6))
		half[i] = aabb.size[i] * 0.5 * length
	return {"c": xf * aabb.get_center(), "u": axes, "e": half}


## The least overlap of two oriented boxes over the 15 separating axes, or 0
## or less when they are apart.
static func _sat(a: Dictionary, b: Dictionary) -> float:
	var d: Vector3 = b["c"] - a["c"]
	var reach := (a["e"] as Vector3).length() + (b["e"] as Vector3).length()
	if d.length() >= reach:
		return -1.0
	var axes: Array[Vector3] = []
	axes.append_array(a["u"])
	axes.append_array(b["u"])
	for ua: Vector3 in a["u"]:
		for ub: Vector3 in b["u"]:
			var cross := ua.cross(ub)
			if cross.length() > 1e-4:
				axes.append(cross.normalized())
	var least := INF
	for axis in axes:
		var ra := 0.0
		var rb := 0.0
		for i in 3:
			ra += a["e"][i] * absf((a["u"][i] as Vector3).dot(axis))
			rb += b["e"][i] * absf((b["u"][i] as Vector3).dot(axis))
		var overlap := ra + rb - absf(d.dot(axis))
		if overlap <= 0.0:
			return overlap
		least = minf(least, overlap)
	return least


## How many of the furniture mesh's triangles cross `box` (in `xf`'s frame)
## shrunk about its centre to `share` of its size.
static func _verts_inside(mesh: Dictionary, xf: Transform3D, box: AABB, share := 1.0) -> int:
	var to_box := xf.affine_inverse() * (mesh["mi"] as MeshInstance3D).global_transform
	var faces: PackedVector3Array = mesh["verts"]
	var centre := box.get_center()
	var half := box.size * 0.5 * share
	var count := 0
	for t in range(0, faces.size(), 3):
		var a := to_box * faces[t] - centre
		var b := to_box * faces[t + 1] - centre
		var c := to_box * faces[t + 2] - centre
		if _tri_box(a, b, c, half):
			count += 1
	return count


## How deep, in metres, the mesh reaches into the box: the box's least half
## extent times the largest shrink step (of 4) at which a triangle still
## crosses it; 0 when only the full box is crossed.
static func _core_depth(mesh: Dictionary, xf: Transform3D, box: AABB) -> float:
	var least := minf(box.size.x, minf(box.size.y, box.size.z)) * 0.5
	for share in [0.25, 0.5, 0.75]:
		if _verts_inside(mesh, xf, box, share) > 0:
			return least * (1.0 - share)
	return 0.0


## Whether the triangle a b c crosses the box of half extents `h` at the
## origin (separating axes: the box's 3, the triangle's normal, 9 edge
## crosses).
static func _tri_box(a: Vector3, b: Vector3, c: Vector3, h: Vector3) -> bool:
	for i in 3:
		if minf(a[i], minf(b[i], c[i])) > h[i] or maxf(a[i], maxf(b[i], c[i])) < -h[i]:
			return false
	var edges: Array[Vector3] = [b - a, c - b, a - c]
	var axes: Array[Vector3] = [edges[0].cross(edges[1])]
	for e in edges:
		axes.append(Vector3(0.0, -e.z, e.y))
		axes.append(Vector3(e.z, 0.0, -e.x))
		axes.append(Vector3(-e.y, e.x, 0.0))
	for axis in axes:
		if axis.length_squared() < 1e-12:
			continue
		var pa := a.dot(axis)
		var pb := b.dot(axis)
		var pc := c.dot(axis)
		var r := h.x * absf(axis.x) + h.y * absf(axis.y) + h.z * absf(axis.z)
		if minf(pa, minf(pb, pc)) > r or maxf(pa, maxf(pb, pc)) < -r:
			return false
	return true


func _summary(world: String) -> void:
	var pull: int = _m["pull"]
	var per := func(n: int) -> float: return 1000.0 * n / maxf(pull, 1.0)
	print(
		(
			"TRAIL_CLEAR %s rollers=%d pull frames=%d overlap frames=%d (%.1f per 1000); box-only %d"
			% [world, _m["rollers"].size(), pull, _m["hit"], per.call(_m["hit"]), _m["box_only"]]
		)
	)
	print(
		(
			(
				"COUNTERFACTUAL %s simple box per 1000 pull frames: drawn %.1f, path_centre %.1f, "
				+ "path_side %.1f, body %.1f"
			)
			% [
				world,
				per.call(_m["drawn"]),
				per.call(_m["centre"]),
				per.call(_m["side"]),
				per.call(_m["body"])
			]
		)
	)
	print("PER_PIECE %s %s" % [world, _m["per_def"]])
	print("PER_STAGE %s %s" % [world, _m["per_stage"]])
	print("PER_TAG %s %s" % [world, _m["per_tag"]])
	print("PULL_STAGE %s %s" % [world, _m["pull_stage"]])
	print("TIPS %s %d tips into the pull: %s" % [world, _m["tips"].size(), _m["tips"]])
	var settled: int = pull - int(_m["spawn_pull"])
	var real_hits: int = int(_m["hit"]) - int(_m["spawn_hit"])
	print(
		(
			"TRAIL_CLEAR_SETTLED %s without the first %d ticks after a probe spawn: %d in %d (%.1f per 1000)"
			% [world, SETTLE_TICKS, real_hits, settled, 1000.0 * real_hits / maxf(settled, 1.0)]
		)
	)
	var eps: Array = _m["episodes"].values()
	eps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["depth"] > b["depth"])
	print("EPISODES %s %d (passenger, piece, mesh)" % [world, eps.size()])
	for ep: Dictionary in eps.slice(0, TOP_EPISODES):
		print(
			(
				"WORST %s p%d %s#%d mesh %s depth %.3f inside %d frames %d tick %d stage %s tag %s own %s"
				% [
					world,
					ep["pid"],
					ep["def"],
					ep["oid"],
					ep["mesh"],
					ep["depth"],
					ep["inside"],
					ep["frames"],
					ep["tick"],
					ep["stage"],
					ep["tag"],
					ep["own"]
				]
			)
		)
	if pull == 0:
		_invalid("%s: no roller was drawn in the pull" % world)


## A plate of the roller in `bag` meeting `mesh`, from beside the pair, the
## camera `dist` m off; proven in frame and visible before it is saved.
func _plate(shot: String, body: Node3D, bag: Node3D, mesh: Dictionary, dist: float) -> void:
	var mi: MeshInstance3D = mesh["mi"]
	var piece_at := mi.global_transform * mi.get_aabb().get_center()
	var bag_at := bag.global_position
	var target := bag_at.lerp(piece_at, 0.3)
	target.y = body.global_position.y + 0.7
	var across := piece_at - bag_at
	across.y = 0.0
	var away := (
		Vector3(-across.z, 0.0, across.x).normalized() if across.length() > 0.01 else Vector3.BACK
	)
	var off_body := bag_at - body.global_position
	off_body.y = 0.0
	if away.dot(off_body) < 0.0:
		away = -away
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 45.0
		_main.add_child(_cam)
	_cam.look_at_from_position(target + away * dist + Vector3.UP * dist * 0.9, target, Vector3.UP)
	_cam.current = true
	await _frames(3)
	var img := root.get_texture().get_image()
	var size := Vector2(img.get_size())
	var inside := Rect2(Vector2.ONE * MARGIN_PX, size - Vector2.ONE * 2.0 * MARGIN_PX)
	var points := {
		"bag": bag_at,
		"piece": piece_at,
		"feet": body.global_position,
		"head": body.global_position + Vector3.UP * 1.7,
	}
	var flat := {}
	for name: String in points:
		var at: Vector2 = _cam.unproject_position(points[name])
		flat[name] = at
		if _cam.is_position_behind(points[name]) or not inside.has_point(at):
			_invalid("%s: %s at %s is out of frame %s" % [shot, name, at, size])
			return
	bag.visible = false
	await _frames(2)
	var no_bag := root.get_texture().get_image()
	bag.visible = true
	var piece_node := _build_view.object_node(int(mesh["oid"]))
	piece_node.visible = false
	await _frames(2)
	var no_piece := root.get_texture().get_image()
	piece_node.visible = true
	var bag_px := _diff(img, no_bag)
	var piece_px := _diff(img, no_piece)
	print(
		(
			"PLATE %s tick %d at=%s bag_diff=%d piece_diff=%d"
			% [shot, _clock.tick, flat, bag_px, piece_px]
		)
	)
	if bag_px < MIN_DIFF_PX or piece_px < MIN_DIFF_PX:
		_invalid("%s: %d px from the roller, %d from the piece" % [shot, bag_px, piece_px])
		return
	_save(img, shot + ".png")
	_sheet.append(img)
	_plates += 1


func _diff(a: Image, b: Image) -> int:
	var count := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.06:
				count += 4
	return count


func _contact_sheet(plates: Array[Image]) -> Image:
	var w := plates[0].get_width() / 2
	var h := plates[0].get_height() / 2
	var rows := ceili(plates.size() / 2.0)
	var sheet := Image.create(w * 2, h * rows, false, Image.FORMAT_RGBA8)
	for i in plates.size():
		var small := plates[i].duplicate() as Image
		small.convert(Image.FORMAT_RGBA8)
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(w * (i % 2), h * (i / 2)))
	return sheet


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
