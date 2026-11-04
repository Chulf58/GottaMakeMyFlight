extends SceneTree
## Windowed plate for the passenger speech-bubble declutter (board f19a5170,
## decision passenger-speech-bubbles-that-overlap-on-screen-keep-the-one): the
## real main scene with the starter terminal built and staffed, 14 passengers
## spawned at once until a check-in lane holds a long queue, then the queue's
## tail given bubbles ("I'm late!" and "Queue full" alternating, set on the
## sim's passengers, since a natural run does not guarantee the clash), seen
## from a camera framed on the queue.
##
## Boots main with a new random sim seed (printed). Before it saves the plate
## it proves its subjects: at least MIN_BUBBLES passengers carry bubble text,
## every one's bubble point projects inside the frame (margin MARGIN_PX), a
## control shows that without the declutter at least one pair of bubble
## rectangles overlaps, then that no two visible bubbles overlap, that a
## hidden bubble overlaps a visible one (so none is hidden for nothing),
## and a raycast shows the kept
## passengers' bodies are in line of sight. It prints every visible bubble's
## screen rectangle. Otherwise it prints PROBE_INVALID and exits 1.
##
## Run (one windowed Godot run project-wide; take the slot first). The window is
## 1536x864 and the UI scale is the project's own 1.25:
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy --resolution 1536x864 \
##     --path game -s res://spike/bubble_declutter_plate_probe.gd
## With `-- --no-plate` it skips the screenshot and the line-of-sight check, so
## the rest of the checks can run headless (the numbers are then not a render).
##
## The plate goes to tools/blender/out/bubble-declutter/.

const PlateSight := preload("res://spike/plate_sight.gd")
const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/bubble-declutter"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const QUEUE_PEOPLE := 14
const MIN_QUEUED := 6
const MIN_BUBBLES := 4
const WAIT_TICKS := 900
const DISTANCES := [9.0, 11.0, 13.0, 16.0, 20.0]
const HEAD_M := 1.7

var _failed := false
var _plate := true


func _initialize() -> void:
	_plate = not OS.get_cmdline_user_args().has("--no-plate")
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	# The headless dummy renderer never emits frame_post_draw.
	if _plate:
		await RenderingServer.frame_post_draw


## The lane and holding area at a desk with the most passengers: [station, ids front first].
func _longest_queue(sim: PassengerSim) -> Array:
	var best_station := 0
	var best: Array[int] = []
	for station in sim.layout.desks:
		var lane := sim.queue_of(station)
		lane.append_array(sim.holding_of(station))
		if lane.size() > best.size():
			best = lane
			best_station = station
	return [best_station, best]


