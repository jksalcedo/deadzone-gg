@tool
extends EditorScript

# Smaller values = higher quality but longer unwrap times.
const TEXEL_SIZE = 0.3

func _run():
	var root = get_scene()
	if root:
		_unwrap_uv2(root)
		print("UV2 unwrapping complete!")
	else:
		print("No scene loaded.")

func _unwrap_uv2(node: Node):
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh = child.mesh
			
			# Imported .glb meshes are converted to ArrayMeshes
			if mesh is ArrayMesh:
				# Generate the UV2 based on the mesh's scale in the world
				var err = mesh.lightmap_unwrap(child.global_transform, TEXEL_SIZE)
				
				if err == OK:
					# Automatically set GI mode to Static so it gets baked by LightmapGI
					child.gi_mode = GeometryInstance3D.GI_MODE_STATIC
				else:
					print("Failed to unwrap UV2 on: ", child.name)
					
			elif mesh and "add_uv2" in mesh:
				mesh.add_uv2 = true
				child.gi_mode = GeometryInstance3D.GI_MODE_STATIC
				
		# Recursively scan through all folders/nodes
		_unwrap_uv2(child)
