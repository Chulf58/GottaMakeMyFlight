extends SceneTree
## Windowed plate of the FlightPlanner End confirm for an Exit fee contract
## (decision odd-hours-and-exit-fee-offer-traits-odd-hours-widens-the-dep,
## departures-live-ops-drawer-and-actionable-on-time-hud-stat), at UI scale
## 1.25 and 1.5. The real main.tscn boots; the airport opens on one gate, C, with
## a big Exit fee contract at 10:00 (Exit fee $120), opens FlightPlanner (P),
## selects the bar, and presses End. Prints the question and checks it reads
## "End this contract? Exit fee $120" and is inside the view before saving.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/departures_exit_fee_plate_probe.gd
##
## The plates go to tools/blender/out/offer_traits3_20261114/.

const OUT_REL := "res://../tools/blender/out/offer_traits3_20261114"
const EXIT := {"up": "loyal_airline", "down": "exit_fee", "level": 2}
const EXPECTED := "End this contract? Exit fee $120"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out_dir := ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var main: Node3D = (load("res://main/main.tscn") as PackedScene).instantiate()
	var clock := main.get_node("SimClock") as SimClock
	var world_seed := randi()
	clock.seed_rng(world_seed)
	print("PROBE sim_seed=", world_seed)
	root.add_child(main)
	clock.set_paused(true)
	await _frames(5)
	var flights := main.get_node("FlightSim") as FlightSim
	var planners := main.find_children("*", "FlightPlanner", true, false)
	if planners.is_empty():
		print("PROBE_INVALID no FlightPlanner in main.tscn")
		quit(1)
		return
	flights.gate_source = func() -> Array[String]: return ["C"] as Array[String]
	flights.stand_source = Callable()
	if flights.opened_tick < 0:
		flights.open_airport()
	var terms := TestFlightFit.terms("XF", 600)
	terms["traits"] = EXIT
	print("PROBE contract XF at 10:00 accepted=", flights.accept_contract(terms))
	var planner := planners[0] as FlightPlanner
	var confirm := await _open_confirm(planner, clock, flights)
	if confirm == null:
		return
	for ui_scale: float in [1.25, 1.5]:
		root.content_scale_factor = ui_scale
		await _frames(8)
		var rect := confirm.get_global_rect()
		var view := root.get_visible_rect()
		var inside := view.grow(-4.0).encloses(rect) and confirm.is_visible_in_tree()
		print("PROBE scale=%.2f confirm=%s view=%s inside=%s" % [ui_scale, rect, view, inside])
		if not inside:
			print("PROBE_INVALID the End confirm is not in view")
			quit(1)
			return
		var img := root.get_texture().get_image()
		var path := out_dir.path_join("end_exit_fee_s%d.png" % int(ui_scale * 100.0))
		var saved := img.save_png(path)
		print("PLATE saved ", path, " size=", img.get_size(), " err=", saved)
		if saved != OK:
			print("PROBE_INVALID the plate could not be written")
			quit(1)
			return
	quit(0)


func _open_confirm(planner: FlightPlanner, clock: SimClock, flights: FlightSim) -> Control:
	planner.open()
	await _frames(3)
	var day := GameCalendar.day_of(clock.tick, 0)
	var bar := planner.bar_button("XF", day)
	if bar == null:
		bar = planner.bar_button("XF", day + 1)
	if bar == null:
		print("PROBE_INVALID no XF bar in FlightPlanner")
		quit(1)
		return null
	bar.pressed.emit()
	await _frames(3)
	var end := planner.part("EndContract") as Button
	if end == null:
		print("PROBE_INVALID no End button for the XF bar")
		quit(1)
		return null
	end.pressed.emit()
	await _frames(3)
	var prompt := planner.part("EndPrompt") as Label
	if prompt == null:
		print("PROBE_INVALID End opened no confirm")
		quit(1)
		return null
	var text := prompt.text
	print("PROBE end prompt '%s' expected '%s' fee=%d" % [text, EXPECTED, flights.end_fee("XF")])
	if text != EXPECTED:
		print("PROBE_INVALID the End confirm does not show the Exit fee")
		quit(1)
		return null
	return planner.part("PlannerActions")


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw
