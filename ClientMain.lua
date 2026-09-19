local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local TextChatService = game:GetService("TextChatService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("ClashConfig"))
local Util = require(ReplicatedStorage:WaitForChild("ClashUtil"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RF = Remotes:WaitForChild("RF")
local RE = Remotes:WaitForChild("RE")

local IS_TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local C = Config.Colors
local S = { Cash = 0, Displayed = 0, Kills = 0, Rebirths = 0, Streak = 0, Passes = {}, Weapons = {},
    Equipped = "fists", Droppers = {}, Vehicles = {}, Ult = 0, Dash = Config.Dash.Charges, DashMax = Config.Dash.Charges,
    Rain = false, Settings = {}, Played = false, Claimed = nil }
for _, def in ipairs(Config.Settings) do S.Settings[def.Key] = def.Def end

local gui = Instance.new("ScreenGui")
gui.Name = "AetherHUD"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")
local guiScale = Instance.new("UIScale"); guiScale.Parent = gui

local camera = workspace.CurrentCamera
local baseFOV = S.Settings.FOV or 70
local shakeT, shakeAmp = 0, 0
local function shake(amp, time) shakeAmp = math.max(shakeAmp, amp) shakeT = math.max(shakeT, time or 0.25) end

local function mk(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props) do inst[k] = v end
    inst.Parent = parent
    return inst
end
local function corner(o, r) return mk("UICorner", { CornerRadius = UDim.new(0, r) }, o) end
local function stroke(o, color, th, tr) return mk("UIStroke", { Color = color, Thickness = th or 1, Transparency = tr or 0.4 }, o) end

local soundPool = {}
local function sound(id, vol, speed)
    if not id or id == "" then return end
    local s = table.remove(soundPool)
    if not s then
        s = Instance.new("Sound")
        s.Parent = SoundService
    end
    s.SoundId = id
    s.Volume = (vol or 0.5) * (S.Settings.SFX or 0.8)
    s.PlaybackSpeed = speed or 1
    s:Play()
    task.delay(5, function()
        if s and s.Parent then
            s:Stop()
            if #soundPool < 16 then table.insert(soundPool, s) else s:Destroy() end
        end
    end)
end

local function buttonize(btn, base)
    base = base or 1
    local us = mk("UIScale", { Scale = base }, btn)
    btn.MouseEnter:Connect(function() Util.tween(us, 0.14, { Scale = base * 1.06 }, Enum.EasingStyle.Back) end)
    btn.MouseLeave:Connect(function() Util.tween(us, 0.14, { Scale = base }) end)
    btn.MouseButton1Down:Connect(function() Util.tween(us, 0.08, { Scale = base * 0.93 }) end)
    btn.MouseButton1Up:Connect(function() Util.tween(us, 0.14, { Scale = base * 1.06 }, Enum.EasingStyle.Back) end)
end

local function animateGradient(g, speed)
    task.spawn(function()
        while g.Parent do
            local t = os.clock() * (speed or 0.25)
            g.Offset = Vector2.new(math.sin(t) * 0.5, math.cos(t * 0.7) * 0.2)
            RunService.RenderStepped:Wait()
        end
    end)
end

-- fire functions defined once, before any wiring
local function aimDir()
    local ch = player.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if not hrp then return Vector3.zAxis end
    local ray = camera:ViewportPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
    local d = (ray.Origin + ray.Direction * 500) - hrp.Position
    d = Vector3.new(d.X, 0, d.Z)
    return d.Magnitude > 0.01 and d.Unit or hrp.CFrame.LookVector
end
local function sendAim() RE:FireServer("Aim", aimDir()) end
local function fireM1() RE:FireServer("M1") end
local function fireSkill(n) RE:FireServer("Skill", n) end
local function fireUlt() RE:FireServer("Ult") end
local function fireDash() RE:FireServer("Dash", aimDir()) end
local blockActive = false
local sprinting = false
local function setSprint(on)
    if sprinting == on then return end
    sprinting = on
    RE:FireServer("Sprint", on)
    local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if hum and S.Played then
        hum.WalkSpeed = (S.Passes.VIP and Config.Sprint.VipSpeed or Config.Sprint.Speed - 8) + (on and 8 or 0)
    end
end

-- vector icon factory
local function makeIcon(parent, kind, color, tileColor)
    color = color or C.Text
    tileColor = tileColor or C.Panel
    local h = mk("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), ZIndex = 3 }, parent)
    local cx, cy = 0.5, 0.5
    if kind == "cash" then
        mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBlack,
            Text = "$", TextScaled = true, TextColor3 = color }, h)
    elseif kind == "shop" then
        local d1 = mk("Frame", { BackgroundColor3 = color, Size = UDim2.fromOffset(20, 20), Position = UDim2.new(cx, -10, cy, -10), Rotation = 45 }, h)
        corner(d1, 4)
        mk("Frame", { BackgroundColor3 = tileColor, Size = UDim2.fromOffset(10, 10), Position = UDim2.new(cx, -5, cy, -5), Rotation = 45 }, h)
        mk("Frame", { BackgroundColor3 = color, Size = UDim2.fromOffset(4, 4), Position = UDim2.new(cx, -2, cy, -2), Rotation = 45 }, h)
    elseif kind == "rebirth" then
        for i = 0, 2 do
            local bar = mk("Frame", { BackgroundColor3 = color, Size = UDim2.fromOffset(6, 16),
                Position = UDim2.new(cx, math.cos(math.rad(i * 120 - 90)) * 11 - 3, cy, math.sin(math.rad(i * 120 - 90)) * 11 - 8), Rotation = i * 120 }, h)
            corner(bar, 3)
        end
        local hubDot = mk("Frame", { BackgroundColor3 = color, Size = UDim2.fromOffset(6, 6), Position = UDim2.new(cx, -3, cy, -3) }, h)
        corner(hubDot, 3)
    elseif kind == "gear" then
        local hubBig = mk("Frame", { BackgroundColor3 = color, Size = UDim2.fromOffset(14, 14), Position = UDim2.new(cx, -7, cy, -7) }, h)
        corner(hubBig, 7)
        local hole = mk("Frame", { BackgroundColor3 = tileColor, Size = UDim2.fromOffset(6, 6), Position = UDim2.new(cx, -3, cy, -3) }, h)
        corner(hole, 3)
        for i = 0, 7 do
            local a = math.rad(i * 45)
            mk("Frame", { BackgroundColor3 = color, Size = UDim2.fromOffset(4, 7),
                Position = UDim2.new(cx, math.cos(a) * 11 - 2, cy, math.sin(a) * 11 - 3.5), Rotation = i * 45 }, h)
        end
    elseif kind == "help" then
        mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBlack,
            Text = "?", TextScaled = true, TextColor3 = color }, h)
    end
    return h
end

-- ══════════════════════════════════════════════════════════════════
-- PROCEDURAL ANIMATION SYSTEM — defined before FXBANK closes over it
-- ══════════════════════════════════════════════════════════════════
local RigCache = {}
local function rigFor(char)
    local r = RigCache[char]
    if r then return r end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local function motor(parent, name)
        local m = parent and parent:FindFirstChild(name)
        return (m and m:IsA("Motor6D")) and m or nil
    end
    local J = { Root = motor(root, "Root") }
    local r15 = char:FindFirstChild("UpperTorso")
    if r15 then
        local lower = char:FindFirstChild("LowerTorso")
        J.Waist = motor(lower, "Waist")
        J.RS = motor(r15, "RightShoulder")
        J.LS = motor(r15, "LeftShoulder")
    else
        local torso = char:FindFirstChild("Torso")
        if torso then
            J.RS = motor(torso, "Right Shoulder")
            J.LS = motor(torso, "Left Shoulder")
        end
    end
    RigCache[char] = J
    return J
end

local Poses = {}
Poses.jab = function(t)
    local p = math.sin(t * math.pi)
    local other = math.sin((t - 0.5) * math.pi * 2)
    return {
        RS = CFrame.Angles(math.rad(-95 * p), 0, math.rad(8 * p)),
        LS = CFrame.Angles(math.rad(-60 * other), 0, math.rad(-8 * other)),
        Waist = CFrame.Angles(0, math.rad(14 * other), 0),
    }
end
Poses.slash = function(t)
    local w = math.clamp(t / 0.35, 0, 1)
    local s = math.clamp((t - 0.35) / 0.3, 0, 1)
    local e = math.clamp((t - 0.75) / 0.25, 0, 1)
    local back = w * (1 - s)
    local fwd = s * (1 - e * 0.7)
    return {
        RS = CFrame.Angles(math.rad(-150 * back - 30 * fwd), 0, math.rad(-50 * back + 55 * fwd)),
        LS = CFrame.Angles(math.rad(-20 * s), 0, math.rad(-30 * s)),
        Waist = CFrame.Angles(0, math.rad(-38 * back + 42 * fwd), 0),
    }
end
Poses.spin = function(t)
    local a = t * math.pi * 2
    return {
        RS = CFrame.Angles(math.rad(-80), 0, math.rad(75)),
        LS = CFrame.Angles(math.rad(-80), 0, math.rad(-75)),
        Waist = CFrame.Angles(0, a, 0),
    }
end
Poses.aim = function(t)
    local p = math.clamp(t / 0.25, 0, 1)
    return {
        RS = CFrame.Angles(math.rad(-90 * p), 0, math.rad(-6 * p)),
        LS = CFrame.Angles(math.rad(-35 * p), 0, math.rad(28 * p)),
        Waist = CFrame.Angles(0, math.rad(-12 * p), 0),
    }
end
Poses.slam = function(t)
    local up = math.clamp(t / 0.4, 0, 1)
    local down = math.clamp((t - 0.45) / 0.25, 0, 1)
    local raise = up * (1 - down)
    local smash = down
    return {
        RS = CFrame.Angles(math.rad(-165 * raise + 140 * smash), 0, math.rad(10)),
        LS = CFrame.Angles(math.rad(-165 * raise + 140 * smash), 0, math.rad(-10)),
        Waist = CFrame.Angles(math.rad(-12 * raise + 26 * smash), 0, 0),
        Root = CFrame.Angles(math.rad(8 * smash), 0, 0),
    }
end
Poses.cast = function(t)
    local p = math.sin(math.clamp(t, 0, 1) * math.pi)
    return {
        RS = CFrame.Angles(math.rad(-150 * p), 0, math.rad(-18 * p)),
        LS = CFrame.Angles(math.rad(-150 * p), 0, math.rad(18 * p)),
        Waist = CFrame.Angles(math.rad(-10 * p), 0, 0),
        Root = CFrame.Angles(math.rad(-6 * p), 0, 0),
    }
end
Poses.block = function()
    return {
        RS = CFrame.Angles(math.rad(-65), 0, math.rad(55)),
        LS = CFrame.Angles(math.rad(-65), 0, math.rad(-55)),
        Waist = CFrame.Angles(math.rad(6), 0, 0),
    }
