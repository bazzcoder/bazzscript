-- ==========================================
-- AUTO CLAN FARM v2.0 (FINAL · рабочая версия)
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
local Save           = loadModule(L.Client.Save)
local Pets           = loadModule(L.Client.PlayerPet)
local Network        = loadModule(L.Client.Network)
local Breakables     = loadModule(L.Client.BreakableFrontend)
local HW             = loadModule(L.Client.HatchWarCmds)
local Types          = loadModule(L.Types.HatchWar)
local HatchingCmds   = loadModule(L.Client.HatchingCmds)
local UpgradeCmds    = loadModule(L.Client.EventUpgradeCmds)
local CurrencyCmds   = loadModule(L.Client.CurrencyCmds)
local PumpkinUtil    = loadModule(L.Util.HatchWarPumpkin)

-- =====================
-- CONFIG
-- =====================
local CONFIG = {
    HATCH_DELAY  = 0.12,
    ORB_DELAY    = 0.8,
    DROP_DELAY   = 0.6,
    DROP_BATCH   = 3,
    UPGRADE_COOL = 3,
    PUMPKIN_COOL = 2,
    CLAN_POINTS  = { huge = 100, titanic = 500, gargantuan = 5000 },
}

-- =====================
-- STATE
-- =====================
local M = {
    Alive = true, Version = "2.0-final", Started = os.clock(),
    AutoOrbs = false, AutoBreak = false, AutoDrops = false,
    AutoBoss = false, AutoProgress = true, AutoUpgrades = false,
    AutoPumpkin = false, AutoHatch = false, AntiAFK = true,
    Hatches = 0, RareHatches = 0, ClanPoints = 0,
    FarmHits = 0, Teleports = 0, CircleHits = 0, Clicks = 0,
    PumpkinFed = 0, PumpkinOpened = 0,
    OrbStatus = "Выкл", BreakStatus = "Выкл", BossStatus = "Выкл",
    UpgradeStatus = "Выкл", PumpkinStatus = "Выкл", HatchStatus = "Выкл",
    AFKStatus = "Выкл", Status = "Загружен",
    NextOrb = 0, NextBreak = 0, NextDrop = 0, NextBoss = 0,
    NextUpgrade = 0, NextPumpkin = 0, NextHatch = 0, NextAFK = 0,
    Skipped = setmetatable({}, { __mode = "k" }),
    DropSkipped = setmetatable({}, { __mode = "k" }),
    Owned = {}, Connections = {},
    CurrentEgg = "Witching Egg",
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

local function snapshotPets()
    local out = {}
    local ok, d = pcall(function() return Save.Get() end)
    if not ok or not d or not d.Inventory or not d.Inventory.Pets then return out end
    for uid in pairs(d.Inventory.Pets) do out[tostring(uid)] = true end
    return out
end

local function getPetTier(pet)
    local name = tostring(pet.id or pet.Name or pet.name or ""):lower()
    if name:find("gargantuan") then return "gargantuan" end
    if name:find("titanic") then return "titanic" end
    if name:find("huge") then return "huge" end
    return nil
end

local function checkNewPets(before)
    local ok, d = pcall(function() return Save.Get() end)
    if not ok or not d or not d.Inventory or not d.Inventory.Pets then return end
    for uid, pet in pairs(d.Inventory.Pets) do
        if not before[tostring(uid)] then
            local tier = getPetTier(pet)
            if tier then
                local pts = CONFIG.CLAN_POINTS[tier] or 0
                M.RareHatches = M.RareHatches + 1
                M.ClanPoints = M.ClanPoints + pts
                log(string.format("🎉 %s! +%d поинтов", tier:upper(), pts))
            end
        end
    end
end

-- =====================
-- AUTO HATCH
-- =====================
local function getFinalEggId()
    if Types.ZONES then
        local last = Types.ZONES[#Types.ZONES]
        if last then return last.Egg or last.Name or last.DisplayName or M.CurrentEgg end
    end
    return M.CurrentEgg
end

local function HatchStep()
    if not M.AutoHatch then M.HatchStatus = "Выкл"; return end
    if os.clock() < M.NextHatch then return end
    M.NextHatch = os.clock() + CONFIG.HATCH_DELAY

    local before = snapshotPets()
    local ok, result = pcall(function() return HatchingCmds.AttemptHatch() end)

    if ok then
        M.Hatches = M.Hatches + 1
        task.wait(0.4)
        checkNewPets(before)
        M.HatchStatus = string.format("Хэтчей: %d · редких: %d", M.Hatches, M.RareHatches)
    else
        M.HatchStatus = "Ошибка: " .. tostring(result)
        M.NextHatch = os.clock() + 1
    end
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
    local r = root()
    if not r then return end
    local ground = inst.model:FindFirstChild("ZONE_GROUND")
    local target = ground and ground:FindFirstChild(tostring(best))
    if not target or not target:IsA("BasePart") then return end
    r.CFrame = target.CFrame * CFrame.new(0, target.Size.Y / 2 + 3, 0)
    r.AssemblyLinearVelocity = Vector3.zero
    lastZone = best
    log("Зона " .. best)
end

-- =====================
-- AUTO ORBS
-- =====================
local function OrbStep()
    if not M.AutoOrbs then M.OrbStatus = "Выкл"; return end
    if os.clock() < M.NextOrb then return end
    M.NextOrb = os.clock() + CONFIG.ORB_DELAY
    local inst, r = HWInst(), root()
    if not inst or not r then return end

    local bank, cap = HW.Feature("Orbs").Bank()
    if bank >= cap then M.OrbStatus = "Полный: " .. bank .. "/" .. cap; return end

    local zone = BestZone()
    local debris = workspace:FindFirstChild("__DEBRIS")
    local folder = debris and debris:FindFirstChild("HatchWarOrbs")
    local target, nearest = nil, math.huge

    if folder then
        for _, orb in ipairs(folder:GetChildren()) do
            if orb:IsA("Model") and (M.Skipped[orb] or 0) <= os.clock() then
                local pos = orb:GetPivot().Position
                if ZoneAt(inst, pos) == zone then
                    local ground = inst.model.ZONE_GROUND:FindFirstChild(tostring(zone))
                    local floorY = ground and ground.Position.Y + ground.Size.Y / 2
                    if floorY and pos.Y < floorY + 10 and pos.Y > floorY - 2 then
                        local d = (pos - r.Position).Magnitude
                        if d < nearest then target = orb; nearest = d end
                    end
                end
            end
        end
    end
    if not target then M.OrbStatus = "Нет · зона " .. zone; return end
    local pos = target:GetPivot().Position
    M.Skipped[target] = os.clock() + 8
    r.CFrame = CFrame.new(pos + Vector3.new(0, 1, 0)) * r.CFrame.Rotation
    r.AssemblyLinearVelocity = Vector3.zero
    M.Teleports = M.Teleports + 1
    M.OrbStatus = "Сбор · " .. bank .. "/" .. cap
end

-- =====================
-- AUTO BOSS
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
        if boss.PlayerLuck(zone) < luck then M.BossStatus = "Удачи: " .. math.floor(boss.PlayerLuck(zone)) .. "/" .. luck; return end
        local r = root()
        if not r then return end
        local interact = inst.model:FindFirstChild("INTERACT")
        local bosses = interact and interact:FindFirstChild("Bosses")
        local target = bosses and bosses:FindFirstChild("Boss" .. zone)
        if not target then M.BossStatus = "Босс не найден"; return end
        BossPending = true
        M.BossStatus = "Запуск · зона " .. zone
        task.spawn(function()
            local ok = pcall(function()
                r.CFrame = target:GetPivot() * CFrame.new(0, 3, 6)
                task.wait(0.6)
                return boss.RequestFight(zone)
            end)
            BossPending = false
            BossNext = os.clock() + (ok and 8 or 20)
            M.BossStatus = ok and "Запущен" or "Отказ"
        end)
        return
    end
    WasFighting = true
    local gui = HW.Feature("GUI").HatchWarBoss()
    if not gui or not gui.Enabled then return end
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
    pcall(function() HW.Feature("Boss").Input.PressCentre() end)
    M.Clicks = M.Clicks + 1
end

-- =====================
-- AUTO BREAK (Candy)
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
-- AUTO UPGRADES (через EventUpgradeCmds.Purchase)
-- =====================
local function UpgradeStep()
    if not M.AutoUpgrades then M.UpgradeStatus = "Выкл"; return end
    if os.clock() < M.NextUpgrade then return end
    M.NextUpgrade = os.clock() + 2
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
        return
    end

    local ok, result = pcall(function() return UpgradeCmds.Purchase(selected) end)
    if ok and result then
        M.UpgradeStatus = "Куплено: " .. selected.Name
        M.NextUpgrade = os.clock() + CONFIG.UPGRADE_COOL
    else
        M.UpgradeStatus = "Отказ: " .. tostring(result)
        M.NextUpgrade = os.clock() + 15
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
-- UI (Rayfield)
-- =====================
local ok, Rayfield = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)
if not ok or not Rayfield then warn("[ACF] Rayfield не загрузился"); return end

local Window = Rayfield:CreateWindow({
    Name = "Auto Clan Farm",
    LoadingTitle = "Загрузка…",
    LoadingSubtitle = "v2.0 · Hatch Wars",
    ConfigurationSaving = { Enabled = true, FolderName = "AutoClanFarm", FileName = "v2" },
    Keybind = "K",
})

local Main    = Window:CreateTab("Главная", 4483362458)
local Orbs    = Window:CreateTab("Орбы", 4483362458)
local Farm    = Window:CreateTab("Фарм", 4483362458)
local Pump    = Window:CreateTab("Тыква", 4483362458)
local Upg     = Window:CreateTab("Апгрейды", 4483362458)
local Stats   = Window:CreateTab("Статистика", 4483362458)

local StatusCard = Main:CreateParagraph({ Title = "Статус", Content = "…" })
local StatsCard  = Stats:CreateParagraph({ Title = "Статистика", Content = "…" })

-- UI: ГЛАВНАЯ
Main:CreateToggle({ Name = "Auto Hatch Final Egg", CurrentValue = false, Flag = "AutoHatch",
    Callback = function(v) M.AutoHatch = v; M.CurrentEgg = getFinalEggId(); log("Яйцо: " .. M.CurrentEgg) end })

Main:CreateToggle({ Name = "Auto Progress", CurrentValue = true, Flag = "AutoProgress",
    Callback = function(v) M.AutoProgress = v end })

Main:CreateToggle({ Name = "Anti-AFK", CurrentValue = true, Flag = "AntiAFK",
    Callback = function(v) M.AntiAFK = v end })

Main:CreateButton({ Name = "Stop All", Callback = function()
    M.AutoHatch, M.AutoOrbs, M.AutoBreak, M.AutoDrops = false, false, false, false
    M.AutoBoss, M.AutoUpgrades, M.AutoPumpkin = false, false, false
    ReleasePets()
    log("Остановлено")
end })

-- UI: ОРБЫ
Orbs:CreateToggle({ Name = "Auto Lucky Orbs", CurrentValue = false, Flag = "AutoOrbs",
    Callback = function(v) M.AutoOrbs = v; M.NextOrb = 0 end })
Orbs:CreateToggle({ Name = "Auto Drops", CurrentValue = false, Flag = "AutoDrops",
    Callback = function(v) M.AutoDrops = v; M.NextDrop = 0 end })
Orbs:CreateSlider({ Name = "Orb Delay", Range = {0.2, 3}, Increment = 0.1, Suffix = "с",
    CurrentValue = CONFIG.ORB_DELAY, Callback = function(v) CONFIG.ORB_DELAY = v end })

-- UI: ФАРМ
Farm:CreateToggle({ Name = "Auto Boss", CurrentValue = false, Flag = "AutoBoss",
    Callback = function(v) M.AutoBoss = v; BossNext = 0 end })
Farm:CreateToggle({ Name = "Auto Break (Candy)", CurrentValue = false, Flag = "AutoBreak",
    Callback = function(v) M.AutoBreak = v; if not v then ReleasePets() end end })

-- UI: ТЫКВА
Pump:CreateToggle({ Name = "Auto Giant Pumpkin", CurrentValue = false, Flag = "AutoPumpkin",
    Callback = function(v) M.AutoPumpkin = v; M.NextPumpkin = 0 end })

-- UI: АПГРЕЙДЫ
Upg:CreateToggle({ Name = "Auto Event Upgrades", CurrentValue = false, Flag = "AutoUpgrades",
    Callback = function(v) M.AutoUpgrades = v; M.NextUpgrade = 0 end })

-- UI обновление
task.spawn(function()
    while M.Alive do
        task.wait(2)
        pcall(function()
            local z = BestZone()
            StatsCard:Set({ Title = "Статистика", Content = string.format(
                "Зона: %d · яйцо: %s\n" ..
                "🥚 Хэтчей: %d · редких: %d\n" ..
                "🏆 Клан-поинтов: %d\n" ..
                "🟢 Орбы: %s\n" ..
                "⚔️ Босс: %s\n" ..
                "🔨 Фарм: %s\n" ..
                "🍬 Тыква: %s\n" ..
                "⬆️ Апгрейды: %s",
                z, M.CurrentEgg, M.Hatches, M.RareHatches, M.ClanPoints,
                M.OrbStatus, M.BossStatus, M.BreakStatus, M.PumpkinStatus, M.UpgradeStatus) })
            StatusCard:Set({ Title = "Статус", Content =
                "Хэтч: " .. M.HatchStatus .. "\nAFK: " .. M.AFKStatus })
        end)
    end
end)

-- =====================
-- MAIN LOOP
-- =====================
table.insert(M.Connections, LP.CharacterAdded:Connect(function()
    ReleasePets()
    M.NextOrb, M.NextBreak, M.NextHatch = os.clock() + 3, os.clock() + 3, os.clock() + 3
end))

task.spawn(function()
    while M.Alive do
        local ok, err = pcall(function()
            HatchStep(); ProgressStep(); OrbStep(); BossStep()
            BreakStep(); DropStep(); UpgradeStep(); PumpkinStep()
        end)
        if not ok then warn("[ACF] " .. tostring(err)); task.wait(2)
        else task.wait(0.15) end
    end
end)

task.spawn(function()
    while M.Alive do task.wait(120); AFKPulse() end
end)

function M.Shutdown()
    M.Alive = false
    M.AutoHatch, M.AutoOrbs, M.AutoBreak, M.AutoDrops = false, false, false, false
    M.AutoBoss, M.AutoUpgrades, M.AutoPumpkin = false, false, false
    ReleasePets()
    for _, c in ipairs(M.Connections) do pcall(function() c:Disconnect() end) end
    if env.AUTO_CLAN_FARM == M then env.AUTO_CLAN_FARM = nil end
    log("Shutdown")
end

log("AUTO CLAN FARM v2.0 загружен · " .. LP.Name)
Rayfield:Notify({ Title = "Auto Clan Farm v2.0", Content = "Включи тумблеры!", Duration = 6 })
