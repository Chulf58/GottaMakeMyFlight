extends SceneTree
## Windowed probe of carry-on bags at a toilet stall (board item carry-on-
## bags-in-a-toilet-stall-clip; StallCarry) in the real main scene. The
## reference terminal stands on the Toon shell's doors with two toilet rooms
## beside it (ToiletTestLayout, three stalls each), built through the grid's
## own edits. Visitors are sent one at a time, each with a pressing toilet
## need and the bags named in VISITORS (the first bag's kind is a hash of the
## id, so passengers are spawned until one fits); the clock is stepped by
## hand.
##
## Strips (frames in a grid, GRID_COLUMNS a row, from a camera STEEP_UP_M over the stall,
## a little to its side, looking down into it over the partitions):
##   in     the walk to the stall: the backpack or roller taken in hand
##          before the approach cell, then stepping in (every 2nd tick)
##   down   sitting down: the bag set down on the floor (every tick)
##   up     standing up and stepping out: the bag picked up (every tick)
##   out    walking on out until the roller trails again (every 2nd tick,
##          straight after "up")
## The "down" and "up" strips are a cutaway (CUTAWAY_STRIPS): every toilet
## stall hidden for the strip and the camera out by the door, because a walker
## stooping over the bags hides them from a camera straight over the stall (the
## walker's own body was every blocker) and the partitions and door leaves are in
## the way of a lower one.
## Every frame proves each bag and the body are inside its crop (their bounds'
## corners projected, with a margin), and sight lines are cast to each bag;
## each bag must be seen in 3 of 4 of a strip's frames (PlateSight; a bag under
## the head or behind the other bag for a frame is allowed); otherwise
## PROBE_INVALID, exit 1. Each frame also
## prints each bag's highest point, how far it reaches toward the bowl and how
## many of the drawn body's vertices (hands left out) lie inside its meshes
## (CarryContact). Any frame with more than CONTACT_MAX such vertices fails the
## probe (PROBE_FAIL, exit 1): a bag through a leg or the hips is the defect
## this probe guards.
## A guard thread calls OS.crash() on a stall.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 900 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/stall_bags_probe.gd
##
## Plates go to tools/blender/out/stall-bags-2/.

const PlateSight := preload("res://spike/plate_sight.gd")
const CarryContact := preload("res://spike/carry_contact.gd")
const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/stall-bags-2"
## Drawn body vertices (hands left out) allowed inside a bag on any frame.
const CONTACT_MAX := 0
const OCCLUDER_OWNERS: Array[String] = [
	"Airside/Terminal", "BuildMode", "PlaneView", "PassengerViews"
]
const MARGIN_PX := 8
## Strips plated as a cutaway: every toilet stall hidden, the camera out by the
## door, so the partitions and the leaves are not in the way and a bag a
## stooping walker bends over is seen in front of the head.
const CUTAWAY_STRIPS: Array[String] = ["down", "up"]
## The cutaway camera: this far further out of the door than the aim point and
## this high, with this field of view (a top-down camera over the stall cannot
## see a bag the walker stoops over).
const CUT_OUT_M := 1.6
const CUT_UP_M := 4.0
const CUT_FOV := 40.0
const HANG_MS := 90000
const LAST_TICKS := 2400
## [label, first bag's kind, bags, strips].
const VISITORS := [
	["case", SecurityLooks.Kind.CASE, 1, ["down", "up"]],
	["backpack", SecurityLooks.Kind.BACKPACK, 1, ["in", "down", "up", "out"]],
	["roller", SecurityLooks.Kind.ROLLER, 1, ["in", "down", "up", "out"]],
	["roller2", SecurityLooks.Kind.ROLLER, 2, ["down", "up", "out"]],
]
## Strip -> [frames, ticks between frames].
const STRIPS := {"in": [16, 2], "down": [8, 1], "up": [10, 1], "out": [12, 2]}
## The camera: this high and this far to the side of the visited stall's
## centre line, looking at a point this far out of the door from its centre.
const STEEP_UP_M := 7.0
const SIDE_M := 0.5
const AIM_OUT := {"in": 1.3, "down": 0.4, "up": 0.6, "out": 1.6}
## Field of view per strip (narrow inside the stall, to see the bag large).
const FOV := {"in": 62.0, "down": 22.0, "up": 30.0, "out": 66.0}
## Frames per row of a strip's plate.
const GRID_COLUMNS := 5
## Crop half size in plate pixels.
const CROP_HALF := Vector2i(400, 470)
## The stall around its footprint centre (StallCarry): the bowl's front and
## the partitions' top.
const BOWL_OUT_M := 0.15
const TOP_M := 2.22

