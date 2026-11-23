class_name RoomPrestige
extends RefCounted
## Deterministic per-room prestige calculator (L1-5; decision b764f946).
## Derived purely from BuildGrid room geometry and placed objects inside the
## room, so nothing is stored in saves.

const MIN_LEVEL := 1
const MAX_LEVEL := 5
## Score thresholds for L1..L5: L1 (0..19), L2 (20..44), L3 (45..74),
## L4 (75..109), L5 (110+). Bare starter rooms stay L1 (+0%).
const LEVEL_THRESHOLDS: Array[int] = [0, 20, 45, 75, 110]
## Spend bonus in percent by level (L1..L5).
const SPEND_BONUS_PERCENTS: Array[int] = [0, 3, 7, 11, 15]
## Break Room staff energy recovery bonus in percent by level (L1..L5).
const BREAK_BONUS_PERCENTS: Array[int] = [0, 2, 5, 8, 10]
## Diminishing returns for identical decor or trophy copies in one room:
## 1st copy 100%, 2nd copy 60%, 3rd+ copy 25%.
const COPY_WEIGHT_PERCENTS: Array[int] = [100, 60, 25]
const CELLS_PER_SIZE_POINT := 3
const MAX_SIZE_POINTS := 14
const MAX_FURNISHING_POINTS := 4
const DEFAULT_MIN_AREA := 9
const AWARD_PREFIX := "award_"
const DEFAULT_TROPHY_POINTS := 30
## Optional per-trophy point overrides for Annual Awards pieces.
const TROPHY_WEIGHTS: Dictionary = {}


## Commercial spend bonus percentage for prestige `level` (L1..L5).
static func spend_bonus_percent(level: int) -> int:
	return SPEND_BONUS_PERCENTS[clampi(level, MIN_LEVEL, MAX_LEVEL) - 1]


## Applies the prestige spend bonus to `base_amount` using integer half-up
## rounding. Returns exact `base_amount` for L1 or non-positive amounts.
static func apply_spend_bonus(base_amount: int, level: int) -> int:
	if level <= MIN_LEVEL or base_amount <= 0:
		return base_amount
	var pct := spend_bonus_percent(level)
	@warning_ignore("integer_division")
	return (base_amount * (100 + pct) + 50) / 100


## Break Room staff energy recovery bonus percentage for prestige `level`.
static func break_recovery_bonus_percent(level: int) -> int:
	return BREAK_BONUS_PERCENTS[clampi(level, MIN_LEVEL, MAX_LEVEL) - 1]


## Whether `kind` is an Annual Awards trophy or plaque piece.
static func is_trophy_kind(kind: StringName) -> bool:
	return TROPHY_WEIGHTS.has(kind) or String(kind).begins_with(AWARD_PREFIX)


## Base prestige points of a trophy/plaque `kind`, or 0 if not a trophy.
static func trophy_points_of(kind: StringName) -> int:
	if not is_trophy_kind(kind):
		return 0
	return int(TROPHY_WEIGHTS.get(kind, DEFAULT_TROPHY_POINTS))


## Whether `kind` is a prestige-granting decor piece from DecorEffect.TABLE.
static func is_decor_kind(kind: StringName) -> bool:
	return DecorEffect.calm_of(kind) > 0


## Base prestige points of a decor piece `kind`, derived from DecorEffect.TABLE.
static func decor_points_of(kind: StringName) -> int:
	var calm := DecorEffect.calm_of(kind)
	if calm <= 0:
		return 0
	return calm * 4 + DecorEffect.radius_of(kind) + 2


## Prestige level (1..5) for `score`.
static func level_for_score(score: int) -> int:
	for i in range(MAX_LEVEL, MIN_LEVEL, -1):
		if score >= LEVEL_THRESHOLDS[i - 1]:
			return i
	return MIN_LEVEL


## Next score threshold above `level`, or 0 when already at MAX_LEVEL.
static func next_threshold_for(level: int) -> int:
	if level < MIN_LEVEL:
		return LEVEL_THRESHOLDS[1]
	if level >= MAX_LEVEL:
		return 0
	return LEVEL_THRESHOLDS[level]


