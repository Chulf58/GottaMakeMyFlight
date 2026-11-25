# gdlint:disable = max-public-methods, max-file-lines
# FlightSim is the one flight data API; ending a contract (end_contract,
# active_contract_ids, contract_end_day) took it past the 20-method cap, and the
# v11 SAVE_VERSION note took it 4 lines past 1600.
class_name FlightSim
extends Node
## The flight schedule as plain data driven by SimClock ticks. Each flight is
## a record (id, start tick of every state, current state, gate); a tick moves
## it to the next state when that state's start tick arrives. Nodes only read
## it. All times are integer sim ticks (20 per second), so speed and pause
## change nothing here.
##
## Flights come from two places. Accepted contracts (FlightContract) run a
## daily timetable: each day's occurrence is issued ahead of its first state
## (FlightTimetable), named "<contract>-d<day>", and pruned after it departs;
## queries on a pruned occurrence still answer from its landed record until
## that is dropped the day after its day; after that it is unknown (_find()),
## never rebuilt from its contract's assignment now. Each contract flies the
## taxi pair of its gate's route (TaxiTimes), set with its gate; an issued
## occurrence keeps the starts it was issued with when its contract moves.
## add_flight adds a one-off flight, which is never pruned; add_default_flight
## is the one-off GMF101 that tests still use.
##
## The airport starts closed and issues no occurrence until it opens
## (decision airport-opening-design-stays-open-once-opened-starter-flight-
## placed-after-opening). AirportGate opens it once it is staffed and has a
## working path, and accepts the STARTER_TERMS contract then; open_airport()
## alone opens it without the starter. It never closes again. A contract
## accepted while closed starts on its first day issued at or after the
## opening (FlightTimetable.opening_day); the days it skipped were never
## flown, so they are never answered as departed.
##
## Gates (decision gates-technical-design-gate-desks-link-to-north-exits-one-
## st, points 4 and 5): gate_ids() lists the gates with a stand, from
## gate_source, and gate_grounds() each one's stand and largest plane class,
## from stand_source. Flights at one gate must not overlap there. The runway,
## the taxi lane and neighbouring stands are booked by GroundPlanner through
## FlightPlans (decision runway-and-taxi-technical-design-movement-plan-
## analytic-bookings-planned-pauses, sections 3, 5, 6 and 8): every flight of a
## day is planned in first-start order and may get a planned pause at a hold
## line (taxi_plan()). An accepted contract gets the best-fit gate its whole
## timetable fits at (the smallest max_class that takes its plane, then the
## lowest letter). An offer is refused with QUIET_NIGHT_TEXT when it departs
## outside 07:00 to 21:00, or an Odd hours offer with ODD_HOURS_NIGHT_TEXT
## outside 06:00 to 22:00 (FlightContract.window_problem, from its frozen
## traits), and with TAXI_BUSY_TEXT when no pause fits it or
## when it would leave an existing contract's occurrence with none (that
## occurrence may gain a pause). reassign_gate and move_contracts move a
## contract's days not yet issued through the same check; the occurrences
## already issued keep their gate, stand and plan.
##
## end_contract stops a contract's future days (decision low-rating-ends-one-
## airline-contract-per-low-day): what it already issued still flies and the
## contract stays on record, but it issues nothing more and no longer holds its
## gate time against new contracts. Taking its flights away must never leave
## another occurrence with no taxi plan, so when the re-plan without them would
## (greedy planning is not monotone) the contract keeps reserving its ground:
## FlightPlans plans its days as unrendered reservations (end_refusal()).
## end_contract_by_player is the player's End: it ends the contract the same way
## and then fires ended_by_player with end_fee, the Exit fee due (decision
## odd-hours-and-exit-fee-offer-traits-odd-hours-widens-the-dep), which
## Settlement charges. The game's own end (low rating) calls end_contract and
## costs nothing.
##
## A side spur the build pushes waits until that side is quiet (SpurMoves):
## every change checks the forecast release on a trial copy, and refuses only a
## flight it would strand (SPUR_STRANDS_TEXT).
##
## One tick: set the tick, let the gate open the airport, issue due
## occurrences and move due spurs in time order, advance every flight, prune.
## PassengerSim binds after FlightSim, so it sees the result.

signal state_changed(flight_id: String, new_state: int)
## Fires once as a flight enters DOORS_CLOSED. The passenger slice stops
## boarding on it; is_doors_closed() answers the same question as a query.
signal doors_closed(flight_id: String)
## Fires once when a contract's occurrence is issued, after it is recorded,
## before any of its states is due. Never fires on a snapshot load.
signal occurrence_added(flight_id: String)
## Fires once when end_contract stops a contract's future days. Never fires on
## a snapshot load.
signal contract_ended(contract_id: String)
## Fires after contract_ended when the player ended the contract
## (end_contract_by_player), with the Exit fee then due (0 for none). Never
## fires on a snapshot load or on the game's own end.
signal ended_by_player(contract_id: String, fee: int)
## Fires after from_snapshot() installs a save, so readers of the open state
## (AirportGate) can refresh. The only signal a load emits.
signal snapshot_loaded
## Fires from check_planning_changed() when the gates, their stands, the
## runway's size or its works differ from the last check, so an answer of
## trial_assignment() (an offer card's fit line) may have changed.
signal planning_changed
## Fires once when a pending side spur (StandPlacement.WEST or EAST) has moved
## to its wanted x (SpurMoves), after its contracts took the new stands' pairs.
signal spur_moved(side: String)

enum State {
	SCHEDULED,
	APPROACH,
	LANDING,
	TAXI_IN,
	AT_STAND,
	BOARDING,
	DOORS_CLOSED,
	PUSHBACK,
	TAXI_OUT,
	TAKEOFF,
	DEPARTED,
}

const STATE_COUNT := 11
## How long each state lasts in ticks, SCHEDULED to TAKEOFF. DEPARTED is final.
## BOARDING is 1200 ticks (60 s): in the reference terminal the walk from the
## farthest gate seat out through the exit and along the apron to the plane
## door is about 915 ticks at walking pace (test_boarding_window.gd).
## TAXI_IN (1000) and TAXI_OUT (920) keep the peak taxi speed at or under
## 16 m/s on the longest route a stand of the first site gives, with no pause
## and with the longest pause MovementPlan allows (user-ruled in decision
## runway-and-taxi-technical-design-movement-plan-analytic-bookings-planned-
## pauses; test_airside_stand.gd). They are TaxiTimes.BASE: a contract flies
## its own taxi pair (FlightContract.TAXI_KEY), longer where its gate's route
## is (ruling taxi-time-follows-each-gate-s-route-length-far-side-gates-ta).
## Departure is the start of PUSHBACK, so a longer TAXI_IN only moves the
## arrival earlier.
const PHASE_TICKS: Array[int] = [100, 120, 140, 1000, 40, 1200, 60, 120, 920, 200]
## Compact boarding length for same-day one-off charters (one_off_day >= 0),
## giving a 90-minute (1,800-tick) small-plane gate hold at TaxiTimes.BASE.
const CHARTER_BOARDING_TICKS := 380
const DEFAULT_ID := "GMF101"
## The gate of add_flight and add_default_flight unless told otherwise.
const DEFAULT_GATE := "C"
## The gates with a stand while gate_source is unset: the one stand so far.
const DEFAULT_GATES: Array[String] = [DEFAULT_GATE]
## The contract the airport opens with (Economy 7/8), without its departure minute, which
## StarterSlot sets at the opening. Fee and size sit inside the offer board's ranges.
const STARTER_TERMS := {
	"id": DEFAULT_ID,
	"airline": "Gotta Air",
	"destination": "Oslo",
	"plane_size": "small",
	"booked_passengers": 6,
	"fee_per_passenger": 50,
}
## 2: occurrences are issued FlightTimetable.ISSUE_LEAD_TICKS (2400, was 1200)
## before their first state, which changes the saved next_day at some ticks.
## 3: the airport's open state (opened_tick, start_day). A version 2 save
## loads as open since tick 0.
## 4: ended contracts (ended: contract id -> its first day never issued). A
## version 2 or 3 save loads with none ended.
## 5: a contract holds its plane class's passenger range (FlightContract.problem),
## so what a save may contain narrowed. A version 4 save is refused; there is no
## migration.
## 6: TAXI_IN and TAXI_OUT last 1000 and 920 ticks (were 600 and 720), so a
## saved occurrence's starts differ for the same contract and day. A version 5
## save is refused; there is no migration.
## 7: taxi plans (Runway R7). Each flight holds the stand it was issued at
## ("stand"), today's pruned occurrences are kept ("landed"), and a load
## re-plans every live flight and refuses a save whose plan fails. Every older
## version is refused; there is no migration.
## 8: every contract holds its offer's "traits" term (FlightContract.TRAITS_KEY,
## OfferTraits). A version 7 save is refused; there is no migration.
## 9: every contract holds its taxi pair (FlightContract.TAXI_KEY, TaxiTimes),
## a flight's TAXI_IN and TAXI_OUT may be longer than PHASE_TICKS', and
## "landed" keeps yesterday's pruned occurrences too. A version 8 save is
## refused; there is no migration.
## 10: a flight's west or east stand holds "lane_x", the x of its spur
## (StandPlacement.is_stand; decision side-spur-move-design-s7-stands-carry-
## lane-x-the-wanted-spur). A version 9 save is refused; there is no migration.
## 11: small contracts carry 4-8 passengers (was 8-16, ruling small-plane-
## passenger-count-and-fare-balance-4-8-passengers). A version 10 save is
## refused; there is no migration.
## 12: contracts carry optional one_off_day (-1 for daily, >= 0 for one-off
## charters with CHARTER_BOARDING_TICKS). A version 11 save is refused; there is
## no migration.
## 13: contracts carry optional is_hub (false for standard, true for Gold Hub
## contracts). A version 12 save is refused; there is no migration.
## 14: contracts carry optional "stand" (defaults to "gate") and flight records
## carry "stand_id". A version 13 save is refused; there is no migration.
const SAVE_VERSION := 14
const CHARTER_LATE_TEXT := "this charter's departure window has already passed"
## The refusal of a flight no taxi pause fits (user ruling a-gate-has-no-size-
## planes-use-any-stand-they-fit-neighbours-share-apron-space).
const TAXI_BUSY_TEXT := GroundPlanner.TAXI_BUSY_TEXT
const QUIET_NIGHT_TEXT := FlightContract.QUIET_NIGHT_TEXT
## An Odd hours contract's window, and the ground planner's guard, which is as wide.
const ODD_HOURS_NIGHT_TEXT := FlightContract.ODD_HOURS_NIGHT_TEXT
## English msgids ({id}: a flight a spur move would strand, {size}: a plane class).
const SPUR_STRANDS_TEXT := "the taxiway move would strand flight {id}"
const RUNWAY_TOO_SHORT_TEXT := "the runway is too short for a {size} plane"
## What kind of refusal trial_assignment() reports ("blocker"): bad terms or a
## used id, the runway's size, a clash at every gate that takes the plane, no
## taxi plan, a quiet-night departure, no gate (with a stand) for the plane, or
## taxi routes too long for any taxi pair at every gate that is not busy
## (FlightContract.assignment_problem()).
const BLOCKER_TERMS := "terms"
const BLOCKER_RUNWAY := "runway"
const BLOCKER_GATE := "gate"
const BLOCKER_TAXI := "taxi"
const BLOCKER_NIGHT := "night"
const BLOCKER_STAND := "stand"
const BLOCKER_ROUTE := "route"
const BLOCKER_BUS_GATE := "bus_gate"
const BLOCKER_CHARTER_CAPACITY := "charter_capacity"

## The clock to follow when this node enters a scene. Tests call bind_clock.
@export var clock: SimClock
## The size the runway starts at. The game scene starts small, per the design,
## and grows through runway works (RunwayWorks); a sim made in code starts with
## a runway that takes every class, so a test sets a smaller one to try the
## limit. A load replaces it.
@export var runway_start: String = PlaneClasses.LARGE:
	set(value):
		runway_start = value
		runway.size = value

## The tick the sim has been told about; set by the clock or a snapshot.
var tick: int = 0
## The calendar epoch E (SimClock.epoch): the clock's, else (no clock: a staged copy) this.
var epoch: int:
	get:
		return clock.epoch if clock != null else _epoch
	set(value):
		_epoch = value
