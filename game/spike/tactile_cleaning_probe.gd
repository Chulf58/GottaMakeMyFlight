extends SceneTree
## Windowed Vulkan plates for tactile cleaning loop (decision dcb3b59a):
##   1. plate_01_cleaner_sweep: cleaner actively sweeping LITTER (Mode.CLEANER + broom)
##   2. plate_02_cleaner_bag_carry: cleaner walking carrying PropKind.TRASH_BAG toward a bin
##   3. plate_03_passenger_bin_toss: passenger tossing litter at a bin (Mode.BIN_TOSS)
## Proves every subject is in frame with margin and unobstructed via PlateSight raycasts.

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/tactile-cleaning"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 12.0
const MIN_SUBJECT_PX := 80.0
const FEET_TOLERANCE_M := 0.06
const PATCH := Vector2i(7, 5)
const CLOSE_M := 4.4
const OWNERS: Array[String] = ["Airside/Terminal", "BuildMode", "PassengerViews", "StaffCharacters"]

var _out_dir := ""
var _failed := false
var _main: Node
var _cam: Camera3D
var _rig: TycoonCamera
var _clock: SimClock
var _sim: PassengerSim
var _staff: StaffSim
var _chars: StaffCharacters
var _pax_views: PassengerViews
var _mess_views: MessViews
var _build: BuildMode
var _patch := Vector2i(-1, -1)
var _saved: Array[Image] = []


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _run() -> void:
	await _boot()
	if not _failed:
		await _plate_cleaner_sweep_and_carry()
	if not _failed:
		await _plate_passenger_bin_toss()
	_main.queue_free()
	await _frames(3)
	if not _saved.is_empty():
		_save(_sheet(), "contact_sheet", false)
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _boot() -> void:
	var world_seed := randi()
	print("PROBE world_seed=%d" % world_seed)
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(world_seed)
	(_main.get_node("BuildMenu") as BuildMenu).grant_hold_s = 0.5
	root.add_child(_main)
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_sim = _main.get_node("PassengerSim")
	_staff = _main.get_node("Staff")
	_chars = _main.get_node("StaffCharacters")
	_pax_views = _main.get_node("PassengerViews")
	_build = _main.get_node("BuildMode")
	_mess_views = _chars.get_node("MessViews")
	await _frames(5)
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	_build.set_tool(BuildMode.Tool.NONE)
	_clock.set_paused(true)
	await _frames(2)
	_patch = _find_patch()
	if _patch.x < 0:
		_invalid("no open %s patch of indoor floor" % PATCH)
	print("PROBE patch=%s" % _patch)


func _find_patch() -> Vector2i:
	var grid := _sim.grid
	var door := _sim.layout.door_cell(grid, _sim.layout.entrances[0])
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for y in grid.size.y - PATCH.y:
		for x in grid.size.x - PATCH.x:
			var open := true
			for dy in PATCH.y:
				for dx in PATCH.x:
					var c := Vector2i(x + dx, y + dy)
					if not grid.is_indoor(c) or not grid.is_walkable(c) or grid.object_at(c) != 0:
						open = false
						break
				if not open:
					break
			var d := absi(x + 3 - door.x) + absi(y + 2 - door.y)
			if open and d < best_d:
				best = Vector2i(x, y)
				best_d = d
	return best


func _cell(offset: Vector2i) -> Vector2i:
	return _patch + offset


func _edit(label: String, edits: Array[BuildEdit]) -> BuildResult:
	var grid := _build.grid
	grid.hold_signals()
	var result := BuildTransaction.commit_plan(grid, edits, null)
	grid.release_signals()
	(_build.get_node("BuildView") as BuildView).refresh(grid)
	if not result.ok:
		_invalid("%s refused (%s)" % [label, result.reason_text()])
	return result


func _aim(at: Vector3, distance: float, yaw: float) -> void:
	_rig.stop_follow()
	_rig.position = Vector3(at.x, 0.0, at.z)
	_rig.yaw = yaw
	_rig.distance = distance


func _frame_rect() -> Rect2:
	return Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2.0
	)


func _owners() -> Array[Node]:
	var owners: Array[Node] = []
	for path in OWNERS:
		owners.append(_main.get_node(path))
	return owners


