extends Control

@onready var gold_label: Label = %GoldLabel
@onready var inventory_list: VBoxContainer = %InventoryList
@onready var shop_list: VBoxContainer = %ShopList
@onready var loadout_list: VBoxContainer = %LoadoutList

func _ready() -> void:
	GameState.initialize_if_needed()
	GameState.state_changed.connect(refresh)
	%EnterRangeButton.pressed.connect(_enter_range)
	refresh()


func _exit_tree() -> void:
	if GameState.state_changed.is_connected(refresh):
		GameState.state_changed.disconnect(refresh)


func refresh() -> void:
	gold_label.text = "Gold: %d" % GameState.gold
	_rebuild_inventory()
	_rebuild_shop()
	_rebuild_loadout()


func _rebuild_inventory() -> void:
	_clear_children(inventory_list)
	for definition in GameState.all_definitions:
		var row: HBoxContainer = _create_row("%s  Owned:%d Free:%d" % [definition.display_name, GameState.get_owned_count(definition), GameState.get_unslotted_count(definition)])
		var add_button: Button = Button.new()
		add_button.text = "Add"
		add_button.disabled = GameState.get_unslotted_count(definition) <= 0
		add_button.pressed.connect(func() -> void: GameState.add_to_loadout(definition))
		row.add_child(add_button)
		inventory_list.add_child(row)


func _rebuild_shop() -> void:
	_clear_children(shop_list)
	for definition in GameState.all_definitions:
		var row: HBoxContainer = _create_row("%s  Cost:%d" % [definition.display_name, definition.cost])
		var buy_button: Button = Button.new()
		buy_button.text = "Buy"
		buy_button.disabled = GameState.gold < definition.cost
		buy_button.pressed.connect(func() -> void: GameState.buy_operator(definition))
		row.add_child(buy_button)
		shop_list.add_child(row)


func _rebuild_loadout() -> void:
	_clear_children(loadout_list)
	for index in range(GameState.loadout.size()):
		var definition: OperatorDefinition = GameState.loadout[index]
		var row: HBoxContainer = _create_row("%d. %s" % [index + 1, definition.display_name])

		var up_button: Button = Button.new()
		up_button.text = "Up"
		up_button.disabled = index == 0
		up_button.pressed.connect(func() -> void: GameState.move_loadout(index, index - 1))
		row.add_child(up_button)

		var down_button: Button = Button.new()
		down_button.text = "Down"
		down_button.disabled = index >= GameState.loadout.size() - 1
		down_button.pressed.connect(func() -> void: GameState.move_loadout(index, index + 1))
		row.add_child(down_button)

		var remove_button: Button = Button.new()
		remove_button.text = "Remove"
		remove_button.pressed.connect(func() -> void: GameState.remove_loadout_at(index))
		row.add_child(remove_button)
		loadout_list.add_child(row)

	var hint: Label = Label.new()
	hint.text = "Order = execution order."
	loadout_list.add_child(hint)


func _create_row(text: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label: Label = Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(320, 28)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


func _clear_children(root: Node) -> void:
	for child in root.get_children():
		child.queue_free()


func _enter_range() -> void:
	get_tree().change_scene_to_file("res://scenes/range_scene.tscn")