## The tick the airport opened, or -1 while it is closed. Set only by
## open_airport() and from_snapshot(); read it, never write it.
var opened_tick: int = -1
## Asked on each tick while the airport is closed whether it may open
## (AirportGate.try_open). Set by AirportGate.bind(); without one the airport
## stays closed until open_airport() is called.
var gate: AirportGate
## Returns the gate letters that have a stand now, as an Array of Strings
## (gate_ids() sorts them). Gates slice 1b sets it from the placed gate desks;
## tests set it to supply more gates. Unset: DEFAULT_GATES.
var gate_source := Callable()
## Returns gate letter -> {"stand": StandPlacement stand, "max_class": the
## largest plane class it holds} for the gates of gate_source (GateDesks sets
## it). Unset: FlightGround.fallback() for each gate.
var stand_source := Callable()
## Bus gate IDs and remote stand sources wired by GateDesks for Slices B2/B3.
var bus_gate_source := Callable()
var bus_ground_source := Callable()
var remote_stand_source := Callable()
var remote_ground_source := Callable()
## Called as spare_stand_source(plane_class) for the stand one more gate could
## have for that class (StandPlacement stand), {} when the player could build
## none (GateDesks sets it from the build grid and SpareStand). Unset (a sim
## with no grid): a stand FlightGround.FALLBACK_SPACING_M east of the eastmost.
var spare_stand_source := Callable()
## spurs() from GateDesks.spurs(), and GateDesks.release_spur(side), called at a
## side's release tick in tick order with issuing (SpurMoves). Unset: both spurs
## stay on the floor and nothing is pending.
var spur_source := Callable()
var spur_release := Callable()
## The airport's runway. Its size decides the plane classes a contract may have
## (accept_problem) and, through OfferDesk, the classes the offer board draws.
## SaveGame saves it as the "runway" part.
var runway := Runway.new(PlaneClasses.LARGE)
## Contract id -> its recorded start day, the first day that is or will be
## issued (see _start_day): a copy, so readers cannot change it. Writing it is
## an error.
var start_days: Dictionary:
	get:
		return _start_day.duplicate()
	set(_value):
		push_error("FlightSim.start_days is read-only")

## Live flights {id, starts, state, gate, contract, day}, in timetable order
## (FlightTimetable.flight_before), so the order is a function of what is
## live and a load restores it exactly.
## A one-off flight has contract "" and day -1.
var _flights: Array[Dictionary] = []
## Read-only contracts in acceptance order.
var _contracts: Array[Dictionary] = []
## Contract id -> the first day not yet issued.
var _next_day: Dictionary = {}
## Contract id -> its first day that is or will be issued: first_day, or for a
## contract accepted while closed, FlightTimetable.opening_day. Days from
## first_day up to it were skipped, not flown.
var _start_day: Dictionary = {}
## Contract id -> the first day it never issues, for the contracts that ended
## (end_contract). The day is the contract's _next_day when it ended, so it
## equals its _next_day from then on.
var _ended: Dictionary = {}
## Contract id -> true for the ended contracts whose days not yet issued still
## book their ground (end_contract()). Saved: it depends on the world at the
## tick the contract ended, which a load cannot rebuild.
var _reserving: Dictionary = {}
## Today's and yesterday's occurrences pruned from _flights, as their records,
## in timetable order: a prune never changes a plan (FlightPlans), and a load
## can tell an occurrence that was pruned from one that is missing without
## knowing the taxi pair it flew (FlightSnapshot). Dropped the day after their
## day.
var _landed: Array[Dictionary] = []
var _plans := FlightPlans.new()
var _epoch := 0
## Bumped on every change to the contracts or the flights that can change a
## plan; the day plans in _day_plans are of this revision and of _grounds_key.
var _revision := 0
var _day_plans := {}
var _day_plans_revision := -1
var _grounds_key := ""
var _grounds_tick := -1
## Flights already reported as having no plan, so a view asking every frame
## reports each once.
var _reported := {}
## trial_assignment()'s own planner and day plans of the sim now, kept apart
## from _plans and _day_plans so an advisory trial changes no live planning
## state. Made on the first trial.
var _trial_plans: FlightPlans
var _trial_day_plans := {}
var _trial_day_planners := {}
var _trial_day_entries := {}
var _trial_plans_key := ""
## The planning state planning_changed last saw (check_planning_changed()).
var _planning_key := ""


func _ready() -> void:
	if clock != null:
		bind_clock(clock)


## Start ticks of every state for a flight whose SCHEDULED state begins at
## `first_tick` and that taxis with pair `taxi` (TaxiTimes).
static func schedule_starts(
	first_tick: int, taxi: Array = TaxiTimes.BASE, boarding_ticks: int = -1
) -> Array[int]:
	var ticks := TaxiTimes.phase_ticks(taxi)
	if boarding_ticks >= 0:
		ticks[State.BOARDING] = boarding_ticks
	var starts: Array[int] = [first_tick]
	for phase_ticks in ticks:
		starts.append(starts[starts.size() - 1] + phase_ticks)
	return starts


func bind_clock(with_clock: SimClock) -> void:
	clock = with_clock
	clock.ticked.connect(on_tick)


## Opens the airport at the current tick, starting the calendar (E freezes on it); it never
## closes again. Each contract accepted while closed starts on its first day issued at or after
## now, and what is due is issued at once. False (with an error) when already open.
## The starter contract is AirportGate.open()'s, not this.
func open_airport() -> bool:
	if opened_tick >= 0:
		push_error("FlightSim.open_airport: the airport opened at tick %d" % opened_tick)
		return false
	opened_tick = tick
	if clock != null:
		clock.start_calendar()
	for contract in _contracts:
		var day := FlightTimetable.opening_day(contract, tick, epoch)
		_start_day[contract["id"]] = day
		_next_day[contract["id"]] = day
	# The contracts' days moved, so every cached day plan is of the closed world.
	_changed()
	_issue_due()
	return true


## Adds the one-off flight GMF101, starting at tick 0.
func add_default_flight() -> bool:
	return add_flight(DEFAULT_ID, schedule_starts(0))


## Adds a one-off flight (tests and debug only; the game adds none). False
## (with an error) when the id is taken or has the occurrence form, `starts` is
## not STATE_COUNT non-decreasing ticks, the gate has no stand, or the flight
## would meet an occurrence at the gate. A one-off is not taxi-planned: it
## books no runway, lane or stand and takes no pause (FlightPlans), so its
## schedule may be any, as the tests' short ones are.
func add_flight(id: String, starts: Array[int], gate := DEFAULT_GATE) -> bool:
	var problem := _one_off_problem(id, starts, gate)
	if problem != "":
		push_error("FlightSim: flight '%s' %s" % [id, problem])
		return false
	_insert(_record(id, starts, gate, "", -1))
	_changed()
	return true


## Accepts an offer's terms (FlightContract.TERM_KEYS) as a contract whose
## first occurrence is the first one whose whole preparation window is still
## ahead, at the best-fit gate its timetable fits at (accept_gate). False (with
## an error) for bad terms, a used id or no gate it fits at. Issues the first
## occurrence at once when it is already due and the airport is open; while it
## is closed the contract waits for the opening.
func accept_contract(terms: Dictionary) -> bool:
	var problem := accept_problem(terms)
	if problem != "":
		push_error("FlightSim.accept_contract: %s" % problem)
		return false
	var chosen := _assignment(terms)
	var contract := _candidate(terms, chosen["gate"], stand_grounds(), chosen["stand"])
	_contracts.append(contract)
	_next_day[contract["id"]] = contract["first_day"]
	_start_day[contract["id"]] = contract["first_day"]
	_changed()
	_issue_due()
	return true


## Why accept_contract would refuse `terms` right now (bad terms, a used id, a
## plane class the runway cannot take (RUNWAY_TOO_SHORT_TEXT), no gate with a
## stand, a departure in the quiet night (QUIET_NIGHT_TEXT), no gate that takes
## its plane, a clash at every gate that takes it, named for the best fit, or
## TAXI_BUSY_TEXT when a gate is free but no taxi plan fits it or it would
## leave an existing occurrence with none), or "" when it would take them.
## Read-only: it pushes no error and changes nothing, so a caller can ask first.
func accept_problem(terms: Dictionary) -> String:
	var problem := FlightContract.problem(terms, FlightContract.TERM_KEYS)
	if problem == "" and FlightContract.is_charter(terms) and opened_tick < 0:
		problem = "the airport is closed"
	if problem == "" and not contract_of(terms["id"]).is_empty():
		problem = "contract id '%s' is already used" % terms["id"]
	if problem == "" and not runway.takes(terms["plane_size"]):
		problem = RunwayWorks.too_short_text(terms["plane_size"])
	if problem != "":
		return problem
	return _assignment(terms)["problem"]


## The taxi refusal behind accept_problem(`terms`): {"reason": GroundPlanner.
## TAXI_BUSY or QUIET_NIGHT, "flight": the occurrence that no plan fits, its
## own or an existing contract's ("" for QUIET_NIGHT)}, or {} when the terms
## are taken or refused for another reason. Read-only.
func accept_refusal(terms: Dictionary) -> Dictionary:
	if FlightContract.problem(terms, FlightContract.TERM_KEYS) != "":
		return {}
	if not contract_of(terms["id"]).is_empty():
		return {}
	return _assignment(terms)["refusal"]


## The gate accept_contract would give `terms` now: the best-fit gate with a
## stand whose timetable and taxi plans it fits, or "" when it would refuse
## them.
func accept_gate(terms: Dictionary) -> String:
	if accept_problem(terms) != "":
		return ""
	return _assignment(terms)["gate"]


func accept_stand(terms: Dictionary) -> String:
	if accept_problem(terms) != "":
		return ""
	return _assignment(terms)["stand"]


## What accept_contract would do with `terms` if the terms in `before` had been
## accepted first, in that order, worked out on copies of the planning state
## (FlightFit's one way in; nothing is accepted, nothing changes): {"gate": the
## gate it would get or "", "stand": stand id, "problem": accept_problem's words or "", "blocker":
## "" or a BLOCKER_ value}. Terms in `before` that would be refused leave it
## refused with their own problem. With `ignore_gate_overlap` a clash at a gate
## is not counted and a spare gate is offered as well (_with_spare_gate), so the
## answer says whether the runway and lane would take the flight were a gate
## free.
func trial_assignment(
	terms: Dictionary, before: Array = [], ignore_gate_overlap := false, only_gate := ""
) -> Dictionary:
	var extra: Array[Dictionary] = []
	var grounds := stand_grounds()
	for earlier: Dictionary in before:
		var assigned := _trial(earlier, extra, false)
		if assigned["gate"] == "":
			return assigned
		extra.append(_candidate(earlier, assigned["gate"], grounds, assigned["stand"]))
	return _trial(terms, extra, ignore_gate_overlap, only_gate)


## Stands in _best_fit_for order that take `terms`'s plane size and have no
## timetable stand/bus-gate clash or assignment problem right now. Read-only.
func free_gates(terms: Dictionary) -> Array[String]:
	if FlightContract.window_problem(terms) != "" or not runway.takes(terms["plane_size"]):
		return [] as Array[String]
	var grounds := stand_grounds()
	var out: Array[String] = []
	for stand_id in _best_fit_for(terms, grounds):
		if FlightContract.assignment_problem(stand_id, grounds[stand_id]["stand"]) != "":
			continue
		var cand_gate := stand_id
		if BusGatePairing.is_remote_stand_id(stand_id):
			var paired := BusGatePairing.nearest_free_bus_gate(
				terms,
				stand_id,
				grounds[stand_id]["stand"],
				bus_gate_ids(),
				bus_gate_grounds(),
				_contracts,
				_flights,
				_ended,
				tick,
				epoch,
				_next_day
			)
			if paired["gate"] == "":
				continue
			cand_gate = paired["gate"]
		var candidate := _candidate(terms, cand_gate, grounds, stand_id)
		if (
			FlightContract.is_charter(candidate)
			and (
				FlightTimetable.first_day(candidate, tick, epoch)
				> FlightContract.one_off_day(candidate)
			)
		):
			continue
		if _stand_or_gate_problem(candidate, _contracts) == "":
			out.append(stand_id)
	return out


