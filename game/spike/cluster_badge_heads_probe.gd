extends SceneTree
## Windowed plates of need-icon count badges over seated gate rows (board
## 769f210d: a cluster badge '3' sat over a seated passenger's head on a gate
## seat row while the single icons on that row sat over the heads). Boots
## main.tscn with NeedFacilityKit's terminal and a gate desk, sends in a crowd
## and steps the clock until SEATED_WANT passengers sit at the gate, then gives
## the crowd a fixed pattern of toilet need, hunger and boredom (printed) and
## frames the seated rows at close zoom (CLOSE_M) and at mid zoom.
##
## For every badge drawn it prints the shift place() gave it (placed minus
## wanted, from NeedCluster's kept shifts), its rect, and the passengers whose
## head rect it overlaps. Head rects are measured here, independently of the
## game: a square HEAD_WIDE_M across the view whose top is HEAD_UP_M over each
## drawn passenger's head bone (the head top the need_icon_near_camera probe
## measured). It also prints overlaps with the kept
## speech bubbles and station captions, and grabs every plate twice
## FLICKER_FRAMES apart and compares the badge rects (flicker).
## Proofs before a plate is saved: at least one badge (close plates), every
## badge inside the frame by MARGIN_PX, the seated rows' centre in frame, and
## a physics ray from the camera to the anchor head not blocked. The HUD
## CanvasLayers are hidden (anti-pattern a-plate-probe-s-occlusion-rays-see-
## only-meshes-so-a-hud-pane). Otherwise PROBE_INVALID, exit 1.
## PROBE_SEED replays a seed; PROBE_TAG names the plates (before, after).
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 900 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/cluster_badge_heads_probe.gd
## Plates go to tools/blender/out/cluster_badge_heads/.

const StarterFlight := preload("res://spike/starter_flight.gd")
const PlateSight := preload("res://spike/plate_sight.gd")
const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/cluster_badge_heads"
const CROWD := 40
const SPAWN_GAP_TICKS := 20
const SEATED_WANT := 12
const ARRIVE_LIMIT_TICKS := 6000
const MARGIN_PX := 12.0
const CLOSE_M := [10.0, 12.0, 14.0, 16.0]
const MID_OF_HOME := 0.7
const YAWS := [0.0, 0.35]
const HEAD_UP_M := 0.12
const HEAD_WIDE_M := 0.3
const FLICKER_FRAMES := 6
const FADE_LIMIT_FRAMES := 120
## The sweep: a slow zoom from SWEEP_FAR_M in to SWEEP_NEAR_M by SWEEP_STEP_M
## at each yaw, panning up to SWEEP_PAN_M side to side, as a player zooms in
## on a gate. A badge keeps its last shift while it fits (NeedCluster.place),
## so a shift taken at one zoom carries to the next; the sweep counts every
## badge over a head, and plates the steps at SWEEP_PLATE_M (grabbed twice, for flicker).
const SWEEP_FAR_M := 19.5
const SWEEP_NEAR_M := 10.0
const SWEEP_STEP_M := 0.25
const SWEEP_PAN_M := 3.0
const SWEEP_YAWS := [0.0, 0.35, -0.35]
const SWEEP_PLATE_M := [19.5, 16.0, 12.0]

var _out_dir := ""
var _tag := "run"
var _failed := false
var _main: Node3D
var _cam: Camera3D
var _rig: TycoonCamera
var _clock: SimClock
var _sim: PassengerSim
var _views: PassengerViews
var _on_heads_total := 0
var _sweep_hits := 0
var _sweep_hits_rising := 0
var _plates_with_badges := 0
var _sweep_steps := 0
var _sweep_badges := 0


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	if OS.has_environment("PROBE_TAG"):
		_tag = OS.get_environment("PROBE_TAG")
	print("PROBE out_dir=%s tag=%s" % [_out_dir, _tag])
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _run() -> void:
	if await _boot():
		await _plates()
	print(
		(
			(
				"PROBE done failed=%s badges_on_heads_total=%d sweep_steps=%d sweep_badges=%d"
				+ " sweep_hits=%d sweep_hits_on_rising_heads=%d"
			)
			% [
				_failed,
				_on_heads_total,
				_sweep_steps,
				_sweep_badges,
				_sweep_hits,
				_sweep_hits_rising
			]
		)
	)
	quit(1 if _failed else 0)


