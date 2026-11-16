extends SceneTree
## S8b phase 2 plates: the construction works (board ecd67e67; TaxiwayWorks,
## TaxiwayWorksView). One windowed run:
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/taxiway_works_plates_probe.gd [-- --seed=N]
## Boots main.tscn with a new random world seed (printed), declines the
## new-game incidents question and fills the starter (gate A, north). The clock
## stays paused. It then STAGES the works: a west and an east stand on the
## starter shell's west and east walls (Airside.set_gate_stands, so the paving
## draws both spurs, their connectors and pads), and FlightSim.spur_source set to
## a stub that holds each spur at the floor with a wanted x farther out, so
## FlightSim.spur_pending() is true for both sides and the works view draws them
## through its production path. Then the stub is cleared and runway works to
## medium are begun at the current tick. The forecast time in the hover plate
## is the staged one (no flight holds the side, so it is now); the real forecast
## is tested in test_taxiway_works_hover.gd.
## Plates go under tools/blender/out/s8b_works/ with every HUD CanvasLayer
## hidden (the hover plate keeps the tooltip's layer): per works a play-distance
## shot (the default yaw and the player's angle step) framing the works ground,
## both end cones and the yard, and a close-up from the yard's open side at the
## lowest angle step, the worst case for the hoarding hiding the brick pile.
## Before each save every framed point must project inside the window, and the
## brick pile's top (and in play shots each end cone's top) must have no mesh
## between it and the camera (a control under the ground must report one), else
## PROBE_INVALID, exit 1. A contact sheet of every plate is saved last.

const MAIN := "res://main/main.tscn"
const IntroClose := preload("res://spike/intro_close.gd")
const OUT_REL := "res://../tools/blender/out/s8b_works"
const WEST_DOOR := Vector2i(10, 6)
const EAST_DOOR := Vector2i(21, 4)
## How far out the stub puts each side's wanted spur.
const WEST_PUSH_M := 40.0
const EAST_PUSH_M := 46.0
const MARGIN_PX := 40.0
const FIT_MARGIN_PX := 60.0
const SETTLE_FRAMES := 12
const FIT_FRAMES := 4
const OCCLUSION_STOP_M := 0.3
const PLAY_DISTANCES: Array[float] = [120.0, 160.0, 200.0, 240.0, 300.0, 360.0, 420.0]
const CLOSE_DISTANCES: Array[float] = [26.0, 32.0, 40.0, 50.0, 64.0, 80.0]
const HANG_LIMIT_MS := 60000
const TOTAL_LIMIT_MS := 600000
const SHEET_CELL := Vector2i(640, 360)

var _guard := Thread.new()
var _mutex := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _done := false
var _out_dir := ""
var _main: Node
var _clock: SimClock
var _flights: FlightSim
var _airside: Airside
var _view: TaxiwayWorksView
var _rig: TycoonCamera
var _cam: Camera3D
var _saved: Array[String] = []


func _initialize() -> void:
	_beat("boot")
	_guard.start(_watchdog)
	var world_seed := IntroClose.seed_or_random()
	print("PROBE world_seed=%d" % world_seed)
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=%s" % _out_dir)
	_main = load(MAIN).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(world_seed)
	_flights = _main.get_node("FlightSim")
	root.add_child(_main)
	current_scene = _main
	_clock.set_paused(true)
	_run.call_deferred()


func _run() -> void:
	await _frames(3)
	_airside = _main.get_node("Airside")
	_view = _main.get_node("ApronStand/TaxiwayWorks")
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	var intro_problem := IntroClose.close(_main)
	if intro_problem != "":
		_fail(intro_problem)
		return
	_clock.set_paused(true)
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	await _frames(3)
	_hide_hud(false)
	if not await _side_plates() or not await _runway_plates():
		return
	_sheet()
	print("PROBE_PASS taxiway works plates")
	_finish(0)


