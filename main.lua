--[[
    PL HUB - MAIN (CORRIGIDO)
    https://raw.githubusercontent.com/guizinfdk/loaders/main/main.lua

    Parser recursivo — varre tabelas aninhadas (Placement, Mutations, etc.)
    pra achar o nome do pet em qualquer layout de record.
--]]

local Players                = game:GetService("Players")
local RunService             = game:GetService("RunService")
local UserInputService       = game:GetService("UserInputService")
local TweenService           = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage      = game:GetService("ReplicatedStorage")
local Workspace              = game:GetService("Workspace")

local LP    = Players.LocalPlayer
local PGui  = LP:WaitForChild("PlayerGui")
local Cam   = Workspace.CurrentCamera

-- Configs
local VEL_RUN      = 1e15
local DIST_CHEGADA = 4
local IGNORAR_Y    = true
local WALK_TMP     = 500
local JUMP_TMP     = 120
local DUR_TRAVA    = 1
local CLONE_LOCAL  = true
local NOME_SMART   = "SmartPromptPart"
local PASTA_OVOS   = "AreaEggSlotsClient"

-- ============================================================
-- LOADER — pets.lua
-- ============================================================
local BASE_URL = "https://raw.githubusercontent.com/guizinfdk/loaders/refs/heads/main/"

local PetDB = {}
pcall(function()
    PetDB = loadstring(game:HttpGet(BASE_URL .. "pets.lua", true))() or {}
end)

local nPetDB = 0
for _ in pairs(PetDB) do nPetDB = nPetDB + 1 end
print("[PL HUB] PetDB carregado:", nPetDB, "pets")

-- ============================================================
-- EggState (do jogo)
-- ============================================================
local EggState = require(ReplicatedStorage.Client.EggState)

-- ============================================================
-- CORES DE RARIDADE
-- ============================================================
local CORES_RARIDADE = {
    Common    = Color3.fromRGB(150, 150, 150),
    Uncommon  = Color3.fromRGB(0, 255, 0),
    Rare      = Color3.fromRGB(25, 145, 255),
    Epic      = Color3.fromRGB(195, 2, 255),
    Legendary = Color3.fromRGB(255, 133, 34),
    Mythic    = Color3.fromRGB(255, 43, 100),
    Cosmic    = Color3.fromRGB(65, 0, 170),
    Secret    = Color3.fromRGB(46, 46, 46),
    Eternal   = Color3.fromRGB(255, 30, 240),
    Divine    = Color3.fromRGB(251, 255, 0),
    Titan     = Color3.fromRGB(255, 64, 64),
    LightDark = Color3.fromRGB(196, 148, 255),
    Boss      = Color3.fromRGB(10, 10, 10),
}

-- ============================================================
-- CLASSIFICADORES
-- ============================================================
local ESTADOS  = { Slot=true, Dropped=true, Carried=true, Claimed=true, GuardCarried=true, Free=true, Placed=true }
local MUTACOES = { Silver=true, Golden=true, Rainbow=true, Scrambled=true, Boss=true, Monstrous=true, Sakura=true, GreatBloom=true, MechaUpgraded=true, None=true }
local BIOMAS   = {
    ["Forest"]=true, ["Jungle"]=true, ["Desert"]=true, ["Snow"]=true,
    ["Volcano"]=true, ["Lake"]=true, ["Abyss Ocean"]=true,
    ["Prehistoric"]=true, ["Cherry Blossom"]=true, ["Cosmic"]=true,
    ["Light Dark"]=true, ["Titan Temple"]=true,
}

local function isHex(s)
    return type(s) == "string" and s:match("^[%x]+$") ~= nil
end

local function classificar(v)
    if type(v) ~= "string" then return nil end
    if #v >= 20 and isHex(v) then return "uid" end
    if v:find(":") and v:find("FirstAreaEgg") then return "uid" end
    if #v == 6 and isHex(v) then return "hash" end
    if v:match("^Slot_%d+$") then return "slot" end
    if ESTADOS[v] then return "estado" end
    if MUTACOES[v] then return "mutacao" end
    if BIOMAS[v] then return "bioma" end
    return "pet"
