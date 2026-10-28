extends SceneTree
## Windowed plates for the staff spots (decision
## staff-spot-design-a-derived-staff-spot-behind-each-desk-and): staff drawn
## on duty on their station's spot, facing its front. Boots the real main scene
## with a new random sim seed (printed), builds ReferenceTerminal through the
## HUD's starter-terminal button, then edits the landside hall in phases:
##   1 facing 0: the starter desks and scanners, agents and officers on duty,
##     plated close and wide (desk_f0_*, scanner_f0_*)
##   2 walk-out: one agent fired, a frame strip of it walking from its desk to
##     the entrance (walk_out_strip)
##   3 facing 1: the starter desks removed, one desk and one scanner placed at
##     facing 1, plated close and wide (desk_f1_*, scanner_f1_*)
##   4 desk row: three desks in a row with a one-cell gap between them, each
##     outlet cell one belt into a collector two rows behind the desks
##     (decision desk-belts-run-one-row-back-desk-then-the-agent-row-then-the, v3),
##     plated wide and close (desk_row_*); diagnostic: a desk nobody reaches is
##     printed as a STAFFED line with entrance_path_cells=0 and does not fail the run
##   5 legacy: a save edited past today's rules (a seat row on a desk's spot)
##     loaded through SaveGame.load_world(), plated with its sign caption
##     (legacy_spot_blocked)
## A staff member counts as shown when PlateSight.person_shown() passes and its
## drawn feet are on the floor; a station counts as shown when its centre
## projects inside the frame and a sight line to it is not blocked before it.
## A plate that fails prints PROBE_INVALID and the probe exits 1. A guard
## thread calls OS.crash() on a stall.
##
## Run (one windowed Godot run project-wide; this probe holds the slot):
##   timeout 900 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/staff_spot_plates_probe.gd
##
## Plates go to tools/blender/out/staff-spot/.

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/staff-spot"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 60000
const WAIT_LIMIT_MS := 180000
const DUTY_TICKS := 1500
const MIN_SUBJECT_PX := 16.0
const FEET_TOLERANCE_M := 0.05
const CLOSE_M := 6.0
const WIDE_M := 14.0
const OCCLUDER_OWNERS: Array[String] = [
	"Airside/Terminal", "BuildMode", "PlaneView", "PassengerViews", "StaffCharacters"
]
const DESK := &"checkin_desk"
const SCANNER := &"security_scanner"
const SEATS := &"seat_row"
## Phase 3 anchors, at facing 1, in the landside hall (x 10-21, y 9-17).
const F1_DESK := Vector2i(13, 12)
const F1_SCANNER := Vector2i(20, 14)
## Phase 4: desks on ROW_Y at ROW_XS (a one-cell gap between them), the agent
## and outlet row ROW_Y - 1, and the collector ROW_Y - 2 from the last outlet
## west to COLLECTOR_END_X, clear of the scanners' lanes.
const ROW_XS: Array[int] = [11, 14, 17]
const ROW_Y := 14
const COLLECTOR_END_X := 10
## Phase 5: a desk whose spot (20, 11) the seat row covers.
const LEGACY_DESK := Vector2i(20, 12)
const LEGACY_SEATS := Vector2i(19, 11)
const STRIP_FRAMES := 5
const STRIP_EVERY_TICKS := 20
const CAPTION_OUTLINE_PX := 8.0

var _out_dir := ""
var _failed := false
var _stage := "init"
var _heartbeat_ms := 0
var _guard_mutex := Mutex.new()
var _guard_stop := false
var _guard: Thread
var _main: Node3D
var _cam: Camera3D
var _rig: TycoonCamera
var _clock: SimClock
var _sim: PassengerSim
var _staff: StaffSim
var _views: StaffCharacters
var _hud: PassengerHud
var _build: BuildMode
var _markers: MissMarkers
var _saved: Array[Image] = []


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_beat("init")
	_guard = Thread.new()
	_guard.start(_watch)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	_beat(_stage)
	return false


func _beat(stage: String) -> void:
	_guard_mutex.lock()
	_stage = stage
	_heartbeat_ms = Time.get_ticks_msec()
	_guard_mutex.unlock()


