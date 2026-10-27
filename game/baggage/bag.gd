class_name Bag
extends RefCounted
## One checked bag as plain data (decision baggage-bag-sim-design-route-field-
## belt-capacity-cutoff). BaggageSim owns and moves it.
##
## A bag on a belt owns one cell, `cell`. It came in from the cell
## `cell - from_step` and still has `remain_mm` to go to the centre of `cell`;
## at the centre (remain_mm 0) it picks its next edge from the route field.
## While remain_mm is more than half a cell its body is still on the cell it
## came from (physical_cell()), so that cell is taken too. An IN_ROOM bag
## keeps the belt end it reached in `cell`; an AT_DESK bag has no cell.
## `passenger` and `desk` are historical: the passenger may be retired and
## the desk demolished while the bag still exists.

enum State { AT_DESK, RIDING, BLOCKED, IN_ROOM, LOADED, MISSED }
enum Cause { NONE, LATE, NO_BELT, NO_ROUTE, LOST }

## Distance between two cell centres, in mm.
const CELL_MM := 1000
## Names of the causes in BaggageSim.results and in saves.
const CAUSE_NAMES: Array[String] = ["none", "late", "no_belt", "no_route", "lost"]

var id := 0
var passenger := 0
var flight := ""
var desk := 0
var state := State.AT_DESK
var cause := Cause.NONE
var cell := Vector2i.ZERO
var from_step := Vector2i.ZERO
var remain_mm := 0
## The tick it began waiting for its next cell: its check-in tick at a desk,
## the tick it reached a cell centre on a belt. Merges go to the earliest,
## then the lower id.
var wait_tick := 0
var created_tick := 0
## The last tick on which reaching a bag room still loads it.
var cutoff_tick := 0
var rest_tick := -1
var outcome_tick := -1


func is_settled() -> bool:
	return state == State.LOADED or state == State.MISSED


func on_belt() -> bool:
	return state == State.RIDING or state == State.BLOCKED


## The cell the bag's body is on: the one it came from while it is in the
## first half of its edge, else its own cell.
func physical_cell() -> Vector2i:
	if remain_mm * 2 > CELL_MM:
		return cell - from_step
	return cell
