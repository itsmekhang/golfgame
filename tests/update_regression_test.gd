extends SceneTree
var failed := false
func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState: n.autosave = false)
	call_deferred("run")
func check(ok: bool, msg: String) -> void:
	if not ok:
		failed = true
		push_error(msg)
func run() -> void:
	var c := PaintedCourse.create("Update checks",Vector2i(400,400))
	c.holes.append({"tee":Vector2(60,0),"pin":Vector2(60,-100),"par":4,"bends":[],"curve":false})
	var b := CourseBusiness.create()
	b.built = {"clubhouse":4,"cart_barn":1,"short_game":3,"driving_range":1}
	b.rooms = {"spa_fitness":3,"locker_rooms":3,"office":1,"pro_shop":1}
	b.staff = {"cart_attendant":1,"range_attendant":1,"shop_clerk":1,"trainer":1}
	b.placements = {"clubhouse":{"pos":Vector2(-80,40),"rot":0.0},"cart_barn":{"pos":Vector2(0,110),"rot":0.0},"short_game":{"pos":Vector2(80,60),"rot":0.0},"driving_range":{"pos":Vector2(80,125),"rot":0.0}}
	var items: Array=[]
	for type in b.placements:
		items.append({"type":type,"level":b.level(type),"pos":b.placements[type]["pos"],"rot":0.0,"rooms":b.rooms})
	var built := FacilityBuilder.build(items,func(_p: Vector2) -> float: return 0.0,false,true)
	root.add_child(built)
	var life := ClubLife.new()
	root.add_child(life)
	life.set_process(false)
	life.course=c;life.business=b;life.facilities=built
	life.refresh()
	await process_frame
	if "--followups" in OS.get_cmdline_user_args():
		await followup_checks(life, built, c)
		life.clear();life.queue_free();built.queue_free()
		await process_frame
		print("FOLLOWUP CHECKS: ", "FAIL" if failed else "PASS")
		quit(1 if failed else 0)
		return
	var w := life._person("golfer_a")
	for clip in ["type","type_sit","hose","chip","carry","situp_in","situps","situp_out","kettlebell","front_raise","bench","spin","elliptical"]:
		check(w.anim.has_animation(clip),"Missing imported exercise/staff clip: "+clip)
	life._play(w,"spin")
	check(w.anim.get_playing_speed()<0,"Bike still uses backward crank direction")
	for use in ["guest_gym_stretch","guest_gym_sit","guest_gym_weights","guest_gym_kettlebell"]:
		var spots := life._free_places("spa_fitness",[use])
		check(not spots.is_empty(),"Missing gym station "+use)
		for place in spots:
			w.data["place"]=place
			life._use_place(w)
			if use=="guest_gym_stretch":
				check(w.data.has("mat_move"),"Exercise erased by held-prop cleanup")
				check(str(w.data.get("mat_move",""))=="situps","Something other than sit-ups on a mat: "+str(w.data.get("mat_move","")))
			elif use in ["guest_gym_weights","guest_gym_kettlebell"]:
				# by the rack and the kettlebells, holding them (user: not on a mat)
				check(w.data.has("gym_held"),"Nothing in hand at the weights: "+use)
				check(w.rest in (["front_raise", "gym/bicep_curl"] if use=="guest_gym_weights" else ["kettlebell"]),"Wrong exercise at "+use+": "+w.rest)
			else:
				if not w.data.has("rack_bar"):
					print("BENCH missing at ",place["xf"])
					for node in built.find_children("*bench*", "MultiMeshInstance3D",true,false):
						print("BENCH batch ",node.name," mesh ",node.multimesh.mesh.get_aabb()," first ",node.global_transform * node.multimesh.get_instance_transform(0))
				check(w.data.has("rack_bar"),"Bench did not unrack its own bar")
				var rack: Array=w.data.get("rack_bar",[])
				if rack.size()==3:
					check(rack[0].multimesh.get_instance_transform(rack[1]).basis.get_scale().x<0.01,"Duplicate bar still on rack")
					life._gym_off(w)
					check(rack[0].multimesh.get_instance_transform(rack[1]).is_equal_approx(rack[2]),"Bar not restored after exercise")
			life._gym_off(w)
	w.node.queue_free()
	var boys := life._staff.filter(func(p: ClubLife.Walker) -> bool: return p.data.get("role","")=="cart_attendant")
	check(boys.size()==1,"No cart attendant")
	var sprayed := false
	var wiped := false
	var washed := false
	for tick in range(3600):
		life._spawn_wait=1e9
		life._process(0.1)
		for boy: ClubLife.Walker in boys:
			var spraying: bool = boy.data.has("hose") and not (boy.data.get("steps",[]) as Array).is_empty() and str((boy.data["steps"] as Array)[0].get("do","")) == "wash" and (boy.data["steps"] as Array)[0].has("t")
			if boy.data.has("hose"):
				sprayed=true
			if spraying:
				check(boy.anim.current_animation=="hose","Hose job not playing Watering clip")  # (spraying: not carrying it over from the reel)
			if sprayed and boy.data.has("wash_cart") and not boy.data.has("hose"): wiped=true
		for cart: ClubLife.Walker in life._stock:
			if cart.data.has("washed_at"): washed=true
		for boy: ClubLife.Walker in boys:  # (or driven back into the barn, done: user)
			var st: Array = boy.data.get("steps",[])
			if not st.is_empty() and str(st[0].get("do","")) == "put_away": washed=true
		if washed: break
	check(sprayed and wiped and washed,"Cart attendant never completed hose + wipe + release")
	print("CART WASH observed: hose=",sprayed," wipe=",wiped," complete=",washed)
	var first := ClubLife.Group.new()
	var second := ClubLife.Group.new()
	b.hours=2.0
	check(life._record_tee_start(first),"First start refused")
	var gap := ClubLife.TEE_INTERVAL
	check(is_equal_approx(b.next_tee_hour,2.0+gap),"Tee interval is not 8 game minutes")
	b.hours=2.0+gap*0.5
	check(life._record_tee_start(first),"Same flight delayed between players")
	check(is_equal_approx(b.next_tee_hour,2.0+gap),"Second golfer moved next tee time")
	check(not life._record_tee_start(second),"Next flight started before its tee time")
	b.hours=2.0+gap
	check(life._record_tee_start(second),"Next flight blocked at its tee time")
	check(is_equal_approx(CourseBusiness.from_dict(b.to_dict()).next_tee_hour,2.0+gap*2.0),"Tee spacing lost on save/load")
	var head := life._new_group(0,false,0,2)
	var follower := life._new_group(0,false,0,2)
	for g: ClubLife.Group in [head,follower]:
		g.hole_reserved=false;g.phase="tee_queue";g.queue_hole=0
	head.queue_ticket=100;follower.queue_ticket=101
	life._groups=[head,follower]
	check(life._try_wait_practice(follower),"Following flight not sent to practice")
	check(life._tee_rank(follower)==1,"Practice flight lost its queue order")
	var third := life._new_group(0,false,0,2)
	third.hole_reserved=false;third.phase="tee_queue";third.queue_hole=0;third.queue_ticket=102
	life._groups.append(third)
	check(life._tee_rank(third)==2 and life._tee_entry_blocked(third),"Third flight overtook practicing flight")
	check(not life._try_wait_practice(head),"The first waiting flight left its tee position")
	print("UPDATE REGRESSION: ","FAIL" if failed else "PASS")
	life.clear();life.queue_free();built.queue_free()
	await process_frame
	quit(1 if failed else 0)


