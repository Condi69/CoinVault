extends RefCounted

var materials: Dictionary = {}
var bolt_poses: Array[Transform3D] = []
var simple_parts: Array[Dictionary] = []

func material(kind: String) -> Material:
	if materials.has(kind):
		return materials[kind]
	var result := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform int surface_kind = 0;
uniform bool simple_surfaces = false;
varying vec3 world_point;
varying vec3 world_normal;
float hash21(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise21(vec2 p) {
 vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);
}
void vertex() {
 world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
 vec2 uv=abs(world_normal.y)>0.5 ? world_point.xz : (abs(world_normal.x)>0.5 ? world_point.zy : world_point.xy);
 float grain=0.0;
 if(!simple_surfaces) { grain=noise21(uv*13.0)*0.035+noise21(uv*2.7)*0.055; }
 ALBEDO=vec3(0.35); ROUGHNESS=0.8; METALLIC=0.0;
 if(surface_kind==0) {
  vec2 p=uv/vec2(0.66,0.29); p.x+=mod(floor(p.y),2.0)*0.5;
  vec2 cell=floor(p); vec2 f=fract(p);
  vec2 edge=min(f,1.0-f)*vec2(0.66,0.29);
  float distance=min(edge.x,edge.y);
  float aa=max(fwidth(distance),0.001);
  float joint=1.0-smoothstep(0.004-aa*0.35,0.014+aa*0.35,distance);
  float bevel=smoothstep(0.006,0.025,distance);
  vec3 brick=vec3(0.49,0.435,0.34)*(0.94+hash21(cell)*0.12)+grain;
  ALBEDO=mix(brick*(0.87+bevel*0.13),vec3(0.31,0.285,0.235),joint*0.75);
  float column=1.0-smoothstep(0.17,0.22,abs(mod(uv.x+6.0,12.0)-6.0));
  float plinth=1.0-smoothstep(0.38,0.46,world_point.y);
  float structure=max(column,plinth);
  vec2 panel=fract(uv/1.8); float seam=1.0-smoothstep(0.002,0.009,min(min(panel.x,1.0-panel.x),min(panel.y,1.0-panel.y)));
  ALBEDO=mix(ALBEDO,vec3(0.24,0.25,0.23)+grain*0.55,structure);
  ALBEDO*=1.0-seam*structure*0.22;
  AO=1.0-joint*0.18;
 } else if(surface_kind==1 || surface_kind==2) {
  float size=surface_kind==1 ? 1.65 : 1.9;
  vec2 p=uv/size; vec2 cell=floor(p); vec2 f=fract(p);
  float edge=min(min(f.x,1.0-f.x),min(f.y,1.0-f.y))*size;
  float aa=max(fwidth(edge),0.001);
  float seam=1.0-smoothstep(0.003-aa*0.3,0.016+aa*0.3,edge);
  vec3 color=surface_kind==1 ? vec3(0.43,0.405,0.335) : vec3(0.265,0.27,0.25);
  ALBEDO=color*(0.91+hash21(cell)*0.14)+grain;
  ALBEDO*=mix(1.0,0.48,seam);
  float rim=1.0-smoothstep(0.018,0.11,edge);
  ALBEDO*=1.0-rim*0.12;
  vec2 bolt=min(abs(f-vec2(0.11)),abs(f-vec2(0.89)))*size;
  float d=length(bolt);
  float ring=(1.0-smoothstep(0.025,0.038,d))*smoothstep(0.012,0.022,d);
  float hole=1.0-smoothstep(0.010,0.018,d);
  ALBEDO=mix(ALBEDO,vec3(0.19,0.185,0.16),ring*0.5+hole*0.8);
  ROUGHNESS=0.78+grain;
  AO=1.0-seam*0.25-hole*0.18;
 } else if(surface_kind==3) {
  float wear=0.5;
  if(!simple_surfaces) { wear=noise21(uv*3.0); }
  ALBEDO=mix(vec3(0.075,0.12,0.14),vec3(0.20,0.25,0.26),wear*0.36);
  METALLIC=0.65; ROUGHNESS=0.43;
 } else if(surface_kind==4) {
  ALBEDO=vec3(0.23,0.27,0.27)+grain*0.3;
  METALLIC=0.72; ROUGHNESS=0.35;
 } else if(surface_kind==5) {
  vec2 grip=fract(vec2(uv.x+uv.y,uv.x-uv.y)*10.0)-0.5;
  float ridge=1.0-smoothstep(0.07,0.15,abs(grip.x));
  ridge*=1.0-smoothstep(0.18,0.35,abs(grip.y));
  ALBEDO=vec3(0.10,0.135,0.14)+grain*0.3+ridge*0.055;
  METALLIC=0.62; ROUGHNESS=0.51;
 } else if(surface_kind==7) {
  ALBEDO=vec3(0.65,0.45,0.075); METALLIC=0.25; ROUGHNESS=0.56;
 } else {
  ALBEDO=vec3(0.34,0.235,0.105)+grain*0.3;
  METALLIC=0.72; ROUGHNESS=0.30;
 }
}
"""
	result.shader=shader
	var kinds := {"wall":0,"floor":1,"ceiling":2,"steel":3,"rail":4,"tread":5,"handrail":6,"safety":7}
	result.set_shader_parameter("surface_kind",kinds.get(kind,3))
	materials[kind]=result
	return result

func box(parent: Node3D, at: Vector3, size: Vector3, kind: String) -> MeshInstance3D:
	var part:=MeshInstance3D.new()
	var mesh:=BoxMesh.new()
	mesh.size=size
	part.mesh=mesh
	part.position=at
	part.material_override=material(kind)
	parent.add_child(part)
	simple_parts.append({"part":part,"kind":kind,"shape":"box"})
	return part

func tube(parent: Node3D, a: Vector3, b: Vector3, radius: float, kind: String) -> MeshInstance3D:
	var part:=MeshInstance3D.new()
	var mesh:=CylinderMesh.new()
	mesh.top_radius=radius
	mesh.bottom_radius=radius
	mesh.height=a.distance_to(b)
	mesh.radial_segments=12
	part.mesh=mesh
	part.transform=Transform3D(Basis(Quaternion(Vector3.UP,(b-a).normalized())),(a+b)*0.5)
	part.material_override=material(kind)
	parent.add_child(part)
	simple_parts.append({"part":part,"kind":kind,"shape":"tube"})
	return part

func foot(parent: Node3D, at: Vector3) -> void:
	box(parent,at+Vector3(0,0.02,0),Vector3(0.22,0.04,0.22),"steel")
	for x in [-0.073,0.073]:
		for z in [-0.073,0.073]:
			bolt_poses.append(parent.global_transform*Transform3D(Basis.IDENTITY,at+Vector3(x,0.05,z)))

func finish_fasteners(parent: Node3D) -> void:
	var multimesh:=MultiMesh.new()
	multimesh.transform_format=MultiMesh.TRANSFORM_3D
	var mesh:=CylinderMesh.new()
	mesh.top_radius=0.014
	mesh.bottom_radius=0.014
	mesh.height=0.018
	mesh.radial_segments=6
	multimesh.mesh=mesh
	multimesh.instance_count=bolt_poses.size()
	for index in range(bolt_poses.size()):
		multimesh.set_instance_transform(index,bolt_poses[index])
	var visual:=MultiMeshInstance3D.new()
	visual.name="RailingAnchorBolts"
	visual.multimesh=multimesh
	visual.material_override=material("rail")
	parent.add_child(visual)

func finish_batches(parent: Node3D) -> void:
	var groups: Dictionary={}
	for record in simple_parts:
		var part: MeshInstance3D=record.part
		var key: String=record.shape+"_"+record.kind
		if not groups.has(key):
			groups[key]={"shape":record.shape,"kind":record.kind,"poses":[]}
		var dimensions: Vector3=part.mesh.size if record.shape=="box" else Vector3(part.mesh.top_radius,part.mesh.height,part.mesh.top_radius)
		groups[key].poses.append(part.global_transform.scaled_local(dimensions))
		part.queue_free()
	for key in groups:
		var group: Dictionary=groups[key]
		var mesh: Mesh
		if group.shape=="box":
			var box_mesh:=BoxMesh.new()
			box_mesh.size=Vector3.ONE
			mesh=box_mesh
		else:
			var cylinder:=CylinderMesh.new()
			cylinder.top_radius=1.0
			cylinder.bottom_radius=1.0
			cylinder.height=1.0
			cylinder.radial_segments=12
			mesh=cylinder
		var mm:=MultiMesh.new()
		mm.transform_format=MultiMesh.TRANSFORM_3D
		mm.mesh=mesh
		mm.instance_count=group.poses.size()
		for index in range(mm.instance_count):
			mm.set_instance_transform(index,group.poses[index])
		var visual:=MultiMeshInstance3D.new()
		visual.name="Architecture_"+key
		visual.multimesh=mm
		visual.material_override=material(group.kind)
		parent.add_child(visual)
	simple_parts.clear()
