extends SceneTree
## Windowed plates of the flight planner (decision flight-planner-a-full-screen-
## day-planner-with-one-row-per-ga). The real main.tscn boots with three gates
## (A, B, C) and four contracts: 10:00 Oslo and 20:00 Paris on gate A, 11:00 Rome
## on B, 14:00 London on A or B as the gates allow. The planner opens at UI scale
## 1.0, 1.25 and 1.5 on a 1920x1080 window, and once more with a bar selected so
## the Move to choices show, then the Departures list's Gate buttons are plated
## with the sheet closed.
## Every plate first proves the sheet, a bar and the Planner toggle project into
## the view; on failure it prints PROBE_INVALID and exits 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://tests/ui/flight_planner_plates_probe.gd
## With `-- --gate-theme` it plates the Departures list, the planner and a selected bar
## at UI scale 1.25, to tools/blender/out/gate_theme_20261114/.
## With `-- --drag` it plates a drag in progress at UI scale 1.0: the 11:00 Rome bar
## (gate B) picked up with real mouse events pushed into the window, held over gate
## A's row (refused, the 10:00 Oslo flight clashes) and then over gate C's (fits),
## to tools/blender/out/planner_drag_20261114/. Each plate first proves the drag is
## in progress, the pointer is in view and A is greyed while C is not. Keep the
## real mouse off the window while it runs, or its motion moves the drag.
##
## The plates go to tools/blender/out/flight_planner_20261114/.

const OUT_REL := "res://../tools/blender/out/flight_planner_20261114"
const GATE_THEME_REL := "res://../tools/blender/out/gate_theme_20261114"
const DRAG_REL := "res://../tools/blender/out/planner_drag_20261114"
const SCALES := [1.0, 1.25, 1.5]

var _main: Node3D
var _out_dir: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gate_theme_only := "--gate-theme" in OS.get_cmdline_user_args()
	var drag_only := "--drag" in OS.get_cmdline_user_args()
	var out_rel := GATE_THEME_REL if gate_theme_only else OUT_REL
	if drag_only:
		out_rel = DRAG_REL
	_out_dir = ProjectSettings.globalize_path(out_rel).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	var clock := _main.get_node("SimClock") as SimClock
	var world_seed := randi()
	clock.seed_rng(world_seed)
	print("PROBE sim_seed=", world_seed)
	root.add_child(_main)
	clock.set_paused(true)
	await _frames(5)
	var flights := _main.get_node("FlightSim") as FlightSim
	flights.gate_source = func() -> Array[String]: return ["A", "B", "C"] as Array[String]
	flights.stand_source = Callable()
	if flights.opened_tick < 0:
		flights.open_airport()
	for spec: Array in [
		["P1", 600, "Oslo", "Gotta Air"],
		["P2", 660, "Rome", "Sunhop"],
		["P3", 840, "London", "Gotta Air"],
		["P4", 1200, "Paris", "Sunhop"],
	]:
		var terms := TestFlightContracts.terms(spec[0], spec[1])
		terms["destination"] = spec[2]
		terms["airline"] = spec[3]
		terms["plane_size"] = "small"
		terms["booked_passengers"] = 12
		print("PROBE contract ", spec[0], " accepted=", flights.accept_contract(terms))
		print("PROBE   gate=", flights.contract_of(spec[0]).get("gate", "-"))
	var planner := _main.find_child("FlightPlanner", true, false) as FlightPlanner
	if planner == null:
		print("PROBE_INVALID no FlightPlanner in the HUD")
		quit(1)
		return
	if gate_theme_only:
		await _run_gate_theme(planner)
		return
	if drag_only:
		await _run_drag(planner)
		return
	for ui_scale: float in SCALES:
		root.content_scale_factor = ui_scale
		planner.open()
		await _frames(8)
		if not await _plate(planner, "planner_s%d" % roundi(ui_scale * 100.0)):
			return
		planner.close()
	root.content_scale_factor = 1.0
	planner.open()
	await _frames(4)
	var bar := planner.bar_button("P2", 0)
	bar.pressed.emit()
	await _frames(8)
	print("PROBE selected summary='%s'" % planner.summary_text())
	if not await _plate(planner, "planner_selected_s100"):
		return
	planner.close()
	await _frames(6)
	if not await _plate_toggle_only(planner, "departures_gate_colours_s100"):
		return
	quit(0)


## The gate colour plates at UI scale 1.25: the Departures list, the open planner
## and the planner with a bar selected (its Move to choices show).
func _run_gate_theme(planner: FlightPlanner) -> void:
	root.content_scale_factor = 1.25
	await _frames(8)
	if not await _plate_toggle_only(planner, "departures_gate_colours_s125"):
		return
	planner.open()
	await _frames(8)
	if not await _plate(planner, "planner_s125"):
		return
	planner.bar_button("P2", 0).pressed.emit()
	await _frames(8)
	if await _plate(planner, "planner_selected_s125"):
		quit(0)


