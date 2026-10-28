extends MeshInstance3D
## Open early enough for a walker; hold until the whole flight has passed.
var closed:=Transform3D.IDENTITY
var opening:=0.0
var hold:=0.0
var swing_sign:=1.0
func _ready()->void:
	configure()
func configure()->void:
	closed=transform
	swing_sign=-1.0 if String(name).begins_with("DOORLEAF_R") else 1.0
func _process(delta:float)->void:
	var near:=false
	for person:Node3D in get_tree().get_nodes_in_group("club_people"):
		if not person.is_visible_in_tree():continue
		var p:=global_transform.affine_inverse()*person.global_position
		if absf(p.y)<2.6 and Vector2(p.x,p.z).length()<2.7:
			near=true;break
	hold=1.0 if near else maxf(0,hold-delta)
	opening=move_toward(opening,1.0 if hold>0 else 0.0,delta*2.5)
	var eased:=opening*opening*(3-2*opening)
	transform=closed*Transform3D(Basis(Vector3.UP,swing_sign*eased*PI*.49),Vector3.ZERO)
