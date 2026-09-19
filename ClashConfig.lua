local Config = {}

Config.GameName = "AETHER CLASH"
Config.Tagline  = "farm · fight · rebirth"
Config.Version  = "v12.4"

Config.Colors = {
    Background = Color3.fromRGB(9, 8, 14),
    Panel      = Color3.fromRGB(17, 15, 27),
    PanelHi    = Color3.fromRGB(26, 22, 42),
    Stroke     = Color3.fromRGB(72, 56, 128),
    Text       = Color3.fromRGB(238, 235, 248),
    Dim        = Color3.fromRGB(138, 130, 170),
    Accent     = Color3.fromRGB(167, 139, 250),
    AccentAlt  = Color3.fromRGB(124, 92, 255),
    Deep       = Color3.fromRGB(58, 40, 120),
    Danger     = Color3.fromRGB(255, 84, 104),
    Gold       = Color3.fromRGB(255, 208, 74),
    Purple     = Color3.fromRGB(178, 102, 255),
}

Config.Sounds = {
    Hit     = "rbxassetid://5801257793",
    Parry   = "rbxassetid://9114294022",
    Buy     = "rbxassetid://131323304",
    Claim   = "rbxassetid://131961136",
    Rebirth = "rbxassetid://199882438",
    Error   = "rbxassetid://550209561",
    Siren   = "rbxassetid://1837103898",
    Kill    = "rbxassetid://5801257793",
    Click   = "rbxassetid://6042053626",
    Whoosh  = "rbxassetid://12222216",
    Boom    = "rbxassetid://165969964",
    Coin    = "rbxassetid://131886985",
    Zap     = "rbxassetid://130791043",
}
Config.MusicId = ""

Config.Badges = {
    FirstBlood  = 0,
    Reborn      = 0,
    Millionaire = 0,
}

Config.Map = { Size = 900, PlotCount = 8, PlotRadius = 205, ArenaRadius = 56, Mountains = 26, Trees = 40, SpawnCount = 6 }
Config.Income = { RainEvery = 210, RainFor = 30, RainMult = 2 }
Config.KillReward = { Base = 120, PerStreak = 45, StreakCap = 25 }
Config.Rebirth = { BaseCost = 5e6, CostMult = 5, PerkMult = 0.25 }
Config.RespawnForceField = 3
Config.Impact = { SkillMinDmg = 40, GlobalGap = 1.2, Freeze = 0.09, FlashTime = 0.12 }
Config.Cine = { UltBanner = 2.2 }
Config.Leaderboard = { UpdateEvery = 60, Top = 10 }

Config.RebirthUnlocks = {
    [1] = { Name = "Violet Aura",     Desc = "A neon aura burns around you. They see you coming." },
    [2] = { Name = "Reinforced Body", Desc = "+50 max health, permanently." },
    [3] = { Name = "Vampiric",        Desc = "Heal 8% of all damage you deal." },
    [4] = { Name = "Adrenal Surge",   Desc = "+1 dash charge and faster recharge." },
    [5] = { Name = "Overlord",        Desc = "+20% cash and a purple presence." },
}

Config.Menu = {
    OrbitRadius = 160, OrbitHeight = 62, OrbitSpeed = 0.06,
    MinLoadTime = 2.5, FlyInTime = 1.2,
    Tips = {
        "Perfect-timed block = PARRY — stuns and shoves the attacker back.",
        "Combo finishers launch. Dash has i-frames — dodge through ults.",
        "Ults charge from dealing AND taking damage.",
        "Kill streaks raise your bounty — cash out or get farmed.",
        "Extractors pay while you fight. Claim a plot early.",
        "CASH RAIN doubles everything — watch the gold chip.",
        "Rebirth 3 unlocks Vampiric. Rebirth 4 adds a dash charge.",
        "On mobile: tap the hotbar to fight, hold HIT to combo.",
    },
    Credits = "AETHER CLASH " .. Config.Version .. " — built from silence. Farm · Fight · Rebirth.",
}

