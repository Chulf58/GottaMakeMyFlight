extends SceneTree
## Windowed plates of the flights UI with pseudolocalization on (PseudoLocale,
## expansion 0.4): the flight planner (closed-sheet and a bar selected), the
## Departures board (with the Move to picker and with the End question open), the
## offers sheet, the runway card and a flight result card. The real main.tscn
## boots with the three gates A, B and C and four contracts. Before each save it
## proves its subject: the plated controls lie inside the window and a label of
## the subject starts with "[" (so the text was routed), otherwise it prints
## PROBE_INVALID and exits 1. It also prints every Label or Button of the subject
## whose text is wider than the room it was given (a clipped label). A guard
## thread prints PROBE_INVALID and calls OS.crash() past LIMIT_MS.
##
## Run (windowed takes the one project-wide slot):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy --path <worktree>/game \
##     -s res://locale/t4_pseudolocale_probe.gd
## The plates go to tools/blender/out/locale/t4/.

const OUT_REL := "res://../tools/blender/out/locale/t4"
const LIMIT_MS := 180000
const WINDOW := Vector2i(1920, 1080)

var _out_dir := ""
var _failed := false
var _start_ms := 0
var _guard := Thread.new()
var _lock := Mutex.new()
var _stop := false
var _main: Node3D


func _initialize() -> void:
	_start_ms = Time.get_ticks_msec()
	_guard.start(_watch)
	_run.call_deferred()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_lock.lock()
		var stop := _stop
		_lock.unlock()
		if stop:
			return
		if Time.get_ticks_msec() - _start_ms > LIMIT_MS:
			print("PROBE_INVALID: the probe ran past %d ms" % LIMIT_MS)
			OS.crash("t4_pseudolocale_probe: no finish within %d ms" % LIMIT_MS)


func _finish() -> void:
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()


func _run() -> void:
	var world_seed := randi()
	print("PROBE world_seed=%d display=%s" % [world_seed, DisplayServer.get_name()])
	if DisplayServer.get_name() == "headless":
		print("PROBE_INVALID: run it windowed")
		_finish()
		quit(1)
		return
	PseudoLocale.enable()
	await _plates(world_seed)
	PseudoLocale.disable()
	print("PROBE done failed=%s" % _failed)
	_finish()
	quit(1 if _failed else 0)


func _plates(world_seed: int) -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(WINDOW)
	await _frames(5)
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	var clock := _main.get_node("SimClock") as SimClock
	clock.seed_rng(world_seed)
	root.add_child(_main)
	clock.set_paused(true)
	await _frames(8)
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
	await _frames(4)
	await _planner()
	await _board()
	await _offers()
	await _runway()
	await _result()
	_main.queue_free()
	await _frames(3)


func _planner() -> void:
	var planner := _main.find_child("FlightPlanner", true, false) as FlightPlanner
	_expect(planner != null, "no FlightPlanner")
	planner.open()
	await _frames(8)
	await _plate("a_planner", planner, [planner.part("PlannerTitle")])
	planner.bar_button("P2", 0).pressed.emit()
	await _frames(8)
	print("PLATE planner summary='%s'" % planner.summary_text())
	await _plate("b_planner_selected", planner, [planner.part("PlannerSummary")])
	planner.close()
	await _frames(4)


func _board() -> void:
	var board := _main.find_child("DeparturesBoard", true, false) as DeparturesBoard
	_expect(board != null, "no DeparturesBoard")
	board.set_shown(true)
	await _frames(8)
	var gate := board.gate_button("P2", 0)
	_expect(gate != null, "no gate button for P2")
	gate.pressed.emit()
	await _frames(6)
	await _plate("c_departures_picker", board, [board.find_child("PickerNote", true, false)])
	board.end_button("P2", 0).pressed.emit()
	await _frames(6)
	await _plate("d_departures_end", board, [board.confirm_end_button()])


func _offers() -> void:
	var panel := _main.find_child("OfferPanel", true, false) as OfferPanel
	_expect(panel != null, "no OfferPanel")
	panel.open()
	await _frames(10)
	await _plate("e_offers", panel, [panel.toggle_button()])
	panel.close()
	await _frames(4)


func _runway() -> void:
	var card := _main.find_child("RunwayCard", true, false) as RunwayCard
	_expect(card != null, "no RunwayCard")
	card.open()
	await _frames(8)
	await _plate("f_runway", card, [card.toggle_button()])
	card.close()
	await _frames(4)


