class_name ServiceTypes
extends RefCounted
## Standalone corridor services placed directly on walkable terminal floor
## without requiring a room zone (decision
## two-point-3-layer-build-model-standalone-stands-and-contextual-room-items):
## Grab-and-go stall, Currency Exchange, ATM, and Nap pod.
## Also provides find_def() and is_food_counter() across both standalone
## services and RoomTypes so simulation and snapshot layers resolve service
## behavior from one place.

static var _services: Dictionary = {}
static var _by_piece: Dictionary = {}


static func get_service(id: StringName) -> ServiceDef:
	_ensure()
	return _services.get(id)


static func by_piece(piece_id: StringName) -> ServiceDef:
	_ensure()
	return _by_piece.get(piece_id)


static func is_standalone(piece_id: StringName) -> bool:
	return by_piece(piece_id) != null


static func ids() -> Array[StringName]:
	_ensure()
	var result: Array[StringName] = []
	result.assign(_services.keys())
	return result


## Resolves either a RoomTypes room type or a standalone ServiceTypes service
## by id. Returns null when neither defines `id`.
static func find_def(id: StringName) -> ServiceDef:
	var room := RoomTypes.get_type(id)
	if room != null:
		return room
	return get_service(id)


## Whether `piece_id` is a food counter of a room or standalone food service.
static func is_food_counter(piece_id: StringName) -> bool:
	if RoomTypes.is_food_counter(piece_id):
		return true
	var svc := by_piece(piece_id)
	return svc != null and svc.food and svc.counter_pieces.has(piece_id)


static func _ensure() -> void:
	if not _services.is_empty():
		return
	_build()


static func _build() -> void:
	var stall := ServiceDef.new()
	stall.id = &"stall"
	stall.piece_id = &"grab_and_go_stall"
	stall.display_name = "Grab-and-go stall"
	stall.food = true
	stall.walk_on = true
	stall.counter_pieces = [&"grab_and_go_stall"]
	stall.base_spend = 8
	stall.order_ticks = 30
	stall.dwell_ticks = 0
	stall.mood_bonus = 5
	stall.needs_staff = true
	_register(stall)

	var exchange := ServiceDef.new()
	exchange.id = &"exchange"
	exchange.piece_id = &"currency_exchange"
	exchange.display_name = "Exchange"
	exchange.shop = true
	exchange.relieves_boredom = false
	exchange.seat_piece = &"currency_exchange"
	exchange.seats_per_piece = 1
	exchange.base_spend = 8
	exchange.needs_staff = true
	_register(exchange)

	var atm := ServiceDef.new()
	atm.id = &"atm"
	atm.piece_id = &"atm"
	atm.display_name = "ATM"
	atm.shop = true
	atm.relieves_boredom = false
	atm.seat_piece = &"atm"
	atm.seats_per_piece = 1
	atm.base_spend = 3
	atm.needs_staff = false
	_register(atm)

	var nap_pod := ServiceDef.new()
	nap_pod.id = &"nap_pod"
	nap_pod.piece_id = &"nap_pod"
	nap_pod.display_name = "Nap pod"
	nap_pod.shop = true
	nap_pod.activity = true
	nap_pod.relieves_boredom = true
	nap_pod.seat_piece = &"nap_pod"
	nap_pod.seats_per_piece = 1
	nap_pod.base_spend = PriceTable.NAP_POD_FEE
	nap_pod.dwell_ticks = 300
	nap_pod.mood_bonus = 15
	nap_pod.needs_staff = false
	_register(nap_pod)


static func _register(svc: ServiceDef) -> void:
	_services[svc.id] = svc
	_by_piece[svc.piece_id] = svc
