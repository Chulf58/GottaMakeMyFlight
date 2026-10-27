extends SceneTree
## Headless probe of Economy 7/8 on the real main scene: the Money slot shows
## the wallet and follows it, the cards show their prices and grey out, the
## cost line shows cost and shortfall for a tool and for a dragged Floor
## rectangle, the flight panel lists today's departures, and the new game
## has the starting budget and the one starter contract. It prints the label
## texts it compared; any mismatch prints PROBE_INVALID and exits 1.
##
## Run:
##   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/money_hud_probe.gd
##
## Boots main.tscn with a new random world seed (printed). Pass values are
## text equalities against the price table and the starter terms, plus a
## control: the money text before and after the wallet changes differs. A
## guard thread ends a hang (anti-pattern a-frame-counting-watchdog-cannot-
## catch-a-stuck-main-thread). Headless draws no pixels; the windowed plate
## check judges how it looks.

const MAIN := "res://main/main.tscn"
const HANG_LIMIT_MS := 30000
const TOTAL_LIMIT_MS := 120000
## Frames to wait so the containers have laid out before rectangles are read.
const LAYOUT_FRAMES := 3

var _guard := Thread.new()
var _mutex := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _done := false

var _main: Node
var _frame := 0
var _phase := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_beat("boot")
	_guard.start(_watch)
	var world_seed := randi()
	print("PROBE world_seed=%d" % world_seed)
	_main = load(MAIN).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(world_seed)
	root.add_child(_main)
	current_scene = _main
	(_main.get_node("SimClock") as SimClock).set_paused(true)


func _process(_delta: float) -> bool:
	_beat("frame %d" % _frame)
	_frame += 1
	if _frame <= LAYOUT_FRAMES:
		return false
	if _phase == 0:
		_check()
		_fill_the_day()
		_phase = 1
		_frame = 0
		return false
	_check_layout()
	for failure in _failures:
		print("PROBE_INVALID %s" % failure)
	print("PROBE_%s" % ("INVALID" if not _failures.is_empty() else "OK"))
	_finish(1 if not _failures.is_empty() else 0)
	return true


func _check() -> void:
	var finances: Finances = _main.get_node("Finances")
	var menu: BuildMenu = _main.get_node("BuildMenu")
	var mode: BuildMode = _main.get_node("BuildMode")
	var hud: PassengerHud = _main.get_node("PassengerHud")
	var flights: FlightSim = _main.get_node("FlightSim")
	var wallet := finances.wallet

	print(
		(
			"NEW_GAME balance=%d contracts=%s flights=%s"
			% [wallet.balance, flights.contract_ids(), flights.flight_ids()]
		)
	)
	_expect("starting budget", wallet.balance, PriceTable.STARTING_BUDGET)
	_expect("one starter contract", flights.contract_ids(), [FlightSim.STARTER_TERMS["id"]])
	_expect("day one has a flight", flights.flight_ids(), ["GMF101-d0"])

	var money_before := menu.money_label().text
	print("LABEL money=%s" % money_before)
	_expect("money slot", money_before, "Money  %d" % PriceTable.STARTING_BUDGET)
	print("LABEL flight=%s" % hud.flight_text())
	var departures := (hud.find_child("Departures", true, false) as Label).text
	print("LABEL departures=%s" % departures.replace("\n", " | "))
	_expect("departures", departures, "07:38  Oslo  Gotta Air")
	_expect("flight line", hud.flight_text().begins_with("GMF101  "), true)

	var prices := {}
	for tool in [
		BuildMode.Tool.FLOOR,
		BuildMode.Tool.WALL,
		BuildMode.Tool.GLASS,
		BuildMode.Tool.DOOR,
		BuildMode.Tool.DESK,
		BuildMode.Tool.SCANNER,
		BuildMode.Tool.SEATS,
		BuildMode.Tool.CAFE_ROOM
	]:
		prices[tool] = menu.card_price_text(tool)
	print("LABEL card prices=%s" % prices)
	_expect("floor price", prices[BuildMode.Tool.FLOOR], str(PriceTable.FLOOR_PRICE))
	_expect("desk price", prices[BuildMode.Tool.DESK], "400")
	_expect("room is free", prices[BuildMode.Tool.CAFE_ROOM], BuildMenu.PRICE_TEXT)

	wallet.from_snapshot({"balance": "300"})
	menu.press_card(BuildMode.Tool.DESK)
	menu.refresh_preview()
	print("LABEL money=%s cost=%s" % [menu.money_label().text, menu.preview_label().text])
	_expect("money follows the wallet", menu.money_label().text, "Money  300")
	_expect("money changed", menu.money_label().text != money_before, true)
	_expect("desk greyed", menu.is_card_affordable(BuildMode.Tool.DESK), false)
	_expect(
		"desk card grey", menu.card(BuildMode.Tool.DESK).modulate, BuildMenu.UNAFFORDABLE_MODULATE
	)
	_expect("floor card normal", menu.card(BuildMode.Tool.FLOOR).modulate, Color.WHITE)
	_expect("tool cost and shortfall", menu.preview_label().text, "Cost 400   Short by 100")

	wallet.from_snapshot({"balance": "100"})
	mode.set_tool(BuildMode.Tool.FLOOR)
	mode.begin_area(mode.grid.cell_to_world(Vector2i(2, 2)))
	mode.move_area(mode.grid.cell_to_world(Vector2i(5, 4)))
	menu.refresh_preview()
	print("LABEL drag cost=%s" % menu.preview_label().text)
	_expect("drag cost and shortfall", menu.preview_label().text, "Cost 300   Short by 200")
	mode.cancel_area()

	print("LABEL debug policy=%s" % PassengerHud.DEBUG_POLICY_TEXT)


## Adds three more contracts so today's list is at its longest.
func _fill_the_day() -> void:
	var flights: FlightSim = _main.get_node("FlightSim")
	for i in 3:
		var terms := FlightSim.STARTER_TERMS.duplicate()
		terms["id"] = "PRB%d" % i
		terms["departure_minute"] = (11 + 3 * i) * 60
		terms["destination"] = "Rome"
		_expect("probe contract %d accepted" % i, flights.accept_contract(terms), true)


## The flight panel with a full list sits clear of the result panel, and the
## list is at its line cap.
func _check_layout() -> void:
	var hud: PassengerHud = _main.get_node("PassengerHud")
	var label := hud.find_child("Departures", true, false) as Label
	print("LABEL full list=%s" % label.text.replace("\n", " | "))
	_expect("list lines", label.text.split("\n").size(), DepartureList.MAX_LINES)
	var panel := hud.get_node("FlightPanel") as Control
	var bottom := panel.get_global_rect().end.y
	print("LAYOUT flight panel bottom=%.0f result top=%.0f" % [bottom, PassengerHud.RESULT_TOP])
	_expect("flight panel clear of the result panel", bottom <= PassengerHud.RESULT_TOP, true)


func _expect(what: String, actual: Variant, expected: Variant) -> void:
	if typeof(actual) == typeof(expected) and actual == expected:
		return
	if typeof(actual) != typeof(expected) and str(actual) == str(expected):
		return
	_failures.append("%s: got %s, expected %s" % [what, actual, expected])


func _finish(code: int) -> void:
	_mutex.lock()
	_done = true
	_mutex.unlock()
	if _guard.is_started():
		_guard.wait_to_finish()
	if _main != null:
		_main.queue_free()
	quit(code)


func _beat(stage: String) -> void:
	_mutex.lock()
	_beat_ms = Time.get_ticks_msec()
	_stage = stage
	_mutex.unlock()


func _watch() -> void:
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
			OS.crash("money hud probe hung")
