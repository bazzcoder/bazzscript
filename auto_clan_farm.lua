-- ==========================================
-- BAZZ — CLAN FARM v3.1 (минимал)
-- Только 2 функции:
--   1. Хэтч последнего яйца
--   2. Ходьба к дереву за бустами
-- ==========================================

local env = getgenv()
local old = env.AUTO_CLAN_FARM
if old and type(old.Shutdown) == "function" then old.Shutdown() end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

local L = RS:WaitForChild("Library", 15)
assert(L, "[BAZZ] PS99 Library нет")

local loadModule   = require
local Save         = loadModule(L.Client.Save)
local HW           = loadModule(L.Client.HatchWarCmds)
local Types        = loadModule(L.Types.HatchWar)
local HatchingCmds = loadModule(L.Client.HatchingCmds)

-- =====================
-- CONFIG
-- =====================
local CONFIG = {
    HATCH_DELAY    = 0.10,   -- Delta-safe
    WALK_SPEED     = 200,    -- скорость ходьбы
    ARRIVE_TREE    = 8,      -- на каком расстоянии считать "дошёл до дерева"
    ARRIVE_EGG     = 8,      -- на каком расстоянии считать "дошёл до яйца"
    CHECK_BOOST    = 2.0,    -- раз в сколько секунд проверять бусты
    TIMEOUT_WALK   = 15,     -- макс время ходьбы (сек)
    CLAN_POINTS    = { huge = 100, titanic = 500, gargantuan = 5000 },
}

-- =====================
-- STATE
-- =====================
local M = {
    Alive = true, Version = "3.1-minimal", Started = os.clock(),

    AutoHatch  = false,
    AutoBoosts = false,
    AntiAFK    = true,

    -- Счётчики
    Hatches     = 0,
    RareHatches = 0,
    ClanPoints  = 0,
    BoostsUsed  = 0,

    -- Статусы
    Status = "Загружен",
    HatchStatus = "Выкл",
    BoostStatus = "Выкл",
    WalkStatus  = "Стою",

    -- Таймеры
    NextHatch = 0,
    NextBoost = 0,
}
env.AUTO_CLAN_FARM = M

-- =====================
-- УТИЛИТЫ
-- =====================
local function log(msg) print("[BAZZ] " .. tostring(msg)) end

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

local function boostSpeed()
    local h = humanoid()
    if h and h.WalkSpeed < CONFIG.WALK_SPEED then
        h.WalkSpeed = CONFIG.WALK_SPEED
    end
end

-- Ходьба к позиции
local function walkTo(pos, arriveDist, timeout, statusFn)
    arriveDist = arriveDist or CONFIG.ARRIVE_TREE
    timeout = timeout or CONFIG.TIMEOUT_WALK
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
        if statusFn then statusFn(d) end
        task.wait(0.1)
    end
    return false
end

-- =====================
-- 1. ХЭТЧ ФИНАЛЬНОГО ЯЙЦА
-- =====================
local function getFinalEgg()
    if Types and Types.ZONES then
        local count = #Types.ZONES
        if count > 0 then
            local last = Types.ZONES[count]
            return last.Egg or last.Name or last.DisplayName
        end
    end
    return nil
end

local function countPets()
    if not Save then return {} end
    local d = Save.Get()
    if not d or not d.Inventory or not d.Inventory.Pets then return {} end
    return d.Inventory.Pets
end

local function getPetTier(pet)
    local name = tostring(pet.id or pet.Name or pet.name or ""):lower()
    if name:find("gargantuan") then return "gargantuan" end
    if name:find("titanic") then return "titanic" end
    if name:find("huge") then return "huge" end
    return nil
end

local function findNewRarePet(petsBefore)
    local deadline = tick() + 0.5
    while tick() < deadline do
        task.wait(0.1)
        local petsAfter = countPets()
        for uid, pet in pairs(petsAfter) do
            if not petsBefore[uid] then
                local tier = getPetTier(pet)
                if tier then
                    local pts = CONFIG.CLAN_POINTS[tier] or 0
                    M.RareHatches = M.RareHatches + 1
                    M.ClanPoints = M.ClanPoints + pts
                    log(string.format("🎉 %s! +%d клан-поинтов", tier:upper(), pts))
                    return true
                end
            end
        end
    end
    return false
end

local function HatchStep()
    if not M.AutoHatch then M.HatchStatus = "Выкл"; return end
    if os.clock() < M.NextHatch then return end
    M.NextHatch = os.clock() + CONFIG.HATCH_DELAY

    if not HatchingCmds then M.HatchStatus = "нет HatchingCmds"; return end

    local before = countPets()

    local ok, result = pcall(function()
        return HatchingCmds.AttemptHatch()
    end)

    if ok and result ~= false and result ~= nil then
        M.Hatches = M.Hatches + 1
        task.wait(0.4)
        findNewRarePet(before)
        M.HatchStatus = string.format("Хэтчей: %d · редких: %d", M.Hatches, M.RareHatches)
    else
        M.HatchStatus = "Ошибка AttemptHatch"
        M.NextHatch = os.clock() + 1
    end
