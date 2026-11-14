extends SceneTree
## Plates of the gate desk and its link lines (Gates 2/4, board 51bcad8a). One
## windowed run (take the slot first):
##   timeout 900 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://assets/interior/gate_desk_plates_probe.gd
## Boots main.tscn with a new random world seed (printed) and no starter shell
## (anti-pattern a-main-tscn-probe-that-builds-its-own-terminal-at-raw-cells),
## buys the land and builds one wide terminal at the site offset with two north
## exits 44 cells apart and a gate desk by each: gates A and B. With the Gates
## tray open (build mode) it takes:
##   a1 both gates with their lines, a2 and a3 each gate close up, a4 gate A's
##   desk near enough to judge its toon look;
## then the west gate's exit goes, a second exit 9 cells west gets its own desk
## and gate, and the west exit comes back: the west desk stays unlinked, its
## stand would overlap the new gate's. It takes:
##   b1 the unlinked desk next to the linked one in build mode, b2 the same out
##   of build mode (the sign stays, the lines go);
## then the east exit goes and a plain wall closes it: b3 a desk with no exit in
## reach; and c the Gates tray with the gate desk card.
## Every subject point is projected into the frame with a margin, and each desk
## gets sight lines from the camera against every visible mesh (PlateSight):
## at least one lands on it and none is blocked. Each line is proved drawn by its
## colour at the projected middle of its outside segment (a positive control),
## and absent there out of build mode. Otherwise PROBE_INVALID, exit 1. Plates go
## to tools/blender/out/gates-2/. A guard thread ends a hang (anti-pattern
## a-frame-counting-watchdog-cannot-catch-a-stuck-main-thread).

const PlateSight := preload("res://spike/plate_sight.gd")
const MAIN := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/gates-2"
const HANG_LIMIT_MS := 60000
const TOTAL_LIMIT_MS := 600000
const MARGIN_PX := 8.0
const SETTLE_FRAMES := 40
const STILL_FRAMES := 5
const STILL_LIMIT_FRAMES := 600
const FLOOR_MIN := Vector2i(10, 2)
const FLOOR_MAX := Vector2i(65, 12)
const ENTRANCE_CELL := Vector2i(30, 12)
const EXIT_A := Vector2i(20, 2)
const EXIT_B := Vector2i(64, 2)
const EXIT_N := Vector2i(11, 2)
const DESK_A := Vector2i(19, 5)
const DESK_B := Vector2i(63, 5)
const DESK_N := Vector2i(10, 5)
const ROW_A := Vector2i(14, 8)
## How far blue must stand over red for a pixel to count as the link line.
## The scene's floor, walls and paving are cream and grey (blue at or under
## red); the faint pass over a cream wall measured 0.22.
const BLUE_OVER_RED := 0.15
## The unlinked sign's disc: a fill point clear of the broken-link glyph and a point
## on its dark rim, in icon pixels from the icon's middle; how far each channel of
## the plate pixel may stand from MarkerIcons.HINT_FILL; the rim's luminance ceiling.
const FILL_POINT := Vector2(-34.0, -24.0)
const RIM_POINT := Vector2(-54.0, 0.0)
const CREAM_TOLERANCE := 0.12
const RIM_MAX_LUMINANCE := 0.45
## Scene nodes whose visible meshes can hide a desk.
const OCCLUDER_OWNERS: Array[String] = ["Airside/Terminal", "BuildMode", "RoofView"]

var _guard := Thread.new()
var _mutex := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _done := false

var _out_dir := ""
var _main: Node
var _clock: SimClock
var _grid: BuildGrid
var _mode: BuildMode
var _menu: BuildMenu
var _gates: GateDesks
var _links: GateLinksView
var _hud: PassengerHud
var _rig: TycoonCamera
var _cam: Camera3D
var _offset := Vector2i.ZERO


