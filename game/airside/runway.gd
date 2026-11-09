class_name Runway
extends RefCounted
## The runway's size (decision runway-and-taxi-technical-design-movement-plan-
## analytic-bookings-planned-pauses, points 1 and 8): small, medium or large,
## 384, 576 or 768 m built from the 96 m pack pieces. A runway takes planes of
## its own class and every smaller one, so a small runway takes small planes
## only. Touchdown, liftoff and approach points belong to the plane class, never
## to the runway, so a bigger runway changes no planned flight.
##
## A runway saves its size and its upgrade works (RunwayWorks). FlightSim holds
## the game's runway; the offer board draws only the classes it takes and
## FlightSim.accept_problem refuses the rest. The drawn runway (RunwayView)
## follows size_changed.

## The size changed: the works ended, a load installed one, or code set it.
signal size_changed(new_size: String)

const SMALL := PlaneClasses.SMALL
const MEDIUM := PlaneClasses.MEDIUM
const LARGE := PlaneClasses.LARGE

## Version 1 saved the size. 2 adds the upgrade works (RunwayWorks); a version 1
## part is refused, with no migration before a release.
const SAVE_VERSION := 2
const SAVE_KEYS := ["save_version", "size", "works"]

## The piece that closes each end, and the one that makes up the middle.
const END_PIECE := "tp_runway_01a"
const STRIP_PIECE := "tp_runway_03a"
## Strips in the middle, by size: the length is the strips plus the two ends,
## each half a strip long.
const STRIPS := {SMALL: 3, MEDIUM: 5, LARGE: 7}
const STRIP_LENGTH_M := 96.0
const NAME_PREFIX := "Runway"

## The runway's size, one of PlaneClasses.ORDER. A new game starts small.
var size: String = SMALL:
	set(value):
		if value == size:
			return
		size = value
		size_changed.emit(size)
## The upgrade works booked or under way.
var works := RunwayWorks.new()


func _init(start_size := SMALL) -> void:
	size = start_size


## The length in metres of a runway of `runway_size`, 0.0 for an unknown size.
static func length_m(runway_size: String) -> float:
	if not STRIPS.has(runway_size):
		return 0.0
	return (STRIPS[runway_size] + 1) * STRIP_LENGTH_M


## Whether a runway of `runway_size` takes `plane_class` planes: the class is
## no bigger than the runway. False for an unknown size or class.
static func size_takes(runway_size: String, plane_class: String) -> bool:
	var rank := PlaneClasses.ORDER.find(plane_class)
	return rank >= 0 and PlaneClasses.ORDER.find(runway_size) >= rank


## Whether this runway takes `plane_class` planes.
func takes(plane_class: String) -> bool:
	return size_takes(size, plane_class)


## The pieces of a runway of `runway_size`, centred on x 0: each is {"piece":
## the PlaneModels.PIECES name, "x": its origin along the runway, "turned":
## whether it is turned half a circle}. The strips are centred on their origin;
## an end piece's origin is the edge it joins to the strips, and the west one is
## turned so that its far edge faces outward. [] for an unknown size.
static func pieces(runway_size: String) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	if not STRIPS.has(runway_size):
		return list
	var count: int = STRIPS[runway_size]
	var half := count * STRIP_LENGTH_M / 2.0
	list.append({"piece": END_PIECE, "x": -half, "turned": true})
	for i in count:
		var x := (i - (count - 1) / 2.0) * STRIP_LENGTH_M
		list.append({"piece": STRIP_PIECE, "x": x, "turned": false})
	list.append({"piece": END_PIECE, "x": half, "turned": false})
	return list


## A Node3D holding the pieces of a runway of `runway_size` as children at
## their x, to be placed on the airport's runway line. The caller owns it.
static func build(runway_size: String) -> Node3D:
	var root := Node3D.new()
	root.name = "%s%s" % [NAME_PREFIX, runway_size.capitalize()]
	for entry in pieces(runway_size):
		var scene: PackedScene = load(PlaneModels.PIECES[entry["piece"]]["path"])
		var node: Node3D = scene.instantiate()
		node.position.x = entry["x"]
		if entry["turned"]:
			node.rotation.y = PI
		root.add_child(node)
	return root


## Takes the new size when the works end at `tick` and drops their booking once
## it has been held long enough (RunwayWorks). True when either happened.
func settle(tick: int) -> bool:
	var changed := false
	if works.scheduled() and tick >= works.finish:
		var built := works.target
		works.target = ""
		size = built
		changed = true
	var held := works.start != RunwayWorks.NO_TICK and not works.scheduled()
	if held and tick >= works.finish + RunwayWorks.HOLD_TICKS:
		works.clear()
		changed = true
	return changed


## JSON-safe state for a save: the size and the works.
func to_snapshot() -> Dictionary:
	return {"save_version": SAVE_VERSION, "size": size, "works": works.to_snapshot()}


## Restores a to_snapshot() dictionary, including one that went through JSON.
## Pushes an error and returns false, leaving the runway unchanged, when
## anything is missing, mistyped or unknown.
func from_snapshot(data: Dictionary) -> bool:
	var problem := snapshot_problem(data)
	if problem != "":
		push_error("Runway.from_snapshot: %s" % problem)
		return false
	size = data["size"]
	works.from_snapshot(data["works"])
	return true


## "" when `data` is exactly SAVE_KEYS with the current version, a size and
## works that build a larger size, or what is wrong with it.
func snapshot_problem(data: Dictionary) -> String:
	for key in data.keys():
		if not SAVE_KEYS.has(key):
			return "unknown key '%s'" % key
	for key in SAVE_KEYS:
		if not data.has(key):
			return "missing key '%s'" % key
	if not WholeNumber.is_whole(data["save_version"]) or int(data["save_version"]) != SAVE_VERSION:
		return "save_version must be %d" % SAVE_VERSION
	if typeof(data["size"]) != TYPE_STRING or not STRIPS.has(data["size"]):
		return "size must be one of %s" % [PlaneClasses.ORDER]
	if typeof(data["works"]) != TYPE_DICTIONARY:
		return "works must be a dictionary"
	var problem := works.snapshot_problem(data["works"])
	var target: String = data["works"].get("target", "")
	if problem == "" and target != "":
		if PlaneClasses.ORDER.find(target) <= PlaneClasses.ORDER.find(data["size"]):
			problem = "the works must build a larger size than %s" % data["size"]
	return "works: %s" % problem if problem != "" else ""
