class_name QuietNight
extends Node
## Decides when the sim clock fast-forwards through a quiet night (decision
## quiet-nights-fast-forward-automatically-when-nothing-is-due and ruling
## quiet-night-faster-stop-at-first-arrival-and-staff-off-shift-overnight).
## The airport is quiet when it is open, nobody is in the terminal, no flight
## is moving and the clock is not paused; modal dialogs (UnlockGuide, GameMenu,
## IncidentPanel, the intro) hold the clock, so a hold counts as paused (build
## trays, OfferPanel, and FlightPlanner do not hold it). While quiet, SimClock
## asks stop_tick() once a frame and fast-forwards to LEAD_TICKS before the
## next morning activity (the earliest of FlightSim.next_morning_activity_tick,
## PassengerSim.next_spawn_tick and IncidentDirector.next_event_tick; a roll at
## midnight schedules none sooner than IncidentDirector.FIRE_FLOOR_TICKS, so
## midnight itself is no stop). Inside that lead the airport is still quiet,
## but the stop is not ahead any more, so nothing restarts the fast-forward
## until after the event: it never flips on and off for reasons the player
## cannot see. Keeps no state and is not saved.

## Game time between the stop and the next morning activity: 10 game minutes,
## 3.3 real seconds at 3x.
const LEAD_TICKS := 200

@export var clock: SimClock
@export var flights: FlightSim
@export var passengers: PassengerSim
## The incidents whose next event also stops a fast-forward. Unset (a test
## world), only the flights do.
@export var incidents: IncidentDirector


func _ready() -> void:
	if clock == null or flights == null or passengers == null:
		push_error("QuietNight: clock, flights or passengers unset, so nights never speed up")
		return
	if incidents == null:
		push_error("QuietNight: no incidents set, so a fast-forward may run past an incident")
	bind(clock, flights, passengers, incidents)


## Drives `with_clock`'s fast-forward from these flights, passengers and
## incidents.
func bind(
	with_clock: SimClock,
	with_flights: FlightSim,
	with_passengers: PassengerSim,
	with_incidents: IncidentDirector = null
) -> void:
	clock = with_clock
	flights = with_flights
	passengers = with_passengers
	incidents = with_incidents
	clock.fast_forward_source = stop_tick


## A node that leaves the tree must not leave the clock calling it.
func _exit_tree() -> void:
	if clock != null and clock.fast_forward_source == Callable(stop_tick):
		clock.fast_forward_source = Callable()


func is_quiet() -> bool:
	return (
		not clock.paused
		and flights.opened_tick >= 0
		and passengers.active_count() == 0
		and not flights.has_moving_flight()
	)


## The tick the clock may fast-forward to now: LEAD_TICKS before the next
## morning activity, pending spawn or incident event, or -1 when the airport is
## not quiet or nothing is due. A tick at or behind the clock's means no
## fast-forward.
func stop_tick() -> int:
	if not is_quiet():
		return -1
	var next := flights.next_morning_activity_tick()
	var spawn := passengers.next_spawn_tick()
	if spawn >= 0:
		next = spawn if next < 0 else mini(next, spawn)
	if incidents != null:
		var incident := incidents.next_event_tick(clock.tick)
		if incident >= 0:
			next = incident if next < 0 else mini(next, incident)
	return next - LEAD_TICKS if next >= 0 else -1
