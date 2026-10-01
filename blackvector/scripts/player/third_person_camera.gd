# third_person_camera.gd — yaw pivot -> pitch pivot -> SpringArm3D -> Camera3D.
class_name ThirdPersonCamera
extends Node3D

var yaw := 0.0
var pitch := -0.32
var target: Node3D
var yaw_node: Node3D
var pitch_node: Node3D
var spring: SpringArm3D
var cam: Camera3D
var crouch_offset := 0.0

func setup(follow: Node3D) -> void:
	target = follow
	yaw_node = Node3D.new()
	yaw_node.name = "YawPivot"
	add_child(yaw_node)
	pitch_node = Node3D.new()
	pitch_node.name = "PitchPivot"
	yaw_node.add_child(pitch_node)
	spring = SpringArm3D.new()
	spring.name = "SpringArm"
	spring.spring_length = 3.4
	spring.margin = 0.3
	spring.rotation_degrees.x = 0.0
	pitch_node.add_child(spring)
	cam = Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 65.0
	cam.near = 0.08
	cam.far = 400.0
	spring.add_child(cam)
	# start behind player
	yaw = target.rotation.y if target else 0.0

func _process(delta: float) -> void:
	if not target:
		return
	global_position = global_position.lerp(target.global_position + Vector3(0, 1.45 - crouch_offset, 0), minf(1.0, 12.0 * delta))
	yaw_node.rotation.y = yaw
	pitch_node.rotation.x = pitch
	# feed yaw to player for camera-relative movement
	if target and target.has_method("set"):
		target.set("cam_yaw", yaw)
	# smooth crouch follow height
	var want_crouch := 0.0
	if "crouch_amount" in target:
		want_crouch = float(target.get("crouch_amount")) * 0.45
	crouch_offset = lerpf(crouch_offset, want_crouch, minf(1.0, 6.0 * delta))

func add_look(dyaw: float, dpitch: float) -> void:
	yaw -= dyaw * 0.0042
	pitch = clampf(pitch - dpitch * 0.0042, -1.05, 0.55)

func _ready() -> void:
	# desktop mouse look fallback
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
