local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local BadgeService = game:GetService("BadgeService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage:WaitForChild("ClashConfig"))
local Util = require(ReplicatedStorage:WaitForChild("ClashUtil"))

local Remotes = Instance.new("Folder"); Remotes.Name = "Remotes"; Remotes.Parent = ReplicatedStorage
local RF = Instance.new("RemoteFunction"); RF.Name = "RF"; RF.Parent = Remotes
local RE = Instance.new("RemoteEvent"); RE.Name = "RE"; RE.Parent = Remotes

local function sanitize(s) return tostring(s or ""):gsub("[^%w _%-]", ""):sub(1, 32) end
local function unit(v)
    if typeof(v) ~= "Vector3" then return Vector3.zAxis end
    local m = v.Magnitude
    return (m < 0.01 or m > 2) and Vector3.zAxis or (v / m)
end

-- NaN-safe direction: zero-distance .Unit produced NaN velocity (void launch)
local function safeDir(from, to)
    local d = to - from
    if d.Magnitude < 0.05 then return Vector3.new(0, 1, 0) end
    return d.Unit
end

local function notify(plr, msg, color) RE:FireClient(plr, "Notify", { Msg = msg, Color = color }) end
local function fxAll(desc) for _, p in ipairs(Players:GetPlayers()) do RE:FireClient(p, "FX", desc) end end
local function cineAll(desc) for _, p in ipairs(Players:GetPlayers()) do RE:FireClient(p, "Cine", desc) end end

-- ── data ──────────────────────────────────────────────────────────
local Store = DataStoreService:GetDataStore("AetherClash_v1")
local LBCash = DataStoreService:GetOrderedDataStore("AetherClashLB_Cash")
local LBKills = DataStoreService:GetOrderedDataStore("AetherClashLB_Kills")
local Sessions = {}

local function defaultSettings()
    local t = {}
    for _, s in ipairs(Config.Settings) do t[s.Key] = s.Def end
    return t
end

local function load(plr)
    local raw
    for _ = 1, 3 do
        local ok, res = pcall(Store.GetAsync, Store, "p_" .. plr.UserId)
        if ok then raw = res break end
        task.wait(1.5)
    end
    local s = {
        Cash = raw and raw.Cash or 250,
        Kills = raw and raw.Kills or 0,
        Deaths = raw and raw.Deaths or 0,
        Rebirths = raw and raw.Rebirths or 0,
        Weapons = (raw and type(raw.Weapons) == "table") and raw.Weapons or { fists = true },
        Equipped = (raw and raw.Equipped) or "fists",
        Droppers = (raw and type(raw.Droppers) == "table") and raw.Droppers or {},
        Settings = (raw and type(raw.Settings) == "table") and raw.Settings or defaultSettings(),
        Vehicles = (raw and type(raw.Vehicles) == "table") and raw.Vehicles or {},
        LoadedOK = raw ~= nil,
        Dirty = false,
    }
    Sessions[plr] = s
    return s
end
local function get(plr) return Sessions[plr] end

local function save(plr)
    local s = Sessions[plr]; if not s then return end
    Sessions[plr] = nil
    if not s.LoadedOK then return end
    local payload = { Cash = s.Cash, Kills = s.Kills, Deaths = s.Deaths, Rebirths = s.Rebirths,
        Weapons = s.Weapons, Equipped = s.Equipped, Droppers = s.Droppers, Settings = s.Settings, Vehicles = s.Vehicles }
    for _ = 1, 3 do
        if pcall(Store.SetAsync, Store, "p_" .. plr.UserId, payload) then break end
        task.wait(1.5)
    end
end

-- ── badges ────────────────────────────────────────────────────────
local awardedBadge = {}
local function awardBadge(plr, key)
    local id = Config.Badges and Config.Badges[key]
    if not id or id <= 0 then return end
    awardedBadge[plr] = awardedBadge[plr] or {}
    if awardedBadge[plr][key] then return end
    awardedBadge[plr][key] = true
    task.spawn(function()
        pcall(function() BadgeService:AwardBadge(plr.UserId, id) end)
    end)
end

-- ── gamepasses ────────────────────────────────────────────────────
local Flags = {}
local function Pass_has(plr, k) return Flags[plr] and Flags[plr][k] or false end
local function Pass_flags(plr) return Flags[plr] or {} end
local function Pass_load(plr)
    local f = {}
    for k, def in pairs(Config.Gamepasses) do
        if def.Id and def.Id > 0 then
            local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, plr.UserId, def.Id)
            f[k] = ok and owns or false
        else f[k] = false end
    end
    Flags[plr] = f
    RE:FireClient(plr, "Passes", f)
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, passId, bought)
    if not bought or not Flags[plr] then return end
    for k, def in pairs(Config.Gamepasses) do
        if def.Id == passId then
            Flags[plr][k] = true
            RE:FireClient(plr, "Passes", Flags[plr])
            notify(plr, def.Name .. " activated!", Config.Colors.Gold)
            if k == "VIP" then
                local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
                if hum then hum.WalkSpeed = Config.Sprint.VipSpeed hum.JumpPower = 60 end
            end
        end
    end
end)

-- ── income ────────────────────────────────────────────────────────
local _rain = false
local function addCash(plr, v)
    local s = get(plr); if not s then return 0 end
    local mult = 1 + s.Rebirths * Config.Rebirth.PerkMult
    if s.Rebirths >= 5 then mult = mult * 1.2 end
    if Pass_has(plr, "DoubleCash") then mult = mult * 2 end
    if Pass_has(plr, "QuadCash") then mult = mult * 4 end
    if Pass_has(plr, "VIP") then mult = mult * 1.1 end
    if _rain then mult = mult * Config.Income.RainMult end
    v = math.floor(v * mult)
    s.Cash += v; s.Dirty = true
    local ls = plr:FindFirstChild("leaderstats")
    if ls then ls.Cash.Value = s.Cash end
    if s.Cash >= 1e6 then awardBadge(plr, "Millionaire") end
    return v
end

local function spend(plr, v)
    local s = get(plr)
    if not s or s.Cash < v then return false end
    s.Cash -= v; s.Dirty = true
    local ls = plr:FindFirstChild("leaderstats")
    if ls then ls.Cash.Value = s.Cash end
    return true
end

local function maxDash(plr)
    local s = get(plr)
    local base = Config.Dash.Charges
    if s and s.Rebirths >= 4 then base = Config.Dash.SurgeCharges end
    return base
end
local function dashRegen(plr)
    local s = get(plr)
    if s and s.Rebirths >= 4 then return Config.Dash.SurgeRegen end
    return Config.Dash.Regen
end

-- ── world ─────────────────────────────────────────────────────────
Lighting.ClockTime = 0
Lighting.Brightness = 1.4
Lighting.Ambient = Color3.fromRGB(52, 48, 78)
Lighting.OutdoorAmbient = Color3.fromRGB(58, 54, 92)
Lighting.FogEnd = 900
do
    local sky = Instance.new("Sky")
    sky.StarCount = 3000; sky.SunAngularSize = 14
    sky.Parent = Lighting
    local atmo = Instance.new("Atmosphere")
    atmo.Density = 0.32; atmo.Offset = 0.4; atmo.Glare = 0.2; atmo.Haze = 1.6
    atmo.Color = Color3.fromRGB(170, 160, 220); atmo.Decay = Color3.fromRGB(52, 44, 96)
    atmo.Parent = Lighting
    local bloom = Instance.new("BloomEffect"); bloom.Intensity = 0.85; bloom.Size = 28; bloom.Threshold = 1.0; bloom.Parent = Lighting
    local sun = Instance.new("SunRaysEffect"); sun.Intensity = 0.14; sun.Spread = 0.8; sun.Parent = Lighting
    local cc = Instance.new("ColorCorrectionEffect"); cc.Saturation = 0.18; cc.Contrast = 0.1; cc.TintColor = Color3.fromRGB(238, 232, 255); cc.Parent = Lighting
    local dof = Instance.new("DepthOfFieldEffect"); dof.FarIntensity = 0.15; dof.FocusDistance = 60; dof.InFocusRadius = 90; dof.NearIntensity = 0.2; dof.Parent = Lighting
end

local World = Instance.new("Folder"); World.Name = "World"; World.Parent = workspace
local FXFolder = Instance.new("Folder"); FXFolder.Name = "ServerFX"; FXFolder.Parent = workspace

local function mkPart(props, parent)
    local p = Instance.new("Part")
    p.Anchored = true; p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
    p.Material = Enum.Material.SmoothPlastic
    for k, v in pairs(props) do p[k] = v end
    p.Parent = parent or World
    return p
