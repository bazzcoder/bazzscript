-- ==========================================
-- AUTO CLAN FARM — ДИАГНОСТИКА v1.0
-- Patch 96 (Hatch Wars / Soul Lantern)
-- Запускать внутри ивента
-- ==========================================

print("========== AUTO CLAN FARM DIAG ==========")
print("PlaceId:", game.PlaceId)
print("JobId:", game.JobId)

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

-- ==========================================
-- 1. SAVE — что вообще есть
-- ==========================================
print("\n[1] SAVE KEYS")
local Save
pcall(function() Save = require(RS.Library.Client.Save) end)

local d
if Save then
    d = Save.Get()
    if d then
        for k, v in pairs(d) do
            local t = type(v)
            if t == "table" then
                local n = 0
                for _ in pairs(v) do n = n + 1 end
                print("  "..tostring(k).." [table, "..n.."]")
            else
                print("  "..tostring(k).." = "..tostring(v))
            end
        end
    else
        print("  Save.Get() = nil")
    end
else
    print("  Save = nil")
end

-- ==========================================
-- 2. INVENTORY — категории и содержимое
-- ==========================================
print("\n[2] INVENTORY")
if d and d.Inventory then
    for cat, items in pairs(d.Inventory) do
        local n = 0
        for _ in pairs(items) do n = n + 1 end
        print("  "..cat..": "..n.." items")
    end

    -- Яйца (ищем везде)
    print("\n[3] EGGS (поиск по всем категориям)")
    for cat, items in pairs(d.Inventory) do
        if type(items) == "table" then
            for uid, item in pairs(items) do
                local id = tostring(item.id or "")
                if id:lower():find("egg") then
                    print("  ["..cat.."] id="..id.." am="..tostring(item._am or item.amount or 1))
                end
            end
        end
    end

    -- Consumable (бусты, ванды, орбы?)
    print("\n[4] CONSUMABLE (первые 30)")
    local c = 0
    if d.Inventory.Consumable then
        for uid, item in pairs(d.Inventory.Consumable) do
            print("  id="..tostring(item.id).." am="..tostring(item._am or 1))
            c = c + 1
            if c >= 30 then break end
        end
    end

    -- Misc
    print("\n[5] MISC (первые 30)")
    c = 0
    if d.Inventory.Misc then
        for uid, item in pairs(d.Inventory.Misc) do
            print("  id="..tostring(item.id).." am="..tostring(item._am or 1))
            c = c + 1
            if c >= 30 then break end
        end
    end
end

-- ==========================================
-- 6. CLAN / CANDY / WANDS / FLAMES / ORB BANK
-- ==========================================
print("\n[6] CLAN / CANDY / WANDS / FLAMES / ORB / BATTLE (поиск в Save)")
if d then
    for k, v in pairs(d) do
        local ks = tostring(k):lower()
        if ks:find("clan") or ks:find("candy") or ks:find("wand")
           or ks:find("flame") or ks:find("orb") or ks:find("battle")
           or ks:find("soul") or ks:find("luck") or ks:find("pumpkin")
           or ks:find("hatch") or ks:find("upgrade") or ks:find("zone") then
            local t = type(v)
            if t == "table" then
                local n = 0
                for _ in pairs(v) do n = n + 1 end
                print("  "..tostring(k).." [table, "..n.."]")
                local c = 0
                for kk, vv in pairs(v) do
                    print("    "..tostring(kk).." = "..tostring(vv))
                    c = c + 1
                    if c >= 5 then break end
                end
            else
                print("  "..tostring(k).." = "..tostring(v))
            end
        end
    end
end

-- ==========================================
-- 7. NETWORK ENDPOINTS
-- ==========================================
print("\n[7] NETWORK")
local Network = RS:FindFirstChild("Network")
if Network then
    local total, interesting = 0, 0
    for _, v in ipairs(Network:GetChildren()) do
        total = total + 1
        local n = v.Name:lower()
        if n:find("hatch") or n:find("egg") or n:find("orb")
           or n:find("boost") or n:find("upgrade") or n:find("clan")
           or n:find("battle") or n:find("flame") or n:find("soul")
           or n:find("burst") or n:find("luck") or n:find("pumpkin")
           or n:find("candy") or n:find("wand") or n:find("zone")
           or n:find("boss") or n:find("circle") or n:find("spell") then
            print("  "..v.Name.." ("..v.ClassName..")")
            interesting = interesting + 1
        end
    end
    print("  Всего: "..total..", интересных: "..interesting)
else
    print("  Network = nil")
end

-- ==========================================
-- 8. WORKSPACE — объекты ивента
-- ==========================================
print("\n[8] WORKSPACE")
for _, v in ipairs(workspace:GetChildren()) do
    local n = v.Name:lower()
    if n:find("event") or n:find("orb") or n:find("flame")
       or n:find("pumpkin") or n:find("hatch") or n:find("battle")
       or n:find("soul") or n:find("lantern") or n:find("boss")
       or n:find("circle") or n:find("zone") or n:find("candy") then
        print("  "..v.Name.." ("..v.ClassName..")")
        if v:IsA("Folder") or v:IsA("Model") then
            local c = 0
            for _, ch in ipairs(v:GetChildren()) do
                print("    └ "..ch.Name.." ("..ch.ClassName..")")
                c = c + 1
                if c >= 8 then print("    └ ..."); break end
            end
        end
    end
end

-- ==========================================
-- 9. ИГРОК — где мы
-- ==========================================
print("\n[9] PLAYER STATE")
local char = LP.Character
if char and char:FindFirstChild("HumanoidRootPart") then
    print("  HRP:", tostring(char.HumanoidRootPart.Position))
end
print("  Team:", tostring(LP.Team and LP.Team.Name))
print("  Attribute Zone:", tostring(LP:GetAttribute("Zone")))

-- ==========================================
-- 10. ВСЕ РЕМОУТЫ В ReplicatedStorage (что вообще есть)
-- ==========================================
print("\n[10] RS — Remotes (что вообще есть в игре)")
for _, v in ipairs(RS:GetChildren()) do
    if v:IsA("Folder") and (v.Name:lower():find("remote") or v.Name:lower():find("net") or v.Name:lower():find("api")) then
        print("  Folder: "..v.Name)
        local c = 0
        for _, ch in ipairs(v:GetChildren()) do
            print("    └ "..ch.Name.." ("..ch.ClassName..")")
            c = c + 1
            if c >= 20 then print("    └ ..."); break end
        end
    end
end

print("\n========== END DIAG ==========")
