class_name PassengerLooks
extends RefCounted
## How a passenger is drawn: one of six Toon City People bodies of its gender,
## a clothing tint and a bag colour (decision comic-life-and-variety-visuals-
## first-passengers-get-10-more). All three are chosen here, in the view, from
## the sim's variant (0 male, 1 female) and the passenger's stable id, so the
## sim, its RNG and saves do not change. Each block of LOOK_BLOCK consecutive
## ids takes a hash-chosen ordering of the bodies, of the tints and of the bag
## colours, so passengers spawned one after another differ.
##
## A tint recolours only the clothes. The converter (tools/blender/
## convert_toon_batch.py) marks each body's clothes' vertices white in COLOR_0
## and every other vertex black. A tinted body draws a copy of its mesh split
## in two surfaces: the clothes on the tint's atlas, everything else (skin,
## hair, shoes, jewellery) on the shared atlas. Tint 0 keeps the vendor
## colours; the others turn the hue of the swatches the clothes sample and give
## grey ones a light colour, keeping each swatch's own shading. Each tint's
## atlas and each body's split mesh is made on first use and then shared.

const BODIES: Array[String] = [
	"tcp_male_character_01",
	"tcp_male_character_02",
	"tcp_male_character_03",
	"tcp_male_character_06",
	"tcp_male_character_08",
	"tcp_male_character_09",
	"tcp_female_character_01",
	"tcp_female_character_03",
	"tcp_female_character_04",
	"tcp_female_character_05",
	"tcp_female_character_08",
	"tcp_female_character_11",
]
const SCENES: Array[PackedScene] = [
	preload("res://assets/people/tcp_male_character_01.glb"),
	preload("res://assets/people/tcp_male_character_02.glb"),
	preload("res://assets/people/tcp_male_character_03.glb"),
	preload("res://assets/people/tcp_male_character_06.glb"),
	preload("res://assets/people/tcp_male_character_08.glb"),
	preload("res://assets/people/tcp_male_character_09.glb"),
	preload("res://assets/people/tcp_female_character_01.glb"),
	preload("res://assets/people/tcp_female_character_03.glb"),
	preload("res://assets/people/tcp_female_character_04.glb"),
	preload("res://assets/people/tcp_female_character_05.glb"),
	preload("res://assets/people/tcp_female_character_08.glb"),
	preload("res://assets/people/tcp_female_character_11.glb"),
]
## Bodies per variant: BODIES holds the males, then the females.
const PER_VARIANT := 6
## Clip speeds measured by the Toon pipeline (its SPEED lines), per body. The
## bodies of one gender share one skeleton, so their speeds agree.
const CLIP_WALK_MPS: Array[float] = [
	1.952, 1.952, 1.952, 1.952, 1.952, 1.952, 1.922, 1.922, 1.922, 1.922, 1.922, 1.922
]
const CLIP_RUN_MPS: Array[float] = [
	5.295, 5.295, 5.295, 5.295, 5.295, 5.295, 4.173, 4.173, 4.173, 4.173, 4.173, 4.173
]
## Clothing tints: [hue turn of coloured swatches, hue given to grey swatches].
## Tint 0 is the vendor's own colours.
const TINTS := [[0.0, -1.0], [0.5, 0.6], [0.17, 0.08], [0.83, 0.95], [0.33, 0.3], [0.67, 0.5]]
## A swatch pixel below this saturation is grey: it takes the tint's grey hue
## at GREY_SAT instead of a hue turn, which would leave it grey.
const GREY_BELOW := 0.15
const GREY_SAT := 0.3
## Texels recoloured around each clothes triangle's UV box, so filtering at
## its edge blends tinted texels only.
const TEXEL_MARGIN := 1
## Bag colours, multiplied into the bag's atlas colour (albedo_tint); 0 keeps
## the vendor colour. Toon palette accents (decision hud-look-warm-cozy-cream-
## cards-with-a-dark-outline-toon-pale): teal, sunny yellow, coral red, green,
## and a navy.
const BAG_TINTS: Array[Color] = [
	Color(1.0, 1.0, 1.0),
	Color(0.35, 0.8, 0.78),
	Color(1.0, 0.82, 0.3),
	Color(1.0, 0.45, 0.4),
	Color(0.5, 0.82, 0.42),
	Color(0.42, 0.5, 0.85),
]
const LOOK_BLOCK := 6

