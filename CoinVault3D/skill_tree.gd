extends Control

var game
var map_view: Control
var balance: Label
var progress: Label
var stats_summary: Label
var hover_comparison: Label
var notice: Label
var hover_panel: PanelContainer
var hover_title: Label
var hover_description: Label
var hover_requirements: Label
var hover_status: Label
var hover_id := ""
var ready_cursor := 0
var next_button: Button
var stats_button: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color=Color("111219")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+edge,18)
	add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",9)
	margin.add_child(content)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation",12)
	content.add_child(toolbar)
	var title := _label("THE COIN TREE",26,Color("f5d69a"))
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	toolbar.add_child(title)
	next_button=Button.new()
	next_button.text="NEXT BUY"
	next_button.pressed.connect(_focus_next_buy)
	toolbar.add_child(next_button)
	stats_button=Button.new()
	stats_button.text="STATS"
	stats_button.toggle_mode=true
	stats_button.toggled.connect(func(show_stats:bool):stats_summary.visible=show_stats)
	toolbar.add_child(stats_button)
	var fit := Button.new()
	fit.text="FIT TREE"
	fit.pressed.connect(func():map_view.frame_revealed())
	toolbar.add_child(fit)
	var close := Button.new()
	close.text="BACK TO VAULT"
	close.pressed.connect(game._close_upgrade_menu)
	toolbar.add_child(close)
	balance=_label("",17,Color("f5d69a"))
	content.add_child(balance)
	progress=_label("",14,Color("a9a2b7"))
	content.add_child(progress)
	stats_summary=_label("",14,Color("d6c99c"))
	content.add_child(stats_summary)
	stats_summary.hide()
	map_view=preload("res://skill_tree_map.gd").new()
	map_view.game=game
	map_view.progression=game.skill_progression
	map_view.size_flags_vertical=Control.SIZE_EXPAND_FILL
	map_view.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	map_view.hovered.connect(_show_hover)
	map_view.purchased.connect(_purchase)
	content.add_child(map_view)
	var legend := _label("GREEN + Ready to buy (price below)   |   Coin: need funds   |   Lock: milestone   |   Check: learned",12,Color("a9a2b7"))
	content.add_child(legend)
	notice=_label("Drag to move  |  Wheel to zoom  |  Hover for effects and comparisons",12,Color("a9a2b7"))
	content.add_child(notice)
	_build_hover_panel()
	visibility_changed.connect(func():
		if map_view!=null:map_view.reset_gesture()
		hover_id=""
		hover_panel.hide()
	)
	visible=false

func _label(value:String,font_size:int,tint:Color) -> Label:
	var label := Label.new()
	label.text=value
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",tint)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return label

func _build_hover_panel() -> void:
	hover_panel=PanelContainer.new()
	hover_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hover_panel.z_index=10
	var style := StyleBoxFlat.new()
	style.bg_color=Color("211e2b")
	style.border_color=Color("a98d61")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(16)
	style.shadow_color=Color(0,0,0,0.5)
	style.shadow_size=10
	hover_panel.add_theme_stylebox_override("panel",style)
	add_child(hover_panel)
	var content := VBoxContainer.new()
	content.mouse_filter=Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation",10)
	hover_panel.add_child(content)
	hover_title=_label("",20,Color("f5d69a"))
	hover_description=_label("",16,Color("e1dce9"))
	hover_comparison=_label("",15,Color("a0d9d1"))
	hover_requirements=_label("",14,Color("ada6bc"))
	hover_status=_label("",14,Color("8ddaa2"))
	for item in [hover_title,hover_description,hover_comparison,hover_requirements,hover_status]:
		item.custom_minimum_size.x=300
		content.add_child(item)
	hover_panel.hide()

func refresh() -> void:
	stats_summary.text=game.skill_progression.current_summary(game)
	balance.text="BANKED  %s coins     |     COLLECTED  %s / 1,000,000" % [_number(game.banked_coins),_number(game.total_coins_collected)]
	progress.text="%d skills learned  |  Next choices revealed as you learn  |  Gold hexagons are milestone rewards  |  [%s] / Esc to close" % [game.skill_progression.purchased.size(),game.game_settings.binding_label("skill_tree")]
	map_view.refresh()
	var counts := {"ready":0,"coins":0,"milestone":0,"learned":0}
	for id in map_view.revealed:counts[map_view.node_state(id)]+=1
	progress.text="%d READY TO BUY   |   %d need coins   |   %d milestone locked   |   %d learned" % [counts.ready,counts.coins,counts.milestone,counts.learned]
	progress.add_theme_color_override("font_color",Color("99e7b6") if counts.ready>0 else Color("a9a2b7"))
	next_button.text="NEXT BUY (%d)" % counts.ready
	next_button.disabled=counts.ready==0
	if not map_view.initialized:map_view.call_deferred("frame_revealed")
	if hover_id!="":_show_hover(hover_id)

func _purchase(id:String) -> void:
	if game.skill_progression.buy(game,id):
		notice.text="Skill learned. New paths revealed.  |  Drag to explore  |  Wheel to zoom"
	else:
		notice.text="Upgrade unavailable. Hover its icon to check the requirements."
	_show_hover(id)
	map_view.queue_redraw()

func _show_hover(id:String) -> void:
	hover_id=id
	if id=="" or not game.skill_progression.is_revealed(id):
		hover_panel.hide()
		return
	var spec: Dictionary=game.skill_progression.nodes[id]
	var branch: String=game.skill_progression.TITLES[spec.branch]
	hover_title.text=spec.title
	hover_title.add_theme_color_override("font_color",Color(game.skill_progression.COLORS[spec.branch]))
	hover_description.text=game.skill_progression.describe(id)
	var owned: bool=game.skill_progression.purchased.has(id)
	hover_comparison.text="" if owned else game.skill_progression.comparison(game,id)
	hover_comparison.visible=not owned
	var milestone := "No collection milestone" if spec.required==0 else "Collected: %s / %s required" % [_number(game.total_coins_collected),_number(spec.required)]
	hover_requirements.text="%s / Tier %d%s\nPrice: %s banked coins\n%s" % [branch,spec.tier," / Milestone" if spec.kind=="major" else "",_number(spec.cost),milestone]
	if owned:hover_status.text="LEARNED"
	elif game.total_coins_collected<spec.required:hover_status.text="Collect %s more physical coins to unlock." % _number(spec.required-game.total_coins_collected)
	elif game.banked_coins<spec.cost:hover_status.text="Bank %s more coins to afford this skill." % _number(spec.cost-game.banked_coins)
	else:hover_status.text="CLICK TO LEARN"
	for item in [hover_title,hover_description,hover_comparison,hover_requirements,hover_status]:item.custom_minimum_size.x=minf(300,maxf(160,size.x-64))
	hover_panel.reset_size()
	hover_panel.show()
	_position_hover()

func _process(_delta:float) -> void:
	if visible and hover_panel.visible:_position_hover()

func _position_hover() -> void:
	hover_panel.reset_size()
	var at := get_local_mouse_position()+Vector2(22,22)
	if at.x+hover_panel.size.x>size.x-12:at.x=get_local_mouse_position().x-hover_panel.size.x-22
	if at.y+hover_panel.size.y>size.y-12:at.y=size.y-hover_panel.size.y-12
	hover_panel.position=Vector2(clampf(at.x,12,maxf(12,size.x-hover_panel.size.x-12)),maxf(12,at.y))

func _number(value:int) -> String:
	return game.hud_view.number(value)


func _focus_next_buy() -> void:
	var choices: Array[String]=[]
	for id in map_view.revealed:
		if game.skill_progression.can_buy(game,id):choices.append(id)
	if choices.is_empty():return
	choices.sort_custom(func(a:String,b:String):
		var ca: int=game.skill_progression.nodes[a].cost
		var cb: int=game.skill_progression.nodes[b].cost
		return ca<cb if ca!=cb else a<b
	)
	var id: String=choices[ready_cursor%choices.size()]
	ready_cursor+=1
	map_view.focus_node(id)
	notice.text="Affordable upgrade centered. Hover its icon for details; click to buy."
