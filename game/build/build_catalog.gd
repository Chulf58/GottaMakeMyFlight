class_name BuildCatalog
extends RefCounted
## The placeable objects, keyed by string id. Placeholder sizes and colours
## until the Toon asset lane supplies real models.

## Walk-through objects only their serviced passenger passes through.
const SECURITY_IDS: Array[StringName] = [&"security_scanner"]
## One-cell door markers on the terminal's edge: the front (interaction) side
## faces in, and the back edge leads out.
const DOOR_IDS: Array[StringName] = [&"entrance_door", &"exit_door"]

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