end

-- ============================================================
-- PARSER RECURSIVO — varre tabelas aninhadas
-- ============================================================
local function varrerRecursivo(t, prof, visitados, strings, cframes)
    prof = prof or 0
    visitados = visitados or {}
    strings = strings or {}
    cframes = cframes or {}

    if prof > 5 then return strings, cframes end
    if type(t) ~= "table" then return strings, cframes end
    if visitados[t] then return strings, cframes end
    visitados[t] = true

    for _, v in pairs(t) do
        local tv = typeof(v)
        if tv == "string" then
            table.insert(strings, v)
        elseif tv == "CFrame" then
            table.insert(cframes, v)
        elseif tv == "table" then
            varrerRecursivo(v, prof + 1, visitados, strings, cframes)
        end
    end
    return strings, cframes
end

local function parseRecord(uid, record)
    if type(record) ~= "table" then return nil end

    local strings, cframes = varrerRecursivo(record)

    local info = { uid = uid, pet = nil, biome = nil, cf = nil }
    local candidatosPet = {}

    for _, s in ipairs(strings) do
        local cat = classificar(s)
        if cat == "bioma" and not info.biome then
            info.biome = s
        elseif cat == "pet" then
            table.insert(candidatosPet, s)
        end
    end

    -- Prioridade 1: pet conhecido no PetDB
    for _, cand in ipairs(candidatosPet) do
        if PetDB[cand] then info.pet = cand; break end
    end
    -- Prioridade 2: o nome mais longo
    if not info.pet then
        local melhor, tam = nil, 0
        for _, cand in ipairs(candidatosPet) do
            if #cand > tam then melhor, tam = cand, #cand end
        end
        info.pet = melhor
    end

    if not info.pet then return nil end

    -- CFrame mais baixo (chão)
    local menorY = math.huge
    for _, cf in ipairs(cframes) do
        if cf.Position.Y < menorY then menorY = cf.Position.Y; info.cf = cf end
    end

    return info
end

-- ============================================================
-- DADOS DO PET
-- ============================================================
local function getDadosPet(pet)
    if not pet then return nil, nil, nil end
    if PetDB[pet] then
        local d = PetDB[pet]
        local cor = d.color or (d.rarity and CORES_RARIDADE[d.rarity]) or nil
        return d.icon, d.rarity, cor
    end
    return nil, nil, nil
end

-- ============================================================
-- VARREDURA DA PASTA + RECORDS
-- ============================================================
local function varrerPasta()
    local pasta = Workspace:FindFirstChild(PASTA_OVOS)
    local out = {}
    if not pasta then return out end
    for _, m in ipairs(pasta:GetChildren()) do
        if m:IsA("Model") then
            local hp = m:FindFirstChild("Hitbox")
            if hp and hp:IsA("BasePart") then
                out[m.Name] = { cf = hp.CFrame }
            elseif m.PrimaryPart then
                out[m.Name] = { cf = m.PrimaryPart.CFrame }
            end
        end
    end
    return out
end

local function getRecords()
    if type(EggState.ReadFieldEggs) ~= "function" then return {} end
    local ok, res = pcall(EggState.ReadFieldEggs, EggState)
    return (ok and type(res) == "table") and res or {}
end

-- ============================================================
-- TELEPORTE
-- ============================================================
local Dest = { pos = nil, usarSpawn = true }
local T = { conn=nil, ativo=false, char=nil, hum=nil, root=nil, wOrig=nil, jOrig=nil }

function T.refs()
    T.char = LP.Character
    if not T.char then return false end
    T.hum  = T.char:FindFirstChildOfClass("Humanoid")
    T.root = T.char:FindFirstChild("HumanoidRootPart")
    return T.hum ~= nil and T.root ~= nil
end

function T.pegarSpawn()
    local lista = {}
    for _, o in ipairs(Workspace:GetDescendants()) do
        if o:IsA("SpawnLocation") then table.insert(lista, o) end
    end
    if #lista == 0 then return nil end
    if not T.root then return lista[1] end
    local melhor, dMin = nil, math.huge
    for _, sp in ipairs(lista) do
        local d = (sp.Position - T.root.Position).Magnitude
        if d < dMin then melhor, dMin = sp, d end
    end
    return melhor
