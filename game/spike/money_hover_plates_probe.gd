extends SceneTree
## Windowed plate probe for the money hover card (HUD 2/7, decision
## money-hover-design-categorised-wallet-transactions-feed-a-sa) on the real
## main.tscn, at 1920x1080 with the UI scale at 1.0 and at 1.25
## (Window.content_scale_factor):
##   a_normal     fees, shop income, wages and toilet upkeep paid and some
##                building; no owed wages
##   b_broke      balance 0, owed wages and owed upkeep above 0 that ate a fee
##                and a rescue grant (Toilets 5/5 added the upkeep rows)
##   c_load       DayLedger.start_since_load(), then a fee and a purchase
## Each scene sets its money through the real Wallet and Settlement (credit,
## spend, Settlement.from_snapshot for the owed wages), then hovers the money
## slot for real: Viewport.warp_mouse plus a motion pushed at viewport
## coordinates, then a wait past the tooltip delay for Godot's own tooltip
## popup. If no popup appears, the probe adds MoneySlot.make_card itself under
## a TooltipPanel and says "MODE fallback".
## Before each save it proves the subject: the card's text equals the expected
## rows, the popup rect lies inside the visible rect (printed), the owed row
## uses HudAttentionText. A crop around the card, scaled 2x, is saved beside the
## full plate. Otherwise it prints PROBE_INVALID and exits 1. After plate a it
## credits a shop sale with the card still open and requires the open card, in
## the same popup, to show EXPECT_A_LIVE (LIVE line, crop named a_live). It then
## sets owed wages with the card open and requires the popup to grow by the
## owed row, and to shrink back to its earlier size when they are cleared. A guard thread
## reads a heartbeat and calls OS.crash() on a hang (anti-pattern
## a-frame-counting-watchdog-cannot-catch-a-stuck-main-thread).
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/gmmf-money/game -s res://spike/money_hover_plates_probe.gd

const MAIN := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/money-hover"
const WINDOW := Vector2i(1920, 1080)
const SCALES: Array[float] = [1.0, 1.25]
const HANG_LIMIT_MS := 20000
const TOTAL_LIMIT_MS := 180000
const TOOLTIP_WAIT_MS := 2500
const EXPECT_A := (
	"Today\nAirline fees  +1840\nShops  +365\nWages paid  -720\nUpkeep paid  -60"
	+ "\nOperating result  +1425\nBuilding  -450\nRescue grant  0\nCash change today  +975"
)
## Plate a after a shop sale of 100 with the card open.
const EXPECT_A_LIVE := (
	"Today\nAirline fees  +1840\nShops  +465\nWages paid  -720\nUpkeep paid  -60"
	+ "\nOperating result  +1525\nBuilding  -450\nRescue grant  0\nCash change today  +1075"
)
const EXPECT_B := (
	"Today\nAirline fees  +240\nShops  0\nWages paid  -740\nUpkeep paid  0"
	+ "\nOperating result  -500\nBuilding  0\nRescue grant  +500\nCash change today  0"
	+ "\nOwed wages  460\nOwed upkeep  30"
)
const EXPECT_C := (
	"Since load\nAirline fees  +300\nShops  0\nWages paid  0\nUpkeep paid  0"
	+ "\nOperating result  +300\nBuilding  -120\nRescue grant  0\nCash change since load  +180"
)

var _guard := Thread.new()
var _mutex := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _done := false
var _failed := false
var _out_dir := ""
var _scale := 1.0
var _fallbacks := 0

var _main: Node3D
var _slot: MoneySlot
var _ledger: DayLedger
var _wallet: Wallet
var _settlement: Settlement
var _layer: CanvasLayer
## The popup (or the fallback panel) the last _show_card found.
var _shown: Node


func _initialize() -> void:
	_beat("boot")
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_guard.start(_watch)
	_run.call_deferred()


