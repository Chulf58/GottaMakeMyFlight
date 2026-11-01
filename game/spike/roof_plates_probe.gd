extends SceneTree
## Windowed plate probe for the player-built terminal's roof, roof cutaway and
## gap markers (board 284993b8, decision player-built-terminal-technical-
## design-site-plot-indoor-mask-passenger-eligibility point 7: the look is
## decided by plates). It builds its own scene and never loads main.tscn: the
## site glb at the world origin (decision terminal-site-asset-lot-paving-flat-
## pad-height-0-22-dips-dropped), a BuildGrid at the site frame (86 x 40 cells
## from (-43, 0.22, -100)), floor, walls and doors built in code, drawn by
## BuildView, RoofView and GapMarkers, seen through the real TycoonCamera.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/roof_plates_probe.gd
## `-- --layout-only` builds the layout and checks its counts with no plates,
## so it runs headless.
##
## Layout: building A, an L of a 30 x 18 hall and a 10 x 8 north wing, walled
## all round with an entrance on the south (road) side and an exit on the
## wing's north (plane) side, so it is indoor and roofed; building B, a 10 x 10
## box whose south wall has a three-edge gap, so it is not indoor, has no roof
## and shows one gap run. The roof height is a plate decision (kit walls 2.5 m
## or the old Toon facade 5.2 m), so every roof plate is made for both options:
## "kit" (top 2.8 m, fascia 0.6 m) and "facade" (top 5.2 m, fascia 2.9 m down
## to just under the 2.5 m walls). No world seed: nothing here is random.
##
## Plates (tools/blender/out/roof_prototype/): per option, six orthographic
## views of building A's roof alone at true scale beside a 1 m cube; the roof
## zoomed out (150 m); the roof at distance (280 m, both buildings); the roof
## mid-fade (level 0.5); the roof held drawn at 40 m (how the roof meets the
## walls); then, roof option free, the roof gone at 45 m with the wall cutaway
## at two headings, and building B's gap marker close up. A contact sheet per
## batch. Every plate proves each subject is in frame (projected bounds inside
## the viewport by MARGIN_PX, and at least a minimum size) and visible (rays
## from the camera to points on the subject's surface whose first hit lands
## on that point, with the site, every wall, post, floor tile, the roof and
## the gap bars as colliders); otherwise it prints PROBE_INVALID, saves no
## plate and exits 1.

const OUT_REL := "res://../tools/blender/out/roof_prototype"
const CAMERA := "res://camera/tycoon_camera.tscn"
const SITE := "res://assets/buildings/tp_airport_site.glb"
## Where main.tscn stands the shell glb (Airside/Terminal, z -80); the site
## glb keeps the shell's frame, so its plot spans world z -100 to -60.
const SITE_POSITION := Vector3(0.0, 0.0, -80.0)
const GRID_SIZE := Vector2i(86, 40)
const GRID_ORIGIN := Vector3(-43.0, 0.22, -100.0)
const HALL := Rect2i(20, 14, 30, 18)
const WING := Rect2i(20, 6, 10, 8)
## The entrance faces in from the south wall, the exit from the wing's north.
const ENTRANCE := Vector2i(34, 31)
const EXIT := Vector2i(24, 6)
const OPEN_BOX := Rect2i(58, 18, 10, 10)
const GAP_XS: Array[int] = [61, 62, 63]
const EXPECT_INDOOR := 620
const EXPECT_GAPS := 3
const EXPECT_RUNS := 1
## [label, roof_height, fascia_depth]: the ruled tall roof (decision player-
## built-terminal-roof-tall-5-2-m-roof-with-the-facade-f). The low option
## (2.8 m, 0.6 m) is no longer drawn by default.
const OPTIONS := [["tall", 5.2, 2.9]]
## The distance the start camera frames the built area at (frame_start_view),
## 41.2 m as the conductor measured it in the game.
const HOME_DISTANCE := 41.2
const SIX_AXIS := {
	"front": Vector3(0, 0, 1),
	"back": Vector3(0, 0, -1),
	"left": Vector3(-1, 0, 0),
	"right": Vector3(1, 0, 0),
	"top": Vector3(0, 1, 0),
	"bottom": Vector3(0, -1, 0),
}
const YAW := 0.7
const MARGIN_PX := 8.0
## A ray "sees" a target point when its first hit lands this close to it.
const HIT_TOLERANCE := 0.05
const HANG_LIMIT_MS := 90000
const STAGE_LIMIT_MS := 120000
const TILE := Vector2i(640, 360)

var _out_dir := ""
var _failed := false
var _stage := "init"
var _heartbeat_ms := 0
var _stage_started_ms := 0
var _guard_mutex := Mutex.new()
var _guard_stop := false
var _guard: Thread
## `-- --proof-only` runs every shot's camera and proofs but grabs and saves
## nothing, so the framing runs headless. `--break-frame` moves each shot's
## camera 200 m off its subject and `--break-occlusion` lays a slab over the
## whole site 8 m up: both must end in PROBE_INVALID and exit 1, the probe's
## control that its proofs can fail.
var _proof_only := false
var _break_frame := false
var _break_occlusion := false


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_beat("init")
	_guard = Thread.new()
	_guard.start(_watch)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	_beat(_stage)
	return false


func _beat(stage: String) -> void:
	_guard_mutex.lock()
	if stage != _stage:
		_stage_started_ms = Time.get_ticks_msec()
	_stage = stage
	_heartbeat_ms = Time.get_ticks_msec()
	_guard_mutex.unlock()


## Guard thread: a frozen main thread never reaches _process, and a stage stuck
## on a signal that never comes keeps beating, so check both from here
## (anti-pattern a-frame-counting-watchdog-cannot-catch-a-stuck-main-thread).
func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_guard_mutex.lock()
		var stop := _guard_stop
		var now := Time.get_ticks_msec()
		var idle_ms := now - _heartbeat_ms
		var stage_ms := now - _stage_started_ms
		var stage := _stage
		_guard_mutex.unlock()
		if stop:
			return
		if idle_ms > HANG_LIMIT_MS or stage_ms > STAGE_LIMIT_MS:
			print(
				(
					"PROBE_INVALID hang stage=%s no heartbeat for %d ms, in stage for %d ms"
					% [stage, idle_ms, stage_ms]
				)
			)
			OS.crash("roof plates probe hung")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_proof_only = args.has("--proof-only")
	_break_frame = args.has("--break-frame")
	_break_occlusion = args.has("--break-occlusion")
	print(
		(
			"PROBE modes proof_only=%s break_frame=%s break_occlusion=%s"
			% [_proof_only, _break_frame, _break_occlusion]
		)
	)
	var grid := _build_layout()
	if args.has("--layout-only") or _failed:
		var check := _scene(grid, false)
		_report_views(check)
		(check["holder"] as Node).free()
		_finish()
		return
	for option in OPTIONS:
		await _plate_six_axis(grid, option)
	var ctx := _scene(grid, true)
	_report_views(ctx)
	# The ruled tall roof at every zoom, then the gap marker close and at the
	# camera's home distance, on one 3 x 3 sheet.
	_set_option(ctx, OPTIONS[0])
	var sheet := Image.create(TILE.x * 3, TILE.y * 3, false, Image.FORMAT_RGBA8)
	var shots := [
		["roof_far", 150.0, YAW, -1.0, ["roof", "cube"]],
		["roof_distance", 280.0, YAW, -1.0, ["roof", "open_box"]],
		["roof_fading", 110.0, YAW, 0.5, ["roof"]],
		["roof_held_40m", 40.0, YAW, 0.0, ["roof_edge"]],
		# The zoom rule hides the roof below 100 m; held drawn here to judge it.
		["roof_home_41m", HOME_DISTANCE, YAW, 0.0, ["roof"]],
		["gap_marker_close", 15.0, YAW, -1.0, ["gap_bars", "gap_sign"]],
		["gap_marker_home", HOME_DISTANCE, YAW, -1.0, ["gap_bars_far", "gap_sign"]],
	]
	for i in shots.size():
		await _shot(ctx, shots[i], sheet, Vector2i(i % 3, floori(i / 3.0)))
	var cut_sheet := Image.create(TILE.x * 2, TILE.y, false, Image.FORMAT_RGBA8)
	var others := [
		["cutaway_yaw40", 45.0, YAW, -1.0, ["hall_floor"]],
		["cutaway_yaw220", 45.0, YAW + PI, -1.0, ["hall_floor"]],
	]
	for i in others.size():
		await _shot(ctx, others[i], cut_sheet, Vector2i(i, 0))
	if not _proof_only:
		_save(sheet, "roof_contact_sheet.png")
		_save(cut_sheet, "cutaway_gap_sheet.png")
	(ctx["holder"] as Node).queue_free()
	await _frames(2)
	_finish()


func _finish() -> void:
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	# The headless dummy renderer never draws, so frame_post_draw never comes.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _grab() -> Image:
	await _frames(4)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


## Blit `img` into the TILE-sized tile at (column, row) `place` of a sheet.
func _blit(sheet: Image, img: Image, place: Vector2i) -> void:
	var copy := img.duplicate() as Image
	copy.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
	var at := place * TILE
	if at.y + TILE.y <= sheet.get_height():
		sheet.blit_rect(copy, Rect2i(Vector2i.ZERO, TILE), at)


# ------------------------------------------------------------ layout


## The grid with both buildings, checked against the expected counts.
func _build_layout() -> BuildGrid:
	_beat("layout")
	var grid := BuildGrid.new(GRID_SIZE, GRID_ORIGIN)
	var edits: Array[BuildEdit] = []
	for area: Rect2i in [HALL, WING, OPEN_BOX]:
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_apply_all(grid, edits, "floor")
	_apply_all(grid, _closing_walls(grid), "outer wall")
	for door in [[&"entrance_door", ENTRANCE, 2], [&"exit_door", EXIT, 0]]:
		var place := BuildEdit.place_object(door[0], door[1], door[2])
		var problem := DoorPlacement.check(grid, place)
		for step in DoorPlacement.edits_for(grid, place):
			if not problem.ok:
				break
			problem = grid.apply(step)
		if not problem.ok:
			_invalid("%s refused: %s" % [door[0], problem.reason_text()])
	var gaps: Array[BuildEdit] = []
	for x in GAP_XS:
		gaps.append(BuildEdit.remove_wall(Vector2i(x, OPEN_BOX.end.y - 1), BuildGrid.Side.SOUTH))
	_apply_all(grid, gaps, "gap")
	var indoor := 0
	for y in grid.size.y:
		for x in grid.size.x:
			indoor += 1 if grid.is_indoor(Vector2i(x, y)) else 0
	var gap_count := EnclosureGaps.gap_edges(grid).size()
	var run_count := EnclosureGaps.gap_runs(grid).size()
	print(
		(
			"LAYOUT indoor=%d (want %d) gaps=%d (want %d) runs=%d (want %d) doors=%d"
			% [
				indoor,
				EXPECT_INDOOR,
				gap_count,
				EXPECT_GAPS,
				run_count,
				EXPECT_RUNS,
				DoorPlacement.ways_out(grid).size()
			]
		)
	)
	if indoor != EXPECT_INDOOR or gap_count != EXPECT_GAPS or run_count != EXPECT_RUNS:
		_invalid("layout counts differ from the plan")
	return grid


## A plain wall on every floor edge that faces no floor.
func _closing_walls(grid: BuildGrid) -> Array[BuildEdit]:
	var edits: Array[BuildEdit] = []
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			if grid.floor_at(cell) == BuildGrid.FLOOR_NONE:
				continue
			for side in 4:
				if grid.floor_at(cell + BuildGrid.SIDE_STEP[side]) == BuildGrid.FLOOR_NONE:
					edits.append(BuildEdit.place_wall(cell, side))
	return edits


func _apply_all(grid: BuildGrid, edits: Array[BuildEdit], what: String) -> void:
	var refused := 0
	for result in grid.apply_batch(edits):
		if not result.ok:
			refused += 1
			if refused == 1:
				_invalid("%s refused: %s" % [what, result.reason_text()])
	print("BUILD %s edits=%d refused=%d" % [what, edits.size(), refused])


# ------------------------------------------------------------ scene


## The site, the grid's views and the camera rig under one holder.
func _scene(grid: BuildGrid, with_site: bool) -> Dictionary:
	_beat("scene")
	var holder := _studio()
	if with_site:
		var site := (load(SITE) as PackedScene).instantiate() as Node3D
		site.name = "Site"
		site.position = SITE_POSITION
		holder.add_child(site)
	var view := BuildView.new()
	holder.add_child(view)
	view.refresh(grid)
	grid.graph_changed.connect(func(_cells: Array[Vector2i]) -> void: view.refresh(grid))
	var rig := (load(CAMERA) as PackedScene).instantiate() as TycoonCamera
	holder.add_child(rig)
	var roof := RoofView.new()
	roof.camera = rig
	holder.add_child(roof)
	roof.bind(grid)
	var markers := GapMarkers.new()
	holder.add_child(markers)
	markers.bind(grid)
	var cube := _cube(holder, grid.cell_to_world(Vector2i(17, 33)) + Vector3(0.0, 0.5, 0.0))
	return {
		"holder": holder,
		"grid": grid,
		"view": view,
		"rig": rig,
		"cam": rig.get_node("Camera3D") as Camera3D,
		"roof": roof,
		"markers": markers,
		"cube": cube,
	}


func _report_views(ctx: Dictionary) -> void:
	var roof: RoofView = ctx["roof"]
	var markers: GapMarkers = ctx["markers"]
	print(
		(
			"VIEWS roofed_cells=%d roof_box=%s roof_meshes=%d bars=%d signs=%d pieces=%s"
			% [
				roof.roofed_cell_count(),
				roof.roof_box(),
				roof.find_children("*", "MeshInstance3D", true, false).size(),
				markers.strip_count(),
				markers.sign_count(),
				(ctx["view"] as BuildView).piece_counts(),
			]
		)
	)
	if roof.roofed_cell_count() != EXPECT_INDOOR or markers.strip_count() != EXPECT_GAPS:
		_invalid(
			(
				"views drew %d roofed cells, %d bars"
				% [roof.roofed_cell_count(), markers.strip_count()]
			)
		)
	if markers.sign_count() != EXPECT_RUNS:
		_invalid("views drew %d gap signs" % markers.sign_count())


func _set_option(ctx: Dictionary, option: Array) -> void:
	var roof: RoofView = ctx["roof"]
	roof.roof_height = option[1]
	roof.fascia_depth = option[2]
	roof.rebuild()
	print(
		(
			"OPTION %s roof_height=%.2f fascia_depth=%.2f box=%s"
			% [option[0], option[1], option[2], roof.roof_box()]
		)
	)


## Sets the roof for a shot: `forced` < 0 follows the zoom rule (RoofCutaway)
## from the rig's distance; otherwise the level is held at `forced`. The wall
## cutaway is on only while no roof is drawn, as the shell gates its facade
## (ShellCutaway's "cut only when roof is gone").
func _set_roof(ctx: Dictionary, forced: float) -> void:
	var roof: RoofView = ctx["roof"]
	var rig: TycoonCamera = ctx["rig"]
	if forced < 0.0:
		roof.cutaway.snap(rig.distance)
		roof.draw_level(roof.cutaway.roof_level)
		roof.set_process(true)
	else:
		roof.set_process(false)
		roof.draw_level(forced)
	(ctx["view"] as BuildView).cutaway_enabled = not roof.roof_node().visible


# ------------------------------------------------------------ shots


## One in-context shot: [name, distance, yaw, roof level or -1 for the rule,
## subject keys]. Returns whether the plate was saved.
func _shot(ctx: Dictionary, shot: Array, sheet: Image, place: Vector2i) -> bool:
	var name: String = shot[0]
	_beat(name)
	var grid: BuildGrid = ctx["grid"]
	var rig: TycoonCamera = ctx["rig"]
	var cam: Camera3D = ctx["cam"]
	var keys: Array = shot[4]
	var focus := _focus(ctx, keys)
	rig.position = focus + (Vector3(0.0, 0.0, 200.0) if _break_frame else Vector3.ZERO)
	rig.distance = shot[1]
	rig.yaw = shot[2]
	rig.zoom(1.0)
	_set_roof(ctx, shot[3])
	await _frames(8)
	if (keys.has("gap_bars") or keys.has("gap_bars_far")) and cam.global_position.z < focus.z:
		# The gap is on the south wall: look from the south.
		rig.yaw += PI
		await _frames(8)
	var view: BuildView = ctx["view"]
	var roof: RoofView = ctx["roof"]
	print(
		(
			"CAMERA %s pos=%s yaw=%.2f distance=%.1f roof_level=%.2f roof_visible=%s cut_edges=%d"
			% [
				name,
				cam.global_position,
				rig.yaw,
				rig.distance,
				roof.cutaway.roof_level if roof.is_processing() else float(shot[3]),
				roof.roof_node().visible,
				view.cut_edges().size(),
			]
		)
	)
	var bodies := _colliders(ctx)
	await physics_frame
	await physics_frame
	var ok := true
	for key in keys:
		ok = _prove_subject(ctx, name + "/" + str(key), key) and ok
	if name.begins_with("cutaway"):
		ok = _prove_cutaway(ctx, name) and ok
	bodies.free()
	if not ok or _proof_only:
		return ok
	var img := await _grab()
	_save(img, name + ".png")
	_blit(sheet, img, place)
	print("SHOT %s grid_origin=%s" % [name, grid.origin])
	return true


## Where the camera looks for a shot's subjects.
func _focus(ctx: Dictionary, keys: Array) -> Vector3:
	var grid: BuildGrid = ctx["grid"]
	if keys.has("gap_bars") or keys.has("gap_bars_far"):
		return EnclosureGaps.gap_runs(grid)[0].centre(grid)
	if keys.has("open_box"):
		return grid.cell_to_world(Vector2i(44, 20))
	if keys.has("roof_edge"):
		return grid.cell_to_world(ENTRANCE)
	return grid.cell_to_world(Vector2i(35, 20))


## The hall's south fascia either side of the entrance (cells x 30 to 40):
## its box from the floor to the roof top, and points on its outer face.
func _roof_edge(ctx: Dictionary) -> Array:
	var grid: BuildGrid = ctx["grid"]
	var roof: RoofView = ctx["roof"]
	var line_z := grid.origin.z + ENTRANCE.y + 1.0 + roof.overhang
	var lo := Vector3(grid.origin.x + 30.0, grid.origin.y, line_z - 1.0)
	var box := AABB(lo, Vector3(11.0, roof.roof_height, 1.0))
	var targets: Array[Vector3] = []
	for x in range(30, 41):
		var y := grid.origin.y + roof.roof_height - roof.fascia_depth * 0.5
		targets.append(Vector3(grid.origin.x + x + 0.5, y, line_z))
	return [box, targets]


## The roof is gone and the walls the camera looks from are cut; the yaw-220
## shot cuts a different set from the yaw-40 one.
func _prove_cutaway(ctx: Dictionary, name: String) -> bool:
	var roof: RoofView = ctx["roof"]
	var view: BuildView = ctx["view"]
	var cut := view.cut_edges()
	var ok := not roof.roof_node().visible and cut.size() > 0
	print(
		(
			"CUTAWAY %s roof_visible=%s cut_edges=%d ok=%s"
			% [name, roof.roof_node().visible, cut.size(), ok]
		)
	)
	if name == "cutaway_yaw40":
		ctx["cut40"] = cut
	elif ctx.has("cut40"):
		var same: bool = cut == ctx["cut40"]
		print("CUTAWAY headings differ=%s" % (not same))
		ok = ok and not same
	if not ok:
		_invalid("%s: cutaway not engaged" % name)
	return ok


## In frame, big enough, and seen (see the class notes) for one subject key.
func _prove_subject(ctx: Dictionary, label: String, key: String) -> bool:
	var cam: Camera3D = ctx["cam"]
	var grid: BuildGrid = ctx["grid"]
	var roof: RoofView = ctx["roof"]
	var markers: GapMarkers = ctx["markers"]
	var ok := false
	match key:
		"roof":
			var box := roof.roof_box()
			ok = roof.roof_node().visible
			if not ok:
				_invalid("%s: the roof is not drawn" % label)
			ok = _prove_in_frame(cam, label, _corners(box)) and ok
			ok = (
				_prove_size(
					cam, label, _corners(box), 100.0 if label.contains("distance") else 150.0
				)
				and ok
			)
			ok = _prove_seen(cam, label, _roof_targets(ctx), 0.8) and ok
		"roof_edge":
			var edge := _roof_edge(ctx)
			ok = roof.roof_node().visible
			if not ok:
				_invalid("%s: the roof is not drawn" % label)
			ok = _prove_in_frame(cam, label, _corners(edge[0])) and ok
			ok = _prove_size(cam, label, _corners(edge[0]), 200.0) and ok
			ok = _prove_seen(cam, label, edge[1], 0.8) and ok
		"cube":
			ok = _prove_in_frame(cam, label, _corners(_aabb_of(ctx["cube"])))
		"open_box":
			var lo := grid.cell_to_world(OPEN_BOX.position) - Vector3(0.5, 0.0, 0.5)
			var area := AABB(lo, Vector3(OPEN_BOX.size.x, 2.5, OPEN_BOX.size.y))
			ok = _prove_in_frame(cam, label, _corners(area))
		"hall_floor":
			var floor_lo := grid.cell_to_world(HALL.position) - Vector3(0.5, 0.0, 0.5)
			var hall := AABB(floor_lo, Vector3(HALL.size.x, 2.5, HALL.size.y))
			ok = _prove_in_frame(cam, label, _corners(hall))
			ok = _prove_seen(cam, label, _floor_targets(grid, HALL), 0.5) and ok
		"gap_bars", "gap_bars_far":
			var targets := _bar_targets(markers)
			var bars := AABB(targets[0] if not targets.is_empty() else Vector3.ZERO, Vector3.ZERO)
			for p in targets:
				bars = bars.expand(p)
			ok = _prove_in_frame(cam, label, _corners(bars.grow(0.5)))
			# Close up the bars must be big enough to judge; at home zoom the
			# sign carries the marker and the bars only need to be seen.
			var floor_px := 100.0 if key == "gap_bars" else 20.0
			ok = _prove_size(cam, label, _corners(bars), floor_px) and ok
			ok = _prove_seen(cam, label, targets, 0.8) and ok
		"gap_sign":
			# Drawn over the world (no depth test), so in frame is the proof.
			var foot := markers.sign_positions()
			if foot.is_empty():
				_invalid("%s: no gap sign" % label)
			else:
				var top: Vector3 = foot[0] + Vector3(0.0, 1.0, 0.0)
				ok = _prove_in_frame(cam, label, [foot[0] as Vector3, top])
		_:
			_invalid("%s: unknown subject" % label)
	return ok


## Points on the roof's top, on every third indoor cell each way.
func _roof_targets(ctx: Dictionary) -> Array[Vector3]:
	var grid: BuildGrid = ctx["grid"]
	var roof: RoofView = ctx["roof"]
	var out: Array[Vector3] = []
	for y in range(0, grid.size.y, 3):
		for x in range(0, grid.size.x, 3):
			if grid.is_indoor(Vector2i(x, y)):
				out.append(grid.cell_to_world(Vector2i(x, y)) + Vector3(0.0, roof.roof_height, 0.0))
	return out


## Points on the floor tiles of `area`, every third cell each way.
func _floor_targets(grid: BuildGrid, area: Rect2i) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for y in range(area.position.y + 1, area.end.y - 1, 3):
		for x in range(area.position.x + 1, area.end.x - 1, 3):
			out.append(grid.cell_to_world(Vector2i(x, y)))
	return out


## The top middle of every gap bar.
func _bar_targets(markers: GapMarkers) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for t in markers.bar_transforms():
		out.append(t.origin + Vector3(0.0, GapMarkers.BAR_HEIGHT * 0.5, 0.0))
	return out


# ------------------------------------------------------------ six-axis


## Six orthographic views of building A's roof alone at true scale, beside a
## 1 m cube, for one roof option.
func _plate_six_axis(grid: BuildGrid, option: Array) -> void:
	var label: String = option[0]
	_beat("six_axis_" + label)
	var holder := _studio()
	var roof := RoofView.new()
	roof.roof_height = option[1]
	roof.fascia_depth = option[2]
	holder.add_child(roof)
	roof.bind(grid)
	var box := roof.roof_box()
	var cube := _cube(holder, Vector3(box.end.x + 1.5, GRID_ORIGIN.y + 0.5, box.end.z + 1.5))
	var whole := box.merge(_aabb_of(cube))
	print("MEASURE roof_%s size_m=%s min=%s" % [label, box.size, box.position])
	var bodies := Node3D.new()
	holder.add_child(bodies)
	bodies.add_child(_body_for(roof.roof_node(), roof.roof_node().global_transform))
	await physics_frame
	await physics_frame
	var cam := _ortho_cam(holder)
	var sheet := Image.create(TILE.x * 3, TILE.y * 2, false, Image.FORMAT_RGBA8)
	var slot := 0
	for view_name in SIX_AXIS:
		var dir: Vector3 = SIX_AXIS[view_name]
		var up := Vector3.FORWARD if absf(dir.y) > 0.5 else Vector3.UP
		cam.look_at_from_position(whole.get_center() + dir * 200.0, whole.get_center(), up)
		cam.size = _ortho_size(cam, whole)
		var tag := "roof_%s_%s" % [label, view_name]
		await _frames(3)
		var ok := _prove_in_frame(cam, tag, _corners(whole))
		ok = _prove_in_frame(cam, tag + "/cube", _corners(_aabb_of(cube))) and ok
		# Only the roof has a body here, so any first hit is the roof (from below
		# the rays pass the one-sided top's underside and still count).
		ok = _prove_seen(cam, tag, _box_face_targets(box, dir), 0.3, true) and ok
		if ok and not _proof_only:
			var img := await _grab()
			_save(img, "six_axis_%s.png" % tag)
			_blit(sheet, img, Vector2i(slot % 3, floori(slot / 3.0)))
		slot += 1
	if not _proof_only:
		_save(sheet, "six_axis_roof_%s_sheet.png" % label)
	holder.queue_free()
	await _frames(2)


