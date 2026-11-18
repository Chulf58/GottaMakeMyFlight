extends SceneTree
## The editor-build entry of the save, quit and cold relaunch probe (board D2c):
## adds save_relaunch_driver.gd, which does the work and documents the run
## commands. The export runs the driver as an autoload instead, because its
## release template ignores -s.


func _initialize() -> void:
	var driver: Node = (
		load(
			(get_script() as Script).resource_path.get_base_dir().path_join(
				"save_relaunch_driver.gd"
			)
		)
		. new()
	)
	driver.name = "SaveRelaunch"
	root.add_child(driver)
