# corley_rig.gd — procedural project-owned humanoid builder.
# Builds an articulated adult humanoid from tapered organic segments
# (NOT cubes for limbs, NOT capsule-stack mannequin): each limb uses
# CylinderMesh with distinct top/bottom radii + joint spheres sunk inside
# the segment so the silhouette is continuous; torso uses stacked tapered
# elliptical sections; head is an ovoid with jaw taper, plus nose/eyes/
# hair so the third-person read is unambiguously human.
# Returns { bones: {...}, meshes: [...], height } for animation by corley.gd / npc.gd.
class_name CorleyRig
extends RefCounted

static func tapered_limb(top_r: float, bot_r: float, len: float, mat: Material, sides: int = 10) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = top_r
	cyl.bottom_radius = bot_r
	cyl.height = len
	cyl.radial_segments = sides
	cyl.rings = 2
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	# pivot at joint: mesh hangs down -len/2
	mi.position = Vector3(0, -len * 0.5, 0)
	if mat:
		mi.material_override = mat
	return mi

static func joint_ball(r: float, mat: Material) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 8
	var mi := MeshInstance3D.new()
	mi.mesh = s
	if mat:
		mi.material_override = mat
	return mi

static func torso_section(top_w: float, bot_w: float, h: float, depth_scale: float, mat: Material) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = top_w * 0.5
	cyl.bottom_radius = bot_w * 0.5
	cyl.height = h
	cyl.radial_segments = 14
	cyl.rings = 2
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.scale = Vector3(1.0, 1.0, depth_scale)
	if mat:
		mi.material_override = mat
	return mi