## Guard thread: a frozen main thread never reaches _process, so check from here.
func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_guard_mutex.lock()
		var stop := _guard_stop
		var idle_ms := Time.get_ticks_msec() - _heartbeat_ms
		var stage := _stage
		_guard_mutex.unlock()
		if stop:
			return
		if idle_ms > HANG_LIMIT_MS:
			print("PROBE_INVALID hang stage=%s no heartbeat for %d ms" % [stage, idle_ms])
			OS.crash("staff spot plates probe hung")


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _run() -> void:
	await _boot()
	await _phase_facing_0()
	await _phase_walk_out()
	await _phase_facing_1()
	await _phase_desk_row()
	await _phase_legacy()
	_main.queue_free()
	await _frames(3)
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	if not _saved.is_empty():
		_save(_sheet(), "contact_sheet", false)
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


# ------------------------------------------------------------ setup


func _boot() -> void:
	_beat("boot")
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	var seed := randi()
	_clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	# The rescue-grant toast would sit over the plates for its 8 s hold.
	(_main.get_node("BuildMenu") as BuildMenu).grant_hold_s = 0.5
	root.add_child(_main)
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_sim = _main.get_node("PassengerSim")
	_staff = _main.get_node("Staff")
	_views = _main.get_node("StaffCharacters")
	_hud = _main.get_node("PassengerHud")
	_build = _main.get_node("BuildMode")
	_markers = (_main.get_node("PassengerViews") as PassengerViews).get_node("MissMarkers")
	await _frames(5)
	print("PROBE camera home_distance=%.1f distance=%.1f" % [_rig.home_distance, _rig.distance])
	_hud.press_starter_terminal()
	_build.set_tool(BuildMode.Tool.NONE)
	await _frames(2)
	if _build.tool != BuildMode.Tool.NONE or (_build.get_node("Ghost") as Node3D).visible:
		_invalid("the build tool or its ghost is still on after clearing it")
	for i in _sim.layout.desks.size():
		_staff.hire(StaffMember.Role.CHECKIN)
	for i in _sim.layout.scanners.size():
		_staff.hire(StaffMember.Role.SECURITY)
	print(
		(
			"PROBE desks=%d scanners=%d hired=%d"
			% [_sim.layout.desks.size(), _sim.layout.scanners.size(), _staff.member_ids().size()]
		)
	)


## Commits `edits` on the live grid as BuildMode does, without the wallet.
func _edit(label: String, edits: Array[BuildEdit]) -> bool:
	var grid := _build.grid
	grid.hold_signals()
	var result := BuildTransaction.commit_plan(grid, edits, null)
	grid.release_signals()
	(_build.get_node("BuildView") as BuildView).refresh(grid)
	print("EDIT %s ok=%s %s" % [label, result.ok, result.reason_text()])
	if not result.ok:
		_invalid("%s: the edit was refused (%s)" % [label, result.reason_text()])
	return result.ok


## Lays a belt line as BuildMode.lay_belt() does, without the wallet.
func _belt(from: Vector2i, to: Vector2i) -> bool:
	var plan := BeltShaper.plan_line(_build.grid, from, to, 0)
	if not plan.result.ok:
		_invalid("belt %s-%s refused (%s)" % [from, to, plan.result.reason_text()])
		return false
	return _edit("belt %s-%s" % [from, to], plan.edits)


## Steps frames until `done` holds or `ticks` sim ticks pass; false on timeout.
func _until(stage: String, done: Callable, ticks: int) -> bool:
	_beat(stage)
	var start_ms := Time.get_ticks_msec()
	var limit := _clock.tick + ticks
	while not done.call():
		if _clock.tick >= limit or Time.get_ticks_msec() - start_ms > WAIT_LIMIT_MS:
			print("WAIT %s timed out at tick %d" % [stage, _clock.tick])
			return false
		await process_frame
	return true


func _on_duty_at(station: int) -> StaffMember:
	var id := _staff.staff_at(station)
	if id == 0:
		return null
	var m := _staff.get_member(id)
	return m if m.state == StaffMember.State.ON_DUTY else null


## Runs the clock fast until every one of `stations` has a member on duty.
func _wait_duty(stage: String, stations: Array[int]) -> bool:
	_hud.press_speed(3)
	var all := func() -> bool:
		return stations.all(func(s: int) -> bool: return _on_duty_at(s) != null)
	var ok: bool = await _until(stage, all, DUTY_TICKS)
	_hud.press_speed(0)
	await _frames(3)
	return ok


# ------------------------------------------------------------ checks


