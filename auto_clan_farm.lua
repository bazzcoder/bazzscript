-- PS99 Event · standalone Fluent hub. No Panda SDK, no embedded keys.
-- Run separately from the main hub. Automation is OFF by default.
local env:any=getgenv()
local old:any=env.PS99EventHub
if old and type(old.Shutdown)=="function"then old.Shutdown()end
local LP=game:GetService("Players").LocalPlayer
local RS=game:GetService("ReplicatedStorage")
local L:any=RS:WaitForChild("Library",15)
assert(L,"PS99 Library unavailable")
local loadModule:any=require
local Http=game:GetService("HttpService")
local M:any={Alive=true,Version="1.0-event",Started=os.clock(),Connections={},Owned={},Errors={},
    AutoBreak=false,AutoDrops=false,AntiAFK=false,DropBusy=false,DropDelay=.6,DropBatch=3,
    LuckyDelay=.8,OrbWait=6,OrbScope="Лучшая зона",OrbMovement="Телепорт",BreakScope="Все открытые",
    BreakStatus="Выключено",DropStatus="Выключен",AFKStatus="Выключен",Assigned=0,RemovedDrops=0,
    RemovedLucky=0,LuckGained=0,AFKAttempts=0,AFKObserved=0,NextBreak=0,NextDrop=0,NextAFK=0}
env.PS99EventHub=M
local Pets:any=loadModule(L.Client.PlayerPet)
local Network:any=loadModule(L.Client.Network)
local Map:any=loadModule(L.Client.MapCmds)
local Breakables:any=loadModule(L.Client.BreakableFrontend)
M.FarmAreaTP=true;M.FarmHits=0;M.FarmRequests=0;M.NextFarmMove=0
table.insert(M.Connections,Breakables.DamageDealt:Connect(function(b:any,_health:any,_damage:any,_pet:any,owner:any)
    if M.Alive and M.AutoBreak and owner==LP and b.parentID=="HatchWar"then
        M.FarmHits+=1;M.LastFarmHit=os.clock()
    end
end))
local function root():BasePart?
    local c=LP.Character
    local h=c and c:FindFirstChildOfClass("Humanoid")
    local r=c and c:FindFirstChild("HumanoidRootPart")
    if h and h.Health>0 and r and r:IsA("BasePart")then return r end
    return nil
end
local createEvent=(function()
-- Verified against Hatch Wars client modules; no remote-name guesses.
return function(M:any, LP:Player, L:any, loadModule:any, Window:any)
    local E:any={AutoOrbs=false,AutoBoss=false,BossPending=false,BossStartNext=0,WasFighting=false,OrbStatus="Выключен",BossStatus="Выключен",
        AutoProgress=true,AutoUpgrades=false,UpgradePending=false,NextUpgrade=0,UpgradeStatus="Выключено",Priorities={},PriorityLoading=true,
        AutoPumpkin=false,PumpkinPending=false,NextPumpkin=0,PumpkinStatus="Выключена",PumpkinFed=0,PumpkinOpened=0,
        NextOrb=0,NextClick=0,NextStatus=0,Skipped=setmetatable({},{__mode="k"}),Teleports=0,Clicks=0,CircleHits=0}
    M.HatchEvent=E
    E.Http=game:GetService("HttpService")
    E.PriorityPath="PS99D1abloCloudAuth/event-priorities-"..tostring(LP.UserId)..".json"
    function E.Init()
        if E.Ready then return true end
        if os.clock()<(E.NextInit or 0)then return false end
        E.NextInit=os.clock()+10
        local ok,loaded=pcall(function()
            local module=L.Client:FindFirstChild("HatchWarCmds")
            if not module then error("Hatch Wars отсутствует в этой локации",0)end
            local data={HW=loadModule(module),Types=loadModule(L.Types.HatchWar),
                Input=loadModule(module.Boss.Input),GUI=loadModule(L.Client.GUI),
                Currency=loadModule(L.Client.CurrencyCmds),UpgradeCmds=loadModule(L.Client.EventUpgradeCmds)}
            if type(data.HW)~="table"or type(data.HW.Feature)~="function"or type(data.HW.Instance)~="function"
                or type(data.Types)~="table"or type(data.Types.UPGRADES)~="table"or type(data.Types.ZONES)~="table"
                or type(data.Input)~="table"or type(data.Input.PressCentre)~="function"
                or type(data.GUI)~="table"or type(data.GUI.HatchWarBoss)~="function"
                or type(data.Currency)~="table"or type(data.Currency.Get)~="function"
                or type(data.UpgradeCmds)~="table"or type(data.UpgradeCmds.GetTier)~="function"
                or type(data.UpgradeCmds.Purchase)~="function"then error("Неполные модули Hatch Wars",0)end
            return data
        end)
        if not ok then E.LastInitError=tostring(loaded);return false end
        for key,value in pairs(loaded)do E[key]=value end
        E.Ready=true;E.LastInitError=nil
        return true
    end
    function E.BestZone()
        local hud=E.HW.Feature("Hud");local zone=1
        for n=1,#E.Types.ZONES do if hud.Unlocked(n)then zone=n end end
        return zone
    end
    function E.CancelStart()
        if E.StartTask then pcall(task.cancel,E.StartTask);E.StartTask=nil end
        E.BossPending=false
    end
    function E.ProgressStep()
        if not E.AutoProgress or os.clock()<(E.NextProgress or 0)then return end
        E.NextProgress=os.clock()+.4
        if not E.Init()then return end
        local inst=E.HW.Instance()
        if not inst then E.ProgressInstance=nil;return end
        local best=E.BestZone()
        if E.ProgressInstance~=inst then
            E.ProgressInstance=inst;E.ProgressZone=best;return
        end
        if best<=(E.ProgressZone or best)then return end
        if E.PumpkinPending or E.HW.Feature("Boss").IsFighting()or E.HW.Feature("Boss").HudHidden or M.Farm or M.AutoRank then return end
        local c=LP.Character;local r=c and c:FindFirstChild("HumanoidRootPart")
        local h=c and c:FindFirstChildOfClass("Humanoid")
        local ground=inst.model:FindFirstChild("ZONE_GROUND")
        local target=ground and ground:FindFirstChild(tostring(best))
        if not r or not h or h.Health<=0 or not target or not target:IsA("BasePart")then return end
        r.CFrame=target.CFrame*CFrame.new(0,target.Size.Y/2+3,0)
        r.AssemblyLinearVelocity=Vector3.zero
        E.ProgressZone=best;E.OrbStatus="Новая зона: "..best
        E.NextOrb=os.clock()+1;E.BossStartNext=os.clock()+3
    end
    function E.LoadPriorities()
        if not E.Init()then return false end
        local defaults={OrbPower=1,OrbBank=2,OrbSpawn=3,OrbReach=4,RareHunter=5,ChainTime=6,PumpkinGrowth=7,PumpkinLoot=8}
        for name,id in pairs(E.Types.UPGRADES)do E.Priorities[id]=defaults[name]or 0 end
        local ok,data=pcall(function()
            if not isfile(E.PriorityPath)then return nil end
            local raw=readfile(E.PriorityPath);if #raw>8192 then return nil end
            return E.Http:JSONDecode(raw)
        end)
        if ok and type(data)=="table"and data.Version==1 and data.UserId==LP.UserId and type(data.Priorities)=="table"then
            for id in pairs(E.Priorities)do
                local p=data.Priorities[id]
                if type(p)=="number"and p==p and p>=0 and p<=99 and p%1==0 then E.Priorities[id]=p end
            end
        end
        local tracks=table.clone(E.HW.Feature("Upgrades").Tracks())
        table.sort(tracks,function(a,b)
            local pa,pb=E.Priorities[a._id]or 0,E.Priorities[b._id]or 0
            if pa==0 then pa=math.huge end;if pb==0 then pb=math.huge end
            if pa~=pb then return pa<pb end
            if (a.Order or 0)~=(b.Order or 0)then return (a.Order or 0)<(b.Order or 0)end
            return a._id<b._id
        end)
        E.PriorityOrder={};E.PriorityDirs={};local seen={}
        for _,dir in ipairs(tracks)do E.PriorityDirs[dir._id]=dir end
        if ok and type(data)=="table"and data.Version==1 and data.UserId==LP.UserId and type(data.Order)=="table"then
            for _,id in ipairs(data.Order)do
                if type(id)=="string"and E.PriorityDirs[id]and not seen[id]then
                    seen[id]=true;table.insert(E.PriorityOrder,id)
                end
            end
        end
        for _,dir in ipairs(tracks)do
            if not seen[dir._id]then table.insert(E.PriorityOrder,dir._id)end
        end
        E.ReindexPriorities()
        return true
    end
    function E.EnsurePriorities()
        if E.PrioritiesReady then return true end
        if os.clock()<(E.NextPriorities or 0)then return false end
        E.NextPriorities=os.clock()+10
        local ok,ready=pcall(E.LoadPriorities)
        E.PrioritiesReady=ok and ready==true
        if not ok then E.LastInitError=tostring(ready)end
        return E.PrioritiesReady
    end
    function E.ReindexPriorities()
        for index,id in ipairs(E.PriorityOrder)do
            if (E.Priorities[id]or 0)>0 then E.Priorities[id]=index end
        end
    end
    function E.RefreshPriorityUI()
        local lines={}
        for _,id in ipairs(E.PriorityOrder)do
            local dir=E.PriorityDirs[id]
            table.insert(lines,(id==E.SelectedUpgradeId and "➜ "or "    ")..dir.Name..((E.Priorities[id]or 0)==0 and " · отключён"or ""))
        end
        if E.PriorityCard then E.PriorityCard:SetDesc(table.concat(lines,"\n"))end
        if E.PriorityEnableButton then
            local enabled=(E.Priorities[E.SelectedUpgradeId]or 0)>0
            E.PriorityEnableButton:SetTitle(enabled and "Отключить выбранный буст"or "Включить выбранный буст")
        end
    end
    function E.MovePriority(delta:number)
        local index=table.find(E.PriorityOrder,E.SelectedUpgradeId)
        if not index then return end
        local target=index+delta
        if target<1 or target>#E.PriorityOrder then return end
        E.PriorityOrder[index],E.PriorityOrder[target]=E.PriorityOrder[target],E.PriorityOrder[index]
        E.ReindexPriorities();E.NextUpgrade=0;E.RefreshPriorityUI();E.SavePriorities()
    end
    function E.ToggleSelectedPriority()
        local id=E.SelectedUpgradeId
        local index=table.find(E.PriorityOrder,id)
        if not index then return end
        E.Priorities[id]=(E.Priorities[id]or 0)>0 and 0 or index
        E.ReindexPriorities();E.NextUpgrade=0;E.RefreshPriorityUI();E.SavePriorities()
    end
    function E.SavePriorities()
        if E.PriorityLoading then return end
        local ok=pcall(function()
            if type(makefolder)=="function"then makefolder("PS99D1abloCloudAuth")end
            writefile(E.PriorityPath,E.Http:JSONEncode({Version=1,UserId=LP.UserId,Priorities=E.Priorities,Order=E.PriorityOrder}))
        end)
        if not ok then E.UpgradeStatus="Не удалось сохранить приоритеты"end
    end
    function E.SelectUpgrade()
        local tracks=E.HW.Feature("Upgrades").Tracks()
        local selected=nil;local priority=math.huge
        for _,dir in ipairs(tracks)do
            local p=E.Priorities[dir._id]or 0
            if p>0 and not E.HW.Feature("Upgrades").IsMax(dir)then
                if p<priority or (p==priority and selected and (dir.Order or 0)<(selected.Order or 0))then
                    selected=dir;priority=p
                end
            end
        end
        return selected
    end
    function E.CancelUpgrade()
        if E.UpgradeTask then pcall(task.cancel,E.UpgradeTask);E.UpgradeTask=nil end
        E.UpgradePending=false
    end
    function E.UpgradeStep()
        if not E.AutoUpgrades then E.UpgradeStatus="Выключено";return end
        if E.PumpkinPending or E.UpgradePending or os.clock()<E.NextUpgrade then return end
        E.NextUpgrade=os.clock()+2
        if not E.Init()or not E.HW.Instance()then E.UpgradeStatus="Войди в Hatch Wars";return end
        if not E.EnsurePriorities()then E.UpgradeStatus="Ивентовые апгрейды недоступны в этой локации";return end
        if E.BossPending or E.HW.Feature("Boss").IsFighting()or E.HW.Feature("Boss").HudHidden then E.UpgradeStatus="Пауза: бой";return end
        local dir=E.SelectUpgrade()
        if not dir then E.UpgradeStatus="Все выбранные бусты максимальны / отключены";return end
        local tier=E.UpgradeCmds.GetTier(dir)
        local cost=E.HW.Feature("Upgrades").Cost(dir,tier+1)
        if cost:CountExact()<cost:GetAmount()then
            E.UpgradeStatus="Копим на "..dir.Name..": "..cost:CountExact().."/"..cost:GetAmount();return
        end
        local inst=E.HW.Instance()
        E.UpgradePending=true;E.UpgradeStatus="Покупаем "..dir.Name.." · уровень "..(tier+1)
        E.UpgradeTask=task.spawn(function()
            local ok,result=pcall(function()
                if not M.Alive or not E.AutoUpgrades or E.HW.Instance()~=inst then return false end
                if E.SelectUpgrade()~=dir or E.UpgradeCmds.GetTier(dir)~=tier
                    or not E.HW.Feature("Upgrades").CanAfford(dir)then return false end
                return E.UpgradeCmds.Purchase(dir)
            end)
            E.UpgradePending=false;E.UpgradeTask=nil
            E.NextUpgrade=os.clock()+(ok and result and 3 or 15)
            if M.Alive and E.AutoUpgrades then
                E.UpgradeStatus=ok and result and ("Куплено: "..dir.Name.." · уровень "..(tier+1))or "Покупка отклонена · повтор через 15 с"
            end
        end)
    end
    function E.PumpkinInit()
        if E.PumpkinUtil then return true end
        if not E.Init()then return false end
        E.PumpkinUtil=loadModule(L.Util.HatchWarPumpkin);E.Items=loadModule(L.Items)
        return true
    end
    function E.BuildPumpkinPlan(spare:any,state:any)
        local plan={};local total=0;local remaining=state.Cap-state.Points
        if remaining<=0 or type(spare)~="table"then return plan,total end
        local growth=E.PumpkinUtil.Growth(LP);local candidates={}
        local strongest=-math.huge;local keepUID=nil;local alreadyKept=false
        for uid,amount in pairs(spare)do
            if type(uid)=="string"and type(amount)=="number"and amount==amount and amount>=0 and amount<math.huge then
                local pet=E.Items.Pet:Get(uid)
                if pet and pet:GetExclusiveLevel()==0 then
                    local points=E.PumpkinUtil.UnitPoints(pet,growth)
                    local owned=math.floor(pet:GetAmount())
                    local count=math.floor(math.min(amount,owned))
                    if owned>0 and type(points)=="number"and points>0 and points<math.huge then
                        local protected=pet:IsLocked()or count<owned
                        if points>strongest then
                            strongest=points;keepUID=uid;alreadyKept=protected
                        elseif points==strongest then
                            alreadyKept=alreadyKept or protected
                            if uid<keepUID then keepUID=uid end
                        end
                        if not pet:IsLocked()and count>0 then
                            table.insert(candidates,{UID=uid,Count=count,Points=points})
                        end
                    end
                end
            end
        end
        if not alreadyKept and keepUID then
            for _,pet in ipairs(candidates)do if pet.UID==keepUID then pet.Count=math.max(0,pet.Count-1)end end
        end
        table.sort(candidates,function(a,b)
            if a.Points~=b.Points then return a.Points<b.Points end
            return a.UID<b.UID
        end)
        for _,pet in ipairs(candidates)do
            local count=math.min(pet.Count,math.ceil(remaining/pet.Points),128-total)
            if count>0 then plan[pet.UID]=count;total+=count;remaining-=count*pet.Points end
            if remaining<=0 or total>=128 then break end
        end
        return plan,total
    end
    function E.CancelPumpkin()
        if E.PumpkinTask then pcall(task.cancel,E.PumpkinTask);E.PumpkinTask=nil end
        E.PumpkinPending=false
    end
    function E.PumpkinCanAct(inst:any)
        local boss=E.HW.Feature("Boss")
        return M.Alive and E.AutoPumpkin and E.HW.Instance()==inst and not E.BossPending
            and not boss.IsFighting()and not boss.HudHidden and not M.Farm and not M.AutoRank
    end
    function E.PumpkinDelay()
        local ok,cooldown=pcall(E.PumpkinUtil.Cooldown)
        if not ok or type(cooldown)~="number"or cooldown~=cooldown or cooldown<0 or cooldown==math.huge then cooldown=1 end
        return math.max(1.25,cooldown+.25)
    end
    function E.PumpkinStep()
        if not E.AutoPumpkin then E.PumpkinStatus="Выключена";return end
        if E.PumpkinPending or E.UpgradePending or os.clock()<E.NextPumpkin then return end
        E.NextPumpkin=os.clock()+3
        if not E.PumpkinInit()or not E.HW.Instance()then E.PumpkinStatus="Войди в Hatch Wars";return end
        if not E.PumpkinUtil.Enabled()then E.PumpkinStatus="Тыква отключена игрой";return end
        local inst=E.HW.Instance()
        if not E.PumpkinCanAct(inst)then E.PumpkinStatus="Пауза: бой / фарм";return end
        local pumpkin=E.HW.Feature("Pumpkin");local state=pumpkin.GetState()
        if not state or type(state.Points)~="number"or type(state.Cap)~="number"or state.Cap<=0 then E.PumpkinStatus="Ожидание состояния";return end
        if E.PumpkinAwait and E.PumpkinAwait.Points==state.Points and E.PumpkinAwait.Cap==state.Cap and E.PumpkinAwait.Opens==state.Opens then
            E.PumpkinStatus="Ожидание подтверждения состояния";return
        end
        E.PumpkinAwait=nil
        E.PumpkinPending=true;E.PumpkinStatus="Проверка запасных слабых питомцев…"
        E.PumpkinTask=task.spawn(function()
            local acted=false
            local ok,result=pcall(function()
                local prefix=E.Types.NET_PREFIX.Pumpkin
                local count=0;local plan={}
                if state.Points<state.Cap then
                    local spare=inst:InvokeCustom(prefix.."Spare")
                    if not E.PumpkinCanAct(inst)then return false end
                    state=pumpkin.GetState()
                    if not state then return false end
                    plan,count=E.BuildPumpkinPlan(spare,state)
                    if state.Points<state.Cap and count==0 then E.PumpkinStatus="Нет запасных слабых питомцев · ждём новые";return true end
                end
                local c=LP.Character;local r=c and c:FindFirstChild("HumanoidRootPart")
                local h=c and c:FindFirstChildOfClass("Humanoid")
                local debris=workspace:FindFirstChild("__DEBRIS")
                local anchor=debris and type(pumpkin.Anchor)=="string"and debris:FindFirstChild(pumpkin.Anchor)
                local interact=inst.model:FindFirstChild("INTERACT");local stalk=interact and interact:FindFirstChild("Stalk")
                if not anchor and stalk and type(pumpkin.Anchor)=="string"then anchor=stalk:FindFirstChild(pumpkin.Anchor,true)end
                if not r or not h or h.Health<=0 or not anchor or not anchor:IsA("BasePart")then
                    E.PumpkinStatus="Ожидание персонажа / площадки тыквы";return true
                end
                if not E.PumpkinCanAct(inst)then return false end
                local top=debris and debris:FindFirstChild("HatchWarPumpkinTop")
                local target=anchor
                if pumpkin.Mode=="stalk"and top and top:IsA("BasePart")then target=top end
                r.CFrame=target.CFrame*CFrame.new(0,target.Size.Y/2+3,0);r.AssemblyLinearVelocity=Vector3.zero
                task.wait(.6)
                if not E.PumpkinCanAct(inst)or not r.Parent or (r.Position-anchor.Position).Magnitude>E.PumpkinUtil.Reach()then return false end
                state=pumpkin.GetState();if not state then return false end
                local operation="Open"
                if state.Points<state.Cap then
                    local spare=inst:InvokeCustom(prefix.."Spare")
                    if not E.PumpkinCanAct(inst)then return false end
                    state=pumpkin.GetState();if not state then return false end
                    if state.Points<state.Cap then
                        plan,count=E.BuildPumpkinPlan(spare,state)
                        if count==0 then E.PumpkinStatus="Нет запасных слабых питомцев · ждём новые";return true end
                        operation="Feed"
                    end
                end
                if not E.PumpkinCanAct(inst)then return false end
                local previous={Points=state.Points,Cap=state.Cap,Opens=state.Opens}
                E.PumpkinStatus=operation=="Feed"and ("Заполнение: "..count.." слабых питомцев")or "Открываем полную тыкву…"
                local accepted,reason
                if operation=="Feed"then accepted,reason=inst:InvokeCustom(prefix..operation,plan)
                else accepted,reason=inst:InvokeCustom(prefix..operation)end
                if not accepted then E.PumpkinStatus="Игра отклонила действие: "..tostring(reason);return false end
                acted=true
                E.PumpkinAwait=previous
                if operation=="Feed"then E.PumpkinFed+=count;E.PumpkinStatus="Добавлено питомцев: "..count
                else E.PumpkinOpened+=1;E.PumpkinStatus="Тыква открыта · награды выдаёт игра"end
                return true
            end)
            E.PumpkinPending=false;E.PumpkinTask=nil
            E.NextPumpkin=os.clock()+(ok and result and (acted and E.PumpkinDelay()or 3)or 15)
            if not ok then E.PumpkinStatus="Ошибка тыквы: "..tostring(result)end
        end)
    end
    function E.Stop()
        E.AutoOrbs=false;E.AutoBoss=false;E.AutoUpgrades=false;E.AutoProgress=false
        E.AutoPumpkin=false;E.CancelStart();E.CancelUpgrade();E.CancelPumpkin()
    end
    function E.ZoneAt(inst:any,pos:Vector3)
        local ground=inst.model:FindFirstChild("ZONE_GROUND")
        if not ground then return nil end
        for _,part in ipairs(ground:GetChildren())do
            if part:IsA("BasePart")then
                local p=part.CFrame:PointToObjectSpace(pos)
                if math.abs(p.X)<=part.Size.X/2 and math.abs(p.Z)<=part.Size.Z/2 then return tonumber(part.Name)end
            end
        end
        return nil
    end
    function E.OrbStep()
        if not E.AutoOrbs then E.OrbStatus="Выключен";return end
        if os.clock()<E.NextOrb then return end
        E.NextOrb=os.clock()+.8
        if not E.Init()then E.OrbStatus="Ивент недоступен";return end
        local inst=E.HW.Instance()
        if not inst then E.OrbStatus="Войди в Hatch Wars";return end
        if E.PumpkinPending then E.OrbStatus="Пауза: гигантская тыква";return end
        if E.BossPending or E.HW.Feature("Boss").IsFighting()or E.HW.Feature("Boss").HudHidden then E.OrbStatus="Пауза: бой с боссом";return end
        if M.Farm or M.AutoRank then E.OrbStatus="Выключи Auto Farm / Auto Rank";return end
        local c=LP.Character;local r=c and c:FindFirstChild("HumanoidRootPart")
        local h=c and c:FindFirstChildOfClass("Humanoid")
        if not r or not h or h.Health<=0 then E.OrbStatus="Ожидание персонажа";return end
        local bank,cap=E.HW.Feature("Orbs").Bank()
        if bank>=cap then E.OrbStatus="Банк полный: "..bank.."/"..cap;return end
        local zone=E.BestZone()
        local debris=workspace:FindFirstChild("__DEBRIS")
        local folder=debris and debris:FindFirstChild("HatchWarOrbs")
        local target:Model?=nil;local nearest=math.huge
        if folder then for _,orb in ipairs(folder:GetChildren())do
            if orb:IsA("Model")and (E.Skipped[orb]or 0)<=os.clock()then
                local pos=orb:GetPivot().Position
                if E.ZoneAt(inst,pos)==zone then
                    local ground=inst.model.ZONE_GROUND:FindFirstChild(tostring(zone))
                    local floorY=ground and ground.Position.Y+ground.Size.Y/2
                    if floorY and pos.Y<floorY+10 and pos.Y>floorY-2 then
                        local d=(pos-r.Position).Magnitude
                        if d<nearest then target=orb;nearest=d end
                    end
                end
            end
        end end
        if not target then E.OrbStatus="Нет доступных орбов · зона "..zone;return end
        local pos=target:GetPivot().Position
        E.Skipped[target]=os.clock()+8
        r.CFrame=CFrame.new(pos+Vector3.new(0,1,0))*r.CFrame.Rotation
        r.AssemblyLinearVelocity=Vector3.zero
        E.Teleports+=1
        E.OrbStatus="Сбор · зона "..zone.." · банк "..bank.."/"..cap
    end
    function E.BossStep()
        if not E.AutoBoss then E.BossStatus="Выключен";return end
        if os.clock()<E.NextClick then return end
        E.NextClick=os.clock()+.17
        if not E.Init()or not E.HW.Instance()then E.BossStatus="Войди в Hatch Wars";return end
        local boss=E.HW.Feature("Boss")
        if not boss.IsFighting()then
            if E.PumpkinPending then E.BossStatus="Пауза: гигантская тыква";return end
            if E.WasFighting then E.WasFighting=false;E.BossStartNext=os.clock()+8 end
            if E.BossPending then E.BossStatus="Ожидание старта боя…";return end
            if os.clock()<E.BossStartNext then return end
            E.BossStartNext=os.clock()+2
            local inst=E.HW.Instance();local zone=E.BestZone()
            local required,luck=boss.Recommended(zone)
            local balance=E.Currency.Get(E.Types.COIN)
            if balance<required then
                E.BossStatus="Ожидание монет: "..tostring(balance).."/"..tostring(required);return
            end
            if boss.PlayerLuck(zone)<luck then
                E.BossStatus="Ожидание удачи: "..math.floor(boss.PlayerLuck(zone)).."/"..tostring(luck);return
            end
            if M.Farm or M.AutoRank then E.BossStatus="Выключи Auto Farm / Auto Rank";return end
            local character=LP.Character;local r=character and character:FindFirstChild("HumanoidRootPart")
            local h=character and character:FindFirstChildOfClass("Humanoid")
            if not r or not h or h.Health<=0 then E.BossStatus="Ожидание персонажа";return end
            local interact=inst.model:FindFirstChild("INTERACT")
            local bosses=interact and interact:FindFirstChild("Bosses")
            local target=bosses and bosses:FindFirstChild("Boss"..zone)
            if not target or not target:IsA("Model")then E.BossStatus="Ожидание модели босса";return end
            E.BossPending=true;E.BossStatus="Запуск босса · зона "..zone
            E.StartTask=task.spawn(function()
                local ok,result=pcall(function()
                    if not M.Alive or not E.AutoBoss or E.HW.Instance()~=inst then return false end
                    local currentCoins,currentLuck=boss.Recommended(zone)
                    if E.Currency.Get(E.Types.COIN)<currentCoins or boss.PlayerLuck(zone)<currentLuck then return false end
                    r.CFrame=target:GetPivot()*CFrame.new(0,3,6)
                    r.AssemblyLinearVelocity=Vector3.zero
                    task.wait(.6)
                    if not M.Alive or not E.AutoBoss or E.HW.Instance()~=inst then return false end
                    if E.Currency.Get(E.Types.COIN)<currentCoins or boss.PlayerLuck(zone)<currentLuck then return false end
                    return boss.RequestFight(zone)
                end)
                E.BossPending=false;E.StartTask=nil
                E.BossStartNext=os.clock()+(ok and result and 8 or 20)
                if M.Alive and E.AutoBoss then
                    E.BossStatus=ok and result and "Бой запущен"or "Старт отклонён · повтор через 20 с"
                end
            end)
            return
        end
        E.WasFighting=true
        local gui=E.GUI.HatchWarBoss()
        if not gui or not gui.Enabled then return end
        local circle=gui:FindFirstChild("LiveCircle")
        if circle and circle:IsA("GuiButton")and circle.Visible and circle.Active then
            for _,connection in ipairs(getconnections(circle.Activated))do
                if connection.Enabled and type(connection.Function)=="function"then
                    local ok=pcall(connection.Function)
                    if ok then E.CircleHits+=1;E.BossStatus="Попаданий по целям: "..E.CircleHits;return end
                end
            end
        end
        if E.Input.PressCentre()then E.Clicks+=1 end
        E.BossStatus="Клики: "..E.Clicks.." · цели: "..E.CircleHits
    end
    function E.Status()
        if not E.Init()then return "Event недоступен в этой локации / версии игры. Остальные вкладки работают.\n"..tostring(E.LastInitError or "Ожидание модулей"):sub(1,220)end
        if not E.HW.Instance()then return "Войди в Hatch Wars"end
        local z=E.BestZone();local boss=E.HW.Feature("Boss")
        local coins,luck=boss.Recommended(z);local bank,cap=E.HW.Feature("Orbs").Bank()
        return string.format("Зона %d · %s\nОрбы: %s/%s · удача: %.0f / %.0f · шанс: %.1f%%\nМонет на бой: %s\nОрбы: %s\nБосс: %s",
            z,E.Types.ZONES[z].Name or E.Types.ZONES[z].DisplayName or E.Types.ZONES[z].Egg,
            tostring(bank),tostring(cap),boss.PlayerLuck(z),luck,boss.WinChance(z)*100,tostring(coins),E.OrbStatus,E.B
