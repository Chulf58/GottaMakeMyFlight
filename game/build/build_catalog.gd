class_name BuildCatalog
extends RefCounted
## The placeable objects, keyed by string id. Placeholder sizes and colours
## until the Toon asset lane supplies real models.

## Walk-through objects only their serviced passenger passes through.
const SECURITY_IDS: Array[StringName] = [&"security_scanner"]
## One-cell door markers on the terminal's edge: the front (interaction) side
## faces in, and the back edge leads out.
const DOOR_IDS: Array[StringName] = [&"entrance_door", &"exit_door"]

## Where a baggage belt piece joins its neighbours, in the piece's frame at
## facing 0, from BAGGAGE_DATA (tools/blender/interior/build_baggage_kit.py).
## Each port is a Mount_Belt_<name> empty on a cell edge at belt-top height:
## F is the front (+Z) edge, B the back, L the -X edge, R the +X edge, and
## [cell, name] says which footprint cell owns it. A check-in desk's belt is
## its +x cell, running front to back, so the desk has a B outlet and no paths:
## a feed placed behind it takes the bags.
const BELT_PORT_SIDES := {
	"F": Vector2i(0, 1),
	"B": Vector2i(0, -1),
	"L": Vector2i(-1, 0),
	"R": Vector2i(1, 0),
}
const BELT_PORTS := {
	&"checkin_desk": [[Vector2i(1, 0), "B"]],
	&"baggage_belt": [[Vector2i.ZERO, "F"], [Vector2i.ZERO, "B"]],
	&"baggage_belt_corner": [[Vector2i.ZERO, "F"], [Vector2i.ZERO, "R"]],
	&"baggage_belt_feed": [[Vector2i.ZERO, "F"], [Vector2i.ZERO, "L"], [Vector2i.ZERO, "R"]],
	&"baggage_belt_end": [[Vector2i.ZERO, "F"]],
}
## The routes a bag can take through a belt piece: each pair of ports a path
## joins. A bag may ride a path either way, because BeltShaper turns a piece
## to fit its neighbours, not the flow (a corner can only join F and R), so
## the bag sim routes along these joins from a desk outlet toward an end. A
## feed is a merge, not a sorter. An exit with no piece beyond it stays open.
## The end piece's bag rests on its slide (Mount_BagRest): "BagRest" is only
## ever the last step.
const BELT_PATHS := {
	&"baggage_belt": [["F", "B"]],
	&"baggage_belt_corner": [["F", "R"]],
	&"baggage_belt_feed": [["F", "L"], ["F", "R"], ["L", "R"]],
	&"baggage_belt_end": [["F", "BagRest"]],
}
## The pieces that make up a belt line (the desk is its source, not a piece).
const BELT_IDS: Array[StringName] = [
	&"baggage_belt", &"baggage_belt_corner", &"baggage_belt_feed", &"baggage_belt_end"
]

static var _defs: Dictionary = {}


static func get_def(id: StringName) -> BuildObjectDef:
	if _defs.is_empty():
		_build()
	return _defs.get(id)


static func ids() -> Array[StringName]:
	if _defs.is_empty():
		_build()
	var result: Array[StringName] = []
	result.assign(_defs.keys())
	return result


static func is_security(id: StringName) -> bool:
	return SECURITY_IDS.has(id)


static func is_door(id: StringName) -> bool:
	return DOOR_IDS.has(id)


static func is_belt(id: StringName) -> bool:
	return BELT_IDS.has(id)


