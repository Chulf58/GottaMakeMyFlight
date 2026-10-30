extends SceneTree
## Live windowed crossing of the basic security scanner (the interior kit's
## security_scanner booth) by passengers carrying their carry-on (board item
## basic-security-scanner-booth-is-narrower-than-the-walking-ch). Boots
## main/main.tscn with a new random sim seed (printed), builds the starter
## terminal through the HUD (two basic scanners), staffs it and opens the
## airport, then sends passengers with chosen carry-on (each bag kind, two
## bags, an alarm and a liquids repack, no bags) to security while the game
## runs.
##
## Every frame, every passenger near a booth is checked in the booth's own
## frame: points of its drawn body and of every bag it holds or has on the
## floor, against each booth mesh (a point is inside when a ray from it
## crosses the mesh an odd number of times). The floor mat is left out: a
## sole or a bag standing on a 1.2 cm mat is not a clip. Clearance is the gap
## from each point to the nearest part beside it (side parts) or above it
## (beam, lamp), at the same height and depth (a diagnostic on part bounds,
## not a penetration depth). The contact count is a sampled check (body
## vertices, bag surface points 4 cm apart), so for a passenger in the passage
## every point past the passage edge is also traced in to the edge: a booth
## part crossed on the way is a clip through a part thinner than the points
## are apart. Body points inside the passenger's own carried bags are counted
## too. Only one ruled clip outside the booth's length is printed instead of
## failed (_ruled_self_clip()): a hard case turning from the side to the front
## on the approach (accepted by the user 2026-10-29, "Accept, merge now").
## Every other body-in-bag point fails, a roller's lift or lowering and a
## pickup after a repack included, as does any contact or crossing; so does a
## sent passenger that never crossed mid-booth, an alarm or liquids passenger
## that never repacked, a bag kind never carried through, or a run that never
## checked a whole roller lift, roller lowering, and a hard case's and a
## shoulder bag's pickup after a repack (each printed with every SELF_DETAIL
## point: the bag, its move, the arm and the contact points in the body's
## frame). A passenger is followed until it has left the booth's surroundings
## after security, so the moves past the exit are checked. Controls: a bag
## set into a side panel must be inside its meshes, and a point just past the
## panel must cross it. Two plates of one crossing (mid-booth, leaving) prove
## the passenger and its bags are in frame and unblocked before they are
## saved. Close plates of a roller's lowering and a hard case's pickup after a
## repack, each at three moments (in its first half, its second half, settled), are taken
## with the sim clock paused at that moment, from a camera of the probe's own
## round the body, each kept only when the body and the bag are in frame, big
## enough and hit by sight lines with no blocker (_plate_close()); a missing one
## fails. Any failure prints PROBE_INVALID and exits 1. Plate moments are
## reached by stepping the paused clock, sight lines see meshes from either
## side, dark plates are refused, and a bag's close plate has a detail plate
## (PlateSteps).
##
## With --lane the east basic scanner is swapped for a security lane (as in the
## security visuals probe) and the west one removed, so every passenger walks
## through the lane's arch, narrowed to fit inside its cell (decision security-
## lane-arch-is-narrowed-to-fit-inside-its-cell-beside-a), and RUNNER_ROLES are
## sent too, kept late so they run. The arch is checked as a booth is (its mat
## left out); a bag in a tray on the X-ray belt beside it is checked for
## contact but not traced in to the passage, which it is not in. Instead of the
## booth's kind, move and crossing-plate requirements, the run must see every
## sent passenger cross mid-arch, at least two of them running, a returner's
## second pass, and a close plate of a passenger with its arms tucked mid-arch
## (each crossing prints its tuck weight there).
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/basic_scanner_crossing_probe.gd [-- --seed=N] [--lane]
## Crossing plates go to tools/blender/out/security-booth/, close plates to
## tools/blender/out/carry-selfclip/.

const PlateSight := preload("res://spike/plate_sight.gd")
const CarryContact := preload("res://spike/carry_contact.gd")
const CarryChecks := preload("res://spike/carry_probe_checks.gd")
const FloatCheck := preload("res://spike/carry_float_check.gd")
const PlateSteps := preload("res://spike/carry_plate_steps.gd")
const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/security-booth"
const CLOSE_OUT_REL := "res://../tools/blender/out/carry-selfclip"
const MAIN_SCENE := "res://main/main.tscn"
const RAY := Vector3(0.0013, 1.0, 0.0007)
const MARGIN_PX := 8.0
const MIN_SUBJECT_PX := 60.0
const RUN_LIMIT_MS := 240000
const SEND_GAP_TICKS := 20
const MAX_SPAWNS := 40
## Near a booth: inside this half-size around its origin, in its own frame
## (past BoothCarry.LEAD_M, so a roller's lift before the booth is checked whole).
const NEAR := Vector3(0.9, 3.0, 3.2)
## [first bag's kind or -1 for any, bags, liquids, alarm].
const ROLES := [
	[SecurityLooks.Kind.CASE, 1, false, false],
	[SecurityLooks.Kind.BACKPACK, 1, false, false],
	[SecurityLooks.Kind.SHOULDER, 1, true, false],
	[SecurityLooks.Kind.ROLLER, 1, false, false],
	[SecurityLooks.Kind.CASE, 2, false, false],
	[SecurityLooks.Kind.ROLLER, 2, false, false],
	[SecurityLooks.Kind.CASE, 1, false, true],
	[-1, 2, true, false],
	[-1, 0, false, false],
	[SecurityLooks.Kind.BACKPACK, 1, false, false],
]
const KIND_NAMES := ["case", "backpack", "shoulder", "roller"]
## Lane mode's extra roles, the fifth entry true: kept late, so they run.
const RUNNER_ROLES := [
	[-1, 0, false, false, true],
	[-1, 1, false, false, true],
	[-1, 1, false, true, true],
]
## The moves plated close, and the progress window of each of their moments
## (the first at 0.4, where a hard case lifted off the floor lay across the
## thighs; board item 5ed915b0).
const MOVE_PLATES: Array[String] = ["roller_lower", "repack_pickup_case"]
const MOMENTS := [[0.3, 0.5], [0.5, 0.99], [1.0, 1.0]]
## A close plate's camera: this far out and this high, aimed at AIM_M over the
## floor at the body; the body must be CLOSE_MIN_PX tall in it.
const CLOSE_M := 3.0
const CLOSE_HEIGHT_M := 1.7
const AIM_M := 1.0
const CLOSE_MIN_PX := 300.0
## Hand-led moves plated close (bag kind and move, hands left out), each at
## mid-move and near its end (_lead_plate_scan()).
const LEAD_PLATES: Array[String] = [
	"CASE floor>hand",
	"CASE hand>floor",
	"BACKPACK back>floor",
	"SHOULDER floor>shoulder",
	"ROLLER pull>floor",
	"ROLLER pull>hand",
	"ROLLER hand>pull",
	"CASE hand>tray",
	"CASE tray>hand",
	"BACKPACK back>tray",
	"BACKPACK tray>back",
	"SHOULDER tray>shoulder",
]
const LEAD_MOMENTS := [[0.4, 0.6], [0.8, 0.97]]
## Lane mode: the lane on the divider as the security visuals probe builds it.
const ARCH_AT := Vector2i(20, ReferenceTerminal.DIVIDER_Y)
const OLD_SCANNERS: Array[Vector2i] = [Vector2i(17, 8), Vector2i(19, 8)]

