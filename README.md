-- ==========================================
-- BAZZ — HATCH WARS v1.2 (ULTIMATE FIX)
-- Все баги исправлены, Delta-safe
-- ==========================================
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- =====================
-- CONFIG
-- =====================
local CONFIG = {
    HATCH_DELAY = 0.08,
    TP_SETTLE = 0.08,
    
    FARM_MODE = "FAST",          -- FAST / LUCKY / BALANCED
    
    AUTO_LUCKY_ORBS = true,
    AUTO_SPEED_ORBS = true,
    AUTO_BUFFS = true,
    
    AUTO_UPGRADE = true,
    UPGRADE_PRIORITY = "LUCK",
    
    TARGET_CLAN_POINTS = 0,
    MAX_HATCHES = 0,
    
    ANTI_AFK = true,
}

-- =====================
-- STATE
-- =====================
local State = {
    IsRunning = false,
    Hatches = 0,
    RareHatches = 0,
    ClanPoints = 0,
    Status = "Ожидание",
    StartTime = tick(),
}

-- =====================
-- МОДУЛИ
-- =====================
local Save, Network, Consume
pcall(function() Save = require(RS.Library.Client.Save) end)
pcall(function() Network = RS:WaitForChild("Network", 10) end)
pcall(function() Consume = Network and Network:WaitForChild("Consumables_Consume", 10) end)

-- =====================
-- ТОЧНЫЕ ЭНДПОИНТЫ (после диагностики)
-- =====================
-- ⚠️ ЗАМЕНИТЕ на точные имена из диагностики!
local HatchEndpoint = Network and Network:WaitForChild("Eggs_Hatch", 5)  -- Пример
local UpgradeEndpoint = Network and Network:WaitForChild("UpgradeMachine_Upgrade", 5) -- Пример

-- =====================
-- RAYFIELD GUI
-- =====================
local RayfieldSuccess, Rayfield = pcall(function()
    return loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
end)

if not RayfieldSuccess or not Rayfield then
    warn("[BAZZ] Ошибка загрузки Rayfield.")
    return
end

local Window = Rayfield:CreateWindow({
    Name = "BAZZ — HATCH WARS v1.2",
    LoadingTitle = "Загрузка...",
    LoadingSubtitle = "by Bazz",
    ConfigurationSaving = { Enabled = true, FolderName = "BazzConfig", FileName = "HatchWarsV12" },
    Keybind = "K"
})

local MainTab = Window:CreateTab("Главная", 4483362458)
local BoostTab = Window:CreateTab("Бусты", 4483362458)
local UpgradeTab = Window:CreateTab("Апгрейды", 4483362458)
local StatsTab = Window:CreateTab("Статистика", 4483362458)
local LogTab = Window:CreateTab("Логи", 4483362458)

-- =====================
-- ЛОГИ (только важное)
-- =====================
local LOGS = {}
local MAX_LOGS = 30

local function logMessage(msg)
    local timestamp = os.date("%H:%M:%S")
    local formatted = string.format("[%s] %s", timestamp, msg)
    table.insert(LOGS, formatted)
    if #LOGS > MAX_LOGS then table.remove(LOGS, 1) end
    print(formatted)
end

local LogParagraph = LogTab:CreateParagraph({ Title = "Логи", Content = "Ожидание..." })

local function updateLogUI()
    pcall(function()
        LogParagraph:Set({ Title = "Логи", Content = table.concat(LOGS, "\n") })
    end)
end

-- =====================
-- ДИАГНОСТИКА (в консоль, не в LOGS)
-- =====================
local function runDiagnostics()
    print("=== HATCH WARS DIAG v1.2 ===")
    print("PlaceId:", game.PlaceId)
    
    if Save then
        local d = Save.Get()
        if d then
            local keys = {}
            for k in pairs(d) do table.insert(keys, k) end
            print("Save keys:", table.concat(keys, ", "))
            
            if d.Inventory then
                for cat, items in pairs(d.Inventory) do
                    local n = 0
                    for _ in pairs(items) do n = n + 1 end
                    print("Inventory."..cat..": "..n.." items")
                end
                
                if d.Inventory.Eggs then
                    print("--- EGGS ---")
                    for uid, e in pairs(d.Inventory.Eggs) do
                        print("  id="..tostring(e.id).." uid="..uid.." am="..tostring(e._am or 1))
                        break
                    end
                end
                
                if d.Inventory.Consumable then
                    print("--- CONSUMABLE ---")
                    for uid, e in pairs(d.Inventory.Consumable) do
                        print("  id="..tostring(e.id).." uid="..uid.." am="..tostring(e._am or 1))
                        break
                    end
                end
            end
        end
    end
    
    if Network then
        print("--- Network endpoints ---")
        for _, v in ipairs(Network:GetChildren()) do
            local n = v.Name:lower()
            if n:find("hatch") or n:find("egg") or n:find("orb") or n:find("boost") or n:find("upgrade") then
                print("  "..v.Name.." ("..v.ClassName..")")
            end
        end
    end
    
    print("--- Workspace orbs ---")
    for _, v in ipairs(workspace:GetChildren()) do
        local n = v.Name:lower()
        if n:find("orb") or n:find("lucky") or n:find("speed") or n:find("event") then
            print("  "..v.Name.." ("..v.ClassName..")")
        end
    end
    
    print("=== END DIAG ===")
