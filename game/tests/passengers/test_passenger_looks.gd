class_name TestPassengerLooks
extends GdUnitTestSuite
## Passenger looks (PassengerLooks): the body, clothing tint and bag colour come
## from the variant and the id alone, neighbours in spawn order differ, a tint
## recolours the clothes and nothing else, and PassengerViews draws each
## passenger with its own body and tint.


func test_a_body_stays_within_its_variant_and_every_body_is_drawn() -> void:
	var seen := {}
	for variant in 2:
		for id in range(1, 61):
			var body := PassengerLooks.body_of(id, variant)
			assert_int(body / PassengerLooks.PER_VARIANT).is_equal(variant)
			seen[body] = true
	print("bodies seen: %s" % [seen.keys()])
	assert_int(seen.size()).is_equal(PassengerLooks.BODIES.size())


func test_the_look_is_the_same_for_the_same_id() -> void:
	for id in [1, 7, 42, 1000]:
		assert_int(PassengerLooks.body_of(id, 1)).is_equal(PassengerLooks.body_of(id, 1))
		assert_int(PassengerLooks.tint_of(id)).is_equal(PassengerLooks.tint_of(id))
		assert_int(PassengerLooks.bag_of(id)).is_equal(PassengerLooks.bag_of(id))


## Within a block of ids every body, tint and bag colour comes once, so no two
## passengers spawned in one block look alike; across a block edge the pair
## of neighbours may share one of them but rarely all three.
func test_neighbours_in_spawn_order_differ() -> void:
	var same_look := 0
	for block in 50:
		var bodies := {}
		var tints := {}
		var bags := {}
		for k in PassengerLooks.LOOK_BLOCK:
			var id := block * PassengerLooks.LOOK_BLOCK + k
			bodies[PassengerLooks.body_of(id, 0)] = true
			tints[PassengerLooks.tint_of(id)] = true
			bags[PassengerLooks.bag_of(id)] = true
		assert_int(bodies.size()).is_equal(PassengerLooks.LOOK_BLOCK)
		assert_int(tints.size()).is_equal(PassengerLooks.TINTS.size())
		assert_int(bags.size()).is_equal(PassengerLooks.BAG_TINTS.size())
	for id in range(1, 301):
		if (
			PassengerLooks.body_of(id, 0) == PassengerLooks.body_of(id + 1, 0)
			and PassengerLooks.tint_of(id) == PassengerLooks.tint_of(id + 1)
		):
			same_look += 1
	print("neighbour pairs with the same body and tint in 300: %d" % same_look)
	assert_int(same_look).is_less(5)


func test_cloth_split_follows_the_clothes_mark() -> void:
	var index := PackedInt32Array([0, 1, 2, 3, 4, 5, 0, 2, 5])
	var colors := PackedColorArray(
		[Color.BLACK, Color.BLACK, Color.BLACK, Color.WHITE, Color.WHITE, Color.WHITE]
	)
	var parts := PassengerLooks.cloth_split(index, colors)
	assert_array(Array(parts[0])).is_equal([0, 1, 2, 0, 2, 5])
	assert_array(Array(parts[1])).is_equal([3, 4, 5])


func test_a_tint_turns_hues_and_colours_greys() -> void:
	var red := Color.from_hsv(0.0, 0.8, 0.6)
	var grey := Color(0.5, 0.5, 0.5)
	assert_that(PassengerLooks.tinted(red, 0.0, -1.0)).is_equal(red)
	var turned := PassengerLooks.tinted(red, 0.5, 0.6, true)
	print(
		"red %s -> %s, grey %s -> %s" % [red, turned, grey, PassengerLooks.tinted(grey, 0.5, 0.6)]
	)
	# A saturated swatch turns by SATURATED_SCALE of the turn and is toned down to
	# SAT_CAP (no neon); a muted one takes the full turn.
	var moved := minf(turned.h, 1.0 - turned.h)
	assert_float(moved).is_equal_approx(0.5 * PassengerLooks.SATURATED_SCALE, 0.01)
	assert_float(turned.s).is_equal_approx(PassengerLooks.SAT_CAP, 0.01)
	assert_float(turned.v).is_equal_approx(0.6, 0.01)
	var muted := PassengerLooks.tinted(Color.from_hsv(0.0, 0.4, 0.6), 0.33, 0.3)
	assert_float(muted.h).is_equal_approx(0.33, 0.01)
	assert_float(muted.s).is_equal_approx(0.4, 0.01)
	var most := 0.0
	for tint in range(1, PassengerLooks.TINTS.size()):
		for k in 20:
			var c := Color.from_hsv(k / 20.0, 1.0, 0.9)
			var t: Array = PassengerLooks.TINTS[tint]
			most = maxf(most, PassengerLooks.tinted(c, t[0], t[1]).s)
	print("most saturated tinted swatch: %.3f" % most)
	assert_float(most).is_less_equal(PassengerLooks.SAT_CAP + 0.01)
	var coloured := PassengerLooks.tinted(grey, 0.5, 0.6)
	assert_float(coloured.h).is_equal_approx(0.6, 0.01)
	assert_float(coloured.s).is_equal_approx(PassengerLooks.GREY_SAT, 0.01)
	assert_float(coloured.v).is_equal_approx(0.5, 0.01)


