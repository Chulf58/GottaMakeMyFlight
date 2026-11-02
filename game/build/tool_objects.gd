class_name ToolObjects
extends RefCounted
## The catalog id each BuildMode object tool places (BuildMode.TOOL_OBJECTS);
## the furniture tools have their own table (FurnitureTools.OBJECTS). Kept
## apart from BuildMode, which is at its file-line cap.

const OBJECTS := {
	BuildMode.Tool.DESK: &"checkin_desk",
	BuildMode.Tool.SCANNER: &"security_scanner",
	BuildMode.Tool.SEATS: &"seat_row",
	BuildMode.Tool.ENTRANCE: &"entrance_door",
	BuildMode.Tool.EXIT: &"exit_door",
	BuildMode.Tool.GATE_DESK: GateDesks.DESK,
	BuildMode.Tool.COUNTER: &"cafe_counter",
	BuildMode.Tool.TABLE: &"cafe_table",
	BuildMode.Tool.CART: &"baggage_cart",
	BuildMode.Tool.TRAY_TABLE: SecurityLanes.TRAY_TABLE,
	BuildMode.Tool.XRAY_BELT: SecurityLanes.XRAY_BELT,
	BuildMode.Tool.ARCH: SecurityLanes.ARCH,
	BuildMode.Tool.PICKUP_TABLE: SecurityLanes.PICKUP_TABLE,
	BuildMode.Tool.TOILET_STALL: &"toilet_stall",
	BuildMode.Tool.TOILET_SINK: &"toilet_sink",
	BuildMode.Tool.KIOSK_COUNTER: &"kiosk_counter",
	BuildMode.Tool.KIOSK_DISPLAY: &"kiosk_display",
	BuildMode.Tool.SCREEN: ScreenCoverage.SCREEN_ID,
	BuildMode.Tool.DUTY_FREE_TILL: &"duty_free_till",
	BuildMode.Tool.DUTY_FREE_SHELF: &"duty_free_shelf",
	BuildMode.Tool.FASHION_TILL: &"fashion_till",
	BuildMode.Tool.FASHION_RAIL: &"fashion_rail",
}
