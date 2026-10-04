-- ==========================================
-- AUTO CLAN FARM v2.4 (SMART WALK)
-- Орбы только ближние. Стоит если никого рядом.
-- ==========================================

local env = getgenv()
local old = env.AUTO_CLAN_FARM
if old and type(old.Shutdown) == "function" then old.Shutdown() end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

local L = RS:WaitForChild("Library", 15)
assert(L, "[ACF] PS99 Library нет")

local loadModule = require
local Save         = loadModule(L.Client.Save)
local Pets         = loadModule(L.Client.PlayerPet)
local Network      = loadModule(L.Client.Network)
local HW           = loadModule(L.Client.HatchWarCmds)
local Types        = loadModule(L.Types.HatchWar)
local UpgradeCmds  = loadModule(L.Client.EventUpgradeCmds)
local CurrencyCmds = loadModule(L.Client.CurrencyCmds)

local GUImod = nil
pcall(function() GUImod = loadModule(L.Client.GUI) end)

-- =====================
-- CONFIG
-- =====================
local CONFIG = {
    WALK_SPEED      = 150,
    ORB_CHECK       = 0.2,
    ORB_MAX_RADIUS  = 80,      -- ★ не идти дальше 80м за орбом
    ORB_ARRIVE      = 12,
    ORB_TIMEOUT     = 8,
    IDLE_JITTER     = 5,       -- ★ стоим на месте ±5м
    BOSS_ARRIVE     = 8,
    BOSS_TIMEOUT    = 20,
    MACHINE_ARRIVE  = 12,
    UPGRADE_COOL    = 3,
    PUMPKIN_COOL    = 2,
    DROP_DELAY      = 0.4,
    DROP_BATCH      = 5,
}

-- =====================
-- STATE
-- =====================
local M = {
    Alive = true, Version = "2.4-smart", Started = os.clock(),
    AutoOrbs = false, AutoBreak = false, AutoDrops = false,
    AutoBoss = false, AutoProgress = true, AutoUpgrades = false,
    AutoPumpkin = false, AntiAFK = true,
    Teleports = 0, CircleHits = 0, Clicks = 0, OrbCollected = 0,
    PumpkinFed = 0, PumpkinOpened = 0,
    OrbStatus = "Выкл", BreakStatus = "Выкл", BossStatus = "Выкл",
    UpgradeStatus = "Выкл", PumpkinStatus = "Выкл",
    AFKStatus = "Выкл", Status = "Загружен",
    NextOrb = 0, NextBreak = 0, NextDrop = 0, NextBoss = 0,
    NextUpgrade = 0, NextPumpkin = 0, NextAFK = 0,
    Skipped = setmetatable({}, { __mode = "k" }),
    DropSkipped = setmetatable({}, { __mode = "k" }),
    Owned = {}, Connections = {},
    CurrentOrb = nil, OrbMoveStart = 0,
}
env.AUTO_CLAN_FARM = M

-- =====================
-- УТИЛИТЫ
-- =====================
local function log(msg) print("[ACF] " .. tostring(msg)) end

local function root()
    local c = LP.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local r = c and c:FindFirstChild("HumanoidRootPart")
    if h and h.Health > 0 and r then return r end
    return nil
end

local function humanoid()
    local c = LP.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function boostSpeed()
    local h = humanoid()
    if h and h.WalkSpeed < CONFIG.WALK_SPEED then
        h.WalkSpeed = CONFIG.WALK_SPEED
    end
end

local function HWInst()
    local ok, inst = pcall(function() return HW.Instance() end)
    return ok and inst or nil
end

local function BestZone()
    local ok, hud = pcall(function() return HW.Feature("Hud") end)
    if not ok or not hud then return 1 end
    local z = 1
    for n = 1, #Types.ZONES do if hud.Unlocked(n) then z = n end end
    return z
end

local function ZoneAt(inst, pos)
    local ground = inst.model:FindFirstChild("ZONE_GROUND")
    if not ground then return nil end
    for _, p in ipairs(ground:GetChildren()) do
        if p:IsA("BasePart") then
            local lp = p.CFrame:PointToObjectSpace(pos)
            if math.abs(lp.X) <= p.Size.X / 2 and math.abs(lp.Z) <= p.Size.Z / 2 then
                return tonumber(p.Name)
            end
        end
    end
    return nil
