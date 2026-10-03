-- ==========================================
-- AUTO CLAN FARM — DIAG v2 (поиск хэтча)
-- ==========================================
print("========== DIAG v2 ==========")

local RS = game:GetService("ReplicatedStorage")
local L = RS:FindFirstChild("Library")
if not L then print("Library = nil"); return end

-- 1. Все модули в Library.Client
print("\n[1] Library.Client — список модулей")
local Client = L:FindFirstChild("Client")
if Client then
    for _, v in ipairs(Client:GetChildren()) do
        local name = v.Name:lower()
        if name:find("egg") or name:find("hatch") or name:find("spawn") 
           or name:find("pet") or name:find("currency") then
            print("  " .. v.Name .. " (" .. v.ClassName .. ")")
        end
    end
end

-- 2. Все модули в Library.Util
print("\n[2] Library.Util — список модулей")
local Util = L:FindFirstChild("Util")
if Util then
    for _, v in ipairs(Util:GetChildren()) do
        local name = v.Name:lower()
        if name:find("egg") or name:find("hatch") or name:find("pumpkin") then
            print("  " .. v.Name .. " (" .. v.ClassName .. ")")
        end
    end
end

-- 3. Types.HatchWar — что внутри
print("\n[3] Types.HatchWar — все ключи")
local Types = L:FindFirstChild("Types")
if Types then
    local hwModule = Types:FindFirstChild("HatchWar")
    if hwModule then
        local ok, types = pcall(require, hwModule)
        if ok and type(types) == "table" then
            for k, v in pairs(types) do
                local t = type(v)
                if t == "table" then
                    local n = 0
                    for _ in pairs(v) do n = n + 1 end
                    print("  " .. tostring(k) .. " [table, " .. n .. "]")
                else
                    print("  " .. tostring(k) .. " = " .. tostring(v))
                end
            end
        end
    end
end

-- 4. Ключи внутри NET_PREFIX
print("\n[4] NET_PREFIX — полный список")
if Types then
    local ok, types = pcall(require, Types.HatchWar)
    if ok and types and types.NET_PREFIX then
        for k, v in pairs(types.NET_PREFIX) do
            print("  " .. tostring(k) .. " = " .. tostring(v))
        end
    end
end

-- 5. ZONES — что внутри (для понимания структуры финального яйца)
print("\n[5] ZONES — все зоны")
if Types then
    local ok, types = pcall(require, Types.HatchWar)
    if ok and types and types.ZONES then
        for i, zone in ipairs(types.ZONES) do
            print("  Zone " .. i .. ":")
            for k, v in pairs(zone) do
                print("    " .. tostring(k) .. " = " .. tostring(v))
            end
        end
    end
end

-- 6. HatchWarCmds — публичные методы
print("\n[6] HatchWarCmds — доступные методы")
local HWMod = Client and Client:FindFirstChild("HatchWarCmds")
if HWMod then
    local ok, hw = pcall(require, HWMod)
    if ok and type(hw) == "table" then
        for k, v in pairs(hw) do
            local t = type(v)
            if t == "function" then
                print("  " .. tostring(k) .. "()")
            elseif t == "table" then
                local sub = {}
                for kk in pairs(v) do table.insert(sub, kk) end
                print("  " .. tostring(k) .. " {" .. table.concat(sub, ", ") .. "}")
            else
                print("  " .. tostring(k) .. " = " .. tostring(v))
            end
        end
    end
end

-- 7. Все RemoteEvent/RemoteFunction в Network
print("\n[7] Network — все ремоуты с 'HW' или 'Egg'")
local Network = RS:FindFirstChild("Network")
if Network then
    for _, v in ipairs(Network:GetChildren()) do
        local n = v.Name:lower()
        if n:find("hw") or n:find("egg") or n:find("hatch") then
            print("  " .. v.Name .. " (" .. v.ClassName .. ")")
        end
    end
end

print("\n========== END DIAG v2 ==========")
