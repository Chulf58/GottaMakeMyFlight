class_name StarterShell
extends RefCounted
## The player-owned terminal shell a new game starts with (decision terminal-
## growth-and-starter-building-move-the-airside-north, point 2): floor, outer
## walls, one entrance and one exit on ReferenceTerminal's 12x16 footprint, no
## desks. BuildMode places it once, when it enters the tree for a new game;
## a load replaces the whole grid (BuildMode.load_snapshot), so a loaded game
## never gets a second shell. The player owns it: it costs nothing, but every
## piece is saved at its list price (BuildEdit.paid), so demolishing one
## refunds PriceTable.REFUND_SHARE_PERCENT of it like any piece
## (BuildTransaction). The roof is generated from the walls (RoofView).


## What the shell's pieces cost together, in the order PriceTable lists them.
static func price() -> int:
	var total := 0
	for edit in ReferenceTerminal.shell_edits():
		total += _price_of(edit)
	return total


## Places the shell on `grid`, every piece saved at its price and no wallet
## touched. Pushes an error and returns false when an edit is refused; the
## edits before it stay on the grid.
static func place(grid: BuildGrid) -> bool:
	var edits := ReferenceTerminal.shell_edits()
	for edit in edits:
		edit.paid = _price_of(edit)
	var result := grid.apply_sequence(edits, Callable())
	if not result.ok:
		push_error("StarterShell: a piece was refused: %s" % result.reason_text())
	return result.ok


static func _price_of(edit: BuildEdit) -> int:
	match edit.kind:
		BuildEdit.Kind.PAINT_FLOOR:
			return PriceTable.price_of_floor()
		BuildEdit.Kind.PLACE_WALL:
			return PriceTable.price_of_wall(edit.wall_kind)
		BuildEdit.Kind.PLACE_OBJECT:
			return PriceTable.price_of_object(edit.def_id)
	return 0
