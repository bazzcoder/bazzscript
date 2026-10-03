-- ==========================================
-- AUTO CLAN FARM v1.0 (FULL)
-- Auto Hatch через HatchingCmds.AttemptHatch()
-- ==========================================

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

-- =====================
-- CONFIG
-- =====================
local CONFIG = {
    HATCH_DELAY = 0.08,
    CHECK_DELAY = 0.5,
    ANTI_AFK = true,
    LOG_LIMIT = 30,
    
    -- Авто-поиск лучшего яйца
    AUTO_BEST_EGG = true,
    -- Если false — использовать FINAL_EGG_ID
    FINAL_EGG_ID = "Witching Egg",
    
    -- Клан-поинты за тир
    CLAN_POINTS = {
        huge = 100,
        titanic = 500,
        gargantuan = 5000,
    },
}

-- =====================
-- STATE
-- =====================
local State = {
    IsRunning = false,
    Hatches = 0,
    RareHatches = 0,
    ClanPoints = 0,
    Status = "Готов",
    StartTime = tick(),
    CurrentEgg = nil,
}

-- =====================
-- МОДУЛИ
-- =====================
local Save, Library, HatchingCmds, EggCmds, Types, HW

pcall(function() Save = require(RS.Library.Client.Save) end)
pcall(function() Library = RS:WaitForChild("Library", 10) end)

if Library then
    pcall(function() HatchingCmds = require(Library.Client.HatchingCmds) end)
    pcall(function() EggCmds = require(Library.Client.EggCmds) end)
    pcall(function() Types = require(Library.Types.HatchWar) end)
    pcall(function() HW = require(Library.Client.HatchWarCmds) end)
end

-- =====================
-- ЛОГИ
-- =====================
local LOGS = {}
local function log(msg)
    local t = os.date("%H:%M:%S")
    local s = string.format("[%s] %s", t, msg)
    table.insert(LOGS, s)
    if #LOGS > CONFIG.LOG_LIMIT then table.remove(LOGS, 1) end
    print(s)
end

-- =====================
-- RAYFIELD
-- =====================
local ok, Rayfield = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)
if not ok or not Rayfield then
    warn("[AUTO CLAN] Rayfield не загрузился")
    return
end

local Window = Rayfield:CreateWindow({
    Name = "AUTO CLAN FARM v1.0",
    LoadingTitle = "Загрузка...",
    LoadingSubtitle = "Auto Hatch + Clan Points",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "AutoClanFarm",
        FileName = "v1",
    },
    Keybind = "K",
})

local MainTab = Window:CreateTab("Главная", 4483362458)
local StatsTab = Window:CreateTab("Статистика", 4483362458)
local LogTab = Window:CreateTab("Логи", 4483362458)

-- =====================
-- UI
-- =====================
local StatsParagraph = StatsTab:CreateParagraph({
    Title = "AUTO CLAN FARM",
    Content = "Ожидание...",
})

local LogParagraph = LogTab:CreateParagraph({
    Title = "Логи",
    Content = "Ожидание...",
})

local function updateStats()
    local elapsed = tick() - State.StartTime
    pcall(function()
        StatsParagraph:Set({
            Title = "Статистика",
            Content = string.format(
                "Статус: %s\n"..
                "🥚 Яйцо: %s\n"..
                "🎯 Хэтчей: %d\n"..
                "🎉 Редких: %d\n"..
                "🏆 Клан-поинтов: %d\n"..
                "⏱ Время: %d сек\n"..
                "📊 Хэтчей/мин: %.1f",
                State.Status,
                State.CurrentEgg or "?",
                State.Hatches,
                State.RareHatches,
                State.ClanPoints,
                math.floor(elapsed),
                State.Hatches / math.max(1, elapsed / 60)
            ),
        })
    end)
end

local function updateLogUI()
    pcall(function()
        LogParagraph:Set({
            Title = "Логи",
            Content = #LOGS > 0 and table.concat(LOGS, "\n") or "Ожидание...",
        })
    end)
end

-- =====================
-- ПИТОМЦЫ И ТИР
-- =====================
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
                    State.RareHatches = State.RareHatches + 1
                    State.ClanPoints = State.ClanPoints + pts
                    log(string.format("🎉 %s! +%d клан-поинтов", tier:upper(), pts))
                    return true
                end
            end
        end
    end
    return false
end

-- =====================
-- ВЫБОР ЯЙЦА
-- =====================
local function getBestEgg()
    -- Финальное яйцо = последняя зона
    if CONFIG.AUTO_BEST_EGG and Types and Types.ZONES then
        local count = #Types.ZONES
        if count > 0 then
            local last = Types.ZONES[count]
            return last.Egg or last.Name or last.DisplayName
        end
    end
    return CONFIG.FINAL_EGG_ID
end

-- =====================
-- ХЭТЧ ЯЙЦА
-- =====================
local function hatchOnce(eggId)
    if not HatchingCmds then
        return false, "HatchingCmds не загружен"
    end

    local petsBefore = countPets()

    -- Вариант 1: Setup + Attempt
    local ok = pcall(function()
        HatchingCmds.SetupEgg(eggId)
        HatchingCmds.Enable()
        return HatchingCmds.AttemptHatch()
    end)

    -- Вариант 2: AttemptHatch(eggId)
    if not ok then
        ok = pcall(function()
            return HatchingCmds.AttemptHatch(eggId)
        end)
    end

    if ok then
        State.Hatches = State.Hatches + 1
        findNewRarePet(petsBefore)
        return true
    end
    return false, "AttemptHatch failed"
end

-- =====================
-- ЦИКЛ ФАРМА
-- =====================
local function farmLoop()
    if State.IsRunning then return end
    State.IsRunning = true
    State.Status = "Работает"

    log("Запуск AUTO CLAN FARM v1.0")

    if not HatchingCmds then
        log("❌ HatchingCmds не загружен — ты не в Hatch Wars?")
        State.Status = "Нет HatchingCmds"
        State.IsRunning = false
        return
    end

    State.CurrentEgg = getBestEgg()
    if not State.CurrentEgg then
        log("⚠️ Яйцо не найдено")
        State.Status = "Нет яйца"
        State.IsRunning = false
        return
    end

    log("Целевое яйцо: " .. tostring(State.CurrentEgg))

    while State.IsRunning do
        local ok, err = hatchOnce(State.CurrentEgg)
        if not ok then
            log("Ошибка: " .. tostring(err))
            task.wait(1)
        else
            task.wait(CONFIG.HATCH_DELAY)
        end

        if tick() % 2 < 0.1 then
            updateStats()
            updateLogUI()
        end
    end

    log("Фарм остановлен")
    State.Status = "Остановлено"
end

-- =====================
-- ДИАГНОСТИКА
-- =====================
local function runDiag()
    print("========== AUTO CLAN FARM DIAG v5 ==========")
    print("Save:", Save and "OK" or "nil")
    print("Library:", Library and "OK" or "nil")
    print("HatchingCmds:", HatchingCmds and "OK" or "nil")
    print("EggCmds:", EggCmds and "OK" or "nil")
    print("Types:", Types and "OK" or "nil")
    print("HW:", HW and "OK" or "nil")
    print("Лучшее яйцо:", tostring(getBestEgg()))
    print("========== END DIAG v5 ==========")

    log("Диагностика выведена в консоль (F9)")
end

-- =====================
-- АНТИ-АФК
-- =====================
if CONFIG.ANTI_AFK then
    local VirtualUser = game:GetService("VirtualUser")
    LP.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:SetKeyDown(0x57)
        task.wait(0.1)
        VirtualUser:SetKeyUp(0x57)
    end)
end

-- =====================
-- UI
-- =====================
MainTab:CreateToggle({
    Name = "Запустить Auto Hatch",
    CurrentValue = false,
    Flag = "StartHatch",
    Callback = function(v)
        State.IsRunning = v
        if v then
            task.spawn(farmLoop)
        else
            log("Остановлено")
        end
    end,
})

MainTab:CreateButton({
    Name = "🔍 Диагностика",
    Callback = function()
        runDiag()
        Rayfield:Notify({
            Title = "Диагностика",
            Content = "Смотри консоль (F9)",
            Duration = 5,
        })
    end,
})

MainTab:CreateButton({
    Name = "Сброс статистики",
    Callback = function()
        State.Hatches = 0
        State.RareHatches = 0
        State.ClanPoints = 0
        State.StartTime = tick()
        log("Статистика сброшена")
    end,
})

MainTab:CreateParagraph({
    Title = "Как использовать",
    Content = "Запусти D1ablo-скрипт параллельно — он делает Auto Boss, Orbs, Upgrades, Pumpkin. AUTO CLAN FARM делает только хэтч финального яйца + считает клан-поинты.",
})

-- =====================
-- ОБНОВЛЕНИЕ UI
-- =====================
task.spawn(function()
    while true do
        task.wait(2)
        updateStats()
        updateLogUI()
    end
end)

log("AUTO CLAN FARM v1.0 загружен")
State.Status = "Готов"

Rayfield:Notify({
    Title = "AUTO CLAN FARM v1.0",
    Content = "Ядро загружено. Жми Старт!",
    Duration = 8,
})