var _out_dir := ""
var _failed := false
var _main: Node3D
var _cam: Camera3D
var _rig: TycoonCamera
var _clock: SimClock
var _sim: PassengerSim
var _views: PassengerViews
## [node, inverse global transform, parts]; parts are [name, local AABB,
## inverse mesh transform, faces, mesh AABB].
var _booths: Array = []
var _roles: Array = []
var _sent: Array[int] = []
## Passenger id -> stats Dictionary.
var _stats := {}
var _kinds_crossed := {}
## Passenger id -> the bones of its first body-in-own-bag contact.
var _self_bones := {}
## Passenger id -> each bag's [home, carry] on its last check.
var _last_bag_state := {}
## Passenger id -> {bag index -> the kind of the move it is in: "roller_lift"
## (PULL to HAND), "roller_lower" (HAND to PULL), "repack_pickup_<kind>" (FLOOR
## to HAND after the repack resolved the incident) or "other"}, recorded when
## the move begins and kept until its transfer has finished.
var _bag_moves := {}
## Move kind -> how many of those moves were checked from start to end.
var _moves_done := {}
## Passenger id -> the process frame its moves were last tracked on: a frame
## missed in between (not near a booth, or plating) forgets the moves under
## way and the state they started from, so only a move seen to begin and end
## on unbroken checks counts as whole.
var _tracked_frame := {}
var _plated := false
var _plates_saved := 0
## True while the crossing plates are being taken.
var _plate_task := false
## Passenger id -> its role (ROLES entry).
var _role_of := {}
var _lane_mode := false
var _close_dir := ""
## Move kind -> true once its three close plates are saved.
var _move_plated := {}
var _arch_plated := false
## Lane mode: runner ids (kept late), and arch crossings counted.
var _runners := {}
## Passenger id -> true once it was measured running between the posts.
var _arch_runners := {}
var _arch_second := 0
## Lane mode: passenger id -> {security phase: true} seen on any frame (a
## lane's repack berth is away from the arch, outside the checked box).
var _phases_seen := {}
## The FLOAT check's tally over every drawn bag, every frame
## (FloatCheck.watch_float), and its control's states ([] until run).
var _floats := FloatCheck.float_counts()
var _float_control := []
## Key -> true once its hand-led move plates are saved.
var _lead_plated := {}
## The process frame a wanted plate move paused the clock on (_on_tick), or -1.
var _hold_frame := -1
## Passenger id -> its drawn pose last checked; body-in-own-bag points over
## distinct poses (a paused frame measures the same pose again).
var _self_seen := {}
var _self_distinct := 0


func _initialize() -> void:
	# --run=<name> writes this run's plates into their own folder.
	var run := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--run="):
			run = "/" + arg.get_slice("=", 1)
	_out_dir = ProjectSettings.globalize_path(OUT_REL + run).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_close_dir = ProjectSettings.globalize_path(CLOSE_OUT_REL + run).simplify_path()
	DirAccess.make_dir_recursive_absolute(_close_dir)
	_lane_mode = OS.get_cmdline_user_args().has("--lane")
	print("PROBE out_dir=", _out_dir, " close_dir=", _close_dir, " lane_mode=", _lane_mode)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	return false


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	await _boot()
	if not _failed:
		await _cross()
	_report()
	print("PROBE done failed=", _failed)
	# The one exit: 1 whenever failed=true was printed.
	var code := 1 if _failed else 0
	print("PROBE exit=%d path=_run" % code)
	quit(code)


func _boot() -> void:
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	var seed := randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed = int(arg.get_slice("=", 1))
	_clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	root.add_child(_main)
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_sim = _main.get_node("PassengerSim")
	_views = _main.get_node("PassengerViews")
	var hud := _main.get_node("PassengerHud") as PassengerHud
	await _frames(5)
	hud.press_starter_terminal()
	var build := _main.get_node("BuildMode") as BuildMode
	build.set_tool(BuildMode.Tool.NONE)
	if _lane_mode:
		_build_lane(build)
		# The removed scanners' nodes go at the end of the frame.
		await _frames(2)
	for child in (build.get_node("BuildView") as BuildView).get_children():
		if child.is_queued_for_deletion():
			continue
		var record: Dictionary = child.get_meta("record", {})
		if StringName(record.get("def", "")) in [&"security_scanner", SecurityLanes.ARCH]:
			_booths.append(_booth(child))
	if _booths.is_empty():
		_invalid("no basic scanner booth is drawn")
		return
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(_clock, _main.get_node("FlightSim"), staff)
	print("PROBE booths=%d hired=%d doors_tick=%d" % [_booths.size(), hired, doors])
	if doors < 0:
		_invalid("the airport did not open")
	for kind in SecurityLooks.Kind.values():
		print("BAGBOX kind=%d box=%s" % [kind, CarryOnProps.bag_box(kind)])
	_control()
	hud.press_speed(1)
	await _frames(10)


## The booth's drawn parts in its own frame. The kit merges a piece into one
## mesh, so the mesh is split into its connected parts (triangles that share
## a corner), each a closed box tested on its own. The floor mat (a part no
## higher than 2 cm) is left out.
func _booth(node: Node3D) -> Array:
	var to_booth := node.global_transform.affine_inverse()
	var parts := []
	var side_in := INF
	var mats := 0
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var local := to_booth * mi.global_transform
		for faces: PackedVector3Array in _components(mi.mesh.get_faces()):
			var mesh_box := AABB(faces[0], Vector3.ZERO)
			for v in faces:
				mesh_box = mesh_box.expand(v)
			var box := local * mesh_box
			if box.end.y < 0.02:
				if box.position.x < 0.0 and box.end.x > 0.0:
					mats += 1
					continue
				_invalid("a booth part below 2 cm that is not the centred mat: %s" % box)
			var name := (
				"x%.2f..%.2f,y%.2f..%.2f,z%.2f..%.2f"
				% [box.position.x, box.end.x, box.position.y, box.end.y, box.position.z, box.end.z]
			)
			parts.append([name, box, mi.global_transform.affine_inverse(), faces, mesh_box])
			if box.position.x > 0.0:
				side_in = minf(side_in, box.position.x)
			elif box.end.x < 0.0:
				side_in = minf(side_in, -box.end.x)
	print(
		(
			"BOOTH at=%s parts=%d mats_left_out=%d clear_width_m=%.3f"
			% [node.global_position, parts.size(), mats, side_in * 2.0]
		)
	)
	if mats != 1:
		_invalid("expected one floor mat in the booth, found %d" % mats)
	for part in parts:
		print("BOOTH_PART ", part[0])
	# Which end of the booth (sign of its local z) the passage enters by.
	var entry_sign := 0.0
	for id: int in _sim.layout.scanners:
		var passage: Array = _sim.layout.passages.get(id, [])
		if passage.size() < 2:
			continue
		var inside := to_booth * _sim.grid.cell_to_world(passage[1])
		if absf(inside.x) < 0.6 and absf(inside.z) < 1.2:
			entry_sign = signf((to_booth * _sim.grid.cell_to_world(passage[0])).z)
	print("BOOTH entry_side_z=%+.0f" % entry_sign)
	if entry_sign == 0.0:
		_invalid("the booth at %s has no passage entry" % node.global_position)
	return [node, to_booth, parts, side_in, entry_sign]


## Lane mode: both basic scanners go and a lane (arch on the divider, LEFT
## mirror, facing 0) takes the east one's place, the divider walls under it
## removed, as the security visuals probe builds it.
func _build_lane(build: BuildMode) -> void:
	var grid := build.grid
	for cell in OLD_SCANNERS:
		var old := grid.object_at(cell)
		if old != 0 and not grid.apply(BuildEdit.remove_object(old)).ok:
			_invalid("could not remove the scanner at %s" % cell)
	var lane := SecurityLanes.geometry(ARCH_AT, 0, SecurityLanes.LEFT)
	for x in range(ARCH_AT.x - 2, ARCH_AT.x + 2):
		var cell := Vector2i(x, ARCH_AT.y)
		if grid.has_wall(cell, BuildGrid.Side.NORTH):
			if not grid.apply(BuildEdit.remove_wall(cell, BuildGrid.Side.NORTH)).ok:
				_invalid("could not open the divider at %s" % cell)
	if not grid.apply(BuildEdit.place_object(SecurityLanes.ARCH, ARCH_AT, 0)).ok:
		_invalid("could not place the arch")
	for part in [SecurityLanes.TRAY_TABLE, SecurityLanes.XRAY_BELT, SecurityLanes.PICKUP_TABLE]:
		if not grid.apply(BuildEdit.place_object(part, lane[part], 0)).ok:
			_invalid("could not place %s" % part)
	(build.get_node("BuildView") as BuildView).refresh(grid)
	var arch := grid.object_at(ARCH_AT)
	var lanes := _sim.layout.security_lanes
	print(
		"LANE arch=%d status=%s scanners=%s" % [arch, lanes.status_text(arch), _sim.layout.scanners]
	)
	if not lanes.is_complete(arch) or _sim.layout.scanners.size() != 1:
		_invalid("the lane is not whole or not the only station")