func _run() -> void:
	var world_seed := randi()
	print("PROBE world_seed=%d" % world_seed)
	DisplayServer.window_set_size(WINDOW)
	_main = (load(MAIN) as PackedScene).instantiate()
	var clock := _main.get_node("SimClock") as SimClock
	clock.seed_rng(world_seed)
	clock.set_paused(true)
	root.add_child(_main)
	await _frames(8)
	_slot = _main.find_child("MoneySlot", true, false) as MoneySlot
	_ledger = _main.get_node("DayLedger") as DayLedger
	_wallet = (_main.get_node("Finances") as Finances).wallet
	_settlement = _main.get_node("Settlement") as Settlement
	_expect(_slot != null and _slot.ledger == _ledger, "the MoneySlot does not watch the ledger")
	print(
		"PROBE window=%s tooltip_delay=%s" % [root.size, _setting("gui/timers/tooltip_delay_sec")]
	)
	for scale_value in SCALES:
		_scale = scale_value
		root.content_scale_factor = scale_value
		await _frames(6)
		print("PROBE scale=%s visible=%s" % [_scale, root.get_visible_rect().size])
		await _scene_normal()
		await _scene_broke()
		await _scene_load()
	print("PROBE fallbacks=%d" % _fallbacks)
	print("PROBE_INVALID" if _failed else "PROBE_PASS")
	_finish(1 if _failed else 0)


func _scene_normal() -> void:
	_beat("a_normal %s" % _scale)
	_set_owed(0)
	_wallet.from_snapshot({"balance": "20000"})
	_zero_ledger()
	_expect(_wallet.credit(1840, Wallet.Category.FEES), "a: fee credit refused")
	_expect(_wallet.credit(365, Wallet.Category.SHOP), "a: shop credit refused")
	_expect(_wallet.spend(720, Wallet.Category.WAGES), "a: wage spend refused")
	_expect(_wallet.spend(60, Wallet.Category.UPKEEP), "a: upkeep spend refused")
	_expect(_wallet.spend(450, Wallet.Category.BUILD), "a: build spend refused")
	await _plate("a_normal", EXPECT_A, true)


func _scene_broke() -> void:
	_beat("b_broke %s" % _scale)
	_wallet.from_snapshot({"balance": "0"})
	_zero_ledger()
	_set_owed(1200, 30)
	# Owed wages take each credit whole: the fee and the grant both go to them.
	_expect(_wallet.credit(240, Wallet.Category.FEES), "b: fee credit refused")
	_expect(_wallet.credit(500, Wallet.Category.GRANT), "b: grant credit refused")
	print(
		(
			"  STATE balance=%d owed=%d upkeep_owed=%d"
			% [_wallet.balance, _settlement.wages_owed(), _settlement.upkeep_owed()]
		)
	)
	await _plate("b_broke", EXPECT_B)


func _scene_load() -> void:
	_beat("c_load %s" % _scale)
	_set_owed(0)
	_wallet.from_snapshot({"balance": "20000"})
	_ledger.start_since_load()
	_expect(_wallet.credit(300, Wallet.Category.FEES), "c: fee credit refused")
	_expect(_wallet.spend(120, Wallet.Category.BUILD), "c: build spend refused")
	_expect(_ledger.is_since_load(), "c: the ledger is not counting since load")
	await _plate("c_load", EXPECT_C)


## Sets the settlement's owed wages and owed upkeep through a snapshot round trip.
func _set_owed(amount: int, upkeep := 0) -> void:
	var data := _settlement.to_snapshot()
	data["wages_owed"] = str(amount)
	data[Settlement.UPKEEP_SNAPSHOT_KEY] = str(upkeep)
	_expect(_settlement.from_snapshot(data), "owed wages %d refused" % amount)
	_expect(_settlement.wages_owed() == amount, "owed wages are %d" % _settlement.wages_owed())
	_expect(_settlement.upkeep_owed() == upkeep, "owed upkeep is %d" % _settlement.upkeep_owed())


func _zero_ledger() -> void:
	var data := _ledger.to_snapshot()
	for key in DayLedger.CATEGORY_KEYS.values():
		data[key] = "0"
	data["since_load"] = false
	_expect(_ledger.from_snapshot(data), "the ledger refused a zeroed snapshot")