end

local M = Config.Map
mkPart({ Size = Vector3.new(M.Size, 2, M.Size), CFrame = CFrame.new(0, -1, 0), Color = Color3.fromRGB(15, 13, 22), Material = Enum.Material.Slate }, World)
for x = -7, 7 do for z = -7, 7 do
    if (x % 2 == 0) or (z % 2 == 0) then
        mkPart({ Size = Vector3.new(0.6, 0.1, M.Size / 15 * 0.86), CFrame = CFrame.new(x * 60, 0.03, z * 60),
            Color = Config.Colors.AccentAlt, Material = Enum.Material.Neon, Transparency = 0.86, CanCollide = false }, World)
    end
end end

mkPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, M.ArenaRadius * 2, M.ArenaRadius * 2),
    CFrame = CFrame.new(0, 0.06, 0) * CFrame.Angles(0, 0, math.rad(90)),
    Color = Config.Colors.Accent, Material = Enum.Material.Neon, Transparency = 0.55, CanCollide = false }, World)
for i = 1, 14 do
    local a = (i / 14) * math.pi * 2
    mkPart({ Size = Vector3.new(2, 10, 2), CFrame = CFrame.new(math.cos(a) * M.ArenaRadius, 5, math.sin(a) * M.ArenaRadius),
        Color = Color3.fromRGB(22, 19, 34), Material = Enum.Material.Metal }, World)
    local cap = mkPart({ Size = Vector3.new(2.4, 1, 2.4), CFrame = CFrame.new(math.cos(a) * M.ArenaRadius, 10.5, math.sin(a) * M.ArenaRadius),
        Color = Config.Colors.AccentAlt, Material = Enum.Material.Neon, Transparency = 0.2, CanCollide = false }, World)
    if i % 2 == 0 then
        local pe = Instance.new("ParticleEmitter")
        pe.Rate = 3; pe.Lifetime = NumberRange.new(1, 2); pe.Speed = NumberRange.new(1, 3)
        pe.Color = ColorSequence.new(Config.Colors.AccentAlt); pe.Size = NumberSequence.new(0.5)
        pe.Transparency = NumberSequence.new(0.4, 1); pe.Parent = cap
    end
end

local PLOT_SLOTS = { -22, -13, -4, 4, 13, 22 }
local PlotByPlayer = {}

local function padMarker(cf, text, color)
    mkPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 8, 8),
        CFrame = cf * CFrame.Angles(0, 0, math.rad(90)), Color = color, Material = Enum.Material.Neon, Transparency = 0.15, CanCollide = false }, World)
    local p = mkPart({ Size = Vector3.new(0.4, 0.4, 0.4), Transparency = 1, CanCollide = false, CFrame = cf * CFrame.new(0, 5, 0) }, World)
    local bb = Instance.new("BillboardGui"); bb.Size = UDim2.fromScale(14, 3.2); bb.StudsOffset = Vector3.new(0, 2, 0); bb.MaxDistance = 120; bb.Parent = p
    local tl = Instance.new("TextLabel"); tl.BackgroundTransparency = 1; tl.Size = UDim2.fromScale(1, 1)
    tl.Font = Enum.Font.GothamBlack; tl.TextScaled = true; tl.Text = text; tl.TextColor3 = color; tl.TextStrokeTransparency = 0.4
    tl.Parent = bb
    return p
end

local ShopPad = padMarker(CFrame.new(0, 0.3, -120), "ARMORY · press E", Config.Colors.Accent)
local GaragePad = padMarker(CFrame.new(120, 0.3, 60), "GARAGE · press E", Config.Colors.Gold)
do
    local pr = Instance.new("ProximityPrompt")
    pr.ActionText = "OPEN ARMORY"; pr.ObjectText = "Armory"; pr.HoldDuration = 0.15; pr.MaxActivationDistance = 12
    pr.RequiresLineOfSight = false; pr.Parent = ShopPad
    pr.Triggered:Connect(function(plr) RE:FireClient(plr, "OpenShop") end)
    local pr2 = Instance.new("ProximityPrompt")
    pr2.ActionText = "OPEN GARAGE"; pr2.ObjectText = "Garage"; pr2.HoldDuration = 0.15; pr2.MaxActivationDistance = 12
    pr2.RequiresLineOfSight = false; pr2.Parent = GaragePad
    pr2.Triggered:Connect(function(plr) RE:FireClient(plr, "OpenShop", "Vehicles") end)
end

for i = 1, M.SpawnCount do
    local a = (i / M.SpawnCount) * math.pi * 2 + 0.4
    local sp = Instance.new("SpawnLocation")
    sp.Size = Vector3.new(12, 1, 12)
    sp.CFrame = CFrame.new(math.cos(a) * 130, 0.55, math.sin(a) * 130)
    sp.Anchored = true; sp.Neutral = true; sp.Duration = Config.RespawnForceField
    sp.Color = Color3.fromRGB(24, 20, 38); sp.Material = Enum.Material.Marble
    sp.TopSurface = Enum.SurfaceType.Smooth
    mkPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 14, 14),
        CFrame = sp.CFrame * CFrame.new(0, -0.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
        Color = Config.Colors.AccentAlt, Material = Enum.Material.Neon, Transparency = 0.3, CanCollide = false }, World)
    sp.Parent = World
end

for i = 1, M.Mountains do
    local a = math.random() * math.pi * 2
    local r = 330 + math.random() * 100
    local h = 30 + math.random() * 70
    mkPart({ Size = Vector3.new(14 + math.random() * 22, h, 14 + math.random() * 22),
        CFrame = CFrame.new(math.cos(a) * r, h / 2 - 2, math.sin(a) * r) * CFrame.Angles(0, math.random() * 6.28, (math.random() - 0.5) * 0.14),
        Color = Color3.fromRGB(20, 17, 30), Material = Enum.Material.Basalt }, World)
end
for i = 1, M.Trees do
    local a = math.random() * math.pi * 2
    local r = 100 + math.random() * 240
    local x, z = math.cos(a) * r, math.sin(a) * r
    if math.abs(x) > 40 or math.abs(z) > 40 then
        local th = 7 + math.random() * 6
        mkPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(th, 1.6, 1.6),
            CFrame = CFrame.new(x, th / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
            Color = Color3.fromRGB(44, 34, 52), Material = Enum.Material.Wood }, World)
        local leaf = mkPart({ Size = Vector3.new(6, 6, 6), CFrame = CFrame.new(x, th + 2.4, z),
            Color = Color3.fromRGB(140, 90, 230), Material = Enum.Material.ForceField, Shape = Enum.PartType.Ball, CanCollide = false }, World)
        if math.random() < 0.3 then
            local pe = Instance.new("ParticleEmitter")
            pe.Rate = 2; pe.Lifetime = NumberRange.new(1.5, 3); pe.Speed = NumberRange.new(0.5, 1.5)
            pe.Color = ColorSequence.new(Config.Colors.AccentAlt); pe.Size = NumberSequence.new(0.35)
            pe.Transparency = NumberSequence.new(0.3, 1); pe.Parent = leaf
        end
    end
end
for i = 1, 24 do
    local a = (i / 24) * math.pi * 2
    mkPart({ Size = Vector3.new(130, 120, 3),
        CFrame = CFrame.new(math.cos(a) * 440, 60, math.sin(a) * 440) * CFrame.Angles(0, -a + math.pi / 2, 0), Transparency = 1 }, World)
end

do
    local p = mkPart({ Size = Vector3.new(1, 1, 1), Transparency = 1, CanCollide = false, CFrame = CFrame.new(0, 20, 0) }, World)
    local bb = Instance.new("BillboardGui"); bb.Size = UDim2.fromScale(70, 15); bb.Parent = p
    local tl = Instance.new("TextLabel"); tl.BackgroundTransparency = 1; tl.Size = UDim2.fromScale(1, 0.6)
    tl.Font = Enum.Font.GothamBlack; tl.TextScaled = true; tl.Text = Config.GameName; tl.TextColor3 = Config.Colors.Text
    tl.Parent = bb
    local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(Config.Colors.Accent, Config.Colors.AccentAlt); g.Parent = tl
    local sub = Instance.new("TextLabel"); sub.BackgroundTransparency = 1; sub.Size = UDim2.fromScale(1, 0.26); sub.Position = UDim2.fromScale(0, 0.62)
    sub.Font = Enum.Font.GothamBold; sub.TextScaled = true; sub.Text = Config.Tagline; sub.TextColor3 = Config.Colors.Dim
    sub.Parent = bb