func _boot() -> bool:
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	var seed := randi()
	if OS.has_environment("PROBE_SEED"):
		seed = OS.get_environment("PROBE_SEED").to_int()
	_clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	var mode := _main.get_node("BuildMode") as BuildMode
	mode.starter_shell = false
	root.add_child(_main)
	_clock.set_paused(true)
	await _frames(5)
	NeedFacilityKit.build(mode.grid)
	if not StarterFlight.add_gate_desk(mode.grid):
		_invalid("the gate desk was refused")
		return false
	(mode.get_node("BuildView") as BuildView).refresh(mode.grid)
	mode.set_tool(BuildMode.Tool.NONE)
	mode.set_process(false)
	(mode.get_node("Ghost") as Node3D).visible = false
	await _frames(20)
	_clock.set_process(false)
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_sim = _main.get_node("PassengerSim")
	_views = _main.get_node("PassengerViews")
	var staff := _main.get_node("Staff") as StaffSim
	StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(_clock, _main.get_node("FlightSim"), staff)
	if doors < 0:
		_invalid("the airport did not open")
		return false
	_clock.set_paused(false)
	var spawned := 0
	var ticks := 0
	while ticks < ARRIVE_LIMIT_TICKS and _seated().size() < SEATED_WANT:
		if spawned < CROWD and ticks % SPAWN_GAP_TICKS == 0:
			_sim.spawn_now(StarterFlight.first_flight())
			spawned += 1
		_clock.advance(SimClock.STEP)
		ticks += 1
		# Calm on the way in, so nobody turns off to a toilet, cafe or shop.
		for id in _sim.passenger_ids():
			var p := _sim.get_passenger(id)
			p.hunger = 0
			p.toilet_need = 0
			p.boredom = 0
	var seated := _seated()
	print(
		(
			"PROBE arrive ticks=%d tick=%d doors=%d spawned=%d seated=%d"
			% [ticks, _clock.tick, doors, spawned, seated.size()]
		)
	)
	if seated.size() < SEATED_WANT or _clock.tick >= doors:
		_invalid("only %d seated at the gate before the doors" % seated.size())
		return false
	_spread_needs()
	_clock.advance(SimClock.STEP)
	_clock.set_paused(true)
	if _main.get_node("PlaneFleet").has_method("update_views"):
		_main.get_node("PlaneFleet").call("update_views")
	await _frames(4)
	print("PROBE seated after needs=%d provided=%s" % [_seated().size(), NeedIcons.provided(_sim)])
	return true


## Ids of the passengers drawn sitting on a chair (NeedIcons' seated anchor).
func _seated() -> Array[int]:
	var out: Array[int] = []
	for id in _sim.passenger_ids():
		var node := _views.node_for(id)
		if node != null and node.get_meta(&"icon_seated", false):
			out.append(id)
	return out


## Toilet need for every passenger, hunger for every other one, boredom for
## one in three: dense enough that one gate row forms a cluster of a kind.
func _spread_needs() -> void:
	var i := 0
	var given := [0, 0, 0]
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		p.toilet_need = ToiletSim.NEED_MAX
		p.hunger = CafeSim.HUNGER_MAX if i % 2 == 0 else 0
		p.boredom = BoredomSim.MAX if i % 3 == 0 else 0
		given[0] += int(i % 2 == 0)
		given[1] += 1
		given[2] += int(i % 3 == 0)
		i += 1
	print("PROBE needs set: hunger=%d toilet=%d boredom=%d" % given)


