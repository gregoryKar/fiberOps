class_name FiberColors
extends RefCounted
## TIA-598 fiber colour code. Fibers 13-24 repeat the twelve colours with a black tracer
## stripe (black fiber 20 gets a white one).

const NAMES: Array[String] = [
	"blue", "orange", "green", "brown", "slate", "white",
	"red", "black", "yellow", "violet", "rose", "aqua",
]
const COLORS: Array[Color] = [
	Color(0.12, 0.35, 0.85), Color(1.0, 0.55, 0.1), Color(0.15, 0.65, 0.25), Color(0.5, 0.3, 0.15),
	Color(0.55, 0.58, 0.62), Color(0.96, 0.96, 0.96), Color(0.85, 0.12, 0.12), Color(0.08, 0.08, 0.08),
	Color(0.98, 0.88, 0.15), Color(0.55, 0.25, 0.75), Color(1.0, 0.6, 0.7), Color(0.3, 0.85, 0.85),
]


static func color_for(fiber: int) -> Color:
	return COLORS[fiber % COLORS.size()]


static func name_for(fiber: int) -> String:
	var base := NAMES[fiber % NAMES.size()]
	return base if fiber < NAMES.size() else base + "/stripe"


static func has_stripe(fiber: int) -> bool:
	return fiber >= NAMES.size()


## Readable text colour on top of the fiber colour.
static func text_color_for(fiber: int) -> Color:
	return Color.BLACK if color_for(fiber).get_luminance() > 0.5 else Color.WHITE
