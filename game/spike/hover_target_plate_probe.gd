extends SceneTree
## Windowed plates for HoverTarget and its AnchoredTooltip (decision calm-view-
## technical-design-shared-hover-target-reusing-click, parts 1-2): the real main
## scene with the starter terminal built.
## Plate 1: a test sign (FakeSignProvider, a 32 px rect over the first check-in
## desk, outlined by a probe-only frame) hovered, with its cream tooltip beside it.
## Plate 2: a spawned passenger hovered, with a probe-only tooltip text (lane B
## owns real passenger text).
## Boots main with a new random sim seed (printed). Before each plate it proves
## its subject: the hover target is that subject; the anchor projects inside the
## frame with a margin; the subject point is in line of sight (a raycast against
## the passenger and the built meshes, with a control ray into the desk that must
## come back blocked); the tooltip shows, is inside the viewport by HudLayout.MARGIN
## and does not cover its anchor. It prints the rects and points it compared.
## Otherwise it prints PROBE_INVALID and exits 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy --resolution 1536x864 \
##     --path game -s res://spike/hover_target_plate_probe.gd
##
## The plates go to tools/blender/out/hover_target_20261114/.

const PlateSight := preload("res://spike/plate_sight.gd")
const FakeSigns := preload("res://tests/ui/fake_sign_provider.gd")
const OUT_REL := "res://../tools/blender/out/hover_target_20261114"
const MAIN_SCENE := "res://main/main.tscn"
const FLIGHT_ID := "GMF101"
const MARGIN_PX := 24.0
const SIGN_PX := 32.0
## Where a station sign floats over its desk, in metres.
const SIGN_HEIGHT_M := 2.2
## No collider carries this tag, so a hit is a blocker or past, never the subject.
const NO_TAG := "no-subject"

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


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
	(main.get_node("TycoonCamera") as TycoonCamera).set_process(false)
	await _frames(10)
	var hover := main.get_node("HoverTarget") as HoverTarget
	var cam: Camera3D = main.get_node("TycoonCamera/Camera3D")
	await _sign_plate(main, hover, cam, build_mode, out_dir)
	await _passenger_plate(main, hover, cam, build_mode, out_dir)
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _sign_plate(
	main: Node, hover: HoverTarget, cam: Camera3D, build_mode: BuildMode, out_dir: String
) -> void:
	var sim: PassengerSim = main.get_node("PassengerSim")
	var desk: int = sim.layout.desks[0]
	var centre := build_mode.grid.cell_to_world(build_mode.grid.get_object(desk)["anchor"])
	cam.look_at_from_position(centre + Vector3(-3.0, 12.0, 9.0), centre)
	var point := centre + Vector3(0.0, SIGN_HEIGHT_M, 0.0)
	var at := cam.unproject_position(point)
	var rect := Rect2(at - Vector2.ONE * SIGN_PX / 2.0, Vector2.ONE * SIGN_PX)
	var signs := FakeSigns.new()
	signs.add(&"probe_desk", rect, "Waiting for staff: no check-in agent free")
	hover.register_provider(signs)
	var layer := CanvasLayer.new()
	var outline := Panel.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1.0, 0.85, 0.3, 0.35)
	box.set_border_width_all(2)
	box.border_color = Color(0.1, 0.13, 0.26)
	outline.add_theme_stylebox_override(&"panel", box)
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outline.position = rect.position
	outline.size = rect.size
	layer.add_child(outline)
	main.add_child(layer)
	hover.pointer_override = rect.get_center()
	await _frames(4)
	var target := hover.hovered_target()
	print("SIGN desk=%d point=%s rect=%s" % [desk, point, rect])
	if target == null or target.kind != HoverTarget.Kind.SIGN or target.key != &"probe_desk":
		_invalid("the hovered target is not the test sign: %s" % target)
	_check_in_frame(cam, point, "sign")
	_check_sight(main, cam, point, [], NO_TAG, centre + Vector3(0.0, 0.3, 0.0), true)
	_check_tooltip(hover, rect, "sign")
	await _save(out_dir.path_join("01_hovered_sign_tooltip.png"))
	hover.unregister_provider(signs)
	layer.queue_free()