## Evaluates room `room_id` on `grid` and returns its prestige level, score,
## breakdown, and bonuses. Unknown/null rooms safely evaluate to L1.
static func evaluate_room(grid: BuildGrid, room_id: int) -> Dictionary:
	if grid == null or room_id <= 0:
		return evaluate_counts({}, Vector2i.ZERO, &"")
	var room := grid.get_room(room_id)
	if room.is_empty():
		return evaluate_counts({}, Vector2i.ZERO, &"")
	var area: Rect2i = room["rect"]
	var type_id := StringName(room["type"])
	var counts: Dictionary = {}
	var seen: Dictionary = {}
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var object_id := grid.object_at(Vector2i(x, y))
			if object_id <= 0 or seen.has(object_id):
				continue
			seen[object_id] = true
			if not RoomRules.piece_inside(grid, object_id, area):
				continue
			var def_id := StringName(grid.get_object(object_id)["def"])
			counts[def_id] = int(counts.get(def_id, 0)) + 1
	return evaluate_counts(counts, area.size, type_id)


## Pure evaluation from piece `counts` (`StringName -> int`), `room_size`, and
## optional `type_id`.
static func evaluate_counts(
	counts: Dictionary, room_size: Vector2i, type_id: StringName = &""
) -> Dictionary:
	var type := RoomTypes.get_type(type_id) if type_id != &"" else null
	var min_area := type.min_size.x * type.min_size.y if type != null else DEFAULT_MIN_AREA
	var area := maxi(0, room_size.x) * maxi(0, room_size.y)
	var extra_cells := maxi(0, area - min_area)
	@warning_ignore("integer_division")
	var size_points := mini(extra_cells / CELLS_PER_SIZE_POINT, MAX_SIZE_POINTS)

	var decor_points := 0
	var trophy_points := 0
	var decor_count := 0
	var unique_decor := 0
	var functional_count := 0

	var keys := counts.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for raw_key: Variant in keys:
		var def_id := StringName(raw_key)
		var count := int(counts[raw_key])
		if count <= 0:
			continue
		if is_trophy_kind(def_id):
			var base_trophy := trophy_points_of(def_id)
			for i in count:
				trophy_points += _scaled_copy_points(base_trophy, i)
		elif is_decor_kind(def_id):
			decor_count += count
			unique_decor += 1
			var base_decor := decor_points_of(def_id)
			for i in count:
				decor_points += _scaled_copy_points(base_decor, i)
		elif not DecorEffect.TABLE.has(def_id):
			functional_count += count

	var furnishing_points := mini(functional_count, MAX_FURNISHING_POINTS)
	var score := size_points + decor_points + trophy_points + furnishing_points
	var level := level_for_score(score)
	return {
		"level": level,
		"score": score,
		"next_threshold": next_threshold_for(level),
		"size_points": size_points,
		"decor_points": decor_points,
		"trophy_points": trophy_points,
		"furnishing_points": furnishing_points,
		"spend_bonus_percent": spend_bonus_percent(level),
		"break_bonus_percent": break_recovery_bonus_percent(level),
		"decor_count": decor_count,
		"unique_decor": unique_decor,
	}


## Prestige level (1..5) of the room containing `cell`, or 1 outside rooms.
static func room_level_at(grid: BuildGrid, cell: Vector2i) -> int:
	if grid == null or not grid.in_bounds(cell):
		return MIN_LEVEL
	var room_id := grid.room_at(cell)
	if room_id <= 0:
		return MIN_LEVEL
	return int(evaluate_room(grid, room_id)["level"])


static func _scaled_copy_points(base_weight: int, copy_index: int) -> int:
	var pct := COPY_WEIGHT_PERCENTS[mini(copy_index, COPY_WEIGHT_PERCENTS.size() - 1)]
	@warning_ignore("integer_division")
	return (base_weight * pct + 50) / 100
