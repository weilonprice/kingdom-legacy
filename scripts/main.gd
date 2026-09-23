extends Node2D
## Entry point: wires up the world, simulation, input controllers and UI.

var world: WorldMap
var citizens: CitizenManager
var raids: RaidDirector
var military: Military
var units: UnitController
var research: Research
var progression: Progression
var needs: Needs
var overlay: Overlay
var day_night: DayNight
var fire: FireSystem
var build: BuildController
var camera: CameraController
var hud: HUD


func _ready() -> void:
	randomize()
	GameState.reset()

	world = WorldMap.new()
	add_child(world)
	world.generate(_seed_from_args())
	print("Map seed: %d" % world.map_seed)

	citizens = CitizenManager.new()
	citizens.setup(world)
	add_child(citizens)

	raids = RaidDirector.new()
	raids.setup(world)
	add_child(raids)

	day_night = DayNight.new()
	day_night.world = world
	add_child(day_night)

	fire = FireSystem.new()
	fire.world = world
	add_child(fire)

	needs = Needs.new()
	needs.setup(world, citizens)
	add_child(needs)

	research = Research.new()
	research.setup(world)
	add_child(research)

	progression = Progression.new()
	progression.setup(world, raids, research)
	add_child(progression)
	raids.progression = progression

	military = Military.new()
	military.setup(world, citizens)
	military.progression = progression
	add_child(military)

	build = BuildController.new()
	build.world = world
	build.progression = progression
	add_child(build)

	overlay = Overlay.new()
	overlay.world = world
	add_child(overlay)

	# Added after the build controller so it sees input first.
	units = UnitController.new()
	units.setup(world, build, military)
	add_child(units)

	camera = CameraController.new()
	camera.bounds = Rect2(Vector2.ZERO, world.pixel_size())
	camera.position = world.tile_center(world.keep.entrance())
	add_child(camera)

	hud = HUD.new()
	hud.setup(build, world, citizens, raids, military, units, progression, research, needs, overlay, day_night)
	add_child(hud)

	world.keep_destroyed.connect(_on_defeat.bind("The Keep has fallen!"))
	citizens.all_villagers_lost.connect(_on_defeat.bind("Your people have abandoned the kingdom."))


## `godot --path . -- --seed=123` replays a specific map; otherwise random.
func _seed_from_args() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			return int(arg.get_slice("=", 1))
	return randi()


func _on_defeat(title: String) -> void:
	if GameState.game_over:
		return
	GameState.end_game()
	hud.show_defeat(title, "Raids survived: %d\nMap seed: %d" % [raids.raids_survived, world.map_seed])