end
Poses.dash = function(t)
    local p = math.sin(t * math.pi)
    return {
        Root = CFrame.Angles(math.rad(-18 * p), 0, 0),
        RS = CFrame.Angles(math.rad(30 * p), 0, math.rad(-20 * p)),
        LS = CFrame.Angles(math.rad(30 * p), 0, math.rad(20 * p)),
    }
end

local CharPoses = {}
local function setPose(char, anim, dur, hold)
    if not Poses[anim] then return end
    CharPoses[char] = { Anim = anim, Start = os.clock(), Dur = dur or 0.35, Hold = hold and true or false, Weight = CharPoses[char] and CharPoses[char].Weight or 0 }
end
local function endPose(char)
    local p = CharPoses[char]
    if p then p.Hold = false; p.EndAt = os.clock() end
end

local HeldCache = {}
local function buildHeld(char, wid)
    local old = HeldCache[char]
    if old then old:Destroy(); HeldCache[char] = nil end
    local w = Config.Weapons[wid]
    if not w or not w.Model then return end
    local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
    if not hand then return end
    local m = Instance.new("Model"); m.Name = "HeldWeapon"
    local function part(size, off, color, shape)
        local p = Instance.new("Part")
        p.Size = size; p.CanCollide = false; p.Massless = true
        p.Material = Enum.Material.Neon; p.Color = color or w.Color
        if shape then p.Shape = shape end
        p.CFrame = hand.CFrame * off
        p.Parent = m
        local weld = Instance.new("WeldConstraint"); weld.Part0 = hand; weld.Part1 = p; weld.Parent = p
        return p
    end
    if w.Model == "blade" then
        part(Vector3.new(0.25, 3, 0.5), CFrame.new(0, -1.8, 0))
        part(Vector3.new(0.55, 0.25, 0.8), CFrame.new(0, -0.3, 0), Color3.fromRGB(30, 26, 48))
    elseif w.Model == "hammer" then
        part(Vector3.new(0.35, 3.4, 0.35), CFrame.new(0, -1.6, 0), Color3.fromRGB(30, 26, 48))
        part(Vector3.new(1.6, 1.2, 1.2), CFrame.new(0, -3.4, 0))
    elseif w.Model == "gun" then
        part(Vector3.new(0.4, 0.5, 2), CFrame.new(0, -0.4, -0.8))
        part(Vector3.new(0.3, 0.7, 0.4), CFrame.new(0, -0.8, 0), Color3.fromRGB(30, 26, 48))
    elseif w.Model == "scythe" then
        part(Vector3.new(0.25, 4.6, 0.25), CFrame.new(0, -2, 0), Color3.fromRGB(30, 26, 48))
        part(Vector3.new(0.2, 2, 0.5), CFrame.new(0.8, -4.2, 0) * CFrame.Angles(0, 0, math.rad(-55)))
    elseif w.Model == "bow" then
        part(Vector3.new(0.2, 3, 0.2), CFrame.new(0, -0.8, -0.3) * CFrame.Angles(0, 0, math.rad(12)))
        part(Vector3.new(0.2, 3, 0.2), CFrame.new(0, -0.8, 0.3) * CFrame.Angles(0, 0, math.rad(-12)))
        part(Vector3.new(0.06, 2.4, 0.06), CFrame.new(0, -0.8, 0), Color3.fromRGB(230, 230, 240))
    end
    m.Parent = char
    HeldCache[char] = m
end

Players.PlayerRemoving:Connect(function(plr)
    if plr.Character then
        CharPoses[plr.Character] = nil
        if HeldCache[plr.Character] then HeldCache[plr.Character]:Destroy(); HeldCache[plr.Character] = nil end
        RigCache[plr.Character] = nil
    end
end)

RunService.RenderStepped:Connect(function(dt)
    local now = os.clock()
    for char, p in pairs(CharPoses) do
        local J = rigFor(char)
        if not J or not J.RS then
            CharPoses[char] = nil
        else
            local t = (now - p.Start) / math.max(p.Dur, 0.05)
            local targetW = 1
            if not p.Hold and (t >= 1.3 or (p.EndAt and now > p.EndAt + 0.15)) then
                CharPoses[char] = nil
                targetW = 0
            end
            p.Weight = Util.lerp(p.Weight, targetW, math.min(1, dt * 14))
            if p.Weight > 0.01 and Poses[p.Anim] then
                local curve = Poses[p.Anim](math.clamp(t, 0, 1))
                for key, cf in pairs(curve) do
                    local motor = J[key]
                    if motor then motor.Transform = motor.Transform:Lerp(cf, p.Weight) end
                end
            end
        end
    end
    local ch = player.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if hrp then
        local J = rigFor(ch)
        if J and J.Root then
            local vel = hrp.AssemblyLinearVelocity
            local flat = Vector3.new(vel.X, 0, vel.Z).Magnitude
            if flat > 4 then
                local lean = math.clamp(flat / 60, 0, 0.16)
                J.Root.Transform = J.Root.Transform:Lerp(CFrame.Angles(lean, 0, 0), math.min(1, dt * 8))
            end
        end
    end
end)

-- ══════════════════════════════════════════════════════════════════
-- FX/SFX BANK — pose/poseend/wmodel handlers present, animations live
-- ══════════════════════════════════════════════════════════════════
local dmgAlive = 0
local function spawnDmgNum(pos, text, color, big)
    if dmgAlive > 22 then return end
    dmgAlive += 1
    local p = Instance.new("Part")
    p.Size = Vector3.new(0.2, 0.2, 0.2); p.Transparency = 1; p.CanCollide = false; p.Anchored = true
    p.CFrame = CFrame.new(pos + Vector3.new((math.random() - 0.5) * 2, 2, 0))
    p.Parent = workspace
    local bb = Instance.new("BillboardGui"); bb.Size = UDim2.fromScale(big and 8 or 6, big and 2.6 or 2); bb.AlwaysOnTop = true; bb.Parent = p
    local tl = Instance.new("TextLabel"); tl.BackgroundTransparency = 1; tl.Size = UDim2.fromScale(1, 1)
    tl.Font = Enum.Font.GothamBlack; tl.TextScaled = true; tl.Text = text; tl.TextColor3 = color
    tl.TextStrokeTransparency = 0.3; tl.Parent = bb
    Util.tween(p, 0.9, { Position = p.Position + Vector3.new(0, 6, 0) })
    Util.tween(tl, 0.9, { TextTransparency = 1, TextStrokeTransparency = 1 })
    task.delay(0.95, function() dmgAlive -= 1 p:Destroy() end)
end

local FXBANK = {}
FXBANK.pose = function(d)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Name == d.Char and plr.Character then
            setPose(plr.Character, d.Anim, d.Dur, d.Hold)
        end
    end
end
FXBANK.poseend = function(d)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Name == d.Char and plr.Character then
            endPose(plr.Character)
        end
    end
end
FXBANK.wmodel = function(d)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Name == d.Char and plr.Character then
            buildHeld(plr.Character, d.W)
        end
    end
end
FXBANK.slash = function(d)
    local dist = (d.To - d.From).Magnitude
    local p = Instance.new("Part")
    p.Size = Vector3.new(dist, 0.6, d.Heavy and 3.2 or 2.4)
    p.CFrame = CFrame.lookAt((d.From + d.To) / 2, d.To)
    p.Anchored = true; p.CanCollide = false
    p.Material = Enum.Material.Neon; p.Color = d.Color or C.Accent
    p.Transparency = d.Thin and 0.4 or 0.1
    p.Parent = workspace
    Util.tween(p, 0.3, { Transparency = 1, Size = Vector3.new(dist, 0.1, d.Thin and 1 or (d.Heavy and 5 or 4)) })
    Debris:AddItem(p, 0.35)
    sound(Config.Sounds.Whoosh, d.Heavy and 0.45 or 0.28, (d.Thin and 1.15 or 0.92) + math.random() * 0.08)
end
FXBANK.ring = function(d)
    local p = Instance.new("Part")
    p.Shape = Enum.PartType.Cylinder
    p.Size = Vector3.new(0.4, 2, 2)
    p.CFrame = CFrame.new(d.Pos) * CFrame.Angles(0, 0, math.rad(90))
    p.Anchored = true; p.CanCollide = false
    p.Material = Enum.Material.Neon; p.Color = d.Color or C.Accent
    p.Transparency = 0.1
    p.Parent = workspace
    Util.tween(p, 0.4, { Size = Vector3.new(0.4, d.Radius * 2, d.Radius * 2), Transparency = 1 })
    Debris:AddItem(p, 0.45)
    sound(Config.Sounds.Zap, 0.4, 0.85)
    shake(0.5, 0.18)
end
FXBANK.blast = function(d)
    local p = Instance.new("Part")
    p.Shape = Enum.PartType.Ball
    p.Size = Vector3.new(2, 2, 2)
    p.CFrame = CFrame.new(d.Pos + Vector3.new(0, 2, 0))
    p.Anchored = true; p.CanCollide = false
    p.Material = Enum.Material.ForceField; p.Color = d.Color or C.Accent
    p.Transparency = 0.15
    p.Parent = workspace
    Util.tween(p, 0.35, { Size = Vector3.new(d.Radius * 2, d.Radius * 2, d.Radius * 2), Transparency = 1 })
    Debris:AddItem(p, 0.4)
    if not d.Small then
        sound(Config.Sounds.Boom, 0.5, 1 + math.random() * 0.2)
        shake(0.6, 0.2)
    end
end
FXBANK.tracer = function(d)
    local dist = (d.To - d.From).Magnitude
    local p = Instance.new("Part")
    p.Size = Vector3.new(dist, d.Thin and 0.15 or 0.4, d.Thin and 0.15 or 0.4)
    p.CFrame = CFrame.lookAt((d.From + d.To) / 2, d.To)
    p.Anchored = true; p.CanCollide = false
    p.Material = Enum.Material.Neon; p.Color = d.Color or C.AccentAlt
    p.Transparency = 0.2
    p.Parent = workspace
    Debris:AddItem(p, 0.12)
    sound(Config.Sounds.Zap, d.Thin and 0.2 or 0.35, 1.2 + math.random() * 0.2)
end
FXBANK.cast = function(d)
    local p = Instance.new("Part")
    p.Shape = Enum.PartType.Ball
    p.Size = Vector3.new(1, 1, 1)
    p.CFrame = CFrame.new(d.Pos)
    p.Anchored = true; p.CanCollide = false
    p.Material = Enum.Material.ForceField; p.Color = d.Color or C.Accent
    p.Parent = workspace
    Util.tween(p, 0.3, { Size = Vector3.new(6, 6, 6), Transparency = 1 })
    Debris:AddItem(p, 0.35)
    sound(Config.Sounds.Zap, 0.3, 0.7)