func _aim(at: Vector3, distance: float, yaw: float) -> void:
	_rig.stop_follow()
	_rig.position = Vector3(at.x, 0.0, at.z)
	_rig.yaw = yaw
	_rig.distance = distance


func _frame_rect() -> Rect2:
	return Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)


func _owners() -> Array[Node]:
	var owners: Array[Node] = []
	for path in OCCLUDER_OWNERS:
		owners.append(_main.get_node(path))
	return owners


func _colliders(subjects: Dictionary) -> Node3D:
	var holder := PlateSight.colliders(root, _owners(), subjects)
	var unbaked: Array = holder.get_meta("unbaked")
	if not unbaked.is_empty():
		_invalid("skinned meshes not baked: %s" % [unbaked])
	await physics_frame
	await physics_frame
	return holder


func _station_centre(station: int) -> Vector3:
	var record := _sim.grid.get_object(station)
	var def := BuildCatalog.get_def(StringName(record["def"]))
	var cells := def.footprint(record["anchor"], record["facing"])
	return BuildView.object_transform(_sim.grid, cells, record["facing"]).origin


## Prints where a station's member stands against its footprint and front, and
## fails when the spot is inside the footprint or the member is not drawn on it.
func _spot_report(label: String, station: int) -> void:
	var record := _sim.grid.get_object(station)
	var def_id := StringName(record["def"])
	var cells := BuildCatalog.get_def(def_id).footprint(record["anchor"], record["facing"])
	var spot := _staff.spot_of(station)
	var m := _on_duty_at(station)
	var drawn := _views.node_for(m.id).position if m != null else Vector3.INF
	var yaw := rad_to_deg(_views.node_for(m.id).rotation.y) if m != null else NAN
	print(
		(
			(
				"SPOT %s station=%d def=%s anchor=%s facing=%d footprint=%s spot=%s beside=%s"
				+ " front=%s member=%s drawn=%s post=%s yaw_deg=%.0f post_yaw_deg=%.0f"
			)
			% [
				label,
				station,
				def_id,
				record["anchor"],
				record["facing"],
				cells,
				spot,
				StaffSpots.beside_of(def_id, record["anchor"], record["facing"]),
				TerminalLayout.front_of(record["facing"]),
				m.id if m != null else 0,
				drawn,
				_views.post_position(station),
				yaw,
				rad_to_deg(_views.post_yaw(station)),
			]
		)
	)
	if cells.has(spot):
		_invalid("%s: the staff spot %s is inside the footprint" % [label, spot])
	var now := _views.tick_position(m.id, true) if m != null else Vector3.INF
	if m != null and now.distance_to(_views.post_position(station)) > 0.001:
		_invalid("%s: member %d is not drawn on its spot" % [label, m.id])


## Grabs the plate with the scene paused; checks each member in `ids` with
## PlateSight.person_shown() and its feet, and each of `stations` for being in
## frame and unblocked. Returns {ok, image}.
func _check(label: String, ids: Array[int], stations: Array[int]) -> Dictionary:
	paused = true
	var img: Image = await PlateSight.grab(self)
	var subjects := {}
	for id in ids:
		subjects[_views.node_for(id)] = str(id)
	var holder: Node3D = await _colliders(subjects)
	var bounds: Dictionary = holder.get_meta("bounds")
	var twin: Dictionary = await PlateSight.hud_twin(self, _main)
	var bare: Image = twin["image"]
	var changed := PlateSight.differing(img, bare, Rect2i(Vector2i.ZERO, img.get_size()), 4)
	print("HUD %s layers_hidden=%d plate_px_changed=%d" % [label, twin["layers"], changed])
	var ok := changed > 0
	for id in ids:
		var box: AABB = bounds.get(str(id), AABB())
		var seen := PlateSight.person_shown(
			_cam, box, str(id), _frame_rect(), img, bare, MIN_SUBJECT_PX
		)
		var m := _staff.get_member(id)
		print(
			(
				(
					"VISIBLE %s member=%d role=%d state=%d drawn=%s px=%s height_px=%.0f on=%d"
					+ " past=%d blockers=%s in_frame=%s hud_px=%d ok=%s"
				)
				% [
					label,
					id,
					m.role,
					m.state,
					_views.node_for(id).position,
					seen.get("px"),
					seen.get("height_px", 0.0),
					seen["on"],
					seen["past"],
					seen["blockers"],
					seen.get("in_frame"),
					seen.get("hud_px", 0),
					seen["ok"]
				]
			)
		)
		ok = ok and seen["ok"]
		ok = _feet("%s_member%d" % [label, id], box) and ok
	for station in stations:
		ok = _station_shown(label, station) and ok
	holder.free()
	paused = false
	return {"ok": ok, "image": img}