end

-- ── global leaderboards ───────────────────────────────────────────
local function buildBoard(pos, title, color)
    local board = mkPart({ Size = Vector3.new(14, 18, 1), CFrame = CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0)),
        Color = Color3.fromRGB(19, 16, 30), Material = Enum.Material.Marble, CanCollide = false }, World)
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.fromScale(26, 30); bb.StudsOffset = Vector3.new(0, 10, 0)
    bb.MaxDistance = 140; bb.Parent = board
    local frame = Instance.new("Frame")
    frame.BackgroundColor3 = Config.Colors.Panel; frame.BackgroundTransparency = 0.15
    frame.Size = UDim2.fromScale(1, 1); frame.Parent = bb
    local fcorner = Instance.new("UICorner"); fcorner.CornerRadius = UDim.new(0, 10); fcorner.Parent = frame
    local fstroke = Instance.new("UIStroke"); fstroke.Color = color; fstroke.Thickness = 2; fstroke.Transparency = 0.3; fstroke.Parent = frame
    local titleL = Instance.new("TextLabel")
    titleL.BackgroundTransparency = 1; titleL.Size = UDim2.fromScale(1, 0.14)
    titleL.Font = Enum.Font.GothamBlack; titleL.TextScaled = true
    titleL.Text = title; titleL.TextColor3 = color
    titleL.Parent = frame
    local holder = Instance.new("Frame")
    holder.BackgroundTransparency = 1; holder.Size = UDim2.fromScale(1, 0.84)
    holder.Position = UDim2.fromScale(0, 0.15); holder.Parent = frame
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 2); layout.HorizontalAlignment = Enum.HorizontalAlignment.Center; layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = holder
    return holder
end

local cashBoard = buildBoard(Vector3.new(30, 8, -38), "💰 RICHEST", Config.Colors.Gold)
local killBoard = buildBoard(Vector3.new(-30, 8, -38), "⚔ TOP SLAYERS", Config.Colors.Danger)

local function renderBoard(holder, ordered, fmt, topN)
    for _, ch in ipairs(holder:GetChildren()) do
        if ch:IsA("TextLabel") then ch:Destroy() end
    end
    local entries = {}
    for _ = 1, 3 do
        local ok, pages = pcall(function()
            return ordered:GetSortedAsync(false, topN)
        end)
        if ok and pages then
            entries = pages:GetCurrentPage()
            break
        end
        task.wait(2)
    end
    if #entries == 0 then
        local row = Instance.new("TextLabel")
        row.BackgroundTransparency = 1; row.Size = UDim2.fromScale(1, 0.09)
        row.Font = Enum.Font.GothamBold; row.TextScaled = true
        row.TextColor3 = Config.Colors.Dim; row.Text = "no entries yet"
        row.LayoutOrder = 0; row.Parent = holder
        return
    end
    for i, e in ipairs(entries) do
        local name = e.key:match("^%d+:(.+)$") or e.key
        local row = Instance.new("TextLabel")
        row.BackgroundTransparency = 1; row.Size = UDim2.fromScale(1, 0.085)
        row.Font = Enum.Font.GothamBold; row.TextScaled = true
        row.TextColor3 = i == 1 and Config.Colors.Gold or Config.Colors.Text
        row.TextStrokeTransparency = 0.5
        row.Text = string.format("#%d %s — %s", i, name, fmt(e.value))
        row.LayoutOrder = i; row.Parent = holder
    end
end

task.spawn(function()
    while true do
        task.wait(Config.Leaderboard.UpdateEvery)
        for _, plr in ipairs(Players:GetPlayers()) do
            local s = get(plr)
            if s and s.LoadedOK then
                local key = plr.UserId .. ":" .. plr.Name
                pcall(function() LBCash:SetAsync(key, math.floor(s.Cash)) end)
                pcall(function() LBKills:SetAsync(key, s.Kills) end)
            end
        end
        renderBoard(cashBoard, LBCash, function(v) return Util.cash(v) end, Config.Leaderboard.Top)
        renderBoard(killBoard, LBKills, function(v) return tostring(v) .. " kills" end, Config.Leaderboard.Top)
    end
end)

-- ── combat state ──────────────────────────────────────────────────
local St = {}
local function stateFor(plr)
    local s = St[plr]
    if not s then
        s = { Ult = 0, Dash = maxDash(plr), DashT = 0, Blocking = false, BlockStart = 0, BlockEnd = 0,
            ImmuneUntil = 0, StunnedUntil = 0, BuffUntil = 0, BuffMult = 1, M1T = 0, Combo = 0,
            Cd = {}, LastDir = Vector3.zAxis, Streak = 0, Sprinting = false }
        St[plr] = s
    end
    return s
end
local function charOf(plr)
    local c = plr.Character
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    local hrp = c and c:FindFirstChild("HumanoidRootPart")
    if hum and hum.Health > 0 and hrp then return c, hum, hrp end
end
local function aliveCharsNear(cf, size, ignore)
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore or {}
    local parts = workspace:GetPartBoundsInBox(cf, size, params)
    local seen, out = {}, {}
    for _, part in ipairs(parts) do
        local m = part:FindFirstAncestorOfClass("Model")
        local hum = m and m:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 and not seen[m] then
            local root = m:FindFirstChild("HumanoidRootPart")
            if root then -- nil-HRP filtered at source
                seen[m] = true
                table.insert(out, { Model = m, Hum = hum, Root = root })
            end
        end
    end
    return out
end

local lastImpact = 0
local function impactFrame(attacker, victimChar)
    local now = os.clock()
    if now - lastImpact < Config.Impact.GlobalGap then return end
    lastImpact = now
    local vhum = victimChar and victimChar:FindFirstChildOfClass("Humanoid")
    local vhrp = victimChar and victimChar:FindFirstChild("HumanoidRootPart")
    if vhrp and vhum and not vhum.SeatPart then
        vhrp.Anchored = true
        task.delay(Config.Impact.Freeze, function() if vhrp.Parent then vhrp.Anchored = false end end)
    end
    fxAll({ Type = "impact", Pos = vhrp and vhrp.Position or nil })
end

local onKill

local function dealDamage(attacker, victimModel, baseDmg, opts)
    opts = opts or {}
    local victim = Players:GetPlayerFromCharacter(victimModel)
    if not victim or victim == attacker then return end
    local vhum = victimModel:FindFirstChildOfClass("Humanoid")
    local vhrp = victimModel:FindFirstChild("HumanoidRootPart")
    if not vhum or not vhrp or vhum.Health <= 0 then return end
    local now = os.clock()
    local vs = stateFor(victim)
    if now < vs.ImmuneUntil then
        RE:FireClient(attacker, "DamageNum", { Pos = vhrp.Position, Amount = "DODGE", Color = Config.Colors.AccentAlt })
        return
    end
    local dmg = baseDmg * (stateFor(attacker).BuffUntil > now and stateFor(attacker).BuffMult or 1)
    if vs.Blocking and now < vs.BlockEnd then
        if now - vs.BlockStart <= Config.Parry.Window then
            vs.Blocking = false
            RE:FireClient(victim, "BlockState", false)
            local as = stateFor(attacker)
            as.StunnedUntil = now + Config.Parry.Stun
            local ahrp = select(3, charOf(attacker))
            if ahrp then
                local away = safeDir(vhrp.Position, ahrp.Position)
                ahrp.AssemblyLinearVelocity = away * 60 + Vector3.new(0, 20, 0)
            end
            fxAll({ Type = "parry", Pos = vhrp.Position })
            impactFrame(attacker, victimModel)
            RE:FireClient(victim, "DamageNum", { Pos = vhrp.Position, Amount = "PARRY!", Color = Config.Colors.Gold })
            return
        end
        dmg = dmg * Config.Parry.Reduce
        vs.Blocking = false
        RE:FireClient(victim, "BlockState", false)
    end
    if opts.Execute and vhum.Health / vhum.MaxHealth < 0.4 then dmg = dmg * opts.Execute end
    vhum:TakeDamage(dmg)
    local as = stateFor(attacker)
    as.Ult = math.min(Config.UltMax, as.Ult + dmg * 0.08)
    vs.Ult = math.min(Config.UltMax, vs.Ult + dmg * 0.05)
    local aSess = get(attacker)
    local healFrac = 0
    if aSess and aSess.Rebirths >= 3 then healFrac += 0.08 end
    if opts.Heal then healFrac += opts.Heal end
    healFrac = math.min(healFrac, 0.6)
    if healFrac > 0 then
        local ahum = select(2, charOf(attacker))
        if ahum then ahum.Health = math.min(ahum.MaxHealth, ahum.Health + dmg * healFrac) end
    end
    if opts.Knock then
        local ahrp = select(3, charOf(attacker))
        local dir = opts.Dir or (ahrp and safeDir(ahrp.Position, vhrp.Position) or Vector3.new(0, 1, 0))
        vhrp.AssemblyLinearVelocity = dir * opts.Knock + Vector3.new(0, math.min(40, opts.Knock * 0.5), 0)
        if opts.Knock >= 45 then
            vhum.PlatformStand = true
            task.delay(1.1, function() if vhum.Parent then vhum.PlatformStand = false end end)
        end
    end
    if opts.Stun then vs.StunnedUntil = now + opts.Stun end
    RE:FireClient(attacker, "Hit")
    RE:FireClient(attacker, "DamageNum", { Pos = vhrp.Position, Amount = math.floor(dmg), Crit = opts.Crit })
    for _, p in ipairs(Players:GetPlayers()) do
        local ch = charOf(p)
        if ch and (ch:GetPivot().Position - vhrp.Position).Magnitude < 130 and p ~= attacker then
            RE:FireClient(p, "DamageNum", { Pos = vhrp.Position, Amount = math.floor(dmg), Color = Config.Colors.Dim })
        end
    end
    if opts.Impact then impactFrame(attacker, victimModel) end
    if vhum.Health <= 0 then onKill(attacker, victimModel) end