end

local function walkTo(pos, arriveDist, timeout, statusSetter)
    arriveDist = arriveDist or 10
    timeout = timeout or 10
    local h = humanoid()
    if not h then return false end
    boostSpeed()
    local deadline = os.clock() + timeout
    while os.clock() < deadline do
        if not M.Alive then return false end
        local r = root()
        if not r then return false end
        local d = (pos - r.Position).Magnitude
        if d < arriveDist then return true end
        h:MoveTo(pos)
        if statusSetter then statusSetter(d) end
        task.wait(0.1)
    end
    return false
end

-- =====================
-- AUTO PROGRESS
-- =====================
local lastInst, lastZone
local NextProg = 0

local function ProgressStep()
    if not M.AutoProgress or os.clock() < NextProg then return end
    NextProg = os.clock() + 0.4
    local inst = HWInst()
    if not inst then lastInst = nil; return end
    local best = BestZone()
    if lastInst ~= inst then lastInst = inst; lastZone = best; return end
    if best <= (lastZone or best) then return end
    local ground = inst.model:FindFirstChild("ZONE_GROUND")
    local target = ground and ground:FindFirstChild(tostring(best))
    if not target or not target:IsA("BasePart") then return end
    local r = root()
    if r then
        r.CFrame = target.CFrame * CFrame.new(0, target.Size.Y / 2 + 3, 0)
        r.AssemblyLinearVelocity = Vector3.zero
        lastZone = best
        log("Переход в зону " .. best)
    end
end

-- =====================
-- AUTO ORBS (SMART)
-- =====================
local function findNearestOrb()
    local inst, r = HWInst(), root()
    if not inst or not r then return nil, nil, math.huge end
    local zone = BestZone()
    local debris = workspace:FindFirstChild("__DEBRIS")
    local folder = debris and debris:FindFirstChild("HatchWarOrbs")
    if not folder then return nil, nil, math.huge end
    local nearest, nearestPos, nearestDist = nil, nil, math.huge
    for _, orb in ipairs(folder:GetChildren()) do
        if orb:IsA("Model") and (M.Skipped[orb] or 0) <= os.clock() then
            local pos = orb:GetPivot().Position
            if ZoneAt(inst, pos) == zone then
                local ground = inst.model.ZONE_GROUND:FindFirstChild(tostring(zone))
                local floorY = ground and ground.Position.Y + ground.Size.Y / 2
                if floorY and pos.Y < floorY + 10 and pos.Y > floorY - 2 then
                    local d = (pos - r.Position).Magnitude
                    -- ★ ограничение радиуса
                    if d < nearestDist and d <= CONFIG.ORB_MAX_RADIUS then
                        nearest, nearestPos, nearestDist = orb, pos, d
                    end
                end
            end
        end
    end
    return nearest, nearestPos, nearestDist
end

local function OrbStep()
    if not M.AutoOrbs then
        M.OrbStatus = "Выкл"
        M.CurrentOrb = nil
        return
    end
    local r = root()
    local h = humanoid()
    if not r or not h then return end
    boostSpeed()

    -- Есть цель — идём
    if M.CurrentOrb then
        local orb = M.CurrentOrb
        if not orb.Parent then
            M.OrbCollected = M.OrbCollected + 1
            M.CurrentOrb = nil
        else
            local pos = orb:GetPivot().Position
            local d = (pos - r.Position).Magnitude
            if d < CONFIG.ORB_ARRIVE then
                M.Skipped[orb] = os.clock() + 5
                M.OrbCollected = M.OrbCollected + 1
                M.CurrentOrb = nil
            elseif os.clock() - M.OrbMoveStart > CONFIG.ORB_TIMEOUT then
                M.Skipped[orb] = os.clock() + 15
                M.CurrentOrb = nil
            else
                h:MoveTo(pos)
                M.OrbStatus = string.format("Идём · %.1fm", d)
                return
            end
        end
    end

    if os.clock() < M.NextOrb then return end
    M.NextOrb = os.clock() + CONFIG.ORB_CHECK

    -- Проверка банка
    local okBank, bank, cap = pcall(function()
        local b, c = HW.Feature("Orbs").Bank()
        return b, c
    end)
    if okBank and bank and cap and bank >= cap then
        M.OrbStatus = "Банк полон: " .. bank .. "/" .. cap
    end

    local orb, pos, dist = findNearestOrb()
    if not orb then
        -- ★ Нет орбов в радиусе — стоим на месте ±5м, магнит подтянет
        M.OrbStatus = "Ожидание · магнит"
        local jitter = CONFIG.IDLE_JITTER
        h:MoveTo(r.Position + Vector3.new(
            math.random(-jitter, jitter), 0, math.random(-jitter, jitter)))
        return
    end
    M.CurrentOrb = orb
    M.OrbMoveStart = os.clock()
    h:MoveTo(pos)
    M.OrbStatus = string.format("Цель · %.1fm", dist)