## Triangle soup `faces` split into connected parts: triangles sharing a
## corner (to the millimetre) are one part.
func _components(faces: PackedVector3Array) -> Array:
	var tris := faces.size() / 3
	var parent := PackedInt32Array()
	parent.resize(tris)
	for t in tris:
		parent[t] = t
	var owner_of := {}
	for t in tris:
		for k in 3:
			var key := Vector3i((faces[t * 3 + k] * 1000.0).round())
			if owner_of.has(key):
				var a := _find(parent, t)
				var b := _find(parent, owner_of[key])
				parent[a] = b
			else:
				owner_of[key] = t
	var groups := {}
	for t in tris:
		var r := _find(parent, t)
		if not groups.has(r):
			groups[r] = PackedVector3Array()
		var g: PackedVector3Array = groups[r]
		g.append_array([faces[t * 3], faces[t * 3 + 1], faces[t * 3 + 2]])
		groups[r] = g
	return groups.values()


func _find(parent: PackedInt32Array, t: int) -> int:
	while parent[t] != t:
		t = parent[t]
	return t


## Control: a bag sunk into the middle of a side panel lies inside its meshes,
## so a zero contact count means clear, not blind.
func _control() -> void:
	var booth: Array = _booths[0]
	var node: Node3D = booth[0]
	var best: AABB
	var tallest := 0.0
	for part in booth[2]:
		var box: AABB = part[1]
		if box.position.x > 0.0 and box.size.y > tallest:
			tallest = box.size.y
			best = box
	var at := node.global_transform * best.get_center()
	var sunk := CarryContact.bag_points(Transform3D(Basis.IDENTITY, at - Vector3.UP * 0.1))
	var hits := _contacts(sunk, booth)
	print("CONTROL bag_in_side_panel_points=%d" % hits)
	if hits == 0:
		_invalid("the control bag in a side panel found no contact, so the check is blind")
	# A point just past the side panel's outside, mid-booth at hip height, has
	# the panel between it and the passage: a crossing, though inside nothing.
	var past := PackedVector3Array([node.global_transform * Vector3(best.end.x + 0.01, 1.0, 0.0)])
	var crossed := _through(past, booth)
	print("CONTROL point_past_the_panel_crossings=%d inside=%d" % [crossed, _contacts(past, booth)])
	if crossed == 0:
		_invalid("the control point past the panel found no crossing, so the check is blind")


func _cross() -> void:
	_roles = ROLES.duplicate(true)
	if _lane_mode:
		_roles.append_array(RUNNER_ROLES.duplicate(true))
	var spawns := 0
	var next_send := _clock.tick
	var stop := Time.get_ticks_msec() + RUN_LIMIT_MS
	_clock.ticked.connect(_on_tick)
	while Time.get_ticks_msec() < stop:
		await RenderingServer.frame_post_draw
		# A hold no plate took (the move was not wanted after all) lets go.
		if _hold_frame >= 0 and not _plate_task and Engine.get_process_frames() - _hold_frame > 3:
			_hold_frame = -1
			_clock.set_paused(false)
		_watch_float()
		_lead_plate_scan()
		if not _roles.is_empty() and _clock.tick >= next_send and spawns < MAX_SPAWNS:
			_send()
			spawns += 1
			next_send = _clock.tick + SEND_GAP_TICKS
		# Runners are kept late (the sim's beat may clear it) until cleared.
		for id: int in _runners:
			var runner := _sim.get_passenger(id)
			if runner != null and runner.stage <= Passenger.Stage.SECURITY:
				runner.late = true
		for id in _sim.passenger_ids():
			_check(id)
		for id in _sent:
			var sent := _sim.get_passenger(id)
			if _lane_mode and sent != null and sent.stage == Passenger.Stage.SECURITY:
				var seen: Dictionary = _phases_seen.get_or_add(id, {})
				seen[sent.security_phase] = true
		var plated := _arch_plated if _lane_mode else _plated
		if _roles.is_empty() and _sent.all(_done) and plated and not _plate_task:
			break
	if not _roles.is_empty():
		_invalid("roles never filled after %d spawns: %s" % [spawns, _roles])
	for id in _sent:
		if not _done(id):
			_invalid("passenger %d never cleared security" % id)


## Close plates of the hand-led moves (CarryLead) as they happen anywhere: the
## first move of each LEAD_PLATES key (bag kind and FloatCheck.move_of, hands
## left out) still early in its move, plated at each LEAD_MOMENTS window, and
## one walking plate per bag kind (a passenger with one bag, settled, moving).
func _lead_plate_scan() -> void:
	# The booth's own move plates (MOVE_PLATES) go first.
	if _plate_task or (not _lane_mode and _move_plated.size() < MOVE_PLATES.size()):
		return
	var props := _views.carry_on_props()
	for id in _sim.passenger_ids():
		var body := _views.node_for(id)
		var p := _sim.get_passenger(id)
		if body == null or p == null or not body.is_visible_in_tree():
			continue
		var kinds: Array = props.props_of(id)["kinds"]
		for i in kinds.size():
			var kind_name: String = SecurityLooks.Kind.keys()[kinds[i]]
			var move := FloatCheck.move_of(props, id, i).replace(".R", "").replace(".L", "")
			var key := kind_name + " " + (move if move != "" else "walk")
			if _lead_plated.has(key) or not (key in LEAD_PLATES or key.ends_with(" walk")):
				continue
			if move == "" and (not p.is_moving() or kinds.size() > 1):
				continue
			if move != "" and props.transfer_progress(id, i) > 0.3:
				continue
			_plate_task = true
			_plate_lead.call_deferred(id, i, key)
			return


## On each sim tick, after the views' sync: a bag about to start a move still
## to be plated (PlateSteps.wanted) pauses the clock with no time left over, so
## the move is first drawn at k 0 and its plate steps the clock to each moment.
func _on_tick(_tick: int) -> void:
	if _plate_task or _hold_frame >= 0:
		return
	var props := _views.carry_on_props()
	var lead_open := _lane_mode or _move_plated.size() >= MOVE_PLATES.size()
	for id in _sim.passenger_ids():
		var kinds: Array = props.props_of(id)["kinds"]
		var p := _sim.get_passenger(id)
		for i in kinds.size():
			var move := PlateSteps.pending_move(props, id, i)
			var plated: Array[Dictionary] = [_move_plated, _lead_plated]
			var repacked := p != null and p.incident_resolved
			var near := move != "" and _near_booth(id)
			if PlateSteps.wanted(kinds[i], move, repacked, near, plated, lead_open, LEAD_PLATES):
				_clock.set_paused(true)
				_clock._accumulator = 0.0
				_hold_frame = Engine.get_process_frames()
				return


## The close plates of one hand-led move (or walk) of bag `i` of passenger
## `id`, the paused sim clock stepped to each moment (no window jumped); each
## prints the bag's FLOAT state, the stoop, the walk and SELF_HEAD (a move).
func _plate_lead(id: int, i: int, key: String) -> void:
	var props := _views.carry_on_props()
	var walk := key.ends_with(" walk")
	var moments: Array = [[1.0, 1.0]] if walk else LEAD_MOMENTS
	var move := FloatCheck.move_of(props, id, i)
	var saved := 0
	for m in moments.size():
		var lo: float = moments[m][0]
		var hi: float = moments[m][1]
		_clock.set_paused(true)
		await PlateSteps.step_to(self, _clock, props, id, i, lo, hi)
		await _frames(1)
		var k := props.transfer_progress(id, i)
		var body := _views.node_for(id)
		var bags: Array = props.props_of(id)["bags"] if body != null else []
		if (
			body == null
			or i >= bags.size()
			or FloatCheck.move_of(props, id, i) != move
			or k < lo
			or k > hi
		):
			print("LEAD_PLATE %s passenger=%d moment=%d missed k=%.2f" % [key, id, m, k])
			_clock.set_paused(false)
			break
		var state := FloatCheck.float_state(_sim, _views, id, i)
		_failed = (not walk and PlateSteps.head_in_bag(body, bags[i], key, k) > 0) or _failed
		var rig: Dictionary = body.get_meta(&"carry_rig", {})
		var stoop: float = (rig["stoop"] as CarryStoop).drawn if rig.has("stoop") else -1.0
		var slug := key.replace(" ", "_").replace(">", "-to-")
		var name := "lead_%s_%d_k%03d" % [slug, m, roundi(k * 100.0)]
		print(
			(
				(
					"LEAD_PLATE %s passenger=%d bag=%d moment=%d k=%.2f state=%s hand_gap_m=%.3f"
					+ " stoop=%.2f walking=%s file=%s.png"
				)
				% [
					key,
					id,
					i,
					m,
					k,
					state[0],
					state[1],
					stoop,
					_sim.get_passenger(id).is_moving(),
					name
				]
			)
		)
		var ok := await _plate_close(id, bags[i], name)
		_clock.set_paused(false)
		if not ok:
			break
		saved += 1
	if saved == moments.size():
		_lead_plated[key] = true
	_clock.set_paused(false)
	_hold_frame = -1
	_plate_task = false