end

onKill = function(attacker, victimModel)
    local victim = Players:GetPlayerFromCharacter(victimModel)
    if not attacker or not victim or attacker == victim then return end
    local s = get(attacker)
    if not s then return end
    awardBadge(attacker, "FirstBlood")
    local as = stateFor(attacker)
    as.Streak += 1
    s.Kills += 1; s.Dirty = true
    local vs = get(victim); if vs then vs.Deaths += 1; vs.Dirty = true end
    local vst = St[victim]
    if vst then
        local lost = vst.Streak; vst.Streak = 0
        if lost >= 5 then notify(attacker, "Bounty collected: " .. victim.Name .. " was on a " .. lost .. " streak!", Config.Colors.Gold) end
    end
    local reward = Config.KillReward.Base + math.min(as.Streak, Config.KillReward.StreakCap) * Config.KillReward.PerStreak
    local gained = addCash(attacker, reward)
    local ls = attacker:FindFirstChild("leaderstats")
    if ls then ls.Kills.Value = s.Kills; ls.Streak.Value = as.Streak end
    impactFrame(attacker, victimModel)
    if as.Streak >= 5 then fxAll({ Type = "aura", Char = attacker.Name, Tier = math.min(3, math.floor(as.Streak / 5)) }) end
    RE:FireClient(attacker, "KillPop", { Name = victim.Name, Cash = gained, Streak = as.Streak })
    for _, p in ipairs(Players:GetPlayers()) do
        RE:FireClient(p, "KillFeed", { Killer = attacker.Name, Victim = victim.Name, Streak = as.Streak })
    end
    if as.Streak == 5 or as.Streak == 10 or as.Streak == 15 or as.Streak == 20 then
        for _, p in ipairs(Players:GetPlayers()) do
            notify(p, attacker.Name .. " is on a " .. as.Streak .. " KILL STREAK!", Config.Colors.Danger)
        end
    end
end

-- ── skill executors ───────────────────────────────────────────────
local Executors = {}

Executors.aoe = function(plr, w, sk, aim)
    local c, hum, hrp = charOf(plr); if not c then return end
    local hits = aliveCharsNear(CFrame.new(hrp.Position), Vector3.new(sk.Radius * 2, 12, sk.Radius * 2), { c })
    for _, h in ipairs(hits) do
        dealDamage(plr, h.Model, sk.Dmg, { Knock = sk.Knock, Stun = sk.Stun, Heal = sk.Heal, Dir = safeDir(hrp.Position, h.Root.Position), Impact = sk.Dmg >= Config.Impact.SkillMinDmg })
    end
    fxAll({ Type = "ring", Pos = hrp.Position, Radius = sk.Radius, Color = w.Color })
end

Executors.line = function(plr, w, sk, aim)
    local c, hum, hrp = charOf(plr); if not c then return end
    local dir = Vector3.new(aim.X, 0, aim.Z)
    if dir.Magnitude < 0.05 then dir = hrp.CFrame.LookVector end
    dir = dir.Unit
    hrp.AssemblyLinearVelocity = dir * (sk.Dmg > 0 and 55 or 85) + Vector3.new(0, 8, 0)
    task.delay(0.12, function()
        local cc = charOf(plr); if not cc then return end
        local mid = cc:GetPivot().Position + dir * (sk.Range * 0.5)
        local hits = aliveCharsNear(CFrame.lookAt(mid, mid + dir), Vector3.new(sk.Range, 8, sk.Radius or 6), { cc })
        for _, h in ipairs(hits) do
            dealDamage(plr, h.Model, sk.Dmg, { Knock = sk.Knock, Dir = dir, Execute = sk.Execute, Impact = sk.Dmg >= Config.Impact.SkillMinDmg })
        end
        fxAll({ Type = "slash", From = cc:GetPivot().Position, To = cc:GetPivot().Position + dir * sk.Range, Color = w.Color, Heavy = true })
    end)
    if sk.Immune then St[plr].ImmuneUntil = os.clock() + sk.Immune end
end

Executors.shot = function(plr, w, sk, aim)
    local c, hum, hrp = charOf(plr); if not c then return end
    for i = 1, (sk.Rays or 1) do
        local d = aim
        if sk.Spread and sk.Rays > 1 then
            local axis = aim:Cross(Vector3.yAxis)
            axis = axis.Magnitude > 0.01 and axis.Unit or Vector3.xAxis
            d = CFrame.fromAxisAngle(axis, math.rad((i - (sk.Rays + 1) / 2) * sk.Spread)) * aim
        end
        local origin = hrp.Position + d * 2
        local ignoreList = { c }
        for _ = 1, (sk.Pierce or 1) do
            local rp = RaycastParams.new()
            rp.FilterType = Enum.RaycastFilterType.Exclude
            rp.FilterDescendantsInstances = ignoreList
            local res = workspace:Raycast(origin, d * (sk.Range or 200), rp)
            if not res then break end
            local m = res.Instance:FindFirstAncestorOfClass("Model")
            local hum2 = m and m:FindFirstChildOfClass("Humanoid")
            if hum2 then
                dealDamage(plr, m, sk.Dmg, { Dir = d, Knock = 8 })
                table.insert(ignoreList, m)
                origin = res.Position + d * 0.5
            else
                fxAll({ Type = "tracer", From = hrp.Position + d * 2, To = res.Position, Color = w.Color })
                break
            end
        end
    end
end

Executors.lob = function(plr, w, sk, aim)
    local c, hum, hrp = charOf(plr); if not c then return end
    local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = { c }
    local res = workspace:Raycast(hrp.Position, aim * sk.Range, rp)
    local pos = res and res.Position or (hrp.Position + aim * sk.Range)
    local hits = aliveCharsNear(CFrame.new(pos), Vector3.new(sk.Radius * 2, 10, sk.Radius * 2), { c })
    for _, h in ipairs(hits) do
        dealDamage(plr, h.Model, sk.Dmg, { Knock = sk.Knock, Dir = safeDir(pos, h.Root.Position), Impact = sk.Dmg >= Config.Impact.SkillMinDmg })
    end
    fxAll({ Type = "blast", Pos = pos, Radius = sk.Radius, Color = w.Color })
end

Executors.well = function(plr, w, sk, aim)
    local c, hum, hrp = charOf(plr); if not c then return end
    local pos = hrp.Position + Vector3.new(aim.X, 0, aim.Z).Unit * math.min(20, sk.Radius)
    fxAll({ Type = "well", Pos = pos, Radius = sk.Radius, Ticks = sk.Ticks, Color = w.Color })
    task.spawn(function()
        for _ = 1, sk.Ticks do
            task.wait(sk.TickTime)
            local cc = charOf(plr) -- re-fetched per tick, caster always excluded
            local hits = aliveCharsNear(CFrame.new(pos), Vector3.new(sk.Radius * 2, 12, sk.Radius * 2), cc and { cc } or {})
            for _, h in ipairs(hits) do
                local toC = (pos - h.Root.Position) * Vector3.new(1, 0, 1)
                if toC.Magnitude > 2 then h.Root.AssemblyLinearVelocity = toC.Unit * sk.Pull end
                dealDamage(plr, h.Model, sk.Dmg, {})
            end
        end
    end)