func followup_checks(life: ClubLife, built: Node3D, c: PaintedCourse) -> void:
	var house := built.get_node("clubhouse") as Node3D
	life._guest_nav(house)
	life._indoor_guest_nav(house)
	two_bikes_check(life)
	var stations := life._free_places("spa_fitness", ClubLife.GYM_USES)
	for place: Dictionary in stations:
		var step := life._place_step(place)
		var local := house.global_transform.affine_inverse() * Vector3(step.x, 0, step.y)
		var path := FacilityBuilder.nav_route(house, "indoor_guest", Vector2(0,12), Vector2(local.x,local.z))
		check(not path.is_empty(), "No indoor route to " + str(place["use"]))
		for p: Vector2 in path:
			check(p.y >= 10.4 and p.y <= 29.1 and p.x <= 40.1, "Gym route left the clubhouse through the patio")
		var crossed := false
		for i in range(1, path.size()):
			if path[i-1].x < 30 and path[i].x >= 30:
				var t := (30.0-path[i-1].x)/(path[i].x-path[i-1].x)
				var z := path[i-1].lerp(path[i],t).y
				crossed = z > 19.3 and z < 21.0
		check(crossed,"Gym route missed the interior gym door")
	print("GYM INDOOR ROUTES ", stations.size())
	for model in ["a", "d"]:
		var w := life._person("golfer_"+model)
		check(w.anim.has_animation("gym/bicep_curl"), "Missing curl for " + model)
		var sk := w.node.find_child("Skeleton3D",true,false) as Skeleton3D
		w.anim.play("gym/bicep_curl",0);w.anim.seek(0,true);w.anim.pause()
		var start := sk.get_bone_global_pose(sk.find_bone("hand.R")).origin
		var curl_travel := 0.0
		for i in range(8):
			w.anim.seek(w.anim.current_animation_length*i/8.0,true)
			curl_travel=maxf(curl_travel,start.distance_to(sk.get_bone_global_pose(sk.find_bone("hand.R")).origin))
		check(curl_travel>.03,"Curl hand never moves")
		print("CURL ",model," hand travel ",curl_travel," track ",w.anim.get_animation("gym/bicep_curl").track_get_path(0))
		var mat: Dictionary = life._free_places("spa_fitness",["guest_gym_stretch"])[0]
		w.data["place"]=mat;life._use_place(w)
		await process_frame
		for clip in ["situp_in","situps","situp_out"]:
			for i in range(5):
				w.anim.play(clip,0);w.anim.seek(w.anim.get_animation(clip).length*i/4.0,true);w.anim.pause()
				await process_frame
				life._mat_contact(w)
				var y := w.node.position.y
				life._mat_contact(w)
				check(is_equal_approx(y,w.node.position.y),"Mat grounding accumulated a height offset")
				if clip == "situps":
					check(absf(torso_bottom(w)-(mat["xf"] as Transform3D).origin.y)<.012,"Hips or back float above the mat during sit-ups")
				if DisplayServer.get_name() != "headless":
					var bottom := INF
					for mi in w.node.find_children("*","MeshInstance3D",true,false):
						if mi.skin == null:continue
						var mesh: ArrayMesh=mi.bake_mesh_from_current_skeleton_pose()
						for s in mesh.get_surface_count():
							for v: Vector3 in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]: bottom=minf(bottom,(mi.global_transform*v).y)
					check(absf(bottom-(mat["xf"] as Transform3D).origin.y)<.01,"Body floats above mat: "+str(bottom-(mat["xf"] as Transform3D).origin.y))
		life._gym_off(w);w.node.queue_free()
	print("CURL AND MAT CONTACT: both rigs, all three floor clips")
	for i in range(ClubLife.BAR_GUESTS):
		var visitor:=ClubLife.Walker.new();visitor.data["place"]={"use":"guest_bar"}
		life._guest_places["bar_test_"+str(i)]=visitor
	check(life._bar_guests()==4,"Bar limit does not count every reserved stool")
	life._guest_places.clear()
	var front: ClubLife.Walker=life._cart_boys()[0]
	var helper:=ClubLife.Walker.new();helper.node=Node3D.new();life.add_child(helper.node);helper.data["role"]="cart_attendant";life._staff.append(helper)
	var line:=life._line.duplicate()
	life._line[0]=null
	var job:=life._cart_job(front)
	check(not job.is_empty() and job.any(func(s:Dictionary)->bool:return s.get("do","")=="drive"),"Front attendant did not help refill a nearly full line")
	life._line=line;life._restocking=false
	for cart: ClubLife.Walker in life._pool:cart.data.erase("job")
	life._staff.erase(helper);helper.node.queue_free()
	var a:=life._cart();var b:=life._cart()
	life._pool.append_array([a,b]);a.speed=4;b.speed=4
	a.node.position=Vector3(20,0,0);b.node.position=Vector3(20,0,6)
	a.path=[Vector3(20,0,12)];b.path=[Vector3(20,0,-6)]
	var da:=life._person("staff_cart_attendant");var db:=life._person("staff_cart_attendant")
	life._seat(da,a,0);life._seat(db,b,0)
	var passed:=false
	for i in range(240):
		life._step(a,.1);life._step(b,.1)
		passed=passed or a.data.has("pass_route") or b.data.has("pass_route")
		var rel:=a.node.position-b.node.position
		check(absf(rel.x)>1.3 or absf(rel.z)>2.7,"Head-on carts overlap")
		if a.path.is_empty() and b.path.is_empty():break
	check(passed,"No cart pulled aside in a head-on meeting")
	check(a.path.is_empty() and b.path.is_empty(),"Cart failed to resume its delivery after passing")
	life._pool.erase(a);life._pool.erase(b);a.node.queue_free();b.node.queue_free()
	c.paint(PaintedCourse.Surface.WATER,Vector2(80,-50),14,1,1)
	var dry:=life._drop_dry(Vector2(80,-50),Vector2(80,-50),Vector2(130,-50))
	check(life._dry_footing(dry,1.2),"Hazard drop is still in water")
	var golfer:=ClubLife.Walker.new();golfer.data={"skill":1.0,"shape":0.0}
	var choice:=life._shot_choice(golfer,Vector2(20,-50),Vector2(80,-50))
	check(life._dry_footing(choice["target"],1.2),"Golf IQ chose a water landing")
	c.paint(PaintedCourse.Surface.WOODS,Vector2(85,0),8,1,1)
	choice=life._shot_choice(golfer,Vector2(20,0),Vector2(150,0))
	check((choice["curve"] as Vector2).length()>1,"Skilled golfer did not shape around the tree line")
	print("BAR LIMIT, FRONT REFILL, CART PASSING, DRY DROPS, SHOT SHAPING checked")

