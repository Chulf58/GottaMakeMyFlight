extends SceneTree
## Windowed plates for the cleaner and mess views (decision cleaner-staff-and-
## messes-visits-leave-messes-bins-fill-pooled-cleaners-nearest-mess, board
## Cleaner 4/5): MessViews' floor props and full-bin rubbish, and the cleaner
## (StaffCharacters, its own body and clean clip) at work. Boots the real main
## scene with a new random sim seed (printed), builds ReferenceTerminal through
## the HUD's starter-terminal button, finds an open 7 x 5 patch of indoor floor
## nearest an entrance, and then:
##   1 normal: LITTER, SPILL and TOILET messes on the patch (MessSim.add()),
##     plated close and at the camera's home distance (messes_normal_*)
##   2 grown: the litter loaded back as grown (MessSim's own load); the sim
##     grows only litter, so grown spill and smear props are put down by the
##     probe on the spill and toilet cells, beside it (messes_grown_*)
##   3 bins: two bins placed, one loaded back full; plated close and at home
##     distance (bins_*)
##   4 cleaner: one cleaner hired with the messes and the full bin there; frame
##     strips of it walking to its first job, cleaning a mess and emptying the
##     bin (cleaner_walk_strip, cleaner_clean_strip, cleaner_bin_strip)
## A prop or rubbish counts as shown when its centre projects inside the frame
## with a margin and a sight line to it lands on it first; the cleaner when
## PlateSight.person_shown() passes and its feet are on the floor. Each check
## prints the projected pixel. A failed check prints PROBE_INVALID and the
## probe exits 1.
##
## Run (one windowed Godot run project-wide; this probe holds the slot):
##   timeout 900 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/cleaner_views_plates_probe.gd
##
## Plates go to tools/blender/out/cleaner-views/.

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/cleaner-views"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const MIN_SUBJECT_PX := 16.0
const FEET_TOLERANCE_M := 0.05
const CLOSE_M := 9.0
const PATCH := Vector2i(7, 5)
const OWNERS: Array[String] = ["Airside/Terminal", "BuildMode", "PassengerViews", "StaffCharacters"]
## Real-time limit on the cleaner phase.
const CLEANER_LIMIT_MS := 240000
const STRIP_FRAMES := 4
## Sight lines a prop or rubbish check casts, each to one of its vertices.
const THING_LINES := 12
## Real seconds between two strip frames (a frame count is no measure: the
## windowed run draws hundreds of frames a second).
const STRIP_GAP_S := 0.5

var _out_dir := ""
var _failed := false
var _main: Node
var _cam: Camera3D
var _rig: TycoonCamera
var _clock: SimClock
var _sim: PassengerSim
var _staff: StaffSim
var _chars: StaffCharacters
var _messes: MessViews
var _build: BuildMode
var _saved: Array[Image] = []
var _patch := Vector2i(-1, -1)


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
		await _phase_messes()
	if not _failed:
		await _phase_cleaner()
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


# ------------------------------------------------------------ setup


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
	_build = _main.get_node("BuildMode")
	_messes = _chars.get_node("MessViews")
	await _frames(5)
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	_build.set_tool(BuildMode.Tool.NONE)
	_clock.set_paused(true)
	await _frames(2)
	_patch = _find_patch()
	print("PROBE home_distance=%.1f patch=%s" % [_rig.home_distance, _patch])
	if _patch.x < 0:
		_invalid("no open %s patch of indoor floor" % PATCH)


## The open patch (every cell indoor, walkable, no object) nearest an entrance.
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


func _edit(label: String, edits: Array[BuildEdit]) -> bool:
	var grid := _build.grid
	grid.hold_signals()
	var result := BuildTransaction.commit_plan(grid, edits, null)
	grid.release_signals()
	(_build.get_node("BuildView") as BuildView).refresh(grid)
	print("EDIT %s ok=%s %s" % [label, result.ok, result.reason_text()])
	if not result.ok:
		_invalid("%s refused (%s)" % [label, result.reason_text()])
	return result.ok


