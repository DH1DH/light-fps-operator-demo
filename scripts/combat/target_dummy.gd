extends StaticBody3D
class_name TargetDummy

@onready var status: StatusController = $StatusController
@onready var mesh_instance: MeshInstance3D = $Visual
@onready var label: Label3D = $Label

func _ready() -> void:
	add_to_group("target_dummy")
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color.FIREBRICK
	mesh_instance.set_surface_override_material(0, material)


func _process(_delta: float) -> void:
	label.text = "HP: %d/%d\nMARK: %d" % [int(round(status.current_hp)), int(round(status.max_hp)), status.mark_stacks]
	var material: Material = mesh_instance.get_active_material(0)
	if material is StandardMaterial3D:
		material.albedo_color = Color.GRAY if status.is_dead() else Color.FIREBRICK


func reset_dummy() -> void:
	status.reset_status()
