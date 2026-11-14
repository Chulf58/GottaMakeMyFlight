class_name BottomDocks
extends RefCounted
## Where the Templates dock and the Debug toggle stand (decision hud-grid-and-
## rails-one-spacing-grid-centred-top-row-right-ra, part 4: Templates beside the
## bar). The bar is centred and takes its whole width at UI scale 1.5 (a 1280
## layout), so there they would cover its first and last buttons. When the room
## either side of the bar is narrower than the wider dock plus a group gap, the
## docks lift one bar height up, onto the row above the bar, on the same margin.

## The wider of the two docks: the Templates dock (a 104 px button in its card).
const DOCK_W := 112.0


## Whether the docks stand beside a bar `bar_width` wide in a layer `layer_width` wide.
static func beside_bar(layer_width: float, bar_width: float) -> bool:
	var side := (layer_width - bar_width) / 2.0
	return side >= float(HudLayout.MARGIN + HudLayout.GROUP_GAP) + DOCK_W


## How far up from the screen's bottom edge a dock's bottom edge is.
static func bottom(beside: bool) -> float:
	var base := float(HudLayout.MARGIN)
	return base if beside else base + HudLayout.BAR_H + HudLayout.GAP
