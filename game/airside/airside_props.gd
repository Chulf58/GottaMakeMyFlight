class_name AirsideProps
extends Node3D
## The airside props on show (board 4c08b8e5, Runway R11; article airside-
## props): one jet bridge at each gate's stand and a taxi sign at each turn-off
## where a taxiway leaves the runway. Airside gives it the gate stands and the
## taxi routes after every rebuild (show_layout()), as it gives TaxiPaving the
## routes, so the props follow the stands. Visual only: nothing in the sim reads
## it and nothing is saved.
##
## A bridge is a nose-loader rooted on the gate's exit door
## (JetBridgePose.root_for(), board 0adca5c6) and waits parked. A PlaneView
## whose plane stands at the gate (AT_STAND, BOARDING, DOORS_CLOSED) reports
## the model it draws, its flight's model (PlaneClasses.flight_model()), through
## dock_plane() (PlaneProps does it every frame); the bridge docks at that
## model's door when the model docks (04 to 07) and the door is in reach
## (JetBridgePose.reaches()). The passenger sim decides its walk out from the
## same flight model (OutsideWalks.departure(), decision bridge-boarding-sim-
## route-chosen-at-departure-from-the-fligh), so the drawn bridge and the walk
## agree.
## Model 03 does not dock: the bridge stays parked over its wing and its
## passengers walk out of the apron door (ruling plane-03-boards-on-foot-from-
## the-apron-plane-04-docks-the-no). Once no view reports the gate it parks
## again. The towbarless tug is the plane's own prop (PlaneProps).
##
## A turn-off is a taxi route leg that crosses the runway asphalt's south edge
## (turn_offs()). Its sign stands beside the leg, SIGN_PAST_EDGE_M south of the
## edge on the left of a plane leaving the runway, facing the runway: the
## location panel shows the leg's letter (STUB_LETTERS, east to west) and the
## direction panel the taxi lane's (LANE_LETTER) with the arrow the way the
## route turns onto the lane. The letters are this file's, as the game has no
## taxiway names yet. `sign_scale` sizes every sign: 1.0 is FAA size 3, and the
## default is DEFAULT_SIGN_SCALE (user ruling airside-props-r11-rulings-board-
## through-a-docked-jet-bridge, 2026-11-09), so the legend reads at play range.

const BRIDGE_SCENE := preload("res://assets/airside/props/jet_bridge.glb")
const SIGN_SCENE := preload("res://assets/airside/props/taxi_sign.glb")
const LANE_LETTER := "A"
const STUB_LETTERS := "BCDE"
## How far a turn-off sign stands south of the runway asphalt's edge, along its
## leg, and outside the leg's paving edge.
const SIGN_PAST_EDGE_M := 4.0
const SIGN_SETBACK_M := 4.0
## Two turn-offs closer than this are one.
const SAME_M := 1.0
## The runway strip piece whose width bounds the runway's asphalt.
const RUNWAY_PIECE := "tp_runway_03a"
## The signs' scale unless set: 2.5 x FAA size 3 (user-ruled 2026-11-09).
const DEFAULT_SIGN_SCALE := 2.5

## Every sign's scale; 1.0 is real size.
@export var sign_scale := DEFAULT_SIGN_SCALE:
	set(value):
		sign_scale = value
		for sign in signs:
			sign.scale = Vector3.ONE * value

## Gate letter -> {"node": the bridge, "joints", "root", "stand", "docked",
## "model" (the reported plane's model, "" for none), "pose" (the
## JetBridgePose pose applied last)}.
var bridges: Dictionary = {}
## The turn-off signs, in turn_offs() order.
var signs: Array[Node3D] = []
## The turn-offs the signs stand at (turn_offs()).
var turn_off_list: Array[Dictionary] = []
## Reporter key -> {"gate", "model"} of a plane standing at a gate.
var _reports: Dictionary = {}
var _routes: Array[PackedVector3Array] = []


## Puts a bridge at the stand of every gate in `stands` (gate letter ->
## StandPlacement stand) and a sign at every turn-off of `routes` (Airside.
## taxi_routes()). Gates no longer listed lose their bridge.
func show_layout(stands: Dictionary, routes: Array[PackedVector3Array]) -> void:
	for gate: String in bridges.keys():
		if not stands.has(gate):
			(bridges[gate]["node"] as Node3D).queue_free()
			bridges.erase(gate)
	for gate: String in stands:
		var stand: Dictionary = stands[gate]
		if bridges.has(gate) and bridges[gate]["stand"] == stand:
			continue
		if not bridges.has(gate):
			var node: Node3D = BRIDGE_SCENE.instantiate()
			node.name = "JetBridge_%s" % gate
			add_child(node)
			bridges[gate] = {"node": node, "joints": JetBridgePose.joints_of(node)}
		# On the ground the parked plane stands on, so its door heights match.
		var spot := StandPlacement.stand_point(stand)
		var root := JetBridgePose.root_for(stand, PlaneView.ground_height_at(spot))
		bridges[gate]["root"] = root
		bridges[gate]["stand"] = stand.duplicate()
		(bridges[gate]["node"] as Node3D).transform = root
		_pose_bridge(gate)
	if routes != _routes:
		_routes = routes.duplicate()
		_show_signs(turn_offs(routes, runway_north(), Airside.runway_south()))


## Docks gate `gate`'s bridge at the door of plane `model` (a PlaneModels
## name) parked at its stand, for the reporter `key` (a PlaneView's instance
## id). The last report of each key counts; a key moving to another gate
## leaves the old one.
func dock_plane(key: int, gate: String, model: String) -> void:
	var before: Dictionary = _reports.get(key, {})
	var report := {"gate": gate, "model": model}
	if before == report:
		return
	_reports[key] = report
	if not before.is_empty() and before["gate"] != gate:
		_pose_bridge(before["gate"])
	_pose_bridge(gate)


