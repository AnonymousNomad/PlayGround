# world_builder.gd — ONE polished wilderness slice: shoreline + creek + boreal
# forest + clearing + cabin + trail + camp + hidden route. All procedural,
# project-owned. Provides height_at(), ground_surface_at(), interactables.
class_name WorldBuilder
extends Node3D

var game = null
var terrain_body: StaticBody3D
var interactables: Array = [] # {id,label,pos,radius,action,data}
var fire_lit := false
var fire_pos := Vector3(20, 0, -12)
var cabin_door: Node3D
var door_open := false
var creek_points: Array = [] # Vector3 water ribbon centers
var rng := RandomNumberGenerator.new()

const SEA_Y := 0.02

func height_at(x: float, z: float) -> float:
	# base rolling
	var h := 2.0 + sin(x * 0.08) * cos(z * 0.07) * 1.4 + sin(x * 0.23 + z * 0.19) * 0.35
	# upland rise to the north
	h += clampf((-z - 10.0) * 0.06, 0.0, 5.0)
	# shoreline: descend toward sea for z > 24
	if z > 24.0:
		var k := clampf((z - 24.0) / 12.0, 0.0, 1.0)
		h = lerpf(h, -2.2, k * k * (3.0 - 2.0 * k))
	# creek carve along x = -8 + z*0.12
	var creek_x := -8.0 + z * 0.12
	var dc: float = absf(x - creek_x)
	if dc < 3.0 and z < 26.0 and z > -55.0:
		var depth := 0.7 * (1.0 - dc / 3.0)
		h -= depth
	# clearing flatten near (0,-6)
	var d_clear := Vector2(x - 0.0, z + 6.0).length()
	if d_clear < 13.0:
		h = lerpf(2.1, h, smoothstep(0.0, 13.0, d_clear))
	# cabin knoll flatten near (20,-14)
	var d_cab := Vector2(x - 20.0, z + 14.0).length()
	if d_cab < 10.0:
		h = lerpf(3.1, h, smoothstep(2.0, 10.0, d_cab))
	# trail gentle: shallow dip toward trail line from shore (6,30)->(0,6)->(8,-2)->(20,-14)
	h -= 0.12 * trail_influence(x, z)
	return h

func trail_influence(x: float, z: float) -> float:
	var pts := [Vector2(6, 32), Vector2(2, 18), Vector2(0, 6), Vector2(8, -3), Vector2(20, -14)]
	var best := 1000.0
	for i in range(pts.size() - 1):
		best = minf(best, _seg_dist(Vector2(x, z), pts[i], pts[i + 1]))
	return clampf(1.0 - best / 2.2, 0.0, 1.0)

func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return (p - (a + ab * t)).length()

func ground_surface_at(p: Vector3) -> String:
	# cabin wood floor zone
	if Vector2(p.x - 20.0, p.z + 14.0).length() < 3.4 and p.y > 3.0:
		return "wood"
	var h := height_at(p.x, p.z)
	if p.y < 0.25 and (p.z > 22.0 or absf(p.x - (-8.0 + p.z * 0.12)) < 2.2):
		return "water"
	if p.z > 21.0:
		return "gravel"
	if trail_influence(p.x, p.z) > 0.55:
		return "mud"
	# rock exposure on steep slope: sample gradient
	var s := absf(height_at(p.x + 1.0, p.z) - h) + absf(height_at(p.x, p.z + 1.0) - h)
	if s > 0.55:
		return "rock"
	return "soil"

func build(g) -> void:
	game = g
	rng.seed = 1337
	_build_lighting()
	_build_terrain()
	_build_water()
	_build_forest()
	_build_rocks_grass()
	_build_trail_traces()
	_build_cabin()
	_build_field_camp()
	_register_core_interactables()

# ---------- lighting ----------
func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.45
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_bias = 0.04
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.35, 0.50, 0.62)
	psm.sky_horizon_color = Color(0.72, 0.78, 0.82)
	psm.ground_bottom_color = Color(0.18, 0.20, 0.20)
	psm.ground_horizon_color = Color(0.62, 0.68, 0.70)
	psm.sun_angle_max = 12.0
	sky.sky_material = psm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.52, 0.52, 0.50)
	e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.0
	e.fog_enabled = true
	e.fog_light_color = Color(0.68, 0.74, 0.78)
	e.fog_density = 0.0006
	e.fog_sky_affect = 0.3
	e.fog_height_density = 0.0
	e.glow_enabled = false
	e.ssao_enabled = false
	e.sdfgi_enabled = false
	env.environment = e
	add_child(env)