func _initialize() -> void:
	_beat("boot")
	_guard.start(_watch)
	var world_seed := randi()
	print("PROBE world_seed=%d" % world_seed)
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=%s" % _out_dir)
	_main = load(MAIN).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(world_seed)
	(_main.get_node("BuildMode") as BuildMode).starter_shell = false
	root.add_child(_main)
	current_scene = _main
	_clock.set_paused(true)
	_run.call_deferred()


func _run() -> void:
	await _frames(3)
	_mode = _main.get_node("BuildMode")
	_grid = _mode.grid
	_menu = _main.get_node("BuildMenu")
	_gates = _main.get_node("GateDesks")
	_links = (_main.get_node("ApronStand") as ApronStand).links_view()
	_hud = _main.get_node("PassengerHud")
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	(_mode.get_node("Ghost") as Node3D).visible = false
	_hud.dismiss_intro()
	_clock.set_paused(true)
	_offset = ReferenceTerminal.offset_on(_grid)
	if not await _two_gates():
		return
	# Each step ends the run itself (_fail) when its check fails.
	var steps: Array[Callable] = [
		_set_building.bind(true),
		_plates_linked,
		_unlink_west,
		_plates_unlinked,
		_close_east,
		_plate_no_exit,
		_plate_tray,
	]
	for step in steps:
		await step.call()
		if _done:
			return
	print("PROBE_PASS gate desk plates")
	_finish(0)


## Builds the terminal; true when its two desks made gates A and B.
func _two_gates() -> bool:
	if not _build_terminal():
		return false
	await _frames(3)
	print("PROBE gates %s unlinked %s" % [_gates.bindings, _gates.unlinked()])
	if _gates.gate_ids() != (["A", "B"] as Array[String]) or not _gates.unlinked().is_empty():
		_fail("the two desks did not make gates A and B")
		return false
	return true


## One wide terminal at the site offset, bought and built through the grid.
func _build_terminal() -> bool:
	var edits := _terminal_edits()
	var land := _mode.land_tool.land
	var wanted := {}
	for edit in edits:
		wanted[land.plot_of(edit.cell)] = true
	for plot: Vector2i in wanted:
		while not land.is_owned(plot):
			var best := Vector2i(-1, -1)
			var best_d := 1 << 30
			for candidate in land.buyable_plots():
				var d := absi(candidate.x - plot.x) + absi(candidate.y - plot.y)
				if d < best_d:
					best_d = d
					best = candidate
			if best == Vector2i(-1, -1) or not land.buy(best, null).ok:
				_fail("the land toward plot %s could not be bought" % plot)
				return false
	for edit in edits:
		if not _apply(edit):
			return false
	return true


func _apply(edit: BuildEdit) -> bool:
	var result := _grid.apply(edit)
	if not result.ok:
		_fail("edit %s at %s refused: %s" % [edit.kind, edit.cell, result.reason_text()])
	return result.ok


func _terminal_edits() -> Array[BuildEdit]:
	var out: Array[BuildEdit] = []
	for y in range(FLOOR_MIN.y, FLOOR_MAX.y + 1):
		for x in range(FLOOR_MIN.x, FLOOR_MAX.x + 1):
			out.append(BuildEdit.paint_floor(Vector2i(x, y) + _offset, BuildGrid.FLOOR_TILE, 1))
	for x in range(FLOOR_MIN.x, FLOOR_MAX.x + 1):
		if x != EXIT_A.x and x != EXIT_B.x:
			out.append(
				BuildEdit.place_wall(Vector2i(x, FLOOR_MIN.y) + _offset, BuildGrid.Side.NORTH)
			)
		if x != ENTRANCE_CELL.x:
			out.append(
				BuildEdit.place_wall(Vector2i(x, FLOOR_MAX.y) + _offset, BuildGrid.Side.SOUTH)
			)
	for y in range(FLOOR_MIN.y, FLOOR_MAX.y + 1):
		out.append(BuildEdit.place_wall(Vector2i(FLOOR_MIN.x, y) + _offset, BuildGrid.Side.WEST))
		out.append(BuildEdit.place_wall(Vector2i(FLOOR_MAX.x, y) + _offset, BuildGrid.Side.EAST))
	out.append(BuildEdit.place_object(&"entrance_door", ENTRANCE_CELL + _offset, 2))
	out.append(BuildEdit.place_object(&"exit_door", EXIT_A + _offset, 0))
	out.append(BuildEdit.place_object(&"exit_door", EXIT_B + _offset, 0))
	out.append(BuildEdit.place_object(&"seat_row", ROW_A + _offset, 0))
	out.append(BuildEdit.place_object(GateDesks.DESK, DESK_A + _offset, 0))
	out.append(BuildEdit.place_object(GateDesks.DESK, DESK_B + _offset, 0))
	return out


