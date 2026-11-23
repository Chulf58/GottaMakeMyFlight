class_name ServiceDef
extends RefCounted
## Shared behavior definition for a terminal service, whether provided by a
## furnished room (RoomTypes.RoomType) or a standalone corridor piece
## (ServiceTypes).

var id: StringName = &""
var piece_id: StringName = &""
var display_name := ""
## The piece that seats guests or holds browse/use slots.
var seat_piece: StringName = &""
var seats_per_piece := 0
## Whether passengers visit through ShopSim.
var shop := false
## What one visit spends or charges before mood and the airside bonus.
var base_spend := 0
## Whether a finished visit resets boredom (ShopSim).
var relieves_boredom := true
## Whether passengers eat and drink here through CafeSim.
var food := false
## Counter pieces accepted (for food services) and table pieces (empty for
## walk-on services).
var counter_pieces: Array[StringName] = []
var table_pieces: Array[StringName] = []
## Whether guests pay at the counter and walk on with no seat or dwell.
var walk_on := false
## Whether this is an activity or rest service on the shop pipeline.
var activity := false
## Ticks to order at the counter (food) and ticks a served guest stays.
var order_ticks := 0
var dwell_ticks := 0
## Mood gained on completing the visit.
var mood_bonus := 0
## Whether standalone operation requires a SHOP server on duty.
var needs_staff := false


## The ticks one visit takes at the counter and table (queue and walk excluded).
func visit_ticks() -> int:
	return order_ticks + dwell_ticks