## True when `first_terms` (taking `first_gate` first) and `second_terms`
## (taking `second_gate` first) each have a stand in `first_free` /
## `second_free` that does not clash at the stand or bus gate with the other.
func gates_pair_compatible(
	first_terms: Dictionary,
	first_gate: String,
	first_free: Array[String],
	second_terms: Dictionary,
	second_gate: String,
	second_free: Array[String]
) -> bool:
	var grounds := stand_grounds()
	var valid := (
		not second_free.is_empty()
		and not first_free.is_empty()
		and grounds.has(first_gate)
		and grounds.has(second_gate)
	)
	var first_cand := _paired_candidate(first_terms, first_gate, grounds, []) if valid else {}
	var second_cand := _paired_candidate(second_terms, second_gate, grounds, []) if valid else {}
	if first_cand.is_empty() or second_cand.is_empty():
		return false
	var second_ok := false
	for stand_id in second_free:
		if not _paired_candidate(second_terms, stand_id, grounds, [first_cand]).is_empty():
			second_ok = true
			break
	if not second_ok:
		return false
	for stand_id in first_free:
		if not _paired_candidate(first_terms, stand_id, grounds, [second_cand]).is_empty():
			return true
	return false


## True when `first_terms` (known to fit alone at `first_gate`) and
## `second_terms` (known to fit alone at `second_gate`) both fit whichever is
## accepted first, skipping redundant single-contract checks.
func trial_pair_fits(
	first_terms: Dictionary, first_gate: String, second_terms: Dictionary, second_gate: String
) -> bool:
	var grounds := stand_grounds()
	if not grounds.has(first_gate) or not grounds.has(second_gate):
		return false
	var first_cand := _paired_candidate(first_terms, first_gate, grounds, [])
	if first_cand.is_empty() or _trial(second_terms, [first_cand], false)["gate"] == "":
		return false
	var second_cand := _paired_candidate(second_terms, second_gate, grounds, [])
	return not second_cand.is_empty() and _trial(first_terms, [second_cand], false)["gate"] != ""


## trial_assignment()'s answer for `terms` beside `extra`, checks of the terms
## first as accept_problem makes them.
func _trial(
	terms: Dictionary, extra: Array[Dictionary], ignore_gate: bool, only_gate := ""
) -> Dictionary:
	var problem := FlightContract.problem(terms, FlightContract.TERM_KEYS)
	if problem == "" and FlightContract.is_charter(terms) and opened_tick < 0:
		problem = "the airport is closed"
	if problem == "" and not contract_of(terms["id"]).is_empty():
		problem = "contract id '%s' is already used" % terms["id"]
	for other in extra:
		if problem == "" and other["id"] == terms["id"]:
			problem = "contract id '%s' is already used" % terms["id"]
	if problem != "":
		return _assigned("", problem, {}, BLOCKER_TERMS)
	if not runway.takes(terms["plane_size"]):
		return _assigned("", RunwayWorks.too_short_text(terms["plane_size"]), {}, BLOCKER_RUNWAY)
	return _assignment(terms, extra, ignore_gate, true, only_gate)


## The gates with a stand now, sorted, from gate_source (DEFAULT_GATES while it
## is unset). Pushes an error and lists none when the source returns anything
## but an array of distinct, non-empty strings.
func gate_ids() -> Array[String]:
	var listed: Variant = gate_source.call() if gate_source.is_valid() else DEFAULT_GATES
	var gates: Array[String] = []
	if typeof(listed) != TYPE_ARRAY:
		push_error("FlightSim.gate_source must return an array of gate letters")
		return gates
	for gate_id: Variant in listed:
		if typeof(gate_id) != TYPE_STRING or gate_id == "" or gates.has(gate_id):
			push_error("FlightSim.gate_source returned a bad gate list: %s" % [listed])
			return [] as Array[String]
		gates.append(gate_id)
	gates.sort()
	return gates


func bus_gate_ids() -> Array[String]:
	if not bus_gate_source.is_valid():
		return [] as Array[String]
	var listed: Variant = bus_gate_source.call()
	var out: Array[String] = []
	if typeof(listed) == TYPE_ARRAY:
		for g: Variant in listed:
			if typeof(g) == TYPE_STRING and g != "" and not out.has(g):
				out.append(g)
	out.sort()
	return out


func remote_stand_ids() -> Array[String]:
	if not remote_stand_source.is_valid():
		return [] as Array[String]
	var listed: Variant = remote_stand_source.call()
	var out: Array[String] = []
	if typeof(listed) == TYPE_ARRAY:
		for s: Variant in listed:
			if typeof(s) == TYPE_STRING and s != "" and not out.has(s):
				out.append(s)
	out.sort()
	return out


func remote_stand_grounds() -> Dictionary:
	if not remote_ground_source.is_valid():
		return {}
	var given: Variant = remote_ground_source.call()
	return (given as Dictionary).duplicate(true) if typeof(given) == TYPE_DICTIONARY else {}


func bus_gate_grounds() -> Dictionary:
	if not bus_ground_source.is_valid():
		return {}
	var given: Variant = bus_ground_source.call()
	return (given as Dictionary).duplicate(true) if typeof(given) == TYPE_DICTIONARY else {}


func all_stand_ids() -> Array[String]:
	var out := gate_ids()
	for sid in remote_stand_ids():
		if not out.has(sid):
			out.append(sid)
	out.sort_custom(BusGatePairing.remote_sort_less)
	return out


func stand_grounds() -> Dictionary:
	var out := gate_grounds()
	out.merge(remote_stand_grounds())
	return out


## Gate letter -> {"stand", "max_class"} for every gate of gate_ids(): from
## stand_source, or FlightGround.fallback() while it is unset. A gate the
## source gives no stand for is reported and left out.
func gate_grounds() -> Dictionary:
	var given: Variant = stand_source.call() if stand_source.is_valid() else null
	var out := {}
	for gate_id in gate_ids():
		var ground: Dictionary = FlightGround.fallback(gate_id)
		if given != null:
			ground = (given as Dictionary).get(gate_id, {})
		if not StandPlacement.is_stand(ground.get("stand")):
			push_error("FlightSim: gate %s has no stand to plan on" % gate_id)
			continue
		out[gate_id] = ground
	return out


## The side spurs (spur_source): side -> {"x", "wanted"}, both on the floor
## while it is unset.
func spurs() -> Dictionary:
	return spur_source.call() if spur_source.is_valid() else SideSpurs.spurs_at({}, {})


## Whether `side`'s spur waits to move (the hover over its works says so).
func spur_pending(side: String) -> bool:
	return SpurMoves.pending(_world(), side)


## The tick `side`'s pending spur is forecast to move at (SpurMoves.release()),
## or -1 when it is not pending.
func spur_release_tick(side: String) -> int:
	return SpurMoves.release(_world(), side)


## The flight ({"id", "reason"}) or {} a build's spurs `with_spurs`, gate
## `grounds` and removal `moves` (SpurMoves.with_moves()) would strand: SpurMoves.
## refusal(), then every taxi plan from today on (GateDesks' trial). Read-only.
func spur_refusal(grounds: Dictionary, with_spurs: Dictionary, moves := {}) -> Dictionary:
	var world := _world(grounds)
	world["spurs"] = with_spurs
	world["contracts"] = SpurMoves.with_moves(_contracts, moves, grounds)
	var stranded := SpurMoves.refusal(world)
	if not stranded.is_empty():
		return stranded
	var days := FlightPlans.days_from(world, GameCalendar.day_of(tick, epoch))
	return SpurMoves.typed(
		_world(), world, _trial_planner().refusal(world, _trial_day_plan, days, [])
	)


## The stand live or landed flight `id` was issued at, or {}.
func flight_stand(id: String) -> Dictionary:
	return _find(id).get("stand", {})


## The taxi pauses of live flight `id`: FlightSim.State -> MovementPlan pause
## ({} for none) for TAXI_IN and TAXI_OUT, as FlightPlans planned its day. {}
## for an unknown flight, and for one no plan fits, which is reported once.
func taxi_plan(id: String) -> Dictionary:
	var index := _index_of(id)
	if index < 0:
		return {}
	var plans := _day_plan(FlightPlans.day_of(_flights[index]["starts"], epoch))
	if _flights[index]["contract"] == "":
		return {}
	var result: Dictionary = plans.get(id, {})
	if result.get("ok", false):
		return result["pauses"]
	if not _reported.has(id):
		_reported[id] = true
		push_error(
			(
				"FlightSim: flight %s has no taxi plan (%s); it taxis without a pause"
				% [id, result.get("reason", "not planned")]
			)
		)
	return {}


## Moves a running contract's days not yet issued to `gate_id` (a regular gate
## or remote stand). Moving to a remote stand auto-pairs the nearest free bus gate.
## The occurrences it already issued keep their gate, stand and plan until they are
## pruned. False (with an error) when reassign_problem names a reason.
func reassign_gate(contract_id: String, gate_id: String) -> bool:
	var problem := reassign_problem(contract_id, gate_id)
	if problem != "":
		push_error("FlightSim.reassign_gate: %s" % problem)
		return false
	var grounds := stand_grounds()
	var resolved := _resolve_move(contract_of(contract_id), gate_id, _contracts, grounds)
	if resolved["problem"] != "":
		push_error("FlightSim.reassign_gate: %s" % resolved["problem"])
		return false
	_contracts = _replaced(_contracts, resolved["contract"])
	_changed()
	return true


## Why reassign_gate would refuse to move `contract_id` to `gate_id` now, or "".
## Read-only.
func reassign_problem(contract_id: String, gate_id: String) -> String:
	var contract := contract_of(contract_id)
	if contract.is_empty():
		return "no contract '%s'" % contract_id
	if FlightContract.is_charter(contract):
		return "one-off charter %s cannot change gates" % contract_id
	if _ended.has(contract_id):
		return "contract %s has ended" % contract_id
	if not gate_ids().has(gate_id) and not remote_stand_ids().has(gate_id):
		return "gate '%s' has no stand" % gate_id
	if BusGatePairing.stand_id_of(contract) == gate_id:
		return "contract %s is already at gate %s" % [contract_id, gate_id]
	return _move_problem(contract, gate_id, _contracts, stand_grounds())


## Where the running contracts at `from_gates` would go if those gates went:
## {"moves": contract id -> its new gate or fallback bus gate, "stuck": the
## contract ids no gate of `to_gates` takes}. Oldest first, each to the best-fit
## gate of `to_gates` it fits (remote contracts re-pair only to staying bus
## gates in `to_gates`; regular contracts move only to regular gates in
## `to_gates`). Live flights are not moved: an issued occurrence keeps its gate.
## Read-only; move_contracts() carries a plan out.
func move_plan(from_gates: Array[String], to_gates: Array[String]) -> Dictionary:
	var grounds := stand_grounds()
	var reg_grounds := gate_grounds()
	var bus_gates := bus_gate_ids()
	var bus_grounds := bus_gate_grounds()
	var world := _world(grounds)
	var contracts := _contracts.duplicate()
	var moves := {}
	var stuck: Array[String] = []
	for i in contracts.size():
		var contract: Dictionary = contracts[i]
		if not FlightPlans.runs(world, contract["id"]):
			continue
		if not from_gates.has(contract["gate"]):
			continue
		var to := ""
		var moved_contract := {}
		var candidates: Array[String] = []
		if BusGatePairing.is_remote_contract(contract):
			var sid := BusGatePairing.stand_id_of(contract)
			var stand: Dictionary = grounds.get(sid, {}).get("stand", {})
			var staying_bus: Array[String] = []
			for bg in bus_gates:
				if to_gates.has(bg):
					staying_bus.append(bg)
			candidates = (
				BusGatePairing.sorted_bus_gates(staying_bus, bus_grounds, stand)
				if not stand.is_empty()
				else staying_bus
			)
		else:
			for gate_id in _best_fit(reg_grounds, contract["plane_size"]):
				if to_gates.has(gate_id):
					candidates.append(gate_id)
		for target_id in candidates:
			var res := _resolve_move(contract, target_id, contracts, grounds)
			if res["problem"] == "":
				to = target_id
				moved_contract = res["contract"]
				break
		if to == "":
			stuck.append(contract["id"])
			continue
		moves[contract["id"]] = to
		contracts[i] = moved_contract
	return {"moves": moves, "stuck": stuck}