end

function T.pegarAlvo()
    if Dest.usarSpawn then
        local sp = T.pegarSpawn()
        if not sp then return nil end
        return sp.Position + Vector3.new(0, 3, 0)
    end
    if not Dest.pos then return nil end
    return Dest.pos + Vector3.new(0, 3, 0)
end

function T.parar()
    if T.conn then T.conn:Disconnect(); T.conn = nil end
    if T.hum then
        if T.wOrig then T.hum.WalkSpeed = T.wOrig end
        if T.jOrig then T.hum.JumpPower = T.jOrig end
    end
    T.wOrig, T.jOrig, T.ativo = nil, nil, false
end

function T.iniciar()
    if T.ativo then T.parar() return end
    if not T.refs() then return end
    local alvo = T.pegarAlvo()
    if not alvo then return end

    T.wOrig = T.hum.WalkSpeed
    T.jOrig = T.hum.JumpPower
    T.hum.WalkSpeed = WALK_TMP
    T.hum.JumpPower = JUMP_TMP
    T.ativo = true

    T.conn = RunService.Heartbeat:Connect(function(dt)
        if not T.ativo then return end
        if not T.refs() then T.parar() return end

        local org = T.root.Position
        local dlt = alvo - org
        if IGNORAR_Y then dlt = Vector3.new(dlt.X, 0, dlt.Z) end
        local dist = dlt.Magnitude

        if dist <= DIST_CHEGADA then
            T.root.CFrame = CFrame.new(alvo) * (T.root.CFrame - T.root.CFrame.Position)
            T.root.AssemblyLinearVelocity = Vector3.zero
            T.root.AssemblyAngularVelocity = Vector3.zero
            T.parar(); return
        end

        local dir = (dist > 0) and dlt.Unit or T.root.CFrame.LookVector
        local passo = math.min(VEL_RUN * dt, dist)
        local nova = org + dir * passo
        T.root.CFrame = CFrame.lookAt(nova, nova + dir)
        T.root.AssemblyLinearVelocity = Vector3.zero
        T.root.AssemblyAngularVelocity = Vector3.zero
    end)
end

-- ============================================================
-- DISFARCE
-- ============================================================
local D = { ativo=false, clone=nil, connCam=nil, thread=nil }

function D.limpar()
    D.ativo = false
    if D.connCam then D.connCam:Disconnect(); D.connCam = nil end
    local t = D.thread
    D.thread = nil
    if t then pcall(task.cancel, t) end
    if D.clone then D.clone:Destroy(); D.clone = nil end
    Cam.CameraType = Enum.CameraType.Custom
end