end
FXBANK.ultburst = function(d)
    for i = 1, 3 do
        local p = Instance.new("Part")
        p.Shape = Enum.PartType.Ball
        p.Size = Vector3.new(2, 2, 2)
        p.CFrame = CFrame.new(d.Pos)
        p.Anchored = true; p.CanCollide = false
        p.Material = Enum.Material.ForceField; p.Color = d.Color or C.Accent
        p.Transparency = 0.1
        p.Parent = workspace
        Util.tween(p, 0.5 + i * 0.15, { Size = Vector3.new(14 + i * 8, 14 + i * 8, 14 + i * 8), Transparency = 1 })
        Debris:AddItem(p, 0.7 + i * 0.15)
    end
    sound(Config.Sounds.Boom, 0.6, 0.8)
    shake(1.2, 0.4)
end
FXBANK.parry = function(d)
    local p = Instance.new("Part")
    p.Shape = Enum.PartType.Ball
    p.Size = Vector3.new(4, 4, 4)
    p.CFrame = CFrame.new(d.Pos)
    p.Anchored = true; p.CanCollide = false
    p.Material = Enum.Material.ForceField; p.Color = C.Gold
    p.Parent = workspace
    Util.tween(p, 0.4, { Size = Vector3.new(12, 12, 12), Transparency = 1 })
    Debris:AddItem(p, 0.45)
    sound(Config.Sounds.Parry, 0.55)
    shake(0.8, 0.25)
end
FXBANK.well = function(d)
    local p = Instance.new("Part")
    p.Shape = Enum.PartType.Ball
    p.Size = Vector3.new(2, 2, 2)
    p.CFrame = CFrame.new(d.Pos)
    p.Anchored = true; p.CanCollide = false
    p.Material = Enum.Material.ForceField; p.Color = d.Color or C.Purple
    p.Transparency = 0.3
    p.Parent = workspace
    Util.tween(p, d.Ticks * 0.7, { Size = Vector3.new(d.Radius * 2, d.Radius, d.Radius * 2), Transparency = 0.85 })
    Debris:AddItem(p, d.Ticks * 0.7 + 0.2)
    sound(Config.Sounds.Whoosh, 0.4, 0.6)
end
FXBANK.orbit = function(d)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Name == d.Char and plr.Character then
            local root = plr.Character:FindFirstChild("HumanoidRootPart")
            if root then
                local att = Instance.new("Attachment"); att.Parent = root
                local pe = Instance.new("ParticleEmitter")
                pe.Rate = 40; pe.Lifetime = NumberRange.new(0.4, 0.8); pe.Speed = NumberRange.new(2, 6)
                pe.SpreadAngle = Vector2.new(180, 180); pe.Color = ColorSequence.new(d.Color or C.Accent)
                pe.Size = NumberSequence.new(0.6, 0.1); pe.Parent = att
                Debris:AddItem(att, d.Ticks * 0.5 + 0.5)
            end
        end
    end
    sound(Config.Sounds.Whoosh, 0.35, 0.8)
end
FXBANK.aura = function(d)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Name == d.Char and plr.Character then
            local root = plr.Character:FindFirstChild("HumanoidRootPart")
            if root then
                local old = root:FindFirstChild("StreakAura")
                if old then old:Destroy() end
                local att = Instance.new("Attachment"); att.Name = "StreakAura"; att.Parent = root
                local pe = Instance.new("ParticleEmitter")
                pe.Rate = d.Tier >= 2 and 14 or 7
                pe.Lifetime = NumberRange.new(0.6, 1.2); pe.Speed = NumberRange.new(1, 4)
                pe.SpreadAngle = Vector2.new(180, 180)
                pe.Color = ColorSequence.new(d.Tier >= 2 and C.Danger or C.AccentAlt, C.Deep)
                pe.Size = NumberSequence.new(0.7, 0)
                pe.Transparency = NumberSequence.new(0.3, 1)
                pe.LightEmission = 0.9
                pe.Parent = att
                if not d.Perm then Debris:AddItem(att, 6) end
            end
        end
    end
    sound(Config.Sounds.Zap, 0.25, 0.6)
end
FXBANK.beam = function(d)
    local mid = d.From + d.Dir * (d.Range * 0.5)
    local p = Instance.new("Part")
    p.Size = Vector3.new(d.Range, 6, 6)
    p.CFrame = CFrame.lookAt(mid, mid + d.Dir)
    p.Anchored = true; p.CanCollide = false
    p.Material = Enum.Material.Neon; p.Color = d.Color or C.AccentAlt
    p.Transparency = 0.25
    p.Parent = workspace
    task.spawn(function()
        for _ = 1, d.Ticks do
            task.wait(0.4)
            if p.Parent then
                p.Transparency = 0.15
                Util.tween(p, 0.35, { Transparency = 0.45 })
            end
        end
    end)
    Debris:AddItem(p, d.Ticks * 0.4 + 0.3)
    sound(Config.Sounds.Zap, 0.55, 0.7)
    shake(0.5, 0.3)
end
FXBANK.nukeflash = function(d)
    if S.Settings.Flash ~= false then
        local f = mk("Frame", { BackgroundColor3 = d.Color or Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), ZIndex = 40, BackgroundTransparency = 0, BorderSizePixel = 0 }, gui)
        Util.tween(f, 1.4, { BackgroundTransparency = 1 })
        Debris:AddItem(f, 1.5)
    end
    sound(Config.Sounds.Boom, 0.9, 0.6)
    shake(3, 1.2)
end

local FlashFrame = mk("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), ZIndex = 48, BackgroundTransparency = 1, BorderSizePixel = 0 }, gui)
local savedLight = nil
FXBANK.impact = function(d)
    if S.Settings.Impact == false then return end
    FlashFrame.BackgroundColor3 = Color3.new(1, 1, 1)
    FlashFrame.BackgroundTransparency = 0
    Util.tween(FlashFrame, Config.Impact.FlashTime, { BackgroundTransparency = 1 })
    if not savedLight then
        savedLight = { Ambient = Lighting.Ambient, Brightness = Lighting.Brightness, FogEnd = Lighting.FogEnd }
        Lighting.Ambient = Color3.new(0, 0, 0)
        Lighting.Brightness = 0.05
        Lighting.FogEnd = 240
        task.delay(0.07, function()
            if savedLight then
                Lighting.Ambient = savedLight.Ambient
                Lighting.Brightness = savedLight.Brightness
                Lighting.FogEnd = savedLight.FogEnd
                savedLight = nil
            end
        end)
    end
    if d.Pos then
        local nearest, bestD = nil, 8
        for _, plr in ipairs(Players:GetPlayers()) do
            local ch = plr.Character
            local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
            if hrp then
                local dd = (hrp.Position - d.Pos).Magnitude
                if dd < bestD then bestD = dd; nearest = ch end
            end
        end
        if nearest then
            local restored = {}
            for _, part in ipairs(nearest:GetDescendants()) do
                if part:IsA("BasePart") then
                    restored[part] = { Color = part.Color, Material = part.Material }
                    part.Color = Color3.new(1, 1, 1)
                    part.Material = Enum.Material.Neon
                end
            end
            task.delay(0.12, function()
                for part, v in pairs(restored) do
                    if part.Parent then part.Color = v.Color; part.Material = v.Material end
                end
            end)
        end
    end
    shake(0.9, 0.16)
    sound(Config.Sounds.Whoosh, 0.5, 1.25)
end

-- ══════════════════════════════════════════════════════════════════
-- CUTSCENE SYSTEM
-- ══════════════════════════════════════════════════════════════════
local LetterTop = mk("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.new(1, 0, 0, 0), ZIndex = 45, BorderSizePixel = 0 }, gui)
local LetterBot = mk("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.new(1, 0, 0, 0), Position = UDim2.new(0, 0, 1, 0), ZIndex = 45, BorderSizePixel = 0 }, gui)
local CineBanner = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 60), Position = UDim2.new(0, 0, 0.68, 0),
    Font = Enum.Font.GothamBlack, TextScaled = true, TextColor3 = C.Text, TextTransparency = 1, ZIndex = 46 }, gui)
local cineLock = false

local function letterbox(open, time)
    local h = open and 90 or 0
    Util.tween(LetterTop, time or 0.4, { Size = UDim2.new(1, 0, 0, h) })
    Util.tween(LetterBot, time or 0.4, { Size = UDim2.new(1, 0, 0, h), Position = UDim2.new(0, 0, 1, -h) })
end
local function banner(text, color, time)
    CineBanner.Text = text
    CineBanner.TextColor3 = color or C.Text
    CineBanner.TextTransparency = 1
    Util.tween(CineBanner, 0.25, { TextTransparency = 0 })
    task.delay(time or 2, function()
        Util.tween(CineBanner, 0.4, { TextTransparency = 1 })
    end)
end
local function cineCamera(kind, timeout)
    if S.Settings.Cine == false then return end
    local origin = camera.CFrame
    cineLock = true
    camera.CameraType = Enum.CameraType.Scriptable
    local lookAt = CFrame.lookAt(Vector3.new(0, 70, 190), Vector3.new(0, 30, 0))
    if kind == "Nuke" then lookAt = CFrame.lookAt(Vector3.new(120, 40, 120), Vector3.new(0, 90, 0)) end
    local t0 = os.clock()
    local conn
    conn = RunService.RenderStepped:Connect(function()
        local a = math.min(1, (os.clock() - t0) / 0.9)
        camera.CFrame = origin:Lerp(lookAt, a * a * (3 - 2 * a))
    end)
    task.delay(timeout or 4, function()
        if conn then conn:Disconnect() end
        cineLock = false
        camera.CameraType = Enum.CameraType.Custom
        camera.CameraSubject = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- LOADING SCREEN → MENU
-- ══════════════════════════════════════════════════════════════════
local boot = mk("Frame", { BackgroundColor3 = C.Background, Size = UDim2.fromScale(1, 1), ZIndex = 60, BorderSizePixel = 0 }, gui)
local bootTitle = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(0.6, 0.12), Position = UDim2.fromScale(0.2, 0.36),
    Font = Enum.Font.GothamBlack, Text = Config.GameName, TextScaled = true, TextColor3 = C.Text, ZIndex = 61 }, boot)
local bootGrad = Instance.new("UIGradient")
bootGrad.Color = ColorSequence.new(C.Accent, C.Text, C.AccentAlt)
bootGrad.Parent = bootTitle
animateGradient(bootGrad, 0.35)
mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(0.6, 0.03), Position = UDim2.fromScale(0.2, 0.49),
    Font = Enum.Font.GothamBold, Text = Config.Tagline .. "  ·  " .. Config.Version, TextScaled = true, TextColor3 = C.Dim, ZIndex = 61 }, boot)
local barBack = mk("Frame", { BackgroundColor3 = C.PanelHi, Size = UDim2.fromScale(0.34, 0.012), Position = UDim2.fromScale(0.33, 0.58), ZIndex = 61 }, boot)
corner(barBack, 8)
local barFill = mk("Frame", { BackgroundColor3 = C.Accent, Size = UDim2.fromScale(0, 1), ZIndex = 62 }, barBack)
corner(barFill, 8)
local statusLabel = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(0.34, 0.025), Position = UDim2.fromScale(0.33, 0.605),
    Font = Enum.Font.GothamBold, Text = "connecting…", TextScaled = true, TextColor3 = C.Dim, ZIndex = 61 }, boot)