var _out_dir := ""
var _failed := false
var _guard := Thread.new()
var _lock := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _stop := false

var _main: Node3D
var _sim: PassengerSim
var _clock: SimClock
var _views: PassengerViews
var _rows: Array[Image] = []


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=%s" % _out_dir)
	_beat("boot")
	_guard.start(_watch)
	_run.call_deferred()


func _run() -> void:
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	_clock = _main.get_node("SimClock") as SimClock
	# A seed to replay: ++ --seed=N after the script; a new random one otherwise.
	var seed := randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed = int(arg.trim_prefix("--seed="))
	_clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	root.add_child(_main)
	_clock.set_process(false)
	_clock.set_paused(false)
	await _frames(3)
	var mode := _main.get_node("BuildMode") as BuildMode
	mode.set_process(false)
	mode.set_tool(BuildMode.Tool.NONE)
	(mode.get_node("Ghost") as Node3D).visible = false
	_sim = _main.get_node("PassengerSim") as PassengerSim
	_views = _main.get_node("PassengerViews") as PassengerViews
	_beat("build")
	var ids := ToiletTestLayout.build(mode.grid, 3, mode.shell)
	(mode.get_node("BuildView") as BuildView).refresh(mode.grid)
	await _frames(4)
	_sim.toilets.refresh()
	print("PROBE ids=%s usable_stalls=%d" % [ids, _sim.toilets.layout.stalls.size()])
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(
		_clock, _main.get_node("FlightSim") as FlightSim, staff
	)
	print("PROBE staff hired=%d opened tick=%d doors_close_tick=%d" % [hired, _clock.tick, doors])
	if hired == 0 or doors < 0 or _sim.toilets.layout.stalls.size() != 6:
		_invalid("the airport did not open, or not six usable stalls")
		_finish()
		quit(1)
		return
	for visitor: Array in VISITORS:
		await _visit(visitor)
	if not _rows.is_empty():
		_save(_sheet(_rows), "stall_bags_contact_sheet.png")
	print("PROBE done tick=%d failed=%s strips=%d" % [_clock.tick, _failed, _rows.size()])
	_finish()
	quit(1 if _failed else 0)


## Sends one visitor and takes its strips as their moments come.
func _visit(visitor: Array) -> void:
	var label: String = visitor[0]
	_beat("spawn %s" % label)
	var p := _spawn(visitor[1], visitor[2])
	print("VISITOR %s passenger=%d kinds=%s" % [label, p.id, _kinds(p)])
	var wanted: Array = visitor[3]
	var taken := {}
	var last := _clock.tick + LAST_TICKS
	while _clock.tick < last and taken.size() < wanted.size():
		_beat("%s tick %d" % [label, _clock.tick])
		var strip := _moment(p, wanted, taken)
		if strip != "":
			taken[strip] = true
			await _strip(p, label, strip)
			if strip == "up" and "out" in wanted:
				# Still stepping out (the up strip ends partway through it).
				taken["out"] = true
				await _strip(p, label, "out")
			continue
		_clock.advance(SimClock.STEP)
		await process_frame
	for strip: String in wanted:
		if not taken.has(strip):
			_invalid("%s: no '%s' moment by tick %d (stage %s)" % [label, strip, last, _name(p)])


