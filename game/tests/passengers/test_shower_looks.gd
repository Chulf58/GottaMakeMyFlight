class_name TestShowerLooks
extends GdUnitTestSuite
## How a showering passenger is drawn (ActivityPoses, ShowerFoam; decision
## activity-poses-sit-on-the-lounge-sofa-recline-in-the-nap-pod and the user's
## asks of 2026-10-31): the looping washing clip, its clothes and shoes off
## while the lather is fully up and back on after (and on release, pool reuse,
## a load and a removed shower), the lather moving within its bounds, and the
## steam that fills the cubicle with the lather. The world helpers are copies
## of TestActivityPoses' own.

## Ticks into a shower stay: washing bare under the full lather.
const MID_WASH := 70
## The most (metres) the lather's motion may take a bubble past where the
## still lather reaches.
const MOTION_MARGIN_M := 0.035

var _world: PassengerTestWorld
var _views: PassengerViews
var _ids: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	_free()


func _free() -> void:
	if _views != null:
		_views.free()
		_views = null
	if _world != null:
		_world.free_all()
		_world = null


func _open(type: StringName) -> void:
	var grid := BuildGrid.new()
	_ids = ActivityTestLayout.build(grid, type)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	_world.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]
	_world.run_to(10)
	_views = _make_views(_world)


func _make_views(world: PassengerTestWorld) -> PassengerViews:
	var views := PassengerViews.new()
	views.clock = world.clock
	views.sim = world.sim
	add_child(views)
	return views


## A bored guest that commits to the room's piece and has just reached it.
func _visitor(cell := ShopTestLayout.AIRSIDE_CELL) -> Passenger:
	var p := ShopTestLayout.airside_guest(_world, 80, cell)
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
	assert_object(_world.sim.shops.visit_of(p.id)).is_not_null()
	_run_to_browse(p)
	return p


func _run_to_browse(p: Passenger) -> void:
	while p.stage != Passenger.Stage.SHOP_BROWSE and _world.clock.tick < 3000:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_BROWSE)


func _clip(id: int) -> String:
	return _views.node_for(id).get_meta(&"clip", "")


func _save(world: PassengerTestWorld) -> String:
	return (
		JSON
		. stringify(
			{
				"clock": world.clock.to_snapshot(),
				"flights": world.flights.to_snapshot(),
				"grid": world.grid.to_snapshot(),
				"passengers": world.sim.to_snapshot(),
			}
		)
	)


