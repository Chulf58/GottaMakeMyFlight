extends "res://tests/landside/landside_views_plates_probe.gd"
## Windowed plates of the three landside residuals fixed under board 5fb27ab3, from
## above, in the real main.tscn (the helpers are the views probe's):
##   lanes   a car on the lot exits' run east along the far carriageway (clear of the
##           centre line), a car at road_in's start (its tail on the road's drawn
##           end), and the berth cars below
##   berth   a car mid pull-in at berth 7 and one mid pull-out at berth 6, close up:
##           the kerb-side corners stay on the road
## The cars are a forced fixture: the sim holds them on their lanes at chosen
## positions, so the plates are evidence of the geometry, not of play.
##
## Run (the windowed slot is taken by the caller; one windowed Godot run at a time):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://tests/landside/landside_residuals_probe.gd
## Plates go to tools/blender/out/landside-residuals/.

const OUT_DIR := "res://../tools/blender/out/landside-residuals"

var _subjects := {}


func _run() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_DIR).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	await _boot()
	if not _landside.build_curb(1):
		_invalid("curb spot 1 refused")
	_fixture()
	_views.snap()
	await _plate_lanes()
	await _plate_berth()
	await _plate_berth_steep()
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _put(
	label: String,
	lane: LandsideVehicle.Lane,
	lot: int,
	stop: int,
	pos_mm: int,
	stage: LandsideVehicle.Stage
) -> void:
	var id := _landside.add_vehicle(
		LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.DROP, [] as Array[int]
	)
	var v := _landside.get_vehicle(id)
	v.lane = lane
	v.lot = lot
	v.stop = stop
	v.pos_mm = pos_mm
	v.stage = stage
	_subjects[label] = id
	var at := _landside.world_position(v)
	print("FIXTURE %s id=%d at %s heading %s" % [label, id, at, _landside.heading(v)])


func _fixture() -> void:
	var paths := _landside.paths
	# road_in's start first: later cars are moved off road_in, so it keeps position 0.
	_put("spawn", LandsideVehicle.Lane.ROAD_IN, 0, -1, 0, LandsideVehicle.Stage.DRIVE)
	var exit0 := LandsideDefinition.length_mm(_landside.definition.lots[0].exit)
	var exit1 := LandsideDefinition.length_mm(_landside.definition.lots[1].exit)
	_put("exit0", LandsideVehicle.Lane.LOT_EXIT, 0, -1, exit0 - 2200, LandsideVehicle.Stage.LEAVE)
	_put("exit1", LandsideVehicle.Lane.LOT_EXIT, 1, -1, exit1 - 13000, LandsideVehicle.Stage.LEAVE)
	_put(
		"pull_in7",
		LandsideVehicle.Lane.BERTH,
		0,
		7,
		paths.berth_stand[7] - 2600,
		LandsideVehicle.Stage.DRIVE
	)
	_put(
		"pull_out6",
		LandsideVehicle.Lane.BERTH,
		0,
		6,
		paths.berth_stand[6] + 2300,
		LandsideVehicle.Stage.LEAVE
	)


func _prove(keys: Array, label: String) -> bool:
	var ok := true
	for key in keys:
		var node := _views.node_for(_subjects[key])
		if node == null:
			_invalid("%s/%s: not drawn" % [label, key])
			return false
		ok = _prove_in_frame("%s/%s" % [label, key], _aabb_of(node)) and ok
		ok = _prove_visible("%s/%s" % [label, key], node) and ok
	return ok


func _plate_lanes() -> void:
	await _aim("lanes", Vector3(28.0, 0.0, -50.5), 44.0, 0.0)
	var ok := await _prove_edge()
	ok = _prove(["spawn", "exit0", "exit1", "pull_in7", "pull_out6"], "lanes") and ok
	var img := await _grab()
	if ok:
		_keep(img, "landside_residuals_lanes.png")


## The road's drawn east end (x 43, through road z -50.5 to -41.25) is in frame.
func _prove_edge() -> bool:
	var box := AABB(Vector3(38.0, 0.0, -50.5), Vector3(5.0, 0.2, 9.25))
	return _prove_in_frame("lanes/road east end", box)


func _plate_berth() -> void:
	await _aim("berth", Vector3(20.0, 0.0, -56.5), 20.0, 0.0)
	var ok := _prove(["pull_in7", "pull_out6"], "berth")
	var img := await _grab()
	if ok:
		_keep(img, "landside_residuals_berth.png")


## The same two cars where the taper is steepest: just leaving the road line going in,
## just back on it going out.
func _plate_berth_steep() -> void:
	var paths := _landside.paths
	_landside.get_vehicle(_subjects["pull_in7"]).pos_mm = paths.berth_split[7] + 700
	_landside.get_vehicle(_subjects["pull_out6"]).pos_mm = paths.berth_join[6] - 700
	_views.snap()
	for key in ["pull_in7", "pull_out6"]:
		var v := _landside.get_vehicle(_subjects[key])
		print(
			"STEEP %s at %s heading %s" % [key, _landside.world_position(v), _landside.heading(v)]
		)
	await _aim("berth_steep", Vector3(20.0, 0.0, -56.0), 24.0, 0.0)
	var ok := _prove(["pull_in7", "pull_out6"], "berth_steep")
	var img := await _grab()
	if ok:
		_keep(img, "landside_residuals_berth_steep.png")
