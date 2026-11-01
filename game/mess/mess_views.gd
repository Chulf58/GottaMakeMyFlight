class_name MessViews
extends Node3D
## Draws the messes and the full bins of MessSim (decision cleaner-staff-and-
## messes-visits-leave-messes-bins-fill-pooled-cleaners-nearest-mess, answer 7:
## small flat floor props, readable at the default zoom, larger when grown).
##
## Each mess is one floor prop on its cell, by kind (LITTER litter, SPILL a
## puddle, TOILET a smear) and the grown variant once the mess has grown. Its
## turn about the vertical comes from its id, so props of one kind do not all
## line up and a mess keeps its turn for as long as it lives; nothing is
## random. A full bin (MessSim.full_bins()) gets the rubbish of the full trash
## can model drawn on the bin the build view already draws: only the
## Bin_Rubbish mesh of tc_trash_can_1a_full.glb is shown, at the bin's own
## transform (BuildView.object_transform()), so the can is never drawn twice.
##
## The sim emits nothing when a mess appears, grows or goes, so every frame
## compares what is drawn with the sim and changes only what differs: a
## change made by a tick, an edit or a load shows on the next frame, paused or
## not. It reads the sim and never writes to it.

## By MessSim.Kind (LITTER, SPILL, TOILET): the normal and the grown prop.
const PROPS: Array[Array] = [
	[
		preload("res://assets/mess/mess_litter.glb"),
		preload("res://assets/mess/mess_litter_grown.glb"),
	],
	[
		preload("res://assets/mess/mess_spill.glb"),
		preload("res://assets/mess/mess_spill_grown.glb"),
	],
	[
		preload("res://assets/mess/mess_smear.glb"),
		preload("res://assets/mess/mess_smear_grown.glb"),
	],
]
const FULL_BIN := preload("res://assets/decor/tc_trash_can_1a_full.glb")
## The one mesh of FULL_BIN drawn over a bin; the can itself is the build view's.
const RUBBISH := "Bin_Rubbish"
## Radians a prop turns per mess id: the golden angle, so ids next to each
## other never share a turn.
const TURN_PER_ID := 2.399963

@export var sim: PassengerSim

## Mess id -> its prop node (metas "kind" and "grown").
var _props: Dictionary = {}
## Bin object id -> its rubbish node.
var _bins: Dictionary = {}


## The prop scene for a mess of `kind` (MessSim.Kind), grown or not.
static func prop_scene(kind: int, grown: bool) -> PackedScene:
	return PROPS[kind][1 if grown else 0]


## A full bin's rubbish, alone: FULL_BIN with the mesh of every node but
## RUBBISH taken off, so the node frames (and a RUBBISH under the can) stay.
static func make_rubbish() -> Node3D:
	var node := FULL_BIN.instantiate() as Node3D
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.name != RUBBISH:
			mesh.mesh = null
	return node


## The turn about the vertical a mess with `id` is drawn with.
static func turn_of(id: int) -> float:
	return fposmod(id * TURN_PER_ID, TAU)


func _process(_delta: float) -> void:
	sync()


## The prop drawn for mess `id`, or null.
func prop_for(id: int) -> Node3D:
	return _props.get(id)


## The rubbish drawn on bin `bin`, or null.
func rubbish_for(bin: int) -> Node3D:
	return _bins.get(bin)


func prop_count() -> int:
	return _props.size()


func rubbish_count() -> int:
	return _bins.size()


## Brings the drawn props and rubbish in line with the sim.
func sync() -> void:
	if sim == null or sim.messes == null:
		return
	var messes := sim.messes
	var grid := sim.grid
	var seen := {}
	for id in messes.mess_ids():
		var mess := messes.get_mess(id)
		var kind := int(mess["kind"])
		var grown: bool = mess["grown"]
		seen[id] = true
		var node: Node3D = _props.get(id)
		if node != null and (node.get_meta(&"kind") != kind or node.get_meta(&"grown") != grown):
			node.queue_free()
			node = null
		if node == null:
			node = prop_scene(kind, grown).instantiate() as Node3D
			node.set_meta(&"kind", kind)
			node.set_meta(&"grown", grown)
			add_child(node)
			_props[id] = node
		node.transform = Transform3D(
			Basis(Vector3.UP, turn_of(id)), grid.cell_to_world(mess["cell"])
		)
	for id: int in _props.keys():
		if not seen.has(id):
			(_props[id] as Node3D).queue_free()
			_props.erase(id)
	var full := {}
	for bin in messes.full_bins():
		full[bin] = true
		var record := grid.get_object(bin)
		var def := BuildCatalog.get_def(record["def"])
		var at := BuildView.object_transform(
			grid, def.footprint(record["anchor"], record["facing"]), record["facing"]
		)
		var node: Node3D = _bins.get(bin)
		if node == null:
			node = make_rubbish()
			add_child(node)
			_bins[bin] = node
		node.transform = at
	for bin: int in _bins.keys():
		if not full.has(bin):
			(_bins[bin] as Node3D).queue_free()
			_bins.erase(bin)