## The belt ports of an object placed at `anchor` and `facing`: each
## {"name": "F"/"B"/"L"/"R", "cell": the footprint cell that owns it,
## "side": the grid step out of that cell through the port}. Empty for an
## object with no belt (BELT_PORTS).
static func belt_ports(id: StringName, anchor: Vector2i, facing: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for port in BELT_PORTS.get(id, []):
		(
			out
			. append(
				{
					"name": port[1],
					"cell": anchor + BuildObjectDef.rotate_offset(port[0], facing),
					"side": BuildObjectDef.rotate_offset(BELT_PORT_SIDES[port[1]], facing),
				}
			)
		)
	return out


## Whether two belt ports (belt_ports() entries) face each other across a cell
## edge, so a bag can pass from one piece to the other.
static func belt_ports_join(a: Dictionary, b: Dictionary) -> bool:
	return a["cell"] + a["side"] == b["cell"] and b["cell"] + b["side"] == a["cell"]


static func _build() -> void:
	var desk := _add(&"checkin_desk", "Check-in desk", Vector2i(2, 1), Color(0.62, 0.42, 0.26), 1.1)
	desk.has_interaction = true
	desk.interaction_offset = Vector2i(0, 1)
	var scanner := _add(
		&"security_scanner", "Security scanner", Vector2i(1, 2), Color(0.55, 0.6, 0.68), 2.2
	)
	scanner.walk_through = true
	scanner.has_interaction = true
	scanner.interaction_offset = Vector2i(0, 2)
	_add(&"seat_row", "Gate seats", Vector2i(3, 1), Color(0.25, 0.45, 0.7), 0.8)
	_add_door(&"entrance_door", "Entrance", Color(0.35, 0.7, 0.4))
	_add_door(&"exit_door", "Exit to the plane", Color(0.3, 0.55, 0.85))
	# Cafe pieces (interior-kit Cafe 1/2). The counter's interaction cell is its
	# Mount_Order spot in front of the till; Mount_Staff behind it is not
	# reserved until staff exist.
	var counter := _add(
		&"cafe_counter", "Cafe counter", Vector2i(2, 1), Color(0.85, 0.78, 0.6), 1.98
	)
	counter.has_interaction = true
	counter.interaction_offset = Vector2i(0, 1)
	var table := _add(&"cafe_table", "Cafe table", Vector2i(3, 1), Color(0.55, 0.4, 0.3), 0.92)
	# A chair in each outer cell, the table in the middle cell. The roots are the
	# .glb's Mount_SitRoot_L/R (0.55 m either side of the table centre, facing
	# it); a guest steps in from the cell in front of the chair, since the cell
	# the chair faces is the table.
	table.seats = [
		{
			"cell": Vector2i(0, 0),
			"approach": Vector2i(0, 1),
			"root": Vector2(0.45, 0.0),
			"facing": Vector2i(1, 0),
		},
		{
			"cell": Vector2i(2, 0),
			"approach": Vector2i(2, 1),
			"root": Vector2(-0.45, 0.0),
			"facing": Vector2i(-1, 0),
		},
	]
	# Baggage pieces (interior-kit Baggage B1). Belts are 0.46 m to the rail
	# top and never walkable: a belt across a walkway blocks it. None has an
	# interaction cell; a bag room is judged by its end piece alone.
	var belt_color := Color(0.4, 0.4, 0.45)
	_add(&"baggage_belt", "Baggage belt", Vector2i.ONE, belt_color, 0.46)
	_add(&"baggage_belt_corner", "Belt corner", Vector2i.ONE, belt_color, 0.46)
	_add(&"baggage_belt_feed", "Belt merge", Vector2i.ONE, belt_color, 0.46)
	_add(&"baggage_belt_end", "Belt end", Vector2i.ONE, Color(0.9, 0.75, 0.25), 1.3)
	_add(&"baggage_cart", "Baggage cart", Vector2i(1, 2), Color(0.3, 0.5, 0.75), 1.62)


## Passengers step through a door along its axis only, so it is walk-through;
## the interaction cell in front keeps the inside of the door clear.
static func _add_door(id: StringName, label: String, color: Color) -> void:
	var door := _add(id, label, Vector2i.ONE, color, 2.4)
	door.walk_through = true
	door.has_interaction = true
	door.interaction_offset = Vector2i(0, 1)


static func _add(
	id: StringName, label: String, size: Vector2i, color: Color, height: float
) -> BuildObjectDef:
	var def := BuildObjectDef.new()
	def.id = id
	def.display_name = label
	def.size = size
	def.color = color
	def.height = height
	_defs[id] = def
	return def