## One frame of the FLOAT check, and its control on the first drawn bag.
func _watch_float() -> void:
	FloatCheck.watch_float(_sim, _views, _floats)
	if not _float_control.is_empty():
		return
	for id in _sim.passenger_ids():
		var bags: Array = _views.carry_on_props().props_of(id)["bags"]
		if _float_control.is_empty() and not bags.is_empty() and bags[0].is_visible_in_tree():
			_float_control = FloatCheck.float_control(_sim, _views, id)


func _done(id: int) -> bool:
	var p := _sim.get_passenger(id)
	if not _stats.has(id):
		return false
	if p == null:
		return true
	return p.stage > Passenger.Stage.SECURITY and not _near_booth(id)


## Whether passenger `id` is drawn near a booth (NEAR, the checked box).
func _near_booth(id: int) -> bool:
	var body := _views.node_for(id)
	if body == null or not body.is_visible_in_tree():
		return false
	for booth in _booths:
		var local: Vector3 = (booth[1] as Transform3D) * body.global_position
		if absf(local.x) <= NEAR.x and absf(local.z) <= NEAR.z:
			return true
	return false


func _send() -> void:
	var id := _sim.spawn_now(StarterFlight.first_flight())
	var p := _sim.get_passenger(id)
	var kind := SecurityLooks.bag_kind(p, 0)
	var at := _roles.find_custom(func(r: Array) -> bool: return r[0] == kind)
	if at < 0:
		at = _roles.find_custom(func(r: Array) -> bool: return r[0] == -1)
	if at < 0:
		return
	var traits: Array = _roles.pop_at(at)
	p.carry_on = traits[1]
	p.liquids = traits[2]
	p.alarm = traits[3]
	p.hunger = 0
	p.apron = []
	p.apron_mm = 0
	p.stage = Passenger.Stage.TO_SECURITY
	p.clear_path()
	_sent.append(id)
	_role_of[id] = traits
	if traits.size() > 4 and traits[4]:
		_runners[id] = true
		p.late = true
	print("SEND passenger=%d kinds=%s role=%s" % [id, [kind, SecurityLooks.bag_kind(p, 1)], traits])


## One frame of passenger `id` against every booth it is near.
func _check(id: int) -> void:
	var body := _views.node_for(id)
	if body == null or not body.is_visible_in_tree():
		return
	for booth in _booths:
		var local: Vector3 = (booth[1] as Transform3D) * body.global_position
		if absf(local.x) > NEAR.x or absf(local.z) > NEAR.z:
			continue
		var p := _sim.get_passenger(id)
		var owned := CarryContact.body_points_owned(body, [])
		var points: PackedVector3Array = owned[0]
		var bag_points := PackedVector3Array()
		var carried_points := PackedVector3Array()
		var props: Dictionary = _views.carry_on_props().props_of(id)
		var bags: Array[Node3D] = props["bags"]
		var homes := SecurityLooks.bag_homes(_sim, p)
		var hand_kinds := []
		var own := CarryContact.body_points(body, CarryChecks.gripping(_sim, p))
		var self_hits := 0
		var reported := {"case_turn": 0}
		var props_now := _views.carry_on_props()
		var front_now := props_now.front_weight_of(id)
		var outside := absf(local.z) > 0.95
		var moves := _track_moves(id, p, homes, props, props_now)
		for i: int in moves:
			if moves[i] in MOVE_PLATES and not _move_plated.has(moves[i]) and not _plate_task:
				_plate_task = true
				_plate_move.call_deferred(id, i, moves[i])
		for i in bags.size():
			var at_lane := not SecurityLooks.lane_of(_sim, p).is_empty()
			if homes[i] == SecurityLooks.Home.TRAY and p.station != 0 and not at_lane:
				_invalid("passenger %d has a tray bag at a basic scanner" % id)
			if bags[i].is_visible_in_tree():
				var surface := CarryChecks.surface(bags[i])
				bag_points.append_array(surface)
				# A bag in a tray rides the belt beside an arch, not the passage.
				if homes[i] != SecurityLooks.Home.TRAY or not _lane_mode:
					carried_points.append_array(surface)
				if homes[i] == SecurityLooks.Home.HAND:
					hand_kinds.append(props["kinds"][i])
					var hits := CarryContact.inside_meshes(own, bags[i])
					var why := ""
					if hits > 0:
						_print_self_detail(id, i, body, own, local.z)
						why = _ruled_self_clip(
							p, props["kinds"][i], outside, signf(local.z) == booth[4], front_now
						)
					if why == "":
						self_hits += hits
					else:
						reported[why] += hits
						print(
							(
								"SELF_REPORTED passenger=%d bag=%d predicate=%s move=%s points=%d along=%.2f front=%.2f"
								% [id, i, why, moves.get(i, "none"), hits, local.z, front_now]
							)
						)
					if hits > 0 and not _self_bones.has(id):
						var grip := CarryChecks.gripping(_sim, p)
						_self_bones[id] = CarryChecks.contact_bones(body, grip, bags[i])
						print(
							(
								"SELF passenger=%d bones=%s along_m=%.2f stage=%d phase=%d moving=%s front=%.2f"
								% [
									id,
									_self_bones[id],
									local.z,
									p.stage,
									p.security_phase,
									p.is_moving(),
									_views.carry_on_props().front_weight_of(id)
								]
							)
						)
		var s: Dictionary = _stats.get(id, {})
		if s.is_empty():
			s = {
				"frames": 0,
				"mid": 0,
				"self_contacts": 0,
				"turn_points": 0,
				"turn_frames": 0,
				"turn_along": [],
				"through": 0,
				"mid_reach": 0.0,
				"mid_bone": "",
				"body_contacts": 0,
				"bag_contacts": 0,
				"body_gap": INF,
				"bag_gap": INF,
				"head_gap": INF,
				"reach": 0.0,
				"bag_reach": 0.0,
				"parts": {},
				"kinds": props["kinds"],
				"phases": {},
				"sent": _sent.has(id),
			}
			_stats[id] = s
		s["frames"] += 1
		# Only the ruled clip is printed instead of failed
		# (_ruled_self_clip); every other body-in-bag point fails.
		if reported["case_turn"] > 0:
			s["turn_points"] += reported["case_turn"]
			s["turn_frames"] += 1
			s["turn_along"].append(snappedf(absf(local.z), 0.01))
		s["self_contacts"] += self_hits
		var pose := [body.global_transform, self_hits, bags.map(func(b): return b.global_transform)]
		if self_hits > 0 and _self_seen.get(id, []) != pose:
			_self_distinct += self_hits
		_self_seen[id] = pose
		if self_hits > 0:
			print(
				(
					"SELF_FAIL passenger=%d points=%d along_m=%.2f front=%.2f kinds=%s stage=%d"
					% [id, self_hits, local.z, front_now, props["kinds"], p.stage]
				)
			)
		s["phases"][p.security_phase] = true
		s["body_contacts"] += _contacts(points, booth, s["parts"])
		if absf(local.x) < 0.3 and absf(local.z) < 1.2:
			s["through"] += _through(points, booth) + _through(carried_points, booth)
		var bag_hits := _contacts(bag_points, booth, s["parts"])
		s["bag_contacts"] += bag_hits
		if bag_hits > 0:
			print(
				(
					(
						"BAG_CONTACT_DETAIL passenger=%d points=%d along=%.2f across=%.2f"
						+ " turn=%.2f arm=%.2f stage=%d moving=%s"
					)
					% [
						id,
						bag_hits,
						local.z,
						local.x,
						props_now.bag_turn_of(id),
						front_now,
						p.stage,
						p.is_moving()
					]
				)
			)
		var gaps := _gaps(points, booth)
		var bag_gaps := _gaps(bag_points, booth)
		s["body_gap"] = minf(s["body_gap"], gaps.x)
		s["head_gap"] = minf(s["head_gap"], gaps.y)
		s["reach"] = maxf(s["reach"], gaps.z)
		s["bag_gap"] = minf(s["bag_gap"], bag_gaps.x)
		s["bag_reach"] = maxf(s["bag_reach"], bag_gaps.z)
		var inside := absf(local.z) < 0.6 and absf(local.x) < 0.3
		if inside:
			s["mid"] += 1
			for k in points.size():
				var x := absf(((booth[1] as Transform3D) * points[k]).x)
				if x > s["mid_reach"]:
					s["mid_reach"] = x
					s["mid_bone"] = (owned[1] as PackedStringArray)[k]
			for k in hand_kinds:
				_kinds_crossed[KIND_NAMES[k]] = true
		var arch := StringName((booth[0] as Node3D).get_meta("record", {}).get("def", ""))
		if arch == SecurityLanes.ARCH:
			_arch_crossing(id, p, s, local, props_now)
		elif (
			not _plated
			and not _plate_task
			and inside
			and absf(local.z) < 0.2
			and props["kinds"].has(SecurityLooks.Kind.CASE)
		):
			_plated = true
			_plate_task = true
			_plate_crossing.call_deferred(id, booth)