## Opens (on) or closes the Gates tray, which starts or ends build mode.
func _set_building(on: bool) -> bool:
	var gates_tray := BuildMenu.category_of(BuildMode.Tool.GATE_DESK)
	if _menu.build_session.active != on:
		_menu.press_category(gates_tray)
	await _frames(3)
	print(
		(
			"PROBE build mode %s: session %s tray %s links shown %s"
			% [on, _menu.build_session.active, _menu.is_tray_open(), _links.is_building()]
		)
	)
	if _menu.build_session.active != on or _links.is_building() != on:
		_fail("build mode did not turn %s" % ("on" if on else "off"))
		return false
	return true


func _plates_linked() -> void:
	var a := _gates.binding_of("A")
	var b := _gates.binding_of("B")
	var middle := _grid.cell_to_world(Vector2i(41, 3) + _offset)
	_view(middle, 72.0, 0.0)
	await _plate("a1_two_gates_linked", [a, b], [], true)
	if _done:
		return
	_view(_grid.cell_to_world(Vector2i(20, 1) + _offset), 26.0, 0.35)
	await _plate("a2_gate_a_close", [a], [], true)
	if _done:
		return
	_view(_grid.cell_to_world(Vector2i(63, 1) + _offset), 26.0, -0.35)
	await _plate("a3_gate_b_close", [b], [], true)
	if _done:
		return
	# The desk itself, near enough to judge its toon ramp and outline.
	_view(_grid.cell_to_world(Vector2i(20, 4) + _offset), 9.0, 0.5)
	# Its line's outside part runs off the top of this near view, so only the
	# desk is checked (a2 checks the line).
	await _plate("a4_desk_a_near", [a], [], true, false)


## The west exit goes (its gate's flights move to B), a gate is made by a new
## exit 9 cells west, and the west exit comes back: the west desk's only free
## exit would overlap the new gate's stand.
func _unlink_west() -> bool:
	_stage = "unlink west"
	var edits: Array[BuildEdit] = [
		BuildEdit.remove_object(_grid.object_at(EXIT_A + _offset)),
		BuildEdit.remove_wall(EXIT_N + _offset, BuildGrid.Side.NORTH),
		BuildEdit.place_object(&"exit_door", EXIT_N + _offset, 0),
		BuildEdit.place_object(GateDesks.DESK, DESK_N + _offset, 0),
		BuildEdit.place_object(&"exit_door", EXIT_A + _offset, 0),
	]
	for edit in edits:
		if not _apply(edit):
			return false
	var unlinked := _gates.unlinked()
	var desk_a := _grid.object_at(DESK_A + _offset)
	print("PROBE after the west unlink: gates %s unlinked %s" % [_gates.bindings, unlinked])
	if not unlinked.has(desk_a) or unlinked[desk_a]["why"] != GateDesks.Unlinked.STAND_OVERLAP:
		_fail("the west desk is not unlinked by a stand overlap")
		return false
	return true


