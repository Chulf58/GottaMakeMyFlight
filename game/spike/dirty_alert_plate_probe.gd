extends SceneTree
## Windowed plates of the dirty-terminal alert card (decision cleaner-staff-and-
## messes-visits-leave-messes-bins-fill-pooled-cleaners-nearest-mess, point 6;
## board Cleaner 5/5). Boots the real main scene with a new random sim seed
## (printed), builds ReferenceTerminal through the HUD's starter-terminal
## button, and:
##   1 clean: no mess, the card must be hidden (the control)
##   2 dirty: DirtyAlert.SHOW_AT fresh spills put on indoor floor, the HUD
##     refreshed; the card must show with the hire-a-cleaner text
##   3 per size (SIZES: 1280 x 720 logical through a content scale of 1.5, then
##     the default 1536 x 864):
##     the card's rect inside the viewport and clear of every other visible
##     HUD panel, button and label (plate <size>_hire); then the airline offer
##     sheet opened, which must be up with the card down (plate
##     <size>_offers_open), and closed again with the card back
##   4 cleaner hired: the text must change to the bins text, and the same
##     checks per size (plates <size>_bins)
##   5 cleaned: every mess cleaned, the card must clear itself
## Each check prints the values it compared. A failed check prints
## PROBE_INVALID and the probe exits 1.
##
## Run (one windowed Godot run project-wide; this probe holds the slot):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/dirty_alert_plate_probe.gd
##
## Plates go to tools/blender/out/cleaner-alert/.

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/cleaner-alert"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
## [label, window size, content scale]: the project stretches by 1.25 with an
## expanding aspect, so the default 1920 x 1080 window is 1536 x 864 logical and
## the viewport never gets narrower on its own; a scale of 1.5 makes the same
## window 1280 x 720 logical, the narrow case.
const SIZES := [["1280", Vector2i(1920, 1080), 1.5], ["default", Vector2i(1920, 1080), 1.25]]

var _out_dir := ""
var _failed := false
var _main: Node
var _clock: SimClock
var _sim: PassengerSim
var _hud: PassengerHud
var _card: DirtyAlert


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	var world_seed := randi()
	print("PROBE world_seed=%d" % world_seed)
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(world_seed)
	(_main.get_node("BuildMenu") as BuildMenu).grant_hold_s = 0.5
	root.add_child(_main)
	_sim = _main.get_node("PassengerSim")
	_hud = _main.get_node("PassengerHud")
	await _frames(5)
	_hud.press_starter_terminal()
	(_main.get_node("BuildMode") as BuildMode).set_tool(BuildMode.Tool.NONE)
	_clock.set_paused(true)
	await _frames(2)
	_card = _hud.find_child("DirtyAlert", true, false) as DirtyAlert
	if _card == null:
		_invalid("the HUD has no DirtyAlert")
	else:
		await _phase_clean()
		if not _failed:
			await _phase_dirty()
		if not _failed:
			await _sizes("hire", DirtyAlert.HIRE_TEXT, true)
		if not _failed:
			await _phase_hired()
		if not _failed:
			await _phase_cleaned()
	_main.queue_free()
	await _frames(3)
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _phase_clean() -> void:
	_hud.refresh()
	await _frames(2)
	print(
		(
			"CLEAN total_dirt=%d shown=%s visible=%s"
			% [_sim.messes.total_dirt(), _card.is_shown(), _card.visible]
		)
	)
	if _card.is_shown() or _card.visible:
		_invalid("the card shows on a clean terminal")


func _phase_dirty() -> void:
	var cells := _indoor_cells(DirtyAlert.SHOW_AT)
	if cells.size() < DirtyAlert.SHOW_AT:
		_invalid("only %d spaced indoor cells" % cells.size())
		return
	for cell in cells:
		if _sim.messes.add(MessSim.Kind.SPILL, cell) == 0:
			_invalid("a spill at %s was refused" % cell)
			return
	_hud.refresh()
	await _frames(2)
	var cleaners := _sim.staff.count(StaffMember.Role.CLEANER)
	print(
		(
			"DIRTY total_dirt=%d show_at=%d cleaners=%d shown=%s text=%s"
			% [
				_sim.messes.total_dirt(),
				DirtyAlert.SHOW_AT,
				cleaners,
				_card.is_shown(),
				_card.card_text()
			]
		)
	)
	if not _card.is_shown() or _card.card_text() != DirtyAlert.HIRE_TEXT:
		_invalid("the card does not show the hire text on a dirty terminal")
		return


func _phase_hired() -> void:
	_sim.staff.hire(StaffMember.Role.CLEANER)
	_hud.refresh()
	await _frames(2)
	print("HIRED cleaners=1 text=%s" % _card.card_text())
	if _card.card_text() != DirtyAlert.BINS_TEXT:
		_invalid("the card does not show the bins text once a cleaner is hired")
		return
	await _sizes("bins", DirtyAlert.BINS_TEXT, false)