## A passenger whose first bag is `kind`, with `count` bags and a pressing
## toilet need; the passengers spawned on the way have no bags and no needs.
func _spawn(kind: SecurityLooks.Kind, count: int) -> Passenger:
	var flight := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	while true:
		var p := _sim.get_passenger(_sim.spawn_now(flight))
		ToiletTestLayout.calm(p)
		p.carry_on = 0
		if SecurityLooks.bag_kind(p, 0) == kind:
			p.carry_on = count
			p.toilet_need = 95
			p.toilet_cooldown = 0
			return p
	return null


func _kinds(p: Passenger) -> Array:
	var out := []
	for i in p.carry_on:
		out.append(SecurityLooks.Kind.keys()[SecurityLooks.bag_kind(p, i)])
	return out


## The strip whose moment is now for `p`, or "".
func _moment(p: Passenger, wanted: Array, taken: Dictionary) -> String:
	var sat := _sim.tick - p.stage_tick
	var moments := {
		# A roller is taken in hand at 1.7 m (StallCarry.LIFT_LEAD_M).
		"in": p.stage == Passenger.Stage.TOILET_WALK and p.remaining_mm() <= 2100,
		"down": p.stage == Passenger.Stage.TOILET_SITTING_DOWN and sat == 0,
		"up":
		p.stage == Passenger.Stage.TOILET_STANDING_UP and sat == PassengerSim.STAND_UP_TICKS - 2,
		"out": false,
	}
	for strip: String in wanted:
		if not taken.has(strip) and moments[strip]:
			return strip
	return ""


## The stall `p` visits: its footprint centre, its way out and across.
func _stall_of(p: Passenger) -> Dictionary:
	var stall := _sim.toilets.visit_of(p.id).stall
	var out := SecurityLooks.world_dir(stall["front"])
	return {
		"centre": stall["use"] - out * ToiletLayout.USE_M,
		"out": out,
		"across": out.cross(Vector3.UP),
	}


## One strip: STRIPS[strip] frames of `p`, the clock stepped between them.
func _strip(p: Passenger, label: String, strip: String) -> void:
	var name := "%s_%s" % [label, strip]
	_beat(name)
	var stall := _stall_of(p)
	var aim: Vector3 = stall["centre"] + stall["out"] * AIM_OUT[strip] + Vector3(0.0, 0.8, 0.0)
	var cam := Camera3D.new()
	cam.fov = FOV[strip]
	_main.add_child(cam)
	var cut: bool = strip in CUTAWAY_STRIPS
	var eye: Vector3 = (
		stall["centre"]
		+ stall["across"] * SIDE_M
		+ stall["out"] * (AIM_OUT[strip] + (CUT_OUT_M if cut else 0.0))
		+ Vector3.UP * (CUT_UP_M if cut else STEEP_UP_M)
	)
	var hidden: Array[Node3D] = []
	if cut:
		cam.fov = CUT_FOV
		hidden = _stall_nodes()
	for node in hidden:
		node.visible = false
	cam.look_at_from_position(eye, aim)
	cam.make_current()
	await _frames(4)
	print("CAMERA %s eye=%s aim=%s" % [name, eye, aim])
	var count: int = STRIPS[strip][0]
	var step: int = STRIPS[strip][1]
	var images: Array[Image] = []
	var ok := true
	var seen := 0
	var looked := 0
	for f in count:
		_beat("%s frame %d" % [name, f])
		var img: Image = await PlateSight.grab(self, 3)
		var per := root.get_visible_rect().size.y / float(img.get_height())
		# Inside the stall the crop stays on the stall; walking to or from it,
		# it follows the walker (the camera stays put).
		var centre := aim
		if strip in ["in", "out"]:
			centre = _views.node_for(p.id).global_position + Vector3.UP * 0.8
		var centre_px := Vector2i(cam.unproject_position(centre) / per)
		var crop := Rect2i(centre_px - CROP_HALF, CROP_HALF * 2).intersection(
			Rect2i(Vector2i.ZERO, img.get_size())
		)
		var frame: Dictionary = await _frame_ok(cam, crop, per, p, stall, name, f)
		ok = ok and frame["in_frame"]
		seen += frame["seen"]
		looked += frame["bags"]
		images.append(img.get_region(crop))
		for t in step:
			_clock.advance(SimClock.STEP)
	for node in hidden:
		node.visible = true
	cam.queue_free()
	# A bag hidden for a frame (under the walker's head, or the other bag as
	# both cross over it) is allowed; most of the time each must be seen.
	print("STRIP %s bags seen in %d of %d bag-frames" % [name, seen, looked])
	ok = ok and seen * 4 >= looked * 3
	var row := _grid(images, GRID_COLUMNS)
	if ok:
		_save(row, "stall_bags_%s.png" % name)
		_rows.append(row)
	else:
		_invalid("%s: a bag or the body is out of the crop or not seen" % name)
		_save(row, "stall_bags_%s_INVALID.png" % name)