func _run() -> void:
	var out_dir := ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var main: Node3D = load(MAIN_SCENE).instantiate()
	var clock: SimClock = main.get_node("SimClock")
	var seed := randi()
	clock.seed_rng(seed)
	print("PROBE sim_seed=", seed, " window=", root.size, " ui_scale=", root.content_scale_factor)
	root.add_child(main)
	clock.set_paused(true)
	await _frames(5)
	(main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	var build_mode := main.get_node("BuildMode") as BuildMode
	build_mode.set_tool(BuildMode.Tool.NONE)
	await _frames(20)
	var sim: PassengerSim = main.get_node("PassengerSim")
	var staff := main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(sim, staff)
	var doors := StarterFlight.advance_until_open(
		clock, main.get_node("FlightSim") as FlightSim, staff
	)
	print("PROBE staff_hired=%d doors_close_tick=%d tick=%d" % [hired, doors, clock.tick])
	if hired == 0 or doors < 0:
		_invalid("the staff were not hired and the airport did not open")
		quit(1)
		return
	for i in QUEUE_PEOPLE:
		sim.spawn_now(FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0))
	clock.set_process(false)
	clock.set_paused(false)
	var waited := 0
	var queue: Array = []
	while waited < WAIT_TICKS:
		clock.advance(SimClock.STEP)
		waited += 1
		queue = _longest_queue(sim)
		if (queue[1] as Array).size() >= MIN_QUEUED:
			break
	clock.set_paused(true)
	var stages := {}
	for id in sim.passenger_ids():
		var stage_name: String = Passenger.Stage.keys()[sim.get_passenger(id).stage]
		stages[stage_name] = int(stages.get(stage_name, 0)) + 1
	print("PROBE stages=%s paused=%s tick=%d" % [stages, clock.paused, clock.tick])
	var station: int = queue[0]
	var lane: Array[int] = []
	lane.assign(queue[1])
	print("PROBE queue_station=%d queued=%d after_ticks=%d" % [station, lane.size(), waited])
	if lane.size() < MIN_QUEUED:
		_invalid("the longest check-in queue holds %d, fewer than %d" % [lane.size(), MIN_QUEUED])
		quit(1)
		return
	# The queue's tail gets the clash: alternating late and queue-full.
	var tail := lane.slice(lane.size() - MIN_BUBBLES - 2)
	for i in tail.size():
		var p := sim.get_passenger(tail[i])
		p.late = i % 2 == 0
		p.stuck = Passenger.Stuck.NONE if i % 2 == 0 else Passenger.Stuck.QUEUE_FULL
	print("PROBE forced_bubbles tail=%s (late on even places, queue full on odd)" % [tail])
	var views := main.get_node("PassengerViews") as PassengerViews
	views.sync()
	var rig: TycoonCamera = main.get_node("TycoonCamera")
	var cam: Camera3D = rig.get_node("Camera3D")
	cam.make_current()
	# Nodes take their place in draw(), which has not run since the sync.
	views.draw()
	var centre := Vector3.ZERO
	for id in lane:
		centre += views.node_for(id).position
	centre /= lane.size()
	var in_frame := false
	var frame := Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2.0
	)
	for d in DISTANCES:
		rig.glide_to(centre * Vector3(1, 0, 1), d)
		for i in 240:
			await _frames(1)
			if not rig.is_gliding():
				break
		await _frames(8)
		views.draw()
		in_frame = true
		for id in tail:
			var at := views.node_for(id).get_node("Bubble") as Label3D
			in_frame = in_frame and frame.has_point(cam.unproject_position(at.global_position))
		if in_frame:
			print("PROBE camera distance=%.1f pitch=%.1f" % [rig.distance, rig.pitch_degrees()])
			for id in tail:
				var at := views.node_for(id).get_node("Bubble") as Label3D
				print(
					(
						"INFRAME id=%d point=%s frame=%s"
						% [id, cam.unproject_position(at.global_position), frame]
					)
				)
			break
	if not in_frame:
		_invalid("the tail's bubbles do not all fit in the frame at any distance")
	_check_bubbles(views, sim, cam, tail)
	if _plate:
		await _check_sight_and_save(views, cam, tail, out_dir)
		await _save_declutter_off(views, cam, tail, out_dir)
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


## The rectangle a passenger's bubble covers now, by the same measure the views use.
func _rect(views: PassengerViews, cam: Camera3D, id: int) -> Rect2:
	var bubble := views.node_for(id).get_node("Bubble") as Label3D
	var unit := NeedIcons.unit_of(root, cam)
	var depth := (bubble.global_position - cam.global_position).dot(-cam.global_basis.z)
	var to_output := root.get_stretch_transform().get_scale().y
	return BubbleDeclutter.rect_of(
		cam.unproject_position(bubble.global_position) * to_output,
		bubble.text,
		bubble.font_size,
		bubble.outline_size,
		bubble.pixel_size / (depth * unit)
	)


