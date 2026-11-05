class_name GateRelocation
extends RefCounted
## A gate-seated passenger when its seat row moves with its room (decision
## move-rooms-technical-design-roommove-plan-of-existing-edits, part 4, the
## same Relocation design as the cafe, toilet and shop visitors; board
## fee68e85). Each passenger keeps the placement of the row it holds
## (Passenger.seat_piece, set when the seat is claimed and refreshed on every
## reconcile while the row stays put). When the sim's reconcile finds the row
## at another placement while the passenger is sitting down or seated, the
## passenger turns back as an early leave turns a sit-down back (the stand-up
## starts from how far the sit-down got) and gets up at the old spot:
## seat_exiting, its seat cells and chair unchanged, so it neither jumps nor
## sits on air. A stand-up already under way just finishes there. When the
## stand-up ends the sim's own stand-up code runs: a roller is taken into the
## pull first (ParkRecovery.stand_up_ticks()), then the passenger plans from
## TO_GATE like any free passenger, a seat near its gate desk at the moved
## row or elsewhere, a standing spot, or the exit once boarding has begun. A
## gate has no service to forecast, so that is the whole of "admitted again,
## or gives up". While it gets up, Relocation.ghosts() lists the row at the old
## spot and Relocation.exit_cells() keeps its seat and chair front clear.
##
## A seat the edit removed, rather than moved, still sends a sitting or
## seated passenger straight to TO_GATE (with the roller collected first,
## ParkRecovery); a stand-up under way finishes either way. A passenger walking
## to a moved row chooses again.

## The stages in which a passenger is physically at its seat row.
const SEAT_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.SITTING_DOWN, Passenger.Stage.SEATED, Passenger.Stage.STANDING_UP
]


## Whether `p`, which holds a seat, keeps it after an edit: true when its row
## is where it was, or when the row moved and `p` started getting up from it
## (this turns it back to STANDING_UP through `set_stage`, the sim's _set_stage).
## False when the seat is gone, or the row moved under a walker still on its
## way, so the sim releases it.
static func holds_seat(sim: PassengerSim, p: Passenger, set_stage: Callable) -> bool:
	if p.seat_exiting:
		return true
	var live := Relocation.placement(sim.grid, p.seat_object)
	if p.stage == Passenger.Stage.STANDING_UP:
		# Never cut short: it finishes getting up from the seat it has.
		if not p.seat_piece.is_empty() and live != p.seat_piece:
			p.seat_exiting = true
			sim.drop_seat_claim(p)
		return true
	var moved := Relocation.moved(p.seat_piece, live)
	if moved and SEAT_STAGES.has(p.stage):
		_get_up(sim, p, set_stage)
		return true
	if moved or not seat_exists(sim, p):
		return false
	p.seat_piece = live
	return true


## Whether the layout holds the seat `p` claimed.
static func seat_exists(sim: PassengerSim, p: Passenger) -> bool:
	for seat in sim.layout.seats:
		if seat["object_id"] == p.seat_object and seat["cell"] == p.seat_cell:
			return true
	return false


## The placement of the seat row `p` is drawn on: the old spot while the row
## has moved (also before the sim's next tick, with the game paused) or `p` is
## getting up from it, else the grid's, empty for a row an edit removed.
static func chair_of(sim: PassengerSim, p: Passenger) -> Dictionary:
	var live := Relocation.placement(sim.grid, p.seat_object)
	if p.seat_exiting or Relocation.moved(p.seat_piece, live):
		return p.seat_piece
	return live


## The relocation a getting-up passenger holds, for Relocation.ghosts(), or
## null while the row has not moved.
static func leaving(p: Passenger) -> Relocation:
	return Relocation.leaving(p.seat_piece, -1) if p.seat_exiting else null


## The cells the passengers at a seat need clear: its seat cell and the chair
## front it comes and goes by.
static func exit_cells(sim: PassengerSim) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		if p.seat_object != 0 and SEAT_STAGES.has(p.stage):
			for cell: Vector2i in [p.seat_cell, p.seat_front]:
				if not out.has(cell):
					out.append(cell)
	return out


## Whether the seat state `p` was saved with makes sense: a placement only with
## a seat, and getting up from a moved row only while standing up.
static func valid(p: Passenger) -> bool:
	if p.seat_object == 0:
		return p.seat_piece.is_empty() and not p.seat_exiting
	if p.seat_exiting:
		return p.stage == Passenger.Stage.STANDING_UP and not p.seat_piece.is_empty()
	return true


## The JSON shape of a seat placement: Relocation's record of a final exit, or
## empty for none.
static func piece_to_record(piece: Dictionary) -> Dictionary:
	return {} if piece.is_empty() else Relocation.leaving(piece, -1).to_record()


## A placement from piece_to_record() (also after JSON): the empty one for
## none, null when malformed.
static func piece_from_record(data: Variant) -> Variant:
	if typeof(data) == TYPE_DICTIONARY and (data as Dictionary).is_empty():
		return {}
	var held := Relocation.from_record(data)
	return null if held == null else held.source


## Turns `p` back to STANDING_UP at its old seat. A sit-down turned back
## partway gets up in as long as it had sat down, as an early cafe leave does.
static func _get_up(sim: PassengerSim, p: Passenger, set_stage: Callable) -> void:
	var sitting := p.stage == Passenger.Stage.SITTING_DOWN
	var spent := mini(sim.tick - p.stage_tick, PassengerSim.SIT_DOWN_TICKS)
	p.seat_exiting = true
	sim.drop_seat_claim(p)
	set_stage.call(p, Passenger.Stage.STANDING_UP)
	if sitting:
		p.stage_tick = sim.tick - (PassengerSim.STAND_UP_TICKS - spent)
