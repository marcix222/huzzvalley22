local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LP  = Players.LocalPlayer
local Cam = workspace.CurrentCamera
if not LP then return end

-- ── cleanup ───────────────────────────────────────────────────────
do
    local pg = LP:FindFirstChild("PlayerGui")
    if pg then
        for _, g in ipairs(pg:GetChildren()) do
            if g.Name == "Panel" or g.Name == "Readout" then g:Destroy() end
        end
    end
end
local GUI = LP:WaitForChild("PlayerGui", 5) or game:GetService("CoreGui")

-- ── remotes ───────────────────────────────────────────────────────
local COH = ReplicatedStorage:FindFirstChild("ChickenOrHero")
         or ReplicatedStorage:WaitForChild("ChickenOrHero", 8)

local function get(parent, name, t)
    if not parent then return nil end
    local f = parent:FindFirstChild(name)
    if f then return f end
    local ok, r = pcall(function() return parent:WaitForChild(name, t or 3) end)
    return ok and r or nil
end

local GameF  = get(COH, "Game")
local PresF  = get(COH, "Presentation")
local MoveF  = get(COH, "Movement")

local Melee  = get(GameF, "MeleeEvent")
local Action = get(GameF, "GameAction")
local Boost  = get(PresF, "BoostRequest")
local Guard  = get(PresF, "MovementGuardEvent")
local DbgEvt = get(GameF, "HitboxDebugEvent")

-- retry discovery until found
RunService.Heartbeat:Connect(function()
    if Melee and Action and Boost then return end
    local gf = COH and COH:FindFirstChild("Game")
    local pf = COH and COH:FindFirstChild("Presentation")
    if gf then
        Melee  = Melee  or gf:FindFirstChild("MeleeEvent")
        Action = Action or gf:FindFirstChild("GameAction")
        DbgEvt = DbgEvt or gf:FindFirstChild("HitboxDebugEvent")
    end
    if pf then
        Boost = Boost or pf:FindFirstChild("BoostRequest")
    end
end)

-- ── game constants ────────────────────────────────────────────────
local REACH    = 12
local CYCLE    = 0.85
local LEAD     = 0.14
local DIVE_CD  = 1.10

local RUN_CAP  = 37.5
local CAT_CAP  = 36.3
local SAFE_MAX = 37.5

do
    local cc = get(GameF, "ContactCatchConfig")
    if cc then
        local ok, m = pcall(require, cc)
        if ok and type(m) == "table" then
            REACH = m.ReachDistance  or REACH
            CYCLE = (m.Windup or 0.12) + (m.ActiveDuration or 0.18) + (m.Recovery or 0.55)
            LEAD  = m.CommitLeadTime or LEAD
        end
    end
    local mc = get(MoveF, "MovementConfig")
    if mc then
        local ok, m = pcall(require, mc)
        if ok and type(m) == "table" then
            local base = m.MaxSpeed or 33.6
            local cb   = m.CrossingBalance or {}
            RUN_CAP  = base * (1 + (cb.RunnerMaxBonus     or 0.12))
            CAT_CAP  = base * (1 + (cb.CatcherMaxReduction or 0.08))
            SAFE_MAX = math.max(RUN_CAP, CAT_CAP)
        end
    end
end

-- ── config ────────────────────────────────────────────────────────
local S = {
    WalkOn      = false,
    WalkSpeed   = 37,
    WalkReport  = 28,
    DriveOn     = false,
    DriveSpeed  = 37,

    StealthOn   = true,
    Jitter      = 0.12,

    BoostOn     = true,
    BoostAuto   = false,

    AttackOn    = false,
    AttackDist  = 12,
    HistLen     = 0.25,
    BurstN      = 5,

    DiveOn      = false,
    DiveDist    = 9,
    DiveLead    = 0.15,

    SpamM       = false,
    SpamD       = false,
    SpamRate    = 5,
    SpamBurst   = false,

    AimOn       = true,
    AimDist     = 200,

    CamFollow   = false,

    AttackRate  = CYCLE,

    ShowReadout = true,
}

-- ── ui ────────────────────────────────────────────────────────────
local C = {
    Bg     = Color3.fromRGB(15,  13,  20),
    Panel  = Color3.fromRGB(24,  21,  30),
    Ctrl   = Color3.fromRGB(32,  28,  39),
    Border = Color3.fromRGB(54,  45,  62),
    Text   = Color3.fromRGB(235, 230, 239),
    Muted  = Color3.fromRGB(157, 147, 165),
    Acc    = Color3.fromRGB(222, 135, 190),
}