func _check_bubbles(views: PassengerViews, sim: PassengerSim, cam: Camera3D, tail: Array) -> void:
	var texted: Array[int] = []
	for id in tail:
		if (views.node_for(id).get_node("Bubble") as Label3D).text != "":
			texted.append(id)
	print("PROBE bubbles_with_text=%d of %d" % [texted.size(), tail.size()])
	if texted.size() < MIN_BUBBLES:
		_invalid("fewer than %d passengers carry bubble text" % MIN_BUBBLES)
	var margin := BubbleDeclutter.MARGIN_PX - 0.01
	var all_overlap := 0
	for i in texted.size():
		for j in range(i + 1, texted.size()):
			if _rect(views, cam, texted[i]).grow(margin / 2.0).intersects(
				_rect(views, cam, texted[j]).grow(margin / 2.0)
			):
				all_overlap += 1
	print("PROBE control overlapping_pairs_before_declutter=%d" % all_overlap)
	if all_overlap == 0:
		_invalid("no two bubbles overlap before the declutter, so it had nothing to do")
	var shown: Array[int] = []
	for id in texted:
		var bubble := views.node_for(id).get_node("Bubble") as Label3D
		var rect := _rect(views, cam, id)
		var rank := BubbleDeclutter.rank_of(sim, sim.get_passenger(id))
		print(
			(
				"BUBBLE id=%d rank=%d text=%s visible=%s rect=%s"
				% [id, rank, bubble.text, bubble.visible, rect]
			)
		)
		if bubble.visible:
			shown.append(id)
	if shown.is_empty():
		_invalid("no bubble is visible")
	for i in shown.size():
		for j in range(i + 1, shown.size()):
			var a := _rect(views, cam, shown[i])
			var b := _rect(views, cam, shown[j])
			if a.grow(margin / 2.0).intersects(b.grow(margin / 2.0)):
				_invalid("visible bubbles %d and %d overlap" % [shown[i], shown[j]])
	# A hidden bubble must overlap a visible one that outranks it.
	for id in texted:
		if shown.has(id):
			continue
		var covered := false
		for other in shown:
			covered = (
				covered
				or (_rect(views, cam, id).grow(margin / 2.0).intersects(
					_rect(views, cam, other).grow(margin / 2.0)
				))
			)
		if not covered:
			_invalid("bubble %d is hidden but overlaps no visible bubble" % id)


## Raycast: each kept passenger's head is in line of sight, then the plate.
func _check_sight_and_save(
	views: PassengerViews, cam: Camera3D, tail: Array, out_dir: String
) -> void:
	var owners: Array[Node] = []
	var subjects := {}
	for id in tail:
		var node := views.node_for(id)
		owners.append(node)
		subjects[node] = "p%d" % id
	var holder := PlateSight.colliders(root, owners, subjects)
	var space := cam.get_world_3d().direct_space_state
	var seen := 0
	for id in tail:
		if not (views.node_for(id).get_node("Bubble") as Label3D).visible:
			continue
		var head := views.node_for(id).position + Vector3(0.0, HEAD_M, 0.0)
		var targets: Array[Vector3] = [head]
		var lines := PlateSight.sight_lines(space, cam.global_position, targets, "p%d" % id)
		var landed: Array[Vector3] = lines["on_subject"]
		print("SIGHT id=%d on=%d blockers=%s" % [id, landed.size(), lines["blockers"]])
		seen += landed.size()
	holder.queue_free()
	if seen == 0:
		_invalid("no kept passenger is in line of sight")
	var img := await PlateSight.grab(self)
	var path := out_dir.path_join("01_queue_tail_bubbles.png")
	img.save_png(path)
	print("PLATE ", path, " size=", img.get_size())


## The same frame with the declutter switched off: every bubble with text must
## show again (a control that the first plate's hiding came from the declutter),
## and the plate is saved for the before-and-after comparison.
func _save_declutter_off(
	views: PassengerViews, cam: Camera3D, tail: Array, out_dir: String
) -> void:
	views.declutter_bubbles = false
	await _frames(3)
	views.draw()
	var visible_count := 0
	for id in tail:
		var bubble := views.node_for(id).get_node("Bubble") as Label3D
		if bubble.text != "" and bubble.visible:
			visible_count += 1
			print("OFF id=%d text=%s rect=%s" % [id, bubble.text, _rect(views, cam, id)])
	print("PROBE declutter_off visible_bubbles=%d of %d" % [visible_count, tail.size()])
	if visible_count != tail.size():
		_invalid("with the declutter off, not every bubble shows")
	var img := await PlateSight.grab(self)
	var path := out_dir.path_join("02_queue_tail_bubbles_declutter_off.png")
	img.save_png(path)
	print("PLATE ", path, " size=", img.get_size())
	views.declutter_bubbles = true