## Withdraws reporter `key`'s plane: its gate's bridge parks unless another
## reporter still stands there.
func release_plane(key: int) -> void:
	if not _reports.has(key):
		return
	var gate: String = _reports[key]["gate"]
	_reports.erase(key)
	_pose_bridge(gate)


## The north edge of the runway asphalt (its strip piece about RUNWAY_Z).
static func runway_north() -> float:
	var piece: AABB = PlaneModels.PIECES[RUNWAY_PIECE]["aabb"]
	return StandPlacement.RUNWAY_Z + piece.position.z


## Every turn-off in `routes`: a leg from inside the runway asphalt (z from
## `north` to `south`) to south of it, or back. Each is {"at": where the leg
## crosses the south edge, "out": the leg's flat direction away from the
## runway, "sign": the sign's spot, "yaw": its turn (front to the runway),
## "loc", "dir": its letters, "arrow": "L", "R" or ""}, once per crossing,
## east to west.
static func turn_offs(
	routes: Array[PackedVector3Array], north: float, south: float
) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for route in routes:
		for i in range(1, route.size()):
			var a := route[i - 1]
			var b := route[i]
			var a_on := a.z >= north and a.z <= south
			var b_on := b.z >= north and b.z <= south
			if a_on == b_on or maxf(a.z, b.z) <= south:
				continue
			var on := a if a_on else b
			var off := b if a_on else a
			var at := on.lerp(off, (south - on.z) / (off.z - on.z))
			if found.any(func(t: Dictionary) -> bool: return t["at"].distance_to(at) < SAME_M):
				continue
			var out := (off - on).slide(Vector3.UP).normalized()
			found.append({"at": at, "out": out, "arrow": _arrow(routes, on, off, out)})
	found.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return p["at"].x > q["at"].x)
	for i in found.size():
		var t := found[i]
		var out: Vector3 = t["out"]
		var left := Vector3.UP.cross(out)
		t["sign"] = (
			t["at"] + out * SIGN_PAST_EDGE_M + left * (TaxiPaving.WIDTH_M / 2.0 + SIGN_SETBACK_M)
		)
		t["yaw"] = atan2(-out.x, -out.z)
		t["loc"] = STUB_LETTERS[mini(i, STUB_LETTERS.length() - 1)]
		t["dir"] = LANE_LETTER
	return found


## The arrow for a plane leaving the runway along `out` from `on` to `off`:
## the side the next leg from `off` turns to, seen facing the sign.
static func _arrow(
	routes: Array[PackedVector3Array], on: Vector3, off: Vector3, out: Vector3
) -> String:
	for route in routes:
		for i in route.size():
			if route[i].distance_to(off) > SAME_M:
				continue
			for j in [i - 1, i + 1]:
				if j < 0 or j >= route.size() or route[j].distance_to(on) < SAME_M:
					continue
				var next := (route[j] - off).slide(Vector3.UP)
				var turn := out.cross(next).y
				if absf(turn) > SAME_M:
					return "R" if turn < 0.0 else "L"
	return ""


## Shows gate `gate`'s bridge docked at the first model reported for it when
## that model docks and its door is in reach, and parked otherwise.
func _pose_bridge(gate: String) -> void:
	if not bridges.has(gate) or bridges[gate]["joints"].is_empty():
		return
	var entry: Dictionary = bridges[gate]
	var ground: float = (entry["root"] as Transform3D).origin.y
	var pose := JetBridgePose.parked()
	var docked := false
	var model := ""
	for key: int in _reports:
		var report: Dictionary = _reports[key]
		if report["gate"] != gate:
			continue
		model = report["model"]
		if JetBridgePose.reaches(entry["stand"], model, ground):
			pose = JetBridgePose.pose_for(entry["stand"], model, true, ground)["pose"]
			docked = true
		break
	JetBridgePose.apply(entry["joints"], pose)
	entry["pose"] = pose
	entry["docked"] = docked
	entry["model"] = model


func _show_signs(list: Array[Dictionary]) -> void:
	for sign in signs:
		sign.queue_free()
	signs.clear()
	turn_off_list = list
	for t in list:
		var sign: Node3D = SIGN_SCENE.instantiate()
		sign.name = "TaxiSign_%s" % t["loc"]
		var at: Vector3 = t["sign"]
		at.y = PlaneView.ground_height_at(at)
		sign.transform = Transform3D(Basis(Vector3.UP, t["yaw"]), at)
		sign.scale = Vector3.ONE * sign_scale
		add_child(sign)
		show_glyphs(sign, t["loc"], t["dir"], t["arrow"])
		signs.append(sign)


## Shows on `sign` (an instanced taxi_sign.glb) only the location letter
## `loc`, the direction letter `dir` and the arrow `arrow` ("" for none).
## Returns how many glyphs it left on show.
static func show_glyphs(sign: Node, loc: String, dir: String, arrow: String) -> int:
	var keep: Array[String] = ["Glyph_Loc_" + loc, "Glyph_Dir_" + dir]
	if arrow != "":
		keep.append("Glyph_Arrow_" + arrow)
	var shown := 0
	for node in sign.find_children("Glyph_*", "Node3D", true, false):
		if String(node.name).ends_with("_Mesh"):
			continue
		(node as Node3D).visible = keep.has(String(node.name))
		shown += 1 if (node as Node3D).visible else 0
	return shown
