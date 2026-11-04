extends SceneTree
## Windowed plates of the checklist card (decision checklist-card-shows-what-the-
## airport-still-needs, board 5018e594). Boots main.tscn with a new random sim
## seed (printed), the clock paused, and at 1920x1080 saves:
##   start    a new game: nothing built, every opening line still to do
##   built    after the HUD's starter terminal: the entrance, desk, scanner and
##            gate desk stand; the staff lines ask to hire
##   agent    one check-in agent hired and stepped to the desk: check-in ticks
##   open     everything staffed and the airport open: only the starter line
##   gap      the security officers fired after opening: the starter line over
##            "Your airport needs" and its hire line
## Each plate proves the card is inside the viewport by MARGIN_PX, centred in
## the top band and clear of every other top HUD rectangle, and that it has the
## rows the plate is about, each inside the card (all printed). Otherwise PROBE_INVALID is printed
## and the probe exits 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/checklist_card_plates_probe.gd
##
## Plates go to tools/blender/out/checklist-card/.

const OUT_REL := "res://../tools/blender/out/checklist-card"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 4.0
const SIZE := Vector2i(1920, 1080)
const OTHERS: Array[String] = [
	"MoneySlot",
	"RatingCard",
	"OffersButton",
	"FlightPanel",
	"AlertHistoryButton",
	"MoodToggle",
	"DeparturesToggle",
	"BuildModeSign",
]

var _out_dir := ""
var _failed := false
var _main: Node
var _staff: StaffPanel
var _sim: StaffSim
var _clock: SimClock
var _hud: PassengerHud


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var world_seed := randi()
	seed(world_seed)
	print("PROBE seed=%d out_dir=%s" % [world_seed, _out_dir])
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	root.size = SIZE
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(randi())
	root.add_child(_main)
	_clock.set_paused(true)
	_staff = _main.get_node("StaffPanel")
	_sim = _main.get_node("Staff")
	_hud = _main.get_node("PassengerHud")
	await _frames(30)
	await _plate("start", 5)
	_hud.press_starter_terminal()
	await _frames(20)
	await _plate("built", 5)
	_sim.hire(StaffMember.Role.CHECKIN)
	_step_until(func() -> bool: return _sim.on_duty_count(StaffMember.Role.CHECKIN) > 0)
	_clock.set_paused(true)
	await _frames(20)
	await _plate("agent", 5)
	StaffTestKit.staff_all(_sim)
	_step_until(func() -> bool: return (_main.get_node("FlightSim") as FlightSim).opened_tick >= 0)
	_clock.set_paused(true)
	_staff.poll_gaps()
	await _frames(20)
	await _plate("open", 0)
	var security := StaffMember.Role.SECURITY
	for i in 10:
		if _sim.count(security) - _sim.leaving_count(security) == 0:
			break
		_sim.fire(security)
	_staff.poll_gaps()
	await _frames(20)
	await _plate("gap", 1)
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


## Steps the sim clock by hand until `done` or 3000 ticks.
func _step_until(done: Callable) -> void:
	_clock.set_paused(false)
	var start := _clock.tick
	while not done.call() and _clock.tick - start < 3000:
		_clock.advance(SimClock.STEP)
	print("stepped %d ticks, done=%s" % [_clock.tick - start, done.call()])
	if not done.call():
		_invalid("the step did not reach its state")


## Saves plate `label`, which must show exactly `want_rows` rows.
func _plate(label: String, want_rows: int) -> void:
	_hud.refresh()
	await _frames(5)
	var card := _staff.hint_card()
	var view := root.get_visible_rect().size
	var rect := card.get_global_rect()
	var rows := _staff.checklist().rows()
	print(
		(
			"PLATE %s view=%s card=%s title='%s' rows=%d lines=%s"
			% [label, view, rect, _staff.hint_label().text, rows.size(), _staff.card_lines()]
		)
	)
	var screen := Rect2(Vector2.ZERO, view).grow(-MARGIN_PX)
	if not card.is_visible_in_tree() or not screen.encloses(rect):
		_invalid("%s: card %s not in frame %s" % [label, rect, screen])
	if absf(rect.get_center().x - view.x / 2.0) > 1.0:
		_invalid("%s: card is not centred" % label)
	if rect.position.y >= view.y * 0.4:
		_invalid("%s: card is not in the top band" % label)
	if rows.size() != want_rows:
		_invalid("%s: %d rows, wanted %d" % [label, rows.size(), want_rows])
	if rect.size.y < 40.0:
		_invalid("%s: card is only %.0f px tall" % [label, rect.size.y])
	for row: Control in rows:
		if not rect.encloses(row.get_global_rect()):
			_invalid("%s: row %s sticks out of the card" % [label, row.get_global_rect()])
	for node_name in OTHERS:
		var other := _main.find_child(node_name, true, false) as Control
		if other != null and other.is_visible_in_tree():
			var other_rect := other.get_global_rect()
			print("  other %s %s" % [node_name, other_rect])
			if other_rect.intersects(rect):
				_invalid("%s: card overlaps %s" % [label, node_name])
	var image := root.get_texture().get_image()
	var path := _out_dir.path_join("checklist_%s.png" % label)
	image.save_png(path)
	print("saved ", path)
