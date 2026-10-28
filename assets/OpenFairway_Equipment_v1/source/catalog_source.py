"""Asset identity and authored finish palette. Prices only where the supplied spec states them."""
CATALOG=[]
def add(asset_id,name,family,rarity,price,crown,face='#a2a8aa',sole=None,style='',**extra):
    if family=='iron':face=sole=crown
    CATALOG.append(dict(id=asset_id,name=name,family=family,rarity=rarity,price=price,crown=crown,face=face,sole=sole or crown,style=style,**extra))

add('loaner_driver','Loaner Driver','driver','loaner',None,'#737a7e',style='rental')
add('thrift_titan_460','Thrift Titan 460','driver','common',24,'#424d57',style='titan')
add('slice_slayer','Slice Slayer Offset','driver','common',20,'#142d4c',style='offset')
add('persimmon_ghost','Persimmon Ghost','driver','uncommon',55,'#854829',face='#252521',sole='#98713a',style='persimmon')
add('rocket_boomer_lt','Rocket Boomer LT','driver','rare',110,'#a51d25',sole='#e6d7b0',style='rocket')
add('hollow_point_tour','Hollow Point Tour','driver','epic',240,'#15191c',sole='#252a2b',style='tour_black')
add('meteor_xr_proto','Meteor XR Prototype','driver','legendary',520,'#303c4d',sole='#402056',style='carbon')

add('loaner_3w','Loaner 3 Wood','fairway','loaner',None,'#70767a',style='rental',length=1.07)
add('loaner_5w','Loaner 5 Wood','fairway','loaner',None,'#70767a',style='rental',length=1.04)
add('garage_3w','Garage Sale 3 Wood','fairway','common',14,'#536372',style='garage')
add('steelhead_classic','Steelhead Classic 3W','fairway','uncommon',38,'#244e65',sole='#b8bdbe',style='steelhead')
add('tour_spoon','Tour Spoon 13°','fairway','rare',95,'#171c1e',sole='#282d2d',style='tour_black')
add('lowball_5w','Lowball 5 Wood','fairway','common',12,'#3b5655',style='lowball',length=1.04)
add('heirloom_5w','Heirloom 5 Wood','fairway','epic',160,'#a87b4b',sole='#513d2b',style='maple',length=1.04)

add('rescue_rookie','Rescue Rookie 3H','hybrid','common',16,'#51697d',style='rescue')
add('cloudcutter_4h','Cloudcutter 4H','hybrid','uncommon',36,'#263a4a',style='cloud')
add('utility_2u','Utility Iron 2U','hybrid','rare',90,'#87928e',sole='#697475',style='utility',head_depth_scale=.64)

add('loaner_irons','Loaner Irons 4–9','iron','loaner',None,'#899596',style='rental')
add('thrift_cavity_backs','Thrift Cavity Backs','iron','common',45,'#aab1af',style='cavity')
add('mustard_muscle','Mustard Muscle Backs','iron','uncommon',70,'#a58a51',style='bronze')
add('game_improver_xl','Game Improver XL','iron','uncommon',80,'#b0bbbe',style='sgi',sole_width=1.4)
add('blade_runner_forged','Blade Runner Forged','iron','rare',190,'#a2aba8',style='forged')
add('tour_forged_cb','Tour Forged CB','iron','epic',380,'#353f42',style='tour_cb')
add('combo_proto','Combo Set Prototype','iron','legendary',720,'#1b2b43',style='combo')

for suffix in ['pw','gw','sw','lw']:
    add('loaner_'+suffix,'Loaner '+suffix.upper(),'wedge','loaner',None,'#929b9b',style='rental',loft_label=suffix.upper())
add('grocery_pw','Grocery Store PW','wedge','common',8,'#b3babc',style='grocery')
add('bent_neck_pw','Bent Neck PW','wedge','uncommon',30,'#596269',face='#909a9c',style='bent')
add('rusty_gap_52','Rusty Gap 52°','wedge','uncommon',34,'#875139',face='#89543e',sole='#734934',style='rust')
add('flop_master_60','Flop Master 60°','wedge','uncommon',28,'#b9c0bd',style='flop',sole_width=1.35)
add('raw_face_56','Raw Face 56°','wedge','rare',85,'#8c9390',face='#858d88',style='raw')
add('tour_grind_58','Tour Grind 58°','wedge','epic',170,'#3a4241',face='#707c78',sole='#555c56',style='grind')
add('sand_shovel','Sand Shovel SW','wedge','common',10,'#b1b8b9',style='shovel',sole_width=2.15)

add('loaner_putter','Loaner Putter','putter','loaner',None,'#929c9c',face='#99a2a0',style='rental')
add('rustbelt_blade','Rustbelt Blade','putter','common',None,'#80543d',face='#887565',sole='#75543e',style='rustbelt')
add('brass_relic','Brass Relic','putter','uncommon',None,'#9e894e',face='#b69f60',sole='#736e43',style='brass')
add('midnight_mallet','Midnight Mallet','putter','rare',None,'#161e24',face='#272f32',style='midnight')
add('copper_classic','Copper Classic','putter','epic',None,'#c58354',face='#b77950',sole='#a76c46',style='copper')
add('tourline_prototype','Tourline Prototype','putter','epic',None,'#858e8f',face='#99a1a0',sole='#737b7b',style='tourline')
add('blackout_tour_issue','Blackout Tour Issue','putter','legendary',None,'#171c20',face='#222b30',style='blackout')
add('scotty_grail','The Grail','putter','mythic',None,'#b8c0be',face='#a0aaa9',sole='#adb7b6',style='grail')
add('grenade_driver','Grenade Prototype Driver','driver','mythic',None,'#4b5737',face='#707869',sole='#414b30',style='grenade',admin_only=True)
add('auto_putt_9000','Auto-Putt 9000','putter','mythic',None,'#34434a',face='#5b6a70',sole='#263238',style='robot',admin_only=True)

FAMILY_LENGTH={'driver':1.16,'fairway':1.07,'hybrid':1.0,'iron':.95,'wedge':.91,'putter':.87}
RARITY_COLORS={'loaner':'#9daba7','common':'#a6aaa6','uncommon':'#57a57e','rare':'#6aa1d6','epic':'#b295cf','legendary':'#e1b961','mythic':'#ef8773'}
assert len(CATALOG)==45
