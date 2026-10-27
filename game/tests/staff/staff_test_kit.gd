class_name StaffTestKit
extends RefCounted
## Test support for staffed stations. The game only hires; tests that are not
## about staffing seat staff at once with staff_all(), so their desks and
## scanners serve from the first tick.


## Hires one member for every usable desk and scanner that has nobody and puts
## it on duty there at once. Returns how many were seated. `roles` limits it
## to stations of those roles (both when empty).
static func staff_all(staff: StaffSim, roles: Array[StaffMember.Role] = []) -> int:
	var layout := staff.sim.layout
	var seated := 0
	var stations: Array[int] = []
	stations.append_array(layout.desks)
	stations.append_array(layout.scanners)
	for station in stations:
		if staff.staff_at(station) != 0 or not layout.is_usable(station):
			continue
		var role := StaffMember.Role.SECURITY
		if layout.desks.has(station):
			role = StaffMember.Role.CHECKIN
		if not roles.is_empty() and not roles.has(role):
			continue
		var member := staff.get_member(staff.hire(role))
		member.station = station
		member.at = layout.lanes[station][0]
		member.clear_path()
		member.state = StaffMember.State.ON_DUTY
		seated += 1
	if seated > 0:
		staff.rederive()
	return seated


## Everything that decides what a member does next, one entry per member.
static func signature(staff: StaffSim) -> String:
	var parts := PackedStringArray()
	for id in staff.member_ids():
		var m := staff.get_member(id)
		(
			parts
			. append(
				(
					"%d|%d|%d|%d|%s|%d|%d|%d|%d|%d|%d|%d"
					% [
						id,
						m.role,
						m.state,
						m.station,
						m.at,
						m.path_index,
						m.path.size(),
						m.seg_mm,
						int(m.needs_replan),
						int(m.search_failed),
						int(m.leaving),
						int(m.backing_out),
					]
				)
			)
		)
	return ";".join(parts)


## The whole world as the text a save file holds.
static func save_text(world: PassengerTestWorld) -> String:
	return (
		JSON
		. stringify(
			{
				"clock": world.clock.to_snapshot(),
				"flights": world.flights.to_snapshot(),
				"grid": world.grid.to_snapshot(),
				"passengers": world.sim.to_snapshot(),
				"staff": world.staff.to_snapshot(),
			}
		)
	)


## A fresh world restored from save_text(), with no auto-staffing; null, with
## an error pushed, when any part is refused.
static func load_world(text: String) -> PassengerTestWorld:
	var data: Dictionary = JSON.parse_string(text)
	var grid := BuildGrid.new()
	if not grid.from_snapshot(data["grid"]):
		push_error("StaffTestKit.load_world: the grid was refused")
		return null
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	world.auto_staff = false
	var loaded: bool = (
		world.clock.from_snapshot(data["clock"])
		and world.flights.from_snapshot(data["flights"])
		and world.sim.from_snapshot(data["passengers"])
		and world.staff.from_snapshot(data["staff"])
	)
	if not loaded:
		push_error("StaffTestKit.load_world: a part of the save was refused")
		world.free_all()
		return null
	return world
