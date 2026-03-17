extends RefCounted
class_name ShotContext

var damage := 0.0
var pellet_count := 1
var spread_angle := 0.0
var effect_tags: Array[String] = []


func add_effect(tag: String) -> void:
	if tag.is_empty():
		return
	if not effect_tags.has(tag):
		effect_tags.append(tag)
