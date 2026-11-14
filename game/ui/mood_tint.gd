class_name MoodTint
extends RefCounted
## The colour mapping behind the queue and mood floor overlay (MoodOverlay),
## all pure functions of the passenger sim's own numbers (decision hud-steal-
## list-self-clearing-alert-cards-money-hover-departu, point 5). A passenger
## has a badness from 0 (fine) to 1 (bad), the worse of how unhappy it is and
## how long it has queued; a floor cell takes the worst badness standing on it
## and lends half of that to its four neighbours, so a queue reads as a patch.
## Read only: nothing here changes the sim.
##
## The overlay has five modes (decision crowd-need-display-mood-overlay-gains-
## hunger-toilet-and-bore): Mood, as above, and one per need (Hunger, Toilet,
## Boredom). A need mode reads that one number off each passenger: green below
## the threshold the sim itself acts on, orange at it, blending to red from
## NEED_BAD_AT. Spread to the neighbours works as in Mood.
##
## The Late mode (decision calm-view-technical-design-shared-hover-target-
## reusing-click, part 5) tints only where a late passenger stands, in one soft
## amber (LATE_COLOR, no red: lateness is feedback, not an alarm; decision
## calm-cozy-default-view-quiet-world-detail-on-ask-soft-statio, part 4). It
## picks passengers by p.late and not p.is_done(), never by the speech
## bubble's text, which puts a stuck reason before lateness.

## Which number the floor shows. MOOD is mood and queue wait; HUNGER, TOILET and
## BOREDOM are the passenger's needs; LATE marks who runs late.
enum Mode { MOOD, HUNGER, TOILET, BOREDOM, LATE }

## Mood at or above this is fine, at or below BAD_MOOD is as bad as it gets.
## Passengers start at Passenger.MOOD_START, 70, and sit in the low 60s within
## seconds on a bare floor (measured in the plate run), so that still reads fine.
const OK_MOOD := 60
const BAD_MOOD := 20
## A queue place held this long is fine, and this long is as bad as it gets
## (ticks, SimClock.TICK_RATE a second: 10 s and 50 s).
const OK_WAIT_TICKS := 200
const BAD_WAIT_TICKS := 1000
## How much of a cell's badness its four neighbours get.
const SPREAD := 0.5
## A need at or above this is as bad as it gets (red).
const NEED_BAD_AT := 85
## Fine, halfway and bad. The overlay draws them at ALPHA.
const GOOD_COLOR := Color(0.12, 0.7, 0.25)
const MIDDLE_COLOR := Color(0.98, 0.8, 0.1)
const BAD_COLOR := Color(0.88, 0.1, 0.1)
## The need modes' halfway colour: MIDDLE_COLOR reads yellow, and a need at its
## threshold is a warning to act on, not a halfway mood.
const ORANGE_COLOR := Color(0.98, 0.5, 0.1)
## The Late mode's one colour, a soft warm amber; a neighbour cell takes it at
## SPREAD of the alpha.
const LATE_COLOR := Color(0.96, 0.62, 0.18)
const ALPHA := 0.7
const NEIGHBOURS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
## The stages that are a wait in a queue for a station.
const QUEUE_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.CHECKIN_QUEUE,
	Passenger.Stage.SECURITY_QUEUE,
	Passenger.Stage.CAFE_QUEUE,
]


## 0 at OK_MOOD and above, 1 at BAD_MOOD and below, linear between.
static func mood_badness(mood: int) -> float:
	return clampf(float(OK_MOOD - mood) / float(OK_MOOD - BAD_MOOD), 0.0, 1.0)


## 0 up to OK_WAIT_TICKS in a queue place, 1 from BAD_WAIT_TICKS, linear between.
static func wait_badness(ticks: int) -> float:
	return clampf(float(ticks - OK_WAIT_TICKS) / float(BAD_WAIT_TICKS - OK_WAIT_TICKS), 0.0, 1.0)


## The passenger's badness at `tick`: the worse of its mood and, while it
## queues, its wait. A passenger the sim marks stuck is as bad as it gets.
static func badness_of(p: Passenger, tick: int) -> float:
	if p.stuck != Passenger.Stuck.NONE:
		return 1.0
	var bad := mood_badness(p.mood)
	if p.stage in QUEUE_STAGES:
		bad = maxf(bad, wait_badness(tick - p.stage_tick))
	return bad


