extends SceneTree
## Windowed Vulkan plate probe for board 73fa430a (decision
## baggage-loop-completion-connect-gated-penalties-visible-wait):
##   1. stacks_desk_and_end.png  - visible stacked AT_DESK bags behind an
##      unconnected check-in desk and IN_ROOM bags stacked on baggage_belt_end.
##   2. cart_shuttle_outbound.png - baggage_cart shuttle driving outbound with
##      Cart_Bags visible during LOAD_LEAD_TICKS.
##   3. cart_at_plane_unloading.png - baggage_cart unloading beside the parked
##      plane's stand before bags settle LOADED.
##
## Run (serialized via tools/blender/out/.windowed.lock):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path .../game -s res://spike/baggage_loop_probe.gd

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/baggage_loop"
const MAIN_SCENE := "res://main/main.tscn"
const ROOM := Rect2i(13, 14, 4, 4)
const DESK1_CELL := Vector2i(11, 11)
const DESK2_ENTRY := Vector2i(15, 10)
const CORNER_CELL := Vector2i(16, 10)
const END_CELL := Vector2i(16, 14)
const CART_CELL := Vector2i(14, 15)
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 60000
const TOTAL_LIMIT_MS := 240000
const WAIT_LIMIT_MS := 150000
const STALL_LIMIT_MS := 8000
const TICK_LIMIT := 25000
const OCCLUDER_OWNERS: Array[String] = [
	"Airside/Terminal", "BuildMode", "PlaneView", "PassengerViews", "BaggageViews"
]

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
var _hud: PassengerHud
var _build: BuildMode
var _sim: BaggageSim
var _views: BaggageViews
var _grid: BuildGrid
var _offset := Vector2i.ZERO
var _desk1_id := 0


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
		var total_ms := Time.get_ticks_msec()
		if idle_ms > HANG_LIMIT_MS or total_ms > TOTAL_LIMIT_MS:
			print(
				(
					"PROBE_INVALID hang stage=%s no heartbeat for %d ms, %d ms in all"
					% [stage, idle_ms, total_ms]
				)
			)
			OS.crash("baggage loop probe hung")


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
		await _capture_stacks_plate()
		await _capture_shuttle_plates()
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _boot() -> void:
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	var seed := randi()
	_clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	root.add_child(_main)
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_hud = _main.get_node("PassengerHud")
	_build = _main.get_node("BuildMode")
	_sim = _main.get_node("BaggageSim")
	_views = _main.get_node("BaggageViews")
	_grid = _build.grid
	await _frames(5)
	_hud.press_starter_terminal()
	_offset = ReferenceTerminal.offset_on(_grid)
	var room_rect := Rect2i(ROOM.position + _offset, ROOM.size)
	var room := RoomTool.mark(_grid, room_rect, &"bag_room", _build.wallet())
	print("BUILD bag_room ok=%s reason=%s" % [room.ok, room.reason_text()])
	if not room.ok:
		_invalid("the bag room was refused")
		return
	var view := _build.get_node("BuildView") as BuildView
	view.refresh(_grid)
	_build.set_tool(BuildMode.Tool.BELT)
	var belt_h := _build.lay_belt(DESK2_ENTRY + _offset, CORNER_CELL + _offset)
	var belt_v := _build.lay_belt(CORNER_CELL + _offset, END_CELL + _offset)
	_build.set_tool(BuildMode.Tool.NONE)
	print("BUILD belts h=%s v=%s" % [belt_h.ok, belt_v.ok])
	if not belt_h.ok or not belt_v.ok:
		_invalid("belt layout failed")
		return
	var cart := _grid.apply(BuildEdit.place_object(&"baggage_cart", CART_CELL + _offset, 0))
	print("BUILD cart ok=%s reason=%s" % [cart.ok, cart.reason_text()])
	if not cart.ok:
		_invalid("baggage_cart placement refused")
		return
	view.refresh(_grid)
	_desk1_id = _grid.object_at(DESK1_CELL + _offset)
	if _desk1_id <= 0:
		_invalid("desk1 not found")
		return
	var staff := _main.get_node("Staff") as StaffSim
	for object_id in _grid.object_ids():
		match StringName(_grid.get_object(object_id)["def"]):
			&"checkin_desk":
				staff.hire(StaffMember.Role.CHECKIN)
			&"security_scanner":
				staff.hire(StaffMember.Role.SECURITY)
			&"gate_desk":
				staff.hire(StaffMember.Role.GATE)
	print(
		(
			"PROBE connected=%s desk1=%d staff=%d"
			% [_sim.has_connected_bag_room(), _desk1_id, staff.member_ids().size()]
		)
	)
	if not _sim.has_connected_bag_room():
		_invalid("expected connected bag room")
		return
	_hud.press_speed(3)


