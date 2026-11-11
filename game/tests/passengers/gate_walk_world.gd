class_name GateWalkWorld
extends RefCounted
## Test support for the gate walk readout (GateWalk): one gate desk (gate A,
## bound by GateDesks and ApronStand) with a row of gate seats beside it, and
## two basic security scanners at different distances from it, on the terminal
## site's grid. Passengers come in at the west door; only the far scanner is
## staffed, so a passenger sent to security is cleared at the far exit. Call
## free_all() when done.

const SITE := preload("res://build/terminal_site.tres")
const FLIGHT := "TO_A"
const EXIT := Vector2i(40, 112)
const DESK := Vector2i(36, 113)
const ROW := Vector2i(30, 118)
const NEAR_SCANNER := Vector2i(38, 121)
const FAR_SCANNER := Vector2i(60, 121)
const BOARDING := 3000
const DOORS := 6000

var world: PassengerTestWorld
var gates: GateDesks
var apron: ApronStand
var near_station := 0
var far_station := 0
var desk := 0
var row := 0
## Set by attach_views().
var finances: Finances
var mode: BuildMode
var card: BuiltItemCard
var view: GateLinksView
## Passenger id -> the tick each stage was first entered, by stage.
var stage_ticks := {}
## Passenger id -> the cell it stood on when it first entered each stage.
var stage_cells := {}


## Builds the world; `suite` owns the nodes (auto_free) and
## PassengerTestWorld.tracker must be set to it. With `seats` false the seat
## row is left out, so the gate's first place is a standing spot.
static func make(suite: GdUnitTestSuite, seats := true) -> GateWalkWorld:
	var out := GateWalkWorld.new()
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	var floor: Array[BuildEdit] = []
	for y in range(112, 126):
		for x in range(18, 67):
			floor.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(floor)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(24, 125), 2)
	PassengerTestWorld.place(grid, &"exit_door", EXIT, 0)
	if seats:
		out.row = PassengerTestWorld.place(grid, &"seat_row", ROW, 0)
	out.near_station = PassengerTestWorld.place(grid, &"security_scanner", NEAR_SCANNER, 0)
	out.far_station = PassengerTestWorld.place(grid, &"security_scanner", FAR_SCANNER, 0)
	EnclosureKit.close_floor(grid)
	var starts := PassengerTestWorld.starts_with(BOARDING, DOORS)
	out.world = PassengerTestWorld.make(grid, starts)
	var sim := out.world.sim
	sim.site = SITE
	out.world.auto_staff = false
	out.gates = suite.auto_free(GateDesks.new()) as GateDesks
	out.gates.bind(grid, out.world.flights)
	out.desk = PassengerTestWorld.place(grid, GateDesks.DESK, DESK, 0)
	out.apron = suite.auto_free(ApronStand.new()) as ApronStand
	out.apron.passengers = sim
	out.apron.bind(grid, SITE, out.world.flights, out.gates)
	assert(out.world.flights.add_flight(FLIGHT, starts, "A"))
	StaffTestKit.seat(out.world.staff, out.far_station, StaffMember.Slot.PRIMARY)
	sim.standing.rebuild(sim)
	sim.stage_changed.connect(out._on_stage)
	return out


## Sends one calm passenger for the flight to security, checked in, no bags;
## returns its id.
func send() -> int:
	var id := world.sim.spawn_now(FLIGHT)
	var p := world.passenger(id)
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.apron = []
	p.apron_mm = 0
	p.stage = Passenger.Stage.TO_SECURITY
	p.clear_path()
	return id


## The tick passenger `id` first entered `stage`, or -1.
func tick_of(id: int, stage: Passenger.Stage) -> int:
	return stage_ticks.get(id, {}).get(stage, -1)


## Steps until passenger `id` has entered `stage`, at most `limit` ticks;
## returns whether it did.
func run_until_stage(id: int, stage: Passenger.Stage, limit := 4000) -> bool:
	for i in limit:
		if tick_of(id, stage) >= 0:
			return true
		world.step()
	return tick_of(id, stage) >= 0


## Puts a desk card on gate A's desk and a gate links view over the gates, both
## reading this world's sim, as the game wires them. Nodes go under `suite`,
## which free_all() frees them from.
func attach_views(suite: GdUnitTestSuite) -> void:
	finances = Finances.new()
	suite.add_child(finances)
	mode = BuildMode.new()
	mode.site = SITE
	mode.finances = finances
	suite.add_child(mode)
	mode.set_process(false)
	card = BuiltItemCard.new()
	card.sim = world.sim
	card.build_mode = mode
	card.gates = gates
	card.selection = BuiltSelection.new()
	card.selection.kind = BuiltSelection.Kind.OBJECT
	card.selection.id = desk
	suite.add_child(card)
	view = GateLinksView.new()
	suite.add_child(view)
	view.bind(world.grid, gates)
	view.bind_walk(world.sim)


## Puts back whichever of the two scanners an edit took away (the id of a
## placed one changes), and steps one tick so the standing spots are derived
## again.
func restore_scanners() -> void:
	if world.grid.get_object(near_station).is_empty():
		near_station = PassengerTestWorld.place(world.grid, &"security_scanner", NEAR_SCANNER, 0)
	if world.grid.get_object(far_station).is_empty():
		far_station = PassengerTestWorld.place(world.grid, &"security_scanner", FAR_SCANNER, 0)
	world.step()


func free_all() -> void:
	for node: Node in [view, card, mode, finances]:
		if node != null and is_instance_valid(node):
			node.free()
	world.free_all()


func _on_stage(id: int, stage: Passenger.Stage) -> void:
	if not stage_ticks.has(id):
		stage_ticks[id] = {}
		stage_cells[id] = {}
	if not stage_ticks[id].has(stage):
		stage_ticks[id][stage] = world.sim.tick
		stage_cells[id][stage] = world.passenger(id).at