## Carries out a move_plan() whose "stuck" is empty, all moves or none: the
## moves are checked in order on a scratch copy of the contracts, each as
## reassign_gate() checks one against the rest as moved so far, and only when
## every one fits does the copy replace the contracts. False (with an error,
## nothing moved) when `plan` has stuck contracts, names a contract that is not
## running, or a move no longer fits (the world changed since the plan).
func move_contracts(plan: Dictionary) -> bool:
	if not (plan["stuck"] as Array).is_empty():
		push_error("FlightSim.move_contracts: contracts %s fit no gate" % [plan["stuck"]])
		return false
	var moves: Dictionary = plan["moves"]
	var grounds := stand_grounds()
	var scratch := _contracts.duplicate()
	var moved := 0
	for i in scratch.size():
		var contract: Dictionary = scratch[i]
		if not moves.has(contract["id"]):
			continue
		var problem := (
			"contract %s has ended" % contract["id"]
			if not FlightPlans.runs(_world(grounds), contract["id"])
			else ""
		)
		var next_contract := {}
		if problem == "":
			var res := _resolve_move(contract, moves[contract["id"]], scratch, grounds)
			problem = res["problem"]
			next_contract = res["contract"]
		if problem != "":
			push_error("FlightSim.move_contracts: nothing moved: %s" % problem)
			return false
		scratch[i] = next_contract
		moved += 1
	if moved != moves.size():
		push_error("FlightSim.move_contracts: nothing moved: the plan names unknown contracts")
		return false
	_contracts = scratch
	_changed()
	return true


## Ends a contract: no day from its next unissued one on is ever issued, so the
## occurrences already issued still fly and the contract stays on record (its
## fee and terms still answer for them). Its gate time is free for a new
## contract, unless taking its days away would leave another occurrence with
## no taxi plan (end_refusal()): then its days stay booked as reservations,
## never flown, and every plan stays as it was. False (with an error) for an
## unknown or already ended contract, while the airport is closed, or when the
## earlier release of a pending side spur that the end brings would strand a
## flight (SPUR_STRANDS_TEXT).
func end_contract(contract_id: String) -> bool:
	var contract := contract_of(contract_id)
	if contract.is_empty():
		push_error("FlightSim.end_contract: no contract '%s'" % contract_id)
		return false
	if FlightContract.is_charter(contract):
		push_error("FlightSim.end_contract: contract '%s' is a one-off charter" % contract_id)
		return false
	if _ended.has(contract_id):
		push_error("FlightSim.end_contract: contract '%s' already ended" % contract_id)
		return false
	if opened_tick < 0:
		push_error("FlightSim.end_contract: the airport is closed")
		return false
	# The world the end leaves, reserving or not, checked whole before it commits.
	var reserving := not end_refusal(contract_id).is_empty()
	var trial := SpurMoves.ending(_world(), contract_id, _next_day[contract_id], reserving)
	var moved := SpurMoves.refusal(trial)
	if moved.is_empty() and reserving and not SpurMoves.pending_sides(trial).is_empty():
		var days := FlightPlans.days_from(trial, _next_day[contract_id])
		moved = SpurMoves.typed(_world(), trial, _plans.refusal(trial, _day_plan, days, []))
	if not moved.is_empty():
		push_error("FlightSim.end_contract: %s" % _ground_text(moved))
		return false
	_ended[contract_id] = _next_day[contract_id]
	if reserving:
		_reserving[contract_id] = true
	_changed()
	contract_ended.emit(contract_id)
	return true


## The player's End: end_contract, then ended_by_player with the Exit fee that
## was due (end_fee) for Settlement to charge. False, with end_contract's
## error, when it is refused; nothing is charged then.
func end_contract_by_player(contract_id: String) -> bool:
	var fee := end_fee(contract_id)
	if not end_contract(contract_id):
		return false
	ended_by_player.emit(contract_id, fee)
	return true


## The dollars ending running contract `contract_id` with the End button costs
## now: its Exit fee (OfferTraits.exit_fee) on the contract's first day and the
## OfferTraits.EXIT_FEE_DAYS - 1 days after it, else 0. 0 for a contract without
## Exit fee, an ended or an unknown one. Read-only; the End confirm shows it.
func end_fee(contract_id: String) -> int:
	var contract := contract_of(contract_id)
	if contract.is_empty() or _ended.has(contract_id) or FlightContract.is_charter(contract):
		return 0
	var term_end: int = contract["first_day"] + OfferTraits.EXIT_FEE_DAYS
	if GameCalendar.day_of(tick, epoch) >= term_end:
		return 0
	return OfferTraits.exit_fee(contract[FlightContract.TRAITS_KEY])


## The occurrence that ending running contract `contract_id` now and freeing
## its ground would leave with no taxi plan: {"id", "reason"}, or {} when every
## surviving occurrence keeps one (or the contract is not running). Read-only.
func end_refusal(contract_id: String) -> Dictionary:
	if contract_of(contract_id).is_empty() or _ended.has(contract_id):
		return {}
	var world := _world()
	var ended := _ended.duplicate()
	ended[contract_id] = _next_day[contract_id]
	world["ended"] = ended
	var days := FlightPlans.days_from(world, _next_day[contract_id])
	return _plans.refusal(world, _day_plan, days, [])


## Whether ended contract `contract_id` still reserves its ground.
func is_reserving(contract_id: String) -> bool:
	return _reserving.has(contract_id)


## The repeating contracts that have not ended, in acceptance order (oldest first).
## One-off charters (one_off_day >= 0) are excluded.
func active_contract_ids() -> Array[String]:
	var ids: Array[String] = []
	for contract in _contracts:
		if not _ended.has(contract["id"]) and not FlightContract.is_charter(contract):
			ids.append(contract["id"])
	return ids


## Contracts with future or running occurrences: active repeating contracts plus
## unissued or still-flying one-off charters.
func scheduled_contract_ids() -> Array[String]:
	var running_charters := {}
	for flight in _flights:
		var cid: String = flight.get("contract", "")
		if cid != "" and int(flight["state"]) < State.DEPARTED:
			running_charters[cid] = true
	var ids: Array[String] = []
	for contract in _contracts:
		var cid: String = contract["id"]
		if _ended.has(cid):
			continue
		if FlightContract.is_charter(contract):
			var unissued := int(_next_day.get(cid, 0)) <= FlightContract.one_off_day(contract)
			if not unissued and not running_charters.has(cid):
				continue
		ids.append(cid)
	return ids


## The first day an ended contract never issues, or -1 while it is running or
## unknown.
func contract_end_day(contract_id: String) -> int:
	return _ended.get(contract_id, -1)


func on_tick(new_tick: int) -> void:
	var from := tick
	tick = new_tick
	if runway.settle(tick, _works_flown_until()):
		_changed()
	if opened_tick < 0 and gate != null:
		gate.try_open()
	_issue_due(from)
	for flight in _flights:
		_advance(flight)
	_prune()
	check_planning_changed()


## Emits planning_changed when the gates, their stands, the side spurs, the
## runway's size or its works differ from what the last call saw; the first
## call only takes note. Each tick calls it, and so do start_works and a view
## that must follow edits made while the clock is paused (OfferPanel, every
## frame it is open).
func check_planning_changed() -> void:
	var key := (
		"%s %s %s %s %s %s %s"
		% [
			gate_grounds(),
			remote_stand_grounds(),
			bus_gate_grounds(),
			FlightGround.layout(),
			runway.size,
			runway.works.fixed_bookings(),
			spurs()
		]
	)
	if key == _planning_key:
		return
	var first := _planning_key == ""
	_planning_key = key
	if not first:
		planning_changed.emit()


## The tick the runway works that build a `target` runway would start if booked
## now: the first stretch of the timetable clear of every booking for the whole
## works (FlightPlans.works_start), or the current tick while the airport is
## closed, when nothing flies. -1 for a size nothing builds and when the next
## days have no such stretch. Read-only.
func works_start(target: String) -> int:
	var ticks := RunwayWorks.ticks(target)
	if ticks == 0:
		return -1
	if opened_tick < 0:
		return tick
	return _plans.works_start(_world(), tick, ticks)


## Books the runway works that build the next size: they start at works_start()
## and, once booked, are a fixed booking in every plan, so offers that would
## use the runway meanwhile are refused (RunwayWorks). While the airport is
## closed the size applies at once and nothing is booked. False (with an error)
## when the runway has no next size, works are already booked, or the
## timetable has no stretch for them.
func start_works(target: String) -> bool:
	var problem := ""
	if target == "" or RunwayWorks.next_size(runway.size) != target:
		problem = "the runway is %s and the works build %s" % [runway.size, target]
	elif runway.works.scheduled():
		problem = RunwayWorks.BOOKED_TEXT
	elif runway.works.start != RunwayWorks.NO_TICK:
		problem = RunwayWorks.HELD_TEXT
	var start := works_start(target) if problem == "" else -1
	if problem == "" and start < 0:
		problem = RunwayWorks.NO_GAP_TEXT
	if problem != "":
		push_error("FlightSim.start_works: %s" % problem)
		return false
	if opened_tick < 0:
		runway.size = target
		runway.works_done.emit(target)
		check_planning_changed()
		return true
	runway.works.begin(target, start)
	_changed()
	check_planning_changed()
	return true


## Live flights: one-off flights and issued occurrences not yet pruned.
func flight_ids() -> Array[String]:
	var ids: Array[String] = []
	for flight in _flights:
		ids.append(flight["id"])
	return ids


func contract_ids() -> Array[String]:
	var ids: Array[String] = []
	for contract in _contracts:
		ids.append(contract["id"])
	return ids


## The read-only contract, or {} for an unknown id.
func contract_of(contract_id: String) -> Dictionary:
	for contract in _contracts:
		if contract["id"] == contract_id:
			return contract
	return {}


## The contract an occurrence belongs to, or "" for a one-off or unknown flight.
func flight_contract_id(id: String) -> String:
	return _find(id).get("contract", "")


## The gate a live flight holds: for an occurrence issued before its contract
## moved, the contract's old gate. A pruned occurrence answers with the gate it
## held while it is landed (today's and yesterday's); "" for an unknown flight,
## including an occurrence pruned before yesterday (_find()).
func flight_gate(id: String) -> String:
	return _find(id).get("gate", "")


## The stand ID flight `id` uses ("A", "R1", ...); defaults to flight_gate(id).
func flight_stand_id(id: String) -> String:
	var rec := _find(id)
	return String(rec.get("stand_id", rec.get("gate", "")))


## All live flights at `gate` now (in [starts[0], starts[DEPARTED])), in
## timetable order.
func flights_at_gate(gate: String) -> Array[String]:
	var ids: Array[String] = []
	for flight in _flights:
		var starts: Array = flight["starts"]
		var at_target: bool = (
			flight["gate"] == gate or String(flight.get("stand_id", flight["gate"])) == gate
		)
		if at_target and starts[0] <= tick and tick < starts[State.DEPARTED]:
			ids.append(flight["id"])
	return ids


## The primary live flight at `gate` now (from its first state until it
## departs), or "". When multiple flights overlap at one gate, prefers the
## flight holding the stand (AT_STAND..PUSHBACK), then TAXI_IN, then TAXI_OUT,
## then earliest active (SCHEDULED..LANDING), then TAKEOFF.
func flight_at_gate(gate: String) -> String:
	var best := ""
	var best_rank := 99
	for flight in _flights:
		var starts: Array = flight["starts"]
		var at_target: bool = (
			flight["gate"] == gate or String(flight.get("stand_id", flight["gate"])) == gate
		)
		if at_target and starts[0] <= tick and tick < starts[State.DEPARTED]:
			var rank := _gate_priority(int(flight["state"]))
			if rank < best_rank:
				best_rank = rank
				best = flight["id"]
	return best


static func _gate_priority(state: int) -> int:
	if state >= State.AT_STAND and state <= State.PUSHBACK:
		return 0
	if state == State.TAXI_IN:
		return 1
	if state == State.TAXI_OUT:
		return 2
	if state <= State.LANDING:
		return 3
	return 4


func state_of(id: String) -> int:
	var flight := _find(id)
	return flight["state"] if not flight.is_empty() else -1