Config.Gamepasses = {
    DoubleCash  = { Id = 0, Name = "2x Cash (Permanent)", Price = 249,  Desc = "All income doubled. Forever." },
    QuadCash    = { Id = 0, Name = "4x Cash (Permanent)", Price = 899,  Desc = "Stacks with 2x for x8 total." },
    AutoCollect = { Id = 0, Name = "Auto Collect",        Price = 199,  Desc = "Droppers pay instantly — no drops needed." },
    ExtraSlots  = { Id = 0, Name = "+3 Dropper Slots",    Price = 299,  Desc = "6 → 9 droppers on your plot." },
    VIP         = { Id = 0, Name = "VIP",                 Price = 499,  Desc = "+10% cash, speed, jump, gold tag." },
    KillAll     = { Id = 0, Name = "KILL ALL",            Price = 799,  Desc = "Annihilate every player on the map. 10 min cooldown." },
    Nuke        = { Id = 0, Name = "NUKE",                Price = 1299, Desc = "Mushroom cloud over the arena. 15 min cooldown." },
}

Config.DropperSlots = 6
Config.DropperSlotsVIP = 9

Config.Droppers = {
    { Id = "iron",    Name = "Iron Extractor",   Cost = 500,    Value = 2,      Interval = 3.0, Color = Color3.fromRGB(185,195,205) },
    { Id = "copper",  Name = "Copper Extractor", Cost = 2500,   Value = 8,      Interval = 2.8, Color = Color3.fromRGB(235,125,60) },
    { Id = "silver",  Name = "Silver Extractor", Cost = 12000,  Value = 30,     Interval = 2.6, Color = Color3.fromRGB(205,225,240) },
    { Id = "gold",    Name = "Gold Extractor",   Cost = 60000,  Value = 120,    Interval = 2.4, Color = Color3.fromRGB(255,200,60) },
    { Id = "crystal", Name = "Crystal Rig",      Cost = 250000, Value = 480,    Interval = 2.2, Color = Color3.fromRGB(110,235,255) },
    { Id = "plasma",  Name = "Plasma Core",      Cost = 1e6,    Value = 2000,   Interval = 2.0, Color = Color3.fromRGB(200,90,255) },
    { Id = "quantum", Name = "Quantum Forge",    Cost = 5e6,    Value = 8500,   Interval = 1.8, Color = Color3.fromRGB(80,255,180) },
    { Id = "void",    Name = "Void Siphon",      Cost = 2e7,    Value = 36000,  Interval = 1.6, Color = Color3.fromRGB(120,100,220) },
    { Id = "star",    Name = "Star Harvester",   Cost = 1e8,    Value = 150000, Interval = 1.4, Color = Color3.fromRGB(255,240,150) },
    { Id = "omega",   Name = "Omega Reactor",    Cost = 5e8,    Value = 650000, Interval = 1.2, Color = Color3.fromRGB(255,80,80) },
}

Config.Weapons = {
    fists = {
        Name = "Fists", Price = 0, Rarity = "Common", Color = Config.Colors.Dim,
        Model = nil, Anim = "jab",
        M1 = { Dmg = { 12, 12, 14, 26 }, Rate = 0.32, Range = 6, Ranged = false },
        Skills = {
            { Key = "Z", Name = "Shock Slam",  Exec = "aoe",  Dmg = 32, Radius = 11, Knock = 46, Cd = 6 },
            { Key = "X", Name = "Bulrush",     Exec = "line", Dmg = 22, Range = 26, Knock = 20, Cd = 5 },
            { Key = "C", Name = "Iron Stance", Exec = "buff", BuffMult = 1.45, BuffTime = 5, Cd = 18 },
        },
        Ult = { Name = "Seismic Wrath", Exec = "rain", Radius = 26, Ticks = 6, Dmg = 18, TickTime = 0.35, Final = 60, Knock = 40, Cd = 60 },
    },
    voidblade = {
        Name = "Voidblade", Price = 30000, Rarity = "Uncommon", Color = Config.Colors.Purple,
        Model = "blade", Anim = "slash",
        M1 = { Dmg = { 18, 18, 20, 34 }, Rate = 0.30, Range = 7, Ranged = false },
        Skills = {
            { Key = "Z", Name = "Rift Slash",   Exec = "line", Dmg = 28, Range = 30, Knock = 24, Cd = 4 },
            { Key = "X", Name = "Gravity Well", Exec = "well", Dmg = 12, Radius = 13, Ticks = 5, TickTime = 0.7, Pull = 55, Cd = 14 },
            { Key = "C", Name = "Phase Step",   Exec = "line", Dmg = 0,  Range = 34, Immune = 0.6, Cd = 7 },
        },
        Ult = { Name = "Event Horizon", Exec = "aoe", Dmg = 120, Radius = 22, Knock = -70, Stun = 1.2, Cd = 75 },
    },
    plasma = {
        Name = "Plasma Repeater", Price = 75000, Rarity = "Rare", Color = Config.Colors.AccentAlt,
        Model = "gun", Anim = "aim",
        M1 = { Dmg = { 9, 9, 9, 18 }, Rate = 0.16, Range = 160, Ranged = true },
        Skills = {
            { Key = "Z", Name = "Overburst",    Exec = "shot", Rays = 6, Dmg = 8, Spread = 9, Cd = 8 },
            { Key = "X", Name = "Railshot",     Exec = "shot", Rays = 1, Dmg = 38, Pierce = 3, Cd = 12 },
            { Key = "C", Name = "Coolant Vent", Exec = "buff", BuffMult = 1.6, BuffTime = 5, Cd = 20 },
        },
        Ult = { Name = "Orbital Lance", Exec = "beam", Dmg = 16, Ticks = 8, TickTime = 0.4, Range = 120, Radius = 8, Cd = 80 },
    },
    gauntlets = {
        Name = "Tempest Gauntlets", Price = 150000, Rarity = "Rare", Color = Color3.fromRGB(255,150,60),
        Model = nil, Anim = "slam",
        M1 = { Dmg = { 24, 24, 26, 44 }, Rate = 0.42, Range = 6.5, Ranged = false },
        Skills = {
            { Key = "Z", Name = "Meteor Punch", Exec = "lob",  Dmg = 58, Radius = 9, Range = 60, Knock = 55, Cd = 10 },
            { Key = "X", Name = "Quake",        Exec = "aoe",  Dmg = 36, Radius = 15, Knock = 70, Stun = 0.6, Cd = 16 },
            { Key = "C", Name = "Titan Rush",   Exec = "buff", BuffMult = 1.35, BuffTime = 6, Immune = 0.4, Cd = 18 },
        },
        Ult = { Name = "Godfist", Exec = "aoe", Dmg = 180, Radius = 30, Knock = 120, Stun = 1, Cd = 90 },
    },
    prism = {
        Name = "Prism Longbow", Price = 300000, Rarity = "Epic", Color = Color3.fromRGB(180,255,220),
        Model = "bow", Anim = "aim",
        M1 = { Dmg = { 16, 16, 16, 30 }, Rate = 0.28, Range = 220, Ranged = true },
        Skills = {
            { Key = "Z", Name = "Triple Volley", Exec = "shot", Rays = 3, Dmg = 15, Spread = 6, Cd = 7 },
            { Key = "X", Name = "Piercing Star", Exec = "shot", Rays = 1, Dmg = 30, Pierce = 5, Cd = 13 },
            { Key = "C", Name = "Windwalk",      Exec = "line", Dmg = 0, Range = 36, Immune = 0.5, Cd = 8 },
        },
        Ult = { Name = "Starfall", Exec = "rain", Radius = 30, Ticks = 8, Dmg = 30, TickTime = 0.4, Final = 80, Knock = 30, Cd = 85 },
    },
    riftscythe = {
        Name = "Riftscythe", Price = 750000, Rarity = "Epic", Color = Color3.fromRGB(255,90,140),
        Model = "scythe", Anim = "spin",
        M1 = { Dmg = { 26, 26, 30, 46 }, Rate = 0.30, Range = 8, Ranged = false },
        Skills = {
            { Key = "Z", Name = "Reap",      Exec = "aoe",   Dmg = 50, Radius = 12, Knock = 30, Cd = 8 },
            { Key = "X", Name = "Cyclone",   Exec = "orbit", Dmg = 15, Radius = 14, Ticks = 10, TickTime = 0.5, Cd = 18 },
            { Key = "C", Name = "Soul Rend", Exec = "line",  Dmg = 60, Range = 28, Execute = 1.5, Knock = 26, Cd = 15 },
        },
        Ult = { Name = "Harvest", Exec = "aoe", Dmg = 150, Radius = 26, Heal = 0.5, Knock = 50, Cd = 80 },
    },
    starbreaker = {
        Name = "Starbreaker Hammer", Price = 2000000, Rarity = "Legendary", Color = Config.Colors.Gold,
        Model = "hammer", Anim = "slam",
        M1 = { Dmg = { 32, 32, 36, 58 }, Rate = 0.5, Range = 8, Ranged = false },
        Skills = {
            { Key = "Z", Name = "Skyfall",    Exec = "lob",  Dmg = 72, Radius = 11, Range = 70, Knock = 60, Cd = 12 },
            { Key = "X", Name = "Bastion",    Exec = "buff", Heal = 40, BuffMult = 1.3, BuffTime = 6, Cd = 22 },
            { Key = "C", Name = "Quake Step", Exec = "line", Dmg = 42, Range = 30, Knock = 80, Cd = 10 },
        },
        Ult = { Name = "Extinction", Exec = "rain", Radius = 34, Ticks = 10, Dmg = 36, TickTime = 0.4, Final = 100, Knock = 90, Cd = 110 },
    },
}
Config.WeaponOrder = { "fists", "voidblade", "plasma", "gauntlets", "prism", "riftscythe", "starbreaker" }