## Body index -> its imported mesh.
static var _plain := {}
## "body/tint" -> the body's mesh split for that tint.
static var _split := {}
## Tint index -> the clothes' material of that tint.
static var _materials := {}
## "material id/colour" -> bag material.
static var _bag_materials := {}


## The body index (into BODIES) a passenger is drawn with.
static func body_of(id: int, variant: int) -> int:
	return variant * PER_VARIANT + pick(id, 0, PER_VARIANT)


## The clothing tint index (into TINTS) of a passenger.
static func tint_of(id: int) -> int:
	return pick(id, 1, TINTS.size())


## The bag colour index (into BAG_TINTS) of a passenger.
static func bag_of(id: int) -> int:
	return pick(id, 2, BAG_TINTS.size())


## Id `id`'s place in a hash-chosen ordering of 0..count-1 for its block of
## LOOK_BLOCK ids (`salt` keeps body, tint and bag orderings apart). Within a
## block of count ids every value comes once.
static func pick(id: int, salt: int, count: int) -> int:
	var block := floori(id / float(LOOK_BLOCK))
	var order: Array[int] = []
	for i in count:
		order.append(i)
	var h := _mix(block * 4 + salt)
	for i in range(count - 1, 0, -1):
		h = _mix(h + i)
		var j := h % (i + 1)
		var swap := order[i]
		order[i] = order[j]
		order[j] = swap
	return order[posmod(id, LOOK_BLOCK) % count]


## The skinned body mesh of a character node from SCENES.
static func body_mesh(node: Node) -> MeshInstance3D:
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.skin != null or mi.get_parent() is Skeleton3D:
			return mi
	return null


## Draws character node `node` of body `body` with tint `tint`.
static func paint_body(node: Node, body: int, tint: int) -> void:
	var mi := body_mesh(node)
	if mi == null:
		push_error("PassengerLooks: %s has no body mesh" % node.name)
		return
	mi.mesh = plain_mesh(body) if tint == 0 else split_mesh(body, tint)


## Body `body`'s imported mesh.
static func plain_mesh(body: int) -> Mesh:
	if not _plain.has(body):
		var node := SCENES[body].instantiate()
		_plain[body] = body_mesh(node).mesh
		node.free()
	return _plain[body]


## Body `body`'s mesh as two surfaces: everything but the clothes on the
## shared atlas (surface 0), the clothes on tint `tint`'s atlas (surface 1).
static func split_mesh(body: int, tint: int) -> Mesh:
	var key := "%d/%d" % [body, tint]
	if _split.has(key):
		return _split[key]
	var plain := plain_mesh(body)
	var arrays := plain.surface_get_arrays(0)
	var parts := cloth_split(arrays[Mesh.ARRAY_INDEX], arrays[Mesh.ARRAY_COLOR])
	if parts[1].is_empty():
		push_error("PassengerLooks: %s has no clothes' mark (COLOR_0)" % BODIES[body])
		_split[key] = plain
		return plain
	var flags: int = (plain as ArrayMesh).surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var mesh := ArrayMesh.new()
	for i in 2:
		arrays[Mesh.ARRAY_INDEX] = parts[i]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	mesh.surface_set_material(0, plain.surface_get_material(0))
	mesh.surface_set_material(1, material(tint))
	_split[key] = mesh
	return mesh


## A triangle index list split into [other triangles, clothes' triangles] by
## the clothes' mark of each triangle's first corner (COLOR_0 red over 0.5).
static func cloth_split(index: PackedInt32Array, colors: PackedColorArray) -> Array:
	var other := PackedInt32Array()
	var cloth := PackedInt32Array()
	if colors.is_empty():
		return [index, cloth]
	for t in range(0, index.size(), 3):
		var into := cloth if colors[index[t]].r > 0.5 else other
		into.append(index[t])
		into.append(index[t + 1])
		into.append(index[t + 2])
	return [other, cloth]