func state_start(id: String, state: int) -> int:
	var flight := _find(id)
	return flight["starts"][state] if not flight.is_empty() else -1


## Ticks from the start of BOARDING (x) to the tick the doors close (y).
func boarding_window(id: String) -> Vector2i:
	return Vector2i(state_start(id, State.BOARDING), state_start(id, State.DOORS_CLOSED))


func doors_close_tick(id: String) -> int:
	return state_start(id, State.DOORS_CLOSED)


## True from the moment the doors close until the flight is gone.
func is_doors_closed(id: String) -> bool:
	return state_of(id) >= State.DOORS_CLOSED


## True while any flight is past SCHEDULED and not yet DEPARTED: on approach,
## on the ground or taxiing out. QuietNight reads it.
func has_moving_flight() -> bool:
	for flight in _flights:
		if flight["state"] > State.SCHEDULED and flight["state"] < State.DEPARTED:
			return true
	return false


## The next tick something is due: the next state change of a flight not yet
## departed or, while the airport is open, the next occurrence a running
## contract issues (the tick its passengers are booked). -1 when nothing is.
## Read-only; QuietNight stops a fast-forward ahead of it.
func next_event_tick() -> int:
	var next := -1
	for flight in _flights:
		if flight["state"] < State.DEPARTED:
			next = _earliest(next, flight["starts"][flight["state"] + 1])
	if opened_tick < 0:
		return next
	for contract in _contracts:
		if _ended.has(contract["id"]):
			continue
		var day: int = _next_day[contract["id"]]
		if FlightContract.is_charter(contract) and day > FlightContract.one_off_day(contract):
			continue
		next = _earliest(next, FlightTimetable.issue_tick(contract, day, epoch))
	return next


## The next tick a scheduled flight approaches or an unissued active contract's
## next occurrence could start receiving relaxed arrivals or approaching, or -1
## when none is due. Read-only; QuietNight and StaffSim read it before
## issue_tick.
func next_morning_activity_tick() -> int:
	var next := -1
	for flight in _flights:
		if flight["state"] == State.SCHEDULED:
			next = _earliest(next, flight["starts"][State.APPROACH])
	if opened_tick < 0:
		return next
	for contract in _contracts:
		if _ended.has(contract["id"]):
			continue
		var day: int = _next_day[contract["id"]]
		if FlightContract.is_charter(contract) and day > FlightContract.one_off_day(contract):
			continue
		var starts := FlightTimetable.starts_for(contract, day, epoch)
		var departure: int = starts[State.PUSHBACK]
		var earliest := mini(departure - ArrivalTypes.RELAXED_LEAD_TICKS, starts[State.APPROACH])
		next = _earliest(next, earliest)
	return next


## The earlier of two ticks, where -1 is none.
static func _earliest(a: int, b: int) -> int:
	return b if a < 0 else mini(a, b)


## How far through its current state a flight is at sim time `time` (a tick
## plus the clock's alpha), from 0 to 1. A final state reads 1.
func phase_progress(id: String, time: float) -> float:
	var flight := _find(id)
	var state: int = flight["state"] if not flight.is_empty() else -1
	if state < 0:
		return 0.0
	if state == State.DEPARTED:
		return 1.0
	var start: int = flight["starts"][state]
	var end: int = flight["starts"][state + 1]
	if end <= start:
		return 1.0
	return clampf((time - start) / float(end - start), 0.0, 1.0)


## JSON-safe state for a save.
func to_snapshot() -> Dictionary:
	return FlightSnapshot.save(
		tick, opened_tick, _contracts, _start_day, _next_day, _ended, _reserving, _flights, _landed
	)


## Restores a to_snapshot() dictionary, including one that went through JSON
## (which turns ints into floats). Pushes an error and returns false, leaving
## the sim unchanged, when anything is missing, mistyped or inconsistent, when
## a live flight's stand is not its gate's, or when a live flight's re-plan
## fails. Emits only snapshot_loaded: what the save had issued stays issued.
func _snapshot_gates() -> Array[String]:
	var out := gate_ids()
	for bg in bus_gate_ids():
		if not out.has(bg):
			out.append(bg)
	out.sort()
	return out


func from_snapshot(data: Dictionary) -> bool:
	var loaded := FlightSnapshot.load(data, _snapshot_gates(), epoch)
	var problem: String = loaded.get("error", "")
	if problem == "":
		problem = _load_plan_problem(loaded)
	if problem != "":
		push_error("FlightSim.from_snapshot: %s" % problem)
		return false
	tick = loaded["tick"]
	opened_tick = loaded["opened_tick"]
	_contracts = loaded["contracts"]
	_start_day = loaded["start_day"]
	_next_day = loaded["next_day"]
	_ended = loaded["ended"]
	_reserving = loaded["reserving"]
	_flights = loaded["flights"]
	_landed = loaded["landed"]
	_changed()
	snapshot_loaded.emit()
	return true


## Why from_snapshot() would refuse `data` with the gates and grounds now, or
## "": what it checks, without installing anything or pushing an error. SaveGame
## stages a load with it.
func load_problem(data: Dictionary) -> String:
	var loaded := FlightSnapshot.load(data, _snapshot_gates(), epoch)
	if loaded.has("error"):
		return loaded["error"]
	return _load_plan_problem(loaded)


## Why a FlightSnapshot.load() result could not be installed with the gates'
## grounds now: a live flight at a stand other than its gate's, a live flight
## or a running or reserving contract too big for its gate's max_class, a
## running or reserving contract whose taxi pair is shorter than its gate's
## stand needs (TaxiTimes.for_stand()), or a request of any day the sim will
## fly (FlightPlans.horizon(): live and landed flights, and every running or
## reserving contract's occurrences) that has no taxi plan; "" for none.
func _load_plan_problem(loaded: Dictionary) -> String:
	for contract: Dictionary in loaded["contracts"]:
		if not runway.takes(contract["plane_size"]):
			return (
				"contract %s is a %s plane but the runway is %s"
				% [contract["id"], contract["plane_size"], runway.size]
			)
	var grounds := gate_grounds()
	var remote := remote_stand_grounds()
	var all_grounds := grounds.duplicate()
	all_grounds.merge(remote)
	var world := {
		"spurs": spurs(),
		"tick": loaded["tick"],
		"epoch": epoch,
		"open": loaded["opened_tick"] >= 0,
		"contracts": loaded["contracts"],
		"start_day": loaded["start_day"],
		"next_day": loaded["next_day"],
		"ended": loaded["ended"],
		"reserving": loaded["reserving"],
		"flights": loaded["flights"],
		"landed": loaded["landed"],
		"grounds": all_grounds,
		"works": runway.works.fixed_bookings(),
	}
	for flight: Dictionary in loaded["flights"]:
		var sid := String(flight.get("stand_id", flight["gate"]))
		var ground: Dictionary = (
			remote.get(sid, {}) if sid != flight["gate"] else grounds.get(flight["gate"], {})
		)
		if ground.is_empty() or not SpurMoves.holds_stand(flight, ground["stand"]):
			return "flight %s is not at its gate's stand" % flight["id"]
		var plane_class := FlightPlans.flight_class(world, flight)
		# On its side's old spur (TAKEOFF on), the gate's max_class does not bind it.
		var on_old: bool = flight["stand"] != ground["stand"]
		if not on_old and not FlightGround.class_fits(plane_class, ground["max_class"]):
			return (
				"flight %s needs a %s gate, but gate %s takes %s"
				% [flight["id"], plane_class, flight["gate"], ground["max_class"]]
			)
	for contract: Dictionary in loaded["contracts"]:
		var problem := (
			_contract_ground_problem(contract, grounds, remote)
			if FlightPlans.runs(world, contract["id"])
			else ""
		)
		if problem != "":
			return problem
	var stranded := SpurMoves.refusal(world)
	for day in FlightPlans.horizon(world) if stranded.is_empty() else []:
		var plans := _plans.plan_day(world, day)
		for request: Dictionary in FlightPlans.requests(world, day):
			var result: Dictionary = plans[request["id"]]
			if not result["ok"]:
				return "flight %s has no taxi plan: %s" % [request["id"], _ground_text(result)]
	return _ground_text(stranded) if not stranded.is_empty() else ""


## Why running or reserving `contract` cannot stand at its gate of `grounds`:
## the gate is too small for its plane, or its stand's routes need a longer taxi
## pair than the contract's (TaxiTimes.for_stand()); "" for neither.
static func _contract_ground_problem(
	contract: Dictionary, grounds: Dictionary, remote := {}
) -> String:
	var sid := String(contract.get(FlightContract.STAND_KEY, contract["gate"]))
	var ground: Dictionary = (
		remote.get(sid, {}) if sid != contract["gate"] else grounds.get(contract["gate"], {})
	)
	if not FlightGround.class_fits(contract["plane_size"], ground.get("max_class", "")):
		return (
			"contract %s needs a %s gate, but gate %s takes %s"
			% [
				contract["id"],
				contract["plane_size"],
				contract["gate"],
				ground.get("max_class", "none")
			]
		)
	var needed := TaxiTimes.for_stand(ground["stand"])
	if not TaxiTimes.covers(FlightTimetable.taxi_of(contract), needed):
		return (
			"contract %s taxis %s ticks, but gate %s needs %s"
			% [contract["id"], FlightTimetable.taxi_of(contract), contract["gate"], needed]
		)
	return ""


## A flight record with the state it is in at the current tick, at its gate's
## stand now.
func _record(
	id: String, starts: Array[int], gate: String, contract: String, day: int, stand_id := ""
) -> Dictionary:
	var resolved_stand := gate if stand_id == "" else stand_id
	var stand_dict: Dictionary = (
		remote_stand_grounds().get(resolved_stand, {}).get("stand", {})
		if resolved_stand != gate
		else gate_grounds().get(gate, {}).get("stand", {})
	)
	return {
		"id": id,
		"starts": starts.duplicate(),
		"state": FlightTimetable.state_at(starts, tick),
		"gate": gate,
		"stand_id": resolved_stand,
		"contract": contract,
		"day": day,
		"stand": stand_dict,
	}


func _one_off_problem(id: String, starts: Array[int], gate: String) -> String:
	if id == "" or _index_of(id) >= 0:
		return "has an empty or used id"
	if not FlightTimetable.parse_occurrence(id).is_empty():
		return "has an id of the contract occurrence form"
	if not FlightTimetable.starts_valid(starts):
		return "needs %d non-decreasing start ticks, 0 or more" % STATE_COUNT
	if not gate_ids().has(gate):
		return "is at gate '%s', which has no stand" % gate
	return _one_off_clash(starts, gate)


## What a one-off at `gate` with `starts` would meet at the gate: a running
## contract's days, or an issued occurrence. Other one-offs at the gate are not
## checked here (the planner books their stand).
func _one_off_clash(starts: Array[int], gate: String) -> String:
	for contract in _contracts:
		if not _ended.has(contract["id"]):
			if FlightTimetable.contract_meets(contract, gate, starts, epoch):
				return "would hold gate %s during contract %s" % [gate, contract["id"]]
	# Issued occurrences hold the gate they were issued at: an ended contract's,
	# or one issued before its contract moved.
	for flight in _flights:
		if flight["contract"] != "":
			if FlightTimetable.shares_gate(
				gate,
				starts,
				flight["gate"],
				flight["starts"],
				PlaneClasses.MEDIUM,
				_flight_plane_size(flight)
			):
				return "would hold gate %s during %s" % [gate, flight["id"]]
	return ""


## The contract `terms` would become now at `gate_id` of `grounds` (the gates'
## grounds, real or with a spare gate): the taxi pair its stand needs
## (FlightContract.assigned()) and its first day for that pair. Terms must be
## valid.
func _candidate(
	terms: Dictionary, gate_id: String, grounds: Dictionary, stand_id := ""
) -> Dictionary:
	var resolved_stand := gate_id if stand_id == "" else stand_id
	var fields := terms.duplicate()
	fields["first_day"] = 0
	fields = (
		FlightContract
		. assigned(fields, gate_id, grounds[resolved_stand]["stand"], resolved_stand)
		. duplicate()
	)
	if FlightContract.is_charter(fields):
		fields["first_day"] = FlightContract.one_off_day(fields)
	else:
		fields["first_day"] = FlightTimetable.first_day(fields, tick, epoch)
	return FlightContract.make(fields)