end

-- =====================
-- AUTO DROPS
-- =====================
local DropBusy = false

local function DropStep()
    if not M.AutoDrops or DropBusy then return end
    if os.clock() < M.NextDrop then return end
    M.NextDrop = os.clock() + 1
    DropBusy = true
    task.spawn(function()
        local r = root()
        local h = humanoid()
        if not r or not h then DropBusy = false; return end
        local things = workspace:FindFirstChild("__THINGS")
        local folder = things and things:FindFirstChild("Orbs")
        if folder then
            local collected = 0
            for _, orb in ipairs(folder:GetChildren()) do
                if collected >= CONFIG.DROP_BATCH then break end
                if (orb:IsA("BasePart") or orb:IsA("Model"))
                   and (M.DropSkipped[orb] or 0) <= os.clock() then
                    local pos = orb:IsA("BasePart") and orb.Position or orb:GetPivot().Position
                    local d = (pos - r.Position).Magnitude
                    if d <= CONFIG.ORB_MAX_RADIUS then
                        M.DropSkipped[orb] = os.clock() + 15
                        walkTo(pos, 8, 5)
                        collected = collected + 1
                    end
                end
            end
        end
        DropBusy = false
    end)
end

-- =====================
-- AUTO BOSS (FIXED)
-- =====================
local BossPending, BossNext, WasFighting = false, 0, false

local function BossStep()
    if not M.AutoBoss then M.BossStatus = "Выкл"; return end
    if os.clock() < M.NextBoss then return end
    M.NextBoss = os.clock() + 0.17

    local inst = HWInst()
    if not inst then M.BossStatus = "Войди в HW"; return end

    local boss = HW.Feature("Boss")
    if not boss.IsFighting() then
        if WasFighting then WasFighting = false; BossNext = os.clock() + 8 end
        if BossPending then M.BossStatus = "Ожидание старта…"; return end
        if os.clock() < BossNext then return end
        BossNext = os.clock() + 2

        local zone = BestZone()
        local req, luck = boss.Recommended(zone)
        local coins = CurrencyCmds.Get(Types.COIN)
        if coins < req then M.BossStatus = "Монет: " .. coins .. "/" .. req; return end
        if boss.PlayerLuck(zone) < luck then
            M.BossStatus = "Удачи: " .. math.floor(boss.PlayerLuck(zone)) .. "/" .. luck
            return
        end
        local r = root()
        if not r then return end
        local interact = inst.model:FindFirstChild("INTERACT")
        local bosses = interact and interact:FindFirstChild("Bosses")
        local target = bosses and bosses:FindFirstChild("Boss" .. zone)
        if not target then M.BossStatus = "Босс не найден"; return end

        BossPending = true
        M.BossStatus = "Идём к боссу…"
        task.spawn(function()
            local arrived = walkTo(target:GetPivot().Position, CONFIG.BOSS_ARRIVE,
                CONFIG.BOSS_TIMEOUT,
                function(d) M.BossStatus = string.format("Идём · %.1fm", d) end)
            if not arrived then
                M.BossStatus = "Не дошли"
                BossPending = false
                BossNext = os.clock() + 5
                return
            end
            task.wait(0.6)
            local ok = pcall(function() return boss.RequestFight(zone) end)
            BossPending = false
            BossNext = os.clock() + (ok and 8 or 20)
            M.BossStatus = ok and "Бой запущен" or "Отказ · повтор"
        end)
        return
    end

    WasFighting = true
    local gui = nil
    pcall(function()
        if GUImod and type(GUImod.HatchWarBoss) == "function" then
            gui = GUImod.HatchWarBoss()
        end
    end)
    if gui and gui.Enabled then
        local circle = gui:FindFirstChild("LiveCircle")
        if circle and circle:IsA("GuiButton") and circle.Visible and circle.Active then
            for _, conn in ipairs(getconnections(circle.Activated)) do
                if conn.Enabled and type(conn.Function) == "function" then
                    local ok = pcall(conn.Function)
                    if ok then
                        M.CircleHits = M.CircleHits + 1
                        M.BossStatus = "Цели: " .. M.CircleHits
                        return
                    end
                end
            end
        end
    end
    pcall(function() HW.Feature("Boss").Input.PressCentre() end)
    M.Clicks = M.Clicks + 1
    M.BossStatus = "Клики: " .. M.Clicks .. " · цели: " .. M.CircleHits