func _plates() -> void:
	var layers := 0
	for node in _main.find_children("*", "CanvasLayer", true, false):
		if (node as CanvasLayer).visible:
			(node as CanvasLayer).visible = false
			layers += 1
	print("PROBE hud layers hidden=%d" % layers)
	await _frames(30)
	_rig.follow(_views)
	_rig.stop_follow()
	var centre := Vector3.ZERO
	var seated := _seated()
	for id in seated:
		centre += _views.node_for(id).global_position
	centre /= seated.size()
	print("PROBE seated_centre=%s" % centre)
	await _sweep(centre)
	for yaw: float in YAWS:
		for distance: float in CLOSE_M:
			await _aim(centre, distance, yaw)
			await _plate("close_%dm_yaw%.2f" % [int(distance), yaw], centre, false)
	await _aim(centre, _rig.home_distance * MID_OF_HOME, 0.0)
	await _plate("mid_zoom", centre, true)
	if _plates_with_badges < 2:
		_invalid("only %d plates show a badge" % _plates_with_badges)


func _aim(at: Vector3, distance: float, yaw: float) -> void:
	_rig.stop_follow()
	_rig.position = Vector3(at.x, 0.0, at.z)
	_rig.yaw = yaw
	_rig.distance = distance
	await _frames(20)
	var roof := _main.get_node("RoofView") as RoofView
	var fade := 0
	while roof.cutaway.roof_level != roof.cutaway.roof_target and fade < FADE_LIMIT_FRAMES:
		await process_frame
		fade += 1
	if roof.cutaway.roof_level != roof.cutaway.roof_target:
		_invalid("the roof fade did not end in %d frames" % FADE_LIMIT_FRAMES)
	if absf(_rig.distance - distance) > 0.01:
		_invalid("the camera is at %.2f m, not %.2f" % [_rig.distance, distance])


func _plate(name: String, centre: Vector3, need_badge: bool) -> void:
	await _frames(2)
	var to_output := root.get_stretch_transform().get_scale().y
	var frame := Rect2(
		Vector2.ONE * MARGIN_PX,
		root.get_visible_rect().size * to_output - Vector2.ONE * MARGIN_PX * 2.0
	)
	var at := _cam.unproject_position(centre) * to_output
	print(
		(
			"PROBE plate=%s distance=%.2f centre_px=%s in_frame=%s"
			% [name, _rig.distance, at, frame.has_point(at)]
		)
	)
	if not frame.has_point(at) or _cam.is_position_behind(centre):
		_invalid("%s: the seated rows' centre is out of frame" % name)
	var first := _badge_rects()
	if first.is_empty() and not need_badge:
		print("PROBE plate=%s %s has no badge; not saved" % [name, _tag])
		return
	_plates_with_badges += 1
	var heads := _head_rects(to_output)
	var others := _other_rects()
	var on_heads := 0
	var inside := 0
	for b: Dictionary in _views.need_badges():
		var rect: Rect2 = b["rect"]
		var shift: Vector2 = _views.need_clusters._shifts.get(b["id"], Vector2(NAN, NAN))
		var wanted := Rect2(rect.position - shift, rect.size)
		var over: Array = []
		var wanted_over: Array = []
		for id: int in heads:
			var head: Rect2 = heads[id][0]
			if rect.intersects(head):
				over.append("%d%s" % [id, "s" if heads[id][1] else ""])
			if wanted.intersects(head):
				wanted_over.append(id)
		var crowded := 0
		for other: Rect2 in others:
			crowded += int(rect.intersects(other))
		inside += int(frame.encloses(rect))
		on_heads += int(not over.is_empty())
		print(
			(
				(
					"BADGE %s %s id=%d kind=%s count=%d rect=%s shift=%s over_heads=%s"
					+ " wanted_over_heads=%s over_bubbles_captions=%d in_frame=%s"
				)
				% [
					_tag,
					name,
					b["id"],
					NeedIcons.Need.keys()[b["kind"]],
					b["count"],
					rect,
					shift,
					over,
					wanted_over,
					crowded,
					frame.encloses(rect)
				]
			)
		)
	_on_heads_total += on_heads
	if need_badge and inside == 0:
		_invalid("%s: no badge inside the frame" % name)
	if inside < _views.need_badges().size():
		_invalid(
			"%s: %d badges reach out of the frame" % [name, _views.need_badges().size() - inside]
		)
	_ray_check(name)
	var plate := await PlateSight.grab(self)
	var second := await _regrab()
	var moved := 0
	for id: int in first:
		moved += int(not second.has(id) or second[id] != first[id])
	print(
		(
			"PROBE plate=%s %s badges=%d on_heads=%d heads=%d flicker_changed=%d"
			% [name, _tag, first.size(), on_heads, heads.size(), moved]
		)
	)
	_save(plate, "%s_%s.png" % [_tag, name])
	_save(_annotated(plate, heads, to_output), "%s_%s_boxes.png" % [_tag, name])


