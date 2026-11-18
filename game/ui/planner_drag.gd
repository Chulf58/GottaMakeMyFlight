class_name PlannerDrag
extends Node
## The drag of a flight planner bar (decision flight-planner-a-full-screen-day-
## planner-with-one-row-per-ga, slice 2), as a child of the FlightPlanner. When a
## PlannerBar is picked up (NOTIFICATION_DRAG_BEGIN), each gate row the move
## would be refused on is greyed with the reason in the player's words
## (DeparturesBoard.reason_text). Two rows are "home" and take no drop, and are
## not greyed: the row the bar was picked up from, and the contract's current
## gate. After a move, an issued day's bar stays on its old row, and dropping it
## back there must not move the future days. The message line follows the row
## under the pointer, since Godot shows no tooltip during a drag. A drop calls
## on_drop(contract id, gate), which the planner points at its Move to path. The
## drag ending (NOTIFICATION_DRAG_END) clears the rows; a drop that did not land
## keeps a refusal shown and clears any other message.

## The English msgid of the message while a flight is dragged and the pointer is
## not over a row it fits. Tests compare with it; the message itself is tr() of
## the same literal, because the POT extractor reads only literals.
const DRAG_TEXT := "Drop the flight on another gate's row."

var flights: FlightSim
## The planner's message line.
var message: Label
## Drags start only while this is visible.
var sheet: Control
## Called with (contract id, gate id) for a drop on a row that takes it.
var on_drop: Callable
## The rows drawn now; the planner shares its own list.
var tracks: Array[PlannerTrack] = []

## The bar being dragged ({contract, day, gate}), {} for none, and the gate of the
## row its pointer was last over.
var _drag := {}
var _over := ""


## The text a drag over a row the flight fits shows: "Drop to move Rome to gate C. ...".
static func drop_text(destination: String, gate_id: String) -> String:
	# gdlint:ignore = max-line-length
	return (
		TranslationServer
		. translate(
			"Drop to move {destination} to gate {gate}. Days already issued keep their gate."
		)
		. format({"destination": destination, "gate": gate_id})
	)


## Why `contract_id` cannot be dropped on each of `gates` now, in the words a
## Move to refusal uses: gate -> text, "" where it fits. Read-only.
static func refusals(sim: FlightSim, contract_id: String, gates: Array[String]) -> Dictionary:
	var out := {}
	for gate_id in gates:
		var problem := sim.reassign_problem(contract_id, gate_id)
		out[gate_id] = "" if problem == "" else DeparturesBoard.reason_text(sim, problem, gate_id)
	return out


func is_dragging() -> bool:
	return not _drag.is_empty()


## Hooks a new row up to the drag.
func watch(track: PlannerTrack) -> void:
	track.drag_hovered.connect(_on_hovered)
	track.dropped.connect(_on_dropped)


## Greys each row the dragged flight cannot go to and marks the home rows, or,
## with nothing dragged, clears every row. The planner runs it again after a
## rebuild mid-drag.
func show_rows() -> void:
	var refused := {}
	var homes: Array[String] = []
	if is_dragging():
		refused = refusals(flights, _drag["contract"], flights.gate_ids())
		homes = [_drag["gate"], flights.contract_of(_drag["contract"]).get("gate", "")]
	for track in tracks:
		track.clear_drag()
		if not is_dragging():
			continue
		track.home = homes.has(track.gate)
		if not track.home:
			track.refusal = refused.get(track.gate, "")


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var drag := PlannerBar.drag_of(get_viewport().gui_get_drag_data())
		if drag.is_empty() or sheet == null or not sheet.visible or flights == null:
			return
		_drag = drag
		_over = ""
		message.text = tr("Drop the flight on another gate's row.")
		show_rows()
	elif what == NOTIFICATION_DRAG_END and is_dragging():
		var landed := get_viewport().gui_is_drag_successful()
		var refusal := _refusal_of(_over)
		_drag = {}
		_over = ""
		show_rows()
		if not landed and refusal == "":
			message.text = ""


func _refusal_of(gate_id: String) -> String:
	for track in tracks:
		if track.gate == gate_id:
			return track.refusal
	return ""


func _on_hovered(track: PlannerTrack) -> void:
	if not is_dragging():
		return
	_over = track.gate
	var text := track.refusal
	if text == "":
		text = tr("Drop the flight on another gate's row.")
		if not track.home:
			var destination: String = flights.contract_of(_drag["contract"])["destination"]
			text = drop_text(destination, track.gate)
	if message.text != text:
		message.text = text


func _on_dropped(track: PlannerTrack, drag: Dictionary) -> void:
	on_drop.call(drag["contract"], track.gate)
