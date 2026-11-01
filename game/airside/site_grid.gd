class_name SiteGrid
extends BuildGrid
## The airport site's live build grid (BuildMode makes one when it has a
## site): a BuildGrid in the site's frame that knows its SiteDefinition, so
## ReferenceTerminal and StarterShell put the starter at its world place on
## it (SiteDefinition.starter_offset), and whose validate() first asks
## `guard` (ApronStand.edit_problem, decision plane-stand-design-airside-
## moves-110-m-north-stand-snaps-to, point 4) whether the edit builds where a
## plane at the stand still needs to go. Every way an edit reaches the grid (a
## click, an area drag, an undo, a template) goes through validate(), so one
## check covers them all. The trial copy BuildUndo checks an undo on is a
## SiteGrid carrying the same guard, so it refuses what the live grid would.
##
## Not guaranteed: the other trial copies (templates, repair plans) are plain
## BuildGrids without the guard.

var site: SiteDefinition
## Called as guard(grid, edit) before every validation; returns a refusal or
## null. Not set: nothing is guarded.
var guard := Callable()


func _init(on_site: SiteDefinition) -> void:
	super(on_site.grid_size, on_site.grid_origin)
	site = on_site


func validate(edit: BuildEdit, check_reach := true) -> BuildResult:
	if guard.is_valid():
		var problem: BuildResult = guard.call(self, edit)
		if problem != null:
			return problem
	return super(edit, check_reach)