## A read-only copy of `contract` at `gate_id` of `grounds`, with the taxi pair
## its stand needs (FlightContract.assigned()); its first_day stays.
static func _at_gate(
	contract: Dictionary, gate_id: String, grounds: Dictionary, stand_id := ""
) -> Dictionary:
	var resolved_stand := gate_id if stand_id == "" else stand_id
	return FlightContract.assigned(
		contract, gate_id, grounds[resolved_stand]["stand"], resolved_stand
	)


## The taxi pair a contract assigned to `gate_id` (regular gate or remote stand)
## now would fly (TaxiTimes), from its stand; [] for none. Read-only.
func gate_taxi(gate_id: String) -> Array:
	var ground: Dictionary = gate_grounds().get(gate_id, remote_stand_grounds().get(gate_id, {}))
	if ground.is_empty():
		return []
	return TaxiTimes.for_stand(ground["stand"])


## `contracts` with the one of `contract`'s id replaced by it.
static func _replaced(contracts: Array[Dictionary], contract: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for other in contracts:
		out.append(contract if other["id"] == contract["id"] else other)
	return out


## The gates of `grounds` that take a `plane_class` plane, best fit first:
## regular gates first (smallest max_class, then letter), then remote stands
## (smallest max_class, then R1..Rn).
static func _best_fit(grounds: Dictionary, plane_class: String) -> Array[String]:
	var out: Array[String] = []
	for gate_id: String in grounds:
		if FlightGround.class_fits(plane_class, grounds[gate_id]["max_class"]):
			out.append(gate_id)
	out.sort_custom(
		func(a: String, b: String) -> bool:
			var ra := BusGatePairing.is_remote_stand_id(a)
			var rb := BusGatePairing.is_remote_stand_id(b)
			if ra != rb:
				return not ra
			var size_a := PlaneClasses.ORDER.find(grounds[a]["max_class"])
			var size_b := PlaneClasses.ORDER.find(grounds[b]["max_class"])
			if size_a != size_b:
				return size_a < size_b
			return BusGatePairing.remote_sort_less(a, b)
	)
	return out


## Candidate stands for `terms` on `grounds`: regular gates always come first
## in best-fit order; remote stands follow (excluded for >40-pax charters).
static func _best_fit_for(terms: Dictionary, grounds: Dictionary) -> Array[String]:
	var ordered := _best_fit(grounds, terms["plane_size"])
	if not FlightContract.is_charter(terms):
		return ordered
	var out: Array[String] = []
	for sid in ordered:
		if BusGatePairing.is_charter_allowed(terms, sid):
			out.append(sid)
	return out


func _paired_candidate(
	terms: Dictionary, stand_id: String, grounds: Dictionary, extra: Array[Dictionary]
) -> Dictionary:
	var eligible := (
		grounds.has(stand_id)
		and FlightGround.class_fits(terms["plane_size"], grounds[stand_id]["max_class"])
		and BusGatePairing.is_charter_allowed(terms, stand_id)
		and FlightContract.assignment_problem(stand_id, grounds[stand_id]["stand"]) == ""
	)
	if not eligible:
		return {}
	var running: Array[Dictionary] = []
	running.append_array(_contracts)
	running.append_array(extra)
	var gate_id := stand_id
	if BusGatePairing.is_remote_stand_id(stand_id):
		if _stand_only_clash(terms, stand_id, grounds[stand_id]["stand"], running) != "":
			return {}
		var paired := BusGatePairing.nearest_free_bus_gate(
			terms,
			stand_id,
			grounds[stand_id]["stand"],
			bus_gate_ids(),
			bus_gate_grounds(),
			running,
			_flights,
			_ended,
			tick,
			epoch,
			_next_day
		)
		gate_id = paired["gate"]
	if gate_id == "":
		return {}
	var cand := _candidate(terms, gate_id, grounds, stand_id)
	return cand if _stand_or_gate_problem(cand, running) == "" else {}


func _assignment(
	terms: Dictionary,
	extra: Array[Dictionary] = [],
	ignore_gate := false,
	trial := false,
	only_gate := ""
) -> Dictionary:
	if gate_ids().is_empty() and remote_stand_ids().is_empty():
		return _assigned("", "no gate has a stand", {}, BLOCKER_STAND)
	var night_text := FlightContract.window_problem(terms)
	if night_text != "":
		var night := {"reason": GroundPlanner.QUIET_NIGHT, "flight": ""}
		return _assigned("", night_text, night, BLOCKER_NIGHT)
	var grounds := stand_grounds()
	var existing := grounds.keys()
	var all_grounds := grounds.duplicate()
	if ignore_gate:
		grounds = _with_spare_gate(gate_grounds(), terms["plane_size"])
		all_grounds.merge(grounds, true)
	var tried := _best_fit_for(terms, grounds)
	if ignore_gate and spare_stand_source.is_valid():
		tried = tried.filter(func(gate_id: String) -> bool: return not existing.has(gate_id))
	if only_gate != "":
		if tried.has(only_gate):
			tried = [only_gate] as Array[String]
		else:
			tried = [] as Array[String]
	var running: Array[Dictionary] = []
	running.append_array(_contracts)
	running.append_array(extra)
	var clash := ""
	var busy := {}
	var too_long := ""
	var too_late := ""
	var no_bus_gate := false
	var bus_gates := bus_gate_ids()
	var bus_grounds := bus_gate_grounds()
	for stand_id in tried:
		var unassignable := FlightContract.assignment_problem(stand_id, grounds[stand_id]["stand"])
		if unassignable != "":
			too_long = unassignable if too_long == "" else too_long
			continue
		var gate_id := stand_id
		if BusGatePairing.is_remote_stand_id(stand_id) and not ignore_gate:
			var stand_clash := _stand_only_clash(
				terms, stand_id, grounds[stand_id]["stand"], running
			)
			if stand_clash != "":
				clash = stand_clash if clash == "" else clash
				continue
			if bus_gates.is_empty():
				no_bus_gate = true
				continue
			var paired := BusGatePairing.nearest_free_bus_gate(
				terms,
				stand_id,
				grounds[stand_id]["stand"],
				bus_gates,
				bus_grounds,
				running,
				_flights,
				_ended,
				tick,
				epoch,
				_next_day
			)
			if paired["gate"] == "":
				clash = paired["clash"] if clash == "" else clash
				continue
			gate_id = paired["gate"]
		var candidate := _candidate(terms, gate_id, grounds, stand_id)
		if (
			FlightContract.is_charter(candidate)
			and (
				FlightTimetable.first_day(candidate, tick, epoch)
				> FlightContract.one_off_day(candidate)
			)
		):
			too_late = TranslationServer.translate(
				"this charter's departure window has already passed"
			)
			continue
		var problem := "" if ignore_gate else _stand_or_gate_problem(candidate, running)
		if problem != "":
			clash = problem if clash == "" else clash
			continue
		var from_day: int = candidate["first_day"]
		for other in extra:
			from_day = mini(from_day, other["first_day"])
		var refusal := _contracts_refusal(
			running + [candidate], candidate, from_day, all_grounds, extra, trial
		)
		if refusal.is_empty():
			return _assigned(gate_id, "", {}, "", stand_id)
		if busy.is_empty():
			busy = {"reason": refusal["reason"], "flight": refusal["id"]}
	if not busy.is_empty():
		var kind := BLOCKER_NIGHT if busy["reason"] == GroundPlanner.QUIET_NIGHT else BLOCKER_TAXI
		return _assigned("", _ground_text(busy), busy, kind)
	var problem := clash if clash != "" else too_long
	var blocker := BLOCKER_GATE if clash != "" else BLOCKER_ROUTE
	if problem == "" and too_late != "":
		problem = too_late
		blocker = BLOCKER_TERMS
	if problem == "" and no_bus_gate:
		problem = "no bus gate available for remote stands"
		blocker = BLOCKER_BUS_GATE
	if problem == "" and BusGatePairing.is_charter_over_capacity(terms) and _any_remote_fits(terms):
		problem = "charters over %d passengers require a regular gate" % BusGatePairing.BUS_CAPACITY
		blocker = BLOCKER_CHARTER_CAPACITY
	if problem == "":
		problem = "no gate takes a %s plane" % terms["plane_size"]
		blocker = BLOCKER_STAND
	return _assigned("", problem, {}, blocker)


func _any_remote_fits(terms: Dictionary) -> bool:
	var rem := remote_stand_grounds()
	for sid: String in rem:
		if FlightGround.class_fits(terms["plane_size"], rem[sid]["max_class"]):
			return true
	return false


## `grounds` with one spare gate added: the first free letter, on the stand
## spare_stand_source gives for `plane_class` (none: grounds as they are), or
## with no source FlightGround.FALLBACK_SPACING_M east of the eastmost stand (or
## west of the westmost when east leaves the taxi lane, omitted if neither joins
## cleanly), taking any class. The run that ignores gate overlap tries it as
## well, so a flight that meets only the planes parked at today's stands can
## still be told another gate would help; the runway and the lane it shares stay
## booked as they are. Not guaranteed: that the player can afford the gate, or
## place an exit door at the source's stand.
func _with_spare_gate(grounds: Dictionary, plane_class: String) -> Dictionary:
	var spare: Dictionary = {}
	var max_class := PlaneClasses.LARGE
	if spare_stand_source.is_valid():
		spare = spare_stand_source.call(plane_class)
		max_class = plane_class
	else:
		var eastmost := {}
		var westmost := {}
		for gate_id: String in grounds:
			var stand: Dictionary = grounds[gate_id]["stand"]
			if StandPlacement.side_of(stand) != StandPlacement.NORTH:
				continue
			if eastmost.is_empty() or float(stand["x"]) > float(eastmost["x"]):
				eastmost = stand
			if westmost.is_empty() or float(stand["x"]) < float(westmost["x"]):
				westmost = stand
		var candidates: Array[Dictionary] = []
		if not eastmost.is_empty():
			var east_cand := eastmost.duplicate()
			east_cand["x"] = float(eastmost["x"]) + FlightGround.FALLBACK_SPACING_M
			candidates.append(east_cand)
			var west_cand := westmost.duplicate()
			west_cand["x"] = float(westmost["x"]) - FlightGround.FALLBACK_SPACING_M
			candidates.append(west_cand)
		else:
			candidates.append(FlightGround.scene_stand())
		for cand in candidates:
			if (
				FlightContract.assignment_problem("", cand) == ""
				and not _overlaps_any_stand(cand, grounds)
			):
				spare = cand
				break
	var out := grounds.duplicate()
	if spare.is_empty():
		return out
	for letter in FlightGround.LETTERS:
		if not grounds.has(letter):
			out[letter] = {"stand": spare, "max_class": max_class}
			break
	return out


static func _overlaps_any_stand(cand: Dictionary, grounds: Dictionary) -> bool:
	for gate_id: String in grounds:
		if GateDesks.stands_overlap(cand, grounds[gate_id]["stand"]):
			return true
	return false


## An _assignment() result.
static func _assigned(
	gate_id: String, problem: String, refusal: Dictionary, blocker: String, stand_id := ""
) -> Dictionary:
	return {
		"gate": gate_id,
		"stand": gate_id if stand_id == "" else stand_id,
		"problem": problem,
		"refusal": refusal,
		"blocker": blocker,
	}


## Why running contract `contract` could not move to `gate_id` beside
## `contracts`.
func _move_problem(
	contract: Dictionary, gate_id: String, contracts: Array[Dictionary], grounds: Dictionary
) -> String:
	return _resolve_move(contract, gate_id, contracts, grounds)["problem"]


func _move_check_contract(contract: Dictionary) -> Dictionary:
	var cid := String(contract["id"])
	if FlightContract.is_charter(contract) or not _next_day.has(cid):
		return contract
	var effective_first := maxi(int(contract["first_day"]), int(_next_day[cid]))
	if effective_first == int(contract["first_day"]):
		return contract
	var copy := contract.duplicate()
	copy["first_day"] = effective_first
	return FlightContract.make(copy)


func _resolve_move(
	contract: Dictionary, target_id: String, contracts: Array[Dictionary], grounds: Dictionary
) -> Dictionary:
	var is_bus_repair := (
		BusGatePairing.is_remote_contract(contract) and bus_gate_ids().has(target_id)
	)
	var is_remote_target := remote_stand_grounds().has(target_id)
	var stand_id := BusGatePairing.stand_id_of(contract) if is_bus_repair else target_id
	var ground: Dictionary = grounds.get(stand_id, {})
	var problem := ""
	if not FlightGround.class_fits(contract["plane_size"], ground.get("max_class", "")):
		problem = "gate %s takes no %s plane" % [stand_id, contract["plane_size"]]
	else:
		problem = FlightContract.assignment_problem(stand_id, ground["stand"])
	var check_contract := _move_check_contract(contract)
	var paired_gate := target_id
	if problem == "" and is_remote_target:
		problem = _stand_only_clash(check_contract, stand_id, ground["stand"], contracts)
		if problem == "":
			var bus_gates := bus_gate_ids()
			if bus_gates.is_empty():
				problem = "remote stand %s has no bus gate" % stand_id
			else:
				var paired := BusGatePairing.nearest_free_bus_gate(
					check_contract,
					stand_id,
					ground["stand"],
					bus_gates,
					bus_gate_grounds(),
					contracts,
					_flights,
					_ended,
					tick,
					epoch,
					_next_day
				)
				paired_gate = paired["gate"]
				problem = paired["clash"] if paired_gate == "" else ""
	if problem != "":
		return {"contract": {}, "problem": problem}
	var moved := _at_gate(contract, paired_gate, grounds, stand_id)
	var check_moved := _at_gate(check_contract, paired_gate, grounds, stand_id)
	problem = _stand_or_gate_problem(check_moved, contracts, moved)
	if problem == "":
		var refusal := _contracts_refusal(
			_replaced(contracts, moved), moved, _next_day[contract["id"]], grounds
		)
		if not refusal.is_empty():
			problem = _ground_text(refusal)
	return {"contract": moved if problem == "" else {}, "problem": problem}


## The taxi refusal ({"id", "reason"}) of the world with `contracts` in place
## of the running ones, on every day from `from_day` whose plan can differ, for
## `subject` (a contract, new or moved, whose own occurrences must plan) or an
## existing flight it would leave with no plan; {} for none. Every new
## contract in `contracts` starts on its first_day. The contracts of `also`
## (new ones planned as if already accepted) must plan too. A `trial` plans
## both worlds on the trial planner (_trial_plans), never on the live one.
func _contracts_refusal(
	contracts: Array,
	subject: Dictionary,
	from_day: int,
	grounds: Dictionary,
	also := [],
	trial := false
) -> Dictionary:
	var world := _world(grounds)
	world["contracts"] = contracts
	var start_day: Dictionary = _start_day.duplicate()
	var next_day: Dictionary = _next_day.duplicate()
	for contract: Dictionary in contracts:
		if not _next_day.has(contract["id"]):
			start_day[contract["id"]] = contract["first_day"]
			next_day[contract["id"]] = contract["first_day"]
	world["start_day"] = start_day
	world["next_day"] = next_day
	var subjects := [subject["id"]]
	for contract: Dictionary in also:
		subjects.append(contract["id"])
	var stranded := SpurMoves.refusal(world)
	if not stranded.is_empty():
		return stranded
	var days := FlightPlans.days_from(world, from_day)
	if trial and world.get("works", []).is_empty() and SpurMoves.pending_sides(world).is_empty():
		return _trial_cluster_refusal(world, days, subjects)
	var planner := _trial_planner() if trial else _plans
	var base := _trial_day_plan if trial else _day_plan
	return SpurMoves.typed(_world(), world, planner.refusal(world, base, days, subjects), subjects)


## Fast cluster-scoped refusal for read-only trials when no runway works or
## pending side spurs link separate clusters on a day: only flights in a
## connected [starts[0], starts[DEPARTED]] cluster containing a subject are
## route-built and planned, while every other flight keeps _trial_day_plan.
func _trial_cluster_refusal(world: Dictionary, days: Array[int], subjects: Array) -> Dictionary:
	var planner := _trial_planner().planner
	var world_epoch: int = world["epoch"]
	var subject_contracts: Array[Dictionary] = []
	for contract: Dictionary in world["contracts"]:
		if subjects.has(contract["id"]):
			subject_contracts.append(contract)
	for day in days:
		var subs: Array[Dictionary] = []
		for contract in subject_contracts:
			var cid: String = contract["id"]
			if not FlightPlans.runs(world, cid) or day < int(world["next_day"][cid]):
				continue
			if FlightContract.is_charter(contract) and day != FlightContract.one_off_day(contract):
				continue
			var ground: Dictionary = world["grounds"].get(BusGatePairing.stand_id_of(contract), {})
			if ground.is_empty():
				continue
			var starts := FlightTimetable.starts_for(contract, day, world_epoch)
			(
				subs
				. append(
					{
						"id": FlightTimetable.occurrence_id(cid, day),
						"s0": int(starts[0]),
						"s1": int(starts[State.DEPARTED]),
						"class": contract["plane_size"],
						"stand": ground["stand"],
						"starts": starts,
						"sub": true,
					}
				)
			)
		if subs.is_empty():
			continue
		var before := _trial_day_plan(day)
		if _fast_accept_subjects(subs, day, world_epoch, before):
			continue
		var entries: Array[Dictionary] = _base_day_entries(day, world).duplicate()
		for sub_entry in subs:
			var pos := entries.size()
			for idx in entries.size():
				var cur: Dictionary = entries[idx]
				if (
					sub_entry["s0"] < cur["s0"]
					or (sub_entry["s0"] == cur["s0"] and sub_entry["id"] < cur["id"])
				):
					pos = idx
					break
			entries.insert(pos, sub_entry)
		var start_idx := 0
		while start_idx < entries.size():
			var end_idx := start_idx + 1
			var cluster_end: int = entries[start_idx]["s1"]
			var has_sub: bool = entries[start_idx]["sub"]
			var first_sub := start_idx if has_sub else -1
			while end_idx < entries.size() and entries[end_idx]["s0"] < cluster_end:
				cluster_end = maxi(cluster_end, entries[end_idx]["s1"])
				if entries[end_idx]["sub"]:
					if not has_sub:
						first_sub = end_idx
					has_sub = true
				end_idx += 1
			if has_sub:
				planner._clear()
				for k in range(start_idx, first_sub):
					var prev_res: Dictionary = before.get(entries[k]["id"], {})
					if prev_res.get("ok", false):
						planner._add(prev_res["bookings"])
				for k in range(first_sub, end_idx):
					var e: Dictionary = entries[k]
					if not planner._buckets.is_empty() and float(e["s0"]) >= planner._held_until:
						planner._buckets.clear()
					if not e["sub"]:
						var prev_res: Dictionary = before.get(e["id"], {})
						if (
							prev_res.get("ok", false)
							and prev_res.get("pauses", {}).is_empty()
							and planner.fits(prev_res["bookings"])
						):
							planner._add(prev_res["bookings"])
							continue
					var req := FlightGround.request(
						e["id"], e["class"], e["stand"], e["starts"], world_epoch
					)
					var result := planner._plan(req)
					if not result["ok"]:
						if e["sub"]:
							return {"id": e["id"], "reason": result["reason"]}
						if before.has(e["id"]) and before[e["id"]]["ok"]:
							return {"id": e["id"], "reason": GroundPlanner.TAXI_BUSY}
			start_idx = end_idx
	return {}


## The player's words for a taxi refusal ({"reason"}).
static func _ground_text(refusal: Dictionary) -> String:
	if refusal["reason"] in SpurMoves.REASONS:
		return TranslationServer.translate("the taxiway move would strand flight {id}").format(
			{"id": refusal.get("id", refusal.get("flight", ""))}
		)
	if refusal["reason"] == GroundPlanner.QUIET_NIGHT:
		return ODD_HOURS_NIGHT_TEXT
	if refusal["reason"] == GroundPlanner.BAD_ROUTE:
		return "its taxi route cannot be booked"
	return TAXI_BUSY_TEXT


func _is_issued_charter(contract: Dictionary) -> bool:
	var cid: String = contract["id"]
	return (
		FlightContract.is_charter(contract)
		and _next_day.has(cid)
		and int(_next_day[cid]) > FlightContract.one_off_day(contract)
	)


func _stand_only_clash(
	terms_or_contract: Dictionary, stand_id: String, stand: Dictionary, contracts: Array[Dictionary]
) -> String:
	var probe := BusGatePairing.probe_contract(
		terms_or_contract, stand_id, stand, stand_id, tick, epoch
	)
	if probe.is_empty():
		return ""
	for other in contracts:
		if other["id"] == probe["id"] or _ended.has(other["id"]) or _is_issued_charter(other):
			continue
		if BusGatePairing.stand_id_of(other) != stand_id:
			continue
		var other_stand_only := _as_stand_only(other, stand_id, stand)
		if FlightTimetable.contracts_share_gate(probe, other_stand_only):
			return "contract %s clashes with %s at stand %s" % [probe["id"], other["id"], stand_id]
	for flight in _flights:
		if flight["contract"] == probe["id"]:
			continue
		var f_sid := String(flight.get("stand_id", flight["gate"]))
		if f_sid != stand_id:
			continue
		if FlightTimetable.contract_meets(
			probe, stand_id, flight["starts"], epoch, _flight_plane_size(flight), stand_id
		):
			return (
				"contract %s clashes with flight %s at stand %s"
				% [probe["id"], flight["id"], stand_id]
			)
	return ""


static func _as_stand_only(contract: Dictionary, stand_id: String, stand: Dictionary) -> Dictionary:
	var copy := contract.duplicate()
	copy["gate"] = stand_id
	copy[FlightContract.STAND_KEY] = stand_id
	copy[FlightContract.TAXI_KEY] = FlightTimetable.taxi_of(contract)
	if copy.has("first_day"):
		return FlightContract.make(copy)
	copy["first_day"] = 0
	return FlightContract.assigned(copy, stand_id, stand, stand_id)


func _stand_or_gate_problem(
	contract: Dictionary, contracts: Array[Dictionary], flight_contract := {}
) -> String:
	return _gate_problem(contract, contracts, flight_contract)


## Why `contract` could not run beside `contracts` at its stand or paired bus gate;
## "" for none. Its own issued occurrences are left out.
func _gate_problem(
	contract: Dictionary, contracts: Array[Dictionary], flight_contract := {}
) -> String:
	var c_stand := BusGatePairing.stand_id_of(contract)
	for other in contracts:
		if other["id"] == contract["id"] or _ended.has(other["id"]) or _is_issued_charter(other):
			continue
		if FlightTimetable.contracts_share_gate(contract, other):
			var o_stand := BusGatePairing.stand_id_of(other)
			if c_stand == o_stand and BusGatePairing.is_remote_stand_id(c_stand):
				return (
					"contract %s clashes with %s at stand %s"
					% [contract["id"], other["id"], c_stand]
				)
			return (
				"contract %s clashes with %s at gate %s"
				% [contract["id"], other["id"], other["gate"]]
			)
	var live_check: Dictionary = contract if flight_contract.is_empty() else flight_contract
	for flight in _flights:
		if flight["contract"] == live_check["id"]:
			continue
		var f_stand := String(flight.get("stand_id", flight["gate"]))
		if FlightTimetable.contract_meets(
			live_check, flight["gate"], flight["starts"], epoch, _flight_plane_size(flight), f_stand
		):
			if c_stand == f_stand and BusGatePairing.is_remote_stand_id(c_stand):
				return (
					"contract %s clashes with flight %s at stand %s"
					% [live_check["id"], flight["id"], c_stand]
				)
			return (
				"contract %s clashes with flight %s at gate %s"
				% [live_check["id"], flight["id"], flight["gate"]]
			)
	return ""


func _flight_plane_size(flight: Dictionary) -> String:
	var contract_id: String = flight.get("contract", "")
	if contract_id != "":
		var contract := contract_of(contract_id)
		if not contract.is_empty():
			return contract["plane_size"]
	return PlaneClasses.MEDIUM


## The planning world of the sim now (FlightPlans), on `grounds`, its spur
## forecast from `from_tick` (SpurMoves).
func _world(grounds := {}, from_tick := tick) -> Dictionary:
	return {
		"spurs": spurs(),
		"tick": from_tick,
		"epoch": epoch,
		"open": opened_tick >= 0,
		"contracts": _contracts,
		"start_day": _start_day,
		"next_day": _next_day,
		"ended": _ended,
		"reserving": _reserving,
		"flights": _flights,
		"landed": _landed,
		"grounds": grounds if not grounds.is_empty() else stand_grounds(),
		"works": runway.works.fixed_bookings(),
	}


## The plan of calendar day `day` for the sim now, cached until the contracts,
## the flights, the gates' grounds or the calendar epoch change.
func _day_plan(day: int) -> Dictionary:
	var world := _world()
	var key := (
		"%d %s %s %s" % [epoch, world["grounds"], FlightGround.layout(), SpurMoves.key(world)]
	)
	if _day_plans_revision != _revision or key != _grounds_key:
		_day_plans.clear()
		_day_plans_revision = _revision
		_grounds_key = key
	if not _day_plans.has(day):
		_day_plans[day] = _plans.plan_day(world, day)
	return _day_plans[day]


## The plan of calendar day `day` for the sim now as the trial planner makes
## it: the same plan _day_plan() gives (planning is a function of the world),
## cached apart from it, so a trial never fills, reads or replans the live
## planner or its cache.
func _trial_day_plan(day: int) -> Dictionary:
	var world := _world()
	var key := (
		"%d %d %s %s %s %s"
		% [
			_revision,
			epoch,
			world["grounds"],
			FlightGround.layout(),
			runway.works.fixed_bookings(),
			SpurMoves.key(world)
		]
	)
	if key != _trial_plans_key:
		_trial_day_plans.clear()
		_trial_day_planners.clear()
		_trial_day_entries.clear()
		_trial_plans_key = key
	if not _trial_day_plans.has(day):
		_trial_day_plans[day] = _trial_planner().plan_day(world, day)
	return _trial_day_plans[day]


## Cached sorted flight entries of the unmodified sim on `day`, sharing _trial_plans_key.
func _base_day_entries(day: int, world: Dictionary) -> Array[Dictionary]:
	if not _trial_day_entries.has(day):
		var base_epoch: int = epoch
		var entries: Array[Dictionary] = []
		for list: String in ["landed", "flights"]:
			for flight: Dictionary in world[list]:
				if (
					flight["contract"] != ""
					and FlightPlans.day_of(flight["starts"], base_epoch) == day
				):
					var starts: Array = flight["starts"]
					(
						entries
						. append(
							{
								"id": flight["id"],
								"s0": int(starts[0]),
								"s1": int(starts[State.DEPARTED]),
								"class": FlightPlans.flight_class(world, flight),
								"stand": flight["stand"],
								"starts": starts,
								"sub": false,
							}
						)
					)
		for contract: Dictionary in _contracts:
			var cid: String = contract["id"]
			if not FlightPlans.runs(world, cid) or day < int(_next_day[cid]):
				continue
			if FlightContract.is_charter(contract) and day != FlightContract.one_off_day(contract):
				continue
			var ground: Dictionary = world["grounds"].get(BusGatePairing.stand_id_of(contract), {})
			if ground.is_empty():
				continue
			var starts := FlightTimetable.starts_for(contract, day, base_epoch)
			(
				entries
				. append(
					{
						"id": FlightTimetable.occurrence_id(cid, day),
						"s0": int(starts[0]),
						"s1": int(starts[State.DEPARTED]),
						"class": contract["plane_size"],
						"stand": ground["stand"],
						"starts": starts,
						"sub": false,
					}
				)
			)
		entries.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				return a["s0"] < b["s0"] if a["s0"] != b["s0"] else a["id"] < b["id"]
		)
		_trial_day_entries[day] = entries
	return _trial_day_entries[day]