end

Executors.buff = function(plr, w, sk, aim)
    local s = stateFor(plr)
    s.BuffUntil = os.clock() + (sk.BuffTime or 5)
    s.BuffMult = sk.BuffMult or 1.3
    if sk.Immune then s.ImmuneUntil = os.clock() + sk.Immune end
    local c, hum = charOf(plr)
    if hum and sk.Heal then hum.Health = math.min(hum.MaxHealth, hum.Health + sk.Heal) end
    RE:FireClient(plr, "Buff", { Time = sk.BuffTime or 5, Name = sk.Name })
end

Executors.orbit = function(plr, w, sk, aim)
    local c = charOf(plr); if not c then return end
    fxAll({ Type = "orbit", Char = plr.Name, Radius = sk.Radius, Ticks = sk.Ticks, Color = w.Color })
    task.spawn(function()
        for _ = 1, sk.Ticks do
            task.wait(sk.TickTime)
            local cc = charOf(plr); if not cc then return end
            local hits = aliveCharsNear(CFrame.new(cc:GetPivot().Position), Vector3.new(sk.Radius * 2, 10, sk.Radius * 2), { cc })
            for _, h in ipairs(hits) do dealDamage(plr, h.Model, sk.Dmg, {}) end
        end
    end)
end

Executors.rain = function(plr, w, sk, aim)
    local c, hum, hrp = charOf(plr); if not c then return end
    local center = hrp.Position
    task.spawn(function()
        for _ = 1, sk.Ticks do
            task.wait(sk.TickTime)
            local cc = charOf(plr) -- re-fetched per tick, caster always excluded
            local off = Vector3.new((math.random() - 0.5) * sk.Radius * 2, 0, (math.random() - 0.5) * sk.Radius * 2)
            local pos = center + off
            local hits = aliveCharsNear(CFrame.new(pos), Vector3.new(10, 10, 10), cc and { cc } or {})
            for _, h in ipairs(hits) do
                dealDamage(plr, h.Model, sk.Dmg, { Knock = sk.Knock, Dir = off.Magnitude > 0 and off.Unit or Vector3.zAxis })
            end
            fxAll({ Type = "blast", Pos = pos, Radius = 5, Color = w.Color, Small = true })
        end
        if sk.Final then
            task.wait(0.2)
            local cc2 = charOf(plr)
            local hits = aliveCharsNear(CFrame.new(center), Vector3.new(sk.Radius * 2, 14, sk.Radius * 2), cc2 and { cc2 } or {})
            for _, h in ipairs(hits) do
                dealDamage(plr, h.Model, sk.Final, { Knock = sk.Knock or 40, Impact = true })
            end
            fxAll({ Type = "blast", Pos = center, Radius = sk.Radius, Color = w.Color })
        end
    end)
end

Executors.beam = function(plr, w, sk, aim)
    local c, hum, hrp = charOf(plr); if not c then return end
    local dir = Vector3.new(aim.X, 0, aim.Z)
    if dir.Magnitude < 0.05 then dir = hrp.CFrame.LookVector end
    dir = dir.Unit
    fxAll({ Type = "beam", From = hrp.Position, Dir = dir, Range = sk.Range, Ticks = sk.Ticks, Color = w.Color })
    task.spawn(function()
        for _ = 1, sk.Ticks do
            task.wait(sk.TickTime)
            local cc = charOf(plr); if not cc then return end
            local mid = cc:GetPivot().Position + dir * (sk.Range * 0.5)
            local hits = aliveCharsNear(CFrame.lookAt(mid, mid + dir), Vector3.new(sk.Range, sk.Radius * 2, sk.Radius * 2), { cc })
            for _, h in ipairs(hits) do dealDamage(plr, h.Model, sk.Dmg, { Dir = dir, Knock = 6 }) end
        end
    end)
end

-- ── input router ──────────────────────────────────────────────────
local Ratelimit = {}
local function rateOk(plr, key, minGap)
    local now = os.clock()
    Ratelimit[plr] = Ratelimit[plr] or {}
    if Ratelimit[plr][key] and now - Ratelimit[plr][key] < minGap then return false end
    Ratelimit[plr][key] = now
    return true
end

local function useSkill(plr, skill, isUlt, aim)
    local s = get(plr); if not s then return end
    local w = Config.Weapons[s.Equipped]; if not w then return end
    local c, hum, hrp = charOf(plr); if not c then return end
    local st = stateFor(plr)
    local now = os.clock()
    if now < st.StunnedUntil then return end
    local cdKey = isUlt and "ULT" or (w.Name .. skill.Name)
    if st.Cd[cdKey] and now < st.Cd[cdKey] then return end
    if isUlt then
        if st.Ult < Config.UltMax then return end
        st.Ult = 0
    end
    st.Cd[cdKey] = now + (skill.Cd or 3)
    local ex = Executors[skill.Exec]
    if ex then ex(plr, w, skill, aim) end
    fxAll({ Type = "pose", Char = plr.Name, Anim = isUlt and "cast" or (w.Anim or "slash"), Dur = isUlt and 0.6 or 0.4 })
    if isUlt then
        cineAll({ Kind = "Ult", Who = plr.Name, Name = skill.Name, Color = w.Color })
        fxAll({ Type = "ultburst", Pos = hrp.Position, Color = w.Color })
    end
    RE:FireClient(plr, "SkillUsed", { Key = isUlt and "V" or skill.Key, Cd = skill.Cd or 3 })
    fxAll({ Type = "cast", Pos = hrp.Position, Color = w.Color })
end

RE.OnServerEvent:Connect(function(plr, action, a)
    if action == "Aim" then
        stateFor(plr).LastDir = unit(a)
    elseif action == "M1" then
        if not rateOk(plr, "M1", 0.12) then return end
        local s = get(plr); local w = s and Config.Weapons[s.Equipped]; if not w then return end
        local c, hum, hrp = charOf(plr); if not c then return end
        local st = stateFor(plr)
        local now = os.clock()
        if now < st.StunnedUntil then return end
        if now - st.M1T > 1.2 then st.Combo = 0 end
        st.M1T = now
        st.Combo = (st.Combo % #w.M1.Dmg) + 1
        local dmg = w.M1.Dmg[st.Combo]
        local dir = st.LastDir
        fxAll({ Type = "pose", Char = plr.Name, Anim = w.Anim or "slash", Dur = 0.3 })
        if w.M1.Ranged then
            Executors.shot(plr, w, { Rays = 1, Dmg = dmg, Range = w.M1.Range, Pierce = 1 }, dir)
            fxAll({ Type = "tracer", From = hrp.Position + dir * 2, To = hrp.Position + dir * w.M1.Range, Color = w.Color, Thin = true })
        else
            local front = CFrame.lookAt(hrp.Position + dir * (w.M1.Range * 0.5), hrp.Position + dir * w.M1.Range)
            local hits = aliveCharsNear(front, Vector3.new(w.M1.Range, 8, w.M1.Range * 0.9), { c })
            local knocked = st.Combo == #w.M1.Dmg
            for i, h in ipairs(hits) do
                if i == 1 or knocked then
                    dealDamage(plr, h.Model, dmg, { Knock = knocked and 60 or 10, Dir = dir, Impact = knocked })
                end
            end
            fxAll({ Type = "slash", From = hrp.Position, To = hrp.Position + dir * w.M1.Range, Color = w.Color, Thin = not knocked })
        end
    elseif action == "Skill" then
        local s = get(plr); local w = s and Config.Weapons[s.Equipped]; if not w then return end
        local sk = w.Skills and w.Skills[tonumber(a)]
        if sk then useSkill(plr, sk, false, stateFor(plr).LastDir) end
    elseif action == "Ult" then
        local s = get(plr); local w = s and Config.Weapons[s.Equipped]
        if w and w.Ult then useSkill(plr, w.Ult, true, stateFor(plr).LastDir) end
    elseif action == "Dash" then
        if not rateOk(plr, "Dash", 0.3) then return end
        local st = stateFor(plr)
        local now = os.clock()
        if now < st.StunnedUntil then return end
        if st.Dash <= 0 then return end
        st.Dash -= 1
        st.DashT = now
        st.ImmuneUntil = now + Config.Dash.Immune
        local c, hum, hrp = charOf(plr)
        if hrp then
            local d = unit(a)
            if d.Magnitude < 0.05 then d = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z).Unit end
            hrp.AssemblyLinearVelocity = d * Config.Dash.Speed + Vector3.new(0, 6, 0)
        end
        fxAll({ Type = "pose", Char = plr.Name, Anim = "dash", Dur = 0.35 })
        RE:FireClient(plr, "Dashed")
    elseif action == "Block" then
        local st = stateFor(plr)
        local now = os.clock()
        if a == true then
            if not st.Blocking and now >= st.StunnedUntil then
                st.Blocking = true
                st.BlockStart = now
                st.BlockEnd = now + Config.Parry.MaxHold
                fxAll({ Type = "pose", Char = plr.Name, Anim = "block", Hold = true })
            end
        else
            st.Blocking = false
            fxAll({ Type = "poseend", Char = plr.Name })
        end
        RE:FireClient(plr, "BlockState", st.Blocking) -- refused blocks un-light the toggle
    elseif action == "Sprint" then
        stateFor(plr).Sprinting = (a == true)
    elseif action == "Equip" then
        local s = get(plr)
        if s and s.Weapons[a] and Config.Weapons[a] then
            s.Equipped = a; s.Dirty = true
            fxAll({ Type = "wmodel", Char = plr.Name, W = a })
        end
    end
end)