local function mk(cls, props, par)
    local o = Instance.new(cls)
    for k, v in pairs(props or {}) do o[k] = v end
    o.Parent = par
    return o
end
local function rnd(o, r) mk("UICorner", { CornerRadius = UDim.new(0, r or 4) }, o) end

local Screen = mk("ScreenGui", { Name="Panel", ResetOnSpawn=false, DisplayOrder=100,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling }, GUI)

local W, H = 380, 900
local Win = mk("Frame", {
    Size = UDim2.fromOffset(W, H),
    Position = UDim2.new(0.5,-W/2,0.5,-H/2),
    BackgroundColor3 = C.Bg, BackgroundTransparency=0.1,
    BorderSizePixel=0, ClipsDescendants=true, ZIndex=1,
}, Screen)
rnd(Win, 6)
mk("UIStroke", { Color=C.Border, Thickness=1, Transparency=0.15 }, Win)

local Hdr = mk("Frame", { Size=UDim2.new(1,0,0,36), BackgroundColor3=C.Panel,
    BorderSizePixel=0, ZIndex=3 }, Win)
mk("TextLabel", { BackgroundTransparency=1, Position=UDim2.fromOffset(12,4),
    Size=UDim2.new(1,-24,0,18), Text="Settings", TextColor3=C.Acc, TextSize=13,
    Font=Enum.Font.GothamSemibold, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=4 }, Hdr)
mk("TextLabel", { BackgroundTransparency=1, Position=UDim2.fromOffset(13,20),
    Size=UDim2.new(1,-26,0,12), Text="RShift toggles", TextColor3=C.Muted, TextSize=9,
    Font=Enum.Font.Gotham, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=4 }, Hdr)

local Scroll = mk("ScrollingFrame", {
    Position=UDim2.fromOffset(0,36), Size=UDim2.new(1,0,1,-36),
    BackgroundTransparency=1, BorderSizePixel=0,
    CanvasSize=UDim2.new(0,0,0,2800), ScrollingDirection=Enum.ScrollingDirection.Y,
    ScrollBarThickness=4, ScrollBarImageColor3=C.Acc, ZIndex=3,
}, Win)
mk("UIPadding",{ PaddingTop=UDim.new(0,8), PaddingLeft=UDim.new(0,10),
    PaddingRight=UDim.new(0,10), PaddingBottom=UDim.new(0,12) }, Scroll)
mk("UIListLayout",{ Padding=UDim.new(0,5), SortOrder=Enum.SortOrder.LayoutOrder }, Scroll)

local lo = 0
local togRefs = {}

local function sec(t)
    lo = lo+1
    mk("TextLabel",{ Size=UDim2.new(1,0,0,14), BackgroundTransparency=1,
        Text=t:upper(), TextColor3=C.Acc, TextSize=9, Font=Enum.Font.GothamBold,
        TextXAlignment=Enum.TextXAlignment.Left, LayoutOrder=lo, ZIndex=5 }, Scroll)
end

local function tog(label, init, cb)
    lo = lo+1
    local val = init and true or false
    local btn = mk("TextButton",{ Size=UDim2.new(1,0,0,26), BackgroundColor3=C.Ctrl,
        BorderSizePixel=0, Text="", AutoButtonColor=false, LayoutOrder=lo, ZIndex=5 }, Scroll)
    rnd(btn,4)
    mk("TextLabel",{ BackgroundTransparency=1, Position=UDim2.fromOffset(10,0),
        Size=UDim2.new(1,-40,1,0), Text=label, TextColor3=C.Text, TextSize=10,
        Font=Enum.Font.Gotham, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=6 }, btn)
    local dot = mk("Frame",{ AnchorPoint=Vector2.new(1,0.5), Position=UDim2.new(1,-10,0.5,0),
        Size=UDim2.fromOffset(12,12), BackgroundColor3=val and C.Acc or C.Muted,
        BorderSizePixel=0, ZIndex=6 }, btn)
    rnd(dot,4)
    local ref = { set = function(v)
        val = v and true or false
        dot.BackgroundColor3 = val and C.Acc or C.Muted
        pcall(cb, val)
    end }
    btn.MouseButton1Click:Connect(function() ref.set(not val) end)
    pcall(cb, val)
    table.insert(togRefs, ref)
    return ref
end