## Lane mode, one frame of passenger `id` at the arch (`local`, its place in
## the arch's frame): within the posts' depth it records its lowest tuck
## weight and whether it ran (on which pass, measured from its walked distance
## per tick); mid-arch, fully tucked and
## with no plate task under way, it is plated close once.
func _arch_crossing(
	id: int, p: Passenger, s: Dictionary, local: Vector3, props_now: CarryOnProps
) -> void:
	if absf(local.x) > 0.3 or absf(local.z) > 0.3:
		return
	var tuck := props_now.tuck_of(id)
	var key := "arch_second" if p.incident_resolved else "arch_first"
	if not s.has(key):
		s[key] = {
			"tuck_min": INF,
			"frames": 0,
			"run_frames": 0,
			"odo": p.odometer_mm,
			"tick": _clock.tick,
		}
		if p.incident_resolved:
			_arch_second += 1
	var run: Dictionary = s[key]
	run["tuck_min"] = minf(run["tuck_min"], tuck)
	run["frames"] += 1
	# Running is measured, not read off the flag: the walked distance per
	# tick since the last tick seen here, near PassengerSim.RUN_MM.
	var ticks: int = _clock.tick - int(run["tick"])
	if ticks > 0:
		var per_tick := float(p.odometer_mm - int(run["odo"])) / ticks
		if per_tick > (PassengerSim.WALK_MM + PassengerSim.RUN_MM) * 0.5:
			run["run_frames"] += 1
			_arch_runners[id] = true
		run["odo"] = p.odometer_mm
		run["tick"] = _clock.tick
	if not _arch_plated and not _plate_task and absf(local.z) < 0.15 and tuck >= 1.0:
		_plate_task = true
		_plate_arch.call_deferred(id)


## Prints one body-in-own-bag frame of bag `i` of passenger `id` (points
## `own` of its drawn body, `along` the booth): the bag's kind, carry, move and
## turn, the arm's front weight, the grip and the contact points in the body's
## frame, so a clip can be told apart by move without another run.
func _print_self_detail(
	id: int, i: int, body: Node3D, own: PackedVector3Array, along: float
) -> void:
	var p := _sim.get_passenger(id)
	var props_now := _views.carry_on_props()
	var props := props_now.props_of(id)
	var bag: Node3D = props["bags"][i]
	var to_body := body.global_transform.affine_inverse()
	var grip := to_body * props_now.grip_of(body, SecurityLooks.hand_of(_sim, p, i))
	print(
		(
			(
				"SELF_DETAIL passenger=%d bag=%d kind=%d carry=%d k=%.2f turn=%.2f arm=%.2f"
				+ " grip=%s moving=%s along=%.2f stage=%d bones=%s at=%s move=%s held_by=%s bag_at=%s"
			)
			% [
				id,
				i,
				props["kinds"][i],
				props["carries"][i],
				props_now.transfer_progress(id, i),
				props_now.bag_turn_of(id),
				props_now.front_weight_of(id),
				grip.snapped(Vector3.ONE * 0.01),
				p.is_moving(),
				along,
				p.stage,
				CarryChecks.contact_bones(body, CarryChecks.gripping(_sim, p), bag),
				_where_inside(to_body, own, bag),
				FloatCheck.move_of(props_now, id, i),
				["held_by", "led", "swap"].map(
					func(key): return props_now.bag_state(id, i).get(key)
				),
				_where_inside(bag.global_transform.affine_inverse(), own, bag)
			]
		)
	)


## Diagnostic: up to four body points inside `bag`, through `to_body` (a frame).
func _where_inside(to_body: Transform3D, own: PackedVector3Array, bag: Node3D) -> Array:
	var out := []
	for mi: MeshInstance3D in bag.find_children("*", "MeshInstance3D", true, false):
		var to_mesh := mi.global_transform.affine_inverse()
		var faces := mi.mesh.get_faces()
		for pt in own:
			var lp: Vector3 = to_mesh * pt
			if mi.get_aabb().grow(0.001).has_point(lp) and CarryContact._odd(lp, faces):
				if out.size() < 4:
					out.append((to_body * pt).snapped(Vector3.ONE * 0.01))
	return out


## Which ruled clip a body-in-own-bag contact is, or "" when it is none (it
## fails). Only one, outside the booth's length (`outside`): case_turn
## (accepted by the user 2026-10-29, "Accept, merge now"), a hard case turning
## from the side to the front (the front carry is the target and its weight is
## part way), on the approach end of the booth (`approach`). A roller's lift
## or lowering and a pickup after a repack are not exempt (fixed 2026-10-29,
## board item pre-existing-carry-self-clips-found-by-game-spike-basic-scan).
func _ruled_self_clip(
	p: Passenger, kind: SecurityLooks.Kind, outside: bool, approach: bool, front: float
) -> String:
	if not outside:
		return ""
	var to_front := SecurityLooks.carry_front(_sim, p)
	if kind == SecurityLooks.Kind.CASE and approach and to_front and front > 0.0 and front < 1.0:
		return "case_turn"
	return ""


## Records, for each bag of passenger `id`, the kind of move it begins on this
## check (its [home, carry] differs from the last check) and keeps it until the
## transfer has finished (CarryOnProps.transfer_progress reaches 1), when it
## counts in _moves_done: the run's proof that each repaired move was checked
## whole. A move that began while the passenger was not checked has no kind.
## Returns the bag index -> kind of the moves under way.
func _track_moves(
	id: int, p: Passenger, homes: Array, props: Dictionary, carry_props: CarryOnProps
) -> Dictionary:
	var frame := Engine.get_process_frames()
	if _tracked_frame.get(id, -10) == frame:
		return _bag_moves.get(id, {})
	if frame - int(_tracked_frame.get(id, -10)) > 1:
		_last_bag_state.erase(id)
		_bag_moves.erase(id)
	_tracked_frame[id] = frame
	var was: Array = _last_bag_state.get(id, [])
	var moves: Dictionary = _bag_moves.get(id, {})
	var now: Array = []
	for i in homes.size():
		var carries: Array = props["carries"]
		var state := [homes[i], carries[i] if i < carries.size() else -1]
		now.append(state)
		if i < was.size() and was[i] != state:
			var kind := "other"
			var roller: bool = (
				i < props["kinds"].size() and props["kinds"][i] == SecurityLooks.Kind.ROLLER
			)
			if (
				was[i][0] == SecurityLooks.Home.FLOOR
				and state[0] == SecurityLooks.Home.HAND
				and p.incident_resolved
			):
				kind = "repack_pickup_" + KIND_NAMES[props["kinds"][i]]
			elif (
				roller
				and was[i][1] == SecurityLooks.Carry.PULL
				and state[1] == SecurityLooks.Carry.HAND
			):
				kind = "roller_lift"
			elif (
				roller
				and was[i][1] == SecurityLooks.Carry.HAND
				and state[1] == SecurityLooks.Carry.PULL
			):
				kind = "roller_lower"
			moves[i] = kind
		if moves.has(i) and carry_props.transfer_progress(id, i) >= 1.0:
			_moves_done[moves[i]] = int(_moves_done.get(moves[i], 0)) + 1
			moves.erase(i)
	_last_bag_state[id] = now
	_bag_moves[id] = moves
	return moves


