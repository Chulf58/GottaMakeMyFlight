extends SceneTree
## Windowed plate probe for the departures board's soft "N running late" line
## (board 7f89cf1e) on the real main.tscn: the starter terminal, one open flight
## with passengers, some flagged Passenger.late. It proves the flight's row shows
## "N running late" with the count LateCount reads from the sim, that the line
## lies inside the window and the board's panel, then saves the full frame and a
## crop of the left column. A failed check prints PROBE_INVALID and exits 1.
##
## Run (one windowed Godot run project-wide; hold the windowed lock):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game -s res://tests/ui/late_count_plate_probe.gd

const OUT_REL := "res://../tools/blender/out/late_count_20261114"
const PASSENGERS := 5
const LATE := 3
const MARGIN_PX := 8.0

var _failed := false


func _initialize() -> void:
	var probe_seed := randi()
	seed(probe_seed)
	print("PROBE seed=", probe_seed)
	_run.call_deferred()


func _run() -> void:
	var main: Node3D = (load("res://main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	var hud := main.get_node("PassengerHud") as PassengerHud
	await _frames(3)
	hud.dismiss_intro()
	hud.press_starter_terminal()
	await _frames(5)
	var gate := main.get_node("AirportGate") as AirportGate
	print("PROBE airport open=%s" % gate.open())
	var contracts := hud.flights.contract_ids()
	print("PROBE contracts=%s" % [contracts])
	var flight_id := FlightTimetable.occurrence_id(contracts[0], 0)
	while not hud.flights.flight_ids().has(flight_id) and hud.clock.tick < 3000:
		hud.clock.advance(SimClock.STEP)
	print("PROBE flights=%s tick=%d" % [hud.flights.flight_ids(), hud.clock.tick])
	if not hud.flights.flight_ids().has(flight_id):
		_invalid("the flight was not issued")
		quit(1)
		return
	# Hold the clock so the sim does not recompute lateness between the flags and
	# the board's read: the starter terminal has no staff, so the sim itself
	# would call nobody late. The flagged passengers are what the board counts.
	hud.clock.set_paused(true)
	var ids: Array[int] = []
	for i in PASSENGERS:
		ids.append(hud.sim.spawn_now(flight_id))
	hud.clock.advance(SimClock.STEP)
	for i in LATE:
		hud.sim.get_passenger(ids[i]).late = true
	await _frames(10)
	var counts := LateCount.by_flight(hud.sim)
	print("PROBE flight=%s counts=%s tick=%d" % [flight_id, counts, hud.sim.tick])
	var board := hud.get_node("DeparturesBoard") as DeparturesBoard
	var late_now: int = counts.get(flight_id, 0)
	if late_now <= 0:
		_invalid("no passenger is late after the tick, so the plate shows nothing")
	var line := board.find_child("Airline*", true, false) as Label
	if line == null:
		_invalid("the board has no line 2 for the flight")
	else:
		var rect := line.get_global_rect()
		var panel := board.find_child("DeparturesPanel", true, false) as Control
		print("PROBE line2='%s' rect=%s panel=%s" % [line.text, rect, panel.get_global_rect()])
		if not line.text.contains("%d running late" % late_now):
			_invalid("line 2 '%s' does not say '%d running late'" % [line.text, late_now])
		if not root.get_visible_rect().grow(-MARGIN_PX).encloses(rect):
			_invalid("line 2 is not inside the window")
		if not panel.get_global_rect().encloses(rect):
			_invalid("line 2 is not inside the board's panel")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var out_dir := ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var full := out_dir.path_join("late_count_full.png")
	var crop := out_dir.path_join("late_count_board.png")
	var left := image.get_region(Rect2i(0, 320, 420, 270))
	left.resize(left.get_width() * 2, left.get_height() * 2, Image.INTERPOLATE_NEAREST)
	for pair: Array in [[image, full], [left, crop]]:
		var err := (pair[0] as Image).save_png(pair[1])
		print("PLATE saved %s err=%d" % [pair[1], err])
		if err != OK:
			_invalid("the plate did not save (error %d)" % err)
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _invalid(why: String) -> void:
	_failed = true
	print("PROBE_INVALID: ", why)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
