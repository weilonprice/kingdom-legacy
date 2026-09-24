class_name Art
extends RefCounted
## Loads PixelLab art from assets/ with caching. Every lookup returns null
## when the file doesn't exist, so callers fall back to placeholder drawing.

const BUILDINGS := "res://assets/sprites/buildings/%s.png"
const CHARACTER_ROTATION := "res://assets/sprites/%s/%s.png"
const TILESET_IMAGE := "res://assets/tiles/%s_image.png"
const TILESET_METADATA := "res://assets/tiles/%s_metadata.json"
## Seasonal art lives in assets/tiles/<season>/ and wins over the shared set.
const SEASON_TILESET := "%s/%s"
const DIRECTIONS := ["south", "east", "north", "west"]
const WALK_FPS := 8.0
const FIRE_FRAME := "res://assets/sprites/fire/fire_%d.png"
const FIRE_FPS := 10.0

static var _textures := {}
static var _walk_frames := {}
static var _wang := {}
## The season the map is drawn for ("" = the original green set). Changing it
## needs a terrain rebuild.
static var season := ""


static func texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]


## `pattern` % name, preferring a <season>/ subfolder version when there is
## one (e.g. snowy bridge planks in winter).
static func seasonal(pattern: String, name: String) -> Texture2D:
	if season != "":
		var tex := texture(pattern % (season + "/" + name))
		if tex != null:
			return tex
	return texture(pattern % name)


## Seasonal variants (e.g. snow on the roofs) live in buildings/<season>/.
static func building(def_id: String) -> Texture2D:
	if season != "":
		var seasonal := texture(BUILDINGS % (season + "/" + def_id))
		if seasonal != null:
			return seasonal
	return texture(BUILDINGS % def_id)


## "south"/"east"/"north"/"west" for a movement vector (south = down-screen).
static func facing(motion: Vector2, current: String) -> String:
	if motion.length_squared() < 0.0001:
		return current
	if absf(motion.x) > absf(motion.y):
		return "east" if motion.x > 0 else "west"
	return "south" if motion.y > 0 else "north"


## Frames per second of each character animation ("<anim>_<dir>_<n>.png").
## Missing animations fall back: carry -> walk, anything -> standing pose.
const ANIM_FPS := {"walk": 8.0, "carry": 8.0, "idle": 4.0, "chop": 9.0, "mine": 9.0,
	"farm": 7.0, "hammer": 10.0, "pickup": 14.0, "putdown": 14.0}
## Played once (holding the last frame) rather than looped.
const ONE_SHOT := ["pickup", "putdown"]


## The frame to draw for `character` facing `direction`: a walk frame while
## moving (if the animation exists), else the standing rotation.
static func character_frame(character: String, direction: String, moving: bool, time: float) -> Texture2D:
	return anim_frame(character, direction, "walk" if moving else "", time)


## Frame `time` seconds into `anim` ("" = standing). "putdown" is "pickup"
## played backwards.
static func anim_frame(character: String, direction: String, anim: String, time: float) -> Texture2D:
	if anim != "":
		var frames := anim_frames(character, "pickup" if anim == "putdown" else anim, direction)
		if frames.is_empty() and anim == "carry":
			frames = walk_frames(character, direction)
		if not frames.is_empty():
			var i := int(time * ANIM_FPS.get(anim, WALK_FPS))
			if anim in ONE_SHOT:
				i = mini(i, frames.size() - 1)
				if anim == "putdown":
					i = frames.size() - 1 - i
			return frames[i % frames.size()]
	return texture(CHARACTER_ROTATION % [character, direction])


static func anim_frames(character: String, anim: String, direction: String) -> Array:
	return frames_matching("res://assets/sprites/%s/%s_%s_" % [character, anim, direction] + "%d.png")


## Draws `character` on `canvas` with its feet at the origin. Returns the
## sprite's top y (for health bars), or NAN if there's no art (the caller
## then draws its placeholder).
static func draw_character(canvas: CanvasItem, character: String, direction: String,
		moving: bool, time: float) -> float:
	return draw_character_anim(canvas, character, direction, "walk" if moving else "", time)


static func draw_character_anim(canvas: CanvasItem, character: String, direction: String,
		anim: String, time: float) -> float:
	var tex := anim_frame(character, direction, anim, time)
	if tex == null:
		return NAN
	var size := Vector2(tex.get_size())
	# PixelLab character canvases leave ~17% empty below the feet.
	var at := Vector2(-size.x * 0.5, -size.y * 0.83)
	canvas.draw_texture(tex, at)
	return at.y + size.y * 0.2


## Current frame of the looping fire animation, or null without art.
static func fire_frame(time: float) -> Texture2D:
	var frames := frames_matching(FIRE_FRAME)
	if frames.is_empty():
		return null
	return frames[int(time * FIRE_FPS) % frames.size()]


## All textures matching a "%d" path pattern, from 0 until one is missing.
static func frames_matching(pattern: String) -> Array:
	if not _walk_frames.has(pattern):
		var frames := []
		var i := 0
		while texture(pattern % i) != null:
			frames.append(texture(pattern % i))
			i += 1
		_walk_frames[pattern] = frames
	return _walk_frames[pattern]


static func walk_frames(character: String, direction: String) -> Array:
	return frames_matching("res://assets/sprites/%s/walk_%s_" % [character, direction] + "%d.png")


## A PixelLab Wang tileset: {"texture": Texture2D, "tiles": {corner_key: Vector2i}}
## where corner_key is NW,NE,SW,SE as 0 (lower) / 1 (upper), e.g. "0101".
## Null if the files aren't there.
static func wang(name: String) -> Variant:
	if season != "":
		var seasonal: Variant = _load_wang(SEASON_TILESET % [season, name])
		if seasonal != null:
			return seasonal
	return _load_wang(name)


static func _load_wang(name: String) -> Variant:
	if _wang.has(name):
		return _wang[name]
	var tex := texture(TILESET_IMAGE % name)
	var meta_path := TILESET_METADATA % name
	var result: Variant = null
	if tex != null and FileAccess.file_exists(meta_path):
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		var tiles := {}
		for tile: Dictionary in meta.tileset_data.tiles:
			var c: Dictionary = tile.corners
			var key := ""
			for corner in ["NW", "NE", "SW", "SE"]:
				key += "1" if c[corner] == "upper" else "0"
			var box: Dictionary = tile.bounding_box
			tiles[key] = Vector2i(int(box.x / box.width), int(box.y / box.height))
		result = {"texture": tex, "tiles": tiles}
	_wang[name] = result
	return result