func _side_plates() -> bool:
	var grid: BuildGrid = (_main.get_node("BuildMode") as BuildMode).grid
	var at := ReferenceTerminal.offset_on(grid)
	var west_x := grid.origin.x + at.x + WEST_DOOR.x
	var west_z := grid.origin.z + at.y + WEST_DOOR.y + 0.5
	var east_x := grid.origin.x + at.x + EAST_DOOR.x + 1
	var east_z := grid.origin.z + at.y + EAST_DOOR.y + 0.5
	var stands := _airside.gate_stands.duplicate()
	stands["W"] = StandPlacement.make(0, west_x, west_z, StandPlacement.WEST)
	stands["E"] = StandPlacement.make(0, east_x, east_z, StandPlacement.EAST)
	var classes := {}
	for gate: String in stands:
		classes[gate] = PlaneClasses.LARGE
	_airside.set_gate_classes(classes)
	if not _airside.set_gate_stands(stands):
		_fail("the staged west and east stands were refused")
		return false
	var floor_x := StandPlacement.SIDE_LANE_X
	var staged := {
		StandPlacement.WEST: {"x": -floor_x, "wanted": -floor_x - WEST_PUSH_M},
		StandPlacement.EAST: {"x": floor_x, "wanted": floor_x + EAST_PUSH_M},
	}
	_flights.spur_source = func() -> Dictionary: return staged
	await _frames(4)
	print(
		(
			"PROBE stands W %s E %s; pending W %s E %s; layouts %s"
			% [
				stands["W"],
				stands["E"],
				_flights.spur_pending(StandPlacement.WEST),
				_flights.spur_pending(StandPlacement.EAST),
				_view.layouts.keys(),
			]
		)
	)
	for side in [StandPlacement.WEST, StandPlacement.EAST]:
		if not _view.layouts.has(side):
			_fail("no works drawn for pending side %s" % side)
			return false
	var west_yaw := deg_to_rad(90.0)
	var east_yaw := deg_to_rad(-90.0)
	var ok := await _play("works_w_play", StandPlacement.WEST, 1)
	ok = ok and await _close("works_w_close", StandPlacement.WEST, west_yaw)
	ok = ok and await _hover("works_w_hover", StandPlacement.WEST)
	ok = ok and await _play("works_e_play", StandPlacement.EAST, 1)
	ok = ok and await _close("works_e_close", StandPlacement.EAST, east_yaw)
	_flights.spur_source = func() -> Dictionary: return SideSpurs.spurs_at({}, {})
	return ok


func _runway_plates() -> bool:
	_flights.runway.works.begin(Runway.MEDIUM, _flights.tick)
	await _frames(4)
	print(
		(
			"PROBE runway works %s from %d to %d at tick %d; layouts %s"
			% [
				_flights.runway.works.target,
				_flights.runway.works.start,
				_flights.runway.works.finish,
				_flights.tick,
				_view.layouts.keys(),
			]
		)
	)
	if _view.layouts.keys() != [TaxiwayWorksView.RUNWAY]:
		_fail("the runway works are not the only works drawn")
		return false
	if not await _play("works_runway_play", TaxiwayWorksView.RUNWAY, 0):
		return false
	return await _close("works_runway_close", TaxiwayWorksView.RUNWAY, 0.0)