local function sld(label, mn, mx, init, cb)
    lo = lo+1
    local val = init
    local hf = mk("Frame",{ Size=UDim2.new(1,0,0,34), BackgroundColor3=C.Ctrl,
        BorderSizePixel=0, LayoutOrder=lo, ZIndex=5 }, Scroll)
    rnd(hf,4)
    mk("TextLabel",{ BackgroundTransparency=1, Position=UDim2.fromOffset(10,2),
        Size=UDim2.new(1,-80,0,13), Text=label, TextColor3=C.Text, TextSize=10,
        Font=Enum.Font.Gotham, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=6 }, hf)
    local vl = mk("TextLabel",{ BackgroundTransparency=1, AnchorPoint=Vector2.new(1,0),
        Position=UDim2.new(1,-10,0,2), Size=UDim2.fromOffset(60,13),
        Text=tostring(val), TextColor3=C.Acc, TextSize=10, Font=Enum.Font.GothamMedium,
        TextXAlignment=Enum.TextXAlignment.Right, ZIndex=6 }, hf)
    local bar = mk("Frame",{ Position=UDim2.new(0,10,0,22), Size=UDim2.new(1,-20,0,4),
        BackgroundColor3=C.Border, BorderSizePixel=0, ZIndex=6 }, hf)
    rnd(bar,3)
    local fill = mk("Frame",{ Size=UDim2.new((val-mn)/(mx-mn),0,1,0),
        BackgroundColor3=C.Acc, BorderSizePixel=0, ZIndex=7 }, bar)
    rnd(fill,3)
    local hit = mk("TextButton",{ Position=UDim2.new(0,0,0,14), Size=UDim2.new(1,0,0,22),
        BackgroundTransparency=1, Text="", ZIndex=8 }, hf)
    local drag = false
    local function setX(x)
        local pct = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X,1), 0, 1)
        val = math.floor(mn + (mx-mn)*pct + 0.5)
        fill.Size = UDim2.new((val-mn)/(mx-mn),0,1,0)
        vl.Text = tostring(val)
        pcall(cb, val)
    end
    hit.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            drag=true; setX(i.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if drag and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
            setX(i.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            drag=false
        end
    end)
end

local function btn(label, cb, col)
    lo = lo+1
    local b = mk("TextButton",{ Size=UDim2.new(1,0,0,26), BackgroundColor3=col or C.Ctrl,
        BorderSizePixel=0, Text=label, TextColor3=C.Text, TextSize=10,
        Font=Enum.Font.GothamMedium, AutoButtonColor=false, LayoutOrder=lo, ZIndex=5 }, Scroll)
    rnd(b,4)
    b.MouseButton1Click:Connect(function() pcall(cb) end)
end

local function cap(t, h)
    lo = lo+1
    mk("TextLabel",{ Size=UDim2.new(1,0,0,h or 22), BackgroundTransparency=1,
        Text=t, TextColor3=C.Muted, TextSize=9, Font=Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left, TextWrapped=true,
        LayoutOrder=lo, ZIndex=5 }, Scroll)
end

-- ── build ui ──────────────────────────────────────────────────────
sec("Stealth")
tog("Stealth Mode", S.StealthOn, function(v) S.StealthOn = v end)
sld("Jitter (%)", 0, 30, math.floor(S.Jitter*100), function(v) S.Jitter = v/100 end)
cap(string.format("Caps speed to server bounds and randomizes. Runner %.1f, Catcher %.1f.",
    RUN_CAP, CAT_CAP), 30)

sec("Speed")
tog("Walk Override",  S.WalkOn,  function(v) S.WalkOn = v end)
sld("Walk Speed",     20, math.floor(SAFE_MAX), S.WalkSpeed,  function(v) S.WalkSpeed = v end)
sld("Reported",       15, 40, S.WalkReport, function(v) S.WalkReport = v end)
tog("Velocity Drive", S.DriveOn, function(v) S.DriveOn = v end)
sld("Drive Speed",    20, math.floor(SAFE_MAX), S.DriveSpeed, function(v) S.DriveSpeed = v end)
cap("Do not enable both Walk and Drive.", 18)

sec("Boost")
tog("Enable Boost",   S.BoostOn,   function(v) S.BoostOn = v end)
tog("Auto Boost",     S.BoostAuto, function(v) S.BoostAuto = v end)
cap("Space triggers boost. Auto fires while moving.", 18)

sec("Aim")
tog("Aim Assist",     S.AimOn, function(v) S.AimOn = v end)

sec("Attack / Reach")
tog("Enable Attack",  S.AttackOn,  function(v) S.AttackOn = v end)
sld("Reach Cap",      4, 14, S.AttackDist, function(v) S.AttackDist = math.min(v, REACH) end)
sld("History (ms)",   100, 1000, math.floor(S.HistLen*1000), function(v) S.HistLen = v/1000 end)
sld("Burst Count",    1, 10, S.BurstN, function(v) S.BurstN = v end)

sec("Dive")
tog("Enable Dive",    S.DiveOn, function(v) S.DiveOn = v end)
sld("Dive Cap",       4, 14, S.DiveDist, function(v) S.DiveDist = math.min(v, 10) end)
sld("Dive Lead (ms)", 0, 400, math.floor(S.DiveLead*1000), function(v) S.DiveLead = v/1000 end)

sec("Spam")
tog("Spam Melee",     S.SpamM,     function(v) S.SpamM = v end)
tog("Spam Dive",      S.SpamD,     function(v) S.SpamD = v end)
sld("Rate (Hz)",      1, 12, S.SpamRate, function(v) S.SpamRate = v end)
tog("Use Burst",      S.SpamBurst, function(v) S.SpamBurst = v end)
cap("Above 6-7 Hz server starts deduplicating aggressively.", 22)

sec("Camera")
tog("Follow Target",  S.CamFollow, function(v) S.CamFollow = v end)

sec("Manual")
btn("Boost",        function() if _G.hv_boost      then _G.hv_boost()      end end, Color3.fromRGB(60,80,50))
btn("Melee",        function() if _G.hv_melee      then _G.hv_melee()      end end, Color3.fromRGB(90,40,60))
btn("Melee Burst",  function() if _G.hv_meleeBurst then _G.hv_meleeBurst() end end, Color3.fromRGB(90,40,60))
btn("Dive",         function() if _G.hv_dive       then _G.hv_dive()       end end, Color3.fromRGB(40,60,90))
btn("Dive Burst",   function() if _G.hv_diveBurst  then _G.hv_diveBurst()  end end, Color3.fromRGB(40,60,90))

sec("Timing")
sld("Attack Interval (ms)", 200, 1500, math.floor(S.AttackRate*1000), function(v)
    S.AttackRate = math.max(v/1000, CYCLE)
end)

sec("Diagnostics")
tog("Show Readout", S.ShowReadout, function(v) S.ShowReadout = v end)
btn("Reset All", function()
    for _, ref in ipairs(togRefs) do ref.set(false) end
end, Color3.fromRGB(90,40,40))

-- drag
do
    local drag, ds, sp
    Hdr.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            drag=true; ds=i.Position; sp=Win.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if drag and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
            local d=i.Position-ds
            Win.Position=UDim2.new(sp.X.Scale, sp.X.Offset+d.X, sp.Y.Scale, sp.Y.Offset+d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            drag=false
        end
    end)
end
UserInputService.InputBegan:Connect(function(i, gp)
    if not gp and i.KeyCode==Enum.KeyCode.RightShift then
        Win.Visible = not Win.Visible
    end
end)

-- readout
local RGui = mk("ScreenGui",{ Name="Readout", ResetOnSpawn=false, DisplayOrder=50 }, GUI)
local Rdout = mk("TextLabel",{
    Size=UDim2.fromOffset(320,150), Position=UDim2.new(1,-340,0,80),
    BackgroundColor3=Color3.fromRGB(15,13,20), BackgroundTransparency=0.4,
    BorderSizePixel=0, Text="", TextColor3=Color3.fromRGB(220,220,220),
    Font=Enum.Font.Gotham, TextSize=11,
    TextXAlignment=Enum.TextXAlignment.Left, TextYAlignment=Enum.TextYAlignment.Top,
}, RGui)
rnd(Rdout,6)
mk("UIStroke",{ Color=C.Acc, Transparency=0.5 }, Rdout)
mk("UIPadding",{ PaddingLeft=UDim.new(0,6), PaddingTop=UDim.new(0,4) }, Rdout)

-- ── helpers ───────────────────────────────────────────────────────
local function char()  return LP.Character end
local function root()  local c=char(); return c and c:FindFirstChild("HumanoidRootPart") end
local function hum()   local c=char(); return c and c:FindFirstChildOfClass("Humanoid") end

local function role(p) return p and p:GetAttribute("GameRole") end
local function myRole() return role(LP) end
local function oppRole(r)
    if r=="Catcher" then return "Runner" end
    if r=="Runner"  then return "Catcher" end
    return nil
end
local function downed(p)
    if not p then return false end
    local c=p.Character; if not c then return false end
    return c:GetAttribute("Ragdolled")==true or c:GetAttribute("RescueAvailable")==true
end

local function nearest(maxDist)
    local r = root(); if not r then return nil, math.huge end
    local best, bd = nil, maxDist or math.huge
    local my = myRole()
    local opp = my and oppRole(my)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            local c  = p.Character
            local h  = c and c:FindFirstChildOfClass("Humanoid")
            local pr = c and c:FindFirstChild("HumanoidRootPart")
            if h and h.Health>0 and pr and not downed(p) then
                local ok
                if opp then ok = role(p)==opp
                elseif my then ok = role(p)~=my
                else ok = true end
                if ok then
                    local d=(pr.Position-r.Position).Magnitude
                    if d<bd then best,bd=p,d end
                end
            end
        end
    end
    return best, bd
end

local function aimDir(tRoot, myRoot)
    if S.AimOn and tRoot then
        local d = (tRoot.Position - myRoot.Position) * Vector3.new(1,0,1)
        if d.Magnitude > 0.1 then return d.Unit end
    end
    local lv = myRoot.CFrame.LookVector * Vector3.new(1,0,1)
    return lv.Magnitude > 0.01 and lv.Unit or nil
end

local jitterFactor = 1
local jitterSeed   = 0
RunService.Heartbeat:Connect(function(dt)
    jitterSeed = jitterSeed + dt
    if jitterSeed >= 0.10 then
        jitterSeed = 0
        jitterFactor = 1 - math.random() * S.Jitter
    end
end)

local function capSpeed(v)
    local limit
    if myRole()=="Catcher" then limit = CAT_CAP else limit = RUN_CAP end
    v = math.min(v, limit)
    if S.StealthOn then v = v * jitterFactor end
    return math.max(v, 6)
end

-- ── history ───────────────────────────────────────────────────────
local history = {}

RunService.Heartbeat:Connect(function()
    local r = root(); if not r then return end
    local now = workspace:GetServerTimeNow()
    local stamp = now - 0.008
    local snap = { time=stamp, pos=r.Position, targets={} }
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            local pr = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
            if pr then
                table.insert(snap.targets, { uid=p.UserId, pos=pr.Position })
            end
        end
    end
    table.insert(history, snap)
    local cut = now - math.max(S.HistLen, 0.6)
    while #history>0 and history[1].time < cut do
        table.remove(history, 1)
    end
end)

-- ── guard ─────────────────────────────────────────────────────────
local disabled = false

if Guard then
    Guard.OnClientEvent:Connect(function(kind)
        if kind=="Warning" then
            disabled = true
            S.WalkOn=false; S.DriveOn=false
            S.AttackOn=false; S.DiveOn=false
            S.SpamM=false; S.SpamD=false
            S.BoostAuto=false
            if Rdout then Rdout.Text = "" end
            for _, ref in ipairs(togRefs) do ref.set(false) end
            _G.hv_boost=nil; _G.hv_melee=nil; _G.hv_meleeBurst=nil
            _G.hv_dive=nil;  _G.hv_diveBurst=nil
        end
    end)
end

-- ── speed override ────────────────────────────────────────────────
RunService:BindToRenderStep("hv_walk", Enum.RenderPriority.Last.Value, function()
    if disabled then return end

    local c = char()
    if not c then return end
    local h = c:FindFirstChildOfClass("Humanoid")
    if not h or h.Health<=0 then return end

    pcall(function() c:SetAttribute("DashCooldownUntil", 0) end)
    pcall(function() c:SetAttribute("DashCooldown",      0) end)
    pcall(function() c:SetAttribute("DashReady",         true) end)
    pcall(function() c:SetAttribute("BoostRecoveryUntil",0) end)

    if S.DriveOn then return end
    if not S.WalkOn then return end
    if h.WalkSpeed <= 0 then return end

    local target = capSpeed(S.WalkSpeed)
    if math.abs(h.WalkSpeed - target) > 0.01 then
        h.WalkSpeed = target
    end
end)

RunService.Stepped:Connect(function(_, dt)
    if disabled or not S.DriveOn then return end
    if S.WalkOn then return end
    local c = char(); if not c then return end
    local h = c:FindFirstChildOfClass("Humanoid")
    local r = c:FindFirstChild("HumanoidRootPart")
    if not h or not r then return end
    if h.Health<=0 or h.Sit or h.PlatformStand or r.Anchored then return end
    local ms = c:GetAttribute("MovementState")
    if ms=="Dashing" or ms=="Boosting" then return end
    if c:GetAttribute("TackleActive") then return end
    if c:GetAttribute("MovementLocked") then return end
    if c:GetAttribute("Ragdolled") then return end
    if h.FloorMaterial == Enum.Material.Air then return end

    local md = h.MoveDirection
    if md.Magnitude < 0.05 then
        local v = r.AssemblyLinearVelocity
        local decay = math.exp(-10*dt)
        r.AssemblyLinearVelocity = Vector3.new(v.X*decay, v.Y, v.Z*decay)
        return
    end
    local flat = Vector3.new(md.X, 0, md.Z)
    if flat.Magnitude < 0.05 then return end
    flat = flat.Unit
    local speed = capSpeed(S.DriveSpeed)
    local cur = r.AssemblyLinearVelocity
    r.AssemblyLinearVelocity = Vector3.new(flat.X*speed, cur.Y, flat.Z*speed)
end)

local lastAttrW = 0
RunService.Heartbeat:Connect(function()
    if disabled or not S.WalkOn then return end
    if os.clock()-lastAttrW < 0.05 then return end
    lastAttrW = os.clock()
    local c = char(); if not c then return end
    local ms = c:GetAttribute("MovementState")
    if ms=="Idle" or ms=="Locked" then return end
    pcall(function() c:SetAttribute("MovementSpeed", S.WalkReport) end)
end)

-- ── boost / dash ──────────────────────────────────────────────────
local lastBoostFire = 0

local function fireDash()
    if not Boost or not S.BoostOn or disabled then return end
    if os.clock()-lastBoostFire < 0.10 then return end
    lastBoostFire = os.clock()
    local c = char()
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local r = c and c:FindFirstChild("HumanoidRootPart")
    if not h or not r then return end
    local to = h.MoveDirection
    if to.Magnitude < 0.05 then to = r.CFrame.LookVector end
    to = Vector3.new(to.X, 0, to.Z)
    if to.Magnitude < 0.01 then return end
    to = to.Unit
    local vel = r.AssemblyLinearVelocity
    local from = Vector3.new(vel.X, 0, vel.Z)
    from = from.Magnitude > 0.5 and from.Unit or to
    pcall(function() Boost:FireServer(from, to) end)
end

_G.hv_boost = fireDash

UserInputService.InputBegan:Connect(function(i, gp)
    if gp or not S.BoostOn or disabled then return end
    if i.KeyCode==Enum.KeyCode.Space then
        if not UserInputService:GetFocusedTextBox() then fireDash() end
    end
end)

RunService.Heartbeat:Connect(function()
    if not S.BoostAuto or not S.BoostOn or disabled then return end
    local h = hum(); if not h then return end
    if h.MoveDirection.Magnitude < 0.05 then return end
    fireDash()
end)

-- ── melee / reach ─────────────────────────────────────────────────
local hits, rejects = 0, 0
local spamM, spamD  = 0, 0
local lastHit, lastRej = 0, 0
local lastReason = ""
local dbgLast = ""

if Melee then
    Melee.OnClientEvent:Connect(function(_, accepted, reason)
        if accepted==false then
            rejects=rejects+1; lastRej=os.clock()
            if type(reason)=="table" then
                local parts={}
                for k,v in pairs(reason) do table.insert(parts, k.."="..tostring(v)) end
                lastReason = table.concat(parts,",")
            else
                lastReason = tostring(reason or "?")
            end
        elseif accepted==true then
            hits=hits+1; lastHit=os.clock()
        end
    end)
end

if DbgEvt then
    DbgEvt.OnClientEvent:Connect(function(data)
        if type(data)~="table" or data.kind~="RewindContact" then return end
        local acc = data.accepted and "HIT" or "MISS"
        local reason = tostring(data.reason or "")
        local disc = ""
        if data.claimedOrigin and data.rewindOrigin then
            disc = string.format(" d=%.2f", (data.claimedOrigin-data.rewindOrigin).Magnitude)
        end
        dbgLast = acc.." "..reason..disc
    end)
end

local function meleeOne(target)
    if not Melee then return 0 end
    local r = root(); if not r then return 0 end
    local tr = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    local dir = aimDir(tr, r); if not dir then return 0 end
    local ok = pcall(function()
        Melee:FireServer({
            id        = HttpService:GenerateGUID(false),
            at        = workspace:GetServerTimeNow(),
            direction = dir,
            position  = r.Position,
        })
    end)
    return ok and 1 or 0
end

local function meleeBurst(target)
    if not Melee then return 0 end
    local r = root(); if not r then return 0 end
    local tr = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    local cap = math.min(S.AttackDist, REACH)
    local now = workspace:GetServerTimeNow()

    local cands = {}
    if target then
        for i = #history, 1, -1 do
            local snap = history[i]
            for _, entry in ipairs(snap.targets) do
                if entry.uid == target.UserId then
                    local diff = (entry.pos - snap.pos) * Vector3.new(1,0,1)
                    local d = diff.Magnitude
                    if d > 0.1 and d <= cap then
                        local age = now - snap.time
                        table.insert(cands, {
                            err  = math.abs(age - LEAD),
                            dist = d,
                            pay  = {
                                id        = HttpService:GenerateGUID(false),
                                at        = snap.time,
                                direction = diff.Unit,
                                position  = snap.pos,
                            },
                        })
                    end
                    break
                end
            end
        end
    end

    table.sort(cands, function(a, b)
        if math.abs(a.err - b.err) > 0.008 then return a.err < b.err end
        return a.dist < b.dist
    end)

    local sent = 0
    for i = 1, math.min(S.BurstN, #cands) do
        if pcall(function() Melee:FireServer(cands[i].pay) end) then
            sent = sent + 1
        end
    end

    local dir = aimDir(tr, r)
    if dir then
        if pcall(function()
            Melee:FireServer({
                id        = HttpService:GenerateGUID(false),
                at        = now,
                direction = dir,
                position  = r.Position,
            })
        end) then
            sent = sent + 1
        end
    end
    return sent
end

-- ── dive / tackle ─────────────────────────────────────────────────
local dives, lastDive = 0, 0

if Action then
    Action.OnClientEvent:Connect(function(kind)
        if kind=="TackleReject" or kind=="Reject" then
            rejects = rejects + 1; lastRej = os.clock()
            lastReason = "TackleReject"
        end
    end)
end

local function diveOne(target)
    if not Action then return 0 end
    local r = root(); if not r then return 0 end
    local tr = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    local dir = aimDir(tr, r); if not dir then return 0 end
    local spd = S.WalkOn and S.WalkReport or math.floor(r.AssemblyLinearVelocity.Magnitude)
    local ok = pcall(function()
        Action:FireServer("Tackle", {
            id        = HttpService:GenerateGUID(false),
            at        = workspace:GetServerTimeNow(),
            direction = dir,
            position  = r.Position,
            speed     = spd,
        })
    end)
    if ok then dives=dives+1; lastDive=os.clock() end
    return ok and 1 or 0
end

local function diveBurst(target)
    if not Action then return 0 end
    if not target then return diveOne(nil) end
    local r = root(); if not r then return 0 end
    local tr = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    if not tr then return diveOne(target) end
    local predicted = tr.Position + tr.AssemblyLinearVelocity * S.DiveLead
    local now = workspace:GetServerTimeNow()
    local spd = S.WalkOn and S.WalkReport or math.floor(r.AssemblyLinearVelocity.Magnitude)

    local sent = 0
    for i = 0, S.BurstN-1 do
        local want = now - (LEAD + i*0.04)
        local best
        for k = #history, 1, -1 do
            if math.abs(history[k].time - want) < 0.05 then best=history[k]; break end
        end
        local usePos = best and best.pos or r.Position
        local diff = (predicted - usePos) * Vector3.new(1,0,1)
        if diff.Magnitude > 0.1 then
            if pcall(function()
                Action:FireServer("Tackle", {
                    id        = HttpService:GenerateGUID(false),
                    at        = best and best.time or now,
                    direction = diff.Unit,
                    position  = usePos,
                    speed     = spd,
                })
            end) then sent = sent + 1 end
        end
    end

    if sent == 0 then return diveOne(target) end
    dives=dives+1; lastDive=os.clock()
    return sent
end

_G.hv_melee      = function() meleeOne(nearest(S.AimDist)) end
_G.hv_meleeBurst = function() meleeBurst(nearest(REACH+8)) end
_G.hv_dive       = function() diveOne(nearest(S.AimDist)) end
_G.hv_diveBurst  = function() diveBurst(nearest(S.AimDist)) end

-- spam loop
local spamAcc = 0
RunService.Heartbeat:Connect(function(dt)
    if not S.SpamM and not S.SpamD then spamAcc=0; return end
    if disabled then return end
    spamAcc = spamAcc + dt
    local iv = 1 / math.max(S.SpamRate, 0.1)
    if spamAcc < iv then return end
    spamAcc = 0
    local t = nearest(S.AimDist)
    if S.SpamM and Melee then
        if S.SpamBurst and t then spamM = spamM + (meleeBurst(t) or 0)
        else spamM = spamM + (meleeOne(t) or 0) end
    end
    if S.SpamD and Action then
        spamD = spamD + (diveOne(t) or 0)
    end
end)

-- camera follow
RunService.RenderStepped:Connect(function()
    if not S.CamFollow then return end
    local t = nearest(S.AimDist); if not t then return end
    local tr = t.Character and t.Character:FindFirstChild("HumanoidRootPart"); if not tr then return end
    local aim = tr.Position + tr.AssemblyLinearVelocity * 0.08
    local cp = Cam.CFrame.Position
    local flat = Vector3.new(aim.X-cp.X, 0, aim.Z-cp.Z)
    if flat.Magnitude < 0.1 then return end
    Cam.CFrame = CFrame.lookAt(cp, cp+flat.Unit)
end)

-- auto attack
local lastAtkCycle = 0
RunService.Heartbeat:Connect(function()
    if not S.AttackOn or disabled then return end
    local rate = math.max(S.AttackRate, CYCLE)
    if os.clock()-lastAtkCycle < rate then return end
    if lastRej>0 and os.clock()-lastRej < 0.15 then return end
    local t = nearest(REACH+8); if not t then return end
    lastAtkCycle = os.clock()
    meleeBurst(t)
end)

-- auto dive
RunService.Heartbeat:Connect(function()
    if not S.DiveOn or disabled then return end
    if os.clock()-lastDive < DIVE_CD then return end
    local t = nearest(S.AimDist); if not t then return end
    local tr = t.Character and t.Character:FindFirstChild("HumanoidRootPart"); if not tr then return end
    local r = root(); if not r then return end
    local pred = tr.Position + tr.AssemblyLinearVelocity * S.DiveLead
    if (pred-r.Position).Magnitude > S.DiveDist then return end
    diveBurst(t)
end)

-- ── readout ───────────────────────────────────────────────────────
RunService.Heartbeat:Connect(function()
    if not S.ShowReadout then
        Rdout.Visible = false
        return
    end
    Rdout.Visible = true

    local t, d = nearest(2000)
    local c = char()
    local spd = 0
    if c then
        local r = c:FindFirstChild("HumanoidRootPart")
        if r then spd = math.floor((r.AssemblyLinearVelocity*Vector3.new(1,0,1)).Magnitude) end
    end
    local spamTxt = "off"
    if S.SpamM or S.SpamD then
        spamTxt = S.SpamRate.."hz"
        if S.SpamM and S.SpamD then spamTxt=spamTxt.." M+D"
        elseif S.SpamM then spamTxt=spamTxt.." M" else spamTxt=spamTxt.." D" end
    end
    local moveTxt = "off"
    if S.DriveOn then moveTxt="drv "..S.DriveSpeed
    elseif S.WalkOn then moveTxt="walk "..S.WalkSpeed end

    local candCount = 0
    if t then
        local cap = math.min(S.AttackDist, REACH)
        for _, snap in ipairs(history) do
            for _, entry in ipairs(snap.targets) do
                if entry.uid == t.UserId then
                    local diff = (entry.pos - snap.pos) * Vector3.new(1,0,1)
                    if diff.Magnitude > 0.1 and diff.Magnitude <= cap then
                        candCount = candCount + 1
                    end
                    break
                end
            end
        end
    end

    local capTxt = string.format("%.0f", myRole()=="Catcher" and CAT_CAP or RUN_CAP)
    local lines = {
        string.format("Atk %s  Dive %s  Spam %s",
            S.AttackOn and "on" or "off",
            S.DiveOn and "on" or "off",
            spamTxt),
        string.format("Move %s  Boost %s",
            moveTxt,
            S.BoostOn and (S.BoostAuto and "auto" or "space") or "off"),
        string.format("Role %s  Cap %s  Stealth %s",
            tostring(myRole() or "?"),
            capTxt,
            S.StealthOn and "on" or "off"),
        t and string.format("Target %.1f  hist:%d/%d", d, candCount, #history)
           or string.format("No target  hist:%d", #history),
        string.format("Speed %d  Hits %d/%d  Dives %d",
            spd, hits, hits+rejects, dives),
        string.format("Spam M:%d D:%d", spamM, spamD),
    }
    if #dbgLast > 0 then
        table.insert(lines, "SVR: "..dbgLast)
    elseif lastRej>0 and os.clock()-lastRej < 2.5 then
        table.insert(lines, "REJ: "..lastReason)
    end
    if lastHit>0 and os.clock()-lastHit < 1.2 then
        table.insert(lines, "HIT")
    end
    if disabled then
        table.insert(lines, "GUARD: disabled")
    end
    Rdout.Text = table.concat(lines, "\n")
end)

print("i love yori")