end

-- =====================
-- 2. БУСТЫ С ДЕРЕВА
-- =====================
-- Проверяем, активны ли бусты
local function areBoostsActive()
    local inst = HWInst()
    if not inst then return false end

    -- Пробуем Feature("Flames")
    local ok, flames = pcall(function() return HW.Feature("Flames") end)
    if ok and flames then
        -- Пробуем разные методы
        if type(flames.IsActive) == "function" then
            local a, b = pcall(function() return flames.IsActive() end)
            if a then return b == true end
        end
        if type(flames.GetCount) == "function" then
            local a, b = pcall(function() return flames.GetCount() end)
            if a and type(b) == "number" then return b >= 3 end
        end
        if type(flames.Active) == "boolean" then return flames.Active end
        if type(flames.Count) == "number" then return flames.Count >= 3 end
    end

    -- Fallback: проверка через Save / Types
    if Types and Types.NET_PREFIX and Types.NET_PREFIX.Flames then
        -- Не знаем точно, поэтому по умолчанию считаем НЕ активны
        return false
    end

    return false
end

-- Найти дерево в workspace
local function findTree()
    local inst = HWInst()
    if not inst then return nil end

    -- Ищем по типичным именам
    local names = {"Tree", "LuckTree", "BoostTree", "FlamesTree", "Stalk", "PumpkinStalk"}
    local model = inst.model
    if not model then return nil end

    for _, name in ipairs(names) do
        local found = model:FindFirstChild(name, true)
        if found and found:IsA("BasePart") then return found end
        if found and found:IsA("Model") and found.PrimaryPart then return found.PrimaryPart end
    end

    -- Ищем в workspace по имени
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("BasePart") then
            local n = v.Name:lower()
            if n:find("tree") or n:find("flame") or n:find("boost") then
                return v
            end
        end
    end

    return nil
end

-- Зажечь флеймы
local function lightFlames()
    local inst = HWInst()
    if not inst then return 0 end

    local lit = 0
    local flames = nil
    pcall(function() flames = HW.Feature("Flames") end)

    if flames then
        -- Метод 1: Light(i)
        if type(flames.Light) == "function" then
            for i = 1, 3 do
                local ok = pcall(function() flames.Light(i) end)
                if ok then lit = lit + 1; task.wait(0.3) end
            end
        end

        -- Метод 2: Activate()
        if lit == 0 and type(flames.Activate) == "function" then
            local ok = pcall(function() flames.Activate() end)
            if ok then lit = 1 end
        end

        -- Метод 3: Toggle(i)
        if lit == 0 and type(flames.Toggle) == "function" then
            for i = 1, 3 do
                local ok = pcall(function() flames.Toggle(i) end)
                if ok then lit = lit + 1; task.wait(0.3) end
            end
        end
    end

    -- Метод 4: InvokeCustom
    if lit == 0 and Types and Types.NET_PREFIX and Types.NET_PREFIX.Flames then
        local prefix = Types.NET_PREFIX.Flames
        for i = 1, 3 do
            local ok = pcall(function()
                return inst:InvokeCustom(prefix .. "Light", i)
            end)
            if ok then lit = lit + 1; task.wait(0.3) end
        end
        -- Или без индекса
        if lit == 0 then
            local ok = pcall(function()
                return inst:InvokeCustom(prefix .. "Light")
            end)
            if ok then lit = 1 end
        end
    end

    return lit
end

-- Ходьба к дереву и обратно к яйцу
local function goToTreeAndLight()
    M.WalkStatus = "Ищем дерево…"
    local tree = findTree()
    if not tree then
        M.WalkStatus = "Дерево не найдено"
        return 0
    end

    M.WalkStatus = "Идём к дереву…"
    local arrived = walkTo(tree.Position, CONFIG.ARRIVE_TREE, CONFIG.TIMEOUT_WALK, function(d)
        M.WalkStatus = string.format("Идём к дереву · %.0fm", d)
    end)

    if not arrived then
        M.WalkStatus = "Не дошли до дерева"
        return 0
    end

    task.wait(0.5)
    M.WalkStatus = "Зажигаем флеймы…"
    local lit = lightFlames()

    if lit > 0 then
        M.BoostsUsed = M.BoostsUsed + lit
        log("Зажжено флеймов: " .. lit)
    end

    M.WalkStatus = "Стою"
    return lit
end

