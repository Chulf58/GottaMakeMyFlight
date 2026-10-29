extends SceneTree
## Crops a saved plate and scales it up, for a close look at a detail:
##   Godot --headless --path game -s res://spike/plate_crop.gd -- <in.png> <out.png> x y w h scale


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var img := Image.load_from_file(args[0])
	var rect := Rect2i(int(args[2]), int(args[3]), int(args[4]), int(args[5]))
	var region := img.get_region(rect.intersection(Rect2i(Vector2i.ZERO, img.get_size())))
	var scale := int(args[6])
	region.resize(
		region.get_width() * scale, region.get_height() * scale, Image.INTERPOLATE_NEAREST
	)
	print("CROP %s -> %s err=%d" % [rect, args[1], region.save_png(args[1])])
	quit()