func _noise_tex(size: int = 256) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var n := 0.5 + 0.5 * sin(x * 0.35 + y * 0.21) * cos(x * 0.13 - y * 0.29)
			var v := int(200 + n * 55)
			img.set_pixel(x, y, Color8(v, v, v))
	return ImageTexture.create_from_image(img)

# ---------- terrain ----------
func _build_terrain() -> void:
	var nx := 110
	var nz := 110
	var sx := 140.0
	var sz := 140.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# grid vertices
	var verts: Array = []
	var colors: Array = []
	var uvs: Array = []
	for iz in nz + 1:
		for ix in nx + 1:
			var x := -sx * 0.5 + sx * float(ix) / float(nx)
			var z := -sz * 0.5 + sz * float(iz) / float(nz)
			var y := height_at(x, z)
			verts.append(Vector3(x, y, z))
			colors.append(_ground_color(x, z, y))
			uvs.append(Vector2(float(ix) / float(nx), float(iz) / float(nz)))
	# triangles wound for UP normals (Godot front-face convention)
	for iz in nz:
		for ix in nx:
			var a: int = iz * (nx + 1) + ix
			var b: int = a + 1
			var c: int = a + (nx + 1)
			var d: int = c + 1
			for tri in [[a, b, c], [b, d, c]]:
				for vi in tri:
					st.set_color(colors[vi])
					st.set_uv(uvs[vi])
					st.add_vertex(verts[vi])
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mi.material_override = mat
	add_child(mi)
	terrain_body = StaticBody3D.new()
	terrain_body.name = "TerrainBody"
	# HeightMap collision (robust + cheap on mobile; concave-from-mesh proved
	# unreliable). Grid matches the visual mesh 1:1.
	var hm := HeightMapShape3D.new()
	hm.map_width = nx + 1
	hm.map_depth = nz + 1
	var hd := PackedFloat32Array()
	hd.resize((nx + 1) * (nz + 1))
	for iz in nz + 1:
		for ix in nx + 1:
			var hx := -sx * 0.5 + sx * float(ix) / float(nx)
			var hz := -sz * 0.5 + sz * float(iz) / float(nz)
			hd[iz * (nx + 1) + ix] = height_at(hx, hz)
	hm.map_data = hd
	var col := CollisionShape3D.new()
	col.shape = hm
	terrain_body.add_child(col)
	terrain_body.scale = Vector3(sx / float(nx), 1.0, sz / float(nz))
	add_child(terrain_body)

func _ground_color(x: float, z: float, y: float) -> Color:
	# soft large patches (low-frequency noise; avoids texel/vertex speckle)
	var n := 0.5 + 0.5 * sin(x * 0.15 + z * 0.11) * cos(x * 0.09 - z * 0.13)
	var n2 := 0.5 + 0.5 * sin(x * 0.45 - z * 0.31) * cos(x * 0.27 + z * 0.39)
	var soil := Color(0.29, 0.22, 0.12)
	var grass := Color(0.20, 0.28, 0.10)
	var moss := Color(0.14, 0.24, 0.11)
	var mud := Color(0.24, 0.18, 0.11)
	var gravel := Color(0.40, 0.37, 0.32)
	var rock := Color(0.33, 0.32, 0.32)
	var wet := Color(0.22, 0.20, 0.16)
	var g := smoothstep(0.35, 0.65, n * 0.8 + n2 * 0.2)
	var c: Color = soil.lerp(grass, g)
	# moss near creek
	var creek_x := -8.0 + z * 0.12
	if absf(x - creek_x) < 5.0:
		c = c.lerp(moss, 0.55)
	# wet band near water level
	if y < 0.45:
		c = c.lerp(wet, clampf((0.45 - y) * 1.6, 0.0, 0.85))
	# shore gravel
	if z > 20.0 and y > 0.1:
		c = c.lerp(gravel, clampf((z - 20.0) / 8.0, 0.0, 0.8))
	# trail mud
	c = c.lerp(mud, trail_influence(x, z) * 0.7)
	# rock on steep
	var s := absf(height_at(x + 1.0, z) - y) + absf(height_at(x, z + 1.0) - y)
	if s > 0.5:
		c = c.lerp(rock, clampf((s - 0.5) * 1.4, 0.0, 0.8))
	# slight variation
	var v := (n - 0.5) * 0.07
	c.r += v
	c.g += v
	c.b += v
	return c

