class_name BuildCatalog
extends RefCounted
## The placeable objects, keyed by string id. Placeholder sizes and colours
## until the Toon asset lane supplies real models.

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