task.spawn(function() -- dash regen + block expiry + walkspeed pin (complete loop)
    while true do
        task.wait(0.5)
        local now = os.clock()
        for _, plr in ipairs(Players:GetPlayers()) do
            local st = St[plr]
            if st then
                local cap = maxDash(plr)
                if st.Dash < cap and now - st.DashT > dashRegen(plr) then
                    st.Dash += 1
                    st.DashT = now
                    RE:FireClient(plr, "DashCharge", st.Dash)
                end
                if st.Blocking and now > st.BlockEnd then
                    st.Blocking = false
                    fxAll({ Type = "poseend", Char = plr.Name })
                    RE:FireClient(plr, "BlockState", false)
                end
                local c, hum = charOf(plr)
                if hum then
                    local base = Pass_has(plr, "VIP") and Config.Sprint.VipSpeed or (Config.Sprint.Speed - 8)
                    local target = base + (st.Sprinting and 8 or 0)
                    if hum.WalkSpeed ~= target then hum.WalkSpeed = target end
                end
            end
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(1)
        for _, plr in ipairs(Players:GetPlayers()) do
            local st = St[plr]
            if st then
                RE:FireClient(plr, "Combat", { Ult = math.floor(st.Ult), Dash = st.Dash, DashMax = maxDash(plr) })
            end
        end
    end
end)

-- ── plots / extractors ────────────────────────────────────────────
local function buildPlot(index, originCF)
    local plot = { Index = index, Origin = originCF, Owner = nil, Droppers = {}, ClaimGen = 0, SlotIdx = 0 }
    local model = Instance.new("Model"); model.Name = "Plot" .. index; model.Parent = World
    plot.Model = model
    plot.BaseFolder = Instance.new("Folder"); plot.BaseFolder.Name = "Base"; plot.BaseFolder.Parent = model
    plot.BuildFolder = Instance.new("Folder"); plot.BuildFolder.Name = "Build"; plot.BuildFolder.Parent = model

    mkPart({ Size = Vector3.new(70, 1, 70), CFrame = originCF * CFrame.new(0, 0.5, 0), Color = Color3.fromRGB(19, 16, 30), Material = Enum.Material.Marble }, plot.BaseFolder)
    for _, c in ipairs({ { Vector3.new(70, 0.3, 0.7), CFrame.new(0, 1.1, -35) }, { Vector3.new(0.7, 0.3, 70), CFrame.new(-35, 1.1, 0) },
        { Vector3.new(0.7, 0.3, 70), CFrame.new(35, 1.1, 0) }, { Vector3.new(70, 0.3, 0.7), CFrame.new(0, 1.1, 35) } }) do
        mkPart({ Size = c[1], CFrame = originCF * c[2], Color = Config.Colors.AccentAlt, Material = Enum.Material.Neon, Transparency = 0.4 }, plot.BaseFolder)
    end
    local claim = mkPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 9, 9),
        CFrame = originCF * CFrame.new(0, 0.9, 28) * CFrame.Angles(0, 0, math.rad(90)),
        Color = Config.Colors.Accent, Material = Enum.Material.Neon, Transparency = 0.1 }, plot.BaseFolder)
    plot.ClaimPad = claim
    local pr = Instance.new("ProximityPrompt")
    pr.ActionText = "CLAIM PLOT"; pr.ObjectText = "Plot " .. index; pr.HoldDuration = 0.3; pr.MaxActivationDistance = 12
    pr.RequiresLineOfSight = false; pr.Parent = claim
    plot.ClaimPrompt = pr
    pr.Triggered:Connect(function(plr)
        if plot.Owner or PlotByPlayer[plr] then return end
        local s = get(plr); if not s then return end
        plot.Owner = plr
        PlotByPlayer[plr] = plot
        claim.Color = Color3.fromRGB(90, 84, 110)
        pr.Enabled = false
        for id in pairs(s.Droppers) do plot:placeDropper(id) end -- keyed table: pairs
        notify(plr, "Plot " .. index .. " claimed — extractors online.", Config.Colors.Accent)
        RE:FireClient(plr, "Claimed", index)
        local ch = plr.Character
        if ch then ch:PivotTo(originCF * CFrame.new(0, 5, 34) * CFrame.Angles(0, math.pi, 0)) end
    end)

    function plot:placeDropper(id)
        local def
        for _, d in ipairs(Config.Droppers) do if d.Id == id then def = d break end end
        if not def or self.Droppers[id] then return end
        local cap = (Pass_has(self.Owner, "ExtraSlots") and Config.DropperSlotsVIP or Config.DropperSlots)
        if self.SlotIdx >= cap then return end -- explicit counter, not #
        self.SlotIdx += 1
        local slot = PLOT_SLOTS[self.SlotIdx] or 0
        local dmodel = Instance.new("Model"); dmodel.Name = "Dropper_" .. id
        mkPart({ Size = Vector3.new(4, 2, 4), CFrame = self.Origin * CFrame.new(slot, 2, -20), Color = Color3.fromRGB(26, 22, 40), Material = Enum.Material.Metal }, dmodel)
        local head = mkPart({ Size = Vector3.new(3, 3, 3), CFrame = self.Origin * CFrame.new(slot, 6, -20), Color = def.Color, Material = Enum.Material.Neon }, dmodel)
        local portal = mkPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 4.4, 4.4),
            CFrame = self.Origin * CFrame.new(slot, 1.4, -20) * CFrame.Angles(0, 0, math.rad(90)),
            Color = def.Color, Material = Enum.Material.Neon, Transparency = 0.25, CanCollide = false }, dmodel)
        dmodel.Parent = self.BuildFolder
        local entry = { Head = head, Portal = portal, Def = def }
        self.Droppers[id] = entry
        portal.Touched:Connect(function(hit)
            if hit:GetAttribute("Value") and self.Owner then
                hit:Destroy()
                local v = addCash(self.Owner, hit:GetAttribute("Value"))
                RE:FireClient(self.Owner, "CashPop", { Pos = portal.Position, Amount = v, Color = def.Color })
            end
        end)
        local gen = self.ClaimGen
        task.spawn(function()
            while self.Owner and self.Droppers[id] == entry and self.ClaimGen == gen do
                task.wait(def.Interval)
                if not self.Owner or self.ClaimGen ~= gen then break end
                if Pass_has(self.Owner, "AutoCollect") then
                    local v = addCash(self.Owner, def.Value)
                    RE:FireClient(self.Owner, "CashPop", { Pos = head.Position, Amount = v, Color = def.Color, Small = true })
                else
                    local cube = Instance.new("Part")
                    cube.Size = Vector3.new(1.2, 1.2, 1.2)
                    cube.Material = Enum.Material.Neon
                    cube.Color = def.Color
                    cube.CFrame = head.CFrame - Vector3.new(0, 2.2, 0)
                    cube:SetAttribute("Value", def.Value)
                    cube.CanCollide = false
                    cube.Parent = self.BuildFolder
                    Debris:AddItem(cube, 8)
                end
            end
        end)
    end

    function plot:clearBuilds()
        self.ClaimGen += 1
        self.BuildFolder:ClearAllChildren()
        self.Droppers = {}
        self.SlotIdx = 0
    end
    return plot
end