## Hovers the money slot, proves the card, saves the plate and a 2x crop.
## With `live`, it then credits a shop sale while the card stays open and
## reports whether the open card follows (LIVE line, an observation).
func _plate(label: String, expected: String, live := false) -> void:
	var name := "%s_%s" % [label, str(_scale).replace(".", "p")]
	print("PLATE %s scale=%s" % [name, _scale])
	_expect(_slot.card_text() == expected, "%s: card_text is\n%s" % [name, _slot.card_text()])
	await _hover_away()
	var popup_rect := await _show_card()
	var card := _find_card(_shown) if _shown != null else null
	var ok := card != null and card.is_visible_in_tree()
	if card != null:
		ok = _check_card(card, expected) and ok
		var view := root.get_visible_rect()
		var inside := view.grow(-2.0).encloses(popup_rect)
		var money := _slot.get_global_rect()
		print(
			(
				"  RECT popup=%s card=%s money=%s visible=%s inside=%s over_money=%s"
				% [
					popup_rect,
					card.get_global_rect(),
					money,
					view,
					inside,
					popup_rect.intersects(money)
				]
			)
		)
		ok = ok and inside
	else:
		print("  CARD not found")
	if not ok:
		_invalid("%s: the card check failed" % name)
		name += "_INVALID"
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_save(image, name)
	var window_rect := root.get_final_transform() * popup_rect
	var crop := Rect2i(window_rect.grow(32.0)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	print("  CROP window_rect=%s crop=%s" % [window_rect, crop])
	if crop.has_area():
		var region := image.get_region(crop)
		region.resize(crop.size.x * 2, crop.size.y * 2, Image.INTERPOLATE_NEAREST)
		_save(region, name + "_crop")
	if live:
		await _live_check(name)
	if _layer != null:
		_layer.queue_free()
		_layer = null
	await _hover_away()


## Moves the pointer onto the money slot and waits for Godot's tooltip popup;
## without one, adds the card itself. Returns the card's rect in viewport
## coordinates.
func _show_card() -> Rect2:
	var point := _slot.get_global_rect().get_center()
	_move_to(point)
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < TOOLTIP_WAIT_MS:
		await _frames(1)
		var popup := _find_popup(root)
		if popup != null:
			await _frames(4)
			print(
				(
					"  MODE hover hovered=%s popup=%s pos=%s size=%s embedded=%s after_ms=%d"
					% [
						root.gui_get_hovered_control(),
						popup.get_class(),
						popup.position,
						popup.size,
						popup.is_embedded(),
						Time.get_ticks_msec() - start
					]
				)
			)
			_shown = popup
			return Rect2(popup.position, popup.size)
	_fallbacks += 1
	print("  MODE fallback hovered=%s (no tooltip popup)" % root.gui_get_hovered_control())
	_layer = CanvasLayer.new()
	_layer.layer = 100
	root.add_child(_layer)
	var panel := PanelContainer.new()
	panel.theme = BuildMenu.HUD_THEME
	panel.theme_type_variation = &"TooltipPanel"
	panel.position = point + Vector2(0.0, 24.0)
	panel.add_child(
		_slot.make_card(
			MoneySlot.heading(_ledger),
			MoneySlot.rows(_ledger, _settlement.wages_owed(), _settlement.upkeep_owed())
		)
	)
	_layer.add_child(panel)
	_shown = panel
	await _frames(4)
	return panel.get_global_rect()


func _move_to(point: Vector2) -> void:
	root.warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)


## Parks the pointer over the world so any tooltip closes.
func _hover_away() -> void:
	var view := root.get_visible_rect()
	_move_to(view.get_center())
	await _frames(6)


## The first visible popup Window under `node`, internal children included.
func _find_popup(node: Node) -> Window:
	for child in node.get_children(true):
		if child is Window and child != root and (child as Window).visible:
			if _find_card(child) != null:
				return child
		var deeper := _find_popup(child)
		if deeper != null:
			return deeper
	return null


## The card box: the parent of a HudTitle label headed Today or Since load.
func _find_card(node: Node) -> Control:
	for child in node.get_children(true):
		if child is Label and (child as Label).theme_type_variation == &"HudTitle":
			var text := (child as Label).text
			if text == "Today" or text == "Since load":
				return child.get_parent() as Control
		var deeper := _find_card(child)
		if deeper != null:
			return deeper
	return null