## One frame's proofs and measures: every bag's corners and the body inside
## the crop (shrunk by MARGIN_PX), and how many bags a sight line lands on.
## Returns {in_frame, seen, bags}.
func _frame_ok(
	cam: Camera3D, crop: Rect2i, per: float, p: Passenger, stall: Dictionary, name: String, f: int
) -> Dictionary:
	var held := _views.carry_on_props().props_of(p.id)
	var bags: Array = held["bags"]
	var body := _views.node_for(p.id)
	var inner := crop.grow(-MARGIN_PX)
	if body == null or bags.is_empty():
		print("FRAME %s %d: no body or no bags" % [name, f])
		return {"in_frame": false, "seen": 0, "bags": 1}
	var points: Array[Vector3] = [body.global_position, body.global_position + Vector3.UP * 1.7]
	var lines := []
	# The drawn body's vertices, both hands left out (a hand holds or lets go
	# of the bag), grouped by their main bone, tested inside each bag's own
	# meshes.
	var owned := CarryContact.body_points_owned(body, [".R", ".L"])
	var by_bone := {}
	for i in (owned[0] as PackedVector3Array).size():
		var bone: String = owned[1][i]
		# A packed array is a value: append to it and store it back.
		var group: PackedVector3Array = by_bone.get(bone, PackedVector3Array())
		group.append(owned[0][i])
		by_bone[bone] = group
	for b in bags.size():
		var node: Node3D = bags[b]
		var contacts := 0
		var touched := []
		for bone: String in by_bone:
			var inside := CarryContact.inside_meshes(by_bone[bone], node)
			if inside > 0:
				contacts += inside
				touched.append("%s:%d" % [bone, inside])
		if contacts > 0:
			print("CONTACT %s %d bag%d %s" % [name, f, b, " ".join(touched)])
		if contacts > CONTACT_MAX:
			print(
				"PROBE_FAIL contact %s %d bag%d: %d body vertices inside" % [name, f, b, contacts]
			)
			_failed = true
		var box := CarryOnProps.bag_box(held["kinds"][b])
		var top := -INF
		var reach := INF
		for i in 8:
			var at := node.global_transform * box.get_endpoint(i)
			points.append(at)
			top = maxf(top, at.y)
			reach = minf(reach, (at - stall["centre"]).dot(stall["out"]))
		lines.append(
			(
				"bag%d %s top=%.2f nearest_bowl_out=%.2f body_points_inside=%d"
				% [b, SecurityLooks.Carry.keys()[held["carries"][b]], top, reach, contacts]
			)
		)
		if top >= TOP_M and reach < 1.0:
			print("FRAME %s %d: bag %d rises to %.2f over the stall" % [name, f, b, top])
	var out_of := 0
	for at in points:
		var px := Vector2i(cam.unproject_position(at) / per)
		if cam.is_position_behind(at) or not inner.has_point(px):
			out_of += 1
	var seen := await _bags_seen(cam, bags)
	var ok := out_of == 0 and seen == bags.size()
	print(
		(
			"FRAME %s %d tick=%d stage=%s body_out=%.2f points_out_of_crop=%d bags_seen=%d/%d %s ok=%s"
			% [
				name,
				f,
				_clock.tick,
				_name(p),
				(body.global_position - stall["centre"]).dot(stall["out"]),
				out_of,
				seen,
				bags.size(),
				" ".join(lines),
				ok
			]
		)
	)
	return {"in_frame": out_of == 0, "seen": seen, "bags": bags.size()}