func _step_sim(ticks := 1) -> void:
	_clock.holds.clear()
	_clock.set_paused(false)
	for i in ticks:
		_clock.advance(SimClock.STEP)
	_clock.set_paused(true)


func _plate_cleaner_sweep_and_carry() -> void:
	var bin_cell := _cell(Vector2i(1, 2))
	var mess_cell := _cell(Vector2i(5, 2))
	var res := _edit("place_bin", [BuildEdit.place_object(MessSim.BIN_ID, bin_cell, 0)])
	if not res.ok:
		return
	var mess_id := _sim.messes.add(MessSim.Kind.LITTER, mess_cell)
	if mess_id == 0:
		_invalid("failed to add litter mess")
		return
	var cleaner_id := _staff.hire(StaffMember.Role.CLEANER)
	var m := _staff.get_member(cleaner_id)
	m.at = _cell(Vector2i(3, 2))
	m.clear_path()

	# Advance until cleaner is actively sweeping the mess for ~10 ticks.
	var ok_sweep := false
	for i in 400:
		_step_sim()
		if m.state == StaffMember.State.ON_DUTY and m.job == mess_id:
			_step_sim(10)
			ok_sweep = true
			break
	if not ok_sweep:
		_invalid("cleaner did not enter ON_DUTY sweep on mess %d" % mess_id)
		return
	_chars.sync(true)
	_chars.draw()
	await _frames(4)
	var cnode := _chars.node_for(cleaner_id)
	var sk := cnode.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	await sk.skeleton_updated
	var mod := cnode.get_meta(&"station_pose", null) as StaffStationPose
	var anim_p := cnode.get_node("AnimationPlayer") as AnimationPlayer
	var hr := sk.get_bone_global_pose(sk.find_bone("Hand.R"))
	var hl := sk.get_bone_global_pose(sk.find_bone("Hand.L"))
	var ar := sk.get_bone_global_pose(sk.find_bone("Arm.R"))
	var fr := sk.get_bone_global_pose(sk.find_bone("Forearm.R"))
	await _frames(1)
	var broom_node := StaffHandProps.prop_node(cnode, StaffHandProps.PropKind.BROOM)
	var bristles_y := -1.0
	if broom_node != null and broom_node.has_node("Bristles"):
		bristles_y = (broom_node.get_node("Bristles") as Node3D).global_position.y
	print(
		(
			(
				"SWEEP_BONES clip=%s mod=%s active=%s mode=%s sub=%s w=%.2f"
				+ " ar_o=%s fr_o=%s hr_o=%s hl_o=%s bristles_y=%.3f"
			)
			% [
				anim_p.current_animation,
				mod != null,
				mod.active if mod != null else false,
				mod.mode if mod != null else -1,
				mod.sub_mode if mod != null else -1,
				mod.weight if mod != null else -1.0,
				ar.origin,
				fr.origin,
				hr.origin,
				hl.origin,
				bristles_y,
			]
		)
	)
	var focus_sweep: Vector3 = cnode.position.lerp(_sim.grid.cell_to_world(mess_cell), 0.35)
	var yaw_sweep: float = wrapf(cnode.rotation.y - 0.85, -PI, PI)
	await _capture_person(
		"plate_01_cleaner_sweep", cnode, "cleaner", focus_sweep, CLOSE_M, yaw_sweep
	)

	# Advance until cleaner finished sweeping and is mid-walk carrying trash bag to bin.
	var ok_carry := false
	for i in 400:
		_step_sim()
		if (
			m.bag_carry == StaffMember.BagCarry.TO_BIN
			and m.state == StaffMember.State.TO_STATION
			and m.is_moving()
		):
			_step_sim(3)
			ok_carry = true
			break
	if not ok_carry:
		_invalid("cleaner did not transition to TO_BIN carry")
		return
	_chars.sync(true)
	_chars.draw()
	await _frames(4)
	var bag_node := StaffHandProps.prop_node(cnode, StaffHandProps.PropKind.TRASH_BAG)
	if bag_node == null or not bag_node.visible:
		_invalid("TRASH_BAG prop not visible during bag carry")
		return
	# Frame cleanly from the right-front diagonal so the right-hand trash bag and thigh clearance show.
	var yaw_carry: float = wrapf(cnode.rotation.y - 0.95, -PI, PI)
	var focus_carry: Vector3 = cnode.position.lerp(_sim.grid.cell_to_world(bin_cell), 0.25)
	await _capture_person(
		"plate_02_cleaner_bag_carry", cnode, "cleaner", focus_carry, CLOSE_M * 0.95, yaw_carry
	)

	# Let cleaner finish bag disposal and exit cleanly before passenger plate.
	for i in 400:
		_step_sim()
		if m.state == StaffMember.State.IDLE and m.bag_carry == StaffMember.BagCarry.NONE:
			break
	_staff.fire(StaffMember.Role.CLEANER)
	for i in 400:
		_step_sim()
		if _staff.member_ids().is_empty():
			break
	_chars.sync(true)
	_chars.draw()