local tipLabel = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(0.5, 0.03), Position = UDim2.fromScale(0.25, 0.64),
    Font = Enum.Font.Gotham, Text = "", TextScaled = true, TextColor3 = C.Dim, ZIndex = 61 }, boot)
local tipIdx = math.random(#Config.Menu.Tips)
tipLabel.Text = "TIP · " .. Config.Menu.Tips[tipIdx]
task.spawn(function()
    while boot.Parent and boot.Visible do
        task.wait(2.6)
        tipIdx = (tipIdx % #Config.Menu.Tips) + 1
        Util.tween(tipLabel, 0.3, { TextTransparency = 1 })
        task.wait(0.32)
        tipLabel.Text = "TIP · " .. Config.Menu.Tips[tipIdx]
        Util.tween(tipLabel, 0.3, { TextTransparency = 0 })
    end
end)

local menu = mk("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 30 }, gui)
local menuShade = mk("Frame", { BackgroundColor3 = C.Background, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), BorderSizePixel = 0 }, menu)
local menuTitle = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(0.42, 0.1), Position = UDim2.fromScale(0.06, 0.16),
    Font = Enum.Font.GothamBlack, Text = Config.GameName, TextScaled = true, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 31 }, menu)
local menuGrad = Instance.new("UIGradient")
menuGrad.Color = ColorSequence.new(C.Accent, C.AccentAlt, C.Text)
menuGrad.Parent = menuTitle
animateGradient(menuGrad, 0.3)
mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(0.42, 0.03), Position = UDim2.fromScale(0.062, 0.265),
    Font = Enum.Font.GothamBold, Text = Config.Tagline, TextScaled = true, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 31 }, menu)

local btnHolder = mk("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(0.24, 0.42), Position = UDim2.fromScale(0.06, 0.36), ZIndex = 31 }, menu)
mk("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, btnHolder)
local menuButtons = {}
local function menuButton(text, order, primary)
    local b = mk("TextButton", { BackgroundColor3 = primary and C.AccentAlt or C.Panel, BackgroundTransparency = primary and 0.15 or 0.25,
        Size = UDim2.new(1, 0, 0, 52), LayoutOrder = order, Font = Enum.Font.GothamBlack, TextSize = 18,
        Text = "  " .. text, TextColor3 = primary and Color3.new(1, 1, 1) or C.Text, TextXAlignment = Enum.TextXAlignment.Left,
        AutoButtonColor = false, ZIndex = 31 }, btnHolder)
    corner(b, 12); stroke(b, C.Stroke, 1.5, 0.3)
    buttonize(b)
    b.MouseEnter:Connect(function() sound(Config.Sounds.Click, 0.2, 1.2) end)
    table.insert(menuButtons, b)
    return b
end

mk("TextLabel", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.3, Size = UDim2.fromOffset(240, 26),
    Position = UDim2.new(0.06, 0, 1, -36), AnchorPoint = Vector2.new(0, 1), Font = Enum.Font.GothamBold, TextSize = 12,
    Text = "  " .. Config.Version .. " · farm fight rebirth", TextColor3 = C.Dim, ZIndex = 31 }, menu)

local hudRoot = mk("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 5 }, gui)

-- ══════════════════════════════════════════════════════════════════
-- HUD
-- ══════════════════════════════════════════════════════════════════
local topBar = mk("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 92), Position = UDim2.new(0, 0, 0, 10) }, hudRoot)
local cashPill = mk("Frame", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.06, Size = UDim2.fromOffset(250, 54), Position = UDim2.new(0.5, -125, 0, 0) }, topBar)
corner(cashPill, 27); stroke(cashPill, C.Stroke, 1.5, 0.35)
local icon = mk("Frame", { BackgroundColor3 = C.Accent, Size = UDim2.fromOffset(38, 38), Position = UDim2.new(0, 8, 0.5, -19) }, cashPill)
corner(icon, 19)
local iconScale = mk("UIScale", { Scale = 1 }, icon)
makeIcon(icon, "cash", Color3.fromRGB(12, 10, 20), C.Accent)
local cashText = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -64, 1, 0), Position = UDim2.new(0, 54, 0, 0),
    Font = Enum.Font.GothamBlack, Text = "$0", TextScaled = true, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Left }, cashPill)
local multChip = mk("TextLabel", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.1, Size = UDim2.fromOffset(280, 24),
    Position = UDim2.new(0.5, -140, 0, 60), Font = Enum.Font.GothamBold, Text = "", TextSize = 13, TextColor3 = C.Dim }, topBar)
corner(multChip, 12)
local streakChip = mk("TextLabel", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.1, Size = UDim2.fromOffset(150, 30),
    Position = UDim2.new(0.5, 170, 0, 12), Font = Enum.Font.GothamBlack, Text = "", TextSize = 15, TextColor3 = C.Danger, Visible = false }, topBar)
corner(streakChip, 15)

local function pulseCash()
    iconScale.Scale = 1.35
    Util.tween(iconScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
end
local function updateChips()
    local m = 1 + S.Rebirths * Config.Rebirth.PerkMult
    if S.Rebirths >= 5 then m = m * 1.2 end
    if S.Passes.DoubleCash then m = m * 2 end
    if S.Passes.QuadCash then m = m * 4 end
    if S.Passes.VIP then m = m * 1.1 end
    if S.Rain then m = m * Config.Income.RainMult end
    multChip.Text = string.format("x%.2f cash · %d rebirth%s%s", m, S.Rebirths, S.Rebirths == 1 and "" or "s", S.Rain and " · 💸 RAIN" or "")
    multChip.TextColor3 = S.Rain and C.Gold or C.Dim
    streakChip.Visible = S.Streak >= 2
    streakChip.Text = S.Streak .. " STREAK"
end

local crosshair = mk("Frame", { BackgroundColor3 = C.Text, BackgroundTransparency = 0.3, Size = UDim2.fromOffset(4, 4),
    Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 10 }, hudRoot)
corner(crosshair, 2)
local hitmark = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(40, 40), Position = UDim2.fromScale(0.5, 0.5),
    AnchorPoint = Vector2.new(0.5, 0.5), Font = Enum.Font.GothamBlack, Text = "✕", TextSize = 22, TextColor3 = C.Danger,
    TextTransparency = 1, ZIndex = 10 }, hudRoot)
local vignette = mk("Frame", { BackgroundColor3 = C.Danger, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 9, BorderSizePixel = 0 }, hudRoot)
mk("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.6, 1), NumberSequenceKeypoint.new(1, 0.4) }), Rotation = 90 }, vignette)

-- ── HOTBAR ────────────────────────────────────────────────────────
local hotbar = mk("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(430, 78),
    Position = UDim2.new(0.5, 0, 1, -14), AnchorPoint = Vector2.new(0.5, 1) }, hudRoot)
mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, hotbar)

local slots = {}
local SLOT_DEFS = {
    { Key = "Q", Label = "DASH" }, { Key = "Z" }, { Key = "X" }, { Key = "C" },
    { Key = "V", Label = "ULT" }, { Key = "F", Label = "BLOCK" },
}
for order, def in ipairs(SLOT_DEFS) do
    local slot = mk("TextButton", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.08, Size = UDim2.fromOffset(62, 62), LayoutOrder = order,
        Text = "", AutoButtonColor = false }, hotbar)
    corner(slot, 14); stroke(slot, C.Stroke, 1.5, 0.35)
    mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, 4),
        Font = Enum.Font.GothamBlack, Text = def.Key, TextSize = 16, TextColor3 = C.Text }, slot)
    local nameLbl = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -4, 0, 14), Position = UDim2.new(0, 2, 1, -18),
        Font = Enum.Font.GothamBold, Text = def.Label or "", TextSize = 9, TextColor3 = C.Dim }, slot)
    local cdFill = mk("Frame", { BackgroundColor3 = C.Background, BackgroundTransparency = 0.35, Size = UDim2.new(1, 0, 1, 0),
        Position = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0, ZIndex = 2 }, slot)
    corner(cdFill, 14)
    local dashPips = mk("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 6), Position = UDim2.new(0, 4, 0, 26) }, slot)
    mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3) }, dashPips)
    for i = 1, Config.Dash.SurgeCharges do
        mk("Frame", { BackgroundColor3 = C.AccentAlt, Size = UDim2.new(1 / Config.Dash.SurgeCharges, -3, 1, 0) }, dashPips)
    end
    local ultFill = mk("Frame", { BackgroundColor3 = C.Gold, BackgroundTransparency = 0.25, Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0, ZIndex = 2 }, slot)
    corner(ultFill, 14)
    slots[def.Key] = { Frame = slot, Name = nameLbl, Cd = cdFill, Ult = ultFill, Pips = dashPips, EndsAt = 0, Total = 1 }
end

local function updateDashPips(dash)
    local i = 0
    for _, f in ipairs(slots.Q.Pips:GetChildren()) do
        if f:IsA("Frame") then
            i += 1
            f.Visible = i <= S.DashMax
            f.BackgroundTransparency = i <= dash and 0 or 0.75
        end
    end
end

local function setBlockVisual(on)
    local f = slots.F.Frame
    f.BackgroundTransparency = on and 0 or 0.08
    f.BackgroundColor3 = on and C.AccentAlt or C.Panel
end

-- every slot wired exactly once
slots.Q.Frame.Activated:Connect(function() if S.Played then sendAim() fireDash() end end)
slots.Z.Frame.Activated:Connect(function() if S.Played then sendAim() fireSkill(1) end end)
slots.X.Frame.Activated:Connect(function() if S.Played then sendAim() fireSkill(2) end end)
slots.C.Frame.Activated:Connect(function() if S.Played then sendAim() fireSkill(3) end end)
slots.V.Frame.Activated:Connect(function() if S.Played then sendAim() fireUlt() end end)
slots.F.Frame.Activated:Connect(function()
    if not S.Played then return end
    blockActive = not blockActive
    RE:FireServer("Block", blockActive)
    setBlockVisual(blockActive)
end)

local weaponLabel = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(300, 22), Position = UDim2.new(0.5, 0, 1, -100),
    AnchorPoint = Vector2.new(0.5, 0), Font = Enum.Font.GothamBlack, Text = "", TextSize = 16, TextColor3 = C.Text }, hudRoot)

local function refreshHotbar()
    local w = Config.Weapons[S.Equipped]
    if not w then return end
    weaponLabel.Text = w.Name .. "  ·  " .. w.Rarity
    weaponLabel.TextColor3 = w.Color
    for key, slot in pairs(slots) do
        if key == "Z" or key == "X" or key == "C" then
            local idx = ({ Z = 1, X = 2, C = 3 })[key]
            local sk = w.Skills and w.Skills[idx]
            slot.Name.Text = sk and sk.Name or "—"
        elseif key == "V" then
            slot.Name.Text = w.Ult and w.Ult.Name or "—"
        end
    end
