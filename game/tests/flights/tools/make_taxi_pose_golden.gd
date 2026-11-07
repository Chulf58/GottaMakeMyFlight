extends SceneTree
## Builds taxi_pose_golden.bin, the old FlightPose taxi poses that
## test_movement_plan_golden.gd pins. It runs only in a copy of game/ taken
## from reference commit 7ab97c7 (before MovementPlan existed) and refuses to
## run anywhere else, so the table is never rebuilt from the code it checks.
## This folder has a .gdignore, so Godot never imports this script at HEAD and
## gdUnit4 never sees it.
##
## From the repo root in WSL (the copy must be on the Windows drive for the
## Windows Godot; GODOT is
## /mnt/c/Users/chulf/AppData/Local/Programs/Godot/Godot_v4.7.2-stable_win64_console.exe):
##
##   mkdir .ref_7ab97c7
##   git archive 7ab97c7 game | tar -x -C .ref_7ab97c7
##   cp game/tests/flights/tools/make_taxi_pose_golden.gd .ref_7ab97c7/game/
##   "$GODOT" --headless --audio-driver Dummy --path .ref_7ab97c7/game --import
##   "$GODOT" --headless --audio-driver Dummy --path .ref_7ab97c7/game \
##     -s res://make_taxi_pose_golden.gd -- \
##     --out "$(wslpath -m .ref_7ab97c7)/taxi_pose_golden.bin" \
##     --against "$(wslpath -m game/tests/flights/taxi_pose_golden.bin)"
##
## With --against it compares the new table with the committed one, route by
## route and sample by sample, and prints GOLDEN_MATCH (exit 0) or
## GOLDEN_DIFFERS with the first difference (exit 1). Copy the new table over
## the committed one only after reading that result, then rm -r .ref_7ab97c7.

const REFERENCE_COMMIT := "7ab97c7"
const REFERENCE_SHA := "7ab97c75592c2c360f88497be71ffc73552624e1"
## SHA-256 at REFERENCE_COMMIT of every file the routes and poses come from.
## A copy taken from any other commit fails here.
const FINGERPRINTS := {
	"res://flights/flight_pose.gd":
	"726f15a764d3a885a65c0d3265496cdb0736ef0c725977bddfbd0eb4f929dd2f",
	"res://flights/flight_sim.gd":
	"b295453c077102d0be67b9e475c68f136edee678eb10fca18cce9dba83fca681",
	"res://airside/airside.gd": "477b79bd33f4281beaf77e20364ca88fc0b27be6197de62dfc66d51919f9de62",
	"res://airside/taxi_graph.gd":
	"c06e6da0fe3c37eb00eb4a4dc71c4fcacef69d393697f7e9a4f7a55c9a1aa8b2",
	"res://airside/stand_placement.gd":
	"a875ff8c14334974da938c8d4b3558e9eb4519fa75b60bc955d0e3d68521cef4",
	"res://main/main.tscn": "a69607264865352c8e59656575dd74a1ea0854c07d0a54842da5e97d4f987952",
	"res://build/terminal_site.tres":
	"483e18d1940ad8657086d9470c73bac2e19e937ce5395bb3257143471bf9ee1c",
	"res://passengers/reference_terminal.gd":
	"8fa3caeadf5ff1ce8db758877ebfc61b009c5f493e7db90b0cfdfbd7ae809be1",
}
const MAIN_SCENE := "res://main/main.tscn"
## Two stands 44 m apart on the starter row, as test_airside_gate_stands.gd.
const STAND_A := {"exit": 2, "x": -22.5, "wall_z": -98.0}
const STAND_B := {"exit": 4, "x": 21.5, "wall_z": -98.0}
## Largest difference --against accepts between two builds of the table.
const SAME := 1e-6


func _initialize() -> void:
	quit(_run())


func _run() -> int:
	var args := _args()
	if not args.has("out"):
		printerr("usage: -s res://make_taxi_pose_golden.gd -- --out PATH [--against PATH]")
		return 2
	if not _at_reference():
		return 1
	var table := {
		"source_commit": REFERENCE_COMMIT, "source_sha": REFERENCE_SHA, "routes": _routes()
	}
	var file := FileAccess.open_compressed(
		args["out"], FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD
	)
	if file == null:
		printerr("cannot write %s: %s" % [args["out"], FileAccess.get_open_error()])
		return 1
	file.store_var(table)
	file.close()
	var samples := 0
	for route: Dictionary in table["routes"]:
		samples += (route["origins"] as PackedVector3Array).size()
	print("GOLDEN routes %d samples %d -> %s" % [table["routes"].size(), samples, args["out"]])
	if not args.has("against"):
		return 0
	var difference := _compare(table, args["against"])
	if difference != "":
		print("GOLDEN_DIFFERS: %s" % difference)
		return 1
	print("GOLDEN_MATCH against %s" % args["against"])
	return 0


## --name value pairs after the "--" on the command line.
func _args() -> Dictionary:
	var out := {}
	var user := OS.get_cmdline_user_args()
	for i in range(0, user.size() - 1, 2):
		out[user[i].trim_prefix("--")] = user[i + 1]
	return out


