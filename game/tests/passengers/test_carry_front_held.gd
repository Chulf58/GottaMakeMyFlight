class_name TestCarryFrontHeld
extends GdUnitTestSuite
## The front carry of a walker held in a boarding file (SecurityLooks.carry_front(),
## board aa2db71d). Held, its path is open (is_moving()) but it takes no step, so
## it reads the cell it stands on and the step it took onto it, never the step
## ahead it has not taken. Read the other way, a gate stander held on a cell
## closed on both flanks turned to the front carry on the boarding tick, which
## vetoed the queue stand of its roller (CarryOnProps), and the stood roller
## tipped into the gate desk behind it.
##
## The reference terminal's boarding world, walkers on one cell as boarding
## opens: the later ones wait in their file (RollerPark.filed_still()). Both
## flanks of the held walker's cell are then walled.

const FILE_CELL := Vector2i(19, 6)
const FILE_WALKERS := 5
const MAX_TICKS := 400

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
	_world = null


## The first walker held in its file with no step taken on its open path, on an
## axis step, after stepping the world; null when none was held in MAX_TICKS.
func _held_walker(walkers: Array[Passenger]) -> Passenger:
	for i in MAX_TICKS:
		_world.step()
		for p in walkers:
			if (
				RollerPark.filed_still(_world.sim, p)
				and p.is_moving()
				and p.path_index == 0
				and p.seg_mm == 0
				and (p.path[1] - p.path[0]).x * (p.path[1] - p.path[0]).y == 0
			):
				return p
	return null


## Walls both flanks of `cell` for a step along `step` (an axis step).
func _close_flanks(cell: Vector2i, step: Vector2i) -> void:
	var sides := (
		[BuildGrid.Side.NORTH, BuildGrid.Side.SOUTH]
		if step.x != 0
		else [BuildGrid.Side.EAST, BuildGrid.Side.WEST]
	)
	for side: int in sides:
		assert_bool(_world.sim.grid.apply(BuildEdit.place_wall(cell, side)).ok).is_true()


## A walker held in its file on a cell closed on both flanks reads no front
## carry, though the step ahead of it runs between the same two walls. Control:
## a walker of the same path and cell that is not held (a bare passenger the
## files do not hold) reads the front carry, and so does the held walker's
## copy once it has begun the step (seg_mm > 0), so the walls and the walk are
## what the held reading differs on.
func test_a_walker_held_in_its_file_does_not_carry_in_front_for_a_step_not_taken() -> void:
	_world = TestBoardingFiles.boarding_world()
	_world.run_to(TestBoardingFiles.BOARDING + 5)
	var walkers: Array[Passenger] = []
	for i in FILE_WALKERS:
		var p := TestBoardingFiles.walker(_world, FILE_CELL)
		p.carry_on = 1
		walkers.append(p)
	var held := _held_walker(walkers)
	assert_object(held).is_not_null()
	var step := held.path[1] - held.path[0]
	_close_flanks(held.at, step)
	var sim := _world.sim
	print(
		(
			"held walker %d at %s path %s: filed_still %s, front %s"
			% [
				held.id,
				held.at,
				held.path,
				RollerPark.filed_still(sim, held),
				SecurityLooks.carry_front(sim, held)
			]
		)
	)
	assert_bool(RollerPark.filed_still(sim, held)).is_true()
	assert_bool(SecurityLooks.carry_front(sim, held)).is_false()
	# Controls: the same cell and path, walking (a bare passenger no file holds).
	var walking := Passenger.new()
	walking.stage = Passenger.Stage.TO_EXIT
	walking.at = held.at
	walking.set_path(held.path.duplicate())
	assert_bool(RollerPark.filed_still(sim, walking)).is_false()
	assert_bool(SecurityLooks.carry_front(sim, walking)).is_true()
	walking.seg_mm = 100
	assert_bool(SecurityLooks.carry_front(sim, walking)).is_true()


## Held part way along its path (a step taken), the cell it stands on and the
## step into it count: closed on both flanks it reads the front carry, open on
## one flank it does not.
func test_a_walker_held_after_a_step_reads_the_cell_it_stands_on() -> void:
	_world = TestBoardingFiles.boarding_world()
	_world.run_to(TestBoardingFiles.BOARDING + 5)
	var walkers: Array[Passenger] = []
	for i in FILE_WALKERS:
		var p := TestBoardingFiles.walker(_world, FILE_CELL)
		p.carry_on = 1
		walkers.append(p)
	var held := _held_walker(walkers)
	assert_object(held).is_not_null()
	var sim := _world.sim
	# Moved on one step along its own path, still held (the file stops it).
	var onto := held.path[1]
	var step := onto - held.at
	held.at = onto
	held.path_index = 1
	assert_bool(held.is_moving()).is_true()
	assert_bool(RollerPark.filed_still(sim, held)).is_true()
	assert_bool(SecurityLooks.carry_front(sim, held)).is_false()
	_close_flanks(onto, step)
	assert_bool(SecurityLooks.carry_front(sim, held)).is_true()