## Every body carries the clothes' mark, and a tinted body draws the clothes on
## a recoloured atlas and everything else on the shared one: a texel under a
## clothes triangle changed, a texel under a face (skin) triangle did not.
func test_a_tint_recolours_the_clothes_and_keeps_the_skin() -> void:
	for body in PassengerLooks.BODIES.size():
		var plain := PassengerLooks.plain_mesh(body)
		var split := PassengerLooks.split_mesh(body, 1)
		assert_int(split.get_surface_count()).is_equal(2)
		var whole: int = (plain.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		var other: int = (split.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		var cloth: int = (split.surface_get_arrays(1)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		print(
			(
				"%s: triangles %d = other %d + clothes %d"
				% [PassengerLooks.BODIES[body], whole / 3, other / 3, cloth / 3]
			)
		)
		assert_int(cloth).is_greater(0)
		assert_int(other).is_greater(0)
		assert_int(other + cloth).is_equal(whole)
		assert_object(split.surface_get_material(0)).is_same(plain.surface_get_material(0))
	var shared := PassengerLooks.plain_mesh(0).surface_get_material(0) as ShaderMaterial
	var base: Texture2D = shared.get_shader_parameter("albedo_texture")
	var tinted: Texture2D = PassengerLooks.material(1).get_shader_parameter("albedo_texture")
	assert_object(tinted).is_not_same(base)
	var before := base.get_image()
	before.decompress()
	var after := tinted.get_image()
	var arrays := PassengerLooks.plain_mesh(0).surface_get_arrays(0)
	var parts := PassengerLooks.cloth_split(arrays[Mesh.ARRAY_INDEX], arrays[Mesh.ARRAY_COLOR])
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var size := Vector2(before.get_width(), before.get_height())
	var changed := 0
	for t in range(0, (parts[1] as PackedInt32Array).size(), 3):
		var at := Vector2i(uvs[parts[1][t]] * size)
		if not before.get_pixelv(at).is_equal_approx(after.get_pixelv(at)):
			changed += 1
	var kept := 0
	var cloth_texels := PassengerLooks.cloth_texels(before.get_width(), before.get_height())
	var clothes := {}
	for t in cloth_texels:
		clothes[t] = true
	for t in range(0, (parts[0] as PackedInt32Array).size(), 3):
		var at := Vector2i(uvs[parts[0][t]] * size)
		if not clothes.has(at.y * before.get_width() + at.x):
			kept += int(before.get_pixelv(at).is_equal_approx(after.get_pixelv(at)))
	print(
		(
			"male_01 tint 1: clothes corners changed %d, other corners off the clothes kept %d"
			% [changed, kept]
		)
	)
	assert_int(changed).is_greater(0)
	assert_int(kept).is_greater(0)


func test_views_draw_each_passenger_with_its_body_and_tint() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(5, 1), 0)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(30, 40))
	var views := PassengerViews.new()
	views.clock = world.clock
	views.sim = world.sim
	add_child(views)
	var tinted := 0
	for n in 12:
		world.sim.spawn_now(PassengerTestWorld.FLIGHT, n % 2)
	world.step()
	for id in world.sim.passenger_ids():
		var p := world.passenger(id)
		var node := views.node_for(id)
		var body := PassengerLooks.body_of(id, p.variant)
		var tint := PassengerLooks.tint_of(id)
		assert_int(node.get_meta(&"body")).is_equal(body)
		var drawn := PassengerLooks.body_mesh(node).mesh
		var want := (
			PassengerLooks.plain_mesh(body) if tint == 0 else PassengerLooks.split_mesh(body, tint)
		)
		assert_object(drawn).is_same(want)
		tinted += int(tint != 0)
	print("passengers drawn %d, tinted %d" % [world.sim.passenger_ids().size(), tinted])
	assert_int(tinted).is_greater(0)
	views.free()
	world.free_all()


func test_bags_take_their_passengers_colour() -> void:
	var bag := InteriorKit.instantiate(SecurityLooks.KIND_PIECES[SecurityLooks.Kind.CASE])
	add_child(bag)
	var id := 1
	while PassengerLooks.bag_of(id) == 0:
		id += 1
	PassengerLooks.paint_bags([{"node": bag}], id)
	var bodies := bag.find_children("*_Body", "MeshInstance3D", true, false)
	assert_int(bodies.size()).is_greater(0)
	var mi := bodies[0] as MeshInstance3D
	var colour: Color = (mi.material_override as ShaderMaterial).get_shader_parameter("albedo_tint")
	assert_that(colour).is_equal(PassengerLooks.BAG_TINTS[PassengerLooks.bag_of(id)])
	var plain_id := 1
	while PassengerLooks.bag_of(plain_id) != 0:
		plain_id += 1
	PassengerLooks.paint_bags([{"node": bag}], plain_id)
	assert_object(mi.material_override).is_null()
	bag.free()