## Points of a passenger in the passage that lie past the passage edge with a
## booth part between them and the passage: the straight line from each point
## in to the edge (at its height and depth) crosses a part's mesh. This finds a
## body or bag through a part thinner than the points are apart, which the
## containment count can miss; a point under a rail, past the edge but with
## nothing in between, is not one.
func _through(points: PackedVector3Array, booth: Array) -> int:
	var count := 0
	var edge: float = booth[3] - 0.002
	var to_world: Transform3D = (booth[1] as Transform3D).affine_inverse()
	for pt in points:
		var lp: Vector3 = (booth[1] as Transform3D) * pt
		if absf(lp.x) <= edge or absf(lp.z) > 0.95:
			continue
		var inner := to_world * Vector3(signf(lp.x) * edge, lp.y, lp.z)
		for part in booth[2]:
			var to_mesh: Transform3D = part[2]
			var a: Vector3 = to_mesh * pt
			var b: Vector3 = to_mesh * inner
			var faces: PackedVector3Array = part[3]
			var hit := false
			for i in range(0, faces.size() - 2, 3):
				if (
					Geometry3D.segment_intersects_triangle(
						a, b, faces[i], faces[i + 1], faces[i + 2]
					)
					!= null
				):
					hit = true
					break
			if hit:
				count += 1
				break
	return count


## Points inside a booth mesh, counted per part into `parts` when given.
func _contacts(points: PackedVector3Array, booth: Array, parts := {}) -> int:
	var count := 0
	for pt in points:
		for part in booth[2]:
			var lp: Vector3 = (part[2] as Transform3D) * pt
			var faces: PackedVector3Array = part[3]
			if not (part[4] as AABB).grow(0.001).has_point(lp):
				continue
			if _odd(lp, faces):
				count += 1
				parts[part[0]] = parts.get(part[0], 0) + 1
				break
	return count


## x: the smallest side gap of `points` to a part beside them at their height
## and depth; y: the smallest gap up to a part above them; z: the widest
## reach from the centre line among points within the booth's length.
func _gaps(points: PackedVector3Array, booth: Array) -> Vector3:
	var side := INF
	var up := INF
	var reach := 0.0
	for pt in points:
		var lp: Vector3 = (booth[1] as Transform3D) * pt
		if absf(lp.z) <= 0.95:
			reach = maxf(reach, absf(lp.x))
		for part in booth[2]:
			var box: AABB = part[1]
			if lp.z < box.position.z or lp.z > box.end.z:
				continue
			if box.position.x > 0.0 or box.end.x < 0.0:
				if lp.y < box.position.y or lp.y > box.end.y:
					continue
				var gap := box.position.x - lp.x if box.position.x > 0.0 else lp.x - box.end.x
				side = minf(side, gap)
			elif lp.x >= box.position.x and lp.x <= box.end.x:
				up = minf(up, box.position.y - lp.y)
	return Vector3(side, up, reach)


func _odd(p: Vector3, faces: PackedVector3Array) -> bool:
	var crossings := 0
	for i in range(0, faces.size() - 2, 3):
		if Geometry3D.ray_intersects_triangle(p, RAY, faces[i], faces[i + 1], faces[i + 2]) != null:
			crossings += 1
	return crossings % 2 == 1


## Plates of passenger `id` crossing `booth`: mid-booth now, then as it
## leaves past the booth's back. Each plate keeps the first of four headings
## where the passenger is in frame and unblocked.
func _plate_crossing(id: int, booth: Array) -> void:
	_plate_task = true
	await _plate_both(id, booth)
	_plate_task = false


func _plate_both(id: int, booth: Array) -> void:
	if not await _plate_best(id, booth, "booth_crossing_0_mid"):
		_invalid("crossing plate: passenger %d not shown mid-booth from any heading" % id)
		return
	var stop := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < stop:
		await process_frame
		var body := _views.node_for(id)
		if body == null:
			break
		var local: Vector3 = (booth[1] as Transform3D) * body.global_position
		if absf(local.z) > 0.8:
			if not await _plate_best(id, booth, "booth_crossing_1_leaving"):
				_invalid("crossing plate: passenger %d not shown leaving" % id)
			return
	_invalid("crossing plate: passenger %d never left the booth" % id)


func _plate_best(id: int, booth: Array, name: String) -> bool:
	var node: Node3D = booth[0]
	var owners: Array[Node] = [_main.get_node("Airside/Terminal"), _main.get_node("BuildMode")]
	# Facing the walker first, so its front-carried bag and hands show.
	for yaw in [0.5 + PI, 0.5 + PI / 2.0, 0.5, 0.5 - PI / 2.0]:
		_rig.stop_follow()
		_rig.position = Vector3(node.global_position.x, 0.0, node.global_position.z)
		_rig.yaw = yaw
		_rig.distance = 4.5
		var holder := PlateSight.colliders(root, owners, {})
		PlateSteps.see_both_sides(holder)
		await physics_frame
		await physics_frame
		await _frames(2)
		var body := _views.node_for(id)
		var ok := body != null and _shown(body, "%s yaw %.2f" % [name, yaw])
		ok = ok and _bags_in_frame(id, name)
		if ok:
			var along := ((booth[1] as Transform3D) * body.global_position).z
			var placed := absf(along) < 0.6 if name.ends_with("mid") else absf(along) > 0.8
			print("INFRAME %s along_booth_m=%.2f placed=%s" % [name, along, placed])
			ok = placed
		var img := root.get_texture().get_image()
		holder.free()
		var dark := PlateSteps.dark_share(img)
		print("INFRAME %s yaw %.2f dark=%.2f" % [name, yaw, dark])
		ok = ok and dark < PlateSteps.DARK_SHARE
		if ok:
			_save(img, name)
			_plates_saved += 1
			return true
	return false


## Close plates of bag `i` of passenger `id` in a `kind` move: at each of
## MOMENTS, once its progress is in the window, the sim clock is paused, the
## progress read again and _plate_close() run; the clock runs on in between.
## All three saved marks the kind plated; a missed window or a plate with no
## good heading leaves it for the next such move.
func _plate_move(id: int, i: int, kind: String) -> void:
	var props := _views.carry_on_props()
	var saved := 0
	# The move's [home, carry] when it began: a change before the last plate
	# is another move, not this one.
	var began: Array = (_last_bag_state.get(id, []) as Array).duplicate(true)
	# A transfer started again (a change of hand keeps [home, carry]) shows as
	# its progress going back.
	var last_k := props.transfer_progress(id, i)
	var restarted := false
	print(
		(
			"MOVE_PLATE %s passenger=%d bag=%d starts at k=%.2f tick=%d"
			% [kind, id, i, props.transfer_progress(id, i), _clock.tick]
		)
	)
	for m in MOMENTS.size():
		var lo: float = MOMENTS[m][0]
		var hi: float = MOMENTS[m][1]
		# The clock is held and stepped to the moment, so no window is jumped.
		_clock.set_paused(true)
		await PlateSteps.step_to(self, _clock, props, id, i, lo, hi)
		await _frames(1)
		var k := props.transfer_progress(id, i)
		var bags: Array = props.props_of(id)["bags"]
		var now_state: Array = _last_bag_state.get(id, [])
		var same: bool = i < began.size() and i < now_state.size() and now_state[i] == began[i]
		same = same and (k >= 1.0 or (_bag_moves.get(id, {}) as Dictionary).get(i, "") == kind)
		restarted = restarted or k < last_k
		last_k = k
		same = same and not restarted
		if k < lo or k > hi or not same or i >= bags.size():
			print("MOVE_PLATE %s passenger=%d moment=%d missed k=%.2f" % [kind, id, m, k])
			_clock.set_paused(false)
			break
		var name := "%s_%d_k%03d" % [kind, m, roundi(k * 100.0)]
		var ok := await _plate_close(id, bags[i], name)
		_clock.set_paused(false)
		if not ok:
			break
		saved += 1
	if saved == MOMENTS.size():
		_move_plated[kind] = true
	_clock.set_paused(false)
	_hold_frame = -1
	_plate_task = false