func _plate_passenger_bin_toss() -> void:
	var bin_cell := _cell(Vector2i(1, 2))
	var bin_id := _sim.grid.object_at(bin_cell)
	var spot := _sim.messes.bin_approach(bin_id)
	if _sim.flights.flight_ids().is_empty():
		var gate: String = _sim.flights.gate_ids()[0]
		_sim.flights.add_flight("PRB101", FlightSim.schedule_starts(_clock.tick), gate)
	var fid := _sim.flights.flight_ids()[0]
	var p := _sim.get_passenger(_sim.spawn_now(fid))
	p.cleared = true
	p.carry_on = 0
	p.stage = Passenger.Stage.TO_GATE
	p.at = spot
	p.clear_path()
	p.bin_detour_bin = bin_id
	p.bin_detour_end = _clock.tick + MessSim.BIN_TOSS_TICKS
	# Step 6 ticks into the 14-tick toss so arm extension peaks clearly toward the bin.
	_step_sim(6)
	_pax_views.snap()
	_pax_views.draw()
	await _frames(4)
	var pnode := _pax_views.node_for(p.id)
	if pnode == null:
		_invalid("passenger view missing for bin toss")
		return
	var focus_toss: Vector3 = pnode.position.lerp(_sim.grid.cell_to_world(bin_cell), 0.45)
	var yaw_toss: float = wrapf(pnode.rotation.y + 1.05, -PI, PI)
	await _capture_person(
		"plate_03_passenger_bin_toss", pnode, "passenger", focus_toss, CLOSE_M * 0.95, yaw_toss
	)


func _capture_person(
	label: String, person_node: Node3D, tag: String, at: Vector3, distance: float, base_yaw: float
) -> void:
	for turn in 4:
		var yaw := wrapf(base_yaw + turn * PI / 2.0, -PI, PI)
		_aim(at, distance, yaw)
		await _frames(8)
		paused = true
		var img: Image = await PlateSight.grab(self)
		var subjects := {person_node: tag}
		var holder := PlateSight.colliders(root, _owners(), subjects)
		await physics_frame
		await physics_frame
		var bounds: Dictionary = holder.get_meta("bounds")
		var box: AABB = bounds.get(tag, AABB())
		var unbaked: Array = holder.get_meta("unbaked")
		var twin: Dictionary = await PlateSight.hud_twin(self, _main)
		var seen := PlateSight.person_shown(
			_cam, box, tag, _frame_rect(), img, twin["image"], MIN_SUBJECT_PX
		)
		var feet_gap := box.position.y - _sim.grid.origin.y if box.size != Vector3.ZERO else 99.0
		var center_px := _cam.unproject_position(box.get_center())
		holder.free()
		paused = false
		print(
			(
				(
					"CHECK %s yaw=%.2f px=(%.0f,%.0f) height_px=%.0f feet_gap=%.3f on=%d"
					+ " blockers=%s ok=%s"
				)
				% [
					label,
					yaw,
					center_px.x,
					center_px.y,
					float(seen.get("height_px", 0.0)),
					feet_gap,
					int(seen.get("on", 0)),
					seen.get("blockers", []),
					seen.get("ok", false),
				]
			)
		)
		if (
			unbaked.is_empty()
			and bool(seen.get("ok", false))
			and absf(feet_gap) <= FEET_TOLERANCE_M
		):
			_save(img, label)
			return
	_invalid("%s not cleanly framed and unobstructed from any quarter turn" % label)


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