# ---------- water ----------
func _water_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
uniform vec4 shallow : source_color = vec4(0.10, 0.16, 0.17, 0.88);
uniform vec4 deep : source_color = vec4(0.03, 0.07, 0.09, 0.94);
uniform float time_scale = 0.6;
void vertex() { VERTEX.y += sin(VERTEX.x * 1.3 + TIME * 1.2) * 0.015 + cos(VERTEX.z * 1.7 + TIME * 0.9) * 0.015; }
void fragment() {
  float w1 = sin(UV.x * 40.0 + TIME * 1.4) * cos(UV.y * 34.0 - TIME * 1.1);
  float w2 = sin((UV.x + UV.y) * 55.0 - TIME * 1.8);
  float m = clamp(0.5 + (w1 + w2) * 0.13, 0.0, 1.0);
  vec4 col = mix(deep, shallow, m * 0.45);
  ALBEDO = col.rgb;
  ALPHA = col.a;
  ROUGHNESS = 0.18;
  SPECULAR = 0.65;
  METALLIC = 0.05;
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m
func _build_water() -> void:
	var wmat := _water_material()
	# sea: extends past horizon so no hard far edge
	var sea := PlaneMesh.new()
	sea.size = Vector2(280, 130)
	var sea_mi := MeshInstance3D.new()
	sea_mi.mesh = sea
	sea_mi.material_override = wmat
	sea_mi.position = Vector3(0, SEA_Y, 75)
	add_child(sea_mi)
	# creek ribbon
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := 1.5
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var first := true
	for i in range(40):
		var z := 26.0 - float(i) * 2.0
		if z < -52.0:
			break
		var cx := -8.0 + z * 0.12
		var wl := maxf(height_at(cx - half, z), height_at(cx + half, z)) + 0.10
		wl = minf(wl, height_at(cx, z) + 0.45)
		var l := Vector3(cx - half, wl, z)
		var r := Vector3(cx + half, wl, z)
		creek_points.append(Vector3(cx, wl, z))
		if not first:
			# two tris wound for UP normals (path runs toward -Z)
			var u0 := float(i - 1) * 0.4
			var u1 := float(i) * 0.4
			st.set_uv(Vector2(0, u0)); st.add_vertex(prev_l)
			st.set_uv(Vector2(1, u0)); st.add_vertex(prev_r)
			st.set_uv(Vector2(0, u1)); st.add_vertex(l)
			st.set_uv(Vector2(1, u0)); st.add_vertex(prev_r)
			st.set_uv(Vector2(1, u1)); st.add_vertex(r)
			st.set_uv(Vector2(0, u1)); st.add_vertex(l)
		prev_l = l
		prev_r = r
		first = false
	st.generate_normals()
	var creek_mesh := st.commit()
	var creek_mi := MeshInstance3D.new()
	creek_mi.mesh = creek_mesh
	creek_mi.material_override = wmat
	add_child(creek_mi)

# ---------- forest / rocks / grass ----------
func _trunk_mesh() -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.14
	c.bottom_radius = 0.24
	c.height = 3.2
	c.radial_segments = 8
	return c

func _canopy_mesh(kind: int) -> Mesh:
	# displaced blob clusters assembled via append_from (keeps valid triangles).
	# Spruce = 3 stacked squashed blobs (NOT cones); birch = 1 round crown.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blobs := []
	if kind == 0:
		blobs = [[0.0, 2.6, 0.0, 1.5, 0.78], [0.0, 3.6, 0.0, 1.15, 0.85], [0.0, 4.5, 0.0, 0.8, 0.9]]
	elif kind == 1:
		blobs = [[0.0, 3.4, 0.0, 1.35, 1.0]]
	else:
		blobs = [[0.0, 3.0, 0.0, 1.0, 0.9]]
	var r := RandomNumberGenerator.new()
	r.seed = 1000 + kind
	for b in blobs:
		var sph := SphereMesh.new()
		sph.radius = float(b[3])
		sph.height = float(b[3]) * 1.5
		sph.radial_segments = 10
		sph.rings = 6
		var xf := Transform3D(Basis().scaled(Vector3(1.0, float(b[4]), 1.0)), Vector3(float(b[0]), float(b[1]), float(b[2])))
		st.append_from(sph, 0, xf)
	st.generate_normals()
	return st.commit()

func _valid_tree_spot(x: float, z: float) -> bool:
	var y := height_at(x, z)
	if y < 0.35:
		return false # water/shore
	var creek_x := -8.0 + z * 0.12
	if absf(x - creek_x) < 2.6:
		return false
	if Vector2(x, z + 6.0).length() < 9.0:
		return false # clearing
	if Vector2(x - 20.0, z + 14.0).length() < 8.0:
		return false # cabin
	if trail_influence(x, z) > 0.6:
		return false
	if Vector2(x - 12.0, z - 6.0).length() < 4.0:
		return false # camp
	# hidden route gap near (26,-20): keep a narrow corridor
	if absf(x - 26.0) < 1.6 and z > -26.0 and z < -12.0:
		return false
	return true

func _build_forest() -> void:
	var trunk := _trunk_mesh()
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.19, 0.13, 0.09)
	trunk_mat.roughness = 0.95
	var canopy_mats := []
	for col in [Color(0.11, 0.20, 0.10), Color(0.14, 0.23, 0.10), Color(0.08, 0.15, 0.09)]:
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.9
		canopy_mats.append(m)
	var spots: Array = []
	var tries := 0
	while spots.size() < 190 and tries < 3000:
		tries += 1
		var x := rng.randf_range(-65, 65)
		var z := rng.randf_range(-60, 30)
		# clustering: accept more readily near existing spots
		if not _valid_tree_spot(x, z):
			continue
		spots.append(Vector3(x, height_at(x, z) - 0.15, z))
	# trunks multimesh
	var mm_trunk := MultiMesh.new()
	mm_trunk.transform_format = MultiMesh.TRANSFORM_3D
	mm_trunk.mesh = trunk
	mm_trunk.instance_count = spots.size()
	for i in spots.size():
		var s := 0.8 + rng.randf() * 0.7
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * (0.9 + rng.randf() * 0.4), s)), spots[i])
		mm_trunk.set_instance_transform(i, t)
	var mmi_t := MultiMeshInstance3D.new()
	mmi_t.multimesh = mm_trunk
	mmi_t.material_override = trunk_mat
	mmi_t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi_t)
	# canopies: 3 kinds cycled
	for kind in 3:
		var cm := _canopy_mesh(kind)
		if cm == null:
			continue
		var subset: Array = []
		for i in spots.size():
			if i % 3 == kind:
				subset.append(spots[i])
		if subset.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = cm
		mm.instance_count = subset.size()
		for j in subset.size():
			var sc := 0.85 + rng.randf() * 0.8
			var t2 := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), subset[j])
			mm.set_instance_transform(j, t2)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = canopy_mats[kind]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)
	# trunk collisions for a subset near gameplay (first 40) to bound physics cost
	for i in mini(40, spots.size()):
		var sb := StaticBody3D.new()
		sb.position = spots[i]
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.25
		cyl.height = 3.0
		cs.shape = cyl
		cs.position = Vector3(0, 1.5, 0)
		sb.add_child(cs)
		add_child(sb)
	# orange trail blazes on a few trees along trail
	var blaze_mat := StandardMaterial3D.new()
	blaze_mat.albedo_color = Color(0.85, 0.45, 0.10)
	blaze_mat.roughness = 0.8
	for tp: Vector2 in [Vector2(2, 18), Vector2(0, 6), Vector2(8, -3), Vector2(14, -9)]:
		var bx: float = tp.x + 1.8
		var bz: float = tp.y
		var blaze := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.12, 0.18)
		blaze.mesh = q
		blaze.material_override = blaze_mat
		blaze.position = Vector3(bx, height_at(bx, bz) + 1.5, bz)
		add_child(blaze)