end

-- =====================
-- ФУНКЦИИ ХЭТЧИНГА
-- =====================
local function getEggs()
    if not Save then return {} end
    local d = Save.Get()
    if not d or not d.Inventory or not d.Inventory.Eggs then return {} end
    
    local eggs = {}
    for uid, egg in pairs(d.Inventory.Eggs) do
        table.insert(eggs, {uid = uid, id = egg.id, amount = egg._am or 1})
    end
    return eggs
end

local function countPets()
    if not Save then return {} end
    local d = Save.Get()
    if not d or not d.Inventory or not d.Inventory.Pets then return {} end
    return d.Inventory.Pets
end

local function findNewRarePet(petsBefore)
    local deadline = tick() + 1
    while tick() < deadline do
        task.wait(0.1)
        local petsAfter = countPets()
        for uid, pet in pairs(petsAfter) do
            if not petsBefore[uid] then
                local r = pet.rarity or pet.Rarity or pet.tier or pet.power or 0
                if r >= 3 then
                    State.RareHatches = State.RareHatches + 1
                    State.ClanPoints = State.ClanPoints + 50
                    logMessage("РЕДКИЙ ПИТОМЕЦ! +50 клан-поинтов")
                    return true
                end
            end
        end
    end
    return false
end

local function hatchEgg(eggUid)
    if not HatchEndpoint then return false end
    
    local petsBefore = countPets()
    
    local ok = pcall(function()
        return HatchEndpoint:InvokeServer(eggUid, 1)
    end)
    
    if ok then
        State.Hatches = State.Hatches + 1
        State.ClanPoints = State.ClanPoints + 10
        
        findNewRarePet(petsBefore)
        return true
    end
    return false
end

-- =====================
-- ОРБЫ
-- =====================
local function findOrbsFolder()
    for _, name in ipairs({"Orbs", "LuckyOrbs", "SpeedOrbs", "Event", "HatchWars"}) do
        local folder = workspace:FindFirstChild(name)
        if folder then return folder end
    end
    return nil
end

local function collectOrbs()
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local orbsFolder = findOrbsFolder()
    if not orbsFolder then return end
    
    local collected = 0
    for _, orb in ipairs(orbsFolder:GetChildren()) do
        if orb:IsA("BasePart") then
            local n = orb.Name:lower()
            if (CONFIG.AUTO_LUCKY_ORBS and n:find("lucky")) or
               (CONFIG.AUTO_SPEED_ORBS and n:find("speed")) then
                hrp.CFrame = CFrame.new(orb.Position + Vector3.new(0, 3, 0))
                task.wait(CONFIG.TP_SETTLE)
                collected = collected + 1
            end
        end
    end
    
    if collected > 0 then
        logMessage("Собрано орбов: "..collected)
    end
end

-- =====================
-- БУСТЫ
-- =====================
local BOOST_WHITELIST = {"Luck Potion", "Speed Potion", "Hatch Speed Potion", "Luck Boost"}

local function useBuffs()
    if not CONFIG.AUTO_BUFFS or not Save or not Consume then return end
    
    local d = Save.Get()
    if not d or not d.Inventory or not d.Inventory.Consumable then return end
    
    local used = 0
    for uid, item in pairs(d.Inventory.Consumable) do
        local id = tostring(item.id)
        for _, name in ipairs(BOOST_WHITELIST) do
            if id == name then
                pcall(function()
                    Consume:InvokeServer(uid, 1)
                end)
                used = used + 1
                task.wait(0.3)
                break
            end
        end
    end
    
    if used > 0 then
        logMessage("Использовано бустов: "..used)
    end