## The clothes' material of tint `tint` (> 0): the shared body material on an
## atlas whose clothes' texels (cloth_texels) are recoloured.
static func material(tint: int) -> ShaderMaterial:
	if _materials.has(tint):
		return _materials[tint]
	var base := plain_mesh(0).surface_get_material(0) as ShaderMaterial
	var made := base.duplicate() as ShaderMaterial
	var atlas := (base.get_shader_parameter("albedo_texture") as Texture2D).get_image()
	if atlas == null:
		push_error("PassengerLooks: the body atlas has no image; tint %d stays untinted" % tint)
	else:
		atlas.decompress()
		var texels := cloth_texels(atlas.get_width(), atlas.get_height())
		var tinted := tint_image(atlas, texels, tint)
		made.set_shader_parameter("albedo_texture", ImageTexture.create_from_image(tinted))
	_materials[tint] = made
	return made


## Texel indices (y * width + x) the clothes of every body sample, each
## triangle's UV box grown by TEXEL_MARGIN, on a width x height atlas.
static func cloth_texels(width: int, height: int) -> PackedInt32Array:
	var mark := {}
	for body in BODIES.size():
		var arrays := plain_mesh(body).surface_get_arrays(0)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var index: PackedInt32Array = cloth_split(
			arrays[Mesh.ARRAY_INDEX], arrays[Mesh.ARRAY_COLOR]
		)[1]
		for t in range(0, index.size(), 3):
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for k in 3:
				var at := uvs[index[t + k]] * Vector2(width, height)
				lo = lo.min(at)
				hi = hi.max(at)
			var x1 := mini(int(hi.x) + TEXEL_MARGIN, width - 1)
			var y1 := mini(int(hi.y) + TEXEL_MARGIN, height - 1)
			for y in range(maxi(int(lo.y) - TEXEL_MARGIN, 0), y1 + 1):
				for x in range(maxi(int(lo.x) - TEXEL_MARGIN, 0), x1 + 1):
					mark[y * width + x] = true
	var out := PackedInt32Array(mark.keys())
	out.sort()
	return out


## A copy of `atlas` with `texels` (y * width + x) recoloured by tint `tint`,
## mipmaps rebuilt.
static func tint_image(atlas: Image, texels: PackedInt32Array, tint: int) -> Image:
	var out := atlas.duplicate() as Image
	if out.has_mipmaps():
		out.clear_mipmaps()
	var width := out.get_width()
	var turn: float = TINTS[tint][0]
	var grey_hue: float = TINTS[tint][1]
	var done := {}
	for t in texels:
		var x := t % width
		var y := t / width
		var c := out.get_pixel(x, y)
		var key := c.to_rgba32()
		if not done.has(key):
			done[key] = tinted(c, turn, grey_hue)
		out.set_pixel(x, y, done[key])
	out.generate_mipmaps()
	return out


## Colour `c` under a tint: a hue turn, or for a grey the tint's grey hue.
static func tinted(c: Color, turn: float, grey_hue: float) -> Color:
	if turn == 0.0 and grey_hue < 0.0:
		return c
	if c.s < GREY_BELOW:
		return Color.from_hsv(grey_hue, maxf(c.s, GREY_SAT), c.v, c.a)
	return Color.from_hsv(fposmod(c.h + turn, 1.0), c.s, c.v, c.a)


## Colours the "_Body" meshes of a passenger's bag nodes with its bag colour.
## `bags` holds CarryOnProps bag records ({"node": Node3D, ...}).
static func paint_bags(bags: Array, id: int) -> void:
	var colour := bag_of(id)
	for bag: Dictionary in bags:
		var node: Node3D = bag["node"]
		if node.get_meta(&"bag_colour", 0) == colour:
			continue
		node.set_meta(&"bag_colour", colour)
		for mi: MeshInstance3D in node.find_children("*_Body", "MeshInstance3D", true, false):
			mi.material_override = null if colour == 0 else _bag_material(mi, colour)


static func _bag_material(mi: MeshInstance3D, colour: int) -> Material:
	# The mesh's own material: get_active_material would return an override set
	# by an earlier paint.
	var source := mi.mesh.surface_get_material(0)
	var key := "%d/%d" % [source.get_instance_id(), colour]
	if not _bag_materials.has(key):
		var made := source.duplicate() as ShaderMaterial
		made.set_shader_parameter("albedo_tint", BAG_TINTS[colour])
		_bag_materials[key] = made
	return _bag_materials[key]


static func _mix(x: int) -> int:
	x = ((x ^ (x >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	x = ((x ^ (x >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	return x ^ (x >> 16)