func _rock_mesh() -> ArrayMesh:
	var sph := SphereMesh.new()
	sph.radius = 0.7
	sph.height = 0.85
	sph.radial_segments = 9
	sph.rings = 6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# slight non-uniform squash via transform (keeps valid indexed triangles)
	st.append_from(sph, 0, Transform3D(Basis().scaled(Vector3(1.15, 0.7, 0.9)), Vector3.ZERO))
	st.generate_normals()
	return st.commit()

func _build_rocks_grass() -> void:
	var rock_mesh := _rock_mesh()
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.26, 0.25, 0.24)
	rock_mat.roughness = 0.98
	var placements: Array = []
	# shore + creek + knoll clusters
	for i in 90:
		var x := 0.0
		var z := 0.0
		var pick := rng.randf()
		if pick < 0.4:
			x = rng.randf_range(-40, 40)
			z = rng.randf_range(20, 32)
		elif pick < 0.7:
			z = rng.randf_range(-40, 24)
			x = -8.0 + z * 0.12 + rng.randf_range(-4, 4)
		else:
			x = rng.randf_range(-30, 35)
			z = rng.randf_range(-35, 15)
		var y := height_at(x, z)
		if y < -0.4:
			continue
		placements.append(Vector3(x, y, z))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = rock_mesh
	mm.instance_count = placements.size()
	for i in placements.size():
		var p: Vector3 = placements[i]
		var s := 0.4 + rng.randf() * 1.4
		var buried := rng.randf_range(0.05, 0.35) * s
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * (0.6 + rng.randf() * 0.5), s * (0.7 + rng.randf() * 0.5))), p - Vector3(0, buried, 0))
		mm.set_instance_transform(i, t)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = rock_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)
	# grass tufts: crossed quads with procedural blade texture (wide base,
	# narrow tip — reads as undergrowth, not cones)
	var blade_img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for yy in 64:
		for xx in 64:
			var a := 0.0
			var bx := absf(float(xx) - 32.0) / 32.0
			var hfrac := float(yy) / 64.0 # 0 top .. 1 bottom
			if hfrac > 0.12 and bx < hfrac * 0.9:
				# a few vertical blade gaps
				var blade := sin(float(xx) * 0.9) * 0.5 + 0.5
				if blade > 0.25 or hfrac < 0.45:
					a = 1.0
			blade_img.set_pixel(xx, yy, Color(0.32, 0.46, 0.20, a))
	var blade_tex := ImageTexture.create_from_image(blade_img)
	var grass_mat := StandardMaterial3D.new()
	grass_mat.albedo_texture = blade_tex
	grass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	grass_mat.alpha_scissor_threshold = 0.5
	grass_mat.albedo_color = Color(0.55, 0.62, 0.45)
	grass_mat.roughness = 0.9
	grass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad_a := QuadMesh.new()
	quad_a.size = Vector2(0.7, 0.55)
	var tuft := SurfaceTool.new()
	tuft.begin(Mesh.PRIMITIVE_TRIANGLES)
	tuft.append_from(quad_a, 0, Transform3D.IDENTITY)
	tuft.append_from(quad_a, 0, Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3.ZERO))
	var tuft_mesh := tuft.commit()
	var gmm := MultiMesh.new()
	gmm.transform_format = MultiMesh.TRANSFORM_3D
	gmm.mesh = tuft_mesh
	var gcount := 650
	gmm.instance_count = gcount
	var gi := 0
	var guard := 0
	while gi < gcount and guard < 6000:
		guard += 1
		var x := rng.randf_range(-45, 40)
		var z := rng.randf_range(-45, 28)
		var y := height_at(x, z)
		if y < 0.3:
			continue
		if Vector2(x - 20.0, z + 14.0).length() < 7.0:
			continue
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * (0.7 + rng.randf() * 0.8)), Vector3(x, y + 0.22, z))
		gmm.set_instance_transform(gi, t)
		gi += 1
	gmm.instance_count = gi
	var gmmi := MultiMeshInstance3D.new()
	gmmi.multimesh = gmm
	gmmi.material_override = grass_mat
	gmmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gmmi)