func _feet(label: String, box: AABB) -> bool:
	var gap := box.position.y - _sim.grid.origin.y
	print(
		"FEET %s lowest_y=%.3f gap_m=%.3f height_m=%.3f" % [label, box.position.y, gap, box.size.y]
	)
	return absf(gap) <= FEET_TOLERANCE_M


## The station's centre, half a metre up, projects inside the frame and the
## first hit on a sight line to it is not more than a metre before it (its own
## counter or arch is hit first).
func _station_shown(label: String, station: int) -> bool:
	var at := _station_centre(station) + Vector3(0.0, 0.5, 0.0)
	var from := _cam.global_position
	var px := _cam.unproject_position(at)
	var in_frame := not _cam.is_position_behind(at) and _frame_rect().has_point(px)
	var to := at + (at - from).normalized() * PlateSight.PAST_M
	var space := _cam.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	var short := 0.0
	var by := ""
	if not hit.is_empty():
		short = from.distance_to(at) - from.distance_to(hit.position)
		by = str((hit.collider as Node).get_meta("mesh", ""))
	var ok := in_frame and short <= 1.0
	print(
		(
			"STATION %s station=%d px=(%.0f,%.0f) in_frame=%s first_hit=%s short_m=%.2f ok=%s"
			% [label, station, px.x, px.y, in_frame, by, short, ok]
		)
	)
	return ok


## Aims at `at` from the four quarter turns from `yaw` until every subject is
## shown; saves the plate. Returns whether it was saved.
func _plate(
	name: String, ids: Array[int], stations: Array[int], at: Vector3, distance: float, yaw: float
) -> bool:
	_beat(name)
	var result := {}
	for turn in 4:
		var view_yaw := wrapf(yaw + turn * PI / 2.0, -PI, PI)
		_aim(at, distance, view_yaw)
		await _frames(25)
		print(
			(
				"PLATE %s tick=%d at=%s distance=%.0f yaw=%.2f"
				% [name, _clock.tick, at, distance, view_yaw]
			)
		)
		result = await _check(name, ids, stations)
		if result["ok"]:
			_save(result["image"], name)
			return true
	_invalid("%s: not every subject shown from any side" % name)
	_save(result["image"], name + "_INVALID", false)
	return false


## Close and wide plates of the member on duty at `station`.
func _duty_plates(label: String, station: int, yaw: float) -> void:
	_spot_report(label, station)
	var m := _on_duty_at(station)
	if m == null:
		_invalid("%s: nobody on duty at station %d" % [label, station])
		return
	var ids: Array[int] = [m.id]
	var stations: Array[int] = [station]
	var at := _views.post_position(station)
	_overlap_report(label, station, m.id)
	await _plate(label + "_close", ids, stations, at, CLOSE_M, yaw)
	await _plate(label + "_wide", ids, stations, at, WIDE_M, yaw)


## Structure evidence, not appearance: each mesh part of the station's view
## whose world bounds overlap the member's drawn bounds, with the overlap in x
## and z. An idle body's bounds take in its arms, so a small overlap with a
## part beside it is expected; the plates answer whether it clips.
func _overlap_report(label: String, station: int, id: int) -> void:
	var node := (_build.get_node("BuildView") as BuildView).object_node(station)
	if node == null:
		print("OVERLAP %s station=%d has no view node" % [label, station])
		return
	var body := _views.node_for(id)
	var subjects := {body: "member"}
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		subjects[mi] = "part:%s" % mi.name
	var owners: Array[Node] = [node, body]
	var holder := PlateSight.colliders(root, owners, subjects)
	var bounds: Dictionary = holder.get_meta("bounds")
	holder.free()
	var me: AABB = bounds.get("member", AABB())
	var hits: Array[String] = []
	for tag: String in bounds:
		var part: AABB = bounds[tag]
		if tag == "member" or not part.intersects(me):
			continue
		var both := part.intersection(me)
		hits.append("%s x=%.2f z=%.2f" % [tag, both.size.x, both.size.z])
	print(
		(
			"OVERLAP %s station=%d member=%d body=%s parts=%d overlapping=%s"
			% [label, station, id, me, bounds.size() - 1, hits]
		)
	)