end

-- =====================
-- AUTO BREAK
-- =====================
local function ReleasePets()
    for pet, rec in pairs(M.Owned) do
        pcall(function()
            if not pet.destroyed and pet:GetTarget() == rec.Assigned then
                if rec.Previous and rec.Previous.Parent then pet:SetTarget(rec.Previous)
                else pet:ClearTarget() end
            end
        end)
    end
    table.clear(M.Owned)
end

local function BreakStep()
    if not M.AutoBreak then M.BreakStatus = "Выкл"; return end
    if os.clock() < M.NextBreak then return end
    M.NextBreak = os.clock() + 0.8
    local inst, r = HWInst(), root()
    if not inst or not r then return end
    local things = workspace:FindFirstChild("__THINGS")
    local folder = things and things:FindFirstChild("Breakables")
    local targets = {}
    if folder then
        for _, v in ipairs(folder:GetChildren()) do
            if v:IsA("Model") and v:GetAttribute("ParentID") == "HatchWar" then
                table.insert(targets, v)
            end
        end
    end
    table.sort(targets, function(a, b)
        return (a:GetPivot().Position - r.Position).Magnitude <
               (b:GetPivot().Position - r.Position).Magnitude
    end)
    if #targets == 0 then M.BreakStatus = "Нет брейкаблов"; ReleasePets(); return end
    local batch, n = {}, 0
    for _, pet in pairs(Pets.GetByPlayer(LP)) do
        if not pet.destroyed and pet.owner == LP then
            n = n + 1
            local cur = pet:GetTarget()
            local tgt = table.find(targets, cur) and cur or targets[(n - 1) % #targets + 1]
            if cur ~= tgt then
                if not M.Owned[pet] then M.Owned[pet] = { Previous = cur } end
                pet:SetTarget(tgt)
                M.Owned[pet].Assigned = tgt
            end
            local uid = tgt:GetAttribute("BreakableUID")
            if uid then batch[pet.euid] = uid end
        end
    end
    if next(batch) then pcall(function() Network.Fire("Breakables_JoinPetBulk", batch) end) end
    M.BreakStatus = "Питомцев: " .. n .. " · целей: " .. #targets
end

-- =====================
-- AUTO UPGRADES
-- =====================
local function findMachine()
    local inst = HWInst()
    if not inst then return nil end
    local ok, upg = pcall(function() return HW.Feature("Upgrades") end)
    if not ok or not upg then return nil end
    local name = upg.MACHINE or "HatchWarUpgradeMachine"
    return inst.model:FindFirstChild(name, true)
end

local function UpgradeStep()
    if not M.AutoUpgrades then M.UpgradeStatus = "Выкл"; return end
    if os.clock() < M.NextUpgrade then return end
    M.NextUpgrade = os.clock() + 1
    local inst = HWInst()
    if not inst then M.UpgradeStatus = "Войди в HW"; return end
    local boss = HW.Feature("Boss")
    if boss.IsFighting() then M.UpgradeStatus = "Пауза: бой"; return end

    local tracks = HW.Feature("Upgrades").Tracks()
    local selected
    for _, dir in ipairs(tracks) do
        if not HW.Feature("Upgrades").IsMax(dir) then selected = dir; break end
    end
    if not selected then M.UpgradeStatus = "Все макс"; return end
    if not HW.Feature("Upgrades").CanAfford(selected) then
        M.UpgradeStatus = "Копим: " .. selected.Name
        M.NextUpgrade = os.clock() + 5
        return
    end

    local machine = findMachine()
    if machine then
        local r = root()
        if r then
            local d = (machine.Position - r.Position).Magnitude
            if d > CONFIG.MACHINE_ARRIVE then
                walkTo(machine.Position, CONFIG.MACHINE_ARRIVE, 10,
                    function(dd) M.UpgradeStatus = string.format("Идём к машине · %.0fm", dd) end)
            end
        end
    end

    local ok, result = pcall(function() return UpgradeCmds.Purchase(selected) end)
    if ok and result then
        M.UpgradeStatus = "Куплено: " .. selected.Name
        M.NextUpgrade = os.clock() + CONFIG.UPGRADE_COOL
    else
        M.UpgradeStatus = "Отказ: " .. tostring(result)
        M.NextUpgrade = os.clock() + 10
    end
end

-- =====================
-- AUTO PUMPKIN
-- =====================
local function PumpkinStep()
    if not M.AutoPumpkin then M.PumpkinStatus = "Выкл"; return end
    if os.clock() < M.NextPumpkin then return end
    M.NextPumpkin = os.clock() + CONFIG.PUMPKIN_COOL
    local inst = HWInst()
    if not inst then M.PumpkinStatus = "Войди в HW"; return end
    local pumpkin = HW.Feature("Pumpkin")
    local state = pumpkin.GetState()
    if not state then return end
    if state.Points >= state.Cap then
        local ok = pcall(function()
            local prefix = Types.NET_PREFIX.Pumpkin
            return inst:InvokeCustom(prefix .. "Open")
        end)
        if ok then
            M.PumpkinOpened = M.PumpkinOpened + 1
            M.PumpkinStatus = "Открыто: " .. M.PumpkinOpened
        end
    else
        M.PumpkinStatus = string.format("Тыква: %d/%d", state.Points, state.Cap)
    end
end

-- =====================
-- ANTI-AFK
-- =====================
local function AFKPulse()
    if not M.Alive or not M.AntiAFK then return end
    pcall(function()
        local vu = game:GetService("VirtualUser")
        vu:CaptureController()
        vu:Button2Down(Vector2.zero, workspace.CurrentCamera.CFrame)
        task.wait(0.1)
        vu:Button2Up(Vector2.zero, workspace.CurrentCamera.CFrame)
    end)
    M.AFKStatus = "OK · " .. os.date("%H:%M:%S")
end

if M.AntiAFK then table.insert(M.Connections, LP.Idled:Connect(AFKPulse)) end

-- =====================
-- UI
-- =====================
local ok, Rayfield = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)
if not ok or not Rayfield then warn("[ACF] Rayfield не загрузился"); return end