# ---------- trail traces / camp ----------
func _wood_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m

func _box(pos: Vector3, size: Vector3, mat: Material, rot_y: float = 0.0, collide: bool = false) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = rot_y
	add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		sb.position = pos
		sb.rotation.y = rot_y
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(cs)
		add_child(sb)
	return mi

func _build_trail_traces() -> void:
	# weathered sign near (4,10)
	var post_mat := _wood_mat(Color(0.30, 0.24, 0.17))
	var sx := 4.0
	var sz := 10.0
	var sy := height_at(sx, sz)
	_box(Vector3(sx, sy + 0.7, sz), Vector3(0.12, 1.4, 0.12), post_mat, 0.0, true)
	var sign := _box(Vector3(sx, sy + 1.35, sz), Vector3(0.9, 0.4, 0.06), _wood_mat(Color(0.45, 0.36, 0.24)), 0.4, false)
	add_interactable("sign", "Read sign", Vector3(sx, sy + 1.0, sz), 2.6, "inspect_sign", {})
	# discarded fuel can + crate near (2,2)
	var red := _wood_mat(Color(0.55, 0.20, 0.12))
	_box(Vector3(2.0, height_at(2, 2) + 0.2, 2.0), Vector3(0.35, 0.4, 0.25), red, 0.5, true)
	add_interactable("fuelcan", "Inspect gear", Vector3(2.0, height_at(2, 2) + 0.4, 2.0), 2.4, "inspect_gear", {})
	# old camp trace: cold fire ring + log near (-3,-2)
	_old_fire_ring(Vector3(-3, height_at(-3, -2), -2), false)
	add_interactable("oldcamp", "Inspect old camp", Vector3(-3, height_at(-3, -2) + 0.5, -2), 2.6, "inspect_oldcamp", {})