func _regrab() -> Dictionary:
	await _frames(FLICKER_FRAMES)
	return _badge_rects()


func _badge_rects() -> Dictionary:
	var out := {}
	for b: Dictionary in _views.need_badges():
		out[b["id"]] = b["rect"]
	return out


## Passenger id -> [head rect in output pixels, seated], measured from the head bone.
func _head_rects(to_output: float) -> Dictionary:
	var out := {}
	for id in _sim.passenger_ids():
		var node := _views.node_for(id)
		if node == null or not node.is_visible_in_tree():
			continue
		var head := _head_point(node)
		if _cam.is_position_behind(head):
			continue
		var top_m := head + Vector3(0.0, HEAD_UP_M, 0.0)
		var top := _cam.unproject_position(top_m)
		var side := (
			_cam.unproject_position(top_m + _cam.global_basis.x * HEAD_WIDE_M).distance_to(top)
			* to_output
		)
		top *= to_output
		out[id] = [
			Rect2(top - Vector2(side / 2.0, 0.0), Vector2(side, side)),
			node.get_meta(&"icon_seated", false)
		]
	return out


## The kept speech bubbles and the station captions, in output pixels.
func _other_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	out.append_array(_views._markers.placed_captions())
	for e: Dictionary in _views._bubble_entries:
		var bubble := _views.node_for(e["id"]).get_node("Bubble") as Label3D
		if bubble.visible:
			out.append(e["rect"])
	return out


func _head_point(node: Node3D) -> Vector3:
	for skeleton in node.find_children("*", "Skeleton3D", true, false):
		var bones := skeleton as Skeleton3D
		for i in bones.get_bone_count():
			if bones.get_bone_name(i).to_lower().contains("head"):
				return bones.global_transform * bones.get_bone_global_pose(i).origin
	return node.global_position + Vector3(0.0, 1.5, 0.0)


## A ray from the camera to the first badge's anchor head must not be blocked.
func _ray_check(name: String) -> void:
	var badges := _views.need_badges()
	if badges.is_empty():
		return
	var space := _cam.get_world_3d().direct_space_state
	for cluster in _views.need_clusters.clusters():
		if cluster["id"] != badges[0]["id"]:
			continue
		var node := _views.node_for(cluster["rep"])
		var head := _head_point(node)
		var hit := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(_cam.global_position, head)
		)
		print("PROBE %s ray_to_rep_head blocked=%s" % [name, not hit.is_empty()])
		if not hit.is_empty() and (hit["position"] as Vector3).distance_to(head) > 0.5:
			_invalid("%s: the badge's representative head is behind %s" % [name, hit["collider"]])


## The plate with the head rects (blue) and badge rects (red) outlined.
func _annotated(plate: Image, heads: Dictionary, to_output: float) -> Image:
	var img := plate.duplicate() as Image
	var k := img.get_size().x / (root.get_visible_rect().size.x * to_output)
	for id: int in heads:
		_outline(img, heads[id][0] as Rect2, k, Color(0.1, 0.4, 1.0))
	for b: Dictionary in _views.need_badges():
		_outline(img, b["rect"], k, Color(1.0, 0.1, 0.1))
	return img


func _outline(img: Image, rect: Rect2, k: float, colour: Color) -> void:
	var r := Rect2i(Vector2i(rect.position * k), Vector2i(rect.size * k))
	var bounds := Rect2i(Vector2i.ZERO, img.get_size())
	for edge in [
		Rect2i(r.position, Vector2i(r.size.x, 2)),
		Rect2i(r.position + Vector2i(0, r.size.y - 2), Vector2i(r.size.x, 2)),
		Rect2i(r.position, Vector2i(2, r.size.y)),
		Rect2i(r.position + Vector2i(r.size.x - 2, 0), Vector2i(2, r.size.y)),
	]:
		var clipped := (edge as Rect2i).intersection(bounds)
		if clipped.has_area():
			img.fill_rect(clipped, colour)


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save " + path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


## Zooms in slowly at each yaw while panning, and counts badges over heads.
func _sweep(centre: Vector3) -> void:
	var to_output := root.get_stretch_transform().get_scale().y
	for yaw: float in SWEEP_YAWS:
		var distance := SWEEP_FAR_M
		var step := 0
		while distance >= SWEEP_NEAR_M:
			var pan := sin(step * 0.3) * SWEEP_PAN_M
			_rig.stop_follow()
			_rig.position = Vector3(centre.x + pan, 0.0, centre.z)
			_rig.yaw = yaw
			_rig.distance = distance
			await _frames(2)
			_sweep_steps += 1
			var heads := _head_rects(to_output)
			_sweep_badges += _views.need_badges().size()
			var hit := false
			for b: Dictionary in _views.need_badges():
				var rect: Rect2 = b["rect"]
				var over: Array = []
				for id: int in heads:
					if rect.intersects(heads[id][0]):
						over.append("%d%s" % [id, "s" if heads[id][1] else ""])
				if over.is_empty():
					continue
				# A head mid stand-up: the probe froze the clock just after the
				# needs were set, and NeedIcons.head_top() (like the icon row's
				# anchor, out of this lane's scope) takes the standing head then.
				var rising := 0
				for id: int in heads:
					if rect.intersects(heads[id][0]):
						var stage := _sim.get_passenger(id).stage
						rising += int(stage == Passenger.Stage.STANDING_UP)
				if rising == over.size():
					_sweep_hits_rising += 1
				else:
					_sweep_hits += 1
				hit = true
				for id: int in heads:
					if rect.intersects(heads[id][0]):
						_print_head(id, heads[id][0], to_output)
				var shift: Vector2 = _views.need_clusters._shifts.get(b["id"], Vector2(NAN, NAN))
				print(
					(
						(
							"SWEEP_HIT %s yaw=%.2f distance=%.2f pan=%.2f id=%d kind=%s count=%d"
							+ " rect=%s shift=%s over_heads=%s"
						)
						% [
							_tag,
							yaw,
							distance,
							pan,
							b["id"],
							NeedIcons.Need.keys()[b["kind"]],
							b["count"],
							rect,
							shift,
							over
						]
					)
				)
			if SWEEP_PLATE_M.has(distance):
				var before := _badge_rects()
				var img := await PlateSight.grab(self)
				var again := await _regrab()
				var moved := 0
				for id: int in before:
					moved += int(not again.has(id) or again[id] != before[id])
				var name := "%s_sweep_yaw%.2f_%dm" % [_tag, yaw, int(distance)]
				print("PROBE sweep plate %s hit=%s flicker_changed=%d" % [name, hit, moved])
				_save(img, name + ".png")
				_save(_annotated(img, heads, to_output), name + "_boxes.png")
			distance -= SWEEP_STEP_M
			step += 1


## A head a badge landed on: the bone-measured rect, the rect the game keeps
## badges clear of (NeedIcons.head_top(), as PassengerViews measures it), the
## passenger's stage and its seated metas.
func _print_head(id: int, bone_rect: Rect2, to_output: float) -> void:
	var node := _views.node_for(id)
	var top: Vector3 = node.global_transform * NeedIcons.head_top(node)
	var depth := (top - _cam.global_position).dot(-_cam.global_basis.z)
	var unit := NeedIcons.unit_of(root, _cam)
	var side := minf(PassengerViews.HEAD_RECT_M / (depth * unit), PassengerViews.HEAD_RECT_MAX_PX)
	var at := _cam.unproject_position(top) * to_output
	print(
		(
			"HEAD id=%d bone_rect=%s game_rect=%s stage=%s seated=%s icon_seated=%s reclined=%s"
			% [
				id,
				bone_rect,
				Rect2(at - Vector2(side / 2.0, 0.0), Vector2(side, side)),
				Passenger.Stage.keys()[_sim.get_passenger(id).stage],
				node.get_meta(&"seated", false),
				node.get_meta(&"icon_seated", false),
				node.get_meta(&"icon_reclined", false)
			]
		)
	)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw
