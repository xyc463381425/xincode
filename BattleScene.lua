
-- type:
        -- normal 正常打关，可以携带好友,有胜利奖励 type ,stageID, battleID,friendID
        -- team   组队打关                          type,...
        -- friendpk 好友对战，无胜利奖励            type,friendID
        -- compete 竞技场，排名                     type,battleID,competeID



-- 普通攻击:  
--         设置动画时长为攻击间隔。 开始攻击(onBeginAttack)：播放动画;  动画事件:产生飞行物(子弹)。
           -- 飞行物与物体碰撞(onAttack)，产生伤害  --期间如果攻击者(playerID)或者被攻击者(targetID)死亡，飞行物无效

-- 技能:
--         设置动画时长为吟唱时间。释放技能：播放动画; 结束技能：吟唱结束， (有延迟时间，延迟)产生伤害,无飞行物。


-- 所有回调均采用内置的CD时间，不以动画的结束时间计算。

local testSocket = require("socket.core")


local GridCell = import("app.test.GridCell")
local Map = require("app.views.battle.MapNew")

local BattleScene = class("BattleScene", function()
    return display.newScene("BattleScene")
end)

BattleScene.Z_ORDER = 10

BattleScene.Z_ORDER_DEBUG = 1080;	-- Debug面板
BattleScene.Z_ORDER_WARING = 1080 - 1;	-- 警告面板
BattleScene.Z_ORDER_UIPANEL = 1080 - 2; -- 最上层的UI面板
BattleScene.Z_ORDER_PLAY = 1080 - 3; -- 玩法层




-- stageID,gameMode,battleID
function BattleScene:ctor(param)
	self._BattleParam = clone(param);	
	self:againCtor(param);
	
	self._GameOverLayer = nil;
	
	
	
--	self._WaringLayer = display.newLayer():addTo(self,100000000):align(display.CENTER,0,0)
--	self._WaringLayer:setTouchEnabled(true);
	
end

function BattleScene:againCtor(param)
	-- 记录Again数据
	BattleSystem:BattleLoopSystem():saveLocationParam(param)

	self.battleSceneSrc = param.battleSceneSrc
	
	local bg  =  util.newColorLayer(cc.c4b(255,255,255,255)):addTo(self)
	local loadingView = param.loadingView
	
	-- 目前看起来，这部分代码是用于多人游戏。
	-- 在进入战斗场景后，需要等待其他玩家进入战场，所以给出的等待UI
	
	if loadingView and not BattleManager.startUpdate then
		local node = display.newNode()
		:addTo(self,20006 - 1)
		BattleManager.loadingNode = node
		local bg = display.newSprite(loadingView):addTo(node)    
		bg:align(display.CENTER,display.cx,display.cy)
		bg:setScale(getShowAllScale())

		local tip_bg = display.newSprite("loading/load_01.png"):addTo(node):align(display.CENTER,display.cx,130)
		local progress = ProgressBar.new({ bVictoryBar = true,mainBarImg = "login/dl_17.png",timerType = PROGRESS_TIMER_BAR_LR,backgroundImg = "login/dl_16.png",anchorPoint = display.CENTER})
		progress:setPercentage(100)
		progress:addTo(node):align(display.CENTER,display.cx,75)
		local label = cc.ui.UILabel.new({
				text = "等待其它玩家...",
				align = cc.ui.TEXT_ALIGN_LEFT,
				size = FONT_SIZE_ONE,
				font = FONT_FZZ
			})
			:align(display.CENTER,tip_bg:getContentSize().width/2,tip_bg:getContentSize().height/2)
			:addTo(tip_bg)
	end
	
	self:initMap(param);

	self:debug();

	self.lastGameTime = 0

	self.autoBattle = false
	
	self.lastIsBossWave = false

	self:initBattle(param)
	
	BattleManager.startUpdate = false;
	self.hudLayer_:setVisible(false);

	self.stepInterval = 1/45
	self.lastTime = cc.GetCustomTime()  --testSocket.gettime() --os.clock()
	self.slop = 0.0;
	self.showResult = false
	BattleScene.i = self
	
	-- 总伤害
	self.damage = 0

	self.isPauseAllNode = false
	
	-- 挂机提示面板
	
	-- 监听：恢复循环
	local resumeListener = function ()
		self:resumeBattle();
	end
	
	-- 监听：循环暂停 - 当前战斗暂停
	local pauseListener = function ()
		self:pauseBattle();
	end

	-- 监听：停止战斗循环
	local stopLoopListener = function ()
		self:resumeBattle();
		BattleSystem:BattleLoopSystem():offLoop();
	end
	
	-- 因为 config.lua 无法热更新 所以 此处不再使用 ALERT_Z_ORDER
	-- 需要让【错误提示】在挂机系统界面之上 所以 ALERT_Z_ORDER -
	self._LoopPanel = require("app.views.LoopBattlePanel").new(param.stageID,pauseListener,resumeListener,stopLoopListener):addTo(self, 20006 + 10)
	self._LoopPanel:setVisible(false);
	
	param = nil

end


local function pause_child(parente)
	local childCount = parente:getChildrenCount()
	if childCount < 1 then
		parente:pause();
		parente:unscheduleUpdate();

		return 
	else 
		local children = parente:getChildren();
		for k , v in next ,children do 
			pause_child(v)
		end
	end
end


local function resume_child(parente)
	local childCount = parente:getChildrenCount()
	if childCount < 1 then
		parente:resume();
		parente:scheduleUpdate();
		return 
	else 
		local children = parente:getChildren();
		for k , v in next ,children do 
			resume_child(v)
		end
	end
end

-- 暂停当前战斗
function BattleScene:pauseBattle(node)
	BattleManager.pauseUpdate = true;
	self:unscheduleUpdate();
	AudioManager:pauseAll();
	pause_child(self)
	if self._GameOverLayer then
		self._GameOverLayer:pause();
	end
	
end
---------重新写两个方法--------------------------------
-- 暂停当前战斗
function BattleScene:pauseBattle_x(node)
	BattleManager.pauseUpdate = true;
	self:unscheduleUpdate();
	audio.pauseMusic();
	pause_child(self)
	if self._GameOverLayer then
		self._GameOverLayer:pause();
	end
	
end

-- 恢复当前战斗
function BattleScene:resumeBattle_x()
	BattleManager.pauseUpdate = false;
	self:scheduleUpdate();
	audio.resumeMusic();
	resume_child(self)
	
	if self._GameOverLayer then
		self._GameOverLayer:resume();
	end
end


-- 恢复当前战斗
function BattleScene:resumeBattle()
	BattleManager.pauseUpdate = false;
	self:scheduleUpdate();
	AudioManager:resumeAll();
	resume_child(self)
	
	if self._GameOverLayer then
		self._GameOverLayer:resume();
	end
end

-- 初始化战斗循环模块
function BattleScene:initLoopBattle()
	if(BattleSystem:getBattleSeting():isBattleLoop()) then
		self._LoopPanel:setVisible(true);
	end
end


function BattleScene:debug()
	if DEBUG_BATTLE == 1 then
		for i=1,10 do
			local cx,cy =(i-1)*display.width/10,0
			display.newRect(cc.rect(cx, 0, 2, display.height),{fillColor = cc.c4f(0,0,0,1), borderColor = cc.c4f(0,0,200,1)})
			:addTo(self)
		 end

		local posY = {  BattleConstants.Middle,
						BattleConstants.Middle+30,
						BattleConstants.Middle-30,
						BattleConstants.Middle+70,
						BattleConstants.Middle-70,
		}

		for i=1,#posY do
			local cx,cy =0,posY[i]
				display.newRect(cc.rect(cx, cy, display.width, 2),{fillColor = cc.c4f(0,1,0,1), borderColor = cc.c4f(0,0,200,1)})
				:addTo(self)
		end
	end
end


function BattleScene:initMap(param)
	local stageInfo = gameConfig:get("soosoogoo_stage",param.stageID)
	local map_type = tonumber(stageInfo.map_id)
	if map_type == 0 then
		map_type = 7
	end
	
	self.mapRoot = util.newNode()
	if CONFIG_SCREEN_WIDTH/960 >= CONFIG_SCREEN_HEIGHT/640 then
		
	else
		self.mapRoot:setScale(getShowAllScale())
		BattleConstants.CellWidth = BattleConstants.CellWidth/getShowAllScale()
	end

	self:addChild(self.mapRoot,Map_Order)

	local map_effect = stageInfo.map_effect
	local mapAni = nil
	if map_effect and map_effect~="" then
		 if string.find(map_effect, ".plist") then
			 cc.ParticleSystemQuad:create("bqs_res/mapEffect/"..map_effect):pos(display.width/2,display.height):addTo(self.mapRoot)
		 else
			mapAni = ArmatureNode.new("bqs_res/mapEffect/"..map_effect,false)
			mapAni:setAni("aa",true,false)
		 end
	end

	local tarr = string.split(map_effect, "__")
	local zOrder = 21

	self.map_3 = Map.new(50,map_type):addTo(self.mapRoot)

	if tarr[2] == "1"  and mapAni~= nil then
		mapAni:addTo(self.mapRoot):pos(display.cx,display.cy)
	end
   

	self.map_2 = Map.new(40,map_type):addTo(self.mapRoot)
	if tarr[2] == "2"  and mapAni~= nil then
		mapAni:addTo(self.mapRoot):pos(display.cx,display.cy)
	end

	self.map_people = util.newNode()
	-- if stageInfo.is_show_emeng == "1" then
	--      display.newSprite("emzhao.png"):addTo(self.mapRoot,29):pos(display.cx, display.cy)
	-- end
	self.map_people:addTo(self.mapRoot)


	self.map_ = Map.new(20,map_type):addTo(self.mapRoot)

	if tarr[2] == "3" and mapAni~= nil then
		mapAni:addTo(self.mapRoot):pos(display.cx,display.cy)
	end

	if #tarr<2 and mapAni~= nil then
		mapAni:addTo(self.mapRoot):pos(display.cx,display.cy)
	end
end


function BattleScene:initBattle(param)
        echo("--initBattle-")
		dump(param)
		BattleManager:checkIsMe();
		
		self.battleID = param.battleID;
        self.stageID = param.stageID;
        self.isBossWarning = false --是否播放完warning动画
        GlobalEventDispatch:addGlobalEventListener("room_return_response", self.returnRoomResponse, self)

        GlobalEventDispatch:addGlobalEventListener("gameOver", self.onGameOver, self)
        GlobalEventDispatch:addGlobalEventListener(Server_Battle_End_Response, self.serverEndBattle, self)
        GlobalEventDispatch:addGlobalEventListener(Server_LegionBattle_End_Response, self.serverEndLegionBattle, self)

        GlobalEventDispatch:addGlobalEventListener("prepareNextWave", self.prepareNextWave, self)
        GlobalEventDispatch:addGlobalEventListener("usePartnerToBattle", self.usePartnerToBattle, self)
        GlobalEventDispatch:addGlobalEventListener("zhaohuanPartnerToBattle", self.zhaohuanPartnerToBattle, self)

        GlobalEventDispatch:addGlobalEventListener("shockSceneEvent", self.shockSceneEvent, self)

        GlobalEventDispatch:addGlobalEventListener("showPeoplePainting", self.showPeoplePainting, self)
        GlobalEventDispatch:addGlobalEventListener("showPartnerEnterPainting", self.showPartnerEnterPainting, self)
        GlobalEventDispatch:addGlobalEventListener("showLowHpWarningEffect", self.showLowHpWarningEffect, self)
        GlobalEventDispatch:addGlobalEventListener("DROP_SMOKE_PlIST", self.addDropSmokePlist, self)
 		GlobalEventDispatch:addGlobalEventListener("BossWar_End_Fight", self.bossWarEndResponse, self)
		
        if self.stageID == "500000" then
            local mapAni = ArmatureNode.new("bqs_res/mapEffect/map_tongyong",false)
            mapAni:setAni("aa",true,false)
            mapAni:addTo(self.mapRoot):pos(display.cx,display.cy)
            mapAni:setScale(getShowAllScale())
        end


        local stageInfo = gameConfig:get("soosoogoo_stage",self.stageID)

        if param.type =="normal" then
            self.gameTime = checknumber(stageInfo.max_time) * 60
         elseif param.type =="legionWar" then
            -- local stageInfo = gameConfig:get("soosoogoo_stage",self.stageID)
            -- self.gameTime = param.gameTime
            -- BattleManager:initLegionBoss()
        elseif param.type == "multiplayer" then
            self.gameTime = checknumber(stageInfo.max_time) * 60
         elseif param.type == "tutorial" then
            self.gameTime = checknumber(stageInfo.max_time) * 60
        elseif param.type == "cheat" then
            self.gameTime = checknumber(stageInfo.max_time) * 60
        end
        if not BattleManager.isLegionBossWar then
            BattleManager:battleAgainstNextWave()
        end
        self.cg_id = param.cg_id
        self.ucgl_id = param.ucgl_id
        local soundArr = string.split(stageInfo.sound, "|")
        self.backgroundMusic = soundArr[1]
        self.bossWaveMusic = ""
        if #soundArr>1 then
            self.bossWaveMusic = soundArr[2]
        end
        self.gameType_ =  param.type
        self.battleTime = 0
        local _param = {}
        _param.__type = param.type
        _param.__team ="teamA"
        if not BattleManager.isMultiPlayer  then
            if self.stageID ~= "500000" then
                _param._isMe = true
            end
        end

        self:addGroupPeople(_param)--add teamA

        BattleManager:setMainView()
        _param.__team = "teamB"
		
        self:addGroupPeople(_param)
        _param = nil

        self.diffLevel = param.diffLevel
		
		BattleManager:checkIsMe();
		
        self.hudLayer_ = require("app.views.battle.HudLayerNew").new(self,param.diffLevel,self.gameType_):addTo(self,Hud_Order)
        self.hudLayer_:setTag(55555)
        BattleManager.isPlayerDeath = false
	
end

-- 出场动画：大概是旧版本代码，不用了，但是没有删除
--[[function BattleScene:customMissionStart( ... )
    local element_file1 = {} 
    element_file1["1002"] =  "dise_feng.png"
    element_file1["1003"] =  "dise_huo.png"
    element_file1["1004"] =  "dise_shui.png"
    element_file1["1000"] =  "dise_guang.png"
    element_file1["1001"] =  "dise_an.png"
	
	
    local icons = {}
        local peopleModelTeam = BattleManager.peopleModelsTeamA
        local num =1
        for k,v in pairs(peopleModelTeam) do
            echo("------k: "..k)
            if v.isMe_ ~= 1 then
                local element_id = v.record.element_id
                local icon = display.newSprite(element_file1[element_id])
                echo("png"..v.record.pic_e)
                local sp = display.newSprite(v.record.pic_e)
                :align(display.CENTER,icon:getContentSize().width/2,icon:getContentSize().height/2)
                :addTo(icon)
                icons[#icons+1] = icon
            end
        end
        local pos = {display.height+350,-350,display.height+350,-350}
        local offset = {-100,100,-100,100}
        local delayTime = {20,25,28,32}
        for i=1,#icons do
            local icon = icons[i]
            :addTo(self)
            local posX = display.cx - 600 + 240*i
            icon.end_pos = cc.p(posX, display.cy )
            local time = delayTime[i] - (delayTime[i-1] or 16)
            self:moveAction(icon,delayTime[i],time,posX+offset[i],pos[i],"vertical")
        end
end--]]

function BattleScene:missionStart()
        -- local bgs = {"kakuang_01_bg1","kakuang_02_bg1","kakuang_03_bg1","kakuang_04_bg1","kakuang_06_bg1"}
         local bgs = {"n_1.png","r_1.png", "hr_1.png","sr_1.png",  "ur_1.png"}
         local bgs2 = {"dise_guang.png", "dise_an.png","dise_feng.png", "dise_huo.png",  "dise_shui.png"}

        -- local sp = display.newSprite("mission_bg.png"):pos(display.cx,display.cy):addTo(self,10)
        -- sp:setScale(1.2)

        local ani = ArmatureNode.new("mission_start"):pos(display.cx,display.cy):addTo(self,LIHUI_GLOBAL_ZORDER)

        local keys = {"lihui2_ren1","lihui2_ren2","lihui2_ren3","lihui2_ren4"}
        -- local keys2 = {"kakuang_02_bg","kakuang_01_bg","kakuang_03_bg","kakuang_04_bg"}

        local keys2 = {"xiyoudu1","xiyoudu2","xiyoudu3","xiyoudu4"} 
        local keys3 = {"lhst_00_kong1","lhst_00_kong2","lhst_00_kong3","lhst_00_kong4"}
        local keys4 = {"dise1","dise2","dise3","dise4"}



        local peopleModelTeam = BattleManager.peopleModelsTeamA
        local num =1
        for k,v in pairs(peopleModelTeam) do
            echo("----------k1--: "..k)

            if v.isMe_ ~= 1 then
                echo("----------kd--: "..k)
                ani:replaceAniImage(keys[num],v.record.pic_e)
                local quality = tonumber(v.record.quality)
                local element_id = tonumber(v.record.element_id)-1000+1
                ani:replaceAniImage(keys2[num],bgs[quality])
                ani:replaceAniImage(keys4[num],bgs2[element_id])
                num = num+1
            end
        end
        -- --todo默认
        for i=num,4 do
            ani:replaceAniImage(keys[i],"partner_e/"..keys3[i]..".png")
            -- ani:replaceAniImage(keys2[num],bgs[quality])
            ani:replaceAniImage(keys4[i],"kakuang_05_bg1.png")
        end

        ani:registerSpineEventHandler(
          function(event)
             local function safeRemove()
                ani:customeRemoveFromParent(true)
                -- sp:removeFromParent()
                self:partnerDengchang()

                AudioManager:playEffect(AudioManager:getGameEffect("2"))
             end
             scheduler.performWithDelayGlobal(safeRemove,0)
          end
        ,SP_ANIMATION_COMPLETE
        )

      ani:registerSpineEventHandler(
          function(event)
                 if  event.eventData.name=="damage" then
                    AudioManager:playEffect(AudioManager:getGameEffect("1"))
                 end
          end
        ,SP_ANIMATION_EVENT
        )

        -- ani:setScaleX(util.getScaleX())
        -- ani:setScaleY(util.getScaleY())
        ani:setAni("zh",false) 
       -- 
       BattleManager.startUpdate = false
end
function BattleScene:moveAction(node,delayTime,time,pos_x,pos_y,ac_type )
    local frame = 35
    ac_type = ac_type or "horizontal"
    local posX   
    local posY    
 
    if ac_type == "vertical" then
        posX = pos_x
        posY = pos_y
    else
        if node.end_pos.x > display.cx then
            posX = pos + display.width
        else
            posX = pos
        end
        posY = node.end_pos.y
    end

    node:align(display.CENTER,posX,posY)
    node:stopAllActions()
    local move1 = cc.EaseSineOut:create(cc.MoveTo:create(time/frame, node.end_pos))
    local action     
    if delayTime > 0 then
      action = cc.Sequence:create(cc.DelayTime:create(delayTime/frame),move1)
    else
        action = move1
    end
    node:runAction(action)
end


function tableLeng(table)
	local count = 0  
	for k,v in pairs(table) do  
		count = count + 1  
	end
	return count;
end


function BattleScene:prepareNextWave(msg)
        local isRefreshTime = msg.isRefreshTime
 
        if isRefreshTime then

            pos = -self.map_:convertToWorldSpace(cc.p(0,0)).x / BattleConstants.CellWidth + display.width-260
            
        else
            self.isBossWave = msg.isBossWave

            self:resetTeamApos()
            echo("-isBossWave--"..tostring(self.isBossWave ).."  "..BattleManager.curWave)
            echo("--isBossWave-"..tostring(self.lastIsBossWave ))
            if self.lastIsBossWave and self.isBossWave then
                pos = BattleManager.bossCell
                echo("------------changeBoss---------")
            else
                pos = -self.map_:convertToWorldSpace(cc.p(0,0)).x / BattleConstants.CellWidth  + display.width-110
            end
             self.lastIsBossWave = self.isBossWave
        end

       

        local param = {}
        param.__team = "teamB"
        param.pos = pos
        param.__isNext = true
        self:addGroupPeople(param)
        BattleManager.isInitWave_ = false


end

function BattleScene:showChallengeLayer()
    display.pause()
    BattleManager.pauseUpdate = true
    local layer = display.newColorLayer(cc.c4b(0,0,0,200)):addTo(self,Hud_Order+1)
    local bg = cc.Sprite:create("popup/tc_ts.png"):addTo(layer)
    bg:pos(display.cx,display.cy)
     util.newTTFLabel({
            text = "遭遇乱入，是否挑战",
            align = cc.ui.TEXT_ALIGN_CENTER,
            font = FONT_FZZ,
            size = 30,
            color = cc.c3b(0X51,0X51,0X51),
            dimensions = cc.size(400,110),
            })
    :align(display.CENTER,bg:getContentSize().width/2,bg:getContentSize().height/2-20)
    :addTo(bg)
    local btn1 = Button.new({
        images = "base/button_05.png",
        text = "确定",
        textColor = cc.c3b(146,95,23),
        listener = function(event)
            display.resume()
            BattleManager:battleAgainstNextWave(true)
            BattleManager.pauseUpdate = false
            layer:removeFromParent()
        end, 
        x = bg:getContentSize().width/2+100,
        y = 50,
        })
    :addTo(bg)

    local btn2 = Button.new({
        images = "base/button_06.png",
        text = "取消",
        listener = function()
            display.resume()
            local stageInfo = gameConfig:get("soosoogoo_stage",self.stageID)
            self.reward_stage_id = stageInfo.base_stage_id
            BattleManager.isGameOver = true
            GlobalEventDispatch:dispatchEvent({name = "gameover", data = {isWin = END_TYPE_WIN }})
            layer:removeFromParent()
        end,
        x = bg:getContentSize().width/2-100,
        y = 50,
        })
    :addTo(bg)
end

function BattleScene:resetTeamApos()
    local _param = {}
    _param.__team ="teamA"

    local teameBefore, teamAfter = self:getKeyGroupTable(_param.__team)

    refreshingPos = false

    local function getModelPosY(models,index)
        local playerIndex = 100
        for i=1,#models do
            if models[i].isMe_  == 1 then
                playerIndex = i
                break
            end
        end
        if index>playerIndex then
            index =  index -1
        end
        if index>4 then
            index = 1
        end
        return index
    end

    local function getPosYs(models)
        local posY = nil
        -- if #models == 1 then
        --     posY = {BattleConstants.Middle}
        -- elseif  #models == 2 then
        --     posY = {    
        --         BattleConstants.Middle-BattleConstants.HDis,
        --         BattleConstants.Middle+BattleConstants.HDis
        --     }
        -- else
            posY = {            BattleConstants.Middle+30,
                                BattleConstants.Middle-30,
                                BattleConstants.Middle+70,
                                BattleConstants.Middle-70,
                }
        -- end 
        return  posY
    end
    if teameBefore then
        local posY = getPosYs(teameBefore)
        for i=1,#teameBefore do
            local v = teameBefore[i]

            local temp = posY[getModelPosY(teameBefore,i)]
            if v.isMe_  == 1 then
                temp = BattleConstants.Middle
            end
            -- 第一波不调整位置
            if v.posY~=nil then
                v:setPosY(temp)
                v:resetPos()
            end
        end
    end
    if teamAfter then
        local posY = getPosYs(teamAfter)
        for i=1,#teamAfter do
            local v = teamAfter[i]
            local temp = posY[getModelPosY(teamAfter,i)]
            if v.isMe_  == 1 then
                temp = BattleConstants.Middle
            end
            -- 第一波不调整位置
            if v.posY~=nil then
                v:setPosY(temp)
                v:resetPos()
            end
        end
    end
end 

function BattleScene:onAutoBattleBtnClicked( event )
    self.autoBattle = event.target:isButtonSelected()          
end

function BattleScene:onEnter()
    NoticeManager:removeRequestChatListener(true)
	
    NoticeManager:addRequestChatListener(10)
	
    AudioManager:playBattleMusic(self.backgroundMusic)
    -- if device.platform == "android" then
        -- avoid unmeant back
        self:performWithDelay(function()
            -- keypad layer, for android
            local layer = util.newLayer()
            layer:addNodeEventListener(6,function(event)
                -- 战斗中不退出
                -- if not UserData:isInTutor() then
                --     if event.key== "back" then 
                --         app:quit()
                --     end
                -- end
            end)
            self:addChild(layer)

            layer:setKeypadEnabled(true)
        end, 0.5)
    -- end

    self:addNodeEventListener(cc.NODE_ENTER_FRAME_EVENT,
        function(dt)
            self:update(dt)
        end
    )
    self:scheduleUpdate()
    refreshingPos = false
    if BattleManager.isMultiPlayer then
        self.hudLayer_:setVisible(true)
        -- self.startUpdate = true

        -- 0.5秒后，发送准备完成的消息
        local function ready() 
            UserData.client:broadCastMessage({cmd = BATTLE_LOADING,data = {role_id = UserData.role_id}})
        end
        ready()
    elseif BattleManager.isTutor then
        self.hudLayer_:setVisible(true)
        BattleManager.startUpdate = true
    end
	
	
	self:initLoopBattle();

end


function BattleScene:clearGame()
    self:unscheduleUpdate()
    BattleManager:clear()
    GlobalEventDispatch:removeAllEventListenersForObject(self)
end


function BattleScene:showWinlayer(data)	
	-- 记录一次体力消耗
	local stageInfo = gameConfig:get("soosoogoo_stage",self.stageID);
	local value = string.split(stageInfo.end_cost, "|");
	BattleSystem:BattleLoopSystem():addConsumption(value[2]);
	
    self._GameOverLayer = require("app.views.WinLayerDevelop").new(data,self.stageID)
    :addTo(self,POPUPVIEW_Z_ORDER):pos(display.cx,display.cy)
	self:loopAgain();
end


-- 【再来一次】按钮的
function BattleScene:loopAgain()
	local function againLoop()
		if(BattleSystem:getBattleSeting():isBattleLoop()) then
			local isBool = BattleSystem:battleAgain();
			if isBool == false then
				self._LoopPanel:loopPause();
			end
		end
	end
	self._BattleLoopDelayAction = cc.Sequence:create(cc.DelayTime:create(1.5),cc.CallFunc:create(againLoop))
	self._GameOverLayer:runAction(self._BattleLoopDelayAction)
end


function BattleScene:showLoselayer()
	if(self._GameOverLayer) then
		self._GameOverLayer:removeFromParent()
		self._GameOverLayer = nil;
	end
	
	-- 战斗失败的UI
    self._GameOverLayer = require("app.views.LoseLayerNew").new({},self.stageID)
    :addTo(self,POPUPVIEW_Z_ORDER):pos(display.cx,display.cy)
	
	
	-- 如果玩家没有选择失败时自动停止挂机，那么尝试"BattleAgain"
	if(not BattleSystem:getBattleSeting():isLoopAutoEnd()) then
		self:loopAgain();
	elseif BattleSystem:getBattleSeting():isBattleLoop() then
		self._LoopPanel:loopPause();
	end
	
end

function BattleScene:showGameOverLayer()
    local function show()
        self.delayDone = true
        self.hudLayer_:setVisible(false)
        if self.isWin == END_TYPE_WIN then
            if self.winInfo then
            	dump("战斗胜利：")
                if self.winInfo.stage and self.winInfo.stage.sid then
                	Account.ChapterSave:complateTick(self.winInfo.stage.sid);
            	end
                self:showWinlayer(self.winInfo)
            end
        elseif self.isWin == END_TYPE_LOSE or self.isWin == END_TYPE_TIMEOUT then
             self:showLoselayer()
        end
    end

    local action = cc.Sequence:create(cc.DelayTime:create(2), cc.CallFunc:create(show))
    self:runAction(action)

end



function BattleScene:serverEndLegionBattle( result )
    self.winInfo = result.data.info
    if self.delayDone then
        self.hudLayer_:setVisible(false)
        self:showWinlayer(self.winInfo)
    end

end

function BattleScene:serverEndBattle( result )
    -- 共斗日志的逻辑处理
    if BattleManager.isMultiPlayer and not result.force then
        local stageinfo = result.data
        dump(stageinfo)
        if stageinfo and stageinfo.sid then
            UserData:updateBattleStageLog(stageinfo.sid.."",stageinfo)    
        end
        return 
    end
    if self.showResult then
        return
    end
    self.showResult = true
    if result.force then
        self.winInfo = result.data
        -- self.delayDone = true
    else
        self.winInfo = result.data.info
    end

    if self.delayDone then
        self.hudLayer_:setVisible(false)
        self:showWinlayer(self.winInfo)
    end

end

function BattleScene:returnRoomResponse( event )

    util.enterMainMenuSceneMap(self.battleSceneSrc,self.stageID)   

end

function BattleScene:onGameOver( message )
    if self._isGameOver  then
        do return end
    end
    BattleManager.isGameOver = true
    self._isGameOver = true
    if self:getChildByTag(909144) then 
        self:removeChildByTag(909144, true)
    end
    self.isWin = message.data.isWin 
    if  self.stageID == "500000"  then 
        return
    end
	
	BattleSystem:BattleLoopSystem():addLoopCount(); --增加一次循环次数

    if BattleManager.isLegionBossWar then
    	local damage = BattleManager.bossHp - BattleManager.bossMonster.hp_
    	self.damage = damage
		local param = {}
	    param.damage = crypto.encodeBase64(tostring(damage).."|".."caromag")
	    -- param.damage = damage
	    param.stageId = tonumber(self.stageID)
	    param.legionId = tonumber(UserData.legion.ul_id)
	    param.time = tonumber(self.lastGameTime)
	    param.utId = tonumber(self._BattleParam.utId)
	    UserData.client:onSendMsg({[EndFight] = param})        
	    return
    end
    display.newLayer()
    :addTo(self,POPUPVIEW_Z_ORDER)
    local stageInfo =  gameConfig:get("soosoogoo_stage",self.stageID)

    if self.isWin == END_TYPE_WIN  then
        local score
        if self.gameType_ == "normal" or self.gameType_ == "multiplayer"  then
            score = util.getScore( self.stageID ,self.battleTime)
            local star = 0
            local last_stage = false
            local d = nil
            local wcg_id = nil
            for i,v in ipairs(UserData.activityInfos) do
            if v.activity_class == "6" then 
                    d = v
                end
            end
            if d~=nil then
                wcg_id = util.getWeekChapter(self.stageID,d.wc_id)
                if wcg_id then
                    star = 3
                    -- if UserData.finishStages[self.stageID] then
                    --     star = tonumber(UserData.finishStages[self.stageID].star) + star
                        -- if star > 8 then
                        --     star = 8
                        -- end 
                    -- end
                    -- 判断是否是最后关卡
                    local wcg_config = gameConfig:get("soosoogoo_week_chapter_gates",wcg_id)
                    local stages = string.split(wcg_config.stage, ",")
                    for i,v in ipairs(stages) do
                        if tonumber(v) > tonumber(self.stageID) then
                            last_stage = false
                        else
                            last_stage = true
                        end
                    end
                end
            end
            local param = {}
            if self.reward_stage_id then
                param.reward_stage_id = self.reward_stage_id
            end
            param.usl_id =self.battleID
            param.score = score
            param.star = star
            
            BattleConstants.BattleEndTime = cc.GetCustomTime()
            param.cost_time = math.round(self.battleTime)
            if UserData.gondou_item then
                param.is_cost = UserData.gondou_item.ulti_id
            end
            
            if last_stage == true then
                param.sid = wcg_id
            end
            if BattleManager.isMultiPlayer then
                local msg = {}
                local data = {
                    RoomId = UserData.client.room_id,
                    RoleId = UserData.role_id,
                    StageId = tonumber(self.stageID),
                    Score = score,
                    Status = 1,
                }

                msg[BATTLE_FINISH_GAME] = data
                UserData.client:onSendMsg(msg,false)
                dump("---    Game finish     --  ")
            else
            	local team = Account.Team:getTeamByOrder(BattleManager.teamOrder);
                param.teamFight = team:getTeamFightCapacity()
			    local teamAttribute = {}
			    teamAttribute[1] = Account.Team:getTeamByOrder(BattleManager.teamOrder):getLeaderTotalAttribute()
		    	local partnerIds = {}
				--TODO；传过来出战队伍的信息
				if  UserData.teams[BattleManager.teamOrder] ~= nil then
					local up_ids =  UserData.teams[BattleManager.teamOrder].up_ids
					for i=1,#up_ids do
						local up_id = up_ids[i]
						partnerIds[i] = up_id
					end
				end
				for i=1,#partnerIds do
					local partnerId = partnerIds[i]
					local attrib = Account.Team:getTeamByOrder(BattleManager.teamOrder):getPartnerTotalAttributeByID(partnerId)
					teamAttribute[#teamAttribute+1] = attrib
				end
				param.teamAttribute = teamAttribute
                -- dump(param,"param=====================xyc---==========给服务器发送的数据==============")
                GlobalEventDispatch:dispatchEvent({name = Server_Battle_End,param = param})
            end
        elseif  self.gameType_ == "legionWar" then
            score = util.getScore( self.stageID ,self.battleTime)
            local star = 0
            local param = {}
            if self.reward_stage_id then
                param.reward_stage_id = self.reward_stage_id
            end
            param.usl_id = self.battleID
            param.score = score
            param.star = star
 
        end
        if self.battleSceneSrc == BattleSceneSrc.Story_Branch then
            TaskManager:saveTaskByType(9)
        elseif self.battleSceneSrc == BattleSceneSrc.Experience_Elite then
            TaskManager:saveActivityStageTask(tostring(self.stageID),"15")
            TaskManager:saveActivityStageTask(tostring(self.stageID),"19") -- 幻境试炼（长期存在任务）
            TaskManager:saveActivityStageTask(tostring(self.stageID),"54") -- 幻境试炼（限时任务）
        end
        local level = util.getScoreLevel(score)
        local record = gameConfig:get("soosoogoo_task")
        for k,v in pairs(record) do
            if tonumber(v.task_type) == 2 then
                local ids =  string.unpackString(v.objective_action_item,"|")
                if ids[1] == tostring(self.stageID) then
                    TaskManager:saveTutorialTask(v.task_id)
                end
            elseif tonumber(v.task_type) == 3 then
                local ids = string.unpackString(v.objective_action_item)
                for i=1,#ids do
                    local str = string.unpackString(ids[i],"|")
                    local item_id = str[1]
                    local max_num = tonumber(str[2])
                    local s_level = true
                    if #ids > 1 then
                        if level < 4 then
                            s_level = false
                        end
                    end
                    if item_id == tostring(self.stageID) then
                        if s_level then
                            TaskManager:saveStoryTask(v.task_id,item_id, max_num)
                        end
                        break
                    end
                end
            end
        end
        TaskManager:saveTaskByType(tonumber(BattleManager.pid))
        TaskManager:saveTaskByType(2)
        TaskManager:saveSevenTask("4",self.stageID,1)
        util.saveAchieveAdd(Achieve_Stage,1,self.stageID)
        TaskManager:saveSevenTask(Achieve_Stage,1,self.stageID)
        if stageInfo.stage_type == "1" then
        elseif stageInfo.stage_type == "2"  then
            util.saveAchieveAdd(Achieve_Stage3,1)
            TaskManager:saveSevenTaskAdd(Achieve_Stage3,1)
            TaskManager:saveDayTaskByType(Achieve_Stage_Entrust,1)
            if stageInfo.difficulty == "4" then
                util.saveAchieveAdd(Achieve_Stage2,1,self.stageID)
                util.saveAchieveAdd(Achieve_Stage4,1)
                TaskManager:saveDayTaskByType(Achieve_Stage_Entrust2,1)
	        elseif stageInfo.difficulty == "5" then
	            TaskManager:saveDayTaskByType(Achieve_Stage_Entrust3,1)
	            util.saveAchieveAdd(Achieve_Limit_Stage,1,self.stageID)
	        end
        elseif stageInfo.stage_type == "3"  then
            if  self.stageID=="580301" or self.stageID=="580302" or self.stageID=="580303" 
                 or self.stageID=="580304" or self.stageID=="580305"then
                util.saveAchieveAdd(Achieve_TrialsALL,1,-1)
            end
        elseif stageInfo.stage_type == "4"  then
            TaskManager:saveSevenTaskAdd(Achieve_Stage5,1,"578001")
            TaskManager:saveDayTaskByType(Achieve_Stage_Practice,1)
        elseif stageInfo.stage_type == "10" then
        	if stageInfo.type == "15" then
            	TaskManager:saveSevenTaskAdd(Achieve_TrailStage,1,self.stageID)
            	util.saveAchieve(Achieve_Illusion_Stage,1,self.stageID)
            end
        end

    elseif  self.isWin == END_TYPE_LOSE or self.isWin == END_TYPE_TIMEOUT then
        if BattleManager.isMultiPlayer then
            local msg = {}
            local data = {
                RoomId = UserData.client.room_id,
                RoleId = UserData.role_id,
                StageId = tonumber(self.stageID),
                Score = 0,
                Status = 2,
            }

            msg[BATTLE_FINISH_GAME] = data
            UserData.client:onSendMsg(msg,false)
        end
    end
 
    self:showGameOverLayer()
    
end


function BattleScene:adjustPos()

        local result = nil
        for k,v in pairs(BattleManager.peopleModelsTeamA) do
            if not v.isNPC then
                if result==nil then
                    result = v
                elseif v.cellPos_>result.cellPos_ then
                    result = v
                end
            end
        end
        if not result then
            return
        end
        
        -- if BattleManager.mainView.peopleModel.isMe_ == 1 or BattleManager.mainView.peopleModel.isMain_ == 1  then
        if BattleManager.peopleViews[result.playerID_]~=nil  then
            local re_localX = BattleManager.peopleViews[result.playerID_]:convertToWorldSpace(cc.p(0,0)).x
            if re_localX>display.cx then
                -- local localX = BattleManager.peopleViews[result.playerID_]:getPositionX()
                self.map_:setPositionX(self.map_:getPositionX() + (display.cx - re_localX ))
                self.map_people:setPositionX(self.map_people:getPositionX() + display.cx - re_localX )

                -- self.map_2:setPositionX(self.map_2:getPositionX() + 0.8*(display.cx - re_localX) )
                -- 这个map_2和 人物是同层，保持相同的速度
                self.map_2:setPositionX(self.map_2:getPositionX() + (display.cx - re_localX) )
                self.map_3:setPositionX(self.map_3:getPositionX() + 0.6*(display.cx - re_localX) )
                -- self.map_1:setPositionX(self.map_1:getPositionX() + 0.8*(display.cx - re_localX) )

                self.map_:refreshContent()
                self.map_2:refreshContent(BattleManager.curWave)
                self.map_3:refreshContent()
                -- self.map_1:refreshContent()
                if  BattleManager.dis_npc then
                    local posX = -self.map_:getPositionX()
                    local cell = posX/BattleConstants.CellWidth
                    self.hudLayer_:updateForwardBar(cell)
                end

            end
        end

  

        if self.isBossWave then
             if math.abs(BattleManager.peopleModels[result.playerID_].cellPos_- BattleManager.bossCell)<BattleManager.peopleModels[result.playerID_].attackDis_ then
                        if self.bossWaveMusic~="" then
                            AudioManager:playBattleMusic(self.bossWaveMusic)
                        end
                        echo("开始播放warning动画")
                        local aniBoss = ArmatureNode.new("bossyujing",true)
                            :pos(display.width/2,display.height/2)
                            :addTo(self,10000)
                        aniBoss:setAni("sb",false)
                        if self.stageID == "500000" and BattleManager.curWave == 4 then
                            aniBoss:setVisible(false)
                        else
                            AudioManager:playEffect(AudioManager:getGameEffect("7"))
                        end
                        if self.bossView and self.bossView.peopleModel.record.model == "BOSSxiyi" then
                            local str =  "xiyi_lihui"
                            local aniBoss2 = ArmatureNode.new(str,true)
                                :pos(display.width/2,display.height/2)
                                :addTo(self,10000)
                            aniBoss2:setAni("sb2",false,true)
                        end

                        BattleManager.pauseUpdate =true
                   
                        self.bossView:setVisible(true)
                        self.bossView:setAnimation("chuchang")
                        self.isBossWave = false

                        for k,v in pairs(BattleManager.peopleModelsTeamA) do
                            v:setState(PeopleState.Idle)
                        end
                        --定时播完warning动画 大概3秒
                        if not self.isBossWarning then
		           --          self.timeHandler = scheduler.scheduleGlobal(function()
		           --          	echo("warning动画播放完222222222222222222222222222222222222")
					        --   	self.isBossWarning = true
					        --     scheduler.unscheduleGlobal(self.timeHandler)
					        -- end, 3)
					        
					        local function setIsBossWarning( )
					        	-- echo("warning动画播放完11111111111111")
					        	self.isBossWarning = true
					        end
					        --战斗过程，3时间过长站位检测 。。。。。
				            local seq = cc.Sequence:create(cc.DelayTime:create(1),cc.CallFunc:create(setIsBossWarning))
						    self:runAction(seq)
                        end
             end
        end
end

-- 固定帧率

function BattleScene:update(dt)
    local currentTime = cc.GetCustomTime()--testSocket.gettime() --os.clock()
    local interval = (currentTime - self.lastTime) + self.slop;
    --多倍速支持
    interval = interval*BattleManager.timeScale
    local calls = 0
    if interval> 10*self.stepInterval then
        self.lastTime = currentTime 
        return
    end
    if interval < 0 then
        self.lastTime = currentTime 
        return
    end
    while (interval >= self.stepInterval) do
        if (calls == 1 and interval <= self.stepInterval) then
            break;
        end
        self:tick(self.stepInterval)
        calls = calls +1
        interval = interval - self.stepInterval;
    end
    if (calls == 0 and interval >= self.stepInterval ) then
        self:tick(self.stepInterval)
        calls = calls +1
        interval = interval - self.stepInterval;
    end
    self.slop = interval;
    self.lastTime = currentTime;
end



function BattleScene:tick(dt)
		--print("BattleScene:tick  "..tostring(dt));
	
        SpineManager:update(dt)
        BulletManager:update(dt)

        if BattleManager.pauseUpdate then
            do return end
        end

  
        if BattleManager.isGameOver then
            return
        end
                --testcode
        if  not BattleManager.startUpdate then
            do return end
        end
        BattleManager:update(dt)
        if BattleManager.state == BattleManager.State.enterBattle or BattleManager.state == BattleManager.State.startBattle then
            self.hudLayer_:update(dt)
 
                self.gameTime = self.gameTime - dt;
                self.battleTime = self.battleTime + dt
                if (BattleManager.isLegionBossWar or BattleManager.dis_npc) and self.gameTime <= 0 then
                    GlobalEventDispatch:dispatchEvent({name = "gameover", data = {isWin = END_TYPE_TIMEOUT }})
                end

                local fullSec = math.round(self.battleTime)
                if fullSec ~= self.lastGameTime then
                    self.hudLayer_:refreshTimeLabel()
                end
        end

        local keys = table.keys(BattleManager.peopleViews)
        for i=#keys,1, -1 do
             if BattleManager.peopleViews[keys[i]] ~= nil then
                BattleManager.peopleViews[keys[i]]:tick(dt)
             end
        end

        self:adjustPos()
end
--[[
*** addGroupPeople   param
]]
function BattleScene:addGroupPeople(param)
    local teameBefore, teamAfter = self:getKeyGroupTable(param.__team,param._isMe or false)
    if teameBefore then 
        param.__models = teameBefore
        param.__isFront= 1
        self:addPeople(param)
    end
    if teamAfter then 
        param.__models = teamAfter
        param.__isFront = 0
        self:addPeople(param)
    end
end

-- 将 param.__models 中的角色添加到地图中
function BattleScene:addPeople(param)
	
    local posX = {  0-4,
                    0-2,
                    0-6,
                    BattleConstants.ModelInterval+4,
                    BattleConstants.ModelInterval-4,
                    2*BattleConstants.ModelInterval
                    }


    local function getPosYs(models)
        local posY = nil
        -- if #models == 1 then
        --     posY = {BattleConstants.Middle}
        -- elseif  #models == 2 then
        --     posY = {    
        --         BattleConstants.Middle-BattleConstants.HDis,
        --         BattleConstants.Middle+BattleConstants.HDis
        --     }
        -- else
            posY = {  BattleConstants.Middle+30,
                                BattleConstants.Middle-30,
                                BattleConstants.Middle+70,
                                BattleConstants.Middle-70,
                }
        -- end 
        return  posY
    end
	
    --分前后排
    --models 为前排（后排）model数组
    local function getPosYs2(models)
        local posYs = {BattleConstants.Middle+30,
                                BattleConstants.Middle-30,
                                BattleConstants.Middle+70,
                                BattleConstants.Middle-70,
                }
        --有人站的设置为0
        for i=1,#models do
            local v = models[i]
            if v.posY ~= nil and (BattleManager.peopleViews[v.playerID_] ~= nil or v.dengchangEffect ~= nil) then
                for i=1,#posYs do
                    if v.posY == posYs[i] then
                        posYs[i] = 0
                    end
                end
            end
        end
        --不为0 的说明没有人，可以。按优先级找出空位。
        for i=1,#posYs do
            if posYs[i] ~= 0 then
                do return posYs[i] end
            end
        end
        return BattleConstants.Middle+30
    end
    local function getPosYIndexAndOffset(_posY)
    	local index,offset = 3,0
    	if _posY == BattleConstants.Middle + 70 then
    		index = 1
    	elseif _posY == BattleConstants.Middle + 30 then
    		index  = 2
    		offset = util.random(50,60)
    	elseif _posY == BattleConstants.Middle then
    		index = 3
    	elseif _posY == BattleConstants.Middle - 30 then
    		index = 4
    		offset = util.random(50,60)
    	elseif _posY == BattleConstants.Middle - 70 then
    		index = 5
    	end
    	return index,offset
    end
    local keys = param.__keys
    local isNextWave = param.__isNext or false
    local isUsePartner = param.__isUsePartner or false
    local f = 0
    if param.__isFront == 0 then
        f = BattleConstants.FrontToBehindDis
    end

    local posY 
    if isUsePartner then
        posY = getPosYs2(param.__models)
    else
        posY = getPosYs(param.__models)
    end
    
    local function getModelPosY(models,index)
        local playerIndex = 100
        for i=1,#models do
            if models[i].isMe_  == 1 then
                playerIndex = i
                break
            end
        end
        if index>playerIndex then
            index =  index -1
        end
        if index>4 then
            index = 1
        end
        return index
    end

    for i=1,#param.__models do
        local ii = i%(#posX)
        if ii == 0 then
            ii = #posX
        end
        local v = param.__models[i]
        if isNextWave == true then
            if BattleManager.peopleViews[v.playerID_] == nil then
            	local temp = posY[getModelPosY(param.__models,i)]
            	local index,offset = getPosYIndexAndOffset(temp)
            	param.pos = param.pos - offset
            	offset = 10
                v:setCellPos(param.pos + posX[ii] + f)
                local  peopleView = require("app.views.PeopleView").new(v,temp)
                self.map_people:addChild(peopleView,2500-temp)
                -- echo("offset================",offset,"v.playerID_==============",v.playerID_)
                if offset ~= 0 then
                	peopleView.peopleModel.attackDis_ = peopleView.peopleModel.attackDis_ + offset
                end
                BattleManager.peopleViews[v.playerID_] = peopleView
                if v.isBoss then
                    self.bossView = peopleView
                    self.bossView:setVisible(false)
                end
            end
        else
            --伙伴上场的位置
            if isUsePartner then
                if BattleManager.peopleViews[v.playerID_] == nil then
                    posY = getPosYs2(param.__models)   --bug 出场叠在一起，每次应该都取
                    local index,offset = getPosYIndexAndOffset(posY)
                    param.pos = 0
                    echo("offset================",offset,"v.record.name==============",v.record.name,"param.pos=======",param.pos,"index====",index)
            		param.pos = param.pos - offset
                    v:setCellPos(param.pos - f)
                    self:addDengChangPartner(v,posY,offset)
                else

                end
            else
                if BattleManager.peopleViews[v.playerID_] == nil then
                	    local temp = posY[getModelPosY(param.__models,i)]
                        if v.isMe_  == 1 then
                            temp = BattleConstants.Middle
                        end
                        if param.isZhaoHuan then
                            temp = BattleConstants.Middle
                        end
                        local index,offset = getPosYIndexAndOffset(temp)
                        if param.pos then
			            	param.pos = param.pos - offset
			        	end
                        if param.__team=="teamA" then
                            if v.isMe_  == 1 then
                                self.playerModel = v
                            end

                            if param.isZhaoHuan then
                                v:setCellPos(param.pos)
                            else
                                if BattleManager.isMultiPlayer  then
                                    v:setCellPos(BattleConstants.PlayerInitCell - posX[ii]-f-300)
                                else
                                    v:setCellPos(BattleConstants.PlayerInitCell - posX[ii]-f-300+360)
                                end
                            end
                            
                        else
                            v:setCellPos(BattleConstants.MonsterInitCell + posX[ii]+f)
                        end 
                        
                        local  peopleView = require("app.views.PeopleView").new(v,temp,param.__type)
                        self.map_people :addChild(peopleView,2500-temp+1)

                        -- echo("111111111111111offset================",offset,"v.playerID_==============",v.playerID_)
		                if offset ~= 0 then
		                	peopleView.peopleModel.attackDis_ = peopleView.peopleModel.attackDis_ + offset
		                end
			                
                        BattleManager.peopleViews[v.playerID_] = peopleView

                        if param.isZhaoHuan then
                              peopleView:playSummonOn()
                        end
                        if v.hide then
                            echo("----"..tostring(v.hide))
                            peopleView:setVisible(false)
                            v.hide = false
                        end   
                end                        
            end
        end
    end
end
--[[
	获取前排后排的,并且排序
	return : teamBefore teamAfter
]]
function BattleScene:getKeyGroupTable(__team,isMe_)

    local teamBefore = {} --前排keys  1
    local teamAfter = {} --后排 keys  2

    if __team == "teamA" then
        for k,v in pairs(BattleManager.peopleModelsTeamA) do
            if isMe_ then
                if v.isMe_ == 1 then
                    if v.isNPC then
                    else
                        if v.before_after == 1 then
                            teamBefore[#teamBefore+1] = v
                        else
                            teamAfter[#teamAfter+1] = v
                        end
                    end
                end
            else
                if v.isNPC then
                else
                    if v.before_after == 1 then
                        teamBefore[#teamBefore+1] = v
                    else
                        teamAfter[#teamAfter+1] = v
                    end
                end
            end
        end

    else
        for k,v in pairs(BattleManager.peopleModelsTeamB) do
            if v.before_after == 1 then
                teamBefore[#teamBefore+1] = v
            else
                teamAfter[#teamAfter+1] = v
            end
        end

        for k,v in pairs(BattleManager.peopleModelsTeamANPC) do
            if v.before_after == 1 then
                teamBefore[#teamBefore+1] = v
            else
                teamAfter[#teamAfter+1] = v
            end
        end
    end

    table.sort(teamBefore,function (a,b)
        return a.pos_priority < b.pos_priority
    end)
    table.sort(teamAfter,function (a,b)
        return a.pos_priority < b.pos_priority
    end)

    return teamBefore, teamAfter
end

function BattleScene:shockSceneEvent(msg)
    msg.shock_type = tonumber(msg.shock_type)
    if  msg.shock_type == 0 then
        do return end
    end
    local min2 = 4
    local min = 8
    local max = 10
    local timeMin = 0.06
    local shockNum = util.random(1,2) --晃动次数
    local actions = {}
    --TODO随机方向和大小有个范围
    for i=1,shockNum do
        local action = nil
        min = util.random(8,10)
        max = min + 5
        if msg.shock_type == 1 then  -- --横向小屏幕
            action = cc.Sequence:create(
                cc.MoveBy:create(timeMin, cc.p(min,0)), 
                cc.MoveBy:create(timeMin, cc.p(-min,0)),
                cc.MoveBy:create(timeMin, cc.p(-min,0)),
                cc.MoveBy:create(timeMin, cc.p(min,0))
            )
        elseif msg.shock_type == 2 then --横向大屏幕
            action = cc.Sequence:create(
                cc.MoveBy:create(timeMin, cc.p(max,0)), 
                cc.MoveBy:create(timeMin, cc.p(-max,0)),
                cc.MoveBy:create(timeMin, cc.p(-max,0)),
                cc.MoveBy:create(timeMin, cc.p(max,0))
            )
        elseif msg.shock_type == 3 then--纵向小屏幕
            action = cc.Sequence:create(
                cc.MoveBy:create(timeMin, cc.p(0,min)), 
                cc.MoveBy:create(timeMin, cc.p(0,-min)),
                cc.MoveBy:create(timeMin, cc.p(0,-min)),
                cc.MoveBy:create(timeMin, cc.p(0,min))
            )
        elseif msg.shock_type == 4 then --纵向大屏幕
            action = cc.Sequence:create(
                cc.MoveBy:create(timeMin, cc.p(0,max)), 
                cc.MoveBy:create(timeMin, cc.p(0,-max)),
                cc.MoveBy:create(timeMin, cc.p(0,-max)),
                cc.MoveBy:create(timeMin, cc.p(0,max))
            )
        elseif msg.shock_type == 5 then--横向小小屏幕
             action = cc.Sequence:create(
                cc.MoveBy:create(timeMin, cc.p(min2,0)), 
                cc.MoveBy:create(timeMin, cc.p(-min2,0)),
                cc.MoveBy:create(timeMin, cc.p(-min2,0)),
                cc.MoveBy:create(timeMin, cc.p(min2,0))
            )
        elseif msg.shock_type == 6 then --纵向小小屏幕
            action = cc.Sequence:create(
                cc.MoveBy:create(timeMin, cc.p(0,min2)), 
                cc.MoveBy:create(timeMin, cc.p(0,-min2)),
                cc.MoveBy:create(timeMin, cc.p(0,-min2)),
                cc.MoveBy:create(timeMin, cc.p(0,min2))
            )           
        end
        actions[#actions+1] = action
    end

    function finish()                    
        self.act=nil
    end
    if self.act==nil then
        local action = cc.CallFunc:create(finish)
        actions[#actions+1] = action
        self.act = cc.Sequence:create(actions)
        self.mapRoot:runAction(self.act)
    end
end

--添加主角大招立绘
function BattleScene:showPeoplePainting(data)
    local peoplePainting = require("app.views.battle.PeoplePainting").new(data)
    self:addChild(peoplePainting, 999)
end
--伙伴上场立绘
function BattleScene:showPartnerEnterPainting(data)
    if BattleManager.isShowPartnerEnterLayer then
        if self.partnerEnter ~= nil then
            self.partnerEnter:stopPlay()
            self.partnerEnter = nil
        end
    end
    if data.data.mtype == 1 then
        self.partnerEnter = require("app.views.battle.PartnerEnterPainting").new(data)
    else
        self.partnerEnter = require("app.views.battle.PartnerDapoPainting").new(data)
    end
    self:addChild(self.partnerEnter, 999)
end

function BattleScene:usePartnerToBattle()
    local param = {}
    param.__team = "teamA"
    param.pos = -self.map_:convertToWorldSpace(cc.p(0,0)).x / BattleConstants.CellWidth -- 500
    param.__isUsePartner = true
    self:addGroupPeople(param)
end

function BattleScene:zhaohuanPartnerToBattle()
        local _param = {}
        _param.__type = "multiplayer"
        _param.__team ="teamA"
        _param.pos = -self.map_:convertToWorldSpace(cc.p(0,0)).x / BattleConstants.CellWidth -450
        _param.isZhaoHuan = true
        self:addGroupPeople(_param)--add teama
end


function BattleScene:addDengChangPartner(model,temp,_offset)
    if model.dengchangEffect ~= nil then
        do return end 
    end 

    local  peopleView = require("app.views.PeopleView").new(model,temp)
    self.map_people :addChild(peopleView,2500-temp+1)
    peopleView:setVisible(false)
    local rect = peopleView:getBoundsInWorldSpace()

    local dengchangEffect = ArmatureNode.new("dengchang")
        :pos(BattleConstants.cellConverToGL(model.cellPos_)-rect.width/2-18, temp+40):addTo(self.map_people,2500-temp) 
    model.dengchangEffect = dengchangEffect
    model:setPosY(temp)
    if _offset ~= 0 then
    	peopleView.peopleModel.attackDis_ = peopleView.peopleModel.attackDis_ + _offset
    end

    BattleManager.peopleViews[model.playerID_] = peopleView
    -- echo("peopleView.peopleModel.pos_priority==============xcjijcjfid=============",peopleView.peopleModel.pos_priority)
    model.isSuccessZhaoHuan = false
    dengchangEffect:setAni("dengchang",false,true) 
    local msg = {}
    --震屏效果
    msg.shock_type = 4 --纵向大屏
    self:shockSceneEvent(msg)
    --self.startUpdate = true   
    dengchangEffect:registerSpineEventHandler(
        function(event)
            local function safeRemove() 
                model.dengchangEffect = nil
                self:removeFromParent(true)
                model.isSuccessZhaoHuan = true    
                dengchangEffect = nil
                BattleManager.startUpdate = true  
                self.hudLayer_:setVisible(true)
                BattleManager.startUpdate = true  
                self.hudLayer_:addStoryBuff()    
            end
            scheduler.performWithDelayGlobal(safeRemove,0)
        end
        ,SP_ANIMATION_COMPLETE
    )

    dengchangEffect:registerSpineEventHandler(
            function(event)
                if event.eventData.name=="damage" then
                    peopleView:setVisible(true)
                    --model.isSuccessZhaoHuan = true         
                    --self.startUpdate = true                       
                end
            end
          ,SP_ANIMATION_EVENT
        )
end

--显示低血量 特效
function BattleScene:showLowHpWarningEffect(data) 
    if data.param.show then
        if self.lowWarningEffect == nil then
            BattleManager.isLowHpWarningEffect = true
            self.lowWarningEffect = ArmatureNode.new("dixueyujin"):pos(display.cx,0):addTo(self,1000)
            self.lowWarningEffect:setAni("animation",true) 
            self.lowWarningEffect:setScaleX(util.getScaleX()) 
            self.lowWarningEffect:setScaleY(util.getScaleY()) 
            -- local function safeRemove()
            --     self.lowWarningEffect:removeFromParent()
            --     self.lowWarningEffect = nil
            --     self.lowWarnScheduler = nil
            -- end
            -- self.lowWarnScheduler = scheduler.performWithDelayGlobal(safeRemove,3.0)
            -- BattleManager:addScheduleHandle(self.lowWarnScheduler)
        end
    else
        if  self.lowWarningEffect ~= nil  then
            BattleManager.isLowHpWarningEffect = false
            self.lowWarningEffect:customeRemoveFromParent()
            self.lowWarningEffect = nil
        end
    end

end

function BattleScene:onExit()
    self:clearGame()
    GlobalEventDispatch :removeAllEventListenersForObject(self)
    SpineManager:clear()
    LoadingManager:clear()
    display.removeUnusedSpriteFrames()
end
--伙伴上场，暂时放到这里，等上场动画出来再改

function BattleScene:partnerDengchang()
 
    local peopleModelTeam = BattleManager.peopleModelsTeamA
    local partnerModels = {}
    local noPartner = true
    for k,v in pairs(peopleModelTeam) do
        BattleManager:usePartnerToBattle(v)    
        if v.modelType == "partner" then
            partnerModels[#partnerModels+1] = v
            noPartner = false
        end
    end
   if noPartner then
    BattleManager.startUpdate = true
    end
    self.hudLayer_:setVisible(true)
    self.hudLayer_:addStoryBuff()
      
    if #partnerModels>0 then
        local value  = math.random(1,#partnerModels)
        AudioManager:playOtherEffect(UserData:getPartnerSound(7,nil,partnerModels[value].record.partner_id))
    end


end


-- 一个粒子特效，但是因为do return end 的关系 应该是废气了
function BattleScene:addDropSmokePlist(param)
    do return end 
    --formID =message.data.playerID ,toID
    --全部飞到主角身上
    local formId =  param.data.formID
    --local toId =  param.data.toID
    local toId = self.playerModel.playerID_
    local formView = BattleManager.peopleViews[formId]
    local toView = BattleManager.peopleViews[toId]
    if toView == nil then
        return
    end
    local startPos = cc.p(formView:getPositionX()+40,formView:getPositionY()+80)
    local endPos = cc.p(toView:getPositionX(),toView:getPositionY()+50)
    --drop.plist
    -- local dropSmoke = cc.ParticleSystemQuad:create("particle/drop_smoke.plist")
    -- :pos(startPos.x,startPos.y):addTo(self.map_people,2501)

    -- cc.ParticleSystemQuad:create("particle/drop.plist")
    -- :pos(0,0):addTo(dropSmoke,1)
    -- --dropSmoke
    -- function finish()
    --     dropSmoke:removeFromParent(true)
    -- end
    -- local seqPos = cc.Sequence:create(cc.MoveTo:create(0.5, endPos),cc.CallFunc:create(finish))
    -- dropSmoke:runAction(seqPos)

    --drop.plist
    local pos = cc.p(startPos.x - endPos.x,startPos.y-endPos.y)
    local dropSmoke = cc.ParticleSystemQuad:create("particle/drop_smoke.plist")
    :pos(pos.x,pos.y):addTo(toView,1)

    cc.ParticleSystemQuad:create("particle/drop.plist")
    :pos(0,0):addTo(dropSmoke,1)

    dropSmoke.schedule = scheduler.scheduleGlobal(function()
        if dropSmoke==nil then
            --玩家死亡

            do return end 
        end
        local x = dropSmoke:getPositionX()
        local y = dropSmoke:getPositionY()
        if x>0 then
            x = x-20
        else
            x = x+20
        end
        if math.abs(x) < 30 then
            function finish()                    
                scheduler.unscheduleGlobal(dropSmoke.schedule)
                dropSmoke:removeFromParent(true)
                dropSmoke = nil 
            end
            local seqPos = cc.Sequence:create(cc.MoveTo:create(0.05, cc.p(-10, 50)),cc.CallFunc:create(finish))
            dropSmoke:runAction(seqPos)

        else
            dropSmoke:runAction(cc.MoveTo:create(0.05, cc.p(x, y)))
        end  
    end,0.05)

end
--议会boss战
function BattleScene:bossWarEndResponse(event)
	local gameOverLayer = require("app.views.WinLayerLegionBossWar").new(BattleManager.damageStatistics,self.stageID,self.damage)
    :addTo(self,POPUPVIEW_Z_ORDER)
end

--xyc---场景所有暂停，播放主角技能遇见
function BattleScene:pauseAllNode( )
	if self.isPauseAllNode then
		self.showtime = true  --showtime显示
		--暂停战斗
		self:pauseBattle_x()
		--播放特效 --后期动画名读表 加音效  DiabloShowTime  bossyujing
	    local aniBoss = ArmatureNode.new("DiabloShowTime",true)
	        :pos(display.width/2,display.height/2)
	        :addTo(self,WAITLAYER_Z_ORDER)
	    aniBoss:setAni("sb",false)
	    --播放音效
	    AudioManager:playEffect(AudioManager:getGameEffect("20"),false)

	    -- local function addTouchLayer( )
			local layer = util.newLayer()
	        layer:setTouchEnabled(true)
	        layer:addNodeEventListener(cc.NODE_TOUCH_EVENT, 
	        function(event)
	        	if event.name == "began" then
	            	-- echo(">>>>>>>>>>>>>>>>>touch______________9000000000000000000000")
					AudioManager:stopEffect(AudioManager:getGameEffect("20"))
		            local function safeRemove()
		            	-- echo("触摸后删除。。。。。。。。。。。。。。。。。。。。。。。。。。。。。。。。。。")
		            	if aniBoss then
		            		-- echo("shanchu aniBoss11111111")
		               		aniBoss:customeRemoveFromParent(true)
		               	end
		            	if layer then
		               		layer:removeFromParent()
		            	end
		            end
	               	scheduler.performWithDelayGlobal(safeRemove,0)
			        self:resumeBattle_x()
					self.isPauseAllNode = false
					self.showtime = false
		           	return true
	           	end
	        end)
	        layer:addTo(self,WAITLAYER_Z_ORDER)--触摸优先级要高解决 bug 界面下方位置点击无法关闭动画
	    -- end

	    aniBoss:registerSpineEventHandler(
        function(event)
            local function safeRemove()
            	-- echo("播放完后删除")
                if aniBoss then
            		-- echo("shanchu aniBoss222222222222222222")
               		aniBoss:customeRemoveFromParent(true)
               	end
            	if layer then
		            layer:removeFromParent()
            	end
            end
            scheduler.performWithDelayGlobal(safeRemove,0)
            self:resumeBattle_x()
			self.isPauseAllNode = false
			self.showtime = false
    --         --继续战斗
	   --      self:runAction(cc.Sequence:create(cc.DelayTime:create(2), cc.CallFunc:create(resume)))
	      	end
        ,SP_ANIMATION_COMPLETE
        )
		-- scheduler.performWithDelayGlobal(addTouchLayer,1)
	end
end


return BattleScene