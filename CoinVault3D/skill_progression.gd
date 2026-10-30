extends RefCounted

const BRANCHES := ["bag","tool","reach","bank","conveyor"]
const TITLES := ["Bags","Tools","Reach","Banking","Conveyors"]
const COLORS := ["efc263","ed8768","65d8c0","f1dc82","8ddaa2"]
const BASE_COSTS := [20,35,30,75,120]
const GATES := [0,100,750,3000,12000,50000,180000,450000]
var nodes: Dictionary = {}
var purchased: Dictionary = {}

func _init() -> void:
	for branch in range(BRANCHES.size()):
		var key: String=BRANCHES[branch]
		var angle := -PI/2.0 + TAU*float(branch)/float(BRANCHES.size())
		var forward := Vector2(cos(angle),sin(angle))
		var side := Vector2(-forward.y,forward.x)
		for tier in range(1,9):
			var stem := "%s_%d" % [key,tier]
			var at := forward*(130.0+(tier-1)*175.0)
			var cost := int(round(BASE_COSTS[branch]*pow(2.6,tier-1)))
			var parents: Array=[] if tier==1 else ["%s_%d" % [key,tier-1]]
			_add(stem,branch,tier,"core",at,parents,cost,GATES[tier-1],"%s %s" % [["Room to Grow","Heavy Scoop","Further Still","Better Returns","Moving Money"][branch],_roman(tier)],_main_effect(key,tier))
			for wing in range(2):
				var id := stem+"_"+str(wing)
				var location := at+forward*45.0+side*(-64.0 if wing==0 else 64.0)
				var title: String=[["Folded Seams","Extra Pockets"],["Quick Fingers","Clean Sweep"],["Wide Sweep","Steady Rhythm"],["Gold Premium","Friendly Teller"],["Extra Rollers","Profit Sharing"]][branch][wing]
				_add(id,branch,tier,"minor",location,[stem],int(round(cost*0.55)),GATES[tier-1],"%s %s" % [title,_roman(tier)],_minor_effect(key,tier,wing))
			if tier%2==0:
				var milestone: int=[250,7500,125000,900000][int(tier/2.0)-1]
				var title: String=["Bottomless Bag","Golden Harvest","Magnetic Horizon","Midas Contract","Golden Factory"][branch]
				_add(stem+"_major",branch,tier,"major",at+forward*90.0,[stem+"_0",stem+"_1"],cost*3,milestone,"%s %s" % [title,_roman(int(tier/2.0))],_major_effect(key,tier))

func _add(id:String,branch:int,tier:int,kind:String,at:Vector2,parents:Array,cost:int,required:int,title:String,effects:Dictionary) -> void:
	nodes[id]={"id":id,"branch":branch,"tier":tier,"kind":kind,"at":at,"parents":parents,"cost":cost,"required":required,"title":title,"effects":effects}

func _main_effect(branch:String,tier:int) -> Dictionary:
	match branch:
		"bag":return {"capacity":int(round(5*pow(2.3,tier-1)))}
		"tool":return {"pickup":int(ceil(pow(1.7,tier-1)))}
		"reach":return {"reach":0.5+0.1*(tier-1)}
		"bank":return {"bank":0.08+0.02*(tier-1)}
		"conveyor":return {"income":int(pow(2,tier-1))}
	return {}

func _minor_effect(branch:String,tier:int,wing:int) -> Dictionary:
	match branch:
		"bag":return {"capacity":maxi(3,int(round(3*pow(2.3,tier-1))))} if wing==0 else {"capacity":maxi(2,int(round(2*pow(2.3,tier-1))))}
		"tool":return {"delay":0.95} if wing==0 else {"pickup":maxi(1,int(ceil(pow(1.5,tier-1))))}
		"reach":return {"reach":0.3} if wing==0 else {"recovery":0.94}
		"bank":return {"bank":0.04} if wing==0 else {"deposit_range":0.4}
		"conveyor":return {"income":maxi(1,int(pow(2,tier-1)))} if wing==0 else {"bank":0.03}
	return {}

func _major_effect(branch:String,tier:int) -> Dictionary:
	match branch:
		"bag":return {"capacity_mult":1.6}
		"tool":return {"pickup_mult":1.75}
		"reach":return {"reach":2.0+float(tier)*0.5}
		"bank":return {"bank":0.5}
		"conveyor":return {"income":int(10*pow(4,int(tier/2.0)-1))}
	return {}

func prerequisites_met(id:String) -> bool:
	if not nodes.has(id):return false
	for parent in nodes[id].parents:
		if not purchased.has(parent):return false
	return true

func is_revealed(id:String) -> bool:
	return nodes.has(id) and (purchased.has(id) or prerequisites_met(id))

func can_buy(game:Node,id:String) -> bool:
	if not nodes.has(id) or purchased.has(id) or not prerequisites_met(id):return false
	return game.total_coins_collected>=nodes[id].required and game.banked_coins>=nodes[id].cost

func buy(game:Node,id:String) -> bool:
	if not can_buy(game,id):return false
	var spec: Dictionary=nodes[id]
	game.banked_coins-=int(spec.cost)
	purchased[id]=true
	var effects: Dictionary=spec.effects
	for key in effects:
		var amount: float=float(effects[key])
		match key:
			"capacity":game.capacity+=int(amount)
			"pickup":game.pickup_amount+=int(amount)
			"reach":game.collection_range+=amount
			"bank":game.banking_multiplier+=amount
			"income":game.passive_income_rate+=int(amount)
			"deposit_range":game.deposit_range+=amount
			"delay":game.pickup_delay=maxf(0.06,game.pickup_delay*amount)
			"recovery":game.pickup_recovery=maxf(0.025,game.pickup_recovery*amount)
			"capacity_mult":game.capacity=int(ceil(game.capacity*amount))
			"pickup_mult":game.pickup_amount=int(ceil(game.pickup_amount*amount))
	game._update_hud()
	if game.feedback!=null:game.feedback.play("upgrade")
	game.request_save()
	return true

func describe(id:String) -> String:
	var lines: PackedStringArray=[]
	for key in nodes[id].effects:
		var value: float=float(nodes[id].effects[key])
		match key:
			"capacity":lines.append("Carry %d more coins." % int(value))
			"pickup":lines.append("Collect %d more coins per pickup." % int(value))
			"reach":lines.append("Collect coins from %.2f m farther away." % value)
			"bank":lines.append("Deposit bonus +%d percentage points." % int(round(value*100)))
			"income":lines.append("Automatically collect and bank %d more vault coins per second. Counts toward collection milestones." % int(value))
			"deposit_range":lines.append("Use the deposit station from %.1f m farther away." % value)
			"delay":lines.append("Pickup wind-up is %d%% shorter (minimum 0.06 s)." % int(round((1.0-value)*100)))
			"recovery":lines.append("Pickup recovery is %d%% shorter (minimum 0.025 s)." % int(round((1.0-value)*100)))
			"capacity_mult":lines.append("Increase your current bag capacity by %d%%." % int(round((value-1)*100)))
			"pickup_mult":lines.append("Increase your current coins per pickup by %d%% (rounded up)." % int(round((value-1)*100)))
	return "\n".join(lines)

func _roman(value:int) -> String:
	return ["I","II","III","IV","V","VI","VII","VIII"][value-1]

func preview_values(game:Node,id:String) -> Dictionary:
	var result: Dictionary={}
	if not nodes.has(id):return result
	for key in nodes[id].effects:
		var amount: float=float(nodes[id].effects[key])
		var before := 0.0
		var after := 0.0
		var caption := ""
		var suffix := ""
		var decimals := 0
		match key:
			"capacity","capacity_mult":
				before=game.capacity
				after=before+amount if key=="capacity" else ceil(before*amount)
				caption="Bag capacity"
				suffix=" coins"
			"pickup","pickup_mult":
				before=game.pickup_amount
				after=before+amount if key=="pickup" else ceil(before*amount)
				caption="Coins per scoop"
			"reach":
				before=game.collection_range
				after=before+amount
				caption="Collection reach"
				suffix=" m"
				decimals=2
			"bank":
				before=(game.banking_multiplier-1)*100
				after=before+amount*100
				caption="Deposit bonus"
				suffix="%"
				decimals=1
			"income":
				before=game.passive_income_rate
				after=before+amount
				caption="Conveyor collection"
				suffix=" coins/s"
			"deposit_range":
				before=game.deposit_range
				after=before+amount
				caption="Deposit reach"
				suffix=" m"
				decimals=1
			"delay":
				before=game.pickup_delay
				after=maxf(0.06,before*amount)
				caption="Pickup wind-up"
				suffix=" s"
				decimals=3
			"recovery":
				before=game.pickup_recovery
				after=maxf(0.025,before*amount)
				caption="Pickup recovery"
				suffix=" s"
				decimals=3
		result[key]={"caption":caption,"before":before,"after":after,"suffix":suffix,"decimals":decimals}
	return result

func comparison(game:Node,id:String) -> String:
	var lines: PackedStringArray=[]
	for values in preview_values(game,id).values():
		var format := "%.*f"
		var before: String=format % [values.decimals,values.before]
		var after: String=format % [values.decimals,values.after]
		lines.append("%s: %s -> %s%s" % [values.caption,before,after,values.suffix])
	return "\n".join(lines)

func current_summary(game:Node) -> String:
	return "BAG %s  |  SCOOP %s  |  REACH %.2f m  |  CONVEYORS %s/s\nPICKUP %.3f s + %.3f s RECOVERY  |  DEPOSIT +%.0f%%  |  BANK REACH %.1f m" % [game.hud_view.number(game.capacity),game.hud_view.number(game.pickup_amount),game.collection_range,game.hud_view.number(game.passive_income_rate),game.pickup_delay,game.pickup_recovery,(game.banking_multiplier-1)*100,game.deposit_range]
