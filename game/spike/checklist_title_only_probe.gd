extends SceneTree
## Windowed reproduction of the D3 playtest moment (board D3a point 5): the
## checklist card showed only its title with the Gates tray open while staff
## were walking to their stations.
##
## Run (one windowed Godot run project-wide, the lock in tools/blender/out):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/checklist_title_only_probe.gd -- --variant=A [--tpf=1]
##
## Run with --tpf=1 to stop on the tick the last member arrives (the airport
## opens one tick later) and plate the card there with the clock paused.
## Variants: A builds the starter terminal, hires an agent and an officer on the
## Staff card, then opens the Gates tray while they walk; B opens the Gates tray
## before hiring; C opens then closes the Staff card first. A new random world
## seed is printed (-- --seed=N replays one). Each frame whose card state changed
## prints the card's rows (text, done flag, visible), the "+N more" state, the
## room it was given, its size, Checklist lines() as data, AirportGate.unmet()
## and each member's state. Plates go to tools/blender/out/checklist-repro/.
## A plate whose card is not on screen prints PROBE_INVALID and exits 1.

const MAIN := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/checklist-repro"
const FRAME_LIMIT := 1500
const IntroClose := preload("res://spike/intro_close.gd")

var _variant := "A"
var _ticks_per_frame := 6
var _tag := ""
var _failed := false
var _out_dir := ""
var _main: Node
var _clock: SimClock
var _panel: StaffPanel
var _menu: BuildMenu
var _staff: StaffSim
var _gate: AirportGate
var _last_key := ""
var _plates := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="):
			_variant = arg.get_slice("=", 1)
		if arg.begins_with("--tag="):
			_tag = arg.get_slice("=", 1) + "-"
		if arg.begins_with("--tpf="):
			_ticks_per_frame = int(arg.get_slice("=", 1))
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var world_seed := IntroClose.seed_or_random()
	print("PROBE variant=%s world_seed=%d" % [_variant, world_seed])
	_main = load(MAIN).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(world_seed)
	root.add_child(_main)
	current_scene = _main
	_clock.set_paused(true)
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _run() -> void:
	await _frames(10)
	var err: String = IntroClose.close(_main)
	if err != "":
		_invalid(err)
		return
	_panel = _main.find_child("StaffPanel", true, false) as StaffPanel
	_menu = _main.find_child("BuildMenu", true, false) as BuildMenu
	_staff = _panel.staff
	_gate = _panel.gate
	_clock.set_paused(true)
	await _frames(5)
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	await _frames(5)
	_report("built terminal")
	if _variant == "B":
		_open_gates()
		await _frames(5)
		_report("gates tray open before hiring")
	if _variant == "C":
		_menu.press_staff()
		await _frames(5)
		_report("staff card open")
		_menu.press_staff()
		await _frames(5)
		_report("staff card closed")
	if _variant != "B" and _variant != "C":
		_menu.press_staff()
		await _frames(3)
	_panel.hire_button(StaffMember.Role.CHECKIN).pressed.emit()
	_panel.hire_button(StaffMember.Role.SECURITY).pressed.emit()
	await _frames(3)
	_report("hired")
	if _variant == "A":
		_open_gates()
		await _frames(3)
		_report("gates tray open while walking")
	await _frames(2)
	await _plate("walking")
	var frame := 0
	var opened_seen := false
	var held := false
	while frame < FRAME_LIMIT and not _failed:
		_clock.set_paused(false)
		for i in _ticks_per_frame:
			_clock.advance(SimClock.STEP)
		_clock.set_paused(true)
		await _frames(1)
		frame += 1
		_report("frame %d" % frame, true)
		if _title_only() and _plates < 4:
			await _plate("title-only-frame%d" % frame)
		if not held and _all_on_duty() and not _gate.is_open():
			# The clock stays paused here, as the player pausing on the tick
			# the last member arrives would leave it: the airport opens one
			# tick later, so every line is done and the airport is closed.
			held = true
			await _frames(10)
			_report("held at the last arrival, clock paused")
			_open_gates()
			await _frames(10)
			_report("held, gates tray open")
			await _plate("held-gates-open")
			break
		if _gate.is_open():
			if not opened_seen:
				opened_seen = true
				await _frames(10)
				_report("airport open")
				await _plate("opened")
			if frame > 0:
				break
	print("PROBE done frames=%d failed=%s plates=%d" % [frame, _failed, _plates])
	quit(1 if _failed else 0)