## Lane mode: a close plate of passenger `id` mid-arch with its arms tucked,
## the sim clock paused for it.
func _plate_arch(id: int) -> void:
	_clock.set_paused(true)
	await _frames(1)
	var tuck := _views.carry_on_props().tuck_of(id)
	var late := _sim.get_passenger(id).late
	print("ARCH_PLATE passenger=%d tuck=%.2f late=%s" % [id, tuck, late])
	if tuck >= 1.0 and await _plate_close(id, null, "arch_tucked_mid"):
		_arch_plated = true
	_clock.set_paused(false)
	_plate_task = false


## A close plate of passenger `id` (and `bag`, when given) saved to the close
## plates folder as `name`: a camera of the probe's own CLOSE_M out and
## CLOSE_HEIGHT_M high, aimed at the body AIM_M over the floor (higher and
## further back for a bag over the head), tries eight
## headings round the body (facing it first) with the HUD hidden. A heading is
## kept only when the body's and the bag's drawn bounds project inside the
## viewport by MARGIN_PX, the body is CLOSE_MIN_PX tall or more, the body is
## shown (PlateSight.person_shown(): sight lines land on it, none blocked),
## and at least two of five sight lines to the bag land on it with none
## blocked by anything but the passenger itself. Each heading prints its
## numbers. The camera, the HUD and the game camera are put back.
func _plate_close(id: int, bag: Node3D, name: String) -> bool:
	var body := _views.node_for(id)
	if body == null:
		return false
	var layers: Array[CanvasLayer] = []
	for node in _main.find_children("*", "CanvasLayer", true, false):
		var layer := node as CanvasLayer
		if layer.visible:
			layer.visible = false
			layers.append(layer)
	var cam := Camera3D.new()
	cam.fov = 50.0
	root.add_child(cam)
	cam.make_current()
	# Every drawn thing that can stand in the way: the building, the built
	# objects, passengers and their bags, staff and baggage.
	var owners: Array[Node] = [_views]
	for path in ["Airside/Terminal", "BuildMode", "StaffCharacters", "BaggageViews"]:
		owners.append(_main.get_node(path))
	var frame := Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)
	var saved := false
	# A bag up over the head (a roller on the overhead route) is framed too:
	# the aim rises to the middle of floor to bag top, the camera backs off.
	var top := 2.0
	if bag != null:
		for mi: MeshInstance3D in bag.find_children("*", "MeshInstance3D", true, false):
			top = maxf(top, (mi.global_transform * mi.get_aabb()).end.y)
	var aim := maxf(AIM_M, top * 0.5)
	var back := CLOSE_M * maxf(1.0, (top + 0.3) / 2.3)
	for h in 8:
		var look := body.global_position + Vector3(0.0, aim, 0.0)
		var yaw := body.global_rotation.y + h * PI / 4.0
		var out := Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, back)
		var up := Vector3(0.0, CLOSE_HEIGHT_M - AIM_M + aim, 0.0)
		cam.global_position = body.global_position + out + up
		cam.look_at(look)
		await _frames(2)
		var img := root.get_texture().get_image()
		var subjects := {body: "subject"}
		if bag != null:
			subjects[bag] = "bag"
		var holder := PlateSight.colliders(root, owners, subjects)
		# A mesh the camera is inside, or behind its one-sided face, blocks too.
		PlateSteps.see_both_sides(holder)
		await physics_frame
		await physics_frame
		var bounds: Dictionary = holder.get_meta("bounds")
		var tag := "%s heading %d" % [name, h]
		var ok := (holder.get_meta("unbaked") as Array).is_empty()
		ok = ok and bounds.has("subject") and (bag == null or bounds.has("bag"))
		if ok:
			ok = _box_in_frame(cam, bounds["subject"], frame, tag + " body")
			if bag != null:
				ok = _box_in_frame(cam, bounds["bag"], frame, tag + " bag") and ok
			var shown := PlateSight.person_shown(
				cam, bounds["subject"], "subject", frame, img, img, CLOSE_MIN_PX
			)
			print("INFRAME %s person=%s" % [tag, shown])
			ok = ok and shown["ok"]
			if bag != null:
				ok = _bag_seen(cam, bounds["bag"], tag) and ok
			var dark := PlateSteps.dark_share(img)
			print("INFRAME %s dark=%.2f" % [tag, dark])
			ok = ok and dark < PlateSteps.DARK_SHARE
		else:
			print("INFRAME %s no bounds or unbaked: %s" % [tag, holder.get_meta("unbaked")])
		holder.free()
		if ok:
			var path := _close_dir.path_join(name + ".png")
			if img.save_png(path) != OK:
				_invalid("could not save %s" % path)
			else:
				print("PLATE saved %s size=%s" % [path, img.get_size()])
				saved = true
				# The bag close up from the same side, for the hand and the legs.
				if bag != null:
					var detail := _close_dir.path_join(name + "_detail.png")
					await PlateSteps.detail_plate(self, cam, body, bag, owners, frame, detail)
			break
	_cam.make_current()
	cam.queue_free()
	for layer in layers:
		layer.visible = true
	await _frames(1)
	return saved


## Whether the corners of `box` all project inside `frame`, in front of `cam`.
func _box_in_frame(cam: Camera3D, box: AABB, frame: Rect2, tag: String) -> bool:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var ok := true
	for c in 8:
		var corner := box.get_endpoint(c)
		ok = ok and not cam.is_position_behind(corner)
		var px := cam.unproject_position(corner)
		lo = lo.min(px)
		hi = hi.max(px)
	ok = ok and frame.has_point(lo) and frame.has_point(hi)
	print("INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) ok=%s" % [tag, lo.x, lo.y, hi.x, hi.y, ok])
	return ok


## Whether at least two of five sight lines from `cam` to `box` (its centre
## and four points 30% out across and up) first hit the bag, and none first
## hits anything but the bag or its own passenger before reaching it.
func _bag_seen(cam: Camera3D, box: AABB, tag: String) -> bool:
	var space := cam.get_world_3d().direct_space_state
	var right := cam.global_transform.basis.x
	var up := cam.global_transform.basis.y
	var centre := box.get_center()
	var reach := box.size.length() * 0.3
	var on := 0
	var blocked: Array[String] = []
	for off in [Vector3.ZERO, right * reach, -right * reach, up * reach, -up * reach]:
		var at: Vector3 = centre + off * 0.5
		var to := at + (at - cam.global_position).normalized() * 3.0
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(cam.global_position, to))
		if hit.is_empty():
			continue
		var what := str((hit.collider as Node).get_meta("subject", ""))
		var before := cam.global_position.distance_to(at) - 0.05
		if what == "bag":
			on += 1
		elif what != "subject" and cam.global_position.distance_to(hit.position) < before:
			blocked.append(str((hit.collider as Node).get_meta("mesh", "")))
	print("INFRAME %s bag_lines_on=%d/5 blocked=%s" % [tag, on, blocked])
	return on >= 2 and blocked.is_empty()


## Whether every visible bag of `id` projects inside the frame, in front of
## the camera.
func _bags_in_frame(id: int, tag: String) -> bool:
	var frame := Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)
	var props := _views.carry_on_props().props_of(id)
	var bags: Array[Node3D] = props["bags"]
	var shown := 0
	for i in bags.size():
		var bag := bags[i]
		if not bag.is_visible_in_tree():
			continue
		var at := bag.global_position
		if _cam.is_position_behind(at) or not frame.has_point(_cam.unproject_position(at)):
			print("INFRAME %s bag at %s is out of frame" % [tag, at])
			return false
		# Nothing built (a chair, a rail, a wall) before the bag's middle.
		var mid := bag.global_transform * CarryOnProps.bag_box(props["kinds"][i]).get_center()
		if PlateSteps.blocked(_cam, mid, tag):
			return false
		shown += 1
	print("INFRAME %s bags_in_frame=%d" % [tag, shown])
	return shown > 0


