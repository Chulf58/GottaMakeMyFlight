class_name StaffTestKit
extends RefCounted
## Test support for staffed stations. The game only hires; tests that are not
## about staffing seat staff at once with staff_all(), so their desks and
## scanners serve from the first tick.


## Hires one member for every usable desk and scanner that has nobody and puts
## it on duty there at once. Returns how many were seated.
static func staff_all(staff: StaffSim) -> int:
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
					"%d|%d|%d|%d|%s|%d|%d|%d|%d|%d|%d"
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
					]
				)
			)
		)
	return ";".join(parts)