local Window = Rayfield:CreateWindow({
    Name = "Auto Clan Farm",
    LoadingTitle = "Загрузка…",
    LoadingSubtitle = "v2.4 · Smart Walk",
    ConfigurationSaving = { Enabled = true, FolderName = "AutoClanFarm", FileName = "v2" },
    Keybind = "K",
})

local Main  = Window:CreateTab("Главная", 4483362458)
local Orbs  = Window:CreateTab("Орбы", 4483362458)
local Farm  = Window:CreateTab("Фарм", 4483362458)
local Pump  = Window:CreateTab("Тыква", 4483362458)
local Upg   = Window:CreateTab("Апгрейды", 4483362458)
local Stats = Window:CreateTab("Статистика", 4483362458)

local StatusCard = Main:CreateParagraph({ Title = "Статус", Content = "…" })
local StatsCard  = Stats:CreateParagraph({ Title = "Статистика", Content = "…" })

Main:CreateToggle({ Name = "Auto Progress", CurrentValue = true, Flag = "AutoProgress",
    Callback = function(v) M.AutoProgress = v end })
Main:CreateToggle({ Name = "Anti-AFK", CurrentValue = true, Flag = "AntiAFK",
    Callback = function(v) M.AntiAFK = v end })
Main:CreateButton({ Name = "Stop All", Callback = function()
    M.AutoOrbs, M.AutoBreak, M.AutoDrops = false, false, false
    M.AutoBoss, M.AutoUpgrades, M.AutoPumpkin = false, false, false
    ReleasePets()
    log("Остановлено")
end })