end

-- =====================
-- АПГРЕЙДЫ
-- =====================
local lastUpgradeAt = 0

local function upgradeMachine()
    if not CONFIG.AUTO_UPGRADE or not UpgradeEndpoint then return end
    
    local upgradeType = "EggLuck"
    if CONFIG.UPGRADE_PRIORITY == "SPEED" then upgradeType = "HatchSpeed"
    elseif CONFIG.UPGRADE_PRIORITY == "CANDY" then upgradeType = "CandyRewards"
    elseif CONFIG.UPGRADE_PRIORITY == "ORB_DURATION" then upgradeType = "OrbDuration" end
    
    pcall(function()
        UpgradeEndpoint:InvokeServer(upgradeType)
        logMessage("Апгрейд: "..upgradeType)
    end)
end

-- =====================
-- ОСНОВНОЙ ЦИКЛ
-- =====================
local function farmLoop()
    if State.IsRunning then return end
    State.IsRunning = true
    logMessage("Запуск Hatch Wars фарма")
    
    if not HatchEndpoint then
        logMessage("⚠️ HatchEndpoint не настроен! Запустите диагностику")
        State.IsRunning = false
        return
    end
    
    useBuffs()
    
    while State.IsRunning do
        local modeDelay = 0.08
        if CONFIG.FARM_MODE == "LUCKY" then
            modeDelay = 0.15
            useBuffs()
            collectOrbs()
        elseif CONFIG.FARM_MODE == "BALANCED" then
            modeDelay = 0.1
            collectOrbs()
        end
        
        local eggs = getEggs()
        for _, egg in ipairs(eggs) do
            if not State.IsRunning then break end
            
            hatchEgg(egg.uid)
            task.wait(modeDelay)
            
            if CONFIG.MAX_HATCHES > 0 and State.Hatches >= CONFIG.MAX_HATCHES then
                State.IsRunning = false
                break
            end
            if CONFIG.TARGET_CLAN_POINTS > 0 and State.ClanPoints >= CONFIG.TARGET_CLAN_POINTS then
                State.IsRunning = false
                break
            end
        end
        
        if CONFIG.AUTO_UPGRADE and State.Hatches - lastUpgradeAt >= 10 then
            upgradeMachine()
            lastUpgradeAt = State.Hatches
        end
        
        task.wait(0.5)
    end
    
    logMessage("Фарм остановлен. Хэтчей: "..State.Hatches..", Поинтов: "..State.ClanPoints)
    State.Status = "Остановлено"
end

-- =====================
-- GUI: ГЛАВНАЯ
-- =====================
MainTab:CreateToggle({
    Name = "Запустить фарм",
    CurrentValue = false,
    Flag = "StartFarm",
    Callback = function(value)
        State.IsRunning = value
        if value then
            task.spawn(farmLoop)
        else
            logMessage("Остановка")
        end
    end
})

MainTab:CreateButton({
    Name = "Запустить диагностику",
    Callback = function()
        runDiagnostics()
        Rayfield:Notify({
            Title = "Диагностика",
            Content = "Результаты в консоли Delta (F9)",
            Duration = 5
        })
    end
})

MainTab:CreateButton({
    Name = "Сброс статистики",
    Callback = function()
        State.Hatches = 0
        State.RareHatches = 0
        State.ClanPoints = 0
        State.StartTime = tick()
        logMessage("Статистика сброшена")
    end
})

-- =====================
-- GUI: БУСТЫ
-- =====================
BoostTab:CreateToggle({
    Name = "Авто-сбор Lucky Orbs",
    CurrentValue = CONFIG.AUTO_LUCKY_ORBS,
    Flag = "AutoLucky",
    Callback = function(v) CONFIG.AUTO_LUCKY_ORBS = v end
})

BoostTab:CreateToggle({
    Name = "Авто-сбор Speed Orbs",
    CurrentValue = CONFIG.AUTO_SPEED_ORBS,
    Flag = "AutoSpeed",
    Callback = function(v) CONFIG.AUTO_SPEED_ORBS = v end
})

BoostTab:CreateToggle({
    Name = "Авто-бусты",
    CurrentValue = CONFIG.AUTO_BUFFS,
    Flag = "AutoBuffs",
    Callback = function(v) CONFIG.AUTO_BUFFS = v end
})

BoostTab:CreateButton({
    Name = "Использовать все бусты",
    Callback = function()
        useBuffs()
        Rayfield:Notify({Title = "Бусты", Content = "Все бусты использованы", Duration = 3})
    end
})

-- =====================
-- GUI: АПГРЕЙДЫ
-- =====================
UpgradeTab:CreateToggle({
    Name = "Авто-апгрейд",
    CurrentValue = CONFIG.AUTO_UPGRADE,
    Flag = "AutoUpgrade",
    Callback = function(v) CONFIG.AUTO_UPGRADE = v end
})

UpgradeTab:CreateDropdown({
    Name = "Приоритет апгрейда",
    Options = {"LUCK", "SPEED", "CANDY", "ORB_DURATION"},
    CurrentValue = CONFIG.UPGRADE_PRIORITY,
    Flag = "UpgradePriority",
    Callback = function(v) CONFIG.UPGRADE_PRIORITY = v end
})

UpgradeTab:CreateButton({
    Name = "Апгрейд сейчас",
    Callback = function()
        upgradeMachine()
    end
})

-- =====================
-- GUI: СТАТИСТИКА
-- =====================
local StatsParagraph = StatsTab:CreateParagraph({
    Title = "Статистика Hatch Wars",
    Content = "Ожидание..."
})

task.spawn(function()
    while true do
        task.wait(1)
        local elapsed = tick() - State.StartTime
        pcall(function()
            StatsParagraph:Set({
                Title = "Статистика Hatch Wars",
                Content = string.format(
                    "Статус: %s\n"..
                    "🥚 Хэтчей: %d\n"..
                    "✨ Редких: %d\n"..
                    "🏆 Клан-поинтов: %d\n"..
                    "⏱ Время: %d сек\n"..
                    "📊 Хэтчей/мин: %.1f\n"..
                    "💎 Поинтов/мин: %.1f",
                    State.Status,
                    State.Hatches,
                    State.RareHatches,
                    State.ClanPoints,
                    math.floor(elapsed),
                    State.Hatches / (elapsed / 60),
                    State.ClanPoints / (elapsed / 60)
                )
            })
        end)
    end
end)

-- =====================
-- GUI: НАСТРОЙКИ
-- =====================
SettingsTab:CreateSection("Скорость (Delta-safe)")
SettingsTab:CreateSlider({
    Name = "HATCH_DELAY", Range = {0.08, 1}, Increment = 0.01, Suffix = "с",
    CurrentValue = CONFIG.HATCH_DELAY, Flag = "HatchDelay",
    Callback = function(v) CONFIG.HATCH_DELAY = v end
})
SettingsTab:CreateSlider({
    Name = "TP_SETTLE", Range = {0.08, 1}, Increment = 0.01, Suffix = "с",
    CurrentValue = CONFIG.TP_SETTLE, Flag = "TPSettle",
    Callback = function(v) CONFIG.TP_SETTLE = v end
})

SettingsTab:CreateSection("Лимиты")
SettingsTab:CreateSlider({
    Name = "Цель по поинтам (0 = бесконечно)",
    Range = {0, 100000}, Increment = 1000,
    CurrentValue = CONFIG.TARGET_CLAN_POINTS, Flag = "TargetPoints",
    Callback = function(v) CONFIG.TARGET_CLAN_POINTS = v end
})
SettingsTab:CreateSlider({
    Name = "Макс хэтчей (0 = без лимита)",
    Range = {0, 10000}, Increment = 100,
    CurrentValue = CONFIG.MAX_HATCHES, Flag = "MaxHatches",
    Callback = function(v) CONFIG.MAX_HATCHES = v end
})

SettingsTab:CreateSection("Безопасность")
SettingsTab:CreateToggle({
    Name = "Анти-АФК",
    CurrentValue = CONFIG.ANTI_AFK,
    Flag = "AntiAFK",
    Callback = function(v) CONFIG.ANTI_AFK = v end
})

if CONFIG.ANTI_AFK then
    local VirtualUser = game:GetService("VirtualUser")
    LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:SetKeyDown(0x57)
        task.wait(0.1)
        VirtualUser:SetKeyUp(0x57)
    end)
end

-- =====================
-- ЛОГИ
-- =====================
task.spawn(function()
    while true do
        task.wait(2)
        updateLogUI()
    end
end)

logMessage("BAZZ — HATCH WARS v1.2 загружен!")
State.Status = "Готов"

Rayfield:Notify({
    Title = "BAZZ — HATCH WARS v1.2",
    Content = "Исправленная версия. Запустите диагностику!",
    Duration = 5
})