func _plates_unlinked() -> void:
	var desk_a := _grid.object_at(DESK_A + _offset)
	var n := _binding_of_desk(_grid.object_at(DESK_N + _offset))
	var focus := _grid.cell_to_world(Vector2i(16, 2) + _offset)
	_view(focus, 28.0, 0.25)
	await _plate("b1_unlinked_next_to_linked", [n], [[desk_a, EXIT_A]], true)
	if _done:
		return
	if not await _set_building(false):
		return
	# Closing the tray glides the camera back over the room the tray took
	# (decision camera-makes-room-for-open-panels); let it land, then frame the
	# same view again.
	await _camera_still()
	_view(focus, 28.0, 0.25)
	await _plate("b2_unlinked_out_of_build_mode", [n], [[desk_a, EXIT_A]], false)
	if _done:
		return
	await _set_building(true)


## The east exit goes and a plain wall closes its edge: the east desk has no
## exit in reach.
func _close_east() -> bool:
	_stage = "close east"
	if not _apply(BuildEdit.remove_object(_grid.object_at(EXIT_B + _offset))):
		return false
	if not _apply(BuildEdit.place_wall(EXIT_B + _offset, BuildGrid.Side.NORTH)):
		return false
	var unlinked := _gates.unlinked()
	var desk_b := _grid.object_at(DESK_B + _offset)
	print("PROBE after the east exit went: gates %s unlinked %s" % [_gates.bindings, unlinked])
	if not unlinked.has(desk_b) or unlinked[desk_b]["why"] != GateDesks.Unlinked.NO_EXIT:
		_fail("the east desk is not unlinked for want of an exit")
		return false
	return true


func _plate_no_exit() -> void:
	var desk_b := _grid.object_at(DESK_B + _offset)
	_view(_grid.cell_to_world(Vector2i(62, 3) + _offset), 24.0, -0.3)
	await _plate("b3_unlinked_no_exit", [], [[desk_b, EXIT_B]], true)


## The Gates tray with the gate desk card, HUD and all.
func _plate_tray() -> void:
	_stage = "plate tray"
	await _frames(SETTLE_FRAMES)
	var card := _menu.card(BuildMode.Tool.GATE_DESK)
	var picture := card.find_children("*", "TextureRect", true, false)[0] as TextureRect
	var view := root.get_visible_rect()
	var rect := card.get_global_rect()
	var inside := view.grow(-MARGIN_PX).encloses(rect) and card.is_visible_in_tree()
	print(
		(
			"PLATE c_gates_tray_card card rect %s view %s in_frame=%s texture %s"
			% [rect, view, inside, picture.texture.resource_path]
		)
	)
	if not inside or picture.texture.resource_path != BuildMenu.THUMBNAIL_DIR % "gate_desk":
		_fail("the gate desk card is not in frame with its own thumbnail")
		return
	var img := await PlateSight.grab(self)
	var path := _out_dir.path_join("c_gates_tray_card.png")
	var err := img.save_png(path)
	var per_screen := view.size.x / img.get_width()
	var tray := PlateSight.to_screen(
		_menu.tray().get_global_rect().grow(24.0), per_screen, img.get_size()
	)
	var crop_err := img.get_region(tray).save_png(_out_dir.path_join("c_gates_tray_card_crop.png"))
	print("PLATE saved %s err=%d crop %s err=%d" % [path, err, tray, crop_err])
	if err != OK or crop_err != OK:
		_fail("the tray plate was not saved")


func _binding_of_desk(desk: int) -> Dictionary:
	for binding in _gates.bindings:
		if binding["desk"] == desk:
			return binding
	return {}


func _view(focus: Vector3, distance: float, yaw: float) -> void:
	_rig.position = focus
	_rig.yaw = yaw
	_rig.distance = distance
	_rig.zoom(1.0)


func _frame_rect() -> Rect2:
	return Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)


