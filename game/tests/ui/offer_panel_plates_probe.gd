extends SceneTree
## Windowed plate probe for the offer panel (OfferPanel, OfferDesk) on the real
## main.tscn with the starter terminal built:
##   a_closed_1920     the Offers button alone, with its open-offer count
##   b_open_1920       the sheet open: one cream card per open offer
##   c_refusal_1920    one offer accepted, a clashing one refused with its reason
##   d_next_day_1920   the clock enters the next day: yesterday's offers expired
##   e_open_1280       1280x720, the sheet open beside the flight panel
## It boots on a world seed whose first day has two clashing offers (and prints
## it), so the refusal plate is always real. Before each save it proves every
## HUD panel lies inside the window, that no two panels overlap, and that the
## real mouse over each card button and the Offers button reaches that button
## (nothing covers it); otherwise it prints PROBE_INVALID and exits 1. A guard
## thread prints PROBE_INVALID and calls OS.crash() if the run passes LIMIT_MS.
##
## Run (one windowed Godot run project-wide):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/.claude/worktrees/<lane>/game \
##     -s res://tests/ui/offer_panel_plates_probe.gd

const OUT_REL := "res://../tools/blender/out/offer-panel"
const LIMIT_MS := 120000
const MAX_BOOTS := 30

var _out_dir := ""
var _failed := false
var _start_ms := 0
var _guard := Thread.new()
var _lock := Mutex.new()
var _stop := false
var _seed := 0
var _main: Node3D
var _menu: BuildMenu
var _hud: PassengerHud
var _panel: OfferPanel
var _desk: OfferDesk
var _flights: FlightSim
var _clock: SimClock


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
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
			OS.crash("offer_panel_plates_probe: no finish within %d ms" % LIMIT_MS)


func _finish() -> void:
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()


## True when the first of day 0's offers fits beside the bootstrap flight GMF101
## and another is then refused, so both an accept and a refusal can be shown.
static func _has_clash(offers: Array[Dictionary]) -> bool:
	var sim := FlightSim.new()
	sim.add_default_flight()
	var clash := false
	if sim.accept_contract(OfferBoard.terms_of(offers[0])):
		for i in range(1, offers.size()):
			clash = clash or sim.accept_problem(OfferBoard.terms_of(offers[i])) != ""
	sim.free()
	return clash


## Boots main.tscn on a new world seed, frozen at tick 0 so acceptance times are
## stable, until day 0's offers include a clashing pair. The offers share
## SimClock.rng with the passenger sim, so they can only be read after the boot.
func _boot() -> void:
	randomize()
	for tries in MAX_BOOTS:
		_seed = randi()
		_main = (load("res://main/main.tscn") as PackedScene).instantiate()
		_clock = _main.get_node("SimClock") as SimClock
		_clock.seed_rng(_seed)
		_clock.set_paused(true)
		root.add_child(_main)
		_desk = _main.get_node("OfferDesk") as OfferDesk
		if _has_clash(_desk.board.open_offers()):
			print("PROBE seed=%d (a clashing pair on boot %d)" % [_seed, tries + 1])
			break
		_main.queue_free()
		await _frames(2)
	_menu = _main.get_node("BuildMenu") as BuildMenu
	_hud = _main.get_node("PassengerHud") as PassengerHud
	_panel = _main.get_node("OfferPanel") as OfferPanel
	_flights = _main.get_node("FlightSim") as FlightSim