function D.iniciar()
    if D.ativo then D.limpar() return end
    local ch = LP.Character
    if not ch or not ch:FindFirstChild("HumanoidRootPart") then return end

    D.ativo = true
    local cf = Cam.CFrame
    Cam.CameraType = Enum.CameraType.Scriptable
    Cam.CFrame = cf

    D.connCam = RunService.RenderStepped:Connect(function()
        if D.ativo then Cam.CFrame = cf end
    end)

    if CLONE_LOCAL and ch.Parent then
        local ea = ch.Archivable
        ch.Archivable = true
        local ok, cl = pcall(function() return ch:Clone() end)
        if ok and cl then
            cl.Name = "CloneLocal_" .. LP.Name
            for _, d in ipairs(cl:GetDescendants()) do
                if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end
            end
            local h = cl:FindFirstChildOfClass("Humanoid")
            if h then
                h.WalkSpeed = 0; h.JumpPower = 0; h.PlatformStand = true
                h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            end
            for _, p in ipairs(cl:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.Anchored = true
                    p.CanCollide = false
                    p.CanTouch = false
                    p.CanQuery = false
                end
            end
            cl.Parent = Workspace
            D.clone = cl
        end
        ch.Archivable = ea
    end

    D.thread = task.delay(DUR_TRAVA, function()
        D.thread = nil; D.limpar()
    end)
end

local armado = false

ProximityPromptService.PromptTriggered:Connect(function(p, pl)
    if not armado then return end
    if pl ~= LP then return end
    local pai = p and p.Parent
    if not pai or pai.Name ~= NOME_SMART then return end
    T.iniciar(); D.iniciar()
end)

LP.CharacterAdded:Connect(function()
    task.wait(1)
    if T.ativo then T.parar() end
    D.limpar(); T.refs()
end)

T.refs()

-- ============================================================
-- UI
-- ============================================================
local ROXO   = Color3.fromRGB(140, 80, 255)
local ROXO_D = Color3.fromRGB(60, 30, 120)
local VERDE  = Color3.fromRGB(80, 240, 110)
local VERM   = Color3.fromRGB(255, 70, 90)
local AZUL   = Color3.fromRGB(80, 200, 240)
local BG     = Color3.fromRGB(14, 12, 22)
local BG_BTN = Color3.fromRGB(28, 22, 42)

local gui = Instance.new("ScreenGui")
gui.Name = "PLHubGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
gui.IgnoreGuiInset = true

local ok, hui = pcall(function() return gethui and gethui() end)
if ok and hui then pcall(function() gui.Parent = hui end) end
if not gui.Parent then gui.Parent = PGui end

local holder = Instance.new("Frame")
holder.Size = UDim2.new(0, 240, 0, 260)
holder.Position = UDim2.new(0.5, -120, 0.1, 0)
holder.BackgroundTransparency = 1
holder.Active = true
holder.Draggable = true
holder.ClipsDescendants = true
holder.Parent = gui

local borda = Instance.new("Frame")
borda.Size = UDim2.new(1, 4, 1, 4)
borda.Position = UDim2.new(0, -2, 0, -2)
borda.BackgroundColor3 = Color3.fromRGB(255,255,255)
borda.BorderSizePixel = 0
borda.ZIndex = 1
borda.Parent = holder
Instance.new("UICorner", borda).CornerRadius = UDim.new(0, 14)

local gradB = Instance.new("UIGradient")
gradB.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0.00, ROXO),
    ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 90, 220)),
    ColorSequenceKeypoint.new(0.60, Color3.fromRGB(90, 180, 255)),
    ColorSequenceKeypoint.new(1.00, ROXO),
})
gradB.Parent = borda

local menu = Instance.new("Frame")
menu.Size = UDim2.new(1, -4, 1, -4)
menu.Position = UDim2.new(0, 2, 0, 2)
menu.BackgroundColor3 = BG
menu.BorderSizePixel = 0
menu.ZIndex = 2
menu.Parent = holder
Instance.new("UICorner", menu).CornerRadius = UDim.new(0, 12)

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 32)
header.BackgroundTransparency = 1
header.ZIndex = 3
header.Parent = menu

local led = Instance.new("Frame")
led.Size = UDim2.new(0, 6, 0, 6)
led.Position = UDim2.new(0, 10, 0, 13)
led.BackgroundColor3 = VERM
led.BorderSizePixel = 0
led.ZIndex = 4
led.Parent = header
Instance.new("UICorner", led).CornerRadius = UDim.new(1, 0)

local titulo = Instance.new("TextLabel")
titulo.Size = UDim2.new(1, -60, 0, 14)
titulo.Position = UDim2.new(0, 22, 0, 4)
titulo.BackgroundTransparency = 1
titulo.Font = Enum.Font.GothamBold
titulo.TextSize = 12
titulo.TextColor3 = Color3.fromRGB(240, 230, 255)
titulo.TextXAlignment = Enum.TextXAlignment.Left
titulo.Text = "PL HUB"
titulo.ZIndex = 4
titulo.Parent = header

local sub = Instance.new("TextLabel")
sub.Size = UDim2.new(1, -60, 0, 10)
sub.Position = UDim2.new(0, 22, 0, 18)
sub.BackgroundTransparency = 1
sub.Font = Enum.Font.Gotham
sub.TextSize = 8
sub.TextColor3 = Color3.fromRGB(170, 150, 210)
sub.TextXAlignment = Enum.TextXAlignment.Left
sub.Text = "IB: @caligsc"
sub.ZIndex = 4
sub.Parent = header

