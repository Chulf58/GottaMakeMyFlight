extends SceneTree
## Times the site-grid work that grows with the grid's width, on today's
## 86x150 site and on the 256x150 wide frame (board a91c3969): RepairPlan's
## whole-grid retry (decision cae408b1 put it at about 3 s), RepairPlan.make()
## as a new game runs it, BuildGrid.clone() (about 0.2 ms) and SpareStand.find().
## Each grid is a SiteGrid with the starter shell built and a new game's land.
## Run: Godot --headless --audio-driver Dummy --path game -s res://spike/wide_site_timing_probe.gd

const SITE := preload("res://build/terminal_site.tres")
const CLONES := 50
const FINDS := 20


func _initialize() -> void:
	print("wide frame: %s at %s" % [SITE.grid_size, SITE.grid_origin])
	_measure(_today(), "today 86x150")
	_measure(SITE, "wide %dx%d" % [SITE.grid_size.x, SITE.grid_size.y])
	quit(0)


## Today's site: the wide frame's middle 86 columns.
func _today() -> SiteDefinition:
	var site: SiteDefinition = SITE.duplicate()
	var centre := SITE.centre_rect()
	var west := int(centre.position.x - SITE.grid_origin.x)
	site.grid_origin = Vector3(centre.position.x, SITE.grid_origin.y, SITE.grid_origin.z)
	site.grid_size = Vector2i(int(centre.size.x), SITE.grid_size.y)
	site.starter_offset = SITE.starter_offset - Vector2i(west, 0)
	site.plot_columns = SITE.plot_columns.slice(
		SITE.centre_columns.x, SITE.centre_columns.x + SITE.centre_columns.y
	)
	site.centre_columns = Vector2i(0, SITE.centre_columns.y)
	var obstacles: Array[Vector2i] = []
	for cell in SITE.obstacles:
		obstacles.append(cell - Vector2i(west, 0))
	site.obstacles = obstacles
	return site


func _measure(site: SiteDefinition, label: String) -> void:
	var grid := SiteGrid.new(site)
	grid.land = LandPlots.for_site(site)
	grid.land.own_start(site)
	if not StarterShell.place(grid, site.starter_offset):
		print("PROBE_INVALID: the starter shell was refused on %s" % label)
		quit(1)
		return
	var whole := Rect2i(Vector2i.ZERO, grid.size)
	var started := Time.get_ticks_usec()
	var on_whole := RepairPlan._made_on(grid, whole, site, {}, grid.land)
	var whole_ms := (Time.get_ticks_usec() - started) / 1000.0
	var empty := SiteGrid.new(site)
	empty.land = grid.land
	started = Time.get_ticks_usec()
	var empty_whole := RepairPlan._made_on(empty, whole, site, {}, empty.land)
	var empty_whole_ms := (Time.get_ticks_usec() - started) / 1000.0
	# Late game: every plot bought, so the search may use the whole grid.
	var all_land := LandPlots.for_site(site)
	all_land._owned.fill(1)
	var bought_out := SiteGrid.new(site)
	bought_out.land = all_land
	started = Time.get_ticks_usec()
	var all_whole := RepairPlan._made_on(bought_out, whole, site, {}, all_land)
	var all_whole_ms := (Time.get_ticks_usec() - started) / 1000.0
	var all_line := "%s: whole-grid retry (every plot owned) %.0f ms ok %s"
	print(all_line % [label, all_whole_ms, all_whole.ok])
	started = Time.get_ticks_usec()
	var made := RepairPlan.make(empty, site)
	var make_ms := (Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	for i in CLONES:
		grid.clone()
	var clone_ms := (Time.get_ticks_usec() - started) / 1000.0 / CLONES
	var stands: Array[Dictionary] = [StandPlacement.starter_stand(grid, site)]
	var spare := {}
	started = Time.get_ticks_usec()
	for i in FINDS:
		spare = SpareStand.find(grid, stands, PlaneClasses.SMALL)
	var find_ms := (Time.get_ticks_usec() - started) / 1000.0 / FINDS
	print(
		(
			(
				"%s: whole-grid retry (starter built) %.0f ms ok %s, whole-grid retry (empty"
				+ " site) %.0f ms ok %s, make (empty site, cropped) %.0f ms ok %s, clone"
				+ " %.3f ms, SpareStand.find %.3f ms found %s"
			)
			% [
				label,
				whole_ms,
				on_whole.ok,
				empty_whole_ms,
				empty_whole.ok,
				make_ms,
				made.ok,
				clone_ms,
				find_ms,
				not spare.is_empty()
			]
		)
	)