func _run() -> void:
	await _boot()
	await _frames(3)
	_hud.press_starter_terminal()
	print("PROBE starter: %s" % _hud.status_text())
	print("PROBE window=%s layout=%s" % [root.size, root.get_visible_rect().size])
	if root.size != Vector2i(1920, 1080):
		_invalid("the window is %s, not 1920x1080" % root.size)
	await _frames(10)

	if _panel.is_open():
		_invalid("a: the sheet is open at start")
	_expect(
		_desk.board.open_offers().size() == OfferBoard.OFFERS_PER_DAY,
		"a: the new game drew %d offers" % _desk.board.open_offers().size()
	)
	await _plate("a_closed_1920", [_panel.toggle_button()])

	_panel.toggle_button().pressed.emit()
	await _frames(6)
	_expect(_panel.card_ids().size() == OfferBoard.OFFERS_PER_DAY, "b: one card per offer")
	await _plate("b_open_1920", _card_buttons())

	var ids := _panel.card_ids()
	var accepted := ""
	var refused := ""
	for id in ids:
		var terms := OfferBoard.terms_of(_desk.board.offer_of(id))
		if accepted == "":
			_panel.accept_button(id).pressed.emit()
			accepted = id
		elif refused == "" and _flights.accept_problem(terms) != "":
			_panel.accept_button(id).pressed.emit()
			refused = id
	print("PROBE accepted=%s refused=%s message='%s'" % [accepted, refused, _panel.message()])
	_expect(refused != "", "c: no offer was refused")
	_expect(
		_flights.contract_ids() == [accepted], "c: the contracts are %s" % [_flights.contract_ids()]
	)
	_expect(_panel.message().find("clashes") >= 0, "c: the refusal does not name the clash")
	await _frames(6)
	await _plate("c_refusal_1920", _card_buttons())

	var day1_tick := GameCalendar.day_start(1)
	_clock.tick = day1_tick
	_clock.ticked.emit(day1_tick)
	await _frames(6)
	print("PROBE day=%d open=%s" % [GameCalendar.day_of(_clock.tick), _panel.card_ids()])
	for offer in _desk.board.open_offers():
		_expect(offer["day"] == 1, "d: an open offer from day %d survived midnight" % offer["day"])
	_expect(_panel.card_ids().size() == OfferBoard.OFFERS_PER_DAY, "d: day 1 has its cards")
	_expect(
		_desk.board.offer_of(refused)["status"] == OfferBoard.EXPIRED,
		"d: the refused offer did not expire"
	)
	await _plate("d_next_day_1920", _card_buttons())

	DisplayServer.window_set_size(Vector2i(1280, 720))
	await _frames(10)
	# The content scale (project.godot) keeps the layout size the same at every
	# window size, so the window is checked by its pixels.
	print("PROBE window=%s layout=%s" % [root.size, root.get_visible_rect().size])
	if root.size != Vector2i(1280, 720):
		_invalid("e: the window is %s, not 1280x720" % root.size)
	await _plate("e_open_1280", _card_buttons())

	print("PROBE done failed=%s" % _failed)
	_finish()
	quit(1 if _failed else 0)


func _card_buttons() -> Array:
	var out: Array = [_panel.toggle_button()]
	for id in _panel.card_ids():
		out.append(_panel.accept_button(id))
		out.append(_panel.decline_button(id))
	return out


## Checks the HUD layout, proves the real mouse reaches each of `buttons`, then
## saves the plate.
func _plate(label: String, buttons: Array) -> void:
	var view := root.get_visible_rect()
	var panels := _panels()
	var ok := true
	print("PLATE %s open=%s cards=%s" % [label, _panel.is_open(), _panel.card_ids()])
	for key in panels:
		var rect: Rect2 = panels[key]
		var inside := view.grow(-4.0).encloses(rect)
		print("  PANEL %s %s inside=%s" % [key, rect, inside])
		ok = ok and inside
	var keys := panels.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			if (panels[keys[i]] as Rect2).intersects(panels[keys[j]]):
				print("  OVERLAP %s with %s" % [keys[i], keys[j]])
				ok = false
	for button: Button in buttons:
		var centre := button.get_global_rect().get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = centre
		motion.global_position = centre
		# The centre is in layout space (the content scale), so push it as such.
		root.push_input(motion, true)
		await process_frame
		await process_frame
		var hit := root.gui_get_hovered_control()
		var reached := hit == button
		print("  HIT %s at %s -> %s reached=%s" % [button.name, centre, hit, reached])
		ok = ok and reached
	root.warp_mouse(Vector2(view.size.x / 2.0, view.size.y - 4.0))
	await process_frame
	if not ok:
		_invalid("%s: a panel or button check failed" % label)
		return
	await RenderingServer.frame_post_draw
	var path := _out_dir.path_join(label + ".png")
	var err := root.get_texture().get_image().save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	if err != OK:
		_invalid("%s: the plate was not saved (error %d)" % [label, err])


## The on-screen rect of every visible HUD panel.
func _panels() -> Dictionary:
	var out := {}
	out["offers_button"] = _panel.toggle_button().get_global_rect()
	if _panel.is_open():
		out["offers_sheet"] = (
			(_panel.find_child("OfferSheet", true, false) as Control).get_global_rect()
		)
	out["bar"] = _menu.bar().get_global_rect()
	if _menu.is_tray_open():
		out["tray"] = _menu.tray().get_global_rect()
	out["money"] = (_menu.find_child("MoneySlot", true, false) as Control).get_global_rect()
	out["flight"] = (_hud.find_child("FlightPanel", true, false) as Control).get_global_rect()
	out["debug"] = (_hud.find_child("DebugCorner", true, false) as Control).get_global_rect()
	return out


func _expect(condition: bool, why: String) -> void:
	if not condition:
		_invalid(why)


func _invalid(why: String) -> void:
	_failed = true
	print("PROBE_INVALID: ", why)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
