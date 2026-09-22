extends Node2D
## Entry point: wires up the world, simulation, input controllers and UI.

var world: WorldMap
var citizens: CitizenManager
var raids: RaidDirector
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

	raids = RaidDirector.new()
	raids.setup(world)
	add_child(raids)

	build = BuildController.new()
	build.world = world
	add_child(build)

	camera = CameraController.new()
	camera.bounds = Rect2(Vector2.ZERO, world.pixel_size())
	camera.position = world.tile_center(world.keep.entrance())
	add_child(camera)

	hud = HUD.new()
	hud.setup(build, world, citizens, raids)
	add_child(hud)

	world.keep_destroyed.connect(_on_defeat.bind("The Keep has fallen!"))
	citizens.all_villagers_lost.connect(_on_defeat.bind("Your people have abandoned the kingdom."))


func _on_defeat(title: String) -> void:
	if GameState.game_over:
		return
	GameState.end_game()
	hud.show_defeat(title, "Raids survived: %d\nMap seed: %d" % [raids.raids_survived, world.map_seed])
