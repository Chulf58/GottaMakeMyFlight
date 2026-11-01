class_name MoodTint
extends RefCounted
## The colour mapping behind the queue and mood floor overlay (MoodOverlay),
## all pure functions of the passenger sim's own numbers (decision hud-steal-
## list-self-clearing-alert-cards-money-hover-departu, point 5). A passenger
## has a badness from 0 (fine) to 1 (bad), the worse of how unhappy it is and
## how long it has queued; a floor cell takes the worst badness standing on it
## and lends half of that to its four neighbours, so a queue reads as a patch.
## Read only: nothing here changes the sim.

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
## Fine, halfway and bad. The overlay draws them at ALPHA.
const GOOD_COLOR := Color(0.12, 0.7, 0.25)
const MIDDLE_COLOR := Color(0.98, 0.8, 0.1)
const BAD_COLOR := Color(0.88, 0.1, 0.1)
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


## Green at 0, yellow at 0.5, red at 1, with the overlay's alpha.
static func color_of(badness: float) -> Color:
	var t := clampf(badness, 0.0, 1.0)
	var color := (
		GOOD_COLOR.lerp(MIDDLE_COLOR, t * 2.0)
		if t < 0.5
		else MIDDLE_COLOR.lerp(BAD_COLOR, (t - 0.5) * 2.0)
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
## SPREAD of it, only on cells that hold floor.
static func cells_for(sim: PassengerSim) -> Dictionary:
	var own := {}
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		if p == null or not on_floor(p):
			continue
		var cell := sim.grid.world_to_cell(sim.world_position(p))
		own[cell] = maxf(own.get(cell, 0.0), badness_of(p, sim.tick))
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
