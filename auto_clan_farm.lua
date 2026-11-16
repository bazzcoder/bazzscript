--[[
    BAZZ · Pumpkin Patch Tycoon — ZaLupa Style UI (Компактная версия)
--]]

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local LP      = Players.LocalPlayer
local G       = getgenv()

local Client  = RS:WaitForChild("Library").Client
local Network = RS:WaitForChild("Network")

local BtnCmds    = require(Client.PumpkinTycoonCmds.Buttons)
local Currency   = require(Client.CurrencyCmds)
local CustomEggs = require(Client.CustomEggsCmds)
local BtnTypes   = require(RS.Library.Types.PumpkinTycoon.Buttons)
local BtnUtil    = require(RS.Library.Util.PumpkinTycoonButtons)
local EggCmds    = require(Client.EggCmds)
local PumpUpg    = require(Client.PumpkinTycoonCmds.Upgrades)
local PT         = require(RS.Library.Types.PumpkinTycoon)
local MT         = require(RS.Library.Types.PumpkinTycoon.Merchant)

local DamageRemote = Network:WaitForChild("Breakables_PlayerDealDamage")
local HatchRemote  = Network:WaitForChild("CustomEggs_Hatch")
local VERB_BUY = MT.VERB_BUY or "FZ_Reserve"

local cfg = {
    breakables    = true,
    pumpkinsOnly  = false,
    autoBuy       = true,
    autoHatch     = true,
    autoMerchant  = true,
    autoProg      = false,
    autoUpgrades  = true,
    antiAfk       = true,
    autoMail      = true,
    fastPumpkins  = true,
    autoEnter     = true,
    noAnim        = true,
    zoneMode      = "best",
    eggChoice     = "auto",
    clickRadius   = 150,
    clickBurst    = 3,
    hitsPerSecond = 300,
    maxEggs       = 256,
    tpDist        = 26,
    tpCooldown    = 2,
    hatchDist     = 40,
    ultraOpti     = false,
}
G.Bazz = cfg

local function normalizeProgression()
    if not cfg.autoProg then return end
    cfg.breakables = true
    cfg.pumpkinsOnly = false
    cfg.zoneMode = "best"
    cfg.eggChoice = "auto"
    cfg.autoHatch = true
    cfg.autoBuy = true
    cfg.autoMerchant = true
    cfg.autoEnter = true
    cfg.fastPumpkins = true
    cfg.autoUpgrades = true
end

local purchaseMemory = G.BazzPurchases or { owned = {}, plot = nil }
G.BazzPurchases = purchaseMemory
if type(purchaseMemory.owned) ~= "table" then purchaseMemory.owned = {} end

local stats   = { broken = 0, hits = 0, hatches = 0, buys = 0, merchant = 0, pumpkinUpg = 0, mails = 0 }
local runtime = { zone = "-", plot = "?", target = "-", pumpkins = 0, egg = "-", mode = "-", eggCount = 0 }
local state = { zones = {}, zonesAt = 0, breakables = {}, breakablesAt = 0, targets = {}, targetsAt = 0, eggs = {}, eggsAt = 0 }

if G.__bazz_cleanup then pcall(G.__bazz_cleanup) end
G.__bazzgen = (G.__bazzgen or 0) + 1
local GEN = G.__bazzgen

local HttpService = game:GetService("HttpService")
local SAVE_FILE = "bazz_config.json"
local SAVE_KEYS = { "breakables", "pumpkinsOnly", "autoBuy", "autoHatch", "autoMerchant", "autoEnter", "noAnim", "zoneMode", "eggChoice", "maxEggs", "clickRadius", "clickBurst", "fastPumpkins", "autoProg", "autoUpgrades", "ultraOpti", "antiAfk", "autoMail" }
local function saveCfg()
    if not writefile then return end
    local data = {}
    for _, k in ipairs(SAVE_KEYS) do data[k] = cfg[k] end
    local ok, encoded = pcall(function() return HttpService:JSONEncode(data) end)
    if ok and type(encoded) == "string" then pcall(writefile, SAVE_FILE, encoded) end
end
local function loadCfg()
    if not (readfile and isfile) then return end
    local okExists, exists = pcall(isfile, SAVE_FILE)
    if not okExists or not exists then return end
    local okRead, text = pcall(readfile, SAVE_FILE)
    if not okRead or type(text) ~= "string" or text == "" then return end
    local okDec, data = pcall(function() return HttpService:JSONDecode(text) end)
    if not okDec or type(data) ~= "table" then return end
    for _, k in ipairs(SAVE_KEYS) do
        local v = data[k]
        if k == "zoneMode" then
            if type(v) == "number" or (type(v) == "string" and v == "best") then cfg[k] = v end
        elseif v ~= nil and type(v) == type(cfg[k]) then cfg[k] = v end
    end
end
loadCfg()
normalizeProgression()

-- ЛОГИКА (без изменений)
local function char() local c = LP.Character return c and c:FindFirstChild("HumanoidRootPart") end
local function distTo(pos) local hrp = char() if not hrp or not pos then return math.huge end return (hrp.Position - pos).Magnitude end
local lastTp, moveKey, moveTarget = 0, nil, nil
local function goTo(key, target, minDist)
    if not target then return false end
    local pos = typeof(target) == "CFrame" and target.Position or target
    local hrp = char() if not hrp then return false end
    if moveKey == key and moveTarget and (moveTarget - pos).Magnitude < 3 and (hrp.Position - pos).Magnitude <= minDist then return false end
    local now = os.clock() if now - lastTp < cfg.tpCooldown then return false end
    hrp.CFrame = typeof(target) == "CFrame" and target or CFrame.new(pos)
    lastTp, moveKey, moveTarget = now, key, pos return true
end
local function coinCount() local ok, v = pcall(Currency.Get, "PumpkinTycoonCoins") return ok and tonumber(v) or 0 end
local function shortNum(n)
    n = tonumber(n) or 0
    local units = { { 1e33, "Dc" }, { 1e30, "No" }, { 1e27, "Oc" }, { 1e24, "Sp" }, { 1e21, "Sx" }, { 1e18, "Qi" }, { 1e15, "Qa" }, { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
    for _, u in ipairs(units) do if n >= u[1] then return string.format("%.2f%s", n / u[1], u[2]) end end
    return tostring(math.floor(n))
end
local function baseId(id) return (tostring(id or ""):gsub("%s*%b()%s*$", "")) end
local function isPumpkinId(id) return baseId(id):lower():find("pumpkin", 1, true) ~= nil end

local ownPlotId
local ClientPlot = require(Client.PlotCmds.ClientPlot)
local function detectPlot()
    local ok, plot = pcall(ClientPlot.GetLocal)
    local id = ok and type(plot) == "table" and plot.Id and tostring(plot.Id) or nil
    if id ~= ownPlotId then
        ownPlotId = id state.zones, state.zonesAt = {}, 0 state.breakables, state.breakablesAt = {}, 0 state.targets, state.targetsAt = {}, 0 state.eggs, state.eggsAt = {}, 0
    end
    return ownPlotId
end
local function ownPlotModel() local id = detectPlot() local plots = workspace.__THINGS:FindFirstChild("Plots") return (id and plots) and plots:FindFirstChild(id) or nil end
local function inTycoon() return detectPlot() ~= nil end
local function buttonStates() local ok, plot = pcall(ClientPlot.GetLocal) local save = ok and plot and plot.SaveVariables return save and type(save.Buttons) == "table" and save.Buttons or {} end
local function tycoonPortals()
    local inst = workspace.__THINGS:FindFirstChild("Instances") local ty = inst and inst:FindFirstChild("PumpkinTycoon") local tel = ty and ty:FindFirstChild("Teleports") local out = {}
    if not tel then return out end
    for _, p in ipairs(tel:GetChildren()) do if p:IsA("BasePart") and p.Name == "Enter" then out[#out + 1] = p end end
    return out
end
local lastEnterTry = 0
local function tryEnterTycoon()
    if inTycoon() then return false end if os.clock() - lastEnterTry < 4 then return false end
    local hrp = char() if not hrp then return false end
    local best, bestD
    for _, p in ipairs(tycoonPortals()) do local d = (p.Position - hrp.Position).Magnitude if not bestD or d < bestD then bestD, best = d, p end end
    if not best then return false end
    lastEnterTry = os.clock() hrp.CFrame = CFrame.new(best.Position) return true
end
local function zoneTable()
    local now = os.clock() if now - state.zonesAt < 2 then return state.zones end
    local out = {} local plot = ownPlotModel() local secs = plot and plot:FindFirstChild("Sections") local buttons = buttonStates()
    if secs then for _, s in ipairs(secs:GetChildren()) do
        local idx = tonumber(s.Name:match("^(%d+)")) local name = s.Name:gsub("^%s*%d+%s*|%s*", ""):gsub("%s+", "")
        if idx and buttons[name .. "_Zone"] == true then out[idx] = { name = name, dir = s, needle = name .. "_Zone_" } end
    end end
    state.zones, state.zonesAt = out, now return out
end
local WEIGHT = { ["Vault"] = 1200, ["Safe"] = 1000, ["Present"] = 800, ["Crate"] = 600, ["Large Coins"] = 400, ["Medium Coins"] = 200, ["Small Coins"] = 10 }
local function itemWeight(base)
    for key, val in pairs(WEIGHT) do if base:find(key, 1, true) then return val end end
    if base:lower():find("pumpkin", 1, true) then return 9999 end return 50
end
local function breakableFolder() local things = workspace:FindFirstChild("__THINGS") return things and things:FindFirstChild("Breakables") end
local breakEntries, breakList, breakDirty, breakPlot, breakFolderRef, breakConns = {}, {}, true, nil, nil, {}
local function breakEntryFor(m, id)
    if not (id and typeof(m) == "Instance" and m:IsA("Model")) then return nil end
    if m:GetAttribute("ParentID") ~= "PumpkinTycoon" then return nil end
    local suffix = "_" .. id local area = tostring(m:GetAttribute("AreaID") or "") local base = baseId(m:GetAttribute("BreakableID"))
    local pumpkin = isPumpkinId(base) local ownerMatch = pumpkin and tostring(m:GetAttribute("OwnerUsername") or "") == LP.Name
    local mine = pumpkin and ownerMatch or (area:sub(-#suffix) == suffix) local uid = mine and m:GetAttribute("BreakableUID")
    if not uid then return nil end
    local ok, pos = pcall(function() return m:GetPivot().Position end) if not ok then return nil end
    return { model = m, uid = tostring(uid), base = base, area = area, pumpkin = pumpkin, pos = pos, weight = itemWeight(base) }
end
local function breakScan()
    breakEntries = {} local folder = breakableFolder() local id = detectPlot() breakPlot = id
    if folder and id then for _, m in ipairs(folder:GetChildren()) do breakEntries[m] = breakEntryFor(m, id) or false end end
    breakDirty = true
end
local function breakwatch()
    local folder = breakableFolder()
    if folder ~= breakFolderRef then
        for _, c in ipairs(breakConns) do pcall(function() c:Disconnect() end) end
        breakConns = {} breakFolderRef = folder
        if folder then
            breakConns[1] = folder.ChildAdded:Connect(function(m) breakEntries[m] = breakEntryFor(m, breakPlot) or false breakDirty = true end)
            breakConns[2] = folder.ChildRemoved:Connect(function(m) if breakEntries[m] then breakEntries[m] = nil breakDirty = true end end)
        end
        breakScan()
    end
end
G.__bazz_cleanup = function() for _, c in ipairs(breakConns) do pcall(function() c:Disconnect() end) end breakConns = {} end
local function ownBreakables()
    breakwatch() local id = detectPlot() if id ~= breakPlot then breakPlot = id breakScan() end
    if breakDirty then
        breakList = {} for _, entry in pairs(breakEntries) do if entry then breakList[#breakList + 1] = entry end end breakDirty = false
    end
    state.breakables = breakList return breakList
end
local function pickZone(zones, list)
    local mode = cfg.autoProg and "best" or cfg.zoneMode
    if mode ~= "best" then local idx = tonumber(mode) if idx and zones[idx] then return idx end end
    local highest for idx in pairs(zones) do if not highest or idx > highest then highest = idx end end return highest
end
local function zoneSpot(zones, list, idx)
    local zone = idx and zones[idx] if not zone then return nil end
    local sum, n = Vector3.zero, 0
    for _, b in ipairs(list) do if not b.pumpkin and b.area:find(zone.needle, 1, true) then sum, n = sum + b.pos, n + 1 end end
    if n > 0 then return sum / n + Vector3.new(0, 6, 0) end
    local bz = zone.dir:FindFirstChild("BREAK_ZONES") local part = bz and bz:FindFirstChildOfClass("BasePart")
    return part and part.Position + Vector3.new(0, 6, 0) or nil
end
local function collectTargets()
    local now = os.clock()
    if cfg.zoneMode ~= cfg.zoneMode then state.targetsAt = 0 end
    if now - state.targetsAt < 0.1 then return state.targets end
    local zones = zoneTable() local list = ownBreakables() local idx = pickZone(zones, list) local zone = idx and zones[idx]
    runtime.zone = zone and string.format("%d %s", idx, zone.name) or "-"
    local hrp = char() local origin = hrp and hrp.Position or Vector3.zero
    local radius = math.clamp(tonumber(cfg.clickRadius) or 150, 10, 400)
    local targets, pumpkins = {}, 0
    for _, b in ipairs(list) do
        if b.pumpkin then pumpkins = pumpkins + 1 end
        if (b.pos - origin).Magnitude <= radius and (b.pumpkin or cfg.autoProg or not cfg.pumpkinsOnly) then targets[#targets + 1] = b end
    end
    runtime.pumpkins = pumpkins runtime.plot = tostring(detectPlot() or "?")
    table.sort(targets, function(a, b)
        if a.pumpkin ~= b.pumpkin then return a.pumpkin end
        if a.weight ~= b.weight then return a.weight > b.weight end
        return (a.pos - origin).Magnitude < (b.pos - origin).Magnitude
    end)
    state.targets, state.targetsAt = targets, now return targets
end
local seenUids = {}
local function clickDetectorOf(model)
    local hitbox = model:FindFirstChild("Hitbox") local cd = hitbox and hitbox:FindFirstChildOfClass("ClickDetector")
    if cd then return cd end
    for _, d in ipairs(model:GetDescendants()) do if d:IsA("ClickDetector") then return d end end return nil
end
local burstTokens, burstStamp = 0, os.clock()
local function tapRound(targets)
    local burst = math.clamp(math.floor(tonumber(cfg.clickBurst) or 3), 1, 10)
    local rate = math.clamp(tonumber(cfg.hitsPerSecond) or 300, 30, 800)
    for _, t in ipairs(targets) do
        if not cfg.breakables then return end
        if not (t.pumpkin and cfg.fastPumpkins) then
            local now = os.clock() burstTokens = math.min(rate, burstTokens + (now - burstStamp) * rate) burstStamp = now
            if burstTokens < burst then task.wait((burst - burstTokens) / rate) burstTokens = 0 burstStamp = os.clock() else burstTokens = burstTokens - burst end
            if t.model.Parent then
                local cd
                if t.pumpkin and G.fireclickdetector then cd = t.cd or clickDetectorOf(t.model) t.cd = cd end
                for _ = 1, burst do if t.pumpkin then if cd then pcall(G.fireclickdetector, cd) end else DamageRemote:FireServer(t.uid) end end
                if not t.pumpkin or cd then stats.hits = stats.hits + burst runtime.target = t.uid seenUids[t.uid] = true end
            end
        end
    end
end
local lastPkTp = 0
task.spawn(function()
    while G.__bazzgen == GEN do
        if cfg.breakables and cfg.fastPumpkins then
            local list = ownBreakables() local hrp = char() local best, bestD
            if hrp then for _, b in ipairs(list) do if b.pumpkin then local d = (b.pos - hrp.Position).Magnitude if not bestD or d < bestD then bestD, best = d, b end end end end
            if best and hrp then
                if bestD > 14 and os.clock() - lastPkTp > 0.4 then lastPkTp = os.clock() hrp.CFrame = CFrame.lookAt(best.pos + Vector3.new(0, 4, 6), best.pos) end
                local cd = best.cd or clickDetectorOf(best.model) best.cd = cd
                if cd and G.fireclickdetector then
                    for _ = 1, 30 do if not best.model.Parent then break end pcall(G.fireclickdetector, cd) stats.hits = stats.hits + 1 runtime.target = best.uid seenUids[best.uid] = true task.wait() end
                else task.wait(0.05) end
            else task.wait(0.1) end
        else task.wait(0.2) end
    end
end)
local function pruneSeen(alive)
    for uid in pairs(seenUids) do if not alive[uid] then stats.broken = stats.broken + 1 seenUids[uid] = nil end end
    local count = 0 for _ in pairs(seenUids) do count = count + 1 end if count > 5000 then seenUids = {} end
end
task.spawn(function()
    while true do
        if G.__bazzgen ~= GEN then break end
        normalizeProgression()
        if cfg.breakables or cfg.autoProg then
            local targets = collectTargets() local alive = {} for _, t in ipairs(targets) do alive[t.uid] = true end pruneSeen(alive)
            if #targets == 0 then task.wait(0.1) else tapRound(targets) task.wait() end
        else task.wait(0.3) end
        task.wait(0.01)
    end
end)

local buttonsById = {}
for _, b in ipairs(BtnTypes.BUTTONS) do if b.Id then buttonsById[b.Id] = b end end
local function eggZone(egg) local def = buttonsById[egg.id:gsub("%s+", ""):gsub("Egg$", "") .. "_Egg"] return def and tonumber(def.Zone) or 99 end
local lastEggList = {}
local function allEggs()
    local now = os.clock() if now - state.eggsAt < 1 and #state.eggs > 0 then return state.eggs end
    local out = {} local buttons = buttonStates() local okAll, all = pcall(CustomEggs.All)
    if okAll and type(all) == "table" then
        for uid, egg in pairs(all) do
            if type(egg) == "table" then
                local id = tostring(egg._id or "") local pos = egg._position local buttonId = id:gsub("%s+", ""):gsub("Egg$", "") .. "_Egg"
                if id ~= "" and pos and buttons[buttonId] == true and egg._owner ~= nil and tostring(egg._owner) == LP.Name then
                    out[#out + 1] = { uid = tostring(uid), model = egg._model, id = id, pos = pos, price = tonumber(egg._dir and egg._dir.overrideCost) or 0 }
                end
            end
        end
        table.sort(out, function(a, b) if a.price ~= b.price then return a.price > b.price end return a.id < b.id end)
    end
    if #out > 0 then lastEggList = out state.eggs, state.eggsAt = out, now return out end
    state.eggsAt = now return lastEggList
end
local REF_PLOT = CFrame.new(9715, 2007.5, 8000, 0, 0, 1, 0, 1, 0, -1, 0, 0)
local EGG_SPOTS = {
    ["Cocoa Cabin Egg"] = CFrame.new(9833.957, 2011.975, 7818.081, 0.990, 0, 0.138, 0, 1, 0, -0.138, 0, 0.990),
    ["Apple Orchard Egg"] = CFrame.new(9876.271, 2012.748, 8141.088, 0.920, 0, -0.393, 0, 1, 0, 0.393, 0, 0.920),
    ["Hayride Hill Egg"] = CFrame.new(9661.750, 2008.200, 8202.911, 0.322, 0, 0.947, 0, 1, 0, -0.947, 0, 0.322),
    ["Cider Mill Egg"] = CFrame.new(9412.692, 2013.834, 8070.824, -0.218, 0, 0.976, 0, 1, 0, -0.976, 0, -0.218),
    ["Golden Grove Egg"] = CFrame.new(9654.024, 2008.477, 7798.854, -0.495, 0, 0.869, 0, 1, 0, -0.869, 0, -0.495),
}
local EGG_OFFSETS = {}
for id, cf in pairs(EGG_SPOTS) do EGG_OFFSETS[id] = REF_PLOT:ToObjectSpace(cf) end
local function eggStandPos(egg)
    local offset = EGG_OFFSETS[egg.id] local ok, plot = pcall(ClientPlot.GetLocal)
    if offset and ok and plot and plot.CFrame then return plot.CFrame:ToWorldSpace(offset) end
    return CFrame.lookAt(egg.pos - Vector3.new(0, 3, 0), egg.pos)
end
local progBatches = {}
local function pickEgg()
    local eggs = allEggs()
    if cfg.eggChoice ~= "auto" then for _, egg in ipairs(eggs) do if egg.id == cfg.eggChoice then return egg end end end
    if cfg.autoProg then for _, egg in ipairs(eggs) do local zone = eggZone(egg) if zone >= 5 or (progBatches[egg.uid] or 0) < 3 then return egg end end return nil end
    if eggs[1] then return eggs[1] end return nil
end
local upgradeReserve = function() return 0 end
local function gameMaxHatch()
    local prev = 8 pcall(function() prev = G.getthreadidentity() or 8 end) pcall(G.setthreadidentity, 2)
    local ok, value = pcall(EggCmds.GetMaxHatch) pcall(G.setthreadidentity, prev)
    return ok and tonumber(value) or nil
end
task.spawn(function()
    while true do
        if G.__bazzgen ~= GEN then break end
        normalizeProgression()
        if cfg.autoHatch then
            local deadline = os.clock() + 10 local t
            repeat state.eggsAt = 0 t = pickEgg() if not t then task.wait(0.5) end until t or os.clock() >= deadline or G.__bazzgen ~= GEN
            if t and distTo(t.pos) <= cfg.hatchDist then
                local opened, lastWant = 0, 0 local zone = eggZone(t)
                for _ = 1, 8 do
                    if cfg.autoProg and zone < 5 and (progBatches[t.uid] or 0) >= 3 then runtime.egg = "лимит " .. t.id break end
                    local coins = math.max(0, coinCount() - (cfg.autoBuy and upgradeReserve() or 0))
                    local want = t.price and t.price > 0 and math.floor(coins / t.price) or cfg.maxEggs
                    want = math.clamp(want, 0, cfg.maxEggs) local cap = gameMaxHatch()
                    if cap == 0 then runtime.egg = "полно " .. t.id break elseif cap and cap > 0 then want = math.min(want, cap) end
                    lastWant = want if want < 1 then runtime.egg = "нет монет " .. t.id break end
                    local got = 0 local n = want
                    while n >= 1 do local ok, res = pcall(function() return HatchRemote:InvokeServer(t.uid, n) end) if ok and res == true then got = n break end n = math.floor(n / 2) end
                    if got < 1 then runtime.egg = "полно/блок " .. t.id break end
                    opened = opened + got progBatches[t.uid] = (progBatches[t.uid] or 0) + 1 stats.hatches = stats.hatches + got runtime.eggCount = opened runtime.egg = string.format("%s x%d", t.id, opened) task.wait(0.15)
                end
                if opened < 1 and lastWant > 0 and not tostring(runtime.egg):find("полно", 1, true) then runtime.egg = "не открылось " .. t.id end
            elseif t then runtime.egg = "далеко " .. t.id else runtime.egg = "нет яйца: " .. tostring(cfg.eggChoice) end
        end
        task.wait(0.7)
    end
end)

local function firstPumpkin(list)
    local hrp = char() local origin = hrp and hrp.Position or Vector3.zero local best, bestD
    for _, b in ipairs(list) do if b.pumpkin then local d = (b.pos - origin).Magnitude if not bestD or d < bestD then bestD, best = d, b end end end
    return best, bestD
end
local pkUid, pkSince
task.spawn(function()
    while true do
        if G.__bazzgen ~= GEN then break end
        normalizeProgression()
        if not inTycoon() then runtime.mode = "вход" task.wait(0.5) else
            local zones = zoneTable() local list = ownBreakables() local pk = firstPumpkin(list) local egg = cfg.autoHatch and pickEgg() or nil
            local now = os.clock()
            if pk then if pkUid ~= pk.uid then pkUid, pkSince = pk.uid, now end else pkUid, pkSince = nil, nil end
            local pkStable = pk and pkSince and (now - pkSince) >= 1.2
            local kind, pos, moveId
            if cfg.breakables and pkStable then kind, pos = "pumpkin", pk.pos + Vector3.new(0, 4, 6) moveId = pk.uid
            elseif egg then kind, pos = "egg", eggStandPos(egg) moveId = egg.uid
            elseif cfg.breakables or cfg.autoProg then local idx = pickZone(zones, list) pos = zoneSpot(zones, list, idx) kind, moveId = "zone", idx end
            runtime.mode = tostring(kind or "-")
            if pos and goTo(kind .. ":" .. tostring(moveId), pos, kind == "egg" and 12 or cfg.tpDist) then task.wait(0.25) end
            task.wait(0.35)
        end
    end
end)
task.spawn(function()
    task.wait(3)
    while true do if G.__bazzgen ~= GEN then break end if cfg.autoEnter and tryEnterTycoon() then runtime.mode = "вход" end task.wait(1) end
end)

local queuedId, workerReady = nil, false
local failCache, lockedCache, itemCooldown = {}, {}, {}
local ownedCache = purchaseMemory.owned
task.spawn(function()
    local okid = pcall(G.setthreadidentity, 2) if not okid then return end
    local okIsland, island = pcall(require, Client.PumpkinTycoonCmds.Island)
    local okMerch, merchant = pcall(require, Client.PumpkinTycoonCmds.Merchant)
    workerReady = okIsland local lastMerchant, lastStock, lastCommit, coinHold = 0, 0, 0, 0
    while true do
        if G.__bazzgen ~= GEN then break end
        local plot = detectPlot()
        if plot and purchaseMemory.plot ~= plot then table.clear(ownedCache) purchaseMemory.plot = plot end
        local id = (os.clock() - lastCommit >= 0.3 and os.clock() >= coinHold) and queuedId or nil
        if id then queuedId = nil end
        if id then
            lastCommit = os.clock() local okObj, obj = pcall(island.AwaitLocal, 5)
            if okObj and type(obj) == "table" then
                local ok, res, reason = pcall(function() return obj:Invoke("NZ_Commit", id) end)
                local r = tostring(reason or "")
                if ok and res == true then stats.buys = stats.buys + 1 ownedCache[id] = true
                elseif r:find("Already purchased", 1, true) then ownedCache[id] = true
                elseif r:find("Requirement", 1, true) then lockedCache[id] = os.clock() + 180
                elseif r:find("coins", 1, true) then failCache[id] = os.clock() + 5 coinHold = os.clock() + 1.5
                else failCache[id] = os.clock() + 15 end
            end
        end
        if okMerch and cfg.autoMerchant then
            if os.clock() - lastMerchant > 8 then lastMerchant = os.clock() local okOn, on = pcall(merchant.AutoOn) if not (okOn and on) then pcall(merchant.SetAuto, true) end end
            if okIsland and os.clock() - lastStock > 0.8 then
                lastStock = os.clock() local okObj, obj = pcall(island.AwaitLocal, 5)
                if okObj and type(obj) == "table" then
                    local okS, stock = pcall(function() return island.Get(nil, PT.VAR.Stock) end)
                    if okS and type(stock) == "table" then
                        local free = true pcall(function() free = #merchant.CleanStock(stock) < merchant.Slots() end)
                        if free then
                            local items = {}
                            for itemId, count in pairs(stock) do if type(count) == "number" and count > 0 and not (itemCooldown[itemId] and itemCooldown[itemId] > os.clock()) then items[#items + 1] = itemId end end
                            table.sort(items, function(a, b) return tostring(a) < tostring(b) end)
                            for _, itemId in ipairs(items) do
                                local okb, res = pcall(function() return obj:Invoke(VERB_BUY, itemId) end)
                                if okb and res then stats.merchant = stats.merchant + 1 itemCooldown[itemId] = os.clock() + 1 break end
                                itemCooldown[itemId] = os.clock() + 10
                            end
                        end
                    end
                end
            end
        end
        task.wait(0.15)
    end
end)

local function killAnimations()
    local anim = Network:FindFirstChild("Eggs_PlayOpenAnimation")
    if anim and G.getconnections then local ok, cons = pcall(G.getconnections, anim.OnClientEvent) if ok then for _, c in ipairs(cons) do pcall(function() c:Disable() end) end end end
    pcall(G.setfflag, "EggOpening", "false")
    local pg = LP:FindFirstChild("PlayerGui")
    for _, name in ipairs({ "EggOpenInfo", "EggOpenAnimation" }) do local g = pg and pg:FindFirstChild(name) if g then pcall(function() g.Enabled = false end) end end
end

local RunService = game:GetService("RunService")
local purgeAt = 0
local function applyAggressiveOpti()
    if not cfg.ultraOpti then return end
    pcall(function()
        settings().Rendering.QualityLevel = 1
        settings().Rendering.SavedQualityLevel = 1
        settings().Rendering.MeshPartDetail = 1
        settings().Rendering.TextureQuality = 1
        settings().Rendering.AnimationQuality = 1
        workspace.GlobalShadows = false
    end)
    pcall(function()
        local terr = workspace:FindFirstChildOfClass("Terrain")
        if terr then terr.WaterWaveSize = 0 terr.WaterWaveSpeed = 0 terr.WaterReflectance = 0 terr.WaterTransparency = 1 terr.Decoration = false end
    end)
end
local function deepPurge()
    if os.clock() - purgeAt < 10 then return end
    purgeAt = os.clock() local ch = LP.Character
    local function strip(inst)
        if ch and inst:IsDescendantOf(ch) then return end
        if inst:IsA("Decal") or inst:IsA("Texture") then pcall(function() inst.Transparency = 1 end)
        elseif inst:IsA("MeshPart") then pcall(function() inst.TextureID = "" end)
        elseif inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles") or inst:IsA("Highlight") then pcall(function() inst.Enabled = false end)
        elseif inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight") then pcall(function() inst.Enabled = false end)
        elseif inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") then pcall(function() inst.Enabled = false end)
        elseif inst:IsA("Sound") then pcall(function() inst.Volume = 0; inst:Stop() end) end
    end
    local descs = workspace:GetDescendants()
    for i = 1, #descs do pcall(strip, descs[i]) if i % 500 == 0 then task.wait() end end
end
local function applyUltra() applyAggressiveOpti() if cfg.ultraOpti then task.spawn(deepPurge) end end

local function ownsButton(id, purchased) return purchased[id] == true or ownedCache[id] == true end
local function bestPurchase()
    local bestId, bestPrice local mult, now = 1, os.clock() local purchased = buttonStates() local coins = coinCount()
    pcall(function() mult = BtnCmds.PriceMult() or 1 end)
    for _, b in ipairs(BtnTypes.BUTTONS) do
        local id = b.Id
        if id and not ownsButton(id, purchased) and not (lockedCache[id] and lockedCache[id] > now) and not (failCache[id] and failCache[id] > now) then
            local ready = true
            if type(b.Required) == "table" then for _, req in pairs(b.Required) do if type(req) == "string" and not ownsButton(req, purchased) then ready = false break end end end
            if ready then
                local okp, price = pcall(BtnUtil.Price, b, mult) price = okp and tonumber(price) or 0
                if price <= coins and (not bestPrice or price < bestPrice) then bestPrice, bestId = price, id end
            end
        end
    end
    return bestId, bestPrice
end
upgradeReserve = function() local _, price = bestPurchase() if not price or price <= 0 then return 0 end return math.floor(price * 0.5) end
task.spawn(function() while G.__bazzgen == GEN do if not cfg.autoBuy then queuedId = nil elseif workerReady and not queuedId then queuedId = bestPurchase() end task.wait(0.5) end end)

local PUMP_PRIORITY = { "RespawnSpeed", "StockSlots", "ChaseOdds", "MerchantLuck" }
local updCooldown, updBusy = {}, false
task.spawn(function()
    pcall(G.setthreadidentity, 2) local http = game:GetService("HttpService")
    while G.__bazzgen == GEN do
        if cfg.autoUpgrades and not updBusy then
            local ok, st = pcall(PumpUpg.TestState)
            if ok and type(st) == "table" and type(st.json) == "string" then
                local okJ, data = pcall(function() return http:JSONDecode(st.json) end)
                if okJ and type(data) == "table" and type(data.rows) == "table" then
                    local tokens = tonumber(data.tokens) or 0
                    local function info(id)
                        local row = data.rows[id] if type(row) ~= "table" then return nil end
                        local max = 0 local _, m = tostring(row.title or ""):match("(%d+)/(%d+)") max = tonumber(m) or 0
                        return { id = id, tier = tonumber(row.tier) or 0, price = tonumber(row.price) or 0, capped = row.capped == true, max = max }
                    end
                    local function pick(list)
                        local best, bestTier
                        for _, id in ipairs(list) do
                            local row = info(id)
                            if row and not row.capped and row.price > 0 and row.price <= tokens and not (updCooldown[id] and updCooldown[id] > os.clock()) then if not bestTier or row.tier < bestTier then best, bestTier = row, row.tier end end
                        end
                        return best
                    end
                    local target = pick(PUMP_PRIORITY)
                    if not target then
                        local priorityDone = true for _, id in ipairs(PUMP_PRIORITY) do local row = info(id) if row and not row.capped then priorityDone = false break end end
                        if priorityDone then
                            local others = {} for id in pairs(data.rows) do if not table.find(PUMP_PRIORITY, id) then others[#others + 1] = id end end table.sort(others) target = pick(others)
                        end
                    end
                    if target then
                        updBusy = true local okBuy = pcall(PumpUpg.TestPress, target.id)
                        if okBuy then runtime.pumpkinUpg = string.format("%s %d/%d", target.id, target.tier + 1, target.max) stats.pumpkinUpg = (stats.pumpkinUpg or 0) + 1
                        else updCooldown[target.id] = os.clock() + 3 end
                        updBusy = false
                    end
                end
            end
        end
        task.wait(0.65)
    end
end)

task.spawn(function()
    local vim = game:GetService("VirtualInputManager")
    while G.__bazzgen == GEN do if cfg.antiAfk then pcall(function() vim:SendKeyEvent(true, Enum.KeyCode.Space, false, game) task.wait(0.12) vim:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end) end task.wait(55) end
end)
task.spawn(function()
    local net = RS:FindFirstChild("Network") local req = net and net:FindFirstChild("Mailbox: Request") local claimAll = net and net:FindFirstChild("Mailbox: Claim All")
    while G.__bazzgen == GEN do if cfg.autoMail and claimAll then pcall(function() if req then req:InvokeServer() end end) local ok, claimed = pcall(function() return claimAll:InvokeServer() end) if ok and claimed then stats.mails = stats.mails + 1 end end task.wait(45) end
end)

-- ============================================================
-- GUI (Компактная версия)
-- ============================================================
local parent = LP:WaitForChild("PlayerGui")
local old = parent:FindFirstChild("BazzHubUI")
if old then old:Destroy() end

local UserInputService = game:GetService("UserInputService")
local COL_BG = Color3.fromRGB(25, 25, 28)
local COL_SIDE = Color3.fromRGB(18, 18, 20)
local COL_ACCENT = Color3.fromRGB(255, 138, 42)
local COL_TEXT = Color3.fromRGB(240, 240, 240)
local COL_MUTED = Color3.fromRGB(150, 150, 160)

local sgui = Instance.new("ScreenGui")
sgui.Name = "BazzHubUI" sgui.ResetOnSpawn = false sgui.IgnoreGuiInset = true sgui.DisplayOrder = 1000000 sgui.Parent = parent

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.fromOffset(46, 46) toggleBtn.Position = UDim2.new(0, 20, 0.5, -23)
toggleBtn.BackgroundColor3 = COL_ACCENT toggleBtn.Text = "B" toggleBtn.TextColor3 = Color3.new(0, 0, 0)
toggleBtn.Font = Enum.Font.GothamBlack toggleBtn.TextSize = 24 toggleBtn.Parent = sgui
local tc = Instance.new("UICorner") tc.CornerRadius = UDim.new(1, 0) tc.Parent = toggleBtn

-- Уменьшенный размер окна
local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(520, 350) main.Position = UDim2.fromScale(0.5, 0.5) main.AnchorPoint = Vector2.new(0.5, 0.5)
main.BackgroundColor3 = COL_BG main.BorderSizePixel = 0 main.Visible = false main.Parent = sgui
local mc = Instance.new("UICorner") mc.CornerRadius = UDim.new(0, 8) mc.Parent = main

local topBar = Instance.new("Frame")
topBar.Size = UDim2.new(1, 0, 0, 35) topBar.BackgroundColor3 = COL_SIDE topBar.Parent = main
local tc2 = Instance.new("UICorner") tc2.CornerRadius = UDim.new(0, 8) tc2.Parent = topBar

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -100, 1, 0) title.Position = UDim2.fromOffset(15, 0) title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold title.Text = "Bazz Hub | PS99" title.TextColor3 = COL_ACCENT title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left title.Parent = topBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(25, 25) closeBtn.Position = UDim2.new(1, -35, 0, 5) closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeBtn.Text = "X" closeBtn.TextColor3 = Color3.new(1, 1, 1) closeBtn.Font = Enum.Font.GothamBold closeBtn.TextSize = 12 closeBtn.Parent = topBar
local cbc = Instance.new("UICorner") cbc.CornerRadius = UDim.new(1, 0) cbc.Parent = closeBtn

local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 130, 1, -35) sidebar.Position = UDim2.fromOffset(0, 35) sidebar.BackgroundColor3 = COL_SIDE sidebar.Parent = main

local tabContainer = Instance.new("Frame")
tabContainer.Size = UDim2.new(1, 0, 1, 0) tabContainer.BackgroundTransparency = 1 tabContainer.Parent = sidebar
local tl = Instance.new("UIListLayout") tl.Padding = UDim.new(0, 2) tl.HorizontalAlignment = Enum.HorizontalAlignment.Center tl.Parent = tabContainer

local content = Instance.new("Frame")
content.Size = UDim2.new(1, -130, 1, -35) content.Position = UDim2.fromOffset(130, 35) content.BackgroundTransparency = 1 content.Parent = main

local tabs = {}
local function switchTab(name)
    for tName, tFrame in pairs(tabs) do tFrame.Visible = (tName == name) end
end

local function createTab(name)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 30) btn.BackgroundColor3 = COL_SIDE btn.Text = "  " .. name
    btn.TextColor3 = COL_TEXT btn.Font = Enum.Font.Gotham btn.TextSize = 13 btn.TextXAlignment = Enum.TextXAlignment.Left btn.Parent = tabContainer
    btn.MouseEnter:Connect(function() btn.BackgroundColor3 = Color3.fromRGB(30,30,35) end)
    btn.MouseLeave:Connect(function() btn.BackgroundColor3 = COL_SIDE end)
    
    local frame = Instance.new("ScrollingFrame")
    frame.Size = UDim2.fromScale(1, 1) frame.BackgroundTransparency = 1 frame.BorderSizePixel = 0
    frame.ScrollBarThickness = 2 frame.ScrollBarImageColor3 = COL_ACCENT
    frame.CanvasSize = UDim2.new(0, 0, 0, 0) frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    frame.Visible = false frame.Parent = content

    local padding = Instance.new("UIPadding") padding.PaddingTop = UDim.new(0, 8) padding.PaddingLeft = UDim.new(0, 8) padding.PaddingRight = UDim.new(0, 8) padding.Parent = frame
    local layout = Instance.new("UIListLayout") layout.Padding = UDim.new(0, 6) layout.SortOrder = Enum.SortOrder.LayoutOrder layout.Parent = frame

    btn.MouseButton1Click:Connect(function() switchTab(name) end)
    tabs[name] = frame
    return frame
end

local function createPanel(parent, order, height)
    local p = Instance.new("Frame")
    p.Size = UDim2.new(1, 0, 0, height or 40) p.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
    p.BorderSizePixel = 0 p.LayoutOrder = order p.Parent = parent
    local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 6) c.Parent = p
    return p
end

local function createToggle(parent, order, label, key, callback)
    local p = createPanel(parent, order, 40)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -60, 1, 0) lbl.Position = UDim2.fromOffset(12, 0) lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham lbl.Text = label lbl.TextColor3 = COL_TEXT lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left lbl.Parent = p

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(36, 18) btn.Position = UDim2.new(1, -46, 0.5, -9)
    btn.BackgroundColor3 = cfg[key] and COL_ACCENT or Color3.fromRGB(60, 60, 70) btn.Text = "" btn.Parent = p
    local bc = Instance.new("UICorner") bc.CornerRadius = UDim.new(1, 0) bc.Parent = btn

    local circle = Instance.new("Frame")
    circle.Size = UDim2.fromOffset(14, 14) circle.Position = cfg[key] and UDim2.fromOffset(20, 2) or UDim2.fromOffset(2, 2)
    circle.BackgroundColor3 = Color3.new(1, 1, 1) circle.Parent = btn
    local cc = Instance.new("UICorner") cc.CornerRadius = UDim.new(1, 0) cc.Parent = circle

    btn.MouseButton1Click:Connect(function()
        cfg[key] = not cfg[key]
        btn.BackgroundColor3 = cfg[key] and COL_ACCENT or Color3.fromRGB(60, 60, 70)
        circle.Position = cfg[key] and UDim2.fromOffset(20, 2) or UDim2.fromOffset(2, 2)
        if callback then callback(cfg[key]) end
        saveCfg()
    end)
end

local function createDropdown(parent, order, label, items, key, callback)
    local p = createPanel(parent, order, 40)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.5, 0, 1, 0) lbl.Position = UDim2.fromOffset(12, 0) lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham lbl.Text = label lbl.TextColor3 = COL_TEXT lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left lbl.Parent = p

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(160, 26) btn.Position = UDim2.new(1, -170, 0.5, -13)
    btn.BackgroundColor3 = Color3.fromRGB(50, 50, 60) btn.Text = "  " .. tostring(cfg[key]) .. " ▼"
    btn.TextColor3 = COL_TEXT btn.Font = Enum.Font.Gotham btn.TextSize = 12 btn.TextXAlignment = Enum.TextXAlignment.Left btn.Parent = p
    local bc = Instance.new("UICorner") bc.CornerRadius = UDim.new(0, 4) bc.Parent = btn

    local dropFrame = Instance.new("ScrollingFrame")
    dropFrame.Size = UDim2.fromOffset(160, math.min(#items * 25, 120)) 
    dropFrame.Position = UDim2.new(1, -170, 0, 30) -- Чуть ниже кнопки
    dropFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
    dropFrame.BorderSizePixel = 0 dropFrame.Visible = false dropFrame.ZIndex = 10 dropFrame.Parent = p
    local dfc = Instance.new("UICorner") dfc.CornerRadius = UDim.new(0, 4) dfc.Parent = dropFrame
    local dfl = Instance.new("UIListLayout") dfl.Parent = dropFrame

    for i, item in ipairs(items) do
        local opt = Instance.new("TextButton")
        opt.Size = UDim2.new(1, 0, 0, 25) opt.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
        opt.Text = "  " .. tostring(item) opt.TextColor3 = COL_TEXT opt.Font = Enum.Font.Gotham opt.TextSize = 12 opt.TextXAlignment = Enum.TextXAlignment.Left opt.LayoutOrder = i opt.Parent = dropFrame
        opt.MouseEnter:Connect(function() opt.BackgroundColor3 = COL_ACCENT opt.TextColor3 = Color3.new(0,0,0) end)
        opt.MouseLeave:Connect(function() opt.BackgroundColor3 = Color3.fromRGB(40, 40, 45) opt.TextColor3 = COL_TEXT end)
        opt.MouseButton1Click:Connect(function()
            cfg[key] = item btn.Text = "  " .. tostring(item) .. " ▼" dropFrame.Visible = false
            if callback then callback(item) end saveCfg()
        end)
    end
    btn.MouseButton1Click:Connect(function() dropFrame.Visible = not dropFrame.Visible if dropFrame.Visible then dropFrame.ZIndex = 100 end end)
end

local tabOverview = createTab("Обзор")
local tabFarm = createTab("Авто Ферма")
local tabEgg = createTab("Яйцо")
local tabEvent = createTab("Ивент / Оптимизация")

createToggle(tabFarm, 1, "Автофарм зоны", "breakables")
createToggle(tabFarm, 2, "Только тыквы", "pumpkinsOnly")
createToggle(tabFarm, 3, "Автопрогресс", "autoProg", function(v) if v then normalizeProgression() end end)
createToggle(tabFarm, 4, "Быстрые тыквы", "fastPumpkins")
createDropdown(tabFarm, 5, "Выбор зоны", {"best", "1", "2", "3", "4", "5"}, "zoneMode")

createToggle(tabEgg, 1, "Автооткрытие яиц", "autoHatch")
createToggle(tabEgg, 2, "Без анимаций", "noAnim", function(v) if v then killAnimations() end end)
createDropdown(tabEgg, 3, "Выбор яйца", {"auto", "Cocoa Cabin Egg", "Apple Orchard Egg", "Hayride Hill Egg", "Cider Mill Egg", "Golden Grove Egg"}, "eggChoice")

createToggle(tabEvent, 1, "Ультра-оптимизация (Без лагов)", "ultraOpti", function(v) applyUltra() end)
createToggle(tabEvent, 2, "Апгрейды тайкуна", "autoBuy")
createToggle(tabEvent, 3, "Апгрейды тыквы (CW)", "autoUpgrades")
createToggle(tabEvent, 4, "Покупка у торговца", "autoMerchant")
createToggle(tabEvent, 5, "Автопочта", "autoMail")

toggleBtn.MouseButton1Click:Connect(function() main.Visible = not main.Visible end)
closeBtn.MouseButton1Click:Connect(function() main.Visible = false end)

local dragging, dragStart, dragOrigin
topBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = true dragStart = input.Position dragOrigin = main.Position end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local d = input.Position - dragStart
        main.Position = UDim2.new(dragOrigin.X.Scale, dragOrigin.X.Offset + d.X, dragOrigin.Y.Scale, dragOrigin.Y.Offset + d.Y)
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
end)

switchTab("Обзор")
applyUltra()
if cfg.noAnim then killAnimations() end
print("[Bazz Hub] Загружено. Компактный интерфейс.")