## Loads the messes back with `change` applied to their snapshot. The save's
## tick is put at least GROW_TICKS on, so the load check counts litter loaded
## as grown (born then GROW_TICKS before) at its age; the live tick is not
## touched.
func _reload(change: Callable) -> bool:
	var data := _sim.messes.to_snapshot()
	data["tick"] = maxi(int(data["tick"]), MessSim.GROW_TICKS)
	change.call(data)
	var ok := _sim.messes.from_snapshot(JSON.parse_string(JSON.stringify(data)))
	if not ok:
		_invalid("the mess load was refused")
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
	for path in OWNERS:
		owners.append(_main.get_node(path))
	return owners


## A prop or rubbish (tag `tag`) is shown: of sight lines to THING_LINES of
## its own drawn vertices, at least MIN_ON land on it first, and every landing
## point projects into the frame. A line to a vertex on its far side may be
## blocked (by the bin's can, say); blockers are printed, not failed on.
func _thing_shown(label: String, node: Node3D, tag: String, bounds: Dictionary) -> bool:
	var box: AABB = bounds.get(tag, AABB())
	if box.size == Vector3.ZERO:
		print("SHOWN %s %s no drawn mesh" % [label, tag])
		return false
	var points := PackedVector3Array()
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh != null and mesh.is_visible_in_tree():
			for v in mesh.mesh.get_faces():
				points.append(mesh.global_transform * v)
	var targets: Array[Vector3] = []
	for i in THING_LINES:
		targets.append(points[i * points.size() / THING_LINES])
	var space := _cam.get_world_3d().direct_space_state
	var lines := PlateSight.sight_lines(space, _cam.global_position, targets, tag)
	var landed: Array[Vector3] = lines["on_subject"]
	var in_frame := true
	for at in landed:
		in_frame = in_frame and _frame_rect().has_point(_cam.unproject_position(at))
	var px := _cam.unproject_position(box.get_center())
	var wide_px := _cam.unproject_position(box.position).distance_to(
		_cam.unproject_position(box.end)
	)
	var on := landed.size()
	var ok := in_frame and on >= PlateSight.MIN_ON
	print(
		(
			"SHOWN %s %s node=%s px=(%.0f,%.0f) span_px=%.0f size_m=%s in_frame=%s on=%d blockers=%s ok=%s"
			% [
				label,
				tag,
				node.position,
				px.x,
				px.y,
				wide_px,
				box.size,
				in_frame,
				on,
				lines["blockers"],
				ok
			]
		)
	)
	return ok


func _feet(label: String, box: AABB) -> bool:
	var gap := box.position.y - _sim.grid.origin.y
	print(
		"FEET %s lowest_y=%.3f gap_m=%.3f height_m=%.3f" % [label, box.position.y, gap, box.size.y]
	)
	return absf(gap) <= FEET_TOLERANCE_M


## Grabs the plate and checks every subject in `things` (tag -> node) and the
## cleaner `member` (0 for none). Returns {ok, image}.
func _check(label: String, things: Dictionary, member: int) -> Dictionary:
	paused = true
	var img: Image = await PlateSight.grab(self)
	var subjects := {}
	for tag: String in things:
		subjects[things[tag]] = tag
	if member != 0:
		subjects[_chars.node_for(member)] = "cleaner"
	var holder := PlateSight.colliders(root, _owners(), subjects)
	await physics_frame
	await physics_frame
	var bounds: Dictionary = holder.get_meta("bounds")
	var ok := (holder.get_meta("unbaked") as Array).is_empty()
	for tag: String in things:
		ok = _thing_shown(label, things[tag], tag, bounds) and ok
	if member != 0:
		var twin: Dictionary = await PlateSight.hud_twin(self, _main)
		var box: AABB = bounds.get("cleaner", AABB())
		var seen := PlateSight.person_shown(
			_cam, box, "cleaner", _frame_rect(), img, twin["image"], MIN_SUBJECT_PX
		)
		var m := _staff.get_member(member)
		var player := _chars.node_for(member).get_node("AnimationPlayer") as AnimationPlayer
		print(
			(
				(
					"VISIBLE %s cleaner=%d state=%d job=%d bin=%s clip=%s at=%.2f px=%s"
					+ " height_px=%.0f on=%d blockers=%s ok=%s"
				)
				% [
					label,
					member,
					m.state,
					m.job,
					m.job_bin,
					player.current_animation,
					player.current_animation_position,
					seen.get("px"),
					seen.get("height_px", 0.0),
					seen["on"],
					seen["blockers"],
					seen["ok"]
				]
			)
		)
		ok = seen["ok"] and _feet(label, box) and ok
	holder.free()
	paused = false
	return {"ok": ok, "image": img}


