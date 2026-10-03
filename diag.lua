-- ==========================================
-- ТЕСТ DELTA ФУНКЦИЙ для AUTO CLAN FARM
-- ==========================================
print("=== DELTA TEST ===")

-- 1. HTTP
print("request:", type(request))
print("http_request:", type(http_request))

-- 2. HWID
print("gethwid:", type(gethwid))

-- 3. File IO
print("readfile:", type(readfile))
print("writefile:", type(writefile))
print("isfile:", type(isfile))
print("makefolder:", type(makefolder))

-- 4. getconnections (нужен для боя с боссом!)
print("getconnections:", type(getconnections))

-- 5. setthreadidentity (нужен для UI)
print("setthreadidentity:", type(setthreadidentity))

-- 6. Доступ к PS99 Library
local RS = game:GetService("ReplicatedStorage")
local L = RS:FindFirstChild("Library")
print("RS.Library:", L and "OK" or "nil")

if L then
    print("L.Client:", L:FindFirstChild("Client") and "OK" or "nil")
    print("L.Types:", L:FindFirstChild("Types") and "OK" or "nil")
    print("HatchWarCmds:", L.Client and L.Client:FindFirstChild("HatchWarCmds") and "OK" or "nil")
    print("EventUpgradeCmds:", L.Client and L.Client:FindFirstChild("EventUpgradeCmds") and "OK" or "nil")
end

print("=== END TEST ===")
