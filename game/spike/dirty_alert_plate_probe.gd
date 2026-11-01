extends SceneTree
## Windowed plate of the dirty-terminal alert card (decision cleaner-staff-and-
## messes-visits-leave-messes-bins-fill-pooled-cleaners-nearest-mess, point 6;
## board Cleaner 5/5). Boots the real main scene with a new random sim seed
## (printed), builds ReferenceTerminal through the HUD's starter-terminal
## button, and:
##   1 clean: no mess, the card must be hidden (the control)
##   2 dirty: DirtyAlert.SHOW_AT fresh spills put on indoor floor, the HUD
##     refreshed; the card must show, with its rect inside the viewport, the
##     hire-a-cleaner text, and a plate is saved (dirty_alert_hire)
##   3 cleaner hired: the text must change to the bins text (dirty_alert_bins)
##   4 cleaned: every mess cleaned, the card must clear itself
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
	await _plate("dirty_alert_hire")


func _phase_hired() -> void:
	_sim.staff.hire(StaffMember.Role.CLEANER)
	_hud.refresh()
	await _frames(2)
	print("HIRED cleaners=1 text=%s" % _card.card_text())
	if _card.card_text() != DirtyAlert.BINS_TEXT:
		_invalid("the card does not show the bins text once a cleaner is hired")
		return
	await _plate("dirty_alert_bins")


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
func _plate(name: String) -> void:
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