## Aims at `at` from the four quarter turns from `yaw` until every subject is
## shown, and saves the plate.
func _plate(name: String, things: Dictionary, at: Vector3, distance: float, yaw: float) -> void:
	var result := {}
	for turn in 4:
		var view_yaw := wrapf(yaw + turn * PI / 2.0, -PI, PI)
		_aim(at, distance, view_yaw)
		await _frames(20)
		print("PLATE %s at=%s distance=%.0f yaw=%.2f" % [name, at, distance, view_yaw])
		result = await _check(name, things, 0)
		if result["ok"]:
			_save(result["image"], name)
			return
	_invalid("%s: not every subject shown from any side" % name)
	_save(result["image"], name + "_INVALID", false)


# ------------------------------------------------------------ phases


func _patch_centre() -> Vector3:
	return _sim.grid.cell_to_world(_cell(Vector2i(3, 2)))


func _phase_messes() -> void:
	var kinds := [MessSim.Kind.LITTER, MessSim.Kind.SPILL, MessSim.Kind.TOILET]
	var ids: Array[int] = []
	for i in kinds.size():
		ids.append(_sim.messes.add(kinds[i], _cell(Vector2i(1 + 2 * i, 1))))
	await _frames(2)
	var things := {}
	for i in ids.size():
		things["mess%d_kind%d" % [ids[i], kinds[i]]] = _messes.prop_for(ids[i])
	print("PROBE messes ids=%s props=%d" % [ids, _messes.prop_count()])
	if _messes.prop_count() != 3:
		_invalid("expected 3 props, %d drawn" % _messes.prop_count())
		return
	await _plate("messes_normal_close", things, _patch_centre(), CLOSE_M, 0.6)
	await _plate("messes_normal_home", things, _patch_centre(), _rig.home_distance, 0.6)

	# Grown: the litter loaded back as grown; spill and smear grown props put
	# down by the probe (the sim never grows them).
	var spill_cell := _sim.messes.get_mess(ids[1])["cell"] as Vector2i
	var smear_cell := _sim.messes.get_mess(ids[2])["cell"] as Vector2i
	_sim.messes.remove(ids[1])
	_sim.messes.remove(ids[2])
	var grow := func(data: Dictionary) -> void:
		for mess: Dictionary in data["messes"]:
			mess["born_tick"] = int(data["tick"]) - MessSim.GROW_TICKS
			mess["grown"] = true
	if not _reload(grow):
		return
	var gallery: Array[Node3D] = []
	for pair in [[MessSim.Kind.SPILL, spill_cell], [MessSim.Kind.TOILET, smear_cell]]:
		var node := MessViews.prop_scene(pair[0], true).instantiate() as Node3D
		node.position = _sim.grid.cell_to_world(pair[1])
		node.rotation.y = MessViews.turn_of(gallery.size() + 7)
		_messes.add_child(node)
		gallery.append(node)
	await _frames(2)
	var grown := {
		"litter_grown": _messes.prop_for(ids[0]),
		"spill_grown_probe": gallery[0],
		"smear_grown_probe": gallery[1],
	}
	print("PROBE grown litter=%s" % _sim.messes.get_mess(ids[0]))
	await _plate("messes_grown_close", grown, _patch_centre(), CLOSE_M, 0.6)
	await _plate("messes_grown_home", grown, _patch_centre(), _rig.home_distance, 0.6)
	for node in gallery:
		node.free()
	# Normal spill and smear back for the cleaner.
	_sim.messes.add(MessSim.Kind.SPILL, spill_cell)
	_sim.messes.add(MessSim.Kind.TOILET, smear_cell)

	# Bins: one full, one empty beside it.
	var bins: Array[int] = []
	for x in [2, 5]:
		var at := _cell(Vector2i(x, 3))
		if not _edit("bin at %s" % at, [BuildEdit.place_object(MessSim.BIN_ID, at, 0)]):
			return
		bins.append(_sim.grid.object_at(at))
	var fill := func(data: Dictionary) -> void: data["bins"][str(bins[0])] = MessSim.BIN_CAPACITY
	if not _reload(fill):
		return
	await _frames(2)
	print(
		(
			"PROBE bins=%s full=%s rubbish=%d"
			% [bins, _sim.messes.full_bins(), _messes.rubbish_count()]
		)
	)
	if _messes.rubbish_count() != 1:
		_invalid("expected rubbish on 1 bin, %d drawn" % _messes.rubbish_count())
		return
	var bin_at := _sim.grid.cell_to_world(_cell(Vector2i(3, 3)))
	var rubbish := {"rubbish_bin%d" % bins[0]: _messes.rubbish_for(bins[0])}
	await _plate("bins_close", rubbish, bin_at, CLOSE_M, 0.6)
	await _plate("bins_home", rubbish, bin_at, _rig.home_distance, 0.6)