func _old_fire_ring(p: Vector3, lit: bool) -> void:
	var stone_mat := _wood_mat(Color(0.4, 0.4, 0.4))
	for i in 8:
		var a := TAU * float(i) / 8.0
		_box(p + Vector3(cos(a) * 0.55, 0.08, sin(a) * 0.55), Vector3(0.22, 0.16, 0.18), stone_mat, a, false)
	_box(p + Vector3(0, 0.05, 0), Vector3(0.5, 0.08, 0.5), _wood_mat(Color(0.12, 0.10, 0.09)), 0.3, false)
	# log seat
	_box(p + Vector3(1.2, 0.25, 0.4), Vector3(1.6, 0.3, 0.35), _wood_mat(Color(0.32, 0.24, 0.16)), 0.5, true)

func _build_cabin() -> void:
	var cx := 20.0
	var cz := -14.0
	var cy := height_at(cx, cz)
	var wall := _wood_mat(Color(0.38, 0.30, 0.21))
	var wall_dark := _wood_mat(Color(0.28, 0.22, 0.15))
	var roof_mat := _wood_mat(Color(0.20, 0.18, 0.16))
	var trim := _wood_mat(Color(0.50, 0.42, 0.30))
	# floor platform + foundation skirt (grounds cabin on slope, no floating)
	_box(Vector3(cx, cy + 0.15, cz), Vector3(5.4, 0.3, 4.4), wall_dark, 0.0, true)
	_box(Vector3(cx, cy - 0.35, cz), Vector3(5.6, 1.1, 4.6), _wood_mat(Color(0.22, 0.20, 0.18)), 0.0, false)
	var wy := cy + 1.4
	# walls: south (door gap 1.0 wide center), north full, east (window gap), west full
	# south wall two segments
	_box(Vector3(cx - 1.7, wy, cz + 2.2), Vector3(2.0, 2.4, 0.18), wall, 0.0, true)
	_box(Vector3(cx + 1.7, wy, cz + 2.2), Vector3(2.0, 2.4, 0.18), wall, 0.0, true)
	_box(Vector3(cx, wy + 0.9, cz + 2.2), Vector3(1.4, 0.6, 0.18), wall, 0.0, true) # lintel
	# north
	_box(Vector3(cx, wy, cz - 2.2), Vector3(5.4, 2.4, 0.18), wall, 0.0, true)
	# west
	_box(Vector3(cx - 2.7, wy, cz), Vector3(0.18, 2.4, 4.4), wall, 0.0, true)
	# east with window gap (two segs + sill + header)
	_box(Vector3(cx + 2.7, wy, cz - 1.3), Vector3(0.18, 2.4, 1.8), wall, 0.0, true)
	_box(Vector3(cx + 2.7, wy, cz + 1.5), Vector3(0.18, 2.4, 1.4), wall, 0.0, true)
	_box(Vector3(cx + 2.7, wy - 0.75, cz + 0.15), Vector3(0.18, 0.5, 1.3), wall_dark, 0.0, false)
	_box(Vector3(cx + 2.7, wy + 0.85, cz + 0.15), Vector3(0.18, 0.7, 1.3), wall, 0.0, false)
	# gable triangles (prism approx via rotated boxes) + roof slabs
	var r1 := _box(Vector3(cx - 1.35, wy + 2.1, cz), Vector3(3.1, 0.14, 4.9), roof_mat, 0.0, false)
	r1.rotation.z = 0.5
	var r2 := _box(Vector3(cx + 1.35, wy + 2.1, cz), Vector3(3.1, 0.14, 4.9), roof_mat, 0.0, false)
	r2.rotation.z = -0.5
	_box(Vector3(cx, wy + 1.55, cz - 2.2), Vector3(5.4, 1.4, 0.16), wall, 0.0, false)
	_box(Vector3(cx, wy + 1.55, cz + 2.2), Vector3(5.4, 1.4, 0.16), wall, 0.0, false)
	# porch
	_box(Vector3(cx, cy + 0.1, cz + 3.4), Vector3(3.0, 0.2, 2.0), wall_dark, 0.0, true)
	# door (hinged left)
	cabin_door = Node3D.new()
	cabin_door.position = Vector3(cx - 0.6, wy - 0.1, cz + 2.2)
	add_child(cabin_door)
	var door_mi := MeshInstance3D.new()
	var db := BoxMesh.new()
	db.size = Vector3(1.15, 2.1, 0.08)
	door_mi.mesh = db
	door_mi.material_override = trim
	door_mi.position = Vector3(0.575, 0.0, 0)
	cabin_door.add_child(door_mi)
	# interior: bunk, workbench, stove, crates, stool, shelf, clothes pile, lantern
	_box(Vector3(cx - 1.6, cy + 0.65, cz - 1.2), Vector3(1.2, 0.35, 2.0), _wood_mat(Color(0.42, 0.33, 0.22)), 0.0, true)
	_box(Vector3(cx + 1.4, cy + 0.9, cz - 1.4), Vector3(1.8, 0.12, 0.7), trim, 0.0, true) # workbench top
	_box(Vector3(cx + 0.7, cy + 0.5, cz - 1.4), Vector3(0.12, 0.8, 0.6), wall_dark, 0.0, false)
	_box(Vector3(cx + 2.1, cy + 0.5, cz - 1.4), Vector3(0.12, 0.8, 0.6), wall_dark, 0.0, false)
	# stove (metal box + pipe) at west
	var metal := _wood_mat(Color(0.15, 0.15, 0.16))
	_box(Vector3(cx - 2.0, cy + 0.7, cz + 0.8), Vector3(0.7, 0.7, 0.7), metal, 0.0, true)
	fire_pos = Vector3(cx - 2.0, cy + 0.45, cz + 0.8)
	# crates + stool + shelf
	_box(Vector3(cx + 1.8, cy + 0.55, cz + 1.2), Vector3(0.6, 0.5, 0.6), _wood_mat(Color(0.46, 0.37, 0.25)), 0.3, true)
	_box(Vector3(cx + 1.8, cy + 1.05, cz + 1.2), Vector3(0.45, 0.4, 0.45), _wood_mat(Color(0.40, 0.32, 0.22)), 0.7, false)
	_box(Vector3(cx - 0.2, cy + 0.55, cz + 0.6), Vector3(0.4, 0.4, 0.4), wall_dark, 0.2, true) # stool
	_box(Vector3(cx + 2.4, cy + 1.5, cz - 0.2), Vector3(0.3, 0.06, 1.6), trim, 0.0, false)
	# fishing rod leaning (thin cylinder) + tackle
	var rod := CylinderMesh.new()
	rod.top_radius = 0.008
	rod.bottom_radius = 0.02
	rod.height = 2.2
	var rod_mi := MeshInstance3D.new()
	rod_mi.mesh = rod
	rod_mi.material_override = _wood_mat(Color(0.30, 0.22, 0.14))
	rod_mi.position = Vector3(cx + 2.3, cy + 1.3, cz + 1.6)
	rod_mi.rotation.z = 0.25
	add_child(rod_mi)
	# fire light + particles (unlit initially)
	var fl := OmniLight3D.new()
	fl.name = "FireLight"
	fl.position = fire_pos + Vector3(0, 0.6, 0)
	fl.light_color = Color(1.0, 0.55, 0.25)
	fl.light_energy = 0.0
	fl.omni_range = 9.0
	add_child(fl)
	var parts := GPUParticles3D.new()
	parts.name = "FireParticles"
	parts.position = fire_pos + Vector3(0, 0.5, 0)
	parts.amount = 24
	parts.lifetime = 0.8
	parts.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 18.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.12
	pm.scale_max = 0.3
	pm.color = Color(1.0, 0.55, 0.2)
	parts.process_material = pm
	var quadp := QuadMesh.new()
	quadp.size = Vector2(0.25, 0.25)
	parts.draw_pass_1 = quadp
	add_child(parts)
	# interactables
	add_interactable("door", "Open door", Vector3(cx, wy - 0.2, cz + 2.6), 2.6, "toggle_door", {})
	add_interactable("clothes", "Take dry clothes", Vector3(cx - 1.6, cy + 1.0, cz - 1.2), 2.2, "take_clothes", {})
	add_interactable("fire", "Light fire", Vector3(cx - 2.0, cy + 0.8, cz + 0.8), 2.4, "light_fire", {})
	add_interactable("rest", "Rest until morning", Vector3(cx - 1.6, cy + 1.0, cz - 1.2), 2.2, "rest", {})
	add_interactable("workbench", "Inspect workbench", Vector3(cx + 1.4, cy + 1.1, cz - 1.4), 2.2, "inspect_bench", {})

