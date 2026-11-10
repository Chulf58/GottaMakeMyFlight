class_name RotateHint
extends RefCounted
## The "R rotate" hint on the build status card (decision
## no-rotate-card-in-build-trays, "Hint while placing"). The trays hold no Rotate
## card, so while a piece or a pasted template that can turn is under the cursor
## the card shows TEXT in its own label beside the status text (BuildMenu, HUD
## 5/7), which keeps it from wrapping.

const TEXT := "R rotate"


## True while the tool places a catalog piece, a template paste is armed or a
## room is in hand (RoomMoveTool).
static func applies(mode: BuildMode) -> bool:
	if mode == null:
		return false
	return (
		BuildMode.tool_object(mode.tool) != &""
		or mode.templates.armed >= 0
		or mode.room_mover.active
	)
