class_name RelocationGhosts
extends Node3D
## The stand-ins of moved pieces still in use (decision move-rooms-technical-
## design-roommove-plan-of-existing-edits, part 5, user-ruled "Keep a ghost
## piece"): while a visitor has not yet left a piece that moved with its room,
## the piece is drawn at its old spot too, as the build view draws it, so
## nobody sits on air while build mode is paused. Relocation.ghosts() says
## which; each frame compares what is drawn with it and changes only what
## differs, so a move, an undo, a tick or a load shows on the next frame,
## paused or not. It reads the sim and never writes to it.

var sim: PassengerSim
## "<id>:<def>:<anchor>:<facing>" -> the stand-in node.
var _nodes: Dictionary = {}


func _process(_delta: float) -> void:
	sync()


## Draws the stand-ins Relocation.ghosts() lists and drops the rest.
func sync() -> void:
	var wanted := {}
	if sim != null and sim.grid != null:
		for ghost in Relocation.ghosts(sim):
			wanted[_key(ghost)] = ghost
	for key: String in _nodes.keys():
		if not wanted.has(key):
			(_nodes[key] as Node3D).queue_free()
			_nodes.erase(key)
	for key: String in wanted:
		if _nodes.has(key):
			continue
		var ghost: Dictionary = wanted[key]
		var def := BuildCatalog.get_def(ghost["def"])
		var node := BuildView.make_object_node(def, null)
		node.transform = BuildView.object_transform(
			sim.grid, def.footprint(ghost["anchor"], ghost["facing"]), ghost["facing"]
		)
		add_child(node)
		_nodes[key] = node


## How many stand-ins are drawn.
func count() -> int:
	return _nodes.size()


## The stand-in drawn for a ghost entry of Relocation.ghosts(), or null.
func node_of(ghost: Dictionary) -> Node3D:
	return _nodes.get(_key(ghost))


static func _key(ghost: Dictionary) -> String:
	return "%d:%s:%s:%d" % [ghost["id"], ghost["def"], ghost["anchor"], ghost["facing"]]