for i = 1, Config.Map.PlotCount do
    local a = ((i - 1) / Config.Map.PlotCount) * math.pi * 2
    local pos = Vector3.new(math.sin(a), 0, math.cos(a)) * Config.Map.PlotRadius
    buildPlot(i, CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0)))
end

-- ── vehicles ──────────────────────────────────────────────────────
local ActiveVehicles = {}
local function destroyVehicle(plr)
    local v = ActiveVehicles[plr]
    if v then
        if v.Con then v.Con:Disconnect() end
        if v.Model then v.Model:Destroy() end
        ActiveVehicles[plr] = nil
    end
end

local function spawnVehicle(plr, id)
    local def = Config.Vehicles[id]
    local s = get(plr)
    if not def or not s or s.Vehicles[id] ~= true then return end
    destroyVehicle(plr)
    local model = Instance.new("Model"); model.Name = "Vehicle_" .. id
    local chassis = Instance.new("Part")
    chassis.Size = id == "warrig" and Vector3.new(12, 3, 20) or Vector3.new(5, 1.6, 10)
    chassis.Color = Color3.fromRGB(24, 20, 36); chassis.Material = Enum.Material.Metal
    chassis.CustomPhysicalProperties = PhysicalProperties.new(0.4, 0.3, 0.5)
    chassis.Name = "Chassis"
    chassis.Parent = model
    local trim = Instance.new("Part")
    trim.Size = Vector3.new(chassis.Size.X * 0.7, 0.3, chassis.Size.Z * 0.9)
    trim.Color = def.Color; trim.Material = Enum.Material.Neon; trim.CanCollide = false
    trim.CFrame = chassis.CFrame * CFrame.new(0, chassis.Size.Y / 2, 0)
    trim.Parent = model
    local weld = Instance.new("WeldConstraint"); weld.Part0 = chassis; weld.Part1 = trim; weld.Parent = chassis
    local att = Instance.new("Attachment"); att.Position = Vector3.new(0, -1, 0); att.Parent = chassis
    local lv = Instance.new("LinearVelocity")
    lv.Attachment0 = att; lv.RelativeTo = Enum.ActuatorRelativeTo.World
    lv.MaxForce = 6e5; lv.VectorVelocity = Vector3.zero
    lv.Parent = chassis
    local ao = Instance.new("AlignOrientation")
    ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
    ao.Attachment0 = att; ao.MaxTorque = 4e6; ao.Responsiveness = 30
    ao.Parent = chassis
    local seat = Instance.new("VehicleSeat")
    seat.Size = Vector3.new(2, 0.5, 2)
    seat.CFrame = chassis.CFrame * CFrame.new(0, chassis.Size.Y / 2 + 0.5, id == "warrig" and -6 or 0)
    seat.MaxSpeed = 0; seat.Torque = 0
    seat.Parent = model
    if def.Seats >= 4 then
        for i = 1, 3 do
            local ps = Instance.new("Seat")
            ps.Size = Vector3.new(2, 0.5, 2)
            ps.CFrame = chassis.CFrame * CFrame.new(i % 2 == 0 and 3 or -3, chassis.Size.Y / 2 + 0.5, i < 2 and 0 or 4)
            ps.Parent = model
        end
    end
    model.Parent = workspace
    model:PivotTo(CFrame.new(120, 6, 52))
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then pcall(function() part:SetNetworkOwner(nil) end) end
    end
    local v = { Model = model, Root = chassis, Seat = seat, LV = lv, AO = ao, Def = def, Params = RaycastParams.new() }
    v.Params.FilterType = Enum.RaycastFilterType.Exclude
    v.Params.FilterDescendantsInstances = { model }
    ActiveVehicles[plr] = v
    v.Con = RunService.Heartbeat:Connect(function()
        if not chassis.Parent then v.Con:Disconnect() return end
        local occ = seat.Occupant
        local yaw = select(2, chassis.CFrame:ToOrientation())
        ao.CFrame = CFrame.Angles(0, yaw, 0)
        local vel = Vector3.zero
        if occ then
            vel = chassis.CFrame.LookVector * seat.ThrottleFloat * def.Speed
                + chassis.CFrame.RightVector * seat.SteerFloat * def.Speed * 0.55
            vel = Vector3.new(vel.X, 0, vel.Z)
        end
        local down = workspace:Raycast(chassis.Position, Vector3.new(0, -8, 0), v.Params)
        local vy = occ and (down and math.clamp((down.Position.Y + 4 - chassis.Position.Y) * 6, -25, 25) or 0) or 0
        lv.VectorVelocity = Vector3.new(vel.X, vy, vel.Z)
        chassis.AssemblyAngularVelocity = chassis.AssemblyAngularVelocity * 0.85
    end)
    seat:GetPropertyChangedSignal("Occupant"):Connect(function()
        if not seat.Occupant then
            task.delay(15, function() if not seat.Occupant then destroyVehicle(plr) end end)
        end
    end)
    if def.ContactDmg then
        chassis.Touched:Connect(function(hit)
            local m = hit:FindFirstAncestorOfClass("Model")
            local hum = m and m:FindFirstChildOfClass("Humanoid")
            if hum and chassis.AssemblyLinearVelocity.Magnitude > 26 and not m:FindFirstChild("VehicleSeat") then
                local victim = Players:GetPlayerFromCharacter(m)
                if victim and victim ~= plr then
                    dealDamage(plr, m, def.ContactDmg, { Knock = 50, Dir = chassis.CFrame.LookVector })
                end
            end
        end)
    end
    notify(plr, def.Name .. " deployed at the garage.", def.Color)
end

-- ── kill all / nuke ───────────────────────────────────────────────
local BigCd = { KillAll = 0, Nuke = 0 }

local function activateKillAll(plr)
    if not Pass_has(plr, "KillAll") then return "no-pass" end
    local now = os.clock()
    if now < BigCd.KillAll then return "cd" end
    BigCd.KillAll = now + 600
    cineAll({ Kind = "KillAll", Who = plr.Name, T = 5 })
    for _, p in ipairs(Players:GetPlayers()) do
        notify(p, "⚠ " .. plr.Name .. " triggered KILL ALL — 5 seconds.", Config.Colors.Danger)
        RE:FireClient(p, "Siren", 5)
    end
    task.delay(5, function()
        for _, victim in ipairs(Players:GetPlayers()) do
            if victim ~= plr then
                local c = victim.Character
                local hum = c and c:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    hum:TakeDamage(1e9)
                    if hum.Health <= 0 then onKill(plr, c) end -- credit only on real death
                end
            end
        end
        fxAll({ Type = "nukeflash", Color = Config.Colors.Danger })
    end)
    return "ok"
end

local function activateNuke(plr)
    if not Pass_has(plr, "Nuke") then return "no-pass" end
    local now = os.clock()
    if now < BigCd.Nuke then return "cd" end
    BigCd.Nuke = now + 900
    cineAll({ Kind = "Nuke", Who = plr.Name, T = 8 })
    for _, p in ipairs(Players:GetPlayers()) do
        notify(p, "☢ " .. plr.Name .. " launched a NUKE at the arena — 8 seconds to impact.", Config.Colors.Danger)
        RE:FireClient(p, "Siren", 8)
    end
    task.delay(8, function()
        local center = Vector3.new(0, 4, 0)
        for _, victim in ipairs(Players:GetPlayers()) do
            local c = victim.Character
            local hrp = c and c:FindFirstChild("HumanoidRootPart")
            if hrp and (hrp.Position - center).Magnitude <= 140 then
                local hum = c:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    hum:TakeDamage(2500)
                    if hum.Health <= 0 then onKill(plr, c) end
                end
            end
        end
        for i = 1, 10 do
            task.spawn(function()
                local h = 8 + i * 12
                local stem = mkPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 14 + i * 3, 14 + i * 3),
                    CFrame = CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
                    Color = Color3.fromRGB(255, 120 - i * 8, 40), Material = Enum.Material.Neon, Transparency = 0.25 + i * 0.05, CanCollide = false }, FXFolder)
                TweenService:Create(stem, TweenInfo.new(6), { Transparency = 1, Size = Vector3.new(h + 10, (14 + i * 3) * 1.4, (14 + i * 3) * 1.4) }):Play()
                Debris:AddItem(stem, 6.5)
            end)
        end
        local cap = mkPart({ Shape = Enum.PartType.Ball, Size = Vector3.new(60, 60, 60), CFrame = CFrame.new(0, 130, 0),
            Color = Color3.fromRGB(220, 160, 255), Material = Enum.Material.Neon, Transparency = 0.2, CanCollide = false }, FXFolder)
        TweenService:Create(cap, TweenInfo.new(7), { Transparency = 1, Size = Vector3.new(160, 160, 160) }):Play()
        Debris:AddItem(cap, 7.5)
        fxAll({ Type = "nukeflash", Color = Color3.fromRGB(220, 180, 255) })
    end)
    return "ok"