func _build_field_camp() -> void:
	var p := Vector3(12, 0, 6)
	p.y = height_at(p.x, p.z)
	_old_fire_ring(p, false)
	# lean-to: two posts + slanted roof plane
	var mat := _wood_mat(Color(0.34, 0.27, 0.19))
	_box(p + Vector3(-1.2, 0.9, -1.0), Vector3(0.12, 1.8, 0.12), mat, 0.0, true)
	_box(p + Vector3(1.2, 0.9, -1.0), Vector3(0.12, 1.8, 0.12), mat, 0.0, true)
	var roof := _box(p + Vector3(0, 1.5, 0.2), Vector3(2.8, 0.1, 2.6), _wood_mat(Color(0.30, 0.26, 0.18)), 0.0, false)
	roof.rotation.x = -0.35
	add_interactable("campfire", "Light camp fire", p + Vector3(0, 0.4, 0), 2.6, "light_fire", {"camp": true})

# ---------- interactables ----------
func add_interactable(id: String, label: String, pos: Vector3, radius: float, action: String, data: Dictionary) -> void:
	interactables.append({"id": id, "label": label, "pos": pos, "radius": radius, "action": action, "data": data})

func nearest_interactable(p: Vector3, for_rest_stage: String = "") -> Dictionary:
	var best := {}
	var bd := 1e9
	for it in interactables:
		# gate rest/fire/clothes by opening stage handled in game.gd via metadata; here pure distance
		var d: float = p.distance_to(it["pos"])
		if d < float(it["radius"]) and d < bd:
			# door label dynamic
			bd = d
			best = it
	if not best.is_empty() and best["id"] == "door":
		best = best.duplicate()
		best["label"] = "Close door" if door_open else "Open door"
	if not best.is_empty() and best["id"] == "fire" and fire_lit:
		best = best.duplicate()
		best["label"] = "Warm hands"
	return best

func try_player_interact(player: Node3D) -> bool:
	var it := nearest_interactable(player.global_position)
	if it.is_empty():
		return false
	if game and game.has_method("do_interact"):
		game.do_interact(it["action"], it)
		return true
	return false

func player_strike(player: Node3D) -> void:
	if game and game.has_method("resolve_strike"):
		game.resolve_strike(player)

func set_fire_lit(v: bool) -> void:
	fire_lit = v
	var fl: OmniLight3D = get_node_or_null("FireLight") as OmniLight3D
	var parts: GPUParticles3D = get_node_or_null("FireParticles") as GPUParticles3D
	if fl:
		fl.light_energy = 2.2 if v else 0.0
	if parts:
		parts.emitting = v

func toggle_door() -> void:
	door_open = not door_open
	if cabin_door:
		var tw := create_tween()
		tw.tween_property(cabin_door, "rotation:y", -1.9 if door_open else 0.0, 0.5)

func _register_core_interactables() -> void:
	# awakening debris near spawn
	var sx := 6.0
	var sz2 := 30.0
	add_interactable("debris", "Inspect wreckage", Vector3(sx + 1.5, 0.6, sz2 - 1.0), 2.6, "inspect_debris", {})