# ------------------------------------------------------------ phases


func _phase_facing_0() -> void:
	var stations: Array[int] = []
	stations.append_array(_sim.layout.desks)
	stations.append_array(_sim.layout.scanners)
	if not await _wait_duty("facing_0_duty", stations):
		_invalid("facing 0: not every starter station staffed by tick %d" % _clock.tick)
		return
	# The starter stations face 0: front +z, so a yaw of PI/4 looks from the
	# passenger side at three quarters.
	await _duty_plates("desk_f0", _sim.layout.desks[0], PI / 4.0)
	await _duty_plates("scanner_f0", _sim.layout.scanners[0], PI / 4.0)


func _phase_walk_out() -> void:
	var on_duty := {}
	for id in _staff.member_ids():
		var m := _staff.get_member(id)
		if m.role == StaffMember.Role.CHECKIN and m.state == StaffMember.State.ON_DUTY:
			on_duty[id] = m.station
	if on_duty.is_empty():
		_invalid("walk-out: no agent on duty to fire")
		return
	_hud.press_speed(0)
	_staff.fire(StaffMember.Role.CHECKIN)
	_hud.press_speed(1)
	var out := func() -> StaffMember:
		for id: int in on_duty:
			var m := _staff.get_member(id)
			if m != null and m.state == StaffMember.State.WALKING_OUT:
				return m
		return null
	if not await _until("walk_out_start", func() -> bool: return out.call() != null, 600):
		_invalid("walk-out: the fired agent never set out")
		return
	_hud.press_speed(0)
	var member: StaffMember = out.call()
	var desk: int = on_duty[member.id]
	var door := _sim.grid.cell_to_world(ReferenceTerminal.ENTRANCE_CELL)
	print("WALKOUT member=%d desk=%d at=%s door=%s" % [member.id, desk, member.at, door])
	_aim((_views.post_position(desk) + door) / 2.0, 11.0, -0.75 * PI)
	var frames: Array[Image] = []
	var gaps: Array[float] = []
	for i in STRIP_FRAMES:
		var node := _views.node_for(member.id)
		if node == null:
			print("WALKOUT frame %d: member %d gone (reached the entrance)" % [i, member.id])
			break
		_hud.press_speed(0)
		await _frames(20)
		var player := node.get_node("AnimationPlayer") as AnimationPlayer
		gaps.append(Vector2(node.position.x, node.position.z).distance_to(Vector2(door.x, door.z)))
		print(
			(
				"WALKOUT frame %d tick=%d state=%d clip=%s drawn=%s to_door_m=%.2f"
				% [i, _clock.tick, member.state, player.current_animation, node.position, gaps[-1]]
			)
		)
		if member.state != StaffMember.State.WALKING_OUT or player.current_animation != "walk":
			_invalid("walk-out frame %d: not walking out" % i)
		var one: Array[int] = [member.id]
		var none: Array[int] = []
		var check: Dictionary = await _check("walk_out_f%d" % i, one, none)
		if not check["ok"]:
			_invalid("walk-out frame %d: member %d not shown" % [i, member.id])
		frames.append(check["image"])
		_hud.press_speed(1)
		var target := _clock.tick + STRIP_EVERY_TICKS
		await _until("walk_out", func() -> bool: return _clock.tick >= target, 200)
	_hud.press_speed(0)
	for i in range(1, gaps.size()):
		if gaps[i] >= gaps[i - 1]:
			_invalid("walk-out frame %d is no nearer the entrance than frame %d" % [i, i - 1])
	if frames.size() < 4:
		_invalid("walk-out: only %d frames before the member left" % frames.size())
	if not frames.is_empty():
		_save(_strip(frames), "walk_out_strip")


