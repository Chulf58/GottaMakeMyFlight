class_name WholeNumber
extends RefCounted
## The check snapshots use for a JSON number that must be a whole number.
## JSON hands back floats, so a whole float is accepted; 480.000001 is not.


static func is_whole(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_finite(value) and value == floorf(value)