func _shown(body: Node3D, tag: String) -> bool:
	var frame := Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)
	var base := body.global_position
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for h in [0.0, 1.0, 1.9]:
		var s := _cam.unproject_position(base + Vector3(0.0, h, 0.0))
		lo = lo.min(s)
		hi = hi.max(s)
	var in_frame := frame.has_point(lo) and frame.has_point(hi)
	var clear := 0
	var space := _cam.get_world_3d().direct_space_state
	for h in [1.0, 1.4, 1.7]:
		var hit := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(_cam.global_position, base + Vector3(0.0, h, 0.0))
		)
		clear += int(hit.is_empty())
	# Every line clear: a near occluder over the legs blocks one line only.
	var ok := in_frame and clear == 3 and hi.y - lo.y >= MIN_SUBJECT_PX
	print(
		(
			"INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) unblocked_lines=%d/3 ok=%s"
			% [tag, lo.x, lo.y, hi.x, hi.y, clear, ok]
		)
	)
	return ok


func _save(img: Image, name: String) -> void:
	var path := _out_dir.path_join(name + ".png")
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _report() -> void:
	var totals := {
		"body": 0,
		"bag": 0,
		"frames": 0,
		"self": 0,
		"through": 0,
		"turn_points": 0,
		"turn_frames": 0,
	}
	var turn_along: Array = []
	var worst := Vector4(INF, INF, INF, 0.0)
	for id in _stats:
		var s: Dictionary = _stats[id]
		totals["body"] += s["body_contacts"]
		totals["bag"] += s["bag_contacts"]
		totals["frames"] += s["frames"]
		totals["self"] += s["self_contacts"]
		totals["turn_points"] += s["turn_points"]
		totals["turn_frames"] += s["turn_frames"]
		turn_along.append_array(s["turn_along"])
		totals["through"] += s["through"]
		worst = Vector4(
			minf(worst.x, s["body_gap"]),
			minf(worst.y, s["bag_gap"]),
			minf(worst.z, s["head_gap"]),
			maxf(worst.w, s["bag_reach"])
		)
		print(
			(
				(
					"CROSSING passenger=%d sent=%s kinds=%s frames=%d mid=%d phases=%s body_contacts=%d"
					+ " bag_contacts=%d parts=%s body_gap_m=%.3f bag_gap_m=%.3f head_gap_m=%.3f"
					+ " body_reach_m=%.3f bag_reach_m=%.3f mid_reach_m=%.3f mid_bone=%s"
					+ " body_in_own_bag=%d through_parts=%d"
				)
				% [
					id,
					s["sent"],
					s["kinds"],
					s["frames"],
					s["mid"],
					s["phases"].keys(),
					s["body_contacts"],
					s["bag_contacts"],
					s["parts"],
					s["body_gap"],
					s["bag_gap"],
					s["head_gap"],
					s["reach"],
					s["bag_reach"],
					s["mid_reach"],
					s["mid_bone"],
					s["self_contacts"],
					s["through"],
				]
			)
		)
	print(
		(
			(
				"BOOTH_TOTAL passengers=%d frames=%d body_contacts=%d bag_contacts=%d"
				+ " min_body_gap_m=%.3f min_bag_gap_m=%.3f min_head_gap_m=%.3f"
				+ " max_bag_reach_m=%.3f kinds_crossed=%s"
			)
			% [
				_stats.size(),
				totals["frames"],
				totals["body"],
				totals["bag"],
				worst.x,
				worst.y,
				worst.z,
				worst.w,
				_kinds_crossed.keys()
			]
		)
	)
	if _lane_mode:
		_report_lane()
	else:
		_report_booth()
	if totals["frames"] < 100:
		_invalid("only %d passenger frames near a booth" % totals["frames"])
	print(
		(
			"BODY_IN_OWN_BAG failing=%d THROUGH_PARTS=%d distinct_poses=%d"
			% [totals["self"], totals["through"], _self_distinct]
		)
	)
	print(
		(
			"CASE_TURN_IN_OWN_BAG points=%d frames=%d distance_from_booth_centre_m=%s (reported, accepted)"
			% [totals["turn_points"], totals["turn_frames"], turn_along]
		)
	)
	print(FloatCheck.float_report(_floats))
	print("LEAD_PLATED %s" % [_lead_plated.keys()])
	PlateSteps.lead_sheet(_close_dir)
	if _floats["float"] > 0:
		_invalid("a carry-on bag floats (neither held, worn nor resting): %d" % _floats["float"])
	if _float_control != ["float", "held"] and _float_control != ["float", "resting"]:
		_invalid("the FLOAT control was not caught or not let go: %s" % [_float_control])
	if _floats["held"] == 0 or _floats["resting"] == 0:
		_invalid("the FLOAT check saw no held or no resting bag (control)")
	if totals["self"] > 0:
		_invalid("a body point lies inside its own carried bag: %d" % totals["self"])
	if totals["through"] > 0:
		_invalid("a body or bag point lies past a booth part: %d" % totals["through"])
	if totals["body"] > 0 or totals["bag"] > 0:
		_invalid(
			(
				"a passenger or its bag clips the booth: body=%d bag=%d"
				% [totals["body"], totals["bag"]]
			)
		)
	for id in _sent:
		var s: Dictionary = _stats.get(id, {})
		var traits: Array = _role_of[id]
		if s.get("mid", 0) == 0:
			_invalid("sent passenger %d never crossed mid-booth" % id)
		elif (traits[2] or traits[3]) and not _phases_of(id, s).has(SecurityRuntime.Phase.REPACK):
			_invalid("passenger %d (liquids or alarm) never repacked" % id)


## Default mode's coverage: every kind carried through a booth, each repaired
## move checked whole, both crossing plates and every move's close plates.
func _report_booth() -> void:
	for kind in KIND_NAMES:
		if not _kinds_crossed.has(kind):
			_invalid("no %s carried through a booth" % kind)
	print("MOVES_CHECKED %s" % _moves_done)
	for move in ["roller_lift", "roller_lower", "repack_pickup_case", "repack_pickup_shoulder"]:
		if int(_moves_done.get(move, 0)) == 0:
			_invalid("no whole %s move was checked" % move)
	if _plates_saved < 2:
		_invalid("only %d of 2 crossing plates saved" % _plates_saved)
	print("MOVE_PLATES %s" % _move_plated)
	for kind in MOVE_PLATES:
		if not _move_plated.has(kind):
			_invalid("no close plates of a whole %s move" % kind)


## Lane mode's coverage: each crossing's lowest tuck weight between the arch's
## posts, at least two crossings run, a returner's second pass, the close
## plate of a tucked passenger mid-arch.
func _report_lane() -> void:
	for id in _stats:
		for key in ["arch_first", "arch_second"]:
			if _stats[id].has(key):
				var run: Dictionary = _stats[id][key]
				print(
					(
						"ARCH_CROSSING passenger=%d pass=%s frames=%d run_frames=%d tuck_min=%.2f"
						% [id, key, run["frames"], run["run_frames"], run["tuck_min"]]
					)
				)
	print(
		(
			"ARCH_TOTAL runners=%s second_passes=%d plated=%s"
			% [_arch_runners.keys(), _arch_second, _arch_plated]
		)
	)
	if _arch_runners.size() < 2:
		_invalid("only %d passengers ran through the arch" % _arch_runners.size())
	if _arch_second == 0:
		_invalid("no returner crossed the arch a second time")
	if not _arch_plated:
		_invalid("no close plate of a tucked passenger mid-arch")


## The security phases passenger `id` was seen in: on checked frames near a
## booth (`s`), and in lane mode on any frame.
func _phases_of(id: int, s: Dictionary) -> Dictionary:
	var out: Dictionary = (s["phases"] as Dictionary).duplicate()
	out.merge(_phases_seen.get(id, {}))
	return out