## How many of `bags` a sight line from the camera lands on (five lines to
## each: its centre and four points about it).
func _bags_seen(cam: Camera3D, bags: Array) -> int:
	var owners: Array[Node] = []
	for path in OCCLUDER_OWNERS:
		owners.append(_main.get_node(path))
	var subjects := {}
	for b in bags.size():
		subjects[bags[b]] = "bag%d" % b
	var holder := PlateSight.colliders(root, owners, subjects)
	await physics_frame
	await physics_frame
	var bounds: Dictionary = holder.get_meta("bounds")
	var space := cam.get_world_3d().direct_space_state
	var seen := 0
	for b in bags.size():
		var box: AABB = bounds.get("bag%d" % b, AABB())
		var c := box.get_center()
		var q := box.size * 0.25
		var targets: Array[Vector3] = [
			c, c + Vector3(q.x, q.y, 0), c - Vector3(q.x, 0, q.z), c + Vector3(0, q.y, q.z), c - q
		]
		var hits := PlateSight.sight_lines(space, cam.global_position, targets, "bag%d" % b)
		seen += 1 if not (hits["on_subject"] as Array).is_empty() else 0
		if (hits["on_subject"] as Array).is_empty():
			print("UNSEEN bag%d blockers=%s past=%s" % [b, hits["blockers"], hits["past"]])
	holder.free()
	return seen


## The toilet stalls drawn now (BuildView's records).
func _stall_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node in _main.get_node("BuildMode/BuildView").get_children():
		var record: Dictionary = node.get_meta("record", {})
		if StringName(record.get("def", "")) == &"toilet_stall" and (node as Node3D).visible:
			out.append(node)
	return out


func _name(p: Passenger) -> String:
	return Passenger.Stage.keys()[p.stage]


## Frames in reading order, `columns` to a row.
func _grid(frames: Array[Image], columns: int) -> Image:
	var w := frames[0].get_width()
	var h := frames[0].get_height()
	var cols := mini(columns, frames.size())
	var rows := ceili(frames.size() / float(cols))
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGBA8)
	for i in frames.size():
		var at := Vector2i(w * (i % cols), h * (i / cols))
		sheet.blit_rect(frames[i], Rect2i(Vector2i.ZERO, frames[i].get_size()), at)
	return sheet


## The rows one under the other, scaled to a common width of 2400 px.
func _sheet(rows: Array[Image]) -> Image:
	var scaled: Array[Image] = []
	var height := 0
	for row in rows:
		var small := row.duplicate() as Image
		var h := roundi(row.get_height() * 2400.0 / row.get_width())
		small.resize(2400, h, Image.INTERPOLATE_BILINEAR)
		scaled.append(small)
		height += h
	var sheet := Image.create(2400, height, false, Image.FORMAT_RGBA8)
	var y := 0
	for small in scaled:
		sheet.blit_rect(small, Rect2i(Vector2i.ZERO, small.get_size()), Vector2i(0, y))
		y += small.get_height()
	return sheet


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
		_beat(_stage)
	await RenderingServer.frame_post_draw


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _beat(stage: String) -> void:
	_lock.lock()
	_stage = stage
	_beat_ms = Time.get_ticks_msec()
	_lock.unlock()


func _finish() -> void:
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_lock.lock()
		var stop := _stop
		var stage := _stage
		var silent := Time.get_ticks_msec() - _beat_ms
		_lock.unlock()
		if stop:
			return
		if silent > HANG_MS:
			print("PROBE_INVALID hang: stage=%s silent_ms=%d" % [stage, silent])
			OS.crash("stall_bags_probe: main thread stalled in %s" % stage)