end

-- ── cash rain ─────────────────────────────────────────────────────
task.spawn(function()
    while true do
        task.wait(Config.Income.RainEvery)
        _rain = true
        for _, p in ipairs(Players:GetPlayers()) do
            notify(p, "💸 CASH RAIN — all income x" .. Config.Income.RainMult .. " for " .. Config.Income.RainFor .. "s!", Config.Colors.Gold)
            RE:FireClient(p, "Rain", true)
        end
        task.wait(Config.Income.RainFor)
        _rain = false
        for _, p in ipairs(Players:GetPlayers()) do RE:FireClient(p, "Rain", false) end
    end
end)

-- ── remote router ─────────────────────────────────────────────────
RF.OnServerInvoke = function(plr, action, a)
    if not rateOk(plr, "RF", 0.08) then return { ok = false } end
    local s = get(plr)
    if action == "GetState" then
        return {
            Cash = s and s.Cash or 0, Kills = s and s.Kills or 0, Rebirths = s and s.Rebirths or 0,
            Weapons = s and s.Weapons or {}, Equipped = s and s.Equipped or "fists",
            Droppers = s and s.Droppers or {}, Vehicles = s and s.Vehicles or {},
            Passes = Pass_flags(plr), Claimed = PlotByPlayer[plr] and PlotByPlayer[plr].Index or nil,
            Streak = St[plr] and St[plr].Streak or 0, Settings = s and s.Settings or {},
            DashMax = maxDash(plr),
        }
    elseif action == "BuyWeapon" then
        local w = Config.Weapons[a]
        if w and s and not s.Weapons[a] and spend(plr, w.Price) then
            s.Weapons[a] = true; s.Dirty = true
            return { ok = true }
        end
        return { ok = false }
    elseif action == "Equip" then
        if s and s.Weapons[a] and Config.Weapons[a] then
            s.Equipped = a; s.Dirty = true
            fxAll({ Type = "wmodel", Char = plr.Name, W = a })
            return { ok = true, Weapon = a }
        end
        return { ok = false }
    elseif action == "BuyVehicle" then
        local v = Config.Vehicles[a]
        if v and s and not s.Vehicles[a] and spend(plr, v.Price) then
            s.Vehicles[a] = true; s.Dirty = true
            return { ok = true }
        end
        return { ok = false }
    elseif action == "Summon" then
        spawnVehicle(plr, sanitize(tostring(a)))
        return { ok = true }
    elseif action == "BuyDropper" then
        local def
        for _, d in ipairs(Config.Droppers) do if d.Id == a then def = d break end end
        local ty = PlotByPlayer[plr]
        if def and s and ty and not s.Droppers[a] and spend(plr, def.Cost) then
            s.Droppers[a] = true; s.Dirty = true
            ty:placeDropper(a)
            return { ok = true }
        end
        return { ok = false }
    elseif action == "Rebirth" then
        local ty = PlotByPlayer[plr]
        if not s or not ty then return { ok = false } end
        local cost = Config.Rebirth.BaseCost * (Config.Rebirth.CostMult ^ s.Rebirths)
        if s.Cash < cost then return { ok = false, Need = cost } end
        s.Cash = 0; s.Rebirths += 1; s.Droppers = {}; s.Dirty = true
        awardBadge(plr, "Reborn")
        local ls = plr:FindFirstChild("leaderstats")
        if ls then ls.Cash.Value = 0; ls.Rebirths.Value = s.Rebirths end
        ty:clearBuilds()
        cineAll({ Kind = "Rebirth", Who = plr.Name, N = s.Rebirths })
        notify(plr, "REBIRTH " .. s.Rebirths .. " — permanent x" .. (1 + s.Rebirths * Config.Rebirth.PerkMult) .. " cash!", Config.Colors.Gold)
        local unlock = Config.RebirthUnlocks[s.Rebirths]
        if unlock then notify(plr, "UNLOCKED: " .. unlock.Name .. " — " .. unlock.Desc, Config.Colors.Purple) end
        local st = St[plr]
        if st then st.Dash = maxDash(plr) end
        RE:FireClient(plr, "Rebirthed", { Rebirths = s.Rebirths, Unlock = unlock and unlock.Name or nil, DashMax = maxDash(plr) })
        fxAll({ Type = "ultburst", Pos = (plr.Character and plr.Character:GetPivot().Position) or Vector3.new(0, 8, 0), Color = Config.Colors.Gold })
        return { ok = true }
    elseif action == "PromptPass" then
        local def = Config.Gamepasses[a]
        if def and def.Id > 0 then pcall(function() MarketplaceService:PromptGamePassPurchase(plr, def.Id) end) end
        return { ok = true }
    elseif action == "Activate" then
        if a == "KillAll" then return { Result = activateKillAll(plr) }
        elseif a == "Nuke" then return { Result = activateNuke(plr) } end
        return { ok = false }
    elseif action == "SetSetting" then
        if s and type(a) == "table" and a.Key and a.Value ~= nil then
            for _, def in ipairs(Config.Settings) do
                if def.Key == a.Key then
                    if def.Max then a.Value = math.clamp(tonumber(a.Value) or def.Def, def.Min, def.Max)
                    else a.Value = (a.Value == true) end
                    s.Settings[a.Key] = a.Value; s.Dirty = true
                    return { ok = true }
                end
            end
        end
        return { ok = false }
    end
    return { ok = false }
end

Players.PlayerAdded:Connect(function(plr)
    load(plr)
    local ls = Instance.new("Folder"); ls.Name = "leaderstats"; ls.Parent = plr
    for _, name in ipairs({ "Cash", "Kills", "Rebirths", "Streak" }) do
        local v = Instance.new("IntValue"); v.Name = name; v.Parent = ls
    end
    ls.Cash.Value = Sessions[plr].Cash
    ls.Kills.Value = Sessions[plr].Kills
    ls.Rebirths.Value = Sessions[plr].Rebirths
    Pass_load(plr)
    plr.CharacterAdded:Connect(function(ch)
        local hum = ch:WaitForChild("Humanoid")
        local s = Sessions[plr]
        hum.WalkSpeed = Pass_has(plr, "VIP") and Config.Sprint.VipSpeed or Config.Sprint.Speed - 8
        hum.JumpPower = Pass_has(plr, "VIP") and 60 or 50
        hum.MaxHealth = 100 + ((s and s.Rebirths >= 2) and 50 or 0)
        hum.Health = hum.MaxHealth
        hum.Died:Connect(function()
            local st = St[plr]
            if st then st.Streak = 0 end
            local l = plr:FindFirstChild("leaderstats")
            if l then l.Streak.Value = 0 end
        end)
        task.delay(0.5, function()
            fxAll({ Type = "wmodel", Char = plr.Name, W = Sessions[plr] and Sessions[plr].Equipped or "fists" })
            if Sessions[plr] and Sessions[plr].Rebirths >= 1 then
                fxAll({ Type = "aura", Char = plr.Name, Tier = 0, Perm = true })
            end
        end)
    end)
end)

Players.PlayerRemoving:Connect(function(plr)
    local ty = PlotByPlayer[plr]
    if ty then
        ty.Owner = nil
        ty:clearBuilds()
        ty.ClaimPad.Color = Config.Colors.Accent
        ty.ClaimPrompt.Enabled = true
        PlotByPlayer[plr] = nil
    end
    destroyVehicle(plr)
    St[plr] = nil
    Flags[plr] = nil
    Ratelimit[plr] = nil
    awardedBadge[plr] = nil
    save(plr)
end)

game:BindToClose(function()
    for _, plr in ipairs(Players:GetPlayers()) do save(plr) end
end)

task.spawn(function()
    while true do
        task.wait(120)
        for _, plr in ipairs(Players:GetPlayers()) do
            local s = get(plr)
            if s and s.Dirty and s.LoadedOK then
                s.Dirty = false
                task.spawn(function()
                    pcall(Store.SetAsync, Store, "p_" .. plr.UserId,
                        { Cash = s.Cash, Kills = s.Kills, Deaths = s.Deaths, Rebirths = s.Rebirths,
                          Weapons = s.Weapons, Equipped = s.Equipped, Droppers = s.Droppers, Settings = s.Settings, Vehicles = s.Vehicles })
                end)
            end
        end
    end
end)

