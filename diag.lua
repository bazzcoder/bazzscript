-- ==========================================
-- AUTO CLAN FARM v1.0 — ЯДРО
-- Только: Auto Hatch Final Egg + Clan Points Tracker
-- Остальное — через D1ablo параллельно
-- ==========================================

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

-- =====================
-- CONFIG
-- =====================
local CONFIG = {
    HATCH_DELAY = 0.08,        -- Delta-safe
    CHECK_DELAY = 0.5,         -- проверка новых петов
    ANTI_AFK = true,
    LOG_LIMIT = 30,

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
}

-- =====================
-- МОДУЛИ PS99
-- =====================
local Save, Library, HW, Types, HWInstance

pcall(function() Save = require(RS.Library.Client.Save) end)
pcall(function() Library = RS:WaitForChild("Library", 10) end)

if Library then
    pcall(function() HW = require(Library.Client.HatchWarCmds) end)
    pcall(function() Types = require(Library.Types.HatchWar) end)
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
    Name = "AUTO CLAN FARM v1.0 (Core)",
    LoadingTitle = "Загрузка ядра...",
    LoadingSubtitle = "Auto Hatch + Clan Points",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "AutoClanFarm",
        FileName = "Core",
    },
    Keybind = "K",
})

local MainTab = Window:CreateTab("Главная", 4483362458)
local StatsTab = Window:CreateTab("Статистика", 4483362458)
local LogTab = Window:CreateTab("Логи", 4483362458)

-- =====================
-- СТАТИСТИКА UI
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
                "🥚 Хэтчей: %d\n"..
                "🎉 Редких: %d\n"..
                "🏆 Клан-поинтов: %d\n"..
                "⏱ Время: %d сек\n"..
                "📊 Хэтчей/мин: %.1f",
                State.Status,
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
-- СЧИТАЕМ ПИТОМЦЕВ
-- =====================
local function countPets()
    if not Save then return {} end
    local d = Save.Get()
    if not d or not d.Inventory or not d.Inventory.Pets then return {} end
    return d.Inventory.Pets
end

-- =====================
-- ТИР ПИТОМЦА
-- =====================
local function getPetTier(pet)
    local name = tostring(pet.id or pet.Name or pet.name or ""):lower()
    if name:find("gargantuan") then return "gargantuan" end
    if name:find("titanic") then return "titanic" end
    if name:find("huge") then return "huge" end
    return nil
end

-- =====================
-- НАЙТИ НОВЫХ РЕДКИХ
-- =====================
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
-- ФИНАЛЬНОЕ ЯЙЦО
-- =====================
local function getFinalEgg()
    -- Пробуем через Types.ZONES (последняя зона = финальное яйцо)
    if Types and Types.ZONES then
        local count = #Types.ZONES
        if count > 0 then
            local last = Types.ZONES[count]
            return last.Egg or last.Name or last.DisplayName or nil
        end
    end

    -- Fallback: ищем яйцо с ключевым словом
    if Save then
        local d = Save.Get()
        if d and d.Inventory then
            for cat, items in pairs(d.Inventory) do
                if type(items) == "table" then
                    for uid, item in pairs(items) do
                        local id = tostring(item.id or ""):lower()
                        if id:find("witch") or id:find("soul") or id:find("moth") or id:find("final") then
                            return item.id
                        end
                    end
                end
            end
        end
    end

    return nil
end

-- =====================
-- ПОЛУЧИТЬ ИНСТАНС HW
-- =====================
local function getHWInstance()
    if not HW then return nil end
    local ok, inst = pcall(function() return HW.Instance() end)
    if ok then return inst end
    return nil
end

-- =====================
-- ХЭТЧ ЯЙЦА
-- =====================
local function hatchEgg(eggId)
    local inst = getHWInstance()
    if not inst then return false, "нет HW инстанса" end

    -- Смотрим, есть ли InvokeCustom с Hatch
    if not Types or not Types.NET_PREFIX then
        return false, "нет NET_PREFIX"
    end

    local prefix = Types.NET_PREFIX.Hatch or Types.NET_PREFIX.Egg
    if not prefix then return false, "нет префикса хэтча" end

    local petsBefore = countPets()

    local ok, result = pcall(function()
        return inst:InvokeCustom(prefix, eggId, 1)
    end)

    if ok then
        State.Hatches = State.Hatches + 1
        findNewRarePet(petsBefore)
        return true, result
    end
    return false, tostring(result)
end

-- =====================
-- ЦИКЛ ФАРМА
-- =====================
local function farmLoop()
    if State.IsRunning then return end
    State.IsRunning = true
    State.Status = "Работает"

    log("Запуск ядра AUTO CLAN FARM")

    -- Проверяем модули
    if not Save then
        log("⚠️ Save не загружен")
        State.Status = "Нет Save"
        State.IsRunning = false
        return
    end

    if not HW then
        log("⚠️ HatchWarCmds не загружен — ты не в Hatch Wars?")
        State.Status = "Нет HW"
        State.IsRunning = false
        return
    end

    local finalEgg = getFinalEgg()
    if not finalEgg then
        log("⚠️ Финальное яйцо не найдено — используем все")
        State.Status = "Нет финального яйца"
    else
        log("Финальное яйцо: " .. tostring(finalEgg))
    end

    while State.IsRunning do
        local inst = getHWInstance()
        if not inst then
            State.Status = "Ждём HW инстанс"
            task.wait(1)
        else
            -- Хэтчим
            local ok, result = hatchEgg(finalEgg or "any")
            if not ok then
                log("Ошибка хэтча: " .. tostring(result))
                task.wait(1)
            else
                task.wait(CONFIG.HATCH_DELAY)
            end
        end

        -- Обновляем UI раз в 2 сек
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
    print("========== AUTO CLAN FARM DIAG ==========")
    print("Save:", Save and "OK" or "nil")
    print("Library:", Library and "OK" or "nil")
    print("HW:", HW and "OK" or "nil")
    print("Types:", Types and "OK" or "nil")

    if Types then
        print("NET_PREFIX keys:")
        for k, v in pairs(Types.NET_PREFIX or {}) do
            print("  " .. tostring(k) .. " = " .. tostring(v))
        end
        print("ZONES count:", #(Types.ZONES or {}))
    end

    local inst = getHWInstance()
    print("HW.Instance():", inst and "OK" or "nil")

    print("Финальное яйцо:", tostring(getFinalEgg()))
    print("========== END DIAG ==========")

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
-- UI: ГЛАВНАЯ
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
            Content = "Смотри консоль Delta (F9)",
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
    Content = "Запусти D1ablo-скрипт параллельно — он делает Auto Boss, Auto Progress, Auto Orbs. Это ядро делает только хэтч финального яйца и считает клан-поинты.",
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

log("AUTO CLAN FARM v1.0 (Core) загружен")
State.Status = "Готов"

Rayfield:Notify({
    Title = "AUTO CLAN FARM v1.0",
    Content = "Ядро загружено. Нажми Диагностику!",
    Duration = 8,
})
