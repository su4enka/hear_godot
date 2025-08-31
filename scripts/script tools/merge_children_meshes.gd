@tool
extends Node3D

# Повесь на узел-родителя (например, ShowerKnobs), затем нажми кнопку в инспекторе.

@export var MERGE_NOW := false : set = _merge

func _merge(_v):
	if not Engine.is_editor_hint(): return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Собираем все MeshInstance3D-потомки
	for child in get_children():
		if child is MeshInstance3D and child.mesh:
			var mi := child as MeshInstance3D
			var xform := global_transform.affine_inverse() * mi.global_transform
			for s in mi.mesh.get_surface_count():
				st.append_from(mi.mesh, s, xform)

	var new_mesh := st.commit()
	if new_mesh == null:
		push_error("Nothing to merge")
		return

	# Создаём новый MeshInstance3D с объединённым мешем
	var merged := MeshInstance3D.new()
	merged.name = "MergedShower"
	merged.mesh = new_mesh
	add_child(merged)
	merged.owner = owner  # чтобы сохранилось в сцену

	# Старые можно скрыть или удалить вручную
	print("Merged ", name, " -> ", merged.mesh.get_surface_count(), " surface(s)")
