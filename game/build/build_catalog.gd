class_name BuildCatalog
extends RefCounted
## The placeable objects, keyed by string id. Placeholder sizes and colours
## until the Toon asset lane supplies real models.

## Walk-through objects only their serviced passenger passes through.
const SECURITY_IDS: Array[StringName] = [&"security_scanner", &"security_arch"]
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
	# Security lane parts (SecurityLanes), one cell each and placed separately.
	# The arch is walked through along its axis from the unpack cell in front
	# of it; the tables and the X-ray belt stand beside the walk.
	var arch := _add(&"security_arch", "Security arch", Vector2i.ONE, Color(0.5, 0.56, 0.66), 2.3)
	arch.walk_through = true
	arch.has_interaction = true
	arch.interaction_offset = Vector2i(0, 1)
	_add(&"tray_table", "Tray table", Vector2i.ONE, Color(0.72, 0.74, 0.78), 0.85)
	_add(&"xray_belt", "X-ray belt", Vector2i.ONE, Color(0.36, 0.42, 0.52), 1.4)
	_add(&"pickup_table", "Pickup table", Vector2i.ONE, Color(0.64, 0.68, 0.74), 0.85)
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
	# Toilet pieces (Toilets 3/5). A stall is one use slot, one cell wide and two
	# deep: the door at the front, the toilet in the rear cell. Each piece's
	# interaction cell is its Mount_Approach, the cell in front of it, kept clear
	# like a counter's. The view draws them with the interior kit's
	# toilet_stall and toilet_sink pieces (Toilets 5/5).
	var stall := _add(&"toilet_stall", "Toilet stall", Vector2i(1, 2), Color(0.8, 0.84, 0.88), 2.1)
	stall.has_interaction = true
	stall.interaction_offset = Vector2i(0, 2)
	var sink := _add(&"toilet_sink", "Sink", Vector2i.ONE, Color(0.92, 0.94, 0.96), 1.0)
	sink.has_interaction = true
	sink.interaction_offset = Vector2i(0, 1)
	# Kiosk pieces (Boredom 2/5), drawn with the interior kit's kiosk_counter
	# and kiosk_display pieces (Boredom 5/5). The counter makes a kiosk work and
	# serves nobody yet (decision
	# first-shop-is-the-kiosk-it-works-without-a-server-and-a-shop); its
	# interaction cell is the till spot in front (Mount_Till), kept clear. A
	# display stand is two cells wide; the cell in front of each is a browse slot
	# (ShopLayout, Mount_Browse_0 and _1), and the first of them is its
	# interaction cell, kept clear.
	var till := _add(&"kiosk_counter", "Kiosk counter", Vector2i(2, 1), Color(0.86, 0.62, 0.4), 1.1)
	till.has_interaction = true
	till.interaction_offset = Vector2i(0, 1)
	var display := _add(
		&"kiosk_display", "Display stand", Vector2i(2, 1), Color(0.5, 0.7, 0.75), 1.6
	)
	display.has_interaction = true
	display.interaction_offset = Vector2i(0, 1)
	# A screen stand (Boredom 4/5; decision boredom-screens-are-floor-standing-
	# screen-stands-placed-like): one floor cell, turned like seats, covering a
	# fan in front of it (ScreenCoverage). Nobody uses it at a spot, so it has
	# no interaction cell. Drawn with the interior kit's screen_stand piece
	# (Boredom 5/5).
	_add(ScreenCoverage.SCREEN_ID, "Screen", Vector2i.ONE, Color(0.16, 0.2, 0.3), 1.88)
	_build_decor()
	_build_services()
	_build_activities()


## Decor (Furniture 4/4; decisions all-11-exported-decor-models-are-placeable-
## plants-trees-foun and furniture-set-modelled-on-copenhagen-airport-decor-
## calms-pas): the Toon City models, one id each, no interaction cell. A
## footprint is the model's extent in whole cells and a height its top, both
## read from the .glb (a test keeps them in step). Placed as exported, with no
## rescale (decision oversized-toon-decor-trees-fountain-statue-tree-bench-is-
## bui). A chain is the middle cell of post, chain, post in a row.
static func _build_decor() -> void:
	var metal := Color(0.55, 0.58, 0.62)
	var green := Color(0.3, 0.55, 0.3)
	var stone := Color(0.7, 0.7, 0.68)
	_add(&"bench_1a", "Bench", Vector2i(1, 3), Color(0.55, 0.4, 0.28), 1.35)
	_add(&"bench_2a_indoor", "Tree bench", Vector2i(4, 4), green, 2.4)
	_add(&"bush", "Bush", Vector2i(2, 2), green, 1.63)
	_add(&"fountain_indoor", "Fountain", Vector2i(2, 2), Color(0.5, 0.7, 0.85), 1.8)
	_add(&"metal_pole", "Post", Vector2i.ONE, metal, 1.62)
	_add(&"metal_pole_chain", "Chain", Vector2i.ONE, metal, 1.21)
	_add(&"plant_pot_1a", "Planter", Vector2i(1, 2), green, 1.62)
	_add(&"plant_pot_2a", "Plant pot", Vector2i(2, 2), green, 1.05)
	_add(&"statue_indoor", "Statue", Vector2i.ONE, stone, 2.4)
	_add(&"trash_can", "Bin", Vector2i.ONE, Color(0.4, 0.45, 0.5), 1.4)
	_add(&"tree_indoor", "Tree", Vector2i(2, 2), green, 2.2)


