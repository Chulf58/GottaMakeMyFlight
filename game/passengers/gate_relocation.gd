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


## Whether the seat state `p` was saved with makes sense. With no seat: no
## placement and not getting up. With a seat: the canonical placement of a
## seat row whose footprint holds the seat cell, at one of its chairs, with the
## chair front the row's own front of that cell; and getting up from a moved
## row only while standing up.
static func valid(p: Passenger) -> bool:
	if p.seat_object == 0:
		return p.seat_piece.is_empty() and not p.seat_exiting
	if p.seat_piece.is_empty() or p.seat_cell == Passenger.NO_CELL:
		return false
	var def := BuildCatalog.get_def(p.seat_piece["def"])
	var cells := def.footprint(p.seat_piece["anchor"], p.seat_piece["facing"])
	var index := cells.find(p.seat_cell)
	if index < 0 or index >= GateChairs.CHAIR_OFFSET_M.size():
		return false
	if p.seat_front != p.seat_cell + TerminalLayout.front_of(p.seat_piece["facing"]):
		return false
	return p.stage == Passenger.Stage.STANDING_UP or not p.seat_exiting


## A passenger from an old save (version 10 or older) has no placement: the
## grid's own for the row it holds (empty when the row is gone, which valid()
## then refuses).
static func derive_piece(p: Passenger, grid: BuildGrid) -> void:
	if p.seat_object != 0 and p.seat_piece.is_empty():
		p.seat_piece = Relocation.placement(grid, p.seat_object)


## The JSON shape of a seat placement, empty for none.
static func piece_to_record(piece: Dictionary) -> Dictionary:
	if piece.is_empty():
		return {}
	var anchor: Vector2i = piece["anchor"]
	return {"def": String(piece["def"]), "anchor": [anchor.x, anchor.y], "facing": piece["facing"]}


## A placement from piece_to_record() (also after JSON): the empty one for
## none, null when malformed: any key but the three, a def that is not a seat
## row, or a facing outside 0 to 3.
static func piece_from_record(data: Variant) -> Variant:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var record: Dictionary = data
	if record.is_empty():
		return {}
	var anchor: Variant = record.get("anchor")
	var ok: bool = (
		record.size() == 3
		and record.get("def") == "seat_row"
		and typeof(anchor) == TYPE_ARRAY
		and anchor.size() == 2
		and WholeNumber.is_whole(anchor[0])
		and WholeNumber.is_whole(anchor[1])
		and WholeNumber.is_whole(record.get("facing"))
		and int(record["facing"]) >= 0
		and int(record["facing"]) <= 3
	)
	if not ok:
		return null
	return {
		"def": &"seat_row",
		"anchor": Vector2i(int(anchor[0]), int(anchor[1])),
		"facing": int(record["facing"]),
	}


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