## A result card in its own layer, with the longest reasons the game has.
func _result() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	root.add_child(layer)
	var card := FlightResultPanel.new()
	layer.add_child(card)
	card.position = Vector2(1500.0, 120.0)
	var reasons: Array = []
	for pair: Array in [
		[Passenger.Stage.TO_CHECKIN, Passenger.Stuck.NO_SECURITY, 5],
		[Passenger.Stage.SEATED, Passenger.Stuck.NONE, 3],
		[Passenger.Stage.TO_EXIT, Passenger.Stuck.NONE, 2],
		[Passenger.Stage.CHECKIN, Passenger.Stuck.EXIT_BLOCKED, 1],
	]:
		reasons.append({"text": FlightResult.reason_text(pair[0], pair[1]), "count": pair[2]})
	card.show_result(
		{"flight": "GMF101", "title": "Sunhop Lisbon", "made": 14, "missed": 11, "reasons": reasons}
	)
	await _frames(8)
	for i in 4:
		card.position.x = float(WINDOW.x) - card.get_combined_minimum_size().x - 20.0
		await _frames(3)
	print("PLATE result text='%s'" % card.result_text().replace("\n", " | "))
	await _plate("g_result", card, [card])
	layer.queue_free()
	await _frames(3)


## Proves `subject` is in the window and that a control of `proof` shows the
## pseudolocalized text, lists the labels wider than their room, saves the plate.
func _plate(plate: String, subject: Node, proof: Array) -> void:
	var view := root.get_visible_rect().grow(-2.0)
	var controls := _text_controls(subject)
	_expect(not controls.is_empty(), "%s: no visible text controls" % plate)
	var inside := 0
	for control: Control in controls:
		if view.encloses(control.get_global_rect()):
			inside += 1
		else:
			print(
				(
					"OUTSIDE %s %s '%s' %s"
					% [plate, control.name, _text_of(control), control.get_global_rect()]
				)
			)
	print("PLATE %s controls=%d inside_window=%d" % [plate, controls.size(), inside])
	_expect(inside == controls.size(), "%s: a text control lies outside the window" % plate)
	for item: Variant in proof:
		var text: String = (item as Object).get("text") if item is Button or item is Label else ""
		if item is Node and text == "":
			text = _first_text(item as Node)
		print("PLATE %s proof text='%s'" % [plate, text.replace("\n", " | ")])
		_expect(text.begins_with("["), "%s: proof text '%s' is not bracketed" % [plate, text])
	for control: Control in controls:
		var wide := _overflow(control)
		if wide > 0.5:
			print(
				(
					"CLIPPED %s %s '%s' needs %.0f px more (width %.0f)"
					% [plate, control.name, _text_of(control), wide, control.size.x]
				)
			)
	await RenderingServer.frame_post_draw
	var path := _out_dir.path_join(plate + ".png")
	var err := root.get_texture().get_image().save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	_expect(err == OK, "the plate %s was not saved" % plate)


func _first_text(node: Node) -> String:
	for control: Control in _text_controls(node):
		var text := _text_of(control)
		if text != "":
			return text
	return ""


func _text_of(control: Control) -> String:
	return str(control.get("text"))


func _text_controls(node: Node) -> Array[Control]:
	var found: Array[Control] = []
	for child in node.find_children("*", "Control", true, false):
		var control := child as Control
		if (control is Label or control is Button) and control.is_visible_in_tree():
			if _text_of(control) != "":
				found.append(control)
	if node is Label or node is Button:
		found.append(node as Control)
	if node is Control and not found.has(node):
		for child in node.find_children("*", "Label", true, false):
			if (child as Control).is_visible_in_tree() and not found.has(child):
				found.append(child as Control)
	return found


## How many pixels wider the control's text is than the room it has, for a
## label or button that does not wrap. 0 when it fits or wraps.
func _overflow(control: Control) -> float:
	var font := control.get_theme_font("font")
	var size := control.get_theme_font_size("font_size")
	var room := control.size.x
	if control is Label:
		var label := control as Label
		if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
			return 0.0
		var wide := 0.0
		for line in label.atr(label.text).split("\n"):
			wide = maxf(wide, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
		return wide - room
	var button := control as Button
	var box := button.get_theme_stylebox("normal")
	room -= box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT)
	return (
		font.get_string_size(button.atr(button.text), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x - room
	)


func _expect(condition: bool, why: String) -> void:
	if not condition:
		_failed = true
		print("PROBE_INVALID: ", why)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