## Indexed bookings of _trial_day_plan(day)'s valid flights, cached alongside it.
func _trial_day_planner(day: int, before: Dictionary) -> GroundPlanner:
	if not _trial_day_planners.has(day):
		var dp := FlightGround.planner()
		for result: Dictionary in before.values():
			if result["ok"]:
				dp._add(result["bookings"])
		_trial_day_planners[day] = dp
	return _trial_day_planners[day]


## True when every subject on `day` fits with no pause against _trial_day_plan(day)'s
## bookings and no two subjects overlap in [s0, s1], so no existing flight can change.
func _fast_accept_subjects(
	subs: Array[Dictionary], day: int, world_epoch: int, before: Dictionary
) -> bool:
	if subs.size() > 1:
		for i in subs.size():
			for j in range(i + 1, subs.size()):
				if subs[i]["s0"] < subs[j]["s1"] and subs[j]["s0"] < subs[i]["s1"]:
					return false
	var dp := _trial_day_planner(day, before)
	for sub_entry in subs:
		if not GroundPlanner.keeps_quiet_night(sub_entry["starts"], world_epoch):
			return false
		var req := FlightGround.request(
			sub_entry["id"],
			sub_entry["class"],
			sub_entry["stand"],
			sub_entry["starts"],
			world_epoch
		)
		var shape := dp._shape(req)
		var opts_in: Array = shape["options"][State.TAXI_IN]
		var opts_out: Array = shape["options"][State.TAXI_OUT]
		if (
			opts_in.is_empty()
			or not opts_in[0].is_empty()
			or opts_out.is_empty()
			or not opts_out[0].is_empty()
		):
			return false
		var base := float(sub_entry["starts"][0])
		var owner: String = sub_entry["id"]
		var bookings := GroundPlanner._shifted(shape["fixed"], base, owner)
		bookings.append_array(
			GroundPlanner._shifted(
				GroundPlanner._option_bookings(shape, State.TAXI_IN, 0), base, owner
			)
		)
		bookings.append_array(
			GroundPlanner._shifted(
				GroundPlanner._option_bookings(shape, State.TAXI_OUT, 0), base, owner
			)
		)
		if not dp.fits(bookings):
			return false
	return true