end

-- ── MOBILE CONTROL CLUSTER ────────────────────────────────────────
if IS_TOUCH then
    local mobileCluster = mk("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(220, 220),
        Position = UDim2.new(1, -18, 1, -110), AnchorPoint = Vector2.new(1, 1) }, hudRoot)
    local attackBtn = mk("TextButton", { BackgroundColor3 = C.AccentAlt, BackgroundTransparency = 0.15, Size = UDim2.fromOffset(96, 96),
        Position = UDim2.new(1, -8, 1, -8), AnchorPoint = Vector2.new(1, 1), Font = Enum.Font.GothamBlack, TextSize = 22,
        Text = "HIT", TextColor3 = Color3.new(1, 1, 1), AutoButtonColor = false }, mobileCluster)
    corner(attackBtn, 48); stroke(attackBtn, C.Stroke, 2, 0.2)
    local runBtn = mk("TextButton", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.1, Size = UDim2.fromOffset(64, 64),
        Position = UDim2.new(1, -24, 1, -120), AnchorPoint = Vector2.new(1, 1), Font = Enum.Font.GothamBlack, TextSize = 16,
        Text = "RUN", TextColor3 = C.Dim, AutoButtonColor = false }, mobileCluster)
    corner(runBtn, 32); stroke(runBtn, C.Stroke, 1.5, 0.35)
    runBtn.Activated:Connect(function()
        setSprint(not sprinting)
        runBtn.TextColor3 = sprinting and C.Accent or C.Dim
        runBtn.BackgroundTransparency = sprinting and 0 or 0.1
    end)
    local m1Held = false
    attackBtn.InputBegan:Connect(function(io)
        if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
            if not m1Held then
                m1Held = true
                task.spawn(function()
                    while m1Held and S.Played do
                        sendAim()
                        fireM1()
                        task.wait(0.16)
                    end
                end)
            end
        end
    end)
    attackBtn.InputEnded:Connect(function(io)
        if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
            m1Held = false
        end
    end)
end

-- ── feed / notifications / panels ─────────────────────────────────
local feed = mk("Frame", { BackgroundTransparency = 1, Position = UDim2.new(1, -16, 0, 100), AnchorPoint = Vector2.new(1, 0), Size = UDim2.new(0, 300, 0, 300) }, hudRoot)
mk("UIListLayout", { Padding = UDim.new(0, 5), HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder }, feed)
local notifyHolder = mk("Frame", { BackgroundTransparency = 1, Position = UDim2.new(1, -16, 0, 420), AnchorPoint = Vector2.new(1, 0), Size = UDim2.new(0, 320, 0, 300) }, hudRoot)
mk("UIListLayout", { Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder }, notifyHolder)

local function notify(msg, color)
    local item = mk("CanvasGroup", { Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.08, GroupTransparency = 1 }, notifyHolder)
    corner(item, 10); stroke(item, color or C.Accent, 1, 0.35)
    mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -24, 1, 0), Position = UDim2.new(0, 12, 0, 0),
        Font = Enum.Font.GothamBold, Text = msg, TextSize = 13, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true }, item)
    local us = mk("UIScale", { Scale = 0.9 }, item)
    Util.tween(us, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
    Util.tween(item, 0.28, { GroupTransparency = 0 })
    task.delay(3.2, function()
        Util.tween(item, 0.3, { GroupTransparency = 1 }); task.wait(0.32); item:Destroy()
    end)
end

local sideBar = mk("Frame", { BackgroundTransparency = 1, Position = UDim2.new(1, -16, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.fromOffset(64, 240) }, hudRoot)
mk("UIListLayout", { Padding = UDim.new(0, 12), HorizontalAlignment = Enum.HorizontalAlignment.Center }, sideBar)
local function sideButton(kind, order)
    local btn = mk("TextButton", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.08, Size = UDim2.fromOffset(56, 56),
        LayoutOrder = order, Text = "", AutoButtonColor = false }, sideBar)
    corner(btn, 16); stroke(btn, C.Stroke, 1.5, 0.35)
    makeIcon(btn, kind, C.Text, C.Panel)
    buttonize(btn)
    btn.MouseEnter:Connect(function() sound(Config.Sounds.Click, 0.15, 1.3) end)
    return btn
end
local shopBtn = sideButton("shop", 1)
local rebirthBtn = sideButton("rebirth", 2)
local settingsBtn = sideButton("gear", 3)
local helpBtn = sideButton("help", 4)

local activePanel
local function makePanel(title, size)
    local p = mk("CanvasGroup", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.04, Size = size,
        Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, GroupTransparency = 1, ZIndex = 20 }, gui)
    corner(p, 16); stroke(p, C.Stroke, 1.5, 0.3)
    mk("UIScale", { Scale = 0.9 }, p)
    local header = mk("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52) }, p)
    mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -64, 1, 0), Position = UDim2.new(0, 18, 0, 0),
        Font = Enum.Font.GothamBlack, Text = title, TextSize = 22, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Left }, header)
    local close = mk("TextButton", { BackgroundTransparency = 1, Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -46, 0.5, -20),
        Font = Enum.Font.GothamBold, Text = "✕", TextSize = 18, TextColor3 = C.Dim }, header)
    buttonize(close)
    close.Activated:Connect(function()
        activePanel = nil
        Util.tween(p, 0.2, { GroupTransparency = 1 })
        Util.tween(p:FindFirstChildOfClass("UIScale"), 0.2, { Scale = 0.9 })
        task.delay(0.22, function() p.Visible = false end)
    end)
    return p
end

local shopPanel = makePanel("ARMORY", UDim2.fromOffset(520, 540))
local rebirthPanel = makePanel("REBIRTH", UDim2.fromOffset(430, 470))
local settingsPanel = makePanel("SETTINGS", UDim2.fromOffset(420, 500))
local helpPanel = makePanel("CONTROLS", UDim2.fromOffset(420, 340))
local creditsPanel = makePanel("CREDITS", UDim2.fromOffset(380, 220))

local function showPanel(p)
    if activePanel and activePanel ~= p then activePanel.Visible = false end
    activePanel = p
    p.Visible = true
    local us = p:FindFirstChildOfClass("UIScale")
    p.GroupTransparency = 1; us.Scale = 0.88
    Util.tween(p, 0.3, { GroupTransparency = 0 })
    Util.tween(us, 0.32, { Scale = 1 }, Enum.EasingStyle.Back)
    sound(Config.Sounds.Click, 0.25)
end
local function togglePanel(p)
    if activePanel == p then
        activePanel = nil
        Util.tween(p, 0.2, { GroupTransparency = 1 })
        Util.tween(p:FindFirstChildOfClass("UIScale"), 0.2, { Scale = 0.9 })
        task.delay(0.22, function() p.Visible = false end)
    else showPanel(p) end
end

local tabRow = mk("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -28, 0, 36), Position = UDim2.new(0, 14, 0, 52) }, shopPanel)
mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, tabRow)
local shopScroll = mk("ScrollingFrame", { BackgroundTransparency = 1, Position = UDim2.new(0, 14, 0, 94), Size = UDim2.new(1, -28, 1, -108),
    CanvasSize = UDim2.new(), ScrollBarThickness = 4, ScrollBarImageColor3 = C.Accent, BorderSizePixel = 0 }, shopPanel)