static func std_material(color: Color, rough: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = 0.0
	return m

# variant: "corley" (adult woman, dark hair, tank + simple pants) or "worker" (male, jacket)
static func build(parent: Node3D, variant: String = "corley") -> Dictionary:
	var is_corley := variant == "corley"
	var skin_mat := std_material(Color(0.82, 0.66, 0.56) if is_corley else Color(0.78, 0.60, 0.50))
	var hair_mat := std_material(Color(0.09, 0.07, 0.06), 0.6)
	var top_mat: StandardMaterial3D
	var pants_mat: StandardMaterial3D
	var boot_mat := std_material(Color(0.16, 0.13, 0.11), 0.9)
	if is_corley:
		top_mat = std_material(Color(0.20, 0.22, 0.20), 0.9) # dark weathered tank
		pants_mat = std_material(Color(0.28, 0.30, 0.33), 0.95) # simple grey lower
	else:
		# workers get hi-vis / work palettes by hue shift param
		var pal: Color = parent.get_meta("palette", Color(0.55, 0.32, 0.12)) if parent.has_meta("palette") else Color(0.55, 0.32, 0.12)
		top_mat = std_material(pal, 0.9)
		pants_mat = std_material(Color(0.23, 0.24, 0.26), 0.95)

	var bones := {}
	var rig := Node3D.new()
	rig.name = "Rig"
	parent.add_child(rig)

	var hips := Node3D.new()
	hips.name = "Hips"
	hips.position = Vector3(0, 0.96, 0)
	rig.add_child(hips)
	bones["hips"] = hips
	bones["rig"] = rig

	# pelvis (clothed)
	var pelvis := torso_section(0.30, 0.28, 0.18, 0.72, pants_mat)
	pelvis.position = Vector3(0, 0.02, 0)
	hips.add_child(pelvis)

	var spine := Node3D.new()
	spine.name = "Spine"
	spine.position = Vector3(0, 0.12, 0)
	hips.add_child(spine)
	bones["spine"] = spine
	var waist := torso_section(0.28, 0.30, 0.20, 0.70, top_mat if is_corley else top_mat)
	waist.position = Vector3(0, 0.10, 0)
	spine.add_child(waist)

	var chest := Node3D.new()
	chest.name = "Chest"
	chest.position = Vector3(0, 0.22, 0)
	spine.add_child(chest)
	bones["chest"] = chest
	var chest_mesh := torso_section(0.32 if is_corley else 0.36, 0.28, 0.24, 0.68, top_mat)
	chest_mesh.position = Vector3(0, 0.10, 0)
	chest.add_child(chest_mesh)
	if is_corley:
		# subtle clothed chest shaping under the tank (single flattened form,
		# reads as torso at third-person distance, no prominent geometry)
		var b := SphereMesh.new()
		b.radius = 0.075
		b.height = 0.13
		var bmi := MeshInstance3D.new()
		bmi.mesh = b
		bmi.material_override = top_mat
		bmi.position = Vector3(0, 0.11, 0.055)
		bmi.scale = Vector3(1.5, 1.0, 0.55)
		chest.add_child(bmi)

	var neck := Node3D.new()
	neck.name = "Neck"
	neck.position = Vector3(0, 0.24, 0)
	chest.add_child(neck)
	bones["neck"] = neck
	var neck_mesh := tapered_limb(0.05, 0.055, 0.08, skin_mat, 10)
	neck.add_child(neck_mesh)

	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.10, 0)
	neck.add_child(head)
	bones["head"] = head
	# cranium: ovoid (wider top, tapered jaw)
	var cranium := SphereMesh.new()
	cranium.radius = 0.105
	cranium.height = 0.24
	cranium.radial_segments = 16
	cranium.rings = 12
	var cranium_mi := MeshInstance3D.new()
	cranium_mi.mesh = cranium
	cranium_mi.material_override = skin_mat
	cranium_mi.position = Vector3(0, 0.10, 0.01)
	cranium_mi.scale = Vector3(0.88, 1.0, 0.94)
	head.add_child(cranium_mi)
	# jaw taper
	var jaw := SphereMesh.new()
	jaw.radius = 0.075
	jaw.height = 0.12
	var jaw_mi := MeshInstance3D.new()
	jaw_mi.mesh = jaw
	jaw_mi.material_override = skin_mat
	jaw_mi.position = Vector3(0, 0.015, 0.025)
	jaw_mi.scale = Vector3(0.9, 0.8, 0.9)
	head.add_child(jaw_mi)
	# nose (tiny wedge)
	var nose_mesh := PrismMesh.new()
	nose_mesh.size = Vector3(0.025, 0.045, 0.03)
	var nose_mi := MeshInstance3D.new()
	nose_mi.mesh = nose_mesh
	nose_mi.material_override = skin_mat
	nose_mi.position = Vector3(0, 0.075, 0.115)
	head.add_child(nose_mi)
	# eyes (small, inset, dark)
	var eye_mat := std_material(Color(0.12, 0.09, 0.08), 0.4)
	for sx in [-1.0, 1.0]:
		var e := SphereMesh.new()
		e.radius = 0.013
		e.height = 0.026
		var emi := MeshInstance3D.new()
		emi.mesh = e
		emi.material_override = eye_mat
		emi.position = Vector3(sx * 0.038, 0.105, 0.093)
		head.add_child(emi)
	# hair: cap + sides + back length (Corley dark, shoulder-length wet look)
	var hair_top := SphereMesh.new()
	hair_top.radius = 0.112
	hair_top.height = 0.20
	var hair_top_mi := MeshInstance3D.new()
	hair_top_mi.mesh = hair_top
	hair_top_mi.material_override = hair_mat
	hair_top_mi.position = Vector3(0, 0.135, -0.018)
	hair_top_mi.scale = Vector3(0.95, 0.9, 1.0)
	head.add_child(hair_top_mi)
	var hair_back := CylinderMesh.new()
	hair_back.top_radius = 0.085
	hair_back.bottom_radius = 0.06 if is_corley else 0.05
	hair_back.height = 0.26 if is_corley else 0.10
	var hair_back_mi := MeshInstance3D.new()
	hair_back_mi.mesh = hair_back
	hair_back_mi.material_override = hair_mat
	hair_back_mi.position = Vector3(0, -0.02, -0.09)
	hair_back_mi.rotation_degrees.x = 6.0
	head.add_child(hair_back_mi)

	# arms
	for side in [-1.0, 1.0]:
		var sname := "L" if side < 0.0 else "R"
		var shoulder := Node3D.new()
		shoulder.name = "Shoulder" + sname
		shoulder.position = Vector3(side * 0.19, 0.19, 0)
		chest.add_child(shoulder)
		bones["shoulder_" + sname] = shoulder
		var deltoid := joint_ball(0.062, top_mat)
		shoulder.add_child(deltoid)
		var upper := Node3D.new()
		upper.name = "UpperArm" + sname
		upper.position = Vector3(0, -0.03, 0)
		shoulder.add_child(upper)
		bones["upper_" + sname] = upper
		var upper_mesh := tapered_limb(0.058, 0.048, 0.28, skin_mat if is_corley else top_mat)
		upper.add_child(upper_mesh)
		var elbow := Node3D.new()
		elbow.name = "Elbow" + sname
		elbow.position = Vector3(0, -0.28, 0)
		upper.add_child(elbow)
		bones["elbow_" + sname] = elbow
		var elbow_ball := joint_ball(0.045, skin_mat if is_corley else top_mat)
		elbow.add_child(elbow_ball)
		var fore_mesh := tapered_limb(0.046, 0.038, 0.26, skin_mat)
		elbow.add_child(fore_mesh)
		var wrist := Node3D.new()
		wrist.name = "Wrist" + sname
		wrist.position = Vector3(0, -0.26, 0)
		elbow.add_child(wrist)
		bones["wrist_" + sname] = wrist
		var hand := SphereMesh.new()
		hand.radius = 0.045
		hand.height = 0.11
		var hand_mi := MeshInstance3D.new()
		hand_mi.mesh = hand
		hand_mi.material_override = skin_mat
		hand_mi.position = Vector3(0, -0.05, 0)
		hand_mi.scale = Vector3(0.8, 1.2, 0.9)
		wrist.add_child(hand_mi)

	# legs
	for side in [-1.0, 1.0]:
		var sname2 := "L" if side < 0.0 else "R"
		var thigh := Node3D.new()
		thigh.name = "Thigh" + sname2
		thigh.position = Vector3(side * 0.095, -0.06, 0)
		hips.add_child(thigh)
		bones["thigh_" + sname2] = thigh
		var thigh_mesh := tapered_limb(0.082, 0.062, 0.42, pants_mat, 12)
		thigh.add_child(thigh_mesh)
		var knee := Node3D.new()
		knee.name = "Knee" + sname2
		knee.position = Vector3(0, -0.42, 0)
		thigh.add_child(knee)
		bones["knee_" + sname2] = knee
		var knee_ball := joint_ball(0.058, pants_mat)
		knee.add_child(knee_ball)
		var shin_mesh := tapered_limb(0.058, 0.045, 0.40, pants_mat if not is_corley else skin_mat if false else pants_mat, 12)
		knee.add_child(shin_mesh)
		var ankle := Node3D.new()
		ankle.name = "Ankle" + sname2
		ankle.position = Vector3(0, -0.40, 0)
		knee.add_child(ankle)
		bones["ankle_" + sname2] = ankle
		# boot: foot box forward + sole
		var boot := BoxMesh.new()
		boot.size = Vector3(0.095, 0.08, 0.24)
		var boot_mi := MeshInstance3D.new()
		boot_mi.mesh = boot
		boot_mi.material_override = boot_mat
		boot_mi.position = Vector3(0, -0.045, 0.06)
		ankle.add_child(boot_mi)

	# cast shadows on, cull reasonable
	for c in rig.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	return {"bones": bones, "rig": rig, "hips_base_y": 0.96}