func _phase_facing_1() -> void:
	var edits: Array[BuildEdit] = []
	for desk in _sim.layout.desks:
		edits.append(BuildEdit.remove_object(desk))
	edits.append(BuildEdit.place_object(DESK, F1_DESK, 1))
	edits.append(BuildEdit.place_object(SCANNER, F1_SCANNER, 1))
	if not _edit("facing_1", edits):
		return
	_staff.hire(StaffMember.Role.SECURITY)
	var desk := _sim.grid.object_at(F1_DESK)
	var scanner := _sim.grid.object_at(F1_SCANNER)
	print(
		(
			"FACING1 desk=%d usable=%s blocked=%s scanner=%d usable=%s blocked=%s"
			% [
				desk,
				_sim.layout.is_usable(desk),
				_staff.spot_blocked(desk),
				scanner,
				_sim.layout.is_usable(scanner),
				_staff.spot_blocked(scanner)
			]
		)
	)
	var stations: Array[int] = [desk, scanner]
	if not await _wait_duty("facing_1_duty", stations):
		_invalid("facing 1: the desk or scanner not staffed by tick %d" % _clock.tick)
		return
	# Front at facing 1 is -x: a yaw of -PI/4 looks from the passenger side.
	await _duty_plates("desk_f1", desk, -PI / 4.0)
	await _duty_plates("scanner_f1", scanner, -PI / 4.0)


func _phase_desk_row() -> void:
	var edits: Array[BuildEdit] = []
	for desk in _sim.layout.desks:
		edits.append(BuildEdit.remove_object(desk))
	edits.append(BuildEdit.remove_object(_sim.grid.object_at(F1_SCANNER)))
	for x in ROW_XS:
		edits.append(BuildEdit.place_object(DESK, Vector2i(x, ROW_Y), 0))
	if not _edit("desk_row", edits):
		return
	if not _belt(Vector2i(ROW_XS[-1] + 1, ROW_Y - 2), Vector2i(COLLECTOR_END_X, ROW_Y - 2)):
		return
	for x in ROW_XS:
		if not _belt(Vector2i(x + 1, ROW_Y - 1), Vector2i(x + 1, ROW_Y - 1)):
			return
	for i in ROW_XS.size() - 1:
		_staff.hire(StaffMember.Role.CHECKIN)
	var desks: Array[int] = []
	for x in ROW_XS:
		desks.append(_sim.grid.object_at(Vector2i(x, ROW_Y)))
	var pieces := []
	for y in range(ROW_Y - 2, ROW_Y):
		for x in range(COLLECTOR_END_X, ROW_XS[-1] + 2):
			var id := _sim.grid.object_at(Vector2i(x, y))
			if id != 0:
				pieces.append("%s:%s" % [Vector2i(x, y), _sim.grid.get_object(id)["def"]])
	print("ROW pieces %s" % [pieces])
	await _wait_duty("desk_row_duty", desks)
	var ids: Array[int] = []
	var centre := Vector3.ZERO
	for desk in desks:
		var spot := _staff.spot_of(desk)
		var path := _sim.grid.find_path(ReferenceTerminal.ENTRANCE_CELL, spot)
		var m := _on_duty_at(desk)
		print(
			(
				(
					"STAFFED desk=%d spot=%s usable=%s blocked=%s unreachable=%s"
					+ " entrance_path_cells=%d on_duty=%s"
				)
				% [
					desk,
					spot,
					_sim.layout.is_usable(desk),
					_staff.spot_blocked(desk),
					_staff.spot_unreachable(desk),
					path.size(),
					m.id if m != null else 0
				]
			)
		)
		if m != null:
			ids.append(m.id)
		centre += _station_centre(desk)
	for id in _staff.member_ids():
		var m := _staff.get_member(id)
		print(
			"MEMBER %d role=%d state=%d station=%d at=%s" % [id, m.role, m.state, m.station, m.at]
		)
	centre /= desks.size()
	await _plate("desk_row_wide", ids, desks, centre, WIDE_M, PI * 0.75)
	await _plate("desk_row_close", ids, desks, centre, CLOSE_M + 3.0, PI * 0.75)