func _passenger_plate(
	main: Node, hover: HoverTarget, cam: Camera3D, build_mode: BuildMode, out_dir: String
) -> void:
	var sim: PassengerSim = main.get_node("PassengerSim")
	var views: PassengerViews = main.get_node("PassengerViews")
	var id := sim.spawn_now(FLIGHT_ID)
	views.sync()
	await _frames(2)
	var node := views.node_for(id)
	if node == null:
		_invalid("the spawned passenger %d has no view" % id)
		return
	var feet := node.position
	cam.look_at_from_position(feet + Vector3(-2.0, 9.0, 7.0), feet + Vector3.UP)
	hover.passenger_text = func(pid: int) -> String: return "Passenger %d (probe text)" % pid
	var head := feet + Vector3(0.0, PassengerViews.BODY_HEIGHT_M, 0.0)
	hover.pointer_override = cam.unproject_position(feet + Vector3.UP)
	await _frames(4)
	print("PASSENGER id=%d feet=%s pointer=%s" % [id, feet, hover.pointer_override])
	if hover.hovered_passenger() != id:
		_invalid("the hovered passenger is %d, not %d" % [hover.hovered_passenger(), id])
	_check_in_frame(cam, head, "passenger head")
	var desk: int = sim.layout.desks[0]
	var desk_centre := build_mode.grid.cell_to_world(build_mode.grid.get_object(desk)["anchor"])
	_check_sight(
		main,
		cam,
		feet + Vector3(0.0, 1.4, 0.0),
		[node],
		"subject",
		desk_centre + Vector3.UP * 0.3,
		false
	)
	var anchor := Rect2(cam.unproject_position(head), Vector2.ZERO)
	_check_tooltip(hover, anchor, "passenger")
	await _save(out_dir.path_join("02_hovered_passenger_tooltip.png"))
	hover.passenger_text = Callable()


func _check_in_frame(cam: Camera3D, point: Vector3, what: String) -> void:
	var at := cam.unproject_position(point)
	var frame := root.get_visible_rect().grow(-MARGIN_PX)
	print("FRAME %s at=%s frame=%s behind=%s" % [what, at, frame, cam.is_position_behind(point)])
	if cam.is_position_behind(point) or not frame.has_point(at):
		_invalid("%s is not inside the frame" % what)


## A sight line to `point` against the subject `owners` (tagged `tag`) and the
## built meshes: it must land on the subject (or reach the point with no hit when
## `in_air`) with no blocker. A control line into `blocked_at` must be blocked.
func _check_sight(
	main: Node,
	cam: Camera3D,
	point: Vector3,
	owners: Array,
	tag: String,
	blocked_at: Vector3,
	in_air: bool
) -> void:
	var all: Array[Node] = [main.get_node("BuildMode/BuildView")]
	var subjects := {}
	for owner: Node in owners:
		all.append(owner)
		subjects[owner] = tag
	var holder := PlateSight.colliders(root, all, subjects)
	var space := cam.get_world_3d().direct_space_state
	var targets: Array[Vector3] = [point]
	var lines := PlateSight.sight_lines(space, cam.global_position, targets, tag)
	var controls: Array[Vector3] = [blocked_at]
	var control := PlateSight.sight_lines(space, cam.global_position, controls, NO_TAG)
	holder.queue_free()
	var landed: Array = lines["on_subject"]
	print(
		(
			"SIGHT tag=%s on=%d past=%d blockers=%s control_blockers=%s"
			% [tag, landed.size(), lines["past"], lines["blockers"], control["blockers"]]
		)
	)
	if (control["blockers"] as Array).is_empty():
		_invalid("the control line into the desk was not blocked: the colliders are not engaged")
	if not (lines["blockers"] as Array).is_empty():
		_invalid("the subject is hidden behind %s" % lines["blockers"])
	if not in_air and landed.is_empty():
		_invalid("no sight line lands on the subject")


func _check_tooltip(hover: HoverTarget, anchor: Rect2, what: String) -> void:
	var tip := hover.tooltip()
	var rect := tip.get_global_rect()
	var room := root.get_visible_rect().grow(-HudLayout.MARGIN)
	print(
		(
			"TOOLTIP %s visible=%s rect=%s anchor=%s text='%s'"
			% [what, tip.visible, rect, anchor, tip.text()]
		)
	)
	if not tip.visible or tip.text() == "":
		_invalid("the %s tooltip does not show" % what)
	if not room.encloses(rect):
		_invalid("the %s tooltip is outside the viewport margin" % what)
	if rect.intersects(anchor) or rect.has_point(anchor.position):
		_invalid("the %s tooltip covers its anchor" % what)
	if rect.position.distance_to(anchor.get_center()) > 400.0:
		_invalid("the %s tooltip is far from its anchor" % what)


func _save(path: String) -> void:
	var img := await PlateSight.grab(self)
	img.save_png(path)
	print("PLATE ", path, " size=", img.get_size())
