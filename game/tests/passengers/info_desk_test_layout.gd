class_name InfoDeskTestLayout
extends RefCounted
## The floor the info desk tests share: 24 x 14 cells, the entrance on the
## south edge and the exit on the north edge, a wall along the north edge of
## row WALL_ROW cutting the two apart, and an info desk on the entrance's side
## whose interaction cell is DESK_FRONT. A cleared passenger walking to the
## exit from the south side has no route (Stuck.NO_ROUTE) until open_wall().

const SIZE := Vector2i(24, 14)
const WALL_ROW := 6
const DESK_ANCHOR := Vector2i(6, 9)
## The desk's interaction cell, in front of its left half.
const DESK_FRONT := Vector2i(6, 10)
const BOARDING := 5000
const DOORS := 6000
const SEED := 7


## The grid, with the info desk when `with_desk`; the control has none.
static func grid(with_desk := true) -> BuildGrid:
	var on_grid := PassengerTestWorld.floored(SIZE)
	PassengerTestWorld.place(on_grid, &"exit_door", Vector2i(2, 0), 0)
	PassengerTestWorld.place(on_grid, &"entrance_door", Vector2i(2, SIZE.y - 1), 2)
	for x in SIZE.x:
		on_grid.apply(BuildEdit.place_wall(Vector2i(x, WALL_ROW), BuildGrid.Side.NORTH))
	if with_desk:
		PassengerTestWorld.place(on_grid, &"info_desk", DESK_ANCHOR, 0)
	return on_grid


static func open_wall(on_grid: BuildGrid) -> void:
	for x in SIZE.x:
		on_grid.apply(BuildEdit.remove_wall(Vector2i(x, WALL_ROW), BuildGrid.Side.NORTH))


## A world on grid(), with the apron walk empty so reaching the exit door is
## making the flight. `staff_roles` limits who is seated (every role when empty).
static func world(
	with_desk := true, staff_roles: Array[StaffMember.Role] = []
) -> PassengerTestWorld:
	var made := PassengerTestWorld.make(
		grid(with_desk), PassengerTestWorld.starts_with(BOARDING, DOORS), SEED
	)
	made.sim.apron_waypoints = PackedVector3Array()
	made.auto_staff_roles = staff_roles
	return made


## A calm cleared passenger with no bags walking to the exit from `cell`, with
## `mood`: stuck with no route at the first step while the wall stands.
static func guest(in_world: PassengerTestWorld, cell: Vector2i, mood: int) -> Passenger:
	var p := in_world.passenger(in_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_EXIT
	p.stage_tick = in_world.clock.tick
	p.at = cell
	p.clear_path()
	p.mood = mood
	return p