## For each window size: the card's plate named <size>_<tag>, and when
## `sheet` the offer sheet opened over it (the card must give way) and closed.
func _sizes(tag: String, text: String, sheet: bool) -> void:
	var offers := _main.get_node("OfferPanel") as OfferPanel
	for entry in SIZES:
		if _failed:
			return
		DisplayServer.window_set_size(entry[1])
		root.content_scale_factor = entry[2]
		await _frames(4)
		_hud.refresh()
		await _frames(2)
		print(
			(
				"SIZE %s window=%s viewport=%s text_ok=%s"
				% [
					entry[0],
					DisplayServer.window_get_size(),
					root.get_visible_rect().size,
					_card.card_text() == text
				]
			)
		)
		if _card.card_text() != text or not _card.visible:
			_invalid("%s: the card is not up with its text" % entry[0])
			return
		await _plate("%s_%s" % [entry[0], tag])
		if sheet and not _failed:
			offers.open()
			await _frames(3)
			print("SHEET %s open=%s card_visible=%s" % [entry[0], offers.is_open(), _card.visible])
			if not offers.is_open() or _card.visible:
				_invalid("%s: the offer sheet is not open over a hidden card" % entry[0])
				return
			await _plate("%s_offers_open" % entry[0], false)
			offers.close()
			await _frames(3)
			if not _card.visible:
				_invalid("%s: the card did not come back when the sheet closed" % entry[0])


func _phase_cleaned() -> void:
	for id in _sim.messes.mess_ids():
		_sim.messes.clean(id)
	_hud.refresh()
	await _frames(2)
	print(
		(
			"CLEANED total_dirt=%d shown=%s visible=%s"
			% [_sim.messes.total_dirt(), _card.is_shown(), _card.visible]
		)
	)
	if _card.is_shown() or _card.visible:
		_invalid("the card did not clear itself when the terminal was clean")


## Saves a plate and checks the card's rect is inside the viewport, printing it.
func _plate(name: String, card_up := true) -> void:
	if not card_up:
		await _save_plate(name)
		return
	var rect := _card.get_global_rect()
	var view := root.get_visible_rect()
	var inside := view.grow(-MARGIN_PX).encloses(rect)
	print(
		(
			"IN_FRAME %s rect=%s viewport=%s card_visible_in_tree=%s inside=%s"
			% [name, rect, view, _card.is_visible_in_tree(), inside]
		)
	)
	var crowd := _overlaps(rect)
	print("OVERLAPS %s with=%s" % [name, crowd])
	if not crowd.is_empty():
		_invalid("%s: the card overlaps %s" % [name, crowd])
		return
	if not inside or not _card.is_visible_in_tree() or rect.size.x < 100.0:
		_invalid("%s: the card is not in frame" % name)
		return
	await _save_plate(name)


func _save_plate(name: String) -> void:
	var img: Image = await PlateSight.grab(self)
	var path := _out_dir.path_join(name + ".png")
	var err := img.save_png(path)
	if err != OK:
		_invalid("could not save %s (error %d)" % [path, err])
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


## The names of the other visible HUD panels, buttons and labels whose rect
## meets `rect`. Pieces inside another listed piece are not listed again.
func _overlaps(rect: Rect2) -> Array[String]:
	var view := root.get_visible_rect().size
	var hits: Array[String] = []
	for node in _main.find_children("*", "Control", true, false):
		var c := node as Control
		if c == _card or _card.is_ancestor_of(c) or not c.is_visible_in_tree():
			continue
		if not (c is PanelContainer or c is Button or c is Label):
			continue
		if c is Label and (c as Label).text == "":
			continue
		var r := c.get_global_rect()
		if r.size.x * r.size.y > view.x * view.y * 0.5 or r.size.x < 1.0:
			continue
		if r.intersects(rect):
			hits.append("%s%s" % [c.name, r])
	return hits


## `count` indoor walkable object-free cells, three apart so no two spills
## merge, nearest the first entrance door first.
func _indoor_cells(count: int) -> Array[Vector2i]:
	var grid := _sim.grid
	var door := _sim.layout.door_cell(grid, _sim.layout.entrances[0])
	var found: Array[Vector2i] = []
	for y in grid.size.y:
		for x in grid.size.x:
			var c := Vector2i(x, y)
			if grid.is_indoor(c) and grid.is_walkable(c) and grid.object_at(c) == 0:
				found.append(c)
	found.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return absi(a.x - door.x) + absi(a.y - door.y) < absi(b.x - door.x) + absi(b.y - door.y)
	)
	var picked: Array[Vector2i] = []
	for c in found:
		var apart := true
		for p in picked:
			apart = apart and maxi(absi(p.x - c.x), absi(p.y - c.y)) >= 3
		if apart:
			picked.append(c)
		if picked.size() == count:
			break
	return picked