## Saves a plate (the HUD hidden) once every subject passes: each linked gate's
## desk top, exit and door point in frame, its desk seen, and its line drawn
## (`lines_on`) or not drawn; each unlinked [desk, exit cell] in frame, seen,
## with its sign drawn and no line where a line out of that exit would run.
func _plate(
	label: String, linked: Array, unlinked: Array, lines_on: bool, line_in_view := true
) -> void:
	_stage = "plate %s" % label
	await _frames(SETTLE_FRAMES)
	if not await _camera_still():
		return
	print(
		(
			"PLATE %s rig %s distance %.1f camera %s"
			% [label, _rig.position, _rig.distance, _cam.global_position]
		)
	)
	var before := _cam.global_transform
	# Hiding the HUD for the HUD-free twin would let the camera reframe the room
	# the panels took (decision camera-makes-room-for-open-panels), so the rig
	# holds still while the plate is taken.
	_rig.process_mode = Node.PROCESS_MODE_DISABLED
	var twin: Dictionary = await PlateSight.hud_twin(self, _main)
	var img: Image = twin["image"]
	_rig.process_mode = Node.PROCESS_MODE_INHERIT
	# The projections below use the camera as it is now; it must be the camera
	# the plate was taken with.
	var moved := not _cam.global_transform.is_equal_approx(before)
	print("  CAMERA still through the grab: %s" % (not moved))
	var ok := not moved
	for binding: Dictionary in linked:
		var path := GateLinksView.link_points(_grid, binding)
		ok = _framed("gate %s desk top" % binding["gate"], _desk_top(binding["desk"])) and ok
		ok = _framed("gate %s exit" % binding["gate"], path[1]) and ok
		ok = _framed("gate %s door" % binding["gate"], path[2]) and ok
		ok = (await _desk_seen("gate %s desk" % binding["gate"], binding["desk"])) and ok
		var mid := path[1].lerp(path[2], 0.75)
		var drawn := _line_blue(img, mid)
		print("  LINE gate %s middle %s drawn=%s want %s" % [binding["gate"], mid, drawn, lines_on])
		ok = ok and (drawn == lines_on or not line_in_view)
	for pair: Array in unlinked:
		var desk: int = pair[0]
		var top := _desk_top(desk)
		ok = _framed("unlinked desk %d top" % desk, top) and ok
		ok = (await _desk_seen("unlinked desk %d" % desk, desk)) and ok
		var marker := _sign_of(desk)
		if marker == null:
			print("  SIGN desk %d missing" % desk)
			ok = false
			continue
		# The sign is the cream broken-link disc: a point on its fill clear of the
		# glyph, and one on its dark rim as the control that the point is on the
		# disc (icon pixels from the icon's middle).
		var icon_px := _icon_point(marker, FILL_POINT)
		var rim_px := _icon_point(marker, RIM_POINT)
		var sign_ok := _cream(img, icon_px) and _rim(img, rim_px)
		ok = ok and sign_ok
		ok = _sign_framed(desk, marker) and ok
		ok = _sign_words(desk, marker, lines_on) and ok
		# Where a line out of its exit edge would run: 3 m out from that cell.
		var exit := _grid.cell_to_world(pair[1] + _offset)
		var would := exit + Vector3(0.0, GateLinksView.LIFT_M, -3.0)
		var stray := _line_blue(img, would)
		print("  NO LINE desk %d at %s line colour there=%s" % [desk, would, stray])
		ok = ok and not stray
	if not ok:
		# Kept apart under its own name, so the failure can be looked at.
		img.save_png(_out_dir.path_join(label + "_FAILED_CHECK.png"))
		_fail("%s: a subject check failed" % label)
		return
	var path := _out_dir.path_join(label + ".png")
	var err := img.save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	if err != OK:
		_fail("%s: not saved" % label)


## Waits until the camera has not moved for STILL_FRAMES frames in a row, so
## the plate and the projections checked against it see the same view.
func _camera_still() -> bool:
	var last := _cam.global_transform
	var still := 0
	for i in STILL_LIMIT_FRAMES:
		await _frames(1)
		var now := _cam.global_transform
		still = still + 1 if now.is_equal_approx(last) else 0
		last = now
		if still >= STILL_FRAMES:
			return true
	_fail("the camera did not come to rest in %d frames" % STILL_LIMIT_FRAMES)
	return false