mk("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, shopScroll)

local TABS = { "Weapons", "Vehicles", "Extractors", "Passes" }
local currentTab = "Weapons"
local tabButtons = {}

local function renderShop()
    for _, ch in ipairs(shopScroll:GetChildren()) do if ch:IsA("Frame") then ch:Destroy() end end
    local rows = 0
    if currentTab == "Weapons" then
        for order, wid in ipairs(Config.WeaponOrder) do
            local w = Config.Weapons[wid]
            local owned = S.Weapons[wid] == true
            local equipped = S.Equipped == wid
            rows += 1
            local row = mk("Frame", { BackgroundColor3 = C.Background, BackgroundTransparency = 0.25, Size = UDim2.new(1, -8, 0, 58), LayoutOrder = order }, shopScroll)
            corner(row, 10)
            mk("Frame", { BackgroundColor3 = w.Color, Size = UDim2.fromOffset(6, 38), Position = UDim2.new(0, 8, 0.5, -19) }, row)
            mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -220, 0, 24), Position = UDim2.new(0, 24, 0, 6),
                Font = Enum.Font.GothamBold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left,
                TextColor3 = owned and w.Color or C.Text, Text = w.Name .. "  ·  " .. w.Rarity }, row)
            mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -220, 0, 18), Position = UDim2.new(0, 24, 0, 30),
                Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Dim,
                Text = w.Ult.Name .. " (ult) · " .. #w.Skills .. " skills" }, row)
            local btn = mk("TextButton", { BackgroundColor3 = C.AccentAlt, BackgroundTransparency = equipped and 0.5 or 0,
                Size = UDim2.fromOffset(110, 36), Position = UDim2.new(1, -122, 0.5, -18),
                Font = Enum.Font.GothamBlack, TextSize = 14, AutoButtonColor = false,
                Text = equipped and "EQUIPPED" or (owned and "EQUIP" or Util.cash(w.Price)),
                TextColor3 = equipped and C.Dim or Color3.new(1, 1, 1) }, row)
            corner(btn, 8); buttonize(btn)
            btn.Activated:Connect(function()
                if equipped then return end
                local res = owned and RF:InvokeServer("Equip", wid) or RF:InvokeServer("BuyWeapon", wid)
                if res and res.ok then
                    sound(Config.Sounds.Buy, 0.5); pulseCash()
                    if not owned then S.Weapons[wid] = true end
                    S.Equipped = wid
                    refreshHotbar(); renderShop()
                else sound(Config.Sounds.Error, 0.4) end
            end)
        end
    elseif currentTab == "Vehicles" then
        local order = 0
        for vid, v in pairs(Config.Vehicles) do
            order += 1; rows += 1
            local owned = S.Vehicles[vid] == true
            local row = mk("Frame", { BackgroundColor3 = C.Background, BackgroundTransparency = 0.25, Size = UDim2.new(1, -8, 0, 58), LayoutOrder = order }, shopScroll)
            corner(row, 10)
            mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -220, 0, 24), Position = UDim2.new(0, 14, 0, 6),
                Font = Enum.Font.GothamBold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Text,
                Text = v.Name .. "  ·  " .. v.Seats .. " seat" .. (v.Seats > 1 and "s" or "") }, row)
            mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -220, 0, 18), Position = UDim2.new(0, 14, 0, 30),
                Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Dim,
                Text = "speed " .. v.Speed .. (v.ContactDmg and (" · contact dmg " .. v.ContactDmg) or "") }, row)
            local btn = mk("TextButton", { BackgroundColor3 = owned and C.Gold or C.AccentAlt, Size = UDim2.fromOffset(110, 36),
                Position = UDim2.new(1, -122, 0.5, -18), Font = Enum.Font.GothamBlack, TextSize = 14, AutoButtonColor = false,
                Text = owned and "SUMMON" or Util.cash(v.Price), TextColor3 = owned and Color3.fromRGB(20, 16, 4) or Color3.new(1, 1, 1) }, row)
            corner(btn, 8); buttonize(btn)
            btn.Activated:Connect(function()
                if owned then RF:InvokeServer("Summon", vid)
                else
                    local res = RF:InvokeServer("BuyVehicle", vid)
                    if res and res.ok then S.Vehicles[vid] = true; sound(Config.Sounds.Buy, 0.5); pulseCash(); renderShop() end
                end
            end)
        end
    elseif currentTab == "Extractors" then
        if not S.Claimed then
            mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 60), Font = Enum.Font.GothamBold, TextSize = 15,
                TextColor3 = C.Dim, Text = "Claim a plot first — look for the glowing CLAIM pad.", TextWrapped = true }, shopScroll)
        end
        for order, d in ipairs(Config.Droppers) do
            local owned = S.Droppers[d.Id] == true
            rows += 1
            local row = mk("Frame", { BackgroundColor3 = C.Background, BackgroundTransparency = 0.25, Size = UDim2.new(1, -8, 0, 52), LayoutOrder = order }, shopScroll)
            corner(row, 10)
            mk("Frame", { BackgroundColor3 = d.Color, Size = UDim2.fromOffset(6, 32), Position = UDim2.new(0, 8, 0.5, -16) }, row)
            mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -220, 0, 22), Position = UDim2.new(0, 24, 0, 4),
                Font = Enum.Font.GothamBold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Text = d.Name,
                TextColor3 = owned and d.Color or C.Text }, row)
            mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -220, 0, 18), Position = UDim2.new(0, 24, 0, 26),
                Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Dim,
                Text = "$" .. Util.abbrev(d.Value) .. " / " .. d.Interval .. "s" }, row)
            if not owned then
                local btn = mk("TextButton", { BackgroundColor3 = C.AccentAlt, Size = UDim2.fromOffset(110, 34), Position = UDim2.new(1, -122, 0.5, -17),
                    Font = Enum.Font.GothamBlack, TextSize = 13, Text = Util.cash(d.Cost), TextColor3 = Color3.new(1, 1, 1), AutoButtonColor = false }, row)
                corner(btn, 8); buttonize(btn)
                btn.Activated:Connect(function()
                    local res = RF:InvokeServer("BuyDropper", d.Id)
                    if res and res.ok then S.Droppers[d.Id] = true; sound(Config.Sounds.Buy, 0.5); pulseCash(); renderShop()
                    else sound(Config.Sounds.Error, 0.4) end
                end)
            else
                mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(110, 34), Position = UDim2.new(1, -122, 0.5, -17),
                    Font = Enum.Font.GothamBlack, TextSize = 13, Text = "ONLINE", TextColor3 = d.Color }, row)
            end
        end
    elseif currentTab == "Passes" then
        local order = 0
        for pid, def in pairs(Config.Gamepasses) do
            order += 1; rows += 1
            local owned = S.Passes[pid] == true
            local row = mk("Frame", { BackgroundColor3 = C.Background, BackgroundTransparency = 0.25, Size = UDim2.new(1, -8, 0, 64), LayoutOrder = order }, shopScroll)
            corner(row, 10)
            mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -220, 0, 24), Position = UDim2.new(0, 14, 0, 6),
                Font = Enum.Font.GothamBold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left,
                TextColor3 = owned and C.Gold or C.Text, Text = def.Name }, row)
            mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -220, 0, 28), Position = UDim2.new(0, 14, 0, 30),
                Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Dim, TextWrapped = true, Text = def.Desc }, row)
            local isBig = (pid == "KillAll" or pid == "Nuke")
            local btn = mk("TextButton", { BackgroundColor3 = (owned and isBig) and C.Danger or C.AccentAlt, BackgroundTransparency = (owned and not isBig) and 0.5 or 0,
                Size = UDim2.fromOffset(110, 36), Position = UDim2.new(1, -122, 0.5, -18), Font = Enum.Font.GothamBlack, TextSize = 13, AutoButtonColor = false,
                Text = isBig and (owned and "ACTIVATE" or ("R$" .. def.Price)) or (owned and "✓ OWNED" or ("R$" .. def.Price)),
                TextColor3 = (owned and not isBig) and C.Gold or Color3.new(1, 1, 1) }, row)
            corner(btn, 8); buttonize(btn)
            btn.Activated:Connect(function()
                if owned and isBig then
                    local res = RF:InvokeServer("Activate", pid)
                    if res and res.Result == "cd" then notify("Ability on cooldown.", C.Danger)
                    elseif res and res.Result == "no-pass" then notify("Pass not owned.", C.Danger) end
                elseif not owned then
                    RF:InvokeServer("PromptPass", pid)
                end
            end)
        end
    end
    shopScroll.CanvasSize = UDim2.new(0, 0, 0, rows * 70 + 10)
end

for i, tabName in ipairs(TABS) do
    local tb = mk("TextButton", { BackgroundColor3 = C.Background, BackgroundTransparency = 0.3, Size = UDim2.fromOffset(110, 34),
        LayoutOrder = i, Font = Enum.Font.GothamBlack, Text = tabName:upper(), TextSize = 13, TextColor3 = C.Dim, AutoButtonColor = false }, tabRow)
    corner(tb, 8)
    tabButtons[tabName] = tb
    tb.Activated:Connect(function()
        currentTab = tabName
        for name, b in pairs(tabButtons) do
            b.BackgroundTransparency = name == currentTab and 0 or 0.3
            b.TextColor3 = name == currentTab and C.Accent or C.Dim
        end
        renderShop()
    end)
end
shopBtn.Activated:Connect(function() togglePanel(shopPanel) renderShop() end)

local rebInfo = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -36, 0, 110), Position = UDim2.new(0, 18, 0, 56),
    Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = C.Text, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
    TextXAlignment = Enum.TextXAlignment.Left }, rebirthPanel)
local rebScroll = mk("ScrollingFrame", { BackgroundTransparency = 1, Position = UDim2.new(0, 18, 0, 170), Size = UDim2.new(1, -36, 1, -260),
    CanvasSize = UDim2.new(), ScrollBarThickness = 3, ScrollBarImageColor3 = C.Accent, BorderSizePixel = 0 }, rebirthPanel)
mk("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, rebScroll)
local rebButton = mk("TextButton", { BackgroundColor3 = C.Background, Size = UDim2.new(1, -36, 0, 52), Position = UDim2.new(0, 18, 1, -70),
    Font = Enum.Font.GothamBlack, TextSize = 18, TextColor3 = C.Dim, Text = "REBIRTH", AutoButtonColor = false }, rebirthPanel)
corner(rebButton, 12); buttonize(rebButton)

local function renderRebirth()
    local cost = Config.Rebirth.BaseCost * (Config.Rebirth.CostMult ^ S.Rebirths)
    rebInfo.Text = string.format("Reset cash + extractors. Keep weapons, vehicles, passes.\nNow x%.2f → next x%.2f cash · Cost $%s",
        1 + S.Rebirths * Config.Rebirth.PerkMult, 1 + (S.Rebirths + 1) * Config.Rebirth.PerkMult, Util.abbrev(cost))
    for _, ch in ipairs(rebScroll:GetChildren()) do if ch:IsA("Frame") then ch:Destroy() end end
    local n = 0
    for tier, u in ipairs(Config.RebirthUnlocks) do
        n += 1
        local have = S.Rebirths >= tier
        local row = mk("Frame", { BackgroundColor3 = C.Background, BackgroundTransparency = 0.25, Size = UDim2.new(1, -4, 0, 46), LayoutOrder = tier }, rebScroll)
        corner(row, 8)
        mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(44, 30), Position = UDim2.new(0, 8, 0.5, -15),
            Font = Enum.Font.GothamBlack, TextSize = 14, Text = "R" .. tier,
            TextColor3 = have and C.Purple or C.Dim }, row)
        mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -130, 0, 20), Position = UDim2.new(0, 56, 0, 4),
            Font = Enum.Font.GothamBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = have and C.Text or C.Dim, Text = u.Name }, row)
        mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -130, 0, 16), Position = UDim2.new(0, 56, 0, 24),
            Font = Enum.Font.Gotham, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = C.Dim, Text = u.Desc, TextTruncate = Enum.TextTruncate.AtEnd }, row)
        mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(60, 30), Position = UDim2.new(1, -66, 0.5, -15),
            Font = Enum.Font.GothamBlack, TextSize = 12, Text = have and "✓" or "LOCKED",
            TextColor3 = have and C.Accent or C.Dim }, row)
    end
    rebScroll.CanvasSize = UDim2.new(0, 0, 0, n * 51)
    local can = S.Cash >= cost
    rebButton.Text = can and "REBIRTH NOW" or ("NEED $" .. Util.abbrev(cost))
    rebButton.BackgroundColor3 = can and C.Gold or C.Background
    rebButton.TextColor3 = can and Color3.fromRGB(20, 16, 4) or C.Dim
end
rebButton.Activated:Connect(function()
    local res = RF:InvokeServer("Rebirth")
    if res and res.ok then sound(Config.Sounds.Rebirth, 0.6); togglePanel(rebirthPanel)
    else sound(Config.Sounds.Error, 0.4) end
end)
rebirthBtn.Activated:Connect(function() togglePanel(rebirthPanel) renderRebirth() end)

local fpsLabel = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(90, 20), Position = UDim2.new(0, 12, 0, 12),
    Font = Enum.Font.GothamBold, Text = "", TextSize = 13, TextColor3 = C.Dim, Visible = false, ZIndex = 10 }, hudRoot)
local musicSound
local applyFns = {}
local function applySetting(key, value) if applyFns[key] then applyFns[key](value) end end
applyFns.Music = function(v) if musicSound then musicSound.Volume = v end end
applyFns.FOV = function(v) baseFOV = v end
applyFns.FPS = function(v) fpsLabel.Visible = v end
applyFns.UIScale = function(v) Util.tween(guiScale, 0.2, { Scale = v }) end