## Picks up the Rome bar with pushed mouse events and plates it over a refused
## row (A) and a fitting row (C), then lets go over the hour labels.
func _run_drag(planner: FlightPlanner) -> void:
	root.content_scale_factor = 1.0
	planner.open()
	await _frames(8)
	var bar := planner.bar_button("P2", 0)
	var track_a := planner.part("Track_A") as PlannerTrack
	var track_c := planner.part("Track_C") as PlannerTrack
	if bar == null or track_a == null or track_c == null:
		print("PROBE_INVALID no Rome bar or no row for gate A or C")
		quit(1)
		return
	var start := bar.get_global_rect().get_center()
	await _mouse_motion(start, start, 0)
	await _mouse_button(start, true)
	await _mouse_motion(start + Vector2(40.0, 0.0), start, MOUSE_BUTTON_MASK_LEFT)
	var spots := [
		["planner_drag_refused_s100", track_a, _lane_point(track_a, 13.0)],
		["planner_drag_fitting_s100", track_c, _lane_point(track_c, 12.0)],
	]
	var last := start + Vector2(40.0, 0.0)
	for spot: Array in spots:
		var at: Vector2 = spot[2]
		await _mouse_motion(at, last, MOUSE_BUTTON_MASK_LEFT)
		await _mouse_motion(at + Vector2(1.0, 0.0), at, MOUSE_BUTTON_MASK_LEFT)
		last = at + Vector2(1.0, 0.0)
		await _frames(4)
		if not _drag_in_view(planner, spot[1], last, track_a, track_c):
			return
		if not _save(spot[0]):
			return
	var hours := planner.part("Hours").get_global_rect().get_center()
	await _mouse_motion(hours, last, MOUSE_BUTTON_MASK_LEFT)
	await _mouse_button(hours, false)
	var rome: String = planner.flights.contract_of("P2")["gate"]
	print("PROBE after release dragging=", root.gui_is_dragging(), " rome gate=", rome)
	quit(0)


## Proves a drag is in progress, the pointer is in view over `over`, and the
## refused row A is greyed while the fitting row C is not.
func _drag_in_view(
	planner: FlightPlanner,
	over: PlannerTrack,
	at: Vector2,
	track_a: PlannerTrack,
	track_c: PlannerTrack,
) -> bool:
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var row := over.get_global_rect()
	print(
		(
			"PROBE drag over %s at=%s row=%s dragging=%s A greyed=%s C greyed=%s message='%s'"
			% [
				over.name,
				at,
				row,
				root.gui_is_dragging(),
				track_a.is_greyed(),
				track_c.is_greyed(),
				planner.message_text(),
			]
		)
	)
	if not root.gui_is_dragging() or not view.has_point(at) or not row.has_point(at):
		print("PROBE_INVALID the drag is not in progress over %s in view" % over.name)
		quit(1)
		return false
	if not track_a.is_greyed() or track_c.is_greyed():
		print("PROBE_INVALID gate A should be greyed and gate C not")
		quit(1)
		return false
	return true


## A point on `track` at `hour`, half way down the row, in window coordinates.
func _lane_point(track: Control, hour: float) -> Vector2:
	var rect := track.get_global_rect()
	return Vector2(rect.position.x + rect.size.x * hour / 24.0, rect.get_center().y)


func _mouse_motion(at: Vector2, from: Vector2, mask: int) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = at - from
	event.button_mask = mask
	root.push_input(event, true)
	await _frames(2)


func _mouse_button(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = at
	event.global_position = at
	root.push_input(event, true)
	await _frames(2)


## Proves the sheet, a bar centre and the toggle are in view, then saves.
func _plate(planner: FlightPlanner, plate_name: String) -> bool:
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var sheet := planner.sheet().get_global_rect()
	var bars := planner.bar_buttons()
	print("PROBE %s view=%s sheet=%s bars=%d" % [plate_name, view, sheet, bars.size()])
	if not planner.is_open() or bars.size() < 3 or not view.encloses(sheet):
		print("PROBE_INVALID the sheet is not open and in view")
		quit(1)
		return false
	for bar in bars:
		var centre := bar.get_global_rect().get_center()
		print("PROBE   %s centre=%s inside=%s" % [bar.name, centre, view.has_point(centre)])
		if not view.has_point(centre):
			print("PROBE_INVALID bar %s outside the view" % bar.name)
			quit(1)
			return false
	return _save(plate_name)


## The closed sheet: the Departures list with its coloured Gate buttons.
func _plate_toggle_only(planner: FlightPlanner, plate_name: String) -> bool:
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var toggle := planner.toggle_button().get_global_rect()
	var gate_buttons := _main.find_children("Gate_*", "Button", true, false)
	print("PROBE %s toggle=%s gate buttons=%d" % [plate_name, toggle, gate_buttons.size()])
	if planner.is_open() or gate_buttons.size() < 3 or not view.encloses(toggle):
		print("PROBE_INVALID the Departures list is not showing its gate buttons")
		quit(1)
		return false
	for button: Button in gate_buttons:
		var box := button.get_theme_stylebox("normal") as StyleBoxFlat
		var fill := box.bg_color
		print("PROBE   %s '%s' fill=%s" % [button.name, button.text, fill])
	return _save(plate_name)


func _save(plate_name: String) -> bool:
	var path := _out_dir.path_join("%s.png" % plate_name)
	var saved := root.get_texture().get_image().save_png(path)
	print("PLATE saved ", path, " err=", saved)
	if saved != OK:
		print("PROBE_INVALID the plate could not be written")
		quit(1)
		return false
	return true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw
