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
##
## The plates go to tools/blender/out/flight_planner_20261114/.

const OUT_REL := "res://../tools/blender/out/flight_planner_20261114"
const GATE_THEME_REL := "res://../tools/blender/out/gate_theme_20261114"
const SCALES := [1.0, 1.25, 1.5]

var _main: Node3D
var _out_dir: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gate_theme_only := "--gate-theme" in OS.get_cmdline_user_args()
	var out_rel := GATE_THEME_REL if gate_theme_only else OUT_REL
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
