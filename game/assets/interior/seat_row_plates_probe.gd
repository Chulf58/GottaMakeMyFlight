extends "res://spike/passenger_plates_probe.gd"
## Windowed in-game plate of a full gate seat row (board dbebe8c3, part 5): the
## row's mesh has one chair per footprint cell, and every seated passenger is
## drawn on its own cell's chair. Built on the passenger plates probe: it boots
## the real main scene with a new random sim seed (printed), builds the
## starter terminal, hires staff, spawns two crowds and runs the first flight
## at 3x until one seat row holds three passengers in their sit pose.
## Then, paused:
## - each sitter's hips are checked against its cell's chair (_check_sitter()):
##   low, over the pan, within 0.2 m of the chair's centre sideways;
## - seat_row_full: the three close up from the row's front quarter;
## - seat_row_full_side: the same from three-quarters.
## Each plate needs all three passengers shown (in frame with a margin, seen
## past every mesh, clear of the HUD; the base probe's _shown()). A failure
## prints PROBE_INVALID and the probe exits 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy --path <checkout>/game \
##     -s res://assets/interior/seat_row_plates_probe.gd
## Plates go to tools/blender/out/seat-row/.

const ROW_OUT_REL := "res://../tools/blender/out/seat-row"
const ROW_CROWDS := 2


func _run() -> void:
	_out_dir = ProjectSettings.globalize_path(ROW_OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("ROW out_dir=", _out_dir)
	await _boot()
	for i in ROW_CROWDS:
		_spawn_crowd()
	await _plate_full_row()
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	if not _saved.is_empty():
		_save(_sheet(), "contact_sheet")
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _plate_full_row() -> void:
	if not await _until("full_row", _doors_tick, func() -> bool: return _full_row().size() == 3):
		return
	_hud.press_speed(0)
	await _frames(5)
	var ids := _full_row()
	var p := _sim.get_passenger(ids[0])
	var record := _sim.grid.get_object(p.seat_object)
	print(
		(
			"ROW object=%d anchor=%s facing=%d sitters=%s"
			% [p.seat_object, record["anchor"], record["facing"], ids]
		)
	)
	for id in ids:
		_check_sitter(id)
	# The rig puts the camera at its own +z (rotation.y = yaw): turn that onto
	# the row's front, so the plate looks at the sitters' faces.
	var front := TerminalLayout.front_of(record["facing"])
	var facing_yaw := atan2(float(front.x), float(front.y))
	await _plate("seat_row_full", ids, 7.0, facing_yaw, 3)
	await _plate("seat_row_full_side", ids, 7.0, facing_yaw + PI * 0.3, 3)
	_hud.press_speed(3)


## The ids of three passengers in their sit pose on the three cells of one
## seat row, ordered by footprint index; empty while no row is full.
func _full_row() -> Array[int]:
	var rows := {}
	for id in _ids(_seated_posed):
		var p := _sim.get_passenger(id)
		var record := _sim.grid.get_object(p.seat_object)
		if record.is_empty():
			continue
		var cells := BuildCatalog.get_def(record["def"]).footprint(
			record["anchor"], record["facing"]
		)
		var index := cells.find(p.seat_cell)
		if index < 0:
			continue
		if not rows.has(p.seat_object):
			rows[p.seat_object] = [-1, -1, -1]
		rows[p.seat_object][index] = id
	for object_id: int in rows:
		var row: Array = rows[object_id]
		if not row.has(-1):
			var out: Array[int] = []
			out.assign(row)
			return out
	return []