func _until(stage: String, done: Callable) -> bool:
	_beat(stage)
	var start_ms := Time.get_ticks_msec()
	var moved_ms := start_ms
	var last_tick := _clock.tick
	while not done.call():
		var now_ms := Time.get_ticks_msec()
		if _clock.tick != last_tick:
			last_tick = _clock.tick
			moved_ms = now_ms
		if _clock.tick >= TICK_LIMIT:
			_invalid("%s: not met by tick %d" % [stage, TICK_LIMIT])
			return false
		if now_ms - start_ms > WAIT_LIMIT_MS:
			_invalid("%s: not met in %d ms (tick %d)" % [stage, WAIT_LIMIT_MS, _clock.tick])
			return false
		if now_ms - moved_ms > STALL_LIMIT_MS:
			_invalid("%s: clock stalled at tick %d" % [stage, last_tick])
			return false
		await process_frame
	return true


func _capture_stacks_plate() -> void:
	var ready := func() -> bool: return _desk1_waiting().size() >= 3 and _end_waiting().size() >= 3
	if not await _until("wait_stacks", ready):
		return
	var settled_tick := _clock.tick + 2
	if not await _until("settle_stacks", func() -> bool: return _clock.tick >= settled_tick):
		return
	_hud.press_speed(0)
	await _frames(3)
	var desk_bags := _desk1_waiting()
	var end_bags := _end_waiting()
	print(
		(
			"STACKS tick=%d desk1_at_desk=%d end_in_room=%d active_nodes=%d"
			% [_clock.tick, desk_bags.size(), end_bags.size(), _views.active_count()]
		)
	)
	var focus := (
		(_grid.cell_to_world(DESK1_CELL + _offset) + _grid.cell_to_world(END_CELL + _offset)) * 0.5
	)
	var subjects := {}
	var desk_nodes: Array[Node3D] = []
	for i in mini(desk_bags.size(), BaggageViews.MAX_DESK_STACK):
		var node := _views.node_for(desk_bags[i].id)
		if node != null:
			desk_nodes.append(node)
			subjects[node] = "desk_%d" % i
	var end_nodes: Array[Node3D] = []
	for i in mini(end_bags.size(), BaggageViews.MAX_ROOM_STACK):
		var node := _views.node_for(end_bags[i].id)
		if node != null:
			end_nodes.append(node)
			subjects[node] = "end_%d" % i
	for i in range(1, desk_nodes.size()):
		if desk_nodes[i].position.y <= desk_nodes[i - 1].position.y + 0.15:
			_invalid(
				(
					"desk stack heights do not rise: %s"
					% [desk_nodes.map(func(n: Node3D) -> float: return n.position.y)]
				)
			)
	for i in range(1, end_nodes.size()):
		if end_nodes[i].position.y <= end_nodes[i - 1].position.y + 0.15:
			_invalid(
				(
					"end stack heights do not rise: %s"
					% [end_nodes.map(func(n: Node3D) -> float: return n.position.y)]
				)
			)
	var best_img: Image = null
	var best_shown := -1
	var best_top_ok := false
	for yaw in [PI * 0.85, -PI * 0.15, PI, -PI * 0.85]:
		_aim(focus, 11.0, yaw)
		await _frames(15)
		var check := await _check_subjects(subjects, 8.0, true)
		var top_desk := "desk_%d" % (desk_nodes.size() - 1)
		var top_end := "end_%d" % (end_nodes.size() - 1)
		var top_ok: bool = (
			check["results"].get(top_desk, {}).get("ok", false)
			and check["results"].get(top_end, {}).get("ok", false)
		)
		print(
			(
				"STACKS_VIEW yaw=%.2f shown=%d/%d top_ok=%s"
				% [yaw, check["shown"], subjects.size(), top_ok]
			)
		)
		if (
			check["shown"] > best_shown
			or (check["shown"] == best_shown and top_ok and not best_top_ok)
		):
			best_shown = check["shown"]
			best_img = check["image"]
			best_top_ok = top_ok
		if check["shown"] == subjects.size() and top_ok:
			break
	if best_img != null:
		_save(best_img, "stacks_desk_and_end")
	if best_shown < subjects.size() or not best_top_ok:
		_invalid(
			(
				"stacks_desk_and_end: only %d of %d stacked bags clear (top_ok=%s)"
				% [best_shown, subjects.size(), best_top_ok]
			)
		)
	_hud.press_speed(3)