## A 5 x 5 grid of points on the face of `box` that looks along `dir`.
func _box_face_targets(box: AABB, dir: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var centre := box.get_center()
	var half := box.size * 0.5
	var a := Vector3(1, 0, 0) if absf(dir.x) < 0.5 else Vector3(0, 0, 1)
	var b := Vector3(0, 1, 0) if absf(dir.y) < 0.5 else Vector3(0, 0, 1)
	for i in 5:
		for j in 5:
			var p := centre + dir * (half * dir.abs()).length()
			p += a * half * ((i - 2) / 2.5) + b * half * ((j - 2) / 2.5)
			out.append(p)
	return out


# ------------------------------------------------------------ proofs


## Every point projects inside the viewport with a margin, and none is behind
## the camera.
func _prove_in_frame(cam: Camera3D, label: String, points: Array) -> bool:
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		if cam.is_position_behind(p):
			_invalid("%s: point %s is behind the camera" % [label, p])
			return false
		var s := cam.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
	var ok := rect.has_point(lo) and rect.has_point(hi)
	print(
		(
			"INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) size_px=(%.0f,%.0f) ok=%s"
			% [label, lo.x, lo.y, hi.x, hi.y, hi.x - lo.x, hi.y - lo.y, ok]
		)
	)
	if not ok:
		_invalid("%s: projected bounds leave the viewport" % label)
	return ok


## The subject's projected bounds are at least `min_px` on their longer side.
func _prove_size(cam: Camera3D, label: String, points: Array, min_px: float) -> bool:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		var s := cam.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
	# Measured in plate pixels: with canvas_items stretch the 3D view renders
	# at the visible rect times the stretch scale (project.godot, 1.25).
	var scale: float = ProjectSettings.get_setting("display/window/stretch/scale", 1.0)
	var size := maxf(hi.x - lo.x, hi.y - lo.y) * scale
	var ok := size >= min_px
	print("SIZE %s longest_px=%.1f min_px=%.1f ok=%s" % [label, size, min_px, ok])
	if not ok:
		_invalid("%s: %.1f px is under the %.1f px floor" % [label, size, min_px])
	return ok


## Rays from the camera to each target; a target is seen when the first hit
## lands within HIT_TOLERANCE of it (with `any_hit`, when the ray hits at
## all). At least `share` of them must be seen.
func _prove_seen(
	cam: Camera3D, label: String, targets: Array[Vector3], share: float, any_hit := false
) -> bool:
	var space := cam.get_world_3d().direct_space_state
	var ortho := cam.projection == Camera3D.PROJECTION_ORTHOGONAL
	var seen := 0
	for t in targets:
		var from := t + cam.global_basis.z * 500.0 if ortho else cam.global_position
		var beyond := 50.0 if any_hit else 0.5
		var q := PhysicsRayQueryParameters3D.create(from, t + (t - from).normalized() * beyond)
		var hit := space.intersect_ray(q)
		if hit and (any_hit or (hit["position"] as Vector3).distance_to(t) <= HIT_TOLERANCE):
			seen += 1
	var ok := targets.size() > 0 and seen >= ceili(targets.size() * share)
	print("VISIBLE %s seen=%d/%d share=%.2f ok=%s" % [label, seen, targets.size(), share, ok])
	if not ok:
		_invalid("%s: occluded or not hit (%d of %d rays)" % [label, seen, targets.size()])
	return ok


# ------------------------------------------------------------ colliders


## Static bodies for the site, every BuildView multimesh instance and object,
## the roof while it is drawn, and every gap bar.
func _colliders(ctx: Dictionary) -> Node3D:
	var bodies := Node3D.new()
	bodies.name = "ProbeColliders"
	var holder: Node3D = ctx["holder"]
	holder.add_child(bodies)
	var site := holder.get_node_or_null("Site")
	if site != null:
		for mi in site.find_children("*", "MeshInstance3D", true, false):
			bodies.add_child(_body_for(mi as MeshInstance3D, (mi as Node3D).global_transform))
	# From the views' own transform lists, not the multimeshes: a headless run
	# reads multimesh instances back as identities.
	var view: BuildView = ctx["view"]
	for piece in view.piece_counts():
		var parts := InteriorKit.meshes(piece)
		for t in view.piece_transforms(piece):
			for part in parts:
				var at: Transform3D = view.global_transform * t * (part[1] as Transform3D)
				bodies.add_child(_body_from_mesh(part[0], at))
	var markers: GapMarkers = ctx["markers"]
	for t in markers.bar_transforms():
		bodies.add_child(_body_from_mesh(markers.bar_node().multimesh.mesh, t))
	for mi in (ctx["view"] as Node).find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).is_visible_in_tree():
			bodies.add_child(_body_for(mi as MeshInstance3D, (mi as Node3D).global_transform))
	var roof: RoofView = ctx["roof"]
	if roof.roof_node().visible:
		bodies.add_child(_body_for(roof.roof_node(), roof.roof_node().global_transform))
	if _break_occlusion:
		var slab := BoxShape3D.new()
		slab.size = Vector3(400.0, 0.5, 400.0)
		var shape_node := CollisionShape3D.new()
		shape_node.shape = slab
		var body := StaticBody3D.new()
		body.position = Vector3(0.0, GRID_ORIGIN.y + 8.0, -80.0)
		body.add_child(shape_node)
		bodies.add_child(body)
	return bodies


func _body_for(mi: MeshInstance3D, at: Transform3D) -> StaticBody3D:
	return _body_from_mesh(mi.mesh, at)


func _body_from_mesh(mesh: Mesh, at: Transform3D) -> StaticBody3D:
	var faces := PackedVector3Array()
	if mesh != null:
		for p in mesh.get_faces():
			faces.append(at * p)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var shape_node := CollisionShape3D.new()
	shape_node.shape = shape
	var body := StaticBody3D.new()
	body.add_child(shape_node)
	return body


# ------------------------------------------------------------ helpers


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		out.append(mi)
	return out


func _aabb_of(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(node):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _corners(box: AABB) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in 8:
		out.append(box.get_endpoint(i))
	return out


func _cube(parent: Node, pos: Vector3) -> MeshInstance3D:
	var cube := MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.1)
	cube.material_override = mat
	cube.position = pos
	cube.name = "ReferenceCube1m"
	parent.add_child(cube)
	return cube


## A holder with the main scene's look: procedural sky, sky ambient, filmic
## tonemap, a shadowed sun.
func _studio() -> Node3D:
	var studio := Node3D.new()
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	studio.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.transform = Transform3D(
		Basis(
			Vector3(0.866025, 0, -0.5),
			Vector3(-0.353553, 0.707107, -0.612372),
			Vector3(0.353553, 0.707107, 0.612372)
		),
		Vector3(0, 20, 0)
	)
	sun.shadow_enabled = true
	studio.add_child(sun)
	root.add_child(studio)
	return studio


func _ortho_cam(parent: Node) -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.far = 1000.0
	parent.add_child(cam)
	cam.make_current()
	return cam


## Orthographic size (vertical extent) that fits the box's projection with 15% room.
func _ortho_size(cam: Camera3D, box: AABB) -> float:
	var inv := cam.global_transform.affine_inverse()
	var w := 0.0
	var h := 0.0
	for p in _corners(box):
		var local := inv * p - inv * box.get_center()
		w = maxf(w, absf(local.x) * 2.0)
		h = maxf(h, absf(local.y) * 2.0)
	var aspect := root.get_visible_rect().size.x / root.get_visible_rect().size.y
	return maxf(h, w / aspect) * 1.15
