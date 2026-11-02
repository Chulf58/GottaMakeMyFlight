class_name RotateHint
extends RefCounted
## The "R rotate" hint at the end of the build status line (decision
## no-rotate-card-in-build-trays, "Hint while placing"). The trays hold no Rotate
## card, so while a piece or a pasted template that can turn is under the cursor
## the line ends with it, after whatever the line already shows.

const TEXT := "R rotate"


## True while the tool places a catalog piece, or a template paste is armed.
static func applies(mode: BuildMode) -> bool:
	if mode == null:
		return false
	return BuildMode.tool_object(mode.tool) != &"" or mode.templates.armed >= 0


## `text` with the hint added when it applies.
static func compose(text: String, mode: BuildMode) -> String:
	if not applies(mode):
		return text
	return TEXT if text == "" else "%s  %s" % [text, TEXT]