func _phase_cleaner() -> void:
	var id := _staff.hire(StaffMember.Role.CLEANER)
	_clock.set_paused(false)
	var start := Time.get_ticks_msec()
	var walked := false
	var cleaned := false
	var emptied := false
	while not (walked and cleaned and emptied):
		if Time.get_ticks_msec() - start > CLEANER_LIMIT_MS:
			_invalid(
				(
					"cleaner phase timed out walked=%s cleaned=%s emptied=%s"
					% [walked, cleaned, emptied]
				)
			)
			return
		await _frames(1)
		var m := _staff.get_member(id)
		if m == null or m.in_pool() or _chars.node_for(id) == null:
			continue
		if not walked and m.is_moving() and m.job != 0:
			walked = true
			await _strip("cleaner_walk_strip", id, {})
		elif not cleaned and m.state == StaffMember.State.ON_DUTY and not m.job_bin:
			cleaned = true
			await _strip("cleaner_clean_strip", id, {"job_mess%d" % m.job: _messes.prop_for(m.job)})
		elif not emptied and m.state == StaffMember.State.ON_DUTY and m.job_bin:
			emptied = true
			await _strip(
				"cleaner_bin_strip", id, {"job_rubbish%d" % m.job: _messes.rubbish_for(m.job)}
			)
	print(
		(
			"PROBE cleaner done tick=%d messes=%d full_bins=%s"
			% [_clock.tick, _sim.messes.mess_count(), _sim.messes.full_bins()]
		)
	)


## STRIP_FRAMES frames of cleaner `id`, the camera on it, STRIP_GAP_S seconds
## apart; the first frame also checks `things` (the job's prop or rubbish).
func _strip(name: String, id: int, things: Dictionary) -> void:
	var frames: Array[Image] = []
	var yaw := 0.6
	for i in STRIP_FRAMES:
		var node := _chars.node_for(id)
		if node == null:
			_invalid("%s: the cleaner left the floor at frame %d" % [name, i])
			return
		var ok := false
		var result := {}
		for turn in 4:
			_aim(node.position, CLOSE_M * 0.7, wrapf(yaw + turn * PI / 2.0, -PI, PI))
			await _frames(2)
			print("PLATE %s frame=%d tick=%d yaw=%.2f" % [name, i, _clock.tick, _rig.yaw])
			result = await _check("%s_%d" % [name, i], things if i == 0 else {}, id)
			if result["ok"]:
				yaw = _rig.yaw
				ok = true
				break
		if not ok:
			_invalid("%s: frame %d not shown from any side" % [name, i])
		frames.append(result["image"])
		await create_timer(STRIP_GAP_S).timeout
	_save(_strip_image(frames), name)


# ------------------------------------------------------------ output


func _strip_image(frames: Array[Image]) -> Image:
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
