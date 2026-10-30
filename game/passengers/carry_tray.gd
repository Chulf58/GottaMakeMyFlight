class_name CarryTray
extends RefCounted
## Where a passenger's security tray is drawn (CarryOnProps): on the tray table
## while it unpacks, riding over the belt by its walker's progress through the
## arch, on the pickup table while it picks up. A tray kept while a bag moves
## out of it stays at the place and on the lane it was given last, so a
## passenger that has lost its lane (finished, sent back, the station closed)
## still has its tray drawn there.

const TRAY_MOUNTS := {
	SecurityLooks.Tray.IN: [SecurityLanes.TRAY_TABLE, "Mount_TrayIn"],
	SecurityLooks.Tray.OUT: [SecurityLanes.PICKUP_TABLE, "Mount_TrayOut"],
}
const SCAN_MOUNT := [SecurityLanes.XRAY_BELT, "Mount_TrayScan"]


## The tray at `at` on `lane` (CarryOnProps' record's "tray_at" and "lane"),
## its passenger drawn at `body`; the identity with no tray.
static func placed(
	grid: BuildGrid, lane: Dictionary, at: SecurityLooks.Tray, body: Vector3
) -> Transform3D:
	match at:
		SecurityLooks.Tray.RIDE:
			return ride(grid, lane, body)
		SecurityLooks.Tray.IN, SecurityLooks.Tray.OUT:
			var mount: Array = TRAY_MOUNTS[at]
			return CarryOnProps.mount_world(grid, lane, mount[0], mount[1])
	return Transform3D.IDENTITY


## Where a riding tray is when its passenger is drawn at `body`: from the tray
## table over the belt to the pickup table, by the body's progress along the
## passage from the unpack cell to the pickup cell.
static func ride(grid: BuildGrid, lane: Dictionary, body: Vector3) -> Transform3D:
	var unpack := grid.cell_to_world(lane["unpack"])
	var pickup := grid.cell_to_world(lane["pickup"])
	var along := pickup - unpack
	var t := clampf((body - unpack).dot(along) / along.length_squared(), 0.0, 1.0)
	var start := CarryOnProps.mount_world(grid, lane, SecurityLanes.TRAY_TABLE, "Mount_TrayIn")
	var mid := CarryOnProps.mount_world(grid, lane, SCAN_MOUNT[0], SCAN_MOUNT[1])
	var end := CarryOnProps.mount_world(grid, lane, SecurityLanes.PICKUP_TABLE, "Mount_TrayOut")
	if t < 0.5:
		return start.interpolate_with(mid, t * 2.0)
	return mid.interpolate_with(end, (t - 0.5) * 2.0)