## Compares the card's labels with `expected` and prints the theme it got.
func _check_card(card: Control, expected: String) -> bool:
	var labels: Array[Label] = []
	for node in card.find_children("*", "Label", true, false):
		labels.append(node as Label)
	var lines: Array[String] = [labels[0].text]
	var right_edges := {}
	var ok := true
	for i in range(1, labels.size(), 2):
		var key := labels[i]
		var value := labels[i + 1]
		lines.append("%s  %s" % [key.text, value.text])
		right_edges[snappedf(value.get_global_rect().end.x, 0.5)] = true
		var colour := value.get_theme_color("font_color")
		var size := value.get_theme_font_size("font_size")
		print(
			(
				"  ROW '%s' '%s' variation=%s colour=%s font_size=%d clipped=%s"
				% [
					key.text,
					value.text,
					value.theme_type_variation,
					colour.to_html(false),
					size,
					(
						key.size.x < key.get_minimum_size().x
						or value.size.x < value.get_minimum_size().x
					)
				]
			)
		)
		ok = ok and key.size.x >= key.get_minimum_size().x
		ok = ok and value.size.x >= value.get_minimum_size().x
		if key.text == "Owed wages" or key.text == "Owed upkeep":
			var want := BuildMenu.HUD_THEME.get_color("font_color", MoneySlot.ATTENTION)
			ok = ok and colour == want
			ok = ok and key.theme_type_variation == MoneySlot.ATTENTION
			ok = ok and value.theme_type_variation == MoneySlot.ATTENTION
	var text := "\n".join(lines)
	print(
		(
			"  CARD title_font=%s title_size=%d separators=%d value_right_edges=%s"
			% [
				labels[0].get_theme_font("font").resource_path,
				labels[0].get_theme_font_size("font_size"),
				card.find_children("*", "HSeparator", true, false).size(),
				right_edges.keys()
			]
		)
	)
	ok = ok and right_edges.size() == 1
	ok = ok and card.find_children("*", "HSeparator", true, false).size() == 1
	if text != expected:
		print("  CARD text differs:\n%s" % text)
		ok = false
	return ok


## Credits a shop sale with the pointer still on the slot, waits, and requires
## the open card to show the new totals; saves a crop either way. Then requires
## the popup to grow for an owed-wages row and shrink back without it.
func _live_check(name: String) -> void:
	_expect(_wallet.credit(100, Wallet.Category.SHOP), "live: shop credit refused")
	await _frames(20)
	var popup := _find_popup(root)
	var card := _find_card(popup) if popup != null else null
	var shown := _card_text(card) if card != null else "<no card>"
	print(
		(
			"  LIVE open=%s same_popup=%s follows=%s shown=%s want=%s"
			% [
				popup != null,
				popup == _shown,
				shown == _slot.card_text(),
				shown.replace("\n", " | "),
				_slot.card_text().replace("\n", " | ")
			]
		)
	)
	_expect(
		popup != null and popup == _shown and shown == EXPECT_A_LIVE,
		"live: the open card does not show the new totals"
	)
	await _resize_check(popup, card)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var crop := Rect2i(root.get_final_transform() * Rect2(Vector2.ZERO, Vector2(520, 380)))
	_save(image.get_region(crop), name.replace("a_normal", "a_live") + "_crop")


## With the card open, owed wages add a row: the popup must grow to hold it,
## and shrink back to its earlier size once they are cleared.
func _resize_check(popup: Window, card: Control) -> void:
	if popup == null or card == null:
		return
	var before := popup.size
	_set_owed(55)
	await _frames(5)
	var grown := popup.size
	var holds := Vector2(grown) + Vector2.ONE >= card.get_combined_minimum_size()
	var owed_row := _card_text(card).ends_with("Owed wages  55")
	_set_owed(0)
	await _frames(5)
	var after := popup.size
	print(
		(
			"  RESIZE before=%s grown=%s after=%s card_min=%s holds=%s owed_row=%s"
			% [before, grown, after, card.get_combined_minimum_size(), holds, owed_row]
		)
	)
	_expect(owed_row, "resize: the open card shows no owed wages row")
	_expect(grown.y > before.y and holds, "resize: the popup did not grow for the owed row")
	_expect(after == before, "resize: the popup did not shrink back")


func _card_text(card: Control) -> String:
	var lines: Array[String] = []
	var labels := card.find_children("*", "Label", true, false)
	lines.append((labels[0] as Label).text)
	for i in range(1, labels.size(), 2):
		lines.append("%s  %s" % [(labels[i] as Label).text, (labels[i + 1] as Label).text])
	return "\n".join(lines)


func _save(image: Image, name: String) -> void:
	var path := _out_dir.path_join(name + ".png")
	var err := image.save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	if err != OK:
		_invalid("%s: not saved (error %d)" % [name, err])


func _setting(key: String) -> Variant:
	return ProjectSettings.get_setting(key)


func _expect(condition: bool, why: String) -> void:
	if not condition:
		_invalid(why)


func _invalid(why: String) -> void:
	_failed = true
	print("PROBE_INVALID: ", why)


func _frames(count: int) -> void:
	for i in count:
		_beat(_stage)
		await process_frame


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
			OS.crash("money hover plates probe hung")
