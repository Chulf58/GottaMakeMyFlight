class_name RotateHint
extends RefCounted
## The "R rotate" hint on the build status card (decision
## no-rotate-card-in-build-trays, "Hint while placing"). The trays hold no Rotate
## card, so while a piece or a pasted template that can turn is under the cursor
## the card shows TEXT in its own label beside the status text (BuildMenu, HUD
## 5/7), which keeps it from wrapping.

## The English msgid: a test compares against it; the label is text(), which says
## tr() of the literal.
const TEXT := "R rotate"


## The hint in the player's language. tr() is an instance method, so a static
## function asks a RotateHint.
static func text() -> String:
	return RotateHint.new().label()


func label() -> String:
	return tr("R rotate")


## True while the tool places a catalog piece, a template paste is armed or a
## room is in hand (RoomMoveTool).
static func applies(mode: BuildMode) -> bool:
	if mode == null:
		return false
	return (
		BuildMode.tool_object(mode.tool) != &""
		or mode.tool == BuildMode.Tool.SECURITY_LANE
		or mode.templates.active_template() != null
		or mode.room_mover.active
		or mode.object_mover.active
		or (mode.starter_kit != null and mode.starter_kit.is_active())
	)
