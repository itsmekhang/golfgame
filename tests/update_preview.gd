extends SceneTree
var failed := false
var camera: Camera3D
const OUT := "C:/Users/willi/Documents/Codex/2026-10-23/ths/outputs/update/"
func shot(name: String, eye: Vector3, target: Vector3) -> void:
	camera.global_position=eye
	camera.look_at(target)
	for frame in range(12): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+name+".png")

func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState: n.autosave = false)
	call_deferred("run")
func check(ok: bool, msg: String) -> void:
	if not ok:
		failed = true
		push_error(msg)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size=Vector2i(1400,1000)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode=Environment.BG_COLOR;e.background_color=Color("a3bbc6")
	e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color.WHITE;e.ambient_light_energy=0.8
	env.environment=e;root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-55,-35,0);sun.light_energy=1.3;sun.shadow_enabled=true;root.add_child(sun)
	camera=Camera3D.new();root.add_child(camera);camera.far=600
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
	FacilityBuilder.set_view(built,FacilityBuilder.View.WALLS_DOWN)
	var house := built.get_node("clubhouse") as Node3D
	var box: Rect2=FacilityBuilder.rig(house)["boxes"]["locker_rooms"]["rect"]
	var center := house.global_transform*Vector3(box.get_center().x,0.8,box.get_center().y)
	await shot("locker_spa",center+Vector3(0,8,-8),center)

	var w := life._person("golfer_a")
	for clip in ["type","type_sit","hose","chip","carry","situp_in","situps","situp_out","kettlebell","front_raise","bench","spin","elliptical"]:
		check(w.anim.has_animation(clip),"Missing imported exercise/staff clip: "+clip)
	var bike: Dictionary=life._free_places("spa_fitness",["guest_gym_ride"])[0]
	w.data["place"]=bike
	life._use_place(w)
	w.anim.seek(0.4,true)
	await shot("bike",w.node.global_position+Vector3(3,2,2.8),w.node.global_position+Vector3(0,0.7,0))
	life._play(w,"spin")
	check(w.anim.get_playing_speed()<0,"Bike still uses backward crank direction")
	for use in ["guest_gym_stretch","guest_gym_sit"]:
		var spots := life._free_places("spa_fitness",[use])
		check(not spots.is_empty(),"Missing gym station "+use)
		for place in spots:
			w.data["place"]=place
			life._use_place(w)
			if use=="guest_gym_stretch":
				check(w.data.has("mat_move"),"Exercise erased by held-prop cleanup")
			else:
				if not w.data.has("rack_bar"):
					print("BENCH missing at ",place["xf"])
					for node in built.find_children("*bench*", "MultiMeshInstance3D",true,false):
						print("BENCH batch ",node.name," mesh ",node.multimesh.mesh.get_aabb()," first ",node.global_transform * node.multimesh.get_instance_transform(0))
				check(w.data.has("rack_bar"),"Bench did not unrack its own bar")
				w.anim.seek(0.7,true)
				life._gym_follow(w)
				await shot("bench_"+str(spots.find(place)),w.node.global_position+Vector3(3,2.8,-3),w.node.global_position+Vector3(0,0.6,0))
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
			if boy.data.has("hose"):
				if not sprayed:
					boy.anim.seek(1.2,true)
					life._hose_follow(boy)
					var cart: ClubLife.Walker=boy.data["wash_cart"]
					var wash_center := boy.node.global_position.lerp(cart.node.global_position,0.5)+Vector3(0,0.7,0)
					await shot("cart_wash",wash_center+Vector3(-4,3,5),wash_center)
				sprayed=true
				check(boy.anim.current_animation=="hose","Hose job not playing Watering clip")
			if sprayed and boy.data.has("wash_cart") and not boy.data.has("hose"): wiped=true
		for cart: ClubLife.Walker in life._stock:
			if cart.data.has("washed_at"): washed=true
		if washed: break
	check(sprayed and wiped and washed,"Cart attendant never completed hose + wipe + release")
	print("CART WASH observed: hose=",sprayed," wipe=",wiped," complete=",washed)
	var first := ClubLife.Group.new()
	var second := ClubLife.Group.new()
	b.hours=2.0
	check(life._record_tee_start(first),"First start refused")
	check(is_equal_approx(b.next_tee_hour,2.25),"Tee interval is not 15 game minutes")
	b.hours=2.1
	check(life._record_tee_start(first),"Same flight delayed between players")
	check(is_equal_approx(b.next_tee_hour,2.25),"Second golfer moved next tee time")
	check(not life._record_tee_start(second),"Next flight started before 15 minutes")
	b.hours=2.25
	check(life._record_tee_start(second),"Next flight blocked at 15 minutes")
	check(is_equal_approx(CourseBusiness.from_dict(b.to_dict()).next_tee_hour,2.5),"Tee spacing lost on save/load")
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
