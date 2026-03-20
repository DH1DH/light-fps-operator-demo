extends RefCounted
class_name ShotContext

enum ShotPhase {
	BUILD,
	RESOLVE,
}

var damage := 0.0
var pellet_count := 1
var spread_angle := 0.0
var effect_tags: Array[String] = []
var phase: ShotPhase = ShotPhase.BUILD
var hand: String = "right"


func add_effect(tag: String) -> void:
	if tag.is_empty():
		return
	if not effect_tags.has(tag):
		effect_tags.append(tag)


static func phase_to_string(value: int) -> String:
	if value == ShotPhase.RESOLVE:
		return "RESOLVE"
	return "BUILD"


static func phase_role_to_string(value: int) -> String:
	if value == ShotPhase.RESOLVE:
		return "爆发"
	return "铺垫"


static func phase_with_role(value: int) -> String:
	return "%s(%s)" % [phase_to_string(value), phase_role_to_string(value)]
