extends RefCounted
class_name CombatTargeting

const StatusController = preload("res://scripts/combat/status_controller.gd")
const COMBAT_TARGET_GROUP := "combat_target"


static func collect_statuses(tree: SceneTree) -> Array[StatusController]:
	var out: Array[StatusController] = []
	if tree == null:
		return out
	for node in tree.get_nodes_in_group(COMBAT_TARGET_GROUP):
		var status: StatusController = resolve_status_from_node(node)
		if status != null:
			out.append(status)
	return out


static func resolve_status_from_node(node: Node) -> StatusController:
	if node == null:
		return null
	if node is StatusController:
		return node as StatusController
	if node.has_method("get_status_controller"):
		var direct_status: Variant = node.call("get_status_controller")
		if direct_status is StatusController:
			return direct_status as StatusController
	if node.has_node("StatusController"):
		return node.get_node("StatusController") as StatusController
	var cursor: Node = node.get_parent()
	while cursor != null:
		if cursor.has_method("get_status_controller"):
			var status_any: Variant = cursor.call("get_status_controller")
			if status_any is StatusController:
				return status_any as StatusController
		if cursor.has_node("StatusController"):
			return cursor.get_node("StatusController") as StatusController
		cursor = cursor.get_parent()
	return null


static func resolve_target_node_from_node(node: Node) -> Node:
	var cursor: Node = node
	while cursor != null:
		if cursor.is_in_group(COMBAT_TARGET_GROUP):
			return cursor
		cursor = cursor.get_parent()
	return null


static func resolve_target_node_from_status(status: StatusController) -> Node:
	if status == null:
		return null
	return resolve_target_node_from_node(status.get_parent())


static func apply_operator_effects_to_node(node: Node, effect_tags: Array[String]) -> void:
	var target_node: Node = resolve_target_node_from_node(node)
	if target_node != null and target_node.has_method("apply_operator_effects"):
		target_node.call("apply_operator_effects", effect_tags)


static func apply_operator_effects_to_status(status: StatusController, effect_tags: Array[String]) -> void:
	var target_node: Node = resolve_target_node_from_status(status)
	if target_node != null and target_node.has_method("apply_operator_effects"):
		target_node.call("apply_operator_effects", effect_tags)