## True when every fingerprinted file is byte for byte REFERENCE_COMMIT's and
## MovementPlan does not exist yet.
func _at_reference() -> bool:
	var ok := true
	for path: String in FINGERPRINTS:
		var sha := FileAccess.get_sha256(path)
		if sha != FINGERPRINTS[path]:
			printerr("NOT_REFERENCE: %s is %s, not %s's" % [path, sha, REFERENCE_COMMIT])
			ok = false
	for entry in ProjectSettings.get_global_class_list():
		if entry["class"] == &"MovementPlan":
			printerr("NOT_REFERENCE: MovementPlan exists, so this is not %s" % REFERENCE_COMMIT)
			ok = false
	return ok


func _routes() -> Array:
	var site: SiteDefinition = load("res://build/terminal_site.tres")
	var airside := _airside()
	var grid := BuildGrid.new(site.grid_size, site.grid_origin)
	var low := site.grid_origin
	var high := site.grid_origin + Vector3(site.grid_size.x, 0.0, site.grid_size.y)
	var layouts := {
		"starter": StandPlacement.starter_stand(grid, site),
		"exit7": StandPlacement.make(7, 10.5, -150.0),
	}
	for door_x in [low.x + 0.5, high.x - 0.5]:
		for wall_z in [low.z, high.z - 1.0]:
			layouts["corner_%.1f_%.1f" % [door_x, wall_z]] = StandPlacement.make(1, door_x, wall_z)
	var routes: Array = []
	for name: String in layouts:
		airside.set_stand(layouts[name])
		_add_gate(routes, airside, name, "")
	airside.set_gate_stands({"A": STAND_A, "B": STAND_B})
	_add_gate(routes, airside, "gates_AB", "A")
	_add_gate(routes, airside, "gates_AB", "B")
	airside.free()
	return routes


## main.tscn's Airside markers and links, as the airside tests build them.
func _airside() -> Airside:
	var state: SceneState = (load(MAIN_SCENE) as PackedScene).get_state()
	var airside := Airside.new()
	for i in state.get_node_count():
		var parent := String(state.get_node_path(i, true))
		var props := {}
		for k in state.get_node_property_count(i):
			props[state.get_node_property_name(i, k)] = state.get_node_property_value(i, k)
		if parent == "./Airside" and state.get_node_type(i) == &"Marker3D":
			var marker := Marker3D.new()
			marker.name = state.get_node_name(i)
			marker.transform = props.get(&"transform", Transform3D.IDENTITY)
			airside.add_child(marker)
		elif String(state.get_node_path(i)) == "./Airside":
			airside.links = props[&"links"]
	root.add_child(airside)
	return airside


## TAXI_IN, PUSHBACK and TAXI_OUT of `gate` at every half tick, each entering
## along the previous phase's exit as PlaneView does.
func _add_gate(routes: Array, airside: Airside, name: String, gate: String) -> void:
	var previous := FlightSim.State.LANDING
	for state in [FlightSim.State.TAXI_IN, FlightSim.State.PUSHBACK, FlightSim.State.TAXI_OUT]:
		var path := airside.phase_path(state, gate)
		var entry := FlightPose.exit_dir(airside.phase_path(previous, gate))
		var ticks: int = FlightSim.PHASE_TICKS[state]
		var origins := PackedVector3Array()
		var noses := PackedVector3Array()
		for k in range(2 * ticks + 1):
			var pose := FlightPose.pose(state, k / (2.0 * ticks), path, entry)
			origins.append(pose.origin)
			noses.append(pose.basis.z)
		(
			routes
			. append(
				{
					"name": "%s %s" % [name, gate],
					"state": state,
					"ticks": ticks,
					"entry": entry,
					"points": path,
					"origins": origins,
					"noses": noses,
				}
			)
		)
		previous = state


## The first way `table` differs from the table at `path`, or "" when they
## hold the same commit, routes and samples (within SAME).
func _compare(table: Dictionary, path: String) -> String:
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return "cannot read %s: %s" % [path, FileAccess.get_open_error()]
	var old: Dictionary = file.get_var()
	file.close()
	if old.get("source_commit", "") != REFERENCE_COMMIT:
		return "committed table is from %s" % old.get("source_commit", "no commit")
	var new_routes: Array = table["routes"]
	var old_routes: Array = old["routes"]
	if new_routes.size() != old_routes.size():
		return "%d routes, committed %d" % [new_routes.size(), old_routes.size()]
	for r in new_routes.size():
		var difference := _compare_route(new_routes[r], old_routes[r])
		if difference != "":
			return "route %d (%s): %s" % [r, new_routes[r]["name"], difference]
	return ""


func _compare_route(now: Dictionary, was: Dictionary) -> String:
	for key in ["name", "state", "ticks"]:
		if now[key] != was[key]:
			return "%s %s, committed %s" % [key, now[key], was[key]]
	if (now["entry"] as Vector3).distance_to(was["entry"]) > SAME:
		return "entry %s, committed %s" % [now["entry"], was["entry"]]
	for key in ["points", "origins", "noses"]:
		var a: PackedVector3Array = now[key]
		var b: PackedVector3Array = was[key]
		if a.size() != b.size():
			return "%d %s, committed %d" % [a.size(), key, b.size()]
		for i in a.size():
			if a[i].distance_to(b[i]) > SAME:
				return "%s[%d] %s, committed %s" % [key, i, a[i], b[i]]
	return ""
