class_name LaneStaffWorld
extends RefCounted
## Test support for security lane staffing: floored grids holding whole
## security lanes, all facing 0, with an entrance on the bottom row.
##
## two_lanes() is mirror-symmetric about its middle column x = 10: an
## entrance at (10, 15), lane A (RIGHT) rooted at (4, 6) and lane B (LEFT)
## rooted at (16, 6), so a member walking in from the entrance has equally
## long ways to the same post of either lane. Lane A is placed first and has
## the lower arch id.

const TWO_SIZE := Vector2i(21, 16)
const ENTRANCE := Vector2i(10, 15)
const ARCH_A := Vector2i(4, 6)
const ARCH_B := Vector2i(16, 6)


## The symmetric two-lane grid; returns [grid, arch A id, arch B id].
static func two_lanes() -> Array:
	var grid := PassengerTestWorld.floored(TWO_SIZE)
	PassengerTestWorld.place(grid, &"entrance_door", ENTRANCE, 2)
	var a: int = SecurityLaneBuilder.build(grid, ARCH_A, 0, SecurityLanes.RIGHT)[SecurityLanes.ARCH]
	var b: int = SecurityLaneBuilder.build(grid, ARCH_B, 0, SecurityLanes.LEFT)[SecurityLanes.ARCH]
	return [grid, a, b]


## Walls the lane's primary officer spot and the floor cell beyond it (away
## from the X-ray belt) into a closed two-cell pocket: the lane is still whole
## (the spot is free and has a step out), but staff cannot walk to the spot
## from any entrance. Only for a lane at facing 0.
static func pocket_primary_spot(grid: BuildGrid, lane: Dictionary) -> void:
	var spot: Vector2i = lane["primary_spot"]
	var beyond: Vector2i = spot + lane["side"]
	var outer := BuildGrid.Side.EAST if (lane["side"] as Vector2i).x > 0 else BuildGrid.Side.WEST
	var walls := [
		[spot, BuildGrid.Side.NORTH],
		[spot, BuildGrid.Side.SOUTH],
		[beyond, BuildGrid.Side.NORTH],
		[beyond, BuildGrid.Side.SOUTH],
		[beyond, outer],
	]
	for wall: Array in walls:
		var result := grid.apply(BuildEdit.place_wall(wall[0], wall[1]))
		assert(result.ok, "pocket wall refused: %s" % result.reason_text())


## The lane of `arch` as the world's layout recognises it.
static func lane_of(world: PassengerTestWorld, arch: int) -> Dictionary:
	return world.sim.layout.security_lanes.lane(arch)


## Steps until `id` is on duty or `limit` ticks pass; returns whether it is.
static func until_on_duty(world: PassengerTestWorld, id: int, limit := 1200) -> bool:
	var stop := world.clock.tick + limit
	while world.clock.tick < stop:
		var m := world.staff.get_member(id)
		if m != null and m.state == StaffMember.State.ON_DUTY:
			return true
		world.step()
	return world.staff.get_member(id).state == StaffMember.State.ON_DUTY


## The rule "a helper never leaves a station closed", as it stands now: ""
## when no member holds a helper post or no security station staff can work
## lacks a primary; otherwise what breaks it.
static func helper_beside_vacancy(staff: StaffSim) -> String:
	var helpers := []
	for id in staff.member_ids():
		if staff.get_member(id).is_helper():
			helpers.append(id)
	if helpers.is_empty():
		return ""
	for station in staff.stations_of(StaffMember.Role.SECURITY):
		if StaffPosts.is_vacant(staff, station, StaffMember.Slot.PRIMARY):
			return "helpers %s while station %d has no primary" % [helpers, station]
	return ""