## Loads a save back into the open world in place, as SaveGame does.
func _restore(text: String) -> void:
	var data: Dictionary = JSON.parse_string(text)
	assert_bool(_world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(_world.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(_world.sim.from_snapshot(data["passengers"])).is_true()


func _load(text: String) -> PassengerTestWorld:
	var data: Dictionary = JSON.parse_string(text)
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	assert_bool(world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(world.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(world.sim.from_snapshot(data["passengers"])).is_true()
	world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	world.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]
	return world


func test_the_shower_clip_loops_on_every_passenger_body_after_import() -> void:
	var looped := 0
	for body in PassengerLooks.BODIES.size():
		# A fresh load: PassengerViews sets loop modes on the cached clips too,
		# and this checks what the import itself wrote.
		var path := PassengerLooks.SCENES[body].resource_path
		var scene := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		var node := (scene as PackedScene).instantiate()
		var player := node.get_node("AnimationPlayer") as AnimationPlayer
		var wash := player.get_animation("shower")
		var once := player.get_animation("sit_down")
		print(
			(
				"%s: shower loop %d length %.2f s, sit_down loop %d"
				% [PassengerLooks.BODIES[body], wash.loop_mode, wash.length, once.loop_mode]
			)
		)
		if wash.loop_mode == Animation.LOOP_LINEAR:
			looped += 1
		assert_float(wash.length).is_equal_approx(5.0, 0.01)
		# Control: a one-shot clip stays one-shot, so the check can fail.
		assert_int(once.loop_mode).is_equal(Animation.LOOP_NONE)
		node.free()
	assert_int(looped).is_equal(PassengerLooks.BODIES.size())


func test_a_showering_passenger_washes_bare_and_dresses_again_on_step_out() -> void:
	_open(&"shower")
	var p := _visitor()
	# Bystanders on their way to the gate, at least one of the showering
	# passenger's own body, to show nobody else's look changes.
	var body := PassengerLooks.body_of(p.id, p.variant)
	var bystanders := 0
	while bystanders < 4 or _same_body_count(p.id, body) == 0:
		ShopTestLayout.airside_guest(_world, 0)
		bystanders += 1
		assert_int(bystanders).is_less(60)
	_world.step()
	var node := _views.node_for(p.id)
	assert_int(node.get_meta(&"body")).is_equal(body)
	var mi := PassengerLooks.body_mesh(node)
	var dressed := mi.mesh
	var dressed_materials := _materials(mi)
	var shared := PassengerLooks.plain_mesh(body).surface_get_material(0) as ShaderMaterial
	var shared_atlas: Texture2D = shared.get_shader_parameter("albedo_texture")
	# Still dressed while the lather builds up.
	_world.run_to(p.stage_tick + ActivityPoses.EASE_TICKS - 2)
	var building := [mi.mesh == dressed, node.has_meta(&"dressed"), _clip(p.id)]
	_world.run_to(p.stage_tick + MID_WASH)
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	var bare := mi.mesh
	var skin := _skin_report(body, bare)
	var others := _other_looks(p.id)
	print(
		(
			"building %s; washing clip %s (%s) bare %s skin %s; others %s"
			% [building, _clip(p.id), player.current_animation, bare != dressed, skin, others]
		)
	)
	assert_array(building).is_equal([true, false, "shower"])
	assert_str(_clip(p.id)).is_equal("shower")
	assert_str(player.current_animation).is_equal("shower")
	assert_object(bare).is_same(ActivityPoses.bare_mesh(body))
	# Every clothes and shoe vertex samples the body's own hand skin, on the
	# shared atlas material (no copy to leak).
	assert_int(skin["vertices"]).is_greater(100)
	assert_int(skin["off_skin"]).is_equal(0)
	assert_int(skin["clothes_left"]).is_equal(0)
	assert_bool(skin["warm"]).is_true()
	for i in bare.get_surface_count():
		assert_object(bare.surface_get_material(i)).is_same(shared)
	# No other drawn passenger changed its look; the shared atlas is as it was.
	assert_int(others["count"]).is_greater_equal(bystanders)
	assert_int(others["same_body"]).is_greater(0)
	assert_int(others["bare"]).is_equal(0)
	assert_int(others["own_look"]).is_equal(others["count"])
	assert_object(shared.get_shader_parameter("albedo_texture")).is_same(shared_atlas)
	# The rinse puts the clothes back on before the step out.
	while ActivityPoses.share(_world.sim, p) > 0.0 and _world.clock.tick < 3000:
		_world.step()
	print("stepped out at tick %d: clip %s" % [_world.clock.tick - p.stage_tick, _clip(p.id)])
	assert_object(mi.mesh).is_same(dressed)
	assert_array(_materials(mi)).is_equal(dressed_materials)
	assert_bool(node.has_meta(&"dressed")).is_false()
	assert_str(_clip(p.id)).is_not_equal("shower")


func test_a_passenger_released_mid_shower_goes_back_to_the_pool_dressed() -> void:
	_open(&"shower")
	var p := _visitor()
	_world.run_to(p.stage_tick + MID_WASH)
	var node := _views.node_for(p.id)
	var body: int = node.get_meta(&"body")
	var mi := PassengerLooks.body_mesh(node)
	var dressed: Mesh = node.get_meta(&"dressed")
	var bare := mi.mesh
	# Drawn no more (as on boarding): the node goes back to the pool.
	p.stage = Passenger.Stage.MADE
	_views.sync()
	var released := [_views.node_for(p.id) == null, mi.mesh == dressed, node.has_meta(&"dressed")]
	# The next passenger of that body takes the same node, in its own look.
	var next := Passenger.new()
	next.variant = p.variant
	next.id = p.id + 1
	while PassengerLooks.body_of(next.id, next.variant) != body:
		next.id += 1
	var taken := _views._take(next)
	var tint := PassengerLooks.tint_of(next.id)
	var look := (
		PassengerLooks.plain_mesh(body) if tint == 0 else PassengerLooks.split_mesh(body, tint)
	)
	print(
		(
			"released %s; reused by %d (tint %d): same node %s"
			% [released, next.id, tint, taken == node]
		)
	)
	assert_bool(bare == dressed).is_false()
	assert_array(released).is_equal([true, true, false])
	assert_object(node.get_node_or_null("ShowerFoam")).is_null()
	assert_object(taken).is_same(node)
	assert_object(PassengerLooks.body_mesh(taken).mesh).is_same(look)


func test_a_load_mid_shower_washes_bare_from_where_the_sim_is() -> void:
	_open(&"shower")
	var p := _visitor()
	_world.run_to(p.stage_tick + MID_WASH)
	var loaded := _load(_save(_world))
	var views := _make_views(loaded)
	views.snap()
	var node := views.node_for(p.id)
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	var want := fposmod((MID_WASH - ActivityPoses.SHUFFLE_TICKS) * SimClock.STEP, 5.0)
	var got := [player.current_animation, node.has_meta(&"dressed")]
	var at := player.current_animation_position
	print("loaded %d ticks in: %s at %.3f s, want %.3f s" % [MID_WASH, got, at, want])
	views.free()
	loaded.free_all()
	assert_array(got).is_equal(["shower", true])
	assert_float(at).is_equal_approx(want, 0.01)
	assert_float(at).is_greater(0.5)


func test_a_load_back_to_before_the_lather_puts_the_clothes_back_on() -> void:
	_open(&"shower")
	var p := _visitor()
	_world.run_to(p.stage_tick + 4)
	var saved := _save(_world)
	_world.run_to(p.stage_tick + MID_WASH)
	var node := _views.node_for(p.id)
	var was_bare := node.has_meta(&"dressed")
	# The same views, the clock gone back (ids survive a load).
	_restore(saved)
	_views.snap()
	var after := [node.has_meta(&"dressed"), _clip(p.id)]
	print("bare before the load %s; after %s" % [was_bare, after])
	assert_bool(was_bare).is_true()
	assert_bool(after[0]).is_false()
	assert_str(after[1]).is_not_equal("shower")


func test_the_lather_moves_within_its_envelope() -> void:
	var soap := ShowerFoam.soap()
	var code := soap.shader.code
	var worst := _lather_excess(ShowerFoam.DRIFT)
	# Control: a drift four times as far breaks the margin, so the check bites.
	var wild := _lather_excess(ShowerFoam.DRIFT * 4.0)
	print(
		(
			"lather: %d bubbles, motion reach %.4f m, worst excess %.4f m (control %.4f), margin %.3f"
			% [
				ShowerFoam.lather_count(),
				ShowerFoam.motion_reach_m(ShowerFoam.R_MAX),
				worst,
				wild,
				MOTION_MARGIN_M
			]
		)
	)
	# The bubbles move on their own (time and instance in the vertex shader),
	# with the swell and drift the bound is worked out from.
	assert_bool("TIME" in code and "INSTANCE_ID" in code).is_true()
	assert_float(soap.get_shader_parameter("swell")).is_equal(ShowerFoam.SWELL)
	assert_float(soap.get_shader_parameter("drift")).is_equal(ShowerFoam.DRIFT)
	assert_float(ShowerFoam.motion_reach_m(ShowerFoam.R_MAX)).is_greater(0.005)
	assert_float(worst).is_less_equal(MOTION_MARGIN_M)
	assert_float(wild).is_greater(MOTION_MARGIN_M)
	# The lather is not culled while the shader moves bubbles past its bounds.
	var foam := ShowerFoam.new()
	var margin := foam.get_node("Lather") as GeometryInstance3D
	print("cull margin %.4f m" % margin.extra_cull_margin)
	# (The margin is stored as a 32-bit float.)
	assert_float(margin.extra_cull_margin).is_greater_equal(
		ShowerFoam.motion_reach_m(ShowerFoam.R_MAX) - 1e-6
	)
	foam.free()


func test_steam_fills_the_cubicle_with_the_lather_and_clears_with_the_rinse() -> void:
	_open(&"shower")
	var p := _visitor()
	_world.run_to(p.stage_tick + 4)
	var node := _views.node_for(p.id)
	var foam := node.get_node("ShowerFoam") as ShowerFoam
	var building := [foam.amount, foam.haze_shown()]
	_world.run_to(p.stage_tick + MID_WASH)
	var full := [foam.amount, foam.haze_shown()]
	var haze := foam.get_node("Haze") as MeshInstance3D
	# Every foam draws the one shared box and material.
	var other := ShowerFoam.new()
	var shared: bool = (other.get_node("Haze") as MeshInstance3D).mesh == haze.mesh
	other.free()
	# The box stands inside the cubicle's glass.
	var cubicle := _piece_box("shower_cubicle")
	var box := ShowerFoam.haze_box().size
	# Into the rinse.
	while foam.amount >= 1.0 and _world.clock.tick < 3000:
		_world.step()
	_world.step()
	var rinsing := [foam.amount, foam.haze_shown()]
	print(
		(
			"steam building %s, full %s, rinsing %s; box %s in cubicle %s; shared %s"
			% [building, full, rinsing, box, cubicle.size, shared]
		)
	)
	assert_float(building[1]).is_equal(building[0])
	assert_float(building[1]).is_less(1.0)
	assert_array(full).is_equal([1.0, 1.0])
	assert_float(rinsing[1]).is_equal(rinsing[0])
	assert_float(rinsing[1]).is_less(1.0)
	assert_bool(shared).is_true()
	assert_object(haze.mesh).is_same(ShowerFoam.haze_box())
	assert_float(box.x).is_less(cubicle.size.x - 0.05)
	assert_float(box.z).is_less(cubicle.size.z - 0.05)
	# ...and under its top, on the tray: no steam edge shows above the glass.
	var top := ActivityPoses.SHOWER_TRAY_M + ShowerFoam.HAZE_FLOOR_M + box.y
	print("steam top %.2f m, cubicle top %.2f m" % [top, cubicle.end.y])
	assert_float(top).is_less_equal(cubicle.end.y)
	while _world.sim.shops.visit_of(p.id) != null and _world.clock.tick < 3000:
		_world.step()
	assert_object(node.get_node_or_null("ShowerFoam")).is_null()


func test_every_body_takes_off_all_its_clothes_and_shoes_in_the_shower() -> void:
	var report := []
	# Control: shoe triangles whose first corner is above the line but another
	# is below, which a first-corner rule (ed5cd31) left on the body.
	var straddling := 0
	for body in PassengerLooks.BODIES.size():
		var bare := ActivityPoses.bare_mesh(body)
		var kept := bare.surface_get_arrays(0)
		var index: PackedInt32Array = kept[Mesh.ARRAY_INDEX]
		var verts: PackedVector3Array = kept[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = kept[Mesh.ARRAY_COLOR]
		var low := 0
		var cloth := 0
		for t in range(0, index.size(), 3):
			var lowest := minf(
				verts[index[t]].y, minf(verts[index[t + 1]].y, verts[index[t + 2]].y)
			)
			if lowest < ActivityPoses.FEET_M:
				low += 1
			for k in 3:
				if colors[index[t + k]].r > 0.5:
					cloth += 1
					break
		var skin := _skin_report(body, bare)
		straddling += _straddling(body)
		report.append([PassengerLooks.BODIES[body], low, cloth, skin["off_skin"], skin["skin"]])
		assert_int(low).is_equal(0)
		assert_int(cloth).is_equal(0)
		assert_int(skin["off_skin"]).is_equal(0)
		assert_bool(skin["warm"]).is_true()
	print("bodies [name, low tris kept, cloth tris kept, off-skin verts, skin]: %s" % [report])
	print("shoe triangles a first-corner rule would keep: %d" % straddling)
	assert_int(straddling).is_greater(0)


func test_a_load_where_a_showering_id_has_another_body_draws_that_body() -> void:
	_open(&"shower")
	var p := _visitor()
	var id := p.id
	_world.run_to(p.stage_tick + MID_WASH)
	var old := _views.node_for(id)
	var old_mi := PassengerLooks.body_mesh(old)
	var old_dressed: Mesh = old.get_meta(&"dressed")
	var data: Dictionary = JSON.parse_string(_save(_world))
	var flipped := 1 - p.variant
	for record: Dictionary in data["passengers"]["passengers"]:
		if int(record["id"]) == id:
			record["variant"] = flipped
	_restore(JSON.stringify(data))
	_views.snap()
	var body := PassengerLooks.body_of(id, flipped)
	var node := _views.node_for(id)
	var mi := PassengerLooks.body_mesh(node)
	var after := [node.get_meta(&"body"), mi.mesh == ActivityPoses.bare_mesh(body), _clip(id)]
	var old_back := [old_mi.mesh == old_dressed, old.has_meta(&"dressed"), old == node]
	var q := _world.sim.get_passenger(id)
	while ActivityPoses.share(_world.sim, q) > 0.0 and _world.clock.tick < 3000:
		_world.step()
	var tint := PassengerLooks.tint_of(id)
	var look := (
		PassengerLooks.plain_mesh(body) if tint == 0 else PassengerLooks.split_mesh(body, tint)
	)
	print(
		(
			"body %d -> %d: drawn %s; old node dressed again %s; dressed after rinse %s"
			% [old.get_meta(&"body"), body, after, old_back, mi.mesh == look]
		)
	)
	assert_int(body).is_not_equal(old.get_meta(&"body"))
	assert_array(after).is_equal([body, true, "shower"])
	assert_array(old_back).is_equal([true, false, false])
	assert_object(mi.mesh).is_same(look)


func test_a_shower_removed_mid_wash_puts_the_clothes_back_on() -> void:
	_open(&"shower")
	var p := _visitor()
	_world.run_to(p.stage_tick + MID_WASH)
	var node := _views.node_for(p.id)
	var mi := PassengerLooks.body_mesh(node)
	var dressed: Mesh = node.get_meta(&"dressed")
	assert_bool(_world.grid.apply(BuildEdit.remove_object(_ids["use"])).ok).is_true()
	_world.step()
	var after := [node.has_meta(&"dressed"), mi.mesh == dressed, _clip(p.id)]
	print("shower removed mid-wash: [bare, dressed mesh, clip] %s" % [after])
	assert_bool(after[0]).is_false()
	assert_bool(after[1]).is_true()
	assert_str(after[2]).is_not_equal("shower")
	assert_object(node.get_node_or_null("ShowerFoam")).is_null()


## Triangles of body `body`'s imported mesh outside its clothes whose first
## corner is at or above FEET_M and another below it.
func _straddling(body: int) -> int:
	var arrays := PassengerLooks.plain_mesh(body).surface_get_arrays(0)
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var count := 0
	for t in range(0, index.size(), 3):
		if colors[index[t]].r > 0.5 or verts[index[t]].y < ActivityPoses.FEET_M:
			continue
		if minf(verts[index[t + 1]].y, verts[index[t + 2]].y) < ActivityPoses.FEET_M:
			count += 1
	return count


## The bounding box of every mesh of an interior piece's .glb, in its frame.
func _piece_box(piece: String) -> AABB:
	var scene := (load("res://assets/interior/%s.glb" % piece) as PackedScene).instantiate()
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var xf := mi.transform
		var parent := mi.get_parent()
		while parent != null and parent != scene:
			xf = (parent as Node3D).transform * xf
			parent = parent.get_parent()
		var part := xf * mi.get_aabb()
		box = part if first else box.merge(part)
		first = false
	scene.free()
	return box


## The most any bubble's surface, moving with drift `drift`, gets past the
## still lather's reach (R_MAX * (1 + OUT) out of its body envelope).
func _lather_excess(drift: float) -> float:
	var worst := -INF
	for b in ShowerFoam.bubbles():
		var reach := b.w * (1.0 + ShowerFoam.SWELL + drift * sqrt(1.25))
		var out := INF
		for part: Array in ShowerFoam.PARTS:
			if b.y < part[2] - 0.001 or b.y > part[3] + 0.001:
				continue
			var at := Vector2(b.x - part[0], b.z - part[1])
			out = minf(out, _ellipse_out(at, part[4], part[5]))
		worst = maxf(worst, out + reach - ShowerFoam.R_MAX * (1.0 + ShowerFoam.OUT))
	return worst


## How far point `at` lies outside the ellipse of half axes `rx`, `rz`
## (negative inside), by the nearest of 720 points round it.
func _ellipse_out(at: Vector2, rx: float, rz: float) -> float:
	var near := INF
	for i in 720:
		var turn := i * TAU / 720.0
		near = minf(near, at.distance_to(Vector2(cos(turn) * rx, sin(turn) * rz)))
	var inside := pow(at.x / rx, 2.0) + pow(at.y / rz, 2.0) < 1.0
	return -near if inside else near


func _materials(mi: MeshInstance3D) -> Array:
	var out := []
	for i in mi.mesh.get_surface_count():
		out.append(mi.get_active_material(i))
	return out


func _surface_materials(mesh: Mesh) -> Array:
	var out := []
	for i in mesh.get_surface_count():
		out.append(mesh.surface_get_material(i))
	return out


## How bare mesh `bare` of body `body` draws: its clothes surface's vertex
## count, how many of them sample anything but the body's skin texel, how
## many clothes triangles are left on the other surface, and whether the skin
## is a warm tone.
func _skin_report(body: int, bare: Mesh) -> Dictionary:
	var atlas := ActivityPoses.atlas_image(bare)
	var skin := ActivityPoses.atlas_colour(atlas, ActivityPoses.skin_uv(body))
	var arrays := bare.surface_get_arrays(1)
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var off := 0
	for i in index:
		if ActivityPoses.atlas_colour(atlas, uvs[i]) != skin:
			off += 1
	var kept := bare.surface_get_arrays(0)
	var colors: PackedColorArray = kept[Mesh.ARRAY_COLOR]
	var left: PackedInt32Array = PassengerLooks.cloth_split(kept[Mesh.ARRAY_INDEX], colors)[1]
	return {
		"vertices": index.size(),
		"off_skin": off,
		"clothes_left": left.size() / 3,
		"warm": skin.r > skin.g and skin.g > skin.b,
		"skin": skin.to_html(false),
	}


## Passengers in the sim other than `id` drawn with body `body`.
func _same_body_count(id: int, body: int) -> int:
	var count := 0
	for other in _world.sim.passenger_ids():
		var p := _world.sim.get_passenger(other)
		if other != id and PassengerLooks.body_of(other, p.variant) == body:
			count += 1
	return count


## Every other drawn passenger: how many, how many of them have the body of
## `id`, how many draw a bare mesh, and how many draw exactly their own look
## (PassengerLooks) with its materials.
func _other_looks(id: int) -> Dictionary:
	var body_of_id: int = _views.node_for(id).get_meta(&"body")
	var out := {"count": 0, "same_body": 0, "bare": 0, "own_look": 0}
	for other: int in _views._nodes:
		if other == id:
			continue
		var p := _world.sim.get_passenger(other)
		var body := PassengerLooks.body_of(other, p.variant)
		var tint := PassengerLooks.tint_of(other)
		var mi := PassengerLooks.body_mesh(_views.node_for(other))
		var look := (
			PassengerLooks.plain_mesh(body) if tint == 0 else PassengerLooks.split_mesh(body, tint)
		)
		out["count"] += 1
		if body == body_of_id:
			out["same_body"] += 1
		if mi.mesh == ActivityPoses.bare_mesh(body):
			out["bare"] += 1
		if mi.mesh == look and _materials(mi) == _surface_materials(look):
			out["own_look"] += 1
	return out
