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
		{"plot_counts": [land.plots.x, land.plots.y], "owned": owned, "bought": land.bought}
	)
	assert(loaded, "LandKit.own_all: the land refused its own snapshot")


## The number of plots `land` owns.
static func owned_count(land: LandPlots) -> int:
	return land.owned_plots().size()


## Buys, for free, the plots that join `target` to the land `land` owns, nearest
## to `target` first, so the land stays a state a save accepts (`bought` counts
## the plots beyond the start land). For a test that saves after building off
## a new game's land; own_all() would break a save's `bought` check.
static func buy_to(land: LandPlots, target: Vector2i) -> void:
	while not land.is_owned(target):
		var best := Vector2i(-1, -1)
		var best_distance := 1 << 30
		for plot in land.buyable_plots():
			var distance := absi(plot.x - target.x) + absi(plot.y - target.y)
			if distance < best_distance:
				best = plot
				best_distance = distance
		assert(best != Vector2i(-1, -1), "LandKit.buy_to: no plot to buy toward %s" % target)
		var result := land.buy(best, null)
		assert(result.ok, "LandKit.buy_to: the land refused a free plot: %s" % result.reason_text())