func _capture_shuttle_plates() -> void:
	var dispatched := func() -> bool: return not _sim.shuttles().is_empty()
	if not await _until("wait_shuttle_dispatch", dispatched):
		return
	var shuttle := _sim.shuttles()[0]
	var mid_tick := int((shuttle.start_tick + shuttle.arrive_tick) / 2.0)
	if not await _until("wait_shuttle_mid", func() -> bool: return _clock.tick >= mid_tick):
		return
	_hud.press_speed(0)
	await _frames(3)
	var cart_node := _views.shuttle_node_for(shuttle.id)
	if cart_node == null:
		_invalid("missing shuttle node at mid-outbound")
		return
	var cart_bags := cart_node.find_child(BaggageViews.CART_BAGS_NODE, true, false) as Node3D
	print(
		(
			"SHUTTLE_OUT tick=%d pos=%s target=%s waypoints=%s cart_bags_vis=%s"
			% [
				_clock.tick,
				cart_node.global_position,
				shuttle.target_world,
				shuttle.waypoints,
				cart_bags != null and cart_bags.visible,
			]
		)
	)
	if cart_bags == null or not cart_bags.visible:
		_invalid("Cart_Bags not visible on outbound shuttle")
	_aim(cart_node.global_position, 14.0, -PI * 0.75)
	await _frames(15)
	var out_check := await _check_subjects({cart_node: "shuttle"}, 12.0)
	_save(out_check["image"], "cart_shuttle_outbound")
	if out_check["shown"] < 1:
		_invalid("cart_shuttle_outbound: shuttle not visible in plate")
	_hud.press_speed(3)

	var unloading := func() -> bool:
		var live := _sim.get_shuttle(shuttle.id)
		return live != null and live.phase == BaggageShuttle.Phase.UNLOADING
	if not await _until("wait_shuttle_unload", unloading):
		return
	_hud.press_speed(0)
	await _frames(3)
	cart_node = _views.shuttle_node_for(shuttle.id)
	if cart_node == null:
		_invalid("missing shuttle node at unloading")
		return
	print(
		(
			"SHUTTLE_UNLOAD tick=%d pos=%s flight=%s"
			% [_clock.tick, cart_node.global_position, shuttle.flight]
		)
	)
	var plane_pos := StandPlacement.stand_point(
		(_main.get_node("FlightSim") as FlightSim).flight_stand(shuttle.flight)
	)
	var frame_focus := (cart_node.global_position + plane_pos) * 0.5
	_aim(frame_focus, 24.0, PI * 0.75)
	await _frames(15)
	var unload_check := await _check_subjects({cart_node: "shuttle"}, 10.0)
	_save(unload_check["image"], "cart_at_plane_unloading")
	if unload_check["shown"] < 1:
		_invalid("cart_at_plane_unloading: shuttle not visible in plate")
	_hud.press_speed(3)

	var settled := func() -> bool: return _sim.loaded_total > 0 and _sim.shuttles().is_empty()
	if not await _until("wait_shuttle_return", settled):
		return
	print("SHUTTLE_DONE tick=%d loaded_total=%d" % [_clock.tick, _sim.loaded_total])


func _desk1_waiting() -> Array[Bag]:
	var out: Array[Bag] = []
	for bag in _sim.bags():
		if bag.state == Bag.State.AT_DESK and bag.desk == _desk1_id:
			out.append(bag)
	return out


func _end_waiting() -> Array[Bag]:
	var out: Array[Bag] = []
	var end_cell := END_CELL + _offset
	for bag in _sim.bags():
		if bag.state == Bag.State.IN_ROOM and bag.cell == end_cell:
			out.append(bag)
	return out


func _aim(at: Vector3, distance: float, yaw: float) -> void:
	_rig.stop_follow()
	_rig.position = Vector3(at.x, 0.0, at.z)
	_rig.yaw = yaw
	_rig.distance = distance


func _check_subjects(subjects: Dictionary, min_px: float, allow_bag_stack := false) -> Dictionary:
	paused = true
	var img: Image = await PlateSight.grab(self)
	var owners: Array[Node] = []
	for path in OCCLUDER_OWNERS:
		owners.append(_main.get_node(path))
	var holder := PlateSight.colliders(root, owners, subjects)
	var bounds: Dictionary = holder.get_meta("bounds")
	await physics_frame
	await physics_frame
	var twin: Dictionary = await PlateSight.hud_twin(self, _main)
	var bare: Image = twin["image"]
	var frame := Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)
	var shown := 0
	var results := {}
	for tag in subjects.values():
		var box: AABB = bounds.get(str(tag), AABB())
		var seen := PlateSight.person_shown(_cam, box, str(tag), frame, img, bare, min_px)
		var stack_ok: bool = seen["ok"]
		if not stack_ok and allow_bag_stack:
			var external := false
			for blocker in seen["blockers"]:
				if str(blocker) != "BaggageBag_Body":
					external = true
			stack_ok = (
				not external
				and seen.get("in_frame", false)
				and int(seen.get("hud_px", 0)) == 0
				and float(seen.get("height_px", 0.0)) >= min_px
			)
		print(
			(
				"VISIBLE tag=%s height_px=%.0f on=%d blockers=%s in_frame=%s hud_px=%d ok=%s stack_ok=%s"
				% [
					tag,
					seen.get("height_px", 0.0),
					seen["on"],
					seen["blockers"],
					seen.get("in_frame"),
					seen.get("hud_px", 0),
					seen["ok"],
					stack_ok,
				]
			)
		)
		results[tag] = seen
		shown += int(stack_ok)
	holder.free()
	paused = false
	return {"shown": shown, "image": img, "results": results}


func _save(img: Image, name: String) -> void:
	var path := _out_dir.path_join(name + ".png")
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