## The card shows its title and nothing else: no visible row and no "+N more".
func _title_only() -> bool:
	var card := _panel.checklist()
	var shown := card.rows().filter(func(r: Node) -> bool: return (r as Control).visible)
	var more := card.find_child("ChecklistMore", true, false) as Label
	return card.title_label().visible and shown.is_empty() and not more.visible


func _all_on_duty() -> bool:
	var ids := _staff.member_ids()
	for id in ids:
		if _staff.get_member(id).state != StaffMember.State.ON_DUTY:
			return false
	return not ids.is_empty()


func _open_gates() -> void:
	for i in BuildMenu.CATEGORIES.size():
		if BuildMenu.CATEGORIES[i]["name"] == "Gates":
			_menu.press_category(i)
	if not _menu.is_tray_open():
		_invalid("the Gates tray did not open")


func _members() -> String:
	var out := PackedStringArray()
	for id in _staff.member_ids():
		var m := _staff.get_member(id)
		out.append("%s:%s" % [StaffMember.Role.keys()[m.role], StaffMember.State.keys()[m.state]])
	return ",".join(out)


func _snapshot() -> Dictionary:
	var card := _panel.checklist()
	var box := _panel.hint_card()
	var bar_w := _menu.bar().get_combined_minimum_size().x
	var layer := _panel.get_viewport().get_visible_rect().size
	var room := LeftColumn.room_below(box.offset_top, layer, bar_w)
	var rows: Array = []
	for row in card.rows():
		var label := row.get_node("Text") as Label
		rows.append([label.text, (row as Control).visible, label.size.y])
	var more := card.find_child("ChecklistMore", true, false) as Label
	var unmet: Array = []
	for b in _gate.unmet():
		unmet.append(AirportGate.Blocker.keys()[b])
	return {
		"tick": _clock.tick,
		"title": card.title_label().text,
		"title_visible": card.title_label().is_visible_in_tree(),
		"rows": rows,
		"more": [more.visible, more.text],
		"room_below": room,
		"fit_room": room - box.get_theme_stylebox("panel").get_minimum_size().y,
		"card_size": card.size,
		"box_size": box.size,
		"box_visible": box.visible,
		"box_top": box.offset_top,
		"box_alpha": box.modulate.a,
		"tray_open": _menu.is_tray_open(),
		"staff_open": _menu.staff_open,
		"lines": card.lines(),
		"unmet": unmet,
		"gate_open": _gate.is_open(),
		"members": _members(),
	}


func _report(label: String, only_changes := false) -> void:
	var snap := _snapshot()
	var shown := snap.duplicate()
	shown.erase("tick")
	shown.erase("box_alpha")
	var key := str(shown)
	if only_changes and key == _last_key:
		return
	_last_key = key
	print("SNAP [%s] %s" % [label, str(snap)])


func _plate(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var card := _panel.hint_card()
	var rect := card.get_global_rect()
	var view := root.get_visible_rect()
	if card.visible and not view.encloses(rect):
		_invalid("the checklist card %s is not inside the viewport %s" % [rect, view])
		return
	var img := root.get_texture().get_image()
	var path := _out_dir.path_join("%s%s-%s.png" % [_tag, _variant, name])
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	_plates += 1
	print("PLATE saved %s card_rect=%s visible=%s" % [path, rect, card.visible])


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true
	quit(1)