local btnMin = Instance.new("TextButton")
btnMin.Size = UDim2.new(0, 18, 0, 18)
btnMin.Position = UDim2.new(1, -44, 0, 7)
btnMin.BackgroundTransparency = 1
btnMin.Font = Enum.Font.GothamBold
btnMin.TextSize = 14
btnMin.TextColor3 = Color3.fromRGB(200, 180, 220)
btnMin.Text = "—"
btnMin.ZIndex = 5
btnMin.Parent = header

local btnX = Instance.new("TextButton")
btnX.Size = UDim2.new(0, 18, 0, 18)
btnX.Position = UDim2.new(1, -22, 0, 7)
btnX.BackgroundTransparency = 1
btnX.Font = Enum.Font.GothamBold
btnX.TextSize = 12
btnX.TextColor3 = Color3.fromRGB(200, 160, 200)
btnX.Text = "✕"
btnX.ZIndex = 5
btnX.Parent = header
btnX.MouseButton1Click:Connect(function() holder.Visible = false end)

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -16, 0, 20)
tabBar.Position = UDim2.new(0, 8, 0, 34)
tabBar.BackgroundTransparency = 1
tabBar.ZIndex = 3
tabBar.Parent = menu

local bFunc = Instance.new("TextButton")
bFunc.Size = UDim2.new(0.5, -2, 1, 0)
bFunc.Position = UDim2.new(0, 0, 0, 0)
bFunc.BackgroundColor3 = Color3.fromRGB(40, 28, 65)
bFunc.BorderSizePixel = 0
bFunc.Font = Enum.Font.GothamBold
bFunc.TextSize = 10
bFunc.TextColor3 = ROXO
bFunc.Text = "⚙ FUNÇÕES"
bFunc.ZIndex = 4
bFunc.Parent = tabBar
Instance.new("UICorner", bFunc).CornerRadius = UDim.new(0, 6)

local bOv = Instance.new("TextButton")
bOv.Size = UDim2.new(0.5, -2, 1, 0)
bOv.Position = UDim2.new(0.5, 2, 0, 0)
bOv.BackgroundColor3 = BG_BTN
bOv.BorderSizePixel = 0
bOv.Font = Enum.Font.GothamBold
bOv.TextSize = 10
bOv.TextColor3 = Color3.fromRGB(235, 225, 255)
bOv.Text = "🥚 OVOS"
bOv.ZIndex = 4
bOv.Parent = tabBar
Instance.new("UICorner", bOv).CornerRadius = UDim.new(0, 6)

local faixa = Instance.new("Frame")
faixa.Size = UDim2.new(1, -16, 0, 2)
faixa.Position = UDim2.new(0, 8, 0, 58)
faixa.BackgroundColor3 = Color3.fromRGB(255,255,255)
faixa.BorderSizePixel = 0
faixa.ZIndex = 3
faixa.Parent = menu
local gF = Instance.new("UIGradient")
gF.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0.00, 1),
    NumberSequenceKeypoint.new(0.20, 0),
    NumberSequenceKeypoint.new(0.80, 0),
    NumberSequenceKeypoint.new(1.00, 1),
})
gF.Color = ColorSequence.new(ROXO, Color3.fromRGB(200, 130, 255))
gF.Parent = faixa

-- Aba Funções
local aFunc = Instance.new("Frame")
aFunc.Size = UDim2.new(1, 0, 1, -66)
aFunc.Position = UDim2.new(0, 0, 0, 62)
aFunc.BackgroundTransparency = 1
aFunc.ZIndex = 3
aFunc.Parent = menu

