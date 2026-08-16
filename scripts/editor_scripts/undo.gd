@tool
extends EditorScript

func _run():
	var root = get_scene()
	if root:
		_remove_collisions(root)
		print("Cleanup complete: All collisions removed!")

func _remove_collisions(node: Node):
	for child in node.get_children():
		if child is MeshInstance3D:
			# Find and delete any StaticBody3D attached to the mesh
			for c in child.get_children():
				if c is StaticBody3D:
					c.free() # Instantly deletes the node in the editor
		
		# Recursively check folders
		_remove_collisions(child)