func _phase_legacy() -> void:
	_beat("legacy")
	var save := _main.get_node("SaveGame") as SaveGame
	var data: Dictionary = JSON.parse_string(JSON.stringify(save.snapshot()))
	var grid: Dictionary = data["grid"]
	var next := int(grid["next_object_id"])
	for entry in [[DESK, LEGACY_DESK], [SEATS, LEGACY_SEATS]]:
		var anchor: Vector2i = entry[1]
		(grid["objects"] as Array).append(
			{"id": next, "def": str(entry[0]), "anchor": [anchor.x, anchor.y], "facing": 0}
		)
		next += 1
	grid["next_object_id"] = next
	if not save.load_world(data):
		_invalid("legacy: the edited save did not load (%s)" % save.message_text())
		return
	_hud.press_speed(1)
	var after := _clock.tick + 3
	await _until("legacy_ticks", func() -> bool: return _clock.tick >= after, 100)
	_hud.press_speed(0)
	await _frames(3)
	var desk := _sim.grid.object_at(LEGACY_DESK)
	var text := _markers.closed_text(desk)
	print(
		(
			"LEGACY desk=%d spot=%s blocked=%s usable=%s reason=%s caption=%s"
			% [
				desk,
				_staff.spot_of(desk),
				_staff.spot_blocked(desk),
				_sim.layout.is_usable(desk),
				MissSignals.closed_reason(_sim, desk),
				text
			]
		)
	)
	if text != MissMarkers.SPOT_BLOCKED_CAPTION:
		_invalid("legacy: the sign caption is %s" % text)
		return
	var none: Array[int] = []
	var stations: Array[int] = [desk]
	for turn in 4:
		var yaw := wrapf(PI / 4.0 + turn * PI / 2.0, -PI, PI)
		_aim(_station_centre(desk), WIDE_M, yaw)
		await _frames(25)
		var check: Dictionary = await _check("legacy_spot_blocked", none, stations)
		if check["ok"] and _sign_shown(desk, check["image"]):
			_save(check["image"], "legacy_spot_blocked")
			return
	_invalid("legacy: the station or its sign not shown from any side")


## The station's sign is visible and its icon and caption rects (computed from
## the font, not measured) lie inside the frame. No HUD-overlap check here.
func _sign_shown(station: int, img: Image) -> bool:
	var sign := _markers.closed_sign_for(station)
	if sign == null or not sign.visible or _cam.is_position_behind(sign.global_position):
		print("SIGN station=%d not visible" % station)
		return false
	var per_screen := root.get_visible_rect().size.y / float(img.get_height())
	var anchor := _cam.unproject_position(sign.global_position)
	var sign_px := MissMarkers.SIGN_PX * per_screen
	var icon := Rect2(anchor - Vector2(sign_px / 2.0, sign_px), Vector2.ONE * sign_px)
	var text := _markers.closed_text(station)
	var size := (
		ThemeDB.fallback_font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, MissMarkers.CAPTION_FONT
		)
		* per_screen
	)
	var lift := (MissMarkers.SIGN_PX + MissMarkers.CAPTION_GAP_PX) * per_screen + size.y
	var caption := Rect2(anchor + Vector2(-size.x / 2.0, -lift), size).grow(
		CAPTION_OUTLINE_PX * per_screen
	)
	var inside := _frame_rect().encloses(icon) and _frame_rect().encloses(caption)
	print(
		(
			"SIGN station=%d text=%s icon=%s caption=%s in_frame=%s"
			% [station, text, icon, caption, inside]
		)
	)
	return inside


# ------------------------------------------------------------ output


func _strip(frames: Array[Image]) -> Image:
	var w := frames[0].get_width() / 2
	var h := frames[0].get_height() / 2
	var strip := Image.create(w * frames.size(), h, false, Image.FORMAT_RGBA8)
	for i in frames.size():
		var small := frames[i].duplicate() as Image
		small.convert(Image.FORMAT_RGBA8)
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		strip.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(w * i, 0))
	return strip


func _save(img: Image, name: String, sheet := true) -> void:
	var path := _out_dir.path_join(name + ".png")
	var err := img.save_png(path)
	if err != OK:
		_invalid("could not save %s (error %d)" % [path, err])
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
	if sheet:
		var copy := img.duplicate() as Image
		copy.convert(Image.FORMAT_RGBA8)
		_saved.append(copy)


## Every saved plate scaled to 640 wide, two to a row.
func _sheet() -> Image:
	var w := 640
	var rows := (_saved.size() + 1) / 2
	var heights: Array[int] = []
	for img in _saved:
		heights.append(int(img.get_height() * w / float(img.get_width())))
	var row_h := 0
	for h in heights:
		row_h = maxi(row_h, h)
	var sheet := Image.create(w * 2, row_h * rows, false, Image.FORMAT_RGBA8)
	for i in _saved.size():
		var small := _saved[i].duplicate() as Image
		small.resize(w, heights[i], Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, w, heights[i]), Vector2i(w * (i % 2), row_h * (i / 2)))
	return sheet