do
    local y = 0
    for _, def in ipairs(Config.Settings) do
        local lbl = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -36, 0, 22), Position = UDim2.new(0, 18, 0, 60 + y),
            Font = Enum.Font.GothamBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Text, Text = def.Label }, settingsPanel)
        if def.Max then
            local sliderBack = mk("Frame", { BackgroundColor3 = C.Background, Size = UDim2.new(1, -130, 0, 10), Position = UDim2.new(0, 18, 0, 32) }, lbl)
            corner(sliderBack, 5)
            local fill = mk("Frame", { BackgroundColor3 = C.Accent, Size = UDim2.new((S.Settings[def.Key] - def.Min) / (def.Max - def.Min), 0, 1, 0) }, sliderBack)
            corner(fill, 5)
            local val = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(60, 22), Position = UDim2.new(1, 12, -0.1, 0),
                Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.Dim, Text = tostring(S.Settings[def.Key]) }, lbl)
            local dragging = false
            sliderBack.InputBegan:Connect(function(io)
                if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then dragging = true end
            end)
            UserInputService.InputEnded:Connect(function(io) -- sliders persist on drag release
                if io.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
                    dragging = false
                    RF:InvokeServer("SetSetting", { Key = def.Key, Value = S.Settings[def.Key] })
                end
            end)
            RunService.RenderStepped:Connect(function()
                if dragging then
                    local mx = math.clamp((UserInputService:GetMouseLocation().X - sliderBack.AbsolutePosition.X) / math.max(sliderBack.AbsoluteSize.X, 1), 0, 1)
                    local v = math.floor((def.Min + mx * (def.Max - def.Min)) * 100 + 0.5) / 100
                    fill.Size = UDim2.new(mx, 0, 1, 0)
                    val.Text = tostring(v)
                    S.Settings[def.Key] = v
                    applySetting(def.Key, v)
                end
            end)
            y += 46
        else
            local toggle = mk("TextButton", { BackgroundColor3 = S.Settings[def.Key] and C.Accent or C.Background,
                BackgroundTransparency = S.Settings[def.Key] and 0 or 0.4, Size = UDim2.fromOffset(56, 26), Position = UDim2.new(1, -56, -0.2, 0),
                Font = Enum.Font.GothamBlack, TextSize = 12, Text = S.Settings[def.Key] and "ON" or "OFF",
                TextColor3 = S.Settings[def.Key] and Color3.fromRGB(12, 10, 20) or C.Dim, AutoButtonColor = false }, lbl)
            corner(toggle, 13)
            toggle.Activated:Connect(function()
                S.Settings[def.Key] = not S.Settings[def.Key]
                toggle.Text = S.Settings[def.Key] and "ON" or "OFF"
                toggle.BackgroundColor3 = S.Settings[def.Key] and C.Accent or C.Background
                toggle.BackgroundTransparency = S.Settings[def.Key] and 0 or 0.4
                toggle.TextColor3 = S.Settings[def.Key] and Color3.fromRGB(12, 10, 20) or C.Dim
                applySetting(def.Key, S.Settings[def.Key])
                RF:InvokeServer("SetSetting", { Key = def.Key, Value = S.Settings[def.Key] })
            end)
            y += 40
        end
    end
end
settingsBtn.Activated:Connect(function() togglePanel(settingsPanel) end)

do
    mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -36, 1, -70), Position = UDim2.new(0, 18, 0, 58),
        Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = C.Text, Text = table.concat(Config.Controls, "\n"), TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top, TextXAlignment = Enum.TextXAlignment.Left, LineHeight = 1.5 }, helpPanel)
    mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -36, 1, -70), Position = UDim2.new(0, 18, 0, 30),
        Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = C.Dim, Text = Config.Menu.Credits, TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Center }, creditsPanel)
end
helpBtn.Activated:Connect(function() togglePanel(helpPanel) end)

if Config.MusicId ~= "" then
    musicSound = Instance.new("Sound")
    musicSound.SoundId = Config.MusicId; musicSound.Looped = true
    musicSound.Volume = S.Settings.Music or 0.4
    musicSound.Parent = SoundService; musicSound:Play()
end

-- ── KEYBOARD INPUT ────────────────────────────────────────────────
local lastTapKey, lastTapTime = nil, 0

UserInputService.InputBegan:Connect(function(io, gp)
    if gp then return end
    if not S.Played then return end
    if io.UserInputType == Enum.UserInputType.MouseButton1 then
        sendAim(); fireM1()
    elseif io.KeyCode == Enum.KeyCode.Q then
        sendAim(); fireDash()
    elseif io.KeyCode == Enum.KeyCode.Z then sendAim(); fireSkill(1)
    elseif io.KeyCode == Enum.KeyCode.X then sendAim(); fireSkill(2)
    elseif io.KeyCode == Enum.KeyCode.C then sendAim(); fireSkill(3)
    elseif io.KeyCode == Enum.KeyCode.V then sendAim(); fireUlt()
    elseif io.KeyCode == Enum.KeyCode.F then
        blockActive = true
        RE:FireServer("Block", true)
        setBlockVisual(true)
    elseif io.KeyCode == Enum.KeyCode.LeftShift then
        setSprint(true)
    elseif io.KeyCode == Enum.KeyCode.W or io.KeyCode == Enum.KeyCode.A or io.KeyCode == Enum.KeyCode.S or io.KeyCode == Enum.KeyCode.D then
        local now = os.clock()
        if io.KeyCode == lastTapKey and now - lastTapTime < 0.28 then
            sendAim(); fireDash()
            lastTapKey = nil
        else
            lastTapKey = io.KeyCode; lastTapTime = now
        end
    else
        local n = io.KeyCode.Value
        if n >= Enum.KeyCode.One.Value and n <= Enum.KeyCode.Seven.Value then
            local wid = Config.WeaponOrder[n - Enum.KeyCode.One.Value + 1]
            if wid and S.Weapons[wid] and S.Equipped ~= wid then
                local res = RF:InvokeServer("Equip", wid)
                if res and res.ok then S.Equipped = wid; refreshHotbar() end
            end
        end
    end
end)
UserInputService.InputEnded:Connect(function(io)
    if io.KeyCode == Enum.KeyCode.F and blockActive then
        blockActive = false
        RE:FireServer("Block", false)
        setBlockVisual(false)
    end
    if io.KeyCode == Enum.KeyCode.LeftShift then setSprint(false) end
end)

-- footstep dust + dash trail (no RE listeners here — Dashed handled once below)
do
    local charConns = {}
    local function wireChar(ch)
        for _, c in ipairs(charConns) do c:Disconnect() end
        charConns = {}
        local hrp = ch:WaitForChild("HumanoidRootPart", 5)
        local hum = ch:WaitForChild("Humanoid", 5)
        if not hrp or not hum then return end
        local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, 1, 0); a0.Parent = hrp
        local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -1, 0); a1.Parent = hrp
        local trail = Instance.new("Trail")
        trail.Name = "DashTrail"
        trail.Attachment0 = a0; trail.Attachment1 = a1
        trail.Color = ColorSequence.new(C.AccentAlt, C.Deep)
        trail.Transparency = NumberSequence.new(0.2, 1)
        trail.Lifetime = 0.25; trail.LightEmission = 0.8; trail.Enabled = false
        trail.Parent = hrp
        table.insert(charConns, hum.StateChanged:Connect(function(_, new)
            if new == Enum.HumanoidStateType.Landed then shake(0.3, 0.12) end
        end))
    end
    if player.Character then wireChar(player.Character) end
    player.CharacterAdded:Connect(function(ch)
        wireChar(ch)
        RigCache[ch] = nil
    end)
    local lastStep = 0
    task.spawn(function()
        while true do
            task.wait(0.1)
            local ch = player.Character
            local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
            local hum = ch and ch:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.FloorMaterial ~= Enum.Material.Air then
                local flat = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z).Magnitude
                if flat > 20 and os.clock() - lastStep > 0.28 then
                    lastStep = os.clock()
                    local pe = hrp:FindFirstChild("StepDust")
                    if not pe then
                        pe = Instance.new("ParticleEmitter")
                        pe.Name = "StepDust"; pe.Enabled = false
                        pe.Lifetime = NumberRange.new(0.3, 0.6); pe.Speed = NumberRange.new(1, 3)
                        pe.SpreadAngle = Vector2.new(60, 60); pe.Size = NumberSequence.new(0.5, 0)
                        pe.Color = ColorSequence.new(C.Deep); pe.Transparency = NumberSequence.new(0.4, 1)
                        pe.Parent = hrp
                    end
                    pe:Emit(2)
                end
            end
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- RE HANDLER
-- ══════════════════════════════════════════════════════════════════
RE.OnClientEvent:Connect(function(ev, data)
    if ev == "FX" then
        local fn = FXBANK[data.Type]
        if fn then fn(data) end
    elseif ev == "Dashed" then
        local ch = player.Character
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        local trail = hrp and hrp:FindFirstChild("DashTrail")
        if trail then
            trail.Enabled = true
            task.delay(0.35, function() trail.Enabled = false end)
        end
    elseif ev == "DamageNum" then
        if S.Settings.DmgNums ~= false then
            spawnDmgNum(data.Pos, tostring(data.Amount), data.Color or (data.Crit and C.Gold) or C.Danger, data.Crit)
        end
    elseif ev == "Notify" then
        notify(data.Msg, data.Color)
    elseif ev == "BlockState" then
        blockActive = data == true
        setBlockVisual(blockActive)
    elseif ev == "Claimed" then
        S.Claimed = data
        if activePanel == shopPanel and currentTab == "Extractors" then renderShop() end
    elseif ev == "DashCharge" then
        S.Dash = data
        updateDashPips(data)
    elseif ev == "Cine" then
        if data.Kind == "Ult" then
            if S.Settings.Cine ~= false then letterbox(true, 0.25) end
            banner("⚡ " .. data.Who .. " — " .. data.Name, data.Color or C.AccentAlt, Config.Cine.UltBanner)
            task.delay(0.9, function() if S.Settings.Cine ~= false then letterbox(false, 0.35) end end)
            if data.Who == player.Name then shake(0.7, 0.3) end
        elseif data.Kind == "Nuke" then
            if S.Settings.Cine ~= false then letterbox(true, 0.5) cineCamera("Nuke", (data.T or 8) + 1.5) end
            banner("☢ NUKE INBOUND — " .. data.Who, C.Danger, data.T or 8)
        elseif data.Kind == "KillAll" then
            if S.Settings.Cine ~= false then letterbox(true, 0.5) cineCamera("KillAll", (data.T or 5) + 1.2) end
            banner("⚠ KILL ALL — " .. data.Who, C.Danger, data.T or 5)
        elseif data.Kind == "Rebirth" then
            banner("★ " .. data.Who .. " REBIRTH " .. data.N, C.Gold, 2.5)
        end
    elseif ev == "OpenShop" then
        if S.Played then
            if data then currentTab = data end
            togglePanel(shopPanel); renderShop()
            for name, b in pairs(tabButtons) do
                b.BackgroundTransparency = name == currentTab and 0 or 0.3
                b.TextColor3 = name == currentTab and C.Accent or C.Dim
            end
        end
    elseif ev == "Hit" then
        hitmark.TextTransparency = 0
        hitmark.TextSize = 26
        Util.tween(hitmark, 0.25, { TextTransparency = 1, TextSize = 18 })
        sound(Config.Sounds.Hit, 0.35, 1 + math.random() * 0.15)
        shake(0.15, 0.08)
    elseif ev == "KillPop" then
        notify("KILLED " .. data.Name .. "  ·  +" .. Util.cash(data.Cash) .. (data.Streak > 1 and ("  ·  " .. data.Streak .. " streak") or ""), C.Danger)
        sound(Config.Sounds.Kill, 0.5, 1.1)
        shake(0.5, 0.2)
    elseif ev == "KillFeed" then
        local item = mk("TextLabel", { Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.35,
            Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.Text,
            Text = data.Killer .. "  ⚔  " .. data.Victim .. (data.Streak > 1 and ("  ·  x" .. data.Streak) or "") }, feed)
        corner(item, 6)
        task.delay(4, function() item:Destroy() end)
    elseif ev == "SkillUsed" then
        local slot = slots[data.Key]
        if slot then slot.EndsAt = os.clock() + data.Cd; slot.Total = data.Cd end
    elseif ev == "Combat" then
        S.Dash = data.Dash
        S.DashMax = data.DashMax or S.DashMax
        updateDashPips(data.Dash)
        local v = slots.V
        local frac = math.clamp(data.Ult / Config.UltMax, 0, 1)
        v.Ult.Size = UDim2.new(1, 0, frac, 0)
        v.Ult.Position = UDim2.new(0, 0, 1 - frac, 0)
        if data.Ult >= Config.UltMax and S.Ult < Config.UltMax then sound(Config.Sounds.Rebirth, 0.4, 1.4) end
        S.Ult = data.Ult
    elseif ev == "Passes" then
        S.Passes = data or {}
        updateChips()
        if S.Passes.VIP then
            TextChatService.OnIncomingMessage = function(message)
                local props = Instance.new("TextChatMessageProperties")
                props.PrefixText = "<font color='#FFD24A'><b>[VIP]</b></font> " .. message.PrefixText
                return props
            end
        end
    elseif ev == "Siren" then
        sound(Config.Sounds.Siren, 0.7)
        shake(0.4, data or 5)
    elseif ev == "Rain" then
        S.Rain = data
        updateChips()
        if data then
            sound(Config.Sounds.Coin, 0.5, 1.2)
            task.spawn(function()
                for i = 1, 26 do
                    local p = Instance.new("Part")
                    p.Size = Vector3.new(0.8, 0.8, 0.8)
                    p.Material = Enum.Material.Neon
                    p.Color = C.Gold
                    p.CFrame = CFrame.new((math.random() - 0.5) * 260, 90 + math.random() * 40, (math.random() - 0.5) * 260)
                    p.Anchored = true; p.CanCollide = false
                    p.Parent = workspace
                    Util.tween(p, 2.2 + math.random(), { Position = p.Position - Vector3.new(0, 100, 0), Transparency = 1 })
                    Debris:AddItem(p, 3.4)
                    task.wait(0.12)
                end
            end)
        end
    elseif ev == "Buff" then
        notify("BUFF: " .. data.Name .. " (" .. data.Time .. "s)", C.Accent)
    elseif ev == "Rebirthed" then
        S.Rebirths = data.Rebirths
        S.Droppers = {}
        S.Cash = 0
        S.DashMax = data.DashMax or S.DashMax
        if data.Unlock then notify("UNLOCKED: " .. data.Unlock, C.Purple) end
        updateChips()
    elseif ev == "CashPop" then
        spawnDmgNum(data.Pos, "+" .. Util.abbrev(data.Amount), data.Color or C.Gold, false)
        if not data.Small then sound(Config.Sounds.Coin, 0.3, 1 + math.random() * 0.3) end
    end
end)

