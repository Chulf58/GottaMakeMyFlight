extends RefCounted
## Shared by the windowed plates probes that boot main.tscn: a new game has no
## staff and a closed airport (rulings staff-a-new-game-starts-with-an-empty-
## staff-pool-and-a-hint and the-airport-opens-when-staffed-no-flights-are-
## scheduled-unti), so a probe hires, lets the staff walk to their stations,
## lets the airport open and waits for the starter's first flight to be
## issued; that flight's states start ISSUE_LEAD_TICKS after the opening.
## Load it with preload(); it has no class_name, so the spike adds nothing to
## the game's global class list.

## Ticks the hiring, the walk and the opening may take before the probe fails.
const OPEN_LIMIT_TICKS := 6000


## The first starter occurrence's id.
static func first_flight() -> String:
	return FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)


## One check-in agent per desk and one security officer per scanner, as the
## panel's Hire buttons hire them. Returns how many were hired.
static func hire_per_station(sim: PassengerSim, staff: StaffSim) -> int:
	var hired := 0
	for desk in sim.layout.desks:
		hired += int(staff.hire(StaffMember.Role.CHECKIN) != 0)
	for scanner in sim.layout.scanners:
		hired += int(staff.hire(StaffMember.Role.SECURITY) != 0)
	return hired


## Steps the clock by hand until every hired member is on duty and the starter's
## first flight is issued. Returns that flight's doors-close tick, or -1 when
## OPEN_LIMIT_TICKS pass first (a probe prints PROBE_INVALID).
static func advance_until_open(clock: SimClock, flights: FlightSim, staff: StaffSim) -> int:
	var open := func() -> bool:
		return _all_on_duty(staff) and flights.flight_ids().has(first_flight())
	if not advance_until(clock, open, OPEN_LIMIT_TICKS):
		return -1
	return flights.doors_close_tick(first_flight())


## Steps the clock by hand (unpausing it meanwhile: a paused clock does not
## advance) until `done` holds or `limit_ticks` pass. Returns whether it held.
static func advance_until(clock: SimClock, done: Callable, limit_ticks: int) -> bool:
	var was_paused := clock.paused
	clock.set_paused(false)
	var limit := clock.tick + limit_ticks
	var met: bool = done.call()
	while not met and clock.tick < limit:
		clock.advance(SimClock.STEP)
		met = done.call()
	clock.set_paused(was_paused)
	return met


static func _all_on_duty(staff: StaffSim) -> bool:
	var ids := staff.member_ids()
	for id in ids:
		if staff.get_member(id).state != StaffMember.State.ON_DUTY:
			return false
	return not ids.is_empty()
