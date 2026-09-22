extends Node2D
## Entry point: wires up the world, simulation, input controllers and UI.

var world: WorldMap
var citizens: CitizenManager
var build: BuildController
var camera: CameraController
var hud: HUD


func _ready() -> void:
	randomize()
	GameState.reset()

	world = WorldMap.new()
	add_child(world)
	world.generate(randi())
	print("Map seed: %d" % world.map_seed)

	citizens = CitizenManager.new()
	citizens.setup(world)
	add_child(citizens)

	build = BuildController.new()
	build.world = world
	add_child(build)

	camera = CameraController.new()
	camera.bounds = Rect2(Vector2.ZERO, world.pixel_size())
	camera.position = world.tile_center(world.keep.entrance())
	add_child(camera)

	hud = HUD.new()
	hud.setup(build, world, citizens)
	add_child(hud)
