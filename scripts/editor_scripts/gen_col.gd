@tool
extends EditorScript

func _run():
	var root = get_scene()
	if root:
		_add_convex_collisions(root)
		print("Convex collisions generated!")

func _add_convex_collisions(node: Node):
	for child in node.get_children():
		if child is MeshInstance3D:
			var has_col = false
			for c in child.get_children():
				if c is StaticBody3D:
					has_col = true
			
			if not has_col:
				child.create_convex_collision()
		
		_add_convex_collisions(child)
