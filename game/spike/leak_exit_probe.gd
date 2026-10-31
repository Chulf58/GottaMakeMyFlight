extends SceneTree
## Boots main.tscn with a new random world seed (printed), steps a few frames,
## frees it and quits, so Godot's exit check can report anything the game left
## alive. Run it with --verbose and read stderr: a clean run prints no
## "ObjectDB instances were leaked" line and no "resources still in use" line.
## The probe prints the frame count it stepped, how many children the scene
## had and that it was freed, so a run that never booted the game cannot pass
## by printing nothing.
##   Godot --headless --verbose --audio-driver Dummy --path game
##     -s res://spike/leak_exit_probe.gd

const MAIN := "res://main/main.tscn"
const FRAMES := 30

var _main: Node
var _frames := 0
var _freed_at := -1


func _initialize() -> void:
	var world_seed := randi()
	print("LEAK_PROBE world_seed=%d" % world_seed)
	_main = load(MAIN).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(world_seed)
	root.add_child(_main)
	current_scene = _main


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == FRAMES:
		print("LEAK_PROBE stepped=%d children=%d" % [_frames, _main.get_child_count()])
		_main.queue_free()
		_freed_at = _frames
		return false
	if _freed_at > 0 and _frames >= _freed_at + 2:
		print("LEAK_PROBE freed=%s frames=%d" % [not is_instance_valid(_main), _frames])
		return true
	return false
