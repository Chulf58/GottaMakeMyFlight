class_name CleanerTestKit
extends RefCounted
## Support for the cleaner tests (StaffSim, CleanerJobs): the mess tests' open
## world (MessTestKit.open_world(), entrance door at (2, 19)), cleaners hired
## onto a chosen cell, the world reset between cases, and stepping until a
## condition holds.

const CLEANER := StaffMember.Role.CLEANER


## No messes, bin fill or counters, and no staff, ids from 1: through each
## sim's own load, the messes first (the staff load checks claims against
## them).
static func reset(world: PassengerTestWorld) -> bool:
	if not MessTestKit.clear(world):
		return false
	var empty := {"save_version": StaffSim.SAVE_VERSION, "next_id": 1, "members": []}
	return world.staff.from_snapshot(empty)


## Hires a cleaner and stands it idle on `cell` (in the pool for NO_CELL).
static func cleaner_at(world: PassengerTestWorld, cell: Vector2i) -> StaffMember:
	var m := world.staff.get_member(world.staff.hire(CLEANER))
	m.at = cell
	m.clear_path()
	return m


## Steps `world` until `done` (no arguments, returns bool) holds, at most
## `limit` ticks; whether it held.
static func step_until(world: PassengerTestWorld, done: Callable, limit := 2000) -> bool:
	for i in limit:
		if done.call():
			return true
		world.step()
	return done.call()


## The mess claimed by member `id`, or 0.
static func claim_of(world: PassengerTestWorld, id: int) -> int:
	var messes := world.sim.messes
	for mess_id in messes.mess_ids():
		if int(messes.get_mess(mess_id)["claimed_by"]) == id:
			return mess_id
	return 0