local function criarBtn(parent, y, h, txt)
    local c = Instance.new("Frame")
    c.Size = UDim2.new(1, -16, 0, h)
    c.Position = UDim2.new(0, 8, 0, y)
    c.BackgroundColor3 = BG_BTN
    c.BorderSizePixel = 0
    c.ZIndex = 3
    c.Parent = parent
    Instance.new("UICorner", c).CornerRadius = UDim.new(0, 7)

    local bl = Instance.new("Frame")
    bl.Size = UDim2.new(0, 3, 1, -6)
    bl.Position = UDim2.new(0, 3, 0, 3)
    bl.BackgroundColor3 = ROXO
    bl.BorderSizePixel = 0
    bl.ZIndex = 4
    bl.Parent = c
    Instance.new("UICorner", bl).CornerRadius = UDim.new(0, 2)

    local bs = Instance.new("UIStroke")
    bs.Thickness = 1
    bs.Color = ROXO_D
    bs.Parent = c

    local lb = Instance.new("TextLabel")
    lb.Size = UDim2.new(1, -40, 1, 0)
    lb.Position = UDim2.new(0, 12, 0, 0)
    lb.BackgroundTransparency = 1
    lb.Font = Enum.Font.GothamBold
    lb.TextSize = 11
    lb.TextColor3 = Color3.fromRGB(230, 220, 255)
    lb.TextXAlignment = Enum.TextXAlignment.Left
    lb.Text = txt
    lb.ZIndex = 4
    lb.Parent = c

    local st = Instance.new("TextLabel")
    st.Size = UDim2.new(0, 18, 1, 0)
    st.Position = UDim2.new(1, -20, 0, 0)
    st.BackgroundTransparency = 1
    st.Font = Enum.Font.GothamBold
    st.TextSize = 14
    st.TextColor3 = ROXO
    st.TextTransparency = 1
    st.Text = "›"
    st.ZIndex = 4
    st.Parent = c

    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 1, 0)
    b.BackgroundTransparency = 1
    b.Text = ""
    b.ZIndex = 6
    b.Parent = c

    b.MouseEnter:Connect(function()
        TweenService:Create(c, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(40, 30, 60) }):Play()
        TweenService:Create(bs, TweenInfo.new(0.15), { Color = ROXO }):Play()
        TweenService:Create(st, TweenInfo.new(0.15), { TextTransparency = 0, Position = UDim2.new(1, -16, 0, 0) }):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(c, TweenInfo.new(0.2), { BackgroundColor3 = BG_BTN }):Play()
        TweenService:Create(bs, TweenInfo.new(0.2), { Color = ROXO_D }):Play()
        TweenService:Create(st, TweenInfo.new(0.2), { TextTransparency = 1, Position = UDim2.new(1, -20, 0, 0) }):Play()
    end)

    local function bounce()
        local t = c.Size
        TweenService:Create(c, TweenInfo.new(0.06), {
            Size = UDim2.new(t.X.Scale, t.X.Offset - 5, t.Y.Scale, t.Y.Offset - 2),
        }):Play()
        task.wait(0.07)
        TweenService:Create(c, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = t }):Play()
    end

    return b, c, lb, st, bl, bs, bounce
end

local bAnti, cAnti, lAnti, sAnti, brAnti, borAnti, bncAnti = criarBtn(aFunc, 0, 28, "🥚 ANTI-BOSS")
local bDst, cDst, lDst, sDst, brDst, borDst, bncDst = criarBtn(aFunc, 32, 24, "📍 DEFINIR DESTINO")
local bRst, cRst, lRst, sRst, brRst, borRst, bncRst = criarBtn(aFunc, 60, 24, "🎯 RESET SPAWN")

-- Aba Ovos
local aOv = Instance.new("Frame")
aOv.Size = UDim2.new(1, 0, 1, -66)
aOv.Position = UDim2.new(0, 0, 0, 62)
aOv.BackgroundTransparency = 1
aOv.Visible = false
aOv.ZIndex = 3
aOv.Parent = menu

local debugLb = Instance.new("TextLabel")
debugLb.Size = UDim2.new(1, -16, 0, 16)
debugLb.Position = UDim2.new(0, 8, 0, 2)
debugLb.BackgroundTransparency = 1
debugLb.Font = Enum.Font.Code
debugLb.TextSize = 9
debugLb.TextColor3 = Color3.fromRGB(120, 200, 140)
debugLb.TextXAlignment = Enum.TextXAlignment.Left
debugLb.Text = "carregando..."
debugLb.ZIndex = 5
debugLb.Parent = aOv

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -16, 1, -22)
scroll.Position = UDim2.new(0, 8, 0, 20)
scroll.BackgroundColor3 = Color3.fromRGB(10, 8, 16)
scroll.BorderSizePixel = 0
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = ROXO
scroll.ZIndex = 4
scroll.Parent = aOv
Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 8)