-- Проверка и поход к дереву
local function BoostStep()
    if not M.AutoBoosts then M.BoostStatus = "Выкл"; return end
    if os.clock() < M.NextBoost then return end
    M.NextBoost = os.clock() + CONFIG.CHECK_BOOST

    if areBoostsActive() then
        M.BoostStatus = "Бусты активны"
        return
    end

    M.BoostStatus = "Бусты кончились — идём к дереву"
    local lit = goToTreeAndLight()
    if lit > 0 then
        M.BoostStatus = "Зажжено: " .. lit
    else
        M.BoostStatus = "Не удалось зажечь"
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
end

LP.Idled:Connect(AFKPulse)

-- =====================
-- UI
-- =====================
local ok, Rayfield = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)
if not ok or not Rayfield then warn("[BAZZ] Rayfield не загрузился"); return end

local Window = Rayfield:CreateWindow({
    Name = "BAZZ — CLAN FARM v3.1",
    LoadingTitle = "Загрузка…",
    LoadingSubtitle = "Hatch + Tree Boosts",
    ConfigurationSaving = { Enabled = true, FolderName = "BAZZ", FileName = "ClanFarmV31" },
    Keybind = "K",
})

local MainTab  = Window:CreateTab("Главная", 4483362458)
local StatsTab = Window:CreateTab("Статистика", 4483362458)

local StatusCard = MainTab:CreateParagraph({ Title = "Статус", Content = "…" })
local StatsCard  = StatsTab:CreateParagraph({ Title = "Статистика", Content = "…" })

MainTab:CreateToggle({
    Name = "🥚 Auto Hatch (последнее яйцо)",
    CurrentValue = false,
    Flag = "AutoHatch",
    Callback = function(v)
        M.AutoHatch = v
        log("Хэтч " .. (v and "ВКЛ" or "выкл"))
    end,
})

MainTab:CreateToggle({
    Name = "🔥 Auto Tree Boosts",
    CurrentValue = false,
    Flag = "AutoBoosts",
    Callback = function(v)
        M.AutoBoosts = v
        log("Бусты " .. (v and "ВКЛ" or "выкл"))
    end,
})

MainTab:CreateToggle({
    Name = "💤 Anti-AFK",
    CurrentValue = true,
    Flag = "AntiAFK",
    Callback = function(v) M.AntiAFK = v end,
})

MainTab:CreateButton({
    Name = "Stop All",
    Callback = function()
        M.AutoHatch, M.AutoBoosts = false, false
        log("Остановлено")
    end,
})

MainTab:CreateButton({
    Name = "🔍 Найти дерево (тест)",
    Callback = function()
        local tree = findTree()
        if tree then
            Rayfield:Notify({
                Title = "Дерево найдено",
                Content = tree:GetFullName(),
                Duration = 10,
            })
        else
            Rayfield:Notify({
                Title = "Дерево НЕ найдено",
                Content = "Проверь имена объектов в workspace",
                Duration = 10,
            })
        end
    end,
})

-- =====================
-- ЦИКЛ
-- =====================
task.spawn(function()
    while M.Alive do
        local ok2, err = pcall(function()
            HatchStep()
            BoostStep()
        end)
        if not ok2 then
            warn("[BAZZ] " .. tostring(err))
            task.wait(2)
        else
            task.wait(0.05)
        end
    end
end)

task.spawn(function()
    while M.Alive do
        task.wait(2)
        pcall(function()
            StatsCard:Set({ Title = "Статистика", Content = string.format(
                "🥚 Хэтчей: %d\n" ..
                "🎉 Редких (HUGE+): %d\n" ..
                "🏆 Клан-поинтов: %d\n" ..
                "🔥 Бустов зажжено: %d\n" ..
                "⏱ Сессия: %d мин",
                M.Hatches, M.RareHatches, M.ClanPoints, M.BoostsUsed,
                math.floor((os.clock() - M.Started) / 60)
            ) })
            StatusCard:Set({ Title = "Статус", Content = string.format(
                "🥚 Хэтч: %s\n" ..
                "🔥 Бусты: %s\n" ..
                "🚶 Движение: %s",
                M.HatchStatus, M.BoostStatus, M.WalkStatus
            ) })
        end)
    end
end)

task.spawn(function()
    while M.Alive do task.wait(120); AFKPulse() end
end)

function M.Shutdown()
    M.Alive = false
    M.AutoHatch, M.AutoBoosts = false, false
    if env.AUTO_CLAN_FARM == M then env.AUTO_CLAN_FARM = nil end
    log("Shutdown")
end

log("BAZZ — CLAN FARM v3.1 загружен · " .. LP.Name)
Rayfield:Notify({
    Title = "BAZZ — CLAN FARM v3.1",
    Content = "Только хэтч + бусты. Жми тумблеры!",
    Duration = 8,
})