## The trial planner, made on first use.
func _trial_planner() -> FlightPlans:
	if _trial_plans == null:
		_trial_plans = FlightPlans.new()
	return _trial_plans


## A change to the contracts or flights that can change a plan.
func _changed() -> void:
	_revision += 1
	_reported.clear()


## Issues every occurrence whose issue tick has come, oldest first (then by
## contract order and day), so the order never depends on dictionary order, and
## moves each pending spur whose release tick has come (forecast from
## `from_tick`, the tick before a jump) before the first occurrence issued at or
## after it, so a skipped-tick jump puts each occurrence on the right side of R.
## Nothing is issued while the airport is closed.
func _issue_due(from_tick := tick) -> void:
	var world := _world({}, from_tick)
	var due: Array = []
	for side in SpurMoves.pending_sides(world):
		if SpurMoves.release(world, side) <= tick:
			due.append([SpurMoves.release(world, side), -1, side])
	for index in _contracts.size():
		var contract := _contracts[index]
		if opened_tick < 0 or _ended.has(contract["id"]):
			continue
		var day: int = _next_day[contract["id"]]
		var limit := (
			FlightContract.one_off_day(contract)
			if FlightContract.is_charter(contract)
			else FlightContract.MAX_DAY
		)
		while day <= limit and FlightTimetable.issue_tick(contract, day, epoch) <= tick:
			due.append([FlightTimetable.issue_tick(contract, day, epoch), index, day])
			day += 1
	due.sort_custom(_issued_before)
	for entry in due:
		if entry[1] < 0:
			_release_spur(entry[2])
		else:
			_issue(_contracts[entry[1]], entry[2])


## Moves `side`'s spur to its wanted x (spur_release), then gives each running or
## reserving contract at a gate on that side its gate's new stand's taxi pair,
## as SpurMoves.resolve() planned its days from the release on.
func _release_spur(side: String) -> void:
	if not spur_release.is_valid():
		push_error("FlightSim: the %s spur is pending but no spur_release is set" % side)
		return
	spur_release.call(side)
	var grounds := gate_grounds()
	var world := _world(grounds)
	for i in _contracts.size():
		var contract := _contracts[i]
		var ground: Dictionary = grounds.get(contract["gate"], {})
		if ground.is_empty() or StandPlacement.side_of(ground["stand"]) != side:
			continue
		if FlightPlans.runs(world, contract["id"]):
			_contracts[i] = _at_gate(contract, contract["gate"], grounds)
	_changed()
	spur_moved.emit(side)


## Orders [issue tick, contract index, day] entries field by field.
static func _issued_before(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false


func _issue(contract: Dictionary, day: int) -> void:
	var id := FlightTimetable.occurrence_id(contract["id"], day)
	var starts := FlightTimetable.starts_for(contract, day, epoch)
	var sid := String(contract.get(FlightContract.STAND_KEY, contract["gate"]))
	_insert(_record(id, starts, contract["gate"], contract["id"], day, sid))
	_next_day[contract["id"]] = day + 1
	occurrence_added.emit(id)


func _insert(record: Dictionary) -> void:
	var at := _flights.size()
	while at > 0 and FlightTimetable.flight_before(record, _flights[at - 1]):
		at -= 1
	_flights.insert(at, record)


## Drops each departed occurrence an hour after it departs by its own starts
## (FlightTimetable.prune_tick(), never its contract's times now), keeping it in
## _landed, in timetable order, until the day after its day is over, and drops
## the landed occurrences of days gone (no plan from yesterday on depends on
## them).
func _prune() -> void:
	for i in range(_flights.size() - 1, -1, -1):
		var flight := _flights[i]
		if flight["contract"] == "":
			continue
		if tick >= FlightTimetable.prune_tick(flight["starts"]):
			_insert_landed(flight)
			_flights.remove_at(i)
	var today := GameCalendar.day_of(tick, epoch)
	for i in range(_landed.size() - 1, -1, -1):
		if FlightPlans.day_of(_landed[i]["starts"], epoch) < today - 1:
			_landed.remove_at(i)
			for day: int in _day_plans.keys():
				if day < today - 1:
					_day_plans.erase(day)
	# A trial plans from today on, so it needs no plan of a past day.
	for day: int in _trial_day_plans.keys():
		if day < today:
			_trial_day_plans.erase(day)
			_trial_day_planners.erase(day)
			_trial_day_entries.erase(day)


## Adds a pruned occurrence to _landed in timetable order. Occurrences prune by
## their own DEPARTED, which with mixed taxi pairs is not first-start order.
func _insert_landed(record: Dictionary) -> void:
	var at := _landed.size()
	while at > 0 and FlightTimetable.flight_before(record, _landed[at - 1]):
		at -= 1
	_landed.insert(at, record)


## The tick until which a live flight that may have met the runway works flies:
## the latest DEPARTED of the live flights whose first state comes before the
## works end; RunwayWorks.NO_TICK with no works or no such flight.
## Runway.settle() holds the works' booking until then as well. Issued flights
## keep their starts, so ending or moving a contract never shortens it.
func _works_flown_until() -> int:
	var until := RunwayWorks.NO_TICK
	if runway.works.start == RunwayWorks.NO_TICK:
		return until
	for flight in _flights:
		var starts: Array = flight["starts"]
		if starts[0] < runway.works.finish:
			until = maxi(until, starts[State.DEPARTED])
	return until


func _advance(flight: Dictionary) -> void:
	var starts: Array = flight["starts"]
	while flight["state"] < State.DEPARTED and tick >= starts[flight["state"] + 1]:
		flight["state"] += 1
		state_changed.emit(flight["id"], flight["state"])
		if flight["state"] == State.DOORS_CLOSED:
			doors_closed.emit(flight["id"])


## The live record, or for an issued occurrence pruned today or yesterday its
## landed record; {} for anything else. An occurrence pruned before yesterday is
## {} too: its record is gone, and rebuilding it from its contract would give
## the contract's gate and taxi pair now, which after a move are not the ones it
## flew. Every caller asks about live flights or ones that left within the day
## (passengers retire PassengerSim.SETTLED_KEEP_TICKS after they settle).
func _find(id: String) -> Dictionary:
	var index := _index_of(id)
	if index >= 0:
		return _flights[index]
	for flight in _landed:
		if flight["id"] == id:
			return flight
	return {}


func _index_of(id: String) -> int:
	for i in _flights.size():
		if _flights[i]["id"] == id:
			return i
	return -1