Config.Dash = { Charges = 3, Regen = 4, Speed = 72, Immune = 0.35, SurgeCharges = 4, SurgeRegen = 3 }
Config.Parry = { Window = 0.28, MaxHold = 2, Stun = 1.4, Reduce = 0.3 }
Config.UltMax = 100
Config.Sprint = { Speed = 26, VipSpeed = 30 }

Config.Vehicles = {
    hoverbike = { Name = "Hoverbike", Price = 50000,  Speed = 64,  Health = 350,  Seats = 1, Color = Config.Colors.Accent },
    warrig    = { Name = "War Rig",   Price = 500000, Speed = 48,  Health = 1200, Seats = 4, ContactDmg = 30, Color = Config.Colors.Danger },
}

Config.Settings = {
    { Key = "Music",   Label = "Music volume",    Def = 0.4, Min = 0, Max = 1 },
    { Key = "SFX",     Label = "SFX volume",      Def = 0.8, Min = 0, Max = 1 },
    { Key = "FOV",     Label = "Field of view",   Def = 70,  Min = 60, Max = 100 },
    { Key = "UIScale", Label = "UI scale",        Def = 1,   Min = 0.8, Max = 1.3 },
    { Key = "Shake",   Label = "Camera shake",    Def = true },
    { Key = "DmgNums", Label = "Damage numbers",  Def = true },
    { Key = "Impact",  Label = "Impact frames",   Def = true },
    { Key = "Cine",    Label = "Cutscenes",       Def = true },
    { Key = "Flash",   Label = "Big-event flash", Def = true },
    { Key = "FPS",     Label = "Show FPS",        Def = false },
}

Config.Controls = {
    "Mouse1 / HIT button — attack · combo finisher launches",
    "Q / double-tap WASD / DASH — dash (i-frames)",
    "F hold / BLOCK — block · perfect timing = PARRY",
    "Z X C — skills · V — ULT (charges in combat)",
    "1-7 — switch weapons · Shift / RUN — sprint",
    "Side rail — armory · rebirth · settings · controls",
}

Config.Units = {}    -- FUTURE: Anime-Last-Stand units
Config.Loadout = {}  -- FUTURE: AUT stand swap
Config.Banners = {}  -- FUTURE: gacha

return Config