## Services kit (Furniture 3b). A counter, stall or desk is 2x1 with its
## interaction cell on its Mount_Order, in front of the till (Mount_Staff
## behind it is not reserved until staff exist, as at the cafe counter); an ATM
## and a shower are used from their Mount_Use cell in front; the pharmacy shelf
## from its Mount_Browse cell. Seats (Mount_SitRoot_*) are not catalogued yet:
## nothing reads them for these pieces. The offsets are read from the .glb
## mounts (a test keeps them in step).
static func _build_services() -> void:
	_add(&"bar_counter", "Bar counter", Vector2i(2, 2), Color(0.45, 0.3, 0.25), 1.54)
	_add_counter(&"grab_and_go_stall", "Grab-and-go stall", 2.25, Color(0.9, 0.6, 0.3))
	_add(&"restaurant_table", "Restaurant table", Vector2i(2, 3), Color(0.6, 0.45, 0.35), 1.01)
	_add(&"restaurant_booth", "Restaurant booth", Vector2i(2, 3), Color(0.65, 0.3, 0.3), 1.15)
	_add_counter(&"info_desk", "Info desk", 2.02, Color(0.3, 0.5, 0.75))
	_add(&"info_screen", "Info screen", Vector2i.ONE, Color(0.16, 0.2, 0.3), 2.27)
	_add_counter(&"currency_exchange", "Currency exchange", 2.16, Color(0.8, 0.7, 0.3))
	var atm := _add(&"atm", "ATM", Vector2i.ONE, Color(0.35, 0.4, 0.5), 1.78)
	atm.has_interaction = true
	atm.interaction_offset = Vector2i(0, 1)
	_add_counter(&"pharmacy_counter", "Pharmacy counter", 1.94, Color(0.4, 0.7, 0.55))
	var shelf := _add(
		&"pharmacy_shelf", "Pharmacy shelf", Vector2i(2, 1), Color(0.5, 0.75, 0.6), 1.98
	)
	shelf.has_interaction = true
	shelf.interaction_offset = Vector2i(0, 1)
	var shower := _add(&"shower_cubicle", "Shower", Vector2i.ONE, Color(0.7, 0.85, 0.9), 2.16)
	shower.has_interaction = true
	shower.interaction_offset = Vector2i(0, 1)
	_add(&"nap_pod", "Nap pod", Vector2i.ONE, Color(0.35, 0.35, 0.55), 1.82)


## Activities kit (Furniture 3): the play area, the lounge, the work desk and
## the prize podium. None is used from an interaction cell. The podium is 6x3
## and its height counts the prize car on it (2.3 m: the 0.3 m podium and the
## 2.0 m SUV, drawn at the podium's Mount_Car).
static func _build_activities() -> void:
	_add(&"play_blocks", "Play blocks", Vector2i(2, 2), Color(0.9, 0.5, 0.3), 0.72)
	_add(&"play_slide", "Play slide", Vector2i(2, 1), Color(0.9, 0.7, 0.2), 0.9)
	_add(&"lounge_sofa", "Lounge sofa", Vector2i(2, 1), Color(0.5, 0.35, 0.6), 0.86)
	_add(&"lounge_armchair", "Lounge armchair", Vector2i.ONE, Color(0.5, 0.35, 0.6), 0.86)
	_add(&"work_desk", "Work desk", Vector2i(2, 2), Color(0.45, 0.5, 0.55), 1.2)
	_add(&"prize_podium", "Prize podium", Vector2i(6, 3), Color(0.8, 0.2, 0.25), 2.3)


## A 2x1 counter, stall or desk served from the cell in front of its left half.
static func _add_counter(id: StringName, label: String, height: float, color: Color) -> void:
	var counter := _add(id, label, Vector2i(2, 1), color, height)
	counter.has_interaction = true
	counter.interaction_offset = Vector2i(0, 1)


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