## Whether the mode is one of the three need modes.
static func is_need_mode(mode: Mode) -> bool:
	return mode == Mode.HUNGER or mode == Mode.TOILET or mode == Mode.BOREDOM


## Whether `p` is one the Late mode marks: running late and not yet boarded or
## missed.
static func is_late(p: Passenger) -> bool:
	return p.late and not p.is_done()


## The number the need mode reads, at which the sim acts on it.
static func need_threshold(mode: Mode) -> int:
	match mode:
		Mode.HUNGER:
			return CafeSim.HUNGRY_AT
		Mode.TOILET:
			return ToiletSim.NEED_AT
		Mode.BOREDOM:
			return BoredomSim.BORED_AT
	return 0


## The passenger's number for the need mode.
static func need_value(p: Passenger, mode: Mode) -> int:
	match mode:
		Mode.HUNGER:
			return p.hunger
		Mode.TOILET:
			return p.toilet_need
		Mode.BOREDOM:
			return p.boredom
	return 0


## 0 below the mode's threshold, 0.5 at it, 1 from NEED_BAD_AT, linear between.
static func need_badness(mode: Mode, value: int) -> float:
	var at := need_threshold(mode)
	if value < at:
		return 0.0
	return 0.5 + 0.5 * clampf(float(value - at) / float(NEED_BAD_AT - at), 0.0, 1.0)


## The passenger's badness for the overlay's mode: Mood mode is badness_of,
## Late mode 1 for a late passenger and 0 for the rest.
static func badness_for(p: Passenger, tick: int, mode: Mode) -> float:
	if mode == Mode.LATE:
		return 1.0 if is_late(p) else 0.0
	if is_need_mode(mode):
		return need_badness(mode, need_value(p, mode))
	return badness_of(p, tick)


## Green at 0, yellow at 0.5, red at 1, with the overlay's alpha. A need mode
## goes through orange instead of yellow. Late mode is LATE_COLOR with its alpha
## scaled by `badness`.
static func color_of(badness: float, mode := Mode.MOOD) -> Color:
	var t := clampf(badness, 0.0, 1.0)
	if mode == Mode.LATE:
		return Color(LATE_COLOR, ALPHA * t)
	var middle := ORANGE_COLOR if is_need_mode(mode) else MIDDLE_COLOR
	var color := (
		GOOD_COLOR.lerp(middle, t * 2.0) if t < 0.5 else middle.lerp(BAD_COLOR, (t - 0.5) * 2.0)
	)
	color.a = ALPHA
	return color


## Whether the passenger stands on the terminal floor or at a gate seat, where
## the overlay draws it: not on the road, the apron, a facility seat or done.
static func on_floor(p: Passenger) -> bool:
	var where := StageKinds.location(p.stage)
	return where == StageKinds.Location.FLOOR or where == StageKinds.Location.GATE_SEAT


## Cell -> badness for every floor cell the overlay tints, read from `sim`:
## the cells passengers stand on at their own badness, their neighbours at
## SPREAD of it, only on cells that hold floor. `mode` picks the badness; Late
## mode tints only the cells of late passengers and their neighbours.
static func cells_for(sim: PassengerSim, mode := Mode.MOOD) -> Dictionary:
	var own := {}
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		if p == null or not on_floor(p):
			continue
		if mode == Mode.LATE and not is_late(p):
			continue
		var cell := sim.grid.world_to_cell(sim.world_position(p))
		own[cell] = maxf(own.get(cell, 0.0), badness_for(p, sim.tick, mode))
	var cells := {}
	for cell: Vector2i in own:
		cells[cell] = maxf(cells.get(cell, 0.0), own[cell])
		for step in NEIGHBOURS:
			var next := cell + step
			cells[next] = maxf(cells.get(next, 0.0), own[cell] * SPREAD)
	for cell: Vector2i in cells.keys():
		if sim.grid.floor_at(cell) == BuildGrid.FLOOR_NONE:
			cells.erase(cell)
	return cells