## Whether the whole unlinked sign lies inside the frame margin, in layout
## pixels: the icon a SIGN_PX square standing on its foot, sized in screen
## pixels and turned into layout pixels. The sign has no world caption, so the
## icon is all there is to frame. Prints the rectangle.
func _sign_framed(desk: int, marker: Sprite3D) -> bool:
	if _cam.is_position_behind(marker.global_position):
		print("  SIGN BOUNDS desk %d: behind the camera" % desk)
		return false
	var foot := _cam.unproject_position(marker.global_position)
	var icon := MissMarkers.SIGN_PX * _layout_per_px()
	var sign_rect := Rect2(foot.x - icon / 2.0, foot.y - icon, icon, icon)
	var frame := _frame_rect()
	var sign_in := frame.encloses(sign_rect)
	print("  SIGN BOUNDS desk %d sign %s in_frame=%s frame %s" % [desk, sign_rect, sign_in, frame])
	return sign_in


## The sign's words are not drawn in the world: no Label3D hangs on it, and
## they reach HoverTarget only in build mode (`building`), through
## GateLinksView.hover_signs(), with the sign's text and a rect around its icon.
func _sign_words(desk: int, marker: Sprite3D, building: bool) -> bool:
	var labels := marker.find_children("*", "Label3D", true, false).size()
	var entries: Array[Dictionary] = []
	for entry in _links.hover_signs():
		if int(entry["key"]) == desk:
			entries.append(entry)
	var words := GateLinksView.text_of(marker)
	var want := 1 if building else 0
	var good := labels == 0 and words != "" and entries.size() == want
	if building and entries.size() == 1:
		good = good and entries[0]["text"] == words
		good = (
			good
			and (entries[0]["rect"] as Rect2).has_point(
				(
					_cam.unproject_position(marker.global_position)
					+ Vector2(0.0, -MissMarkers.SIGN_PX / 2.0)
				)
			)
		)
	print(
		(
			"  SIGN WORDS desk %d labels %d hover entries %d (want %d) text '%s' ok=%s"
			% [desk, labels, entries.size(), want, words, good]
		)
	)
	return good


func _framed(what: String, point: Vector3) -> bool:
	var px := _cam.unproject_position(point)
	var in_frame := _frame_rect().has_point(px) and not _cam.is_position_behind(point)
	print("  FRAMED %s %s -> %s in_frame=%s" % [what, point, px, in_frame])
	return in_frame


## Sight lines from the camera to three points on desk `desk` (its board and
## its counter top): at least one lands on it and none is blocked.
func _desk_seen(what: String, desk: int) -> bool:
	var node := (_mode.get_node("BuildView") as BuildView).object_node(desk)
	if node == null:
		print("  SEEN %s: no drawn node" % what)
		return false
	var owners: Array[Node] = []
	for owner_path in OCCLUDER_OWNERS:
		var owner_node := _main.get_node_or_null(owner_path)
		if owner_node != null:
			owners.append(owner_node)
	var holder := PlateSight.colliders(root, owners, {node: "desk"})
	var top := _desk_top(desk)
	var targets: Array[Vector3] = [
		top + Vector3(0.0, -0.2, 0.0), top + Vector3(0.0, -1.1, 0.0), top + Vector3(0.4, -1.0, 0.0)
	]
	var space := _cam.get_world_3d().direct_space_state
	await physics_frame
	await physics_frame
	var lines := PlateSight.sight_lines(space, _cam.global_position, targets, "desk")
	holder.free()
	var on := (lines["on_subject"] as Array).size()
	print("  SEEN %s on=%d past=%d blockers=%s" % [what, on, lines["past"], lines["blockers"]])
	return on >= 1 and (lines["blockers"] as Array).is_empty()