Orbs:CreateToggle({ Name = "Auto Lucky Orbs (walk)", CurrentValue = false, Flag = "AutoOrbs",
    Callback = function(v) M.AutoOrbs = v; M.NextOrb = 0; M.CurrentOrb = nil end })
Orbs:CreateToggle({ Name = "Auto Drops", CurrentValue = false, Flag = "AutoDrops",
    Callback = function(v) M.AutoDrops = v; M.NextDrop = 0 end })
Orbs:CreateSlider({ Name = "Walk Speed", Range = {50, 300}, Increment = 10,
    CurrentValue = CONFIG.WALK_SPEED, Callback = function(v)
        CONFIG.WALK_SPEED = v
        local h = humanoid(); if h then h.WalkSpeed = v end
    end })
Orbs:CreateSlider({ Name = "Orb Radius", Range = {20, 200}, Increment = 10,
    CurrentValue = CONFIG.ORB_MAX_RADIUS, Callback = function(v) CONFIG.ORB_MAX_RADIUS = v end })

Farm:CreateToggle({ Name = "Auto Boss", CurrentValue = false, Flag = "AutoBoss",
    Callback = function(v) M.AutoBoss = v; BossNext = 0 end })
Farm:CreateToggle({ Name = "Auto Break (Candy)", CurrentValue = false, Flag = "AutoBreak",
    Callback = function(v) M.AutoBreak = v; if not v then ReleasePets() end end })

Pump:CreateToggle({ Name = "Auto Giant Pumpkin", CurrentValue = false, Flag = "AutoPumpkin",
    Callback = function(v) M.AutoPumpkin = v; M.NextPumpkin = 0 end })

Upg:CreateToggle({ Name = "Auto Event Upgrades", CurrentValue = false, Flag = "AutoUpgrades",
    Callback = function(v) M.AutoUpgrades = v; M.NextUpgrade = 0 end })

task.spawn(function()
    while M.Alive do
        task.wait(2)
        pcall(function()
            local z = BestZone()
            StatsCard:Set({ Title = "Статистика", Content = string.format(
                "Зона: %d\n" ..
                "🟢 Орбы: %s\n" ..
                "⚔️ Босс: %s\n" ..
                "🔨 Фарм: %s\n" ..
                "🍬 Тыква: %s\n" ..
                "⬆️ Апгрейды: %s\n" ..
                "📊 Орбов: %d · целей: %d · кликов: %d",
                z, M.OrbStatus, M.BossStatus, M.BreakStatus,
                M.PumpkinStatus, M.UpgradeStatus,
                M.OrbCollected, M.CircleHits, M.Clicks) })
            StatusCard:Set({ Title = "Статус", Content = "AFK: " .. M.AFKStatus })
        end)
    end
end)

table.insert(M.Connections, LP.CharacterAdded:Connect(function()
    ReleasePets()
    M.NextOrb = os.clock() + 3
    M.NextBreak = os.clock() + 3
    M.CurrentOrb = nil
end))

task.spawn(function()
    while M.Alive do
        local ok2, err = pcall(function()
            ProgressStep()
            OrbStep()
            BossStep()
            BreakStep()
            DropStep()
            UpgradeStep()
            PumpkinStep()
        end)
        if not ok2 then
            warn("[ACF] " .. tostring(err))
            task.wait(2)
        else
            task.wait(0.1)
        end
    end
end)

task.spawn(function()
    while M.Alive do task.wait(120); AFKPulse() end
end)

function M.Shutdown()
    M.Alive = false
    M.AutoOrbs, M.AutoBreak, M.AutoDrops = false, false, false
    M.AutoBoss, M.AutoUpgrades, M.AutoPumpkin = false, false, false
    ReleasePets()
    for _, c in ipairs(M.Connections) do pcall(function() c:Disconnect() end) end
    if env.AUTO_CLAN_FARM == M then env.AUTO_CLAN_FARM = nil end
    log("Shutdown")
end

log("AUTO CLAN FARM v2.4 загружен · " .. LP.Name)
Rayfield:Notify({ Title = "Auto Clan Farm v2.4", Content = "Smart Walk · орбы до 80м", Duration = 6 })