## The prop nodes of works `works`, in layout order.
func _nodes(works: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var root_node := _view.get_node("Works%s" % works.capitalize())
	for child in root_node.get_children():
		if child.name != "Ground":
			out.append(child)
	return out


## The node and footprint centre of the first prop of `kind` in works `works`
## whose centre has the least (`least`) or most `axis` coordinate, among those
## inside `within` when it has an area.
func _pick(works: String, kind: String, axis: int, least: bool, within := Rect2()) -> Array:
	var props: Array = _view.layouts[works]["props"]
	var nodes := _nodes(works)
	var best := -1
	for i in props.size():
		if props[i]["kind"] != kind:
			continue
		if within.has_area() and not within.has_point(props[i]["centre"]):
			continue
		var at: float = (props[i]["centre"] as Vector2)[axis]
		var best_at: float = (props[best]["centre"] as Vector2)[axis] if best >= 0 else 0.0
		if best < 0 or (at < best_at if least else at > best_at):
			best = i
	return [nodes[best], props[best]["centre"]]


## The top centre of `node`'s meshes.
func _top(node: Node3D) -> Vector3:
	var box := _aabb_of(node)
	return box.get_center() + Vector3.UP * box.size.y * 0.5


func _yard_corners(works: String) -> Array:
	var yard: Rect2 = _view.layouts[works]["yard"]
	var out: Array = []
	for corner: Vector2 in [
		yard.position,
		yard.end,
		Vector2(yard.position.x, yard.end.y),
		Vector2(yard.end.x, yard.position.y)
	]:
		out.append(
			Vector3(corner.x, PlaneView.ground_height_at(Vector3(corner.x, 0, corner.y)), corner.y)
		)
	return out


## The play-distance plate of works `works`: the far ground piece's corners,
## its two end cones (along `axis`) and the yard in frame.
func _play(label: String, works: String, axis: int) -> bool:
	_rig.angle_step = TycoonCamera.AngleStep.TOP_DOWN
	var ground: Array = _view.layouts[works]["ground"]
	var piece: Rect2 = ground[ground.size() - 1]
	var framed := _yard_corners(works)
	for corner: Vector2 in [
		piece.position,
		piece.end,
		Vector2(piece.position.x, piece.end.y),
		Vector2(piece.end.x, piece.position.y)
	]:
		framed.append(Vector3(corner.x, 0.2, corner.y))
	var bricks: Array = _pick(works, "bricks", 0, true)
	var first: Array = _pick(works, "cone", axis, true, piece)
	var last: Array = _pick(works, "cone", axis, false, piece)
	var subjects := [
		[_top(bricks[0]), bricks[0]], [_top(first[0]), first[0]], [_top(last[0]), last[0]]
	]
	for subject: Array in subjects:
		framed.append(subject[0])
	print("PROBE %s pieces %s, end cones at %s and %s" % [label, ground, first[1], last[1]])
	await _fit(framed, 0.0, PLAY_DISTANCES)
	return await _plate(label, framed, subjects)


## The close-up of works `works`' yard from its open side (camera yaw `yaw`),
## at the lowest angle step.
func _close(label: String, works: String, yaw: float) -> bool:
	_rig.angle_step = TycoonCamera.AngleStep.LOW
	var framed := _yard_corners(works)
	var bricks: Array = _pick(works, "bricks", 0, true)
	var subjects := [[_top(bricks[0]), bricks[0]]]
	framed.append(subjects[0][0])
	await _fit(framed, yaw, CLOSE_DISTANCES)
	return await _plate(label, framed, subjects)


## The close-up again with the pointer on the yard and the tooltip's layer shown.
func _hover(label: String, works: String) -> bool:
	var hover := HoverTarget.find(self)
	if hover == null:
		_fail("no HoverTarget in the scene")
		return false
	var signs := _view.hover_signs()
	var rect := Rect2()
	for sign_entry: Dictionary in signs:
		if sign_entry["key"] == works:
			rect = sign_entry["rect"]
	if rect.size == Vector2.ZERO:
		_fail("%s: the works yard gave no hover rect" % label)
		return false
	hover.pointer_override = rect.get_center()
	_hide_hud(true)
	await _frames(SETTLE_FRAMES)
	var shown: Variant = hover.shown_target()
	var text: String = shown.text if shown != null else ""
	print("PROBE %s pointer %s rect %s tooltip '%s'" % [label, rect.get_center(), rect, text])
	if not text.contains("forecast at"):
		_fail("%s: the tooltip does not show the forecast time" % label)
		return false
	var bricks: Array = _pick(works, "bricks", 0, true)
	var ok := await _plate(label, _yard_corners(works), [[_top(bricks[0]), bricks[0]]])
	hover.pointer_override = null
	_hide_hud(false)
	return ok


## Hides every HUD CanvasLayer; with `keep_tooltip`, not the one holding the
## hover tooltip (anti_pattern a-plate-probe-s-occlusion-rays-see-only-meshes).
func _hide_hud(keep_tooltip: bool) -> void:
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		var tooltip := not layer.find_children("*", "AnchoredTooltip", true, false).is_empty()
		(layer as CanvasLayer).visible = keep_tooltip and tooltip


func _fit(points: Array, yaw: float, distances: Array[float]) -> void:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point: Vector3 in points:
		low = Vector2(minf(low.x, point.x), minf(low.y, point.z))
		high = Vector2(maxf(high.x, point.x), maxf(high.y, point.z))
	var middle := (low + high) * 0.5
	var frame := root.get_visible_rect().grow(-FIT_MARGIN_PX)
	for distance in distances:
		_rig.position = Vector3(middle.x, 0.0, middle.y)
		_rig.yaw = yaw
		_rig.distance = distance
		_rig.zoom(1.0)
		await _frames(FIT_FRAMES)
		var fits := true
		for point: Vector3 in points:
			if (
				_cam.is_position_behind(point)
				or not frame.has_point(_cam.unproject_position(point))
			):
				fits = false
				break
		print("  FIT distance %.0f (rig %.1f) fits=%s" % [distance, _rig.distance, fits])
		if fits:
			return


## Saves a plate once every `framed` point projects inside the window and no
## mesh but its own node hides each subject ([point, node]).
func _plate(label: String, framed: Array, subjects: Array) -> bool:
	_stage = "plate %s" % label
	await _frames(SETTLE_FRAMES)
	var view := root.get_visible_rect()
	print(
		(
			"PLATE %s rig %s distance %.1f yaw %.0f pitch %.0f camera %s"
			% [
				label,
				_rig.position,
				_rig.distance,
				rad_to_deg(_rig.yaw),
				_rig.pitch_degrees(),
				_cam.global_position
			]
		)
	)
	var control := _occluder(Vector3(_rig.position.x, -2.0, _rig.position.z))
	print("  CONTROL under the ground: %s" % (control if control != "" else "clear"))
	if control == "":
		_fail("%s: the occlusion control found nothing" % label)
		return false
	var ok := true
	var points: Array = framed.duplicate()
	for subject: Array in subjects:
		points.append(subject[0])
	for point: Vector3 in points:
		var p := _cam.unproject_position(point)
		var in_frame := view.grow(-MARGIN_PX).has_point(p) and not _cam.is_position_behind(point)
		print("  FRAMED %s -> %s in_frame=%s" % [point, p, in_frame])
		ok = ok and in_frame
	for subject: Array in subjects:
		var occluder := _occluder(subject[0], subject[1])
		print(
			(
				"  OCCLUSION %s %s: %s"
				% [subject[1].name, subject[0], occluder if occluder != "" else "clear"]
			)
		)
		ok = ok and occluder == ""
	if not ok:
		_fail("%s: a subject check failed" % label)
		return false
	await RenderingServer.frame_post_draw
	var path := _out_dir.path_join(label + ".png")
	var err := root.get_texture().get_image().save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	if err != OK:
		_fail("%s: not saved" % label)
		return false
	_saved.append(path)
	return true


func _sheet() -> void:
	var columns := 3
	var rows := ceili(float(_saved.size()) / columns)
	var sheet := Image.create(SHEET_CELL.x * columns, SHEET_CELL.y * rows, false, Image.FORMAT_RGB8)
	for i in _saved.size():
		var image := Image.load_from_file(_saved[i])
		image.convert(Image.FORMAT_RGB8)
		image.resize(SHEET_CELL.x, SHEET_CELL.y)
		var at := Vector2i(i % columns * SHEET_CELL.x, floori(float(i) / columns) * SHEET_CELL.y)
		sheet.blit_rect(image, Rect2i(Vector2i.ZERO, SHEET_CELL), at)
	var path := _out_dir.path_join("works_contact_sheet.png")
	print("PLATE sheet %s err=%d" % [path, sheet.save_png(path)])


func _aabb_of(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for found in node.find_children("*", "MeshInstance3D", true, false):
		var instance := found as MeshInstance3D
		if instance.mesh == null or not instance.is_visible_in_tree():
			continue
		var bounds: AABB = instance.global_transform * instance.get_aabb()
		box = bounds if first else box.merge(bounds)
		first = false
	return box


func _occluder(subject: Vector3, own: Node = null) -> String:
	var from := _cam.global_position
	var to := subject + (from - subject).normalized() * OCCLUSION_STOP_M
	var ghost := _main.get_node("BuildMode/Ghost")
	var best := ""
	var best_distance := INF
	for node in _main.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null or not instance.is_visible_in_tree() or ghost.is_ancestor_of(node):
			continue
		if own != null and (own == node or own.is_ancestor_of(node)):
			continue
		var material := instance.material_override
		if material == null and instance.mesh.get_surface_count() > 0:
			material = instance.get_active_material(0)
		var base := material as BaseMaterial3D
		if base != null and base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var xform := instance.global_transform
		if (xform * instance.get_aabb()).intersects_segment(from, to) == null:
			continue
		var inverse := xform.affine_inverse()
		var hit: Dictionary = instance.mesh.generate_triangle_mesh().intersect_segment(
			inverse * from, inverse * to
		)
		if hit.is_empty():
			continue
		var world_hit: Vector3 = xform * (hit["position"] as Vector3)
		var distance := from.distance_to(world_hit)
		if distance < best_distance:
			best_distance = distance
			best = "%s at %s" % [instance.get_path(), world_hit]
	return best


func _frames(count: int) -> void:
	for i in count:
		_beat(_stage)
		await process_frame


func _beat(stage: String) -> void:
	_mutex.lock()
	_beat_ms = Time.get_ticks_msec()
	_stage = stage
	_mutex.unlock()


func _watchdog() -> void:
	var started := Time.get_ticks_msec()
	while true:
		OS.delay_msec(500)
		_mutex.lock()
		var done := _done
		var beat := _beat_ms
		var stage := _stage
		_mutex.unlock()
		if done:
			return
		var now := Time.get_ticks_msec()
		if now - beat > HANG_LIMIT_MS or now - started > TOTAL_LIMIT_MS:
			print(
				(
					"PROBE_INVALID hang in stage '%s': %d ms since the last beat, %d ms in all"
					% [stage, now - beat, now - started]
				)
			)
			OS.crash("taxiway works plates probe hung")


func _fail(reason: String) -> void:
	print("PROBE_INVALID %s" % reason)
	_finish(1)


func _finish(code: int) -> void:
	_mutex.lock()
	_done = true
	_mutex.unlock()
	if _guard.is_started():
		_guard.wait_to_finish()
	if _main != null:
		_main.queue_free()
	quit(code)