local lay = Instance.new("UIListLayout")
lay.Padding = UDim.new(0, 3)
lay.SortOrder = Enum.SortOrder.LayoutOrder
lay.Parent = scroll

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 4); pad.PaddingBottom = UDim.new(0, 4)
pad.PaddingLeft = UDim.new(0, 4); pad.PaddingRight = UDim.new(0, 4)
pad.Parent = scroll

local function criarLinha(order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 40)
    row.BackgroundColor3 = Color3.fromRGB(22, 18, 32)
    row.BorderSizePixel = 0
    row.LayoutOrder = order
    row.ZIndex = 5
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

    local stk = Instance.new("UIStroke")
    stk.Thickness = 1
    stk.Color = ROXO_D
    stk.Parent = row

    local img = Instance.new("ImageLabel")
    img.Size = UDim2.new(0, 32, 0, 32)
    img.Position = UDim2.new(0, 4, 0.5, -16)
    img.BackgroundColor3 = Color3.fromRGB(30, 25, 45)
    img.BackgroundTransparency = 0.3
    img.BorderSizePixel = 0
    img.ZIndex = 6
    img.Parent = row
    Instance.new("UICorner", img).CornerRadius = UDim.new(0, 4)

    local nm = Instance.new("TextLabel")
    nm.Size = UDim2.new(1, -90, 0, 14)
    nm.Position = UDim2.new(0, 42, 0, 4)
    nm.BackgroundTransparency = 1
    nm.Font = Enum.Font.GothamBold
    nm.TextSize = 11
    nm.TextColor3 = Color3.fromRGB(240, 230, 255)
    nm.TextXAlignment = Enum.TextXAlignment.Left
    nm.TextTruncate = Enum.TextTruncate.AtEnd
    nm.ZIndex = 6
    nm.Parent = row

    local rr = Instance.new("TextLabel")
    rr.Size = UDim2.new(1, -90, 0, 10)
    rr.Position = UDim2.new(0, 42, 0, 18)
    rr.BackgroundTransparency = 1
    rr.Font = Enum.Font.GothamBold
    rr.TextSize = 9
    rr.TextColor3 = Color3.fromRGB(200, 200, 220)
    rr.TextXAlignment = Enum.TextXAlignment.Left
    rr.TextTruncate = Enum.TextTruncate.AtEnd
    rr.ZIndex = 6
    rr.Parent = row

    local dd = Instance.new("TextLabel")
    dd.Size = UDim2.new(0, 44, 1, 0)
    dd.Position = UDim2.new(1, -48, 0, 0)
    dd.BackgroundTransparency = 1
    dd.Font = Enum.Font.GothamBold
    dd.TextSize = 10
    dd.TextColor3 = AZUL
    dd.TextXAlignment = Enum.TextXAlignment.Right
    dd.ZIndex = 6
    dd.Parent = row

    return row, img, nm, rr, dd, stk
end

local cache = {}

local function renderizar()
    local records = getRecords()
    local pasta   = varrerPasta()
    local root = T.root or (LP.Character and LP.Character:FindFirstChild("HumanoidRootPart"))

    local nRec, nPasta = 0, 0
    for _ in pairs(records) do nRec = nRec + 1 end
    for _ in pairs(pasta)   do nPasta = nPasta + 1 end

    debugLb.Text = string.format(
        "DB:%s | Records:%d | Pasta:%d",
        (nPetDB > 0) and "✓" or "✗", nRec, nPasta
    )

    local lista, vistos = {}, {}

    for uid, rec in pairs(records) do
        local info = parseRecord(uid, rec)
        if info then
            vistos[uid] = true
            local d = math.huge
            if root and info.cf then
                d = (info.cf.Position - root.Position).Magnitude
            end
            info.dist = d
            table.insert(lista, info)
        end
    end

    for nome, dados in pairs(pasta) do
