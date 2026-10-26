class_name ShellDoorConnection
extends Resource
## One Toon doorway of the terminal shell as the build tools and passengers
## use it: the grid cell just inside it, the facing an entrance or exit takes
## there and the authored walk outside. Part of a ShellDefinition.

## Landside doors take entrances, airside gate doors take exits.
enum Kind { LANDSIDE, AIRSIDE }

## The shell's Doorway_n empty this connection stands for.
@export var doorway := 0
@export var kind := Kind.LANDSIDE
## The letter on the door's porch sign: A to D on each side.
@export var label := ""
## The border cell just inside the doorway.
@export var cell := Vector2i.ZERO
## The facing an entrance or exit door object takes on `cell`, in BuildMode's
## convention: DoorPlacement.back_step(facing) points out through the doorway.
@export var facing := 0
## The walk outside, world points with authored heights. A landside route runs
## from the road to the doorway, an airside one from the doorway to the plane
## door.
@export var route := PackedVector3Array()


## Which kind of door a door object (BuildCatalog.DOOR_IDS) needs.
static func kind_for(def_id: StringName) -> Kind:
	return Kind.AIRSIDE if def_id == &"exit_door" else Kind.LANDSIDE