func torso_bottom(w:ClubLife.Walker)->float:
	var skel:Skeleton3D=w.node.find_child("Skeleton3D",true,false)
	var low:=INF
	for part:Array in w.data["mat_skin"]:
		var skin:Skin=part[0];var palette:Array[Transform3D]=[];var legs:Array[bool]=[]
		for i in skin.get_bind_count():
			var bone:=skel.find_bone(skin.get_bind_name(i));var name:=str(skel.get_bone_name(bone))
			legs.append(name.begins_with("thigh.") or name.begins_with("shin.") or name.begins_with("foot."))
			palette.append(skel.global_transform*skel.get_bone_global_pose(bone)*skin.get_bind_pose(i))
		var influences:int=part[2].size()/part[1].size()
		for i in part[1].size():
			var v:=Vector3.ZERO;var legweight:=0.0
			for j in influences:
				var at:int=i*influences+j;var weight:float=part[3][at];var bind:int=part[2][at]
				v+=(palette[bind]*part[1][i])*weight
				if legs[bind]:legweight+=weight
			if legweight<.5:low=minf(low,v.y)
	return low


func two_bikes_check(life: ClubLife) -> void:
	var bikes := life._free_places("spa_fitness", ["guest_gym_ride"])
	check(bikes.size() == 2, "Each of the two bikes needs its own station")
	if bikes.size() == 2:
		for i in range(2):
			var center: Vector3 = bikes[i]["xf"].origin
			var other: Vector3 = bikes[1-i]["xf"].origin
			var access := life._place_step(bikes[i])
			check((access-Vector2(center.x,center.z)).dot(Vector2(other.x-center.x,other.z-center.z)) < 0.0, "Bike access must be outside the pair")
			check(access.distance_to(Vector2(other.x,other.z)) > 1.6, "Occupied neighboring bike blocks access")
	var users: Array = []
	for look in ["a", "d"]:
		var g := ClubLife.Group.new()
		g.visit = "gym"
		var w := life._person("golfer_" + look)
		w.node.global_position = life._fac("clubhouse").global_transform * Vector3(0, 0, 12)
		g.golfers = [w]
		var claimed := life._to_places(g, "spa_fitness", ["guest_gym_ride"], false)
		check(claimed, "Second gym visitor could not reserve their own bike")
		if claimed:
			life._use_place(w)
		users.append(w)
	check(life._free_places("spa_fitness", ["guest_gym_ride"]).is_empty(), "Bike reservations were shared instead of independent")
	if users.size() == 2 and users[0].data.has("place") and users[1].data.has("place"):
		check(users[0].data["place"]["key"] != users[1].data["place"]["key"], "Two riders reserved the same bike")
		check(users[0].node.global_position.distance_to(users[1].node.global_position) > 0.8, "Two riders sit on the same bike")
		check(users.all(func(w: ClubLife.Walker) -> bool: return w.rest == "spin" and w.data.get("seated", false)), "Both bike riders should be exercising at once")
	for w: ClubLife.Walker in users:
		if w.data.has("place"): life._guest_places.erase(w.data["place"]["key"])
		life._gym_off(w)
		w.node.queue_free()
	check(life._free_places("spa_fitness", ["guest_gym_ride"]).size() == 2, "Released bikes were not available independently")