func _desk_top(desk: int) -> Vector3:
	var cells := GateDesks.desk_footprint(_grid, desk)
	var at := (_grid.cell_to_world(cells[0]) + _grid.cell_to_world(cells[-1])) / 2.0
	at.y = _grid.origin.y + BuildCatalog.get_def(GateDesks.DESK).height
	return at


func _sign_of(desk: int) -> Sprite3D:
	for marker in _links.signs():
		if int(marker.get_meta("desk")) == desk:
			return marker
	return null


## Layout pixels per plate pixel's worth of the fixed-size sign (the stretch
## scale), so a sign size in screen pixels converts to layout pixels.
func _layout_per_px() -> float:
	var view := root
	return 1.0 / view.get_stretch_transform().get_scale().y


## Whether the plate pixel where `point` projects is the line's blue, drawn
## plainly or faintly through a wall: blue well over red (the floor, walls,
## paving and desks are not).
func _line_blue(img: Image, point: Vector3) -> bool:
	if _cam.is_position_behind(point):
		return false
	var got := _pixel(img, _cam.unproject_position(point))
	var blue := got.b - got.r > BLUE_OVER_RED and got.b > 0.7
	print("    pixel got %s blue=%s" % [got, blue])
	return blue


## Whether the plate pixel at `layout_px` is the build-hint disc's cream
## (MarkerIcons.HINT_FILL, the game's grading drawing it a little darker or
## lighter): each channel within CREAM_TOLERANCE of it.
func _cream(img: Image, layout_px: Vector2) -> bool:
	var got := _pixel(img, layout_px)
	var want := MarkerIcons.HINT_FILL
	var cream := (
		absf(got.r - want.r) < CREAM_TOLERANCE
		and absf(got.g - want.g) < CREAM_TOLERANCE
		and absf(got.b - want.b) < CREAM_TOLERANCE
	)
	print("    pixel got %s want %s cream=%s" % [got, want, cream])
	return cream


## Whether the plate pixel at `layout_px` is the disc's dark outline (the
## control that the cream point lies on the sign): dark and clearly unlike the
## cream.
func _rim(img: Image, layout_px: Vector2) -> bool:
	var got := _pixel(img, layout_px)
	var dark := got.get_luminance() < RIM_MAX_LUMINANCE
	print("    pixel got %s rim dark=%s" % [got, dark])
	return dark


## Where `at` (icon pixels from the icon's middle) falls in layout pixels on
## `marker`'s sign, its sideways slide included: the middle stands half the
## sign's height over its foot.
func _icon_point(marker: Sprite3D, at: Vector2) -> Vector2:
	var foot := _cam.unproject_position(marker.global_position)
	var scale := MissMarkers.SIGN_PX / MarkerIcons.SIZE
	var from_foot := (
		(at + Vector2(marker.offset.x, 0.0)) * scale + Vector2(0.0, -MissMarkers.SIGN_PX / 2.0)
	)
	return foot + from_foot * _layout_per_px()


## The plate pixel at layout pixel `layout_px`, or transparent black outside.
func _pixel(img: Image, layout_px: Vector2) -> Color:
	var per_screen := root.get_visible_rect().size.x / img.get_width()
	var px := Vector2i((layout_px / per_screen).round())
	if not Rect2i(Vector2i.ZERO, img.get_size()).has_point(px):
		return Color(0.0, 0.0, 0.0, 0.0)
	return img.get_pixel(px.x, px.y)


func _frames(count: int) -> void:
	for i in count:
		_beat(_stage)
		await process_frame


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
			OS.crash("gate desk plates probe hung")


func _fail(reason: String) -> void:
	print("PROBE_INVALID %s" % reason)
	_finish(1)


func _finish(code: int) -> void:
	_mutex.lock()
	_done = true
	_mutex.unlock()
	if _guard.is_started():
		_guard.wait_to_finish()
	if _main != null:
		_main.queue_free()
	quit(code)