-- ══════════════════════════════════════════════════════════════════
-- BOOT SEQUENCE
-- ══════════════════════════════════════════════════════════════════
local initialState = nil
local stateArrived = false
task.spawn(function()
    local ok, st = pcall(function() return RF:InvokeServer("GetState") end)
    if ok then initialState = st end
    stateArrived = true
end)

task.spawn(function()
    local steps = { "connecting…", "loading profile…", "warming shaders…", "charging arena…" }
    local t0 = os.clock()
    while true do
        local elapsed = os.clock() - t0
        local target = math.min(1, elapsed / Config.Menu.MinLoadTime)
        if stateArrived and elapsed >= Config.Menu.MinLoadTime then target = 1 end
        statusLabel.Text = steps[math.min(#steps, math.floor(target * #steps) + 1)]
        Util.tween(barFill, 0.25, { Size = UDim2.fromScale(target, 1) })
        if target >= 1 then break end
        task.wait(0.25)
    end
    task.wait(0.35)
    Util.tween(boot, 0.6, { BackgroundTransparency = 1 })
    bootTitle.Visible = false; tipLabel.Visible = false; barBack.Visible = false; statusLabel.Visible = false
    task.wait(0.62)
    boot.Visible = false
    menu.Visible = true
    Util.tween(menuShade, 0.8, { BackgroundTransparency = 0.45 })
    for i, b in ipairs(menuButtons) do
        local us = b:FindFirstChildOfClass("UIScale") or mk("UIScale", { Scale = 0.8 }, b)
        us.Scale = 0.8
        Util.tween(b, 0.35, { BackgroundTransparency = i == 1 and 0.15 or 0.25 })
        Util.tween(us, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
        task.wait(0.07)
    end
end)

local function enterGame()
    if S.Played then return end
    S.Played = true
    sound(Config.Sounds.Claim, 0.5)
    local ch = player.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if hrp then hrp.Anchored = false end
    menu.Visible = false
    hudRoot.Visible = true
    camera.CameraType = Enum.CameraType.Scriptable
    local camFrom = camera.CFrame
    local camTo
    if hrp then
        camTo = CFrame.lookAt(hrp.Position + Vector3.new(0, 8, 14), hrp.Position)
    else
        camTo = CFrame.new(0, 20, 40)
    end
    local t0 = os.clock()
    local conn
    conn = RunService.RenderStepped:Connect(function()
        local a = math.min(1, (os.clock() - t0) / Config.Menu.FlyInTime)
        local e = a * a * (3 - 2 * a)
        camera.CFrame = camFrom:Lerp(camTo, e)
        if a >= 1 then
            conn:Disconnect()
            camera.CameraType = Enum.CameraType.Custom
            local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
            if hum then camera.CameraSubject = hum end
        end
    end)
    for _, el in ipairs({ cashPill, multChip, hotbar, weaponLabel, sideBar }) do
        local us = mk("UIScale", { Scale = 0.85 }, el)
        Util.tween(us, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
    end
    if initialState then
        S.Cash = initialState.Cash; S.Displayed = initialState.Cash
        S.Rebirths = initialState.Rebirths
        S.Passes = initialState.Passes or {}
        S.Weapons = initialState.Weapons or {}
        S.Equipped = initialState.Equipped
        S.Droppers = initialState.Droppers or {}
        S.Vehicles = initialState.Vehicles or {}
        S.Claimed = initialState.Claimed
        S.Streak = initialState.Streak or 0
        S.DashMax = initialState.DashMax or S.DashMax
        if initialState.Settings then
            for k, v in pairs(initialState.Settings) do
                S.Settings[k] = v
                applySetting(k, v)
            end
        end
        cashText.Text = Util.cash(S.Cash)
        refreshHotbar(); updateChips(); renderRebirth()
        RE:FireServer("Equip", S.Equipped)
    end
    if IS_TOUCH then notify("Touch mode: hold HIT to combo · tap hotbar for skills · RUN to sprint", C.Accent) end
    notify("Claim a plot · arm up · the arena is waiting.", C.Accent)
end

menuButton("ENTER THE CLASH", 1, true).Activated:Connect(enterGame)
menuButton("LOADOUT", 2).Activated:Connect(function() togglePanel(shopPanel) renderShop() end)
menuButton("SETTINGS", 3).Activated:Connect(function() togglePanel(settingsPanel) end)
menuButton("CONTROLS", 4).Activated:Connect(function() togglePanel(helpPanel) end)
menuButton("CREDITS", 5).Activated:Connect(function() togglePanel(creditsPanel) end)

local menuT = 0
RunService.RenderStepped:Connect(function(dt)
    if not S.Played and menu.Visible then
        menuT += dt * Config.Menu.OrbitSpeed * math.pi * 2
        local r = Config.Menu.OrbitRadius
        camera.CameraType = Enum.CameraType.Scriptable
        camera.CFrame = CFrame.lookAt(
            Vector3.new(math.cos(menuT) * r, Config.Menu.OrbitHeight, math.sin(menuT) * r),
            Vector3.new(0, 8, 0))
        local ch = player.Character
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        if hrp and not hrp.Anchored then hrp.Anchored = true end
    end
end)

task.spawn(function()
    local ls = player:WaitForChild("leaderstats")
    local cashStat = ls:WaitForChild("Cash")
    cashStat.Changed:Connect(function(v)
        if v > S.Cash then pulseCash() end
        S.Cash = v
        if activePanel == rebirthPanel then renderRebirth() end
    end)
    ls:WaitForChild("Rebirths").Changed:Connect(function(v)
        S.Rebirths = v
        updateChips()
    end)
end)

RunService.Heartbeat:Connect(function(dt)
    local diff = S.Cash - S.Displayed
    if math.abs(diff) > 0.5 then
        S.Displayed += diff * math.min(1, dt * 7)
        cashText.Text = Util.cash(math.floor(S.Displayed + 0.5))
    elseif S.Displayed ~= S.Cash then
        S.Displayed = S.Cash
        cashText.Text = Util.cash(S.Cash)
    end
    local now = os.clock()
    for _, slot in pairs(slots) do
        if slot.EndsAt > now then
            local remain = slot.EndsAt - now
            slot.Cd.Position = UDim2.new(0, 0, remain / slot.Total, 0)
            slot.Cd.Visible = true
        elseif slot.Cd.Visible then
            slot.Cd.Visible = false
        end
    end
    if shakeT > 0 then
        shakeT -= dt
        if S.Settings.Shake ~= false then
            local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.CameraOffset = Vector3.new((math.random() - 0.5) * shakeAmp, (math.random() - 0.5) * shakeAmp, 0) end
        end
        if shakeT <= 0 then
            shakeAmp = 0
            local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.CameraOffset = Vector3.zero end
        end
    end
    if not cineLock then
        local targetFov = baseFOV + (sprinting and 6 or 0)
        local ch = player.Character
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        if hrp and hrp.AssemblyLinearVelocity.Magnitude > 45 then targetFov += 8 end
        camera.FieldOfView += (targetFov - camera.FieldOfView) * math.min(1, dt * 8)
    end
    local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health > 0 and hum.Health / hum.MaxHealth < 0.35 then
        vignette.BackgroundTransparency = 0.55 + 0.25 * math.sin(os.clock() * 6)
    else
        vignette.BackgroundTransparency = 1
    end
end)

task.spawn(function()
    local frames, acc = 0, 0
    RunService.Heartbeat:Connect(function(dt)
        frames += 1; acc += dt
    end)
    while true do
        task.wait(0.5)
        if S.Settings.FPS and acc > 0 then
            fpsLabel.Text = math.floor(frames / acc + 0.5) .. " FPS"
        end
        frames, acc = 0, 0
    end
end)

task.spawn(function()
    while true do
        task.wait(3)
        local ch = player.Character
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        if hrp and hrp.Position.Y < -40 and not hrp.Anchored then hrp.CFrame = CFrame.new(0, 8, 0) end
    end
end)