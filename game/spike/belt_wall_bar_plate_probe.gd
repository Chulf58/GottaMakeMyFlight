extends SceneTree
## Windowed plates of the red bar a Belt line refused by a wall draws on the
## blocking wall edge (decision a-belt-refused-by-a-wall-draws-a-red-bar-on-the-
## blocking-wal, board 16ae0865 part 8). Boots main.tscn with the starter shell,
## adds the reference interior (the debug starter button: the divider wall
## across row 9 with its scanners, desks and seats), picks the Belt tool and
## drags a line from the landside hall north across the divider. Four plates:
## a close view from the landside, a low view from the airside with the
## scanners between camera and bar, the game camera's angle at PLAY_DISTANCE,
## and the game's own camera at its start zoom. Proof before each save: the
## plan is refused BELT_WALL at the divider
## edge, one bar is live in the ghost, and the bar's centre and both ends are
## inside the viewport by MARGIN_PX. The occlusion ray from the camera to the
## bar centre is printed; the close, play and distance plates also require a clear
## line of sight. Otherwise PROBE_INVALID, exit 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/belt_wall_bar_plate_probe.gd [-- --out=<dir>]
##
## Plates go to tools/blender/out/belt-wall-bar/ unless --out names a directory.

const OUT_REL := "res://../tools/blender/out/belt-wall-bar"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const SETTLE_FRAMES := 8
## How far the play-zoom plate stands from the terminal's middle, in metres.
const PLAY_DISTANCE := 30.0
## The line, in ReferenceTerminal cells (before the grid's offset): from the
## landside hall north across the divider into the airside.
const FROM := Vector2i(16, 12)
const TO := Vector2i(16, 6)

var _out_dir := ""
var _failed := false
var _main: Node3D
var _build: BuildMode
var _menu: BuildMenu
var _game_cam: Camera3D
var _probe_cam: Camera3D


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.get_slice("=", 1)
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
	_main = load(MAIN_SCENE).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(randi())
	root.add_child(_main)
	_game_cam = _main.get_node("TycoonCamera/Camera3D")
	_build = _main.get_node("BuildMode")
	_menu = _main.get_node("BuildMenu")
	await _frames(60)
	var filled := ReferenceTerminal.fill_interior(_build.grid)
	print("PROBE interior ok=%s" % filled.ok)
	if not filled.ok:
		_invalid("the reference interior was refused: %s" % filled.reason_text())
		_finish()
		return
	var offset := ReferenceTerminal.offset_on(_build.grid)
	var from := FROM + offset
	var to := TO + offset
	# A new game has the Belt behind a tier (BuildUnlocks); the plate is of the ghost.
	_build.unlocks = null
	_build.require_unlocks = false
	_build.set_tool(BuildMode.Tool.BELT)
	print("PROBE unlock gate lifted tool=%d belt=%d" % [_build.tool, BuildMode.Tool.BELT])
	if _build.tool != BuildMode.Tool.BELT:
		_invalid("the Belt tool was not picked")
		_finish()
		return
	_point_at(_game_cam, to)
	_build.begin_area(_build.grid.cell_to_world(from))
	_build.move_area(_build.grid.cell_to_world(to))
	await _frames(SETTLE_FRAMES)
	var plan := _build._belt_plan
	if plan == null:
		_invalid("no belt plan after the drag")
		_finish()
		return
	print(
		(
			"PROBE offset=%s from=%s to=%s ok=%s reason=%d wall_cell=%s wall_side=%d status='%s'"
			% [
				offset,
				from,
				to,
				plan.result.ok,
				plan.result.reason,
				plan.wall_cell,
				plan.wall_side,
				_build.status_text()
			]
		)
	)
	var divider := Vector2i(16, ReferenceTerminal.DIVIDER_Y) + offset
	if (
		plan.result.reason != BuildResult.Reason.BELT_WALL
		or plan.wall_cell != divider
		or plan.wall_side != BuildGrid.Side.NORTH
	):
		_invalid("the line is not refused at the divider edge %s NORTH" % divider)
		_finish()
		return
	var bars := _live_bars()
	if bars.size() != 1:
		_invalid("expected one live wall bar, found %d" % bars.size())
		_finish()
		return
	var bar := bars[0]
	var centre := bar.global_position
	_probe_cam = Camera3D.new()
	_probe_cam.fov = 50.0
	root.add_child(_probe_cam)
	_probe_cam.look_at_from_position(centre + Vector3(4.5, 5.0, 6.5), centre)
	await _plate("belt_wall_bar_close", _probe_cam, to, bar, true)
	_probe_cam.look_at_from_position(centre + Vector3(2.5, 1.4, -5.5), centre)
	await _plate("belt_wall_bar_through", _probe_cam, to, bar, false)
	# The game camera's angle, PLAY_DISTANCE from the terminal's middle.
	var middle := _build.grid.cell_to_world(Vector2i(15, 9) + offset)
	var ahead := -_game_cam.global_basis.z
	_probe_cam.look_at_from_position(middle - ahead * PLAY_DISTANCE, middle)
	await _plate("belt_wall_bar_play", _probe_cam, to, bar, true)
	_probe_cam.current = false
	_game_cam.current = true
	await _plate("belt_wall_bar_distance", _game_cam, to, bar, true)
	_finish()


## The ghost's live boxes that use the blocking-wall material.
func _live_bars() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in _build._ghost.get_children():
		if child.is_queued_for_deletion() or not child is MeshInstance3D:
			continue
		if (child as MeshInstance3D).material_override == _build._wall_block_material:
			out.append(child as MeshInstance3D)
	return out


## Puts the probe pointer over `cell` as `cam` sees it, so the drag stays live.
func _point_at(cam: Camera3D, cell: Vector2i) -> void:
	_build.pointer_override = cam.unproject_position(_build.grid.cell_to_world(cell))


func _plate(
	name: String, cam: Camera3D, to: Vector2i, bar: MeshInstance3D, need_clear: bool
) -> void:
	cam.current = true
	_point_at(cam, to)
	await _frames(SETTLE_FRAMES)
	var frame := root.get_visible_rect().grow(-MARGIN_PX)
	var half := (bar.mesh as BoxMesh).size.x / 2.0
	var ends := [
		["centre", bar.global_position],
		["end_a", bar.global_transform * Vector3(-half, 0.0, 0.0)],
		["end_b", bar.global_transform * Vector3(half, 0.0, 0.0)],
	]
	for pair: Array in ends:
		var world: Vector3 = pair[1]
		var at := cam.unproject_position(world)
		var inside := not cam.is_position_behind(world) and frame.has_point(at)
		print("INFRAME %s %s world=%s screen=%s in=%s" % [name, pair[0], world, at, inside])
		if not inside:
			_invalid("%s: bar %s is outside the viewport frame" % [name, pair[0]])
	var space := cam.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(cam.global_position, bar.global_position)
	var hit := space.intersect_ray(ray)
	var blocker: Object = hit.get("collider")
	print(
		(
			"OCCLUSION %s hit=%s at=%s"
			% [name, blocker.get_path() if blocker is Node else "none", hit.get("position")]
		)
	)
	if need_clear and not hit.is_empty():
		_invalid("%s: the line of sight to the bar is blocked" % name)
	print(
		(
			"PLATE %s pointer=%s status='%s' bars=%d"
			% [name, _build.pointer_override, _build.status_text(), _live_bars().size()]
		)
	)
	if _failed:
		return
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := _out_dir.path_join(name + ".png")
	if img.save_png(path) != OK:
		_invalid("could not save " + path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _finish() -> void:
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)
