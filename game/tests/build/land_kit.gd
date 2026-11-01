class_name LandKit
extends RefCounted
## Test helpers for the site's land plots (LandPlots).


## Makes `land` own every plot of the site, bought count unchanged, so a test
## about something else can build anywhere on the site's grid.
static func own_all(land: LandPlots) -> void:
	var owned := []
	for y in land.plots.y:
		for x in land.plots.x:
			owned.append([x, y])
	var loaded := land.from_snapshot(
		{"plot_size": land.plot_size, "owned": owned, "bought": land.bought}
	)
	assert(loaded, "LandKit.own_all: the land refused its own snapshot")


## The number of plots `land` owns.
static func owned_count(land: LandPlots) -> int:
	return land.owned_plots().size()
