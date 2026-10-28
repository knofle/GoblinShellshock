local PREFIX, MAXPLAYERS = "GoblinShellshock", 10
-- Players must match this exactly (## Version in the .toc); bump it on every release
local VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)("GoblinShellshock", "Version") or "?"

-- W and NCOLS grow with player count (set in StartGame)
local BASEW, PERPLAYERW = 600, 80
local W, H, COLW, HUDH = BASEW, 300, 2, 36
local NCOLS = W / COLW
local G, SPEED, WINDK, STEP = 200, 4, 3, 1 / 120
local TANKW, TANKH, BARREL, TURRET = 16, 8, 12, 7
local HITW, HITH = 22, 12 -- shell hitbox, matches the drawn hull and turret
local CLIMB = 7
local MAXCRATES, CRATEAMMO, SHIELD = 7, 2, 60 -- MAXCRATES: crate visuals; the field holds 2 + 1 per 2 tanks alive
local SHOPTIME = 30
local GRACE = 2 -- host waits this long past the shot timer before sending SKIP
local FALLG = 600 -- visual gravity for settling dirt, tanks and debris
local MEDIA = "Interface\\AddOns\\GoblinShellshock\\Media\\"
local GOLD = { 0.83, 0.69, 0.22 }

local floor, ceil, sqrt, max, min, abs = math.floor, math.ceil, math.sqrt, math.max, math.min, math.abs
local cos, sin, rad, atan2 = math.cos, math.sin, math.rad, math.atan2

local COLORS = { {0.9,0.3,0.3}, {0.3,0.6,1}, {0.4,0.9,0.4}, {1,0.85,0.3}, {0.8,0.4,1}, {1,0.6,0.2},
	{0.3,0.9,0.9}, {1,0.5,0.75}, {0.9,0.9,0.9}, {0.65,0.45,0.25} }
local TEAMCOLORS = {
	{ {0.9,0.3,0.3}, {1,0.55,0.3}, {0.9,0.35,0.6}, {0.75,0.2,0.2}, {1,0.7,0.5} },
	{ {0.3,0.6,1}, {0.3,0.85,0.9}, {0.55,0.5,1}, {0.2,0.45,0.8}, {0.6,0.8,1} },
}

-- Skies. top/bottom: gradient; hill: backdrop tint; light: terrain brightness; sun/sunY, moon, stars (alpha);
-- clouds: how many, cloud: their tint and alpha; rain: drops; windK: wind multiplier; storm: lightning strikes.
local SKIES = {
	{ name = "Sunny day", top = { 0.3, 0.55, 0.92 }, bottom = { 0.72, 0.86, 1 }, hill = { 0.5, 0.65, 0.6 }, light = 1,
		sun = { 1, 0.95, 0.7 }, sunY = 245, clouds = 4, cloud = { 1, 1, 1, 0.8 } },
	{ name = "Dusk", top = { 0.2, 0.2, 0.45 }, bottom = { 1, 0.55, 0.3 }, hill = { 0.36, 0.25, 0.33 }, light = 0.85,
		sun = { 1, 0.5, 0.2 }, sunY = 100, clouds = 3, cloud = { 1, 0.6, 0.5, 0.6 } },
	{ name = "Twilight", top = { 0.06, 0.06, 0.2 }, bottom = { 0.42, 0.28, 0.5 }, hill = { 0.2, 0.17, 0.31 }, light = 0.7,
		stars = 0.4, clouds = 2, cloud = { 0.5, 0.4, 0.6, 0.5 } },
	{ name = "Starlight", top = { 0.01, 0.01, 0.05 }, bottom = { 0.07, 0.07, 0.17 }, hill = { 0.09, 0.09, 0.16 }, light = 0.55,
		stars = 1 },
	{ name = "Moonlight", top = { 0.02, 0.04, 0.11 }, bottom = { 0.13, 0.18, 0.3 }, hill = { 0.11, 0.15, 0.25 }, light = 0.65,
		stars = 0.6, moon = true, clouds = 2, cloud = { 0.4, 0.45, 0.6, 0.5 } },
	{ name = "Rain", top = { 0.22, 0.24, 0.28 }, bottom = { 0.45, 0.47, 0.5 }, hill = { 0.32, 0.34, 0.38 }, light = 0.8,
		clouds = 7, cloud = { 0.5, 0.52, 0.56, 0.9 }, rain = 50, windK = 1.5, desc = "Rain: wind up to 1.5x stronger." },
	{ name = "Thunderstorm", top = { 0.06, 0.06, 0.09 }, bottom = { 0.2, 0.2, 0.25 }, hill = { 0.14, 0.14, 0.18 }, light = 0.6,
		clouds = 7, cloud = { 0.25, 0.25, 0.3, 0.95 }, rain = 90, windK = 2, storm = true,
		desc = "Storm: double wind, lightning strikes between turns." },
}

-- Rule presets the host picks in the lobby; every value can then be tweaked (RULEDEFS).
-- gain/moves: moves per turn and the most you can store; dist: columns per move;
-- crates: on average one crate per this many rounds (0 = off); start: random items each tank begins with;
-- shop: 30s shop before the match with `gold` to spend.
local PRESETS = {
	{ name = "Classic", hp = 100, time = 20, gain = 1, moves = 3, dist = 15, crates = 3, wind = 20, start = 0, shop = 0, gold = 100,
		desc = "100 HP, 20s shots, about 1 crate per 3 rounds." },
	{ name = "Quick",   hp = 60,  time = 12, gain = 1, moves = 3, dist = 15, crates = 2, wind = 20, start = 0, shop = 0, gold = 100,
		desc = "60 HP, 12s shots, about 1 crate per 2 rounds." },
	{ name = "Arsenal", hp = 100, time = 20, gain = 1, moves = 3, dist = 15, crates = 6, wind = 20, start = 4, shop = 0, gold = 100,
		desc = "Start with 4 random items, fewer crates." },
}

-- Lobby settings in send order. sky 0 = random. cat: a category heading shown above that row.
-- vals: the only values the arrows step through (instead of lo to hi by step); names: shown instead of
-- the number, one per value. toggle: a single On/Off button instead of arrows.
local RULEDEFS = {
	{ key = "hp",     label = "Tank HP",        lo = 20, hi = 300, step = 10, cat = "Tanks" },
	{ key = "time",   label = "Shot time",      lo = 5,  hi = 60,  step = 5, fmt = "%ds" },
	-- Fuel for driving, in moves: each move is worth Move distance columns
	{ key = "gain",   label = "Fuel per turn", lo = 0,  hi = 3,   step = 1,
		names = { "None", "Some", "Medium", "Lots" } },
	{ key = "moves",  label = "Max fuel",      lo = 0,  hi = 9,   step = 1, vals = { 0, 1, 2, 3, 5, 7, 9 },
		names = { "None", "Little", "Some", "Medium", "Decent", "Lots", "Full tank" } },
	{ key = "dist",   label = "Move distance",   lo = 5,  hi = 40,  step = 5 },
	{ key = "crates", label = "Crates",         lo = 0,  hi = 10,  step = 1, fmt = "~1 per %d rounds", zero = "Off", cat = "Items" },
	{ key = "start",  label = "Start items",    lo = 0,  hi = 8,   step = 1 },
	{ key = "shop",   label = "Shop",           lo = 0,  hi = 1,   step = 1, fmt = "On", zero = "Off", toggle = true },
	{ key = "gold",   label = "Shop gold",      lo = 50, hi = 300, step = 25, fmt = "%dg" },
	{ key = "wind",   label = "Max wind",       lo = 0,  hi = 40,  step = 5, zero = "Calm", cat = "Battlefield" },
	{ key = "mix",    label = "Team spawns",    lo = 0,  hi = 1,   step = 1, fmt = "Mixed", zero = "Sides" },
	{ key = "sky",    label = "Sky",            lo = 0,  hi = #SKIES, step = 1, zero = "Random" },
	-- Zone: hi and list are set from BIOMES once that's defined. Terrain: same order as GenTerrain's styles
	{ key = "zone",   label = "Zone",           lo = 0,  hi = 0,   step = 1, zero = "Random" },
	{ key = "terrain", label = "Terrain",       lo = 0,  hi = 5,   step = 1, zero = "Random",
		list = { "Hills", "Mountain", "Valley", "Mesas", "Twin peaks" } },
}

-- Position of v in d.vals (or in lo..hi by step): the last one not above v
function RULEDEFS.Index(d, v)
	if not d.vals then return floor((v - d.lo) / d.step) + 1 end
	local i = 1
	while d.vals[i + 1] and d.vals[i + 1] <= v do i = i + 1 end
	return i
end

-- One arrow click from v: the next value in d.vals, or v plus or minus step
function RULEDEFS.Step(d, v, dir)
	if d.vals then return d.vals[max(1, min(#d.vals, RULEDEFS.Index(d, v) + dir))] end
	return max(d.lo, min(d.hi, v + dir * d.step))
end

function RULEDEFS.Show(d, v)
	if d.names then return d.names[RULEDEFS.Index(d, v)] end
	if v == 0 and d.zero then return d.zero end
	if d.key == "sky" then return SKIES[v].name end
	if d.list then return d.list[v].name or d.list[v] end
	if d.key == "crates" and v == 1 then return "~1 per round" end -- a random chance each turn, not a schedule
	return (d.fmt or "%d"):format(v)
end

-- Rules table from a preset or another rules table (sky defaults to random)
function RULEDEFS.Copy(src)
	local r = {}
	for _, d in ipairs(RULEDEFS) do r[d.key] = src[d.key] or 0 end
	return r
end

-- Index of the preset these rules match (map look and team spawns ignored), or nil for custom
RULEDEFS.KEEP = { sky = true, mix = true, zone = true, terrain = true }
function RULEDEFS.Preset(r)
	for k, p in ipairs(PRESETS) do
		local same = true
		for _, d in ipairs(RULEDEFS) do
			if not RULEDEFS.KEEP[d.key] and p[d.key] ~= r[d.key] then same = false end
		end
		if same then return k end
	end
end

function RULEDEFS.Encode(r)
	local out = {}
	for i, d in ipairs(RULEDEFS) do out[i] = r[d.key] end
	return table.concat(out, ".")
end

function RULEDEFS.Decode(s)
	local v, r = { strsplit(".", s or "") }, {}
	for i, d in ipairs(RULEDEFS) do
		r[d.key] = max(d.lo, min(d.hi, tonumber(v[i]) or PRESETS[1][d.key] or 0))
	end
	return r
end

-- Weapons and power-ups. Goblin Shell (1) is unlimited; everything else comes from crates.
-- weight = crate rarity: 6-8 common, 4-5 uncommon, 2-3 rare, 1 epic.
-- Behaviour: split (shells at apex), pellets (spread at launch), burst/burstV/spread (bomblets on impact;
-- carry: they fan out forward only and keep that share of the shell's sideways speed),
-- hail (shells from the sky), roll, bounce (times), home (steers at enemies), speed (launch multiplier),
-- napalm (burn reach per blob), cap (most burn damage one tank takes from a shot), fuse/drops (bursts in the air after fuse seconds into burning blobs), leech (heals the damage dealt),
-- wall (raises a column of dirt), knock (columns a close hit shoves tanks, default 4),
-- drill (px of earth it bores through in a straight line; the tunnel caves in).
-- power = used from the selector instead of fired. one = crates and the shop give 1, not 2.
-- crate = only from crates: not in the shop, the shop's leftover gold or the starting items.
-- use: the shop group (Utility, Defensive, Movement); Offensive when left out.
-- price: shop price instead of the one from weight. late: crates drop it more often as rounds pass.
-- laser: a straight sight line out of the barrel while you aim it. direct: precise hits on a tank deal more.
local WEAPONS = {
	{ name = "Goblin Shell",         radius = 24, dmg = 50,
		desc = "Trusty goblin ordnance. You never run out." },
	{ name = "Thorium Shell",        radius = 40, dmg = 70,  weight = 6, knock = 10,
		desc = "A heavier shell with a much bigger blast." },
	{ name = "Goblin Sapper Charge", radius = 60, dmg = 85,  weight = 2, knock = 14,
		desc = "A huge blast. Stand well back." },
	{ name = "The Big One",          radius = 90, dmg = 100, weight = 1, one = true, crate = true,
		desc = "Flattens everything in a wide area. Goblins call it subtle." },
	{ name = "Splintering Shell",    radius = 18, dmg = 35,  weight = 8, split = 3,
		desc = "Splits into 3 shells at the top of its arc." },
	{ name = "Rocket Barrage",       radius = 22, dmg = 40,  weight = 3, split = 5,
		desc = "Splits into 5 rockets at the top of its arc." },
	{ name = "Scatter Shot",         radius = 10, dmg = 20,  weight = 7, pellets = 5,
		desc = "Fires 5 pellets in a narrow spread." },
	{ name = "Iron Grenade Cluster", radius = 16, dmg = 30,  weight = 4, burst = 6, burstV = 100, spread = 40, carry = 0.3,
		desc = "Scatters 6 grenades around the impact." },
	{ name = "Molten Eruption",      radius = 14, dmg = 25,  weight = 4, burst = 6, burstV = 260, spread = 50,
		desc = "Erupts 6 molten blobs high into the air on impact." },
	{ name = "Blizzard",             radius = 16, dmg = 30,  weight = 3, hail = 5,
		desc = "Calls 5 ice shards down from the sky over the impact." },
	{ name = "Explosive Sheep",      radius = 24, dmg = 50,  weight = 8, roll = true,
		desc = "Lands, then trots downhill and explodes." },
	{ name = "Bouncing Bomb",        radius = 22, dmg = 45,  weight = 7, bounce = 3,
		desc = "Bounces 3 times before it goes off." },
	{ name = "Arcane Missile",       radius = 20, dmg = 29,  weight = 3, home = true,
		desc = "Steers toward the nearest enemy on the way down." },
	{ name = "Aimed Shot",           radius = 8,  dmg = 65,  weight = 5, speed = 1.6, knock = 10, laser = true, direct = true,
		desc = "Fast and flat, with a laser sight. A small but strong blast." },
	{ name = "Goblin Drill Rocket",  radius = 20, dmg = 30,  weight = 4, drill = 150, use = "Utility",
		desc = "Bores straight through up to 150px of earth, then flies on. The tunnel caves in behind it." },
	{ name = "Rain of Fire",         radius = 6,  dmg = 12,  weight = 4, napalm = 30, fuse = 0.9, drops = 7, cap = 40,
		desc = "Bursts in the air and rains 7 burning blobs. A tank takes at most 40 from one volley." },
	{ name = "Drain Life",           radius = 32, dmg = 40,  weight = 4, leech = true,
		desc = "Heals you for all the damage it deals." },
	{ name = "Seaforium Charge",     radius = 70, dmg = 20,  weight = 5, knock = 20, use = "Utility",
		desc = "Blasts a huge crater but deals little damage. Throws tanks far." },
	{ name = "Earthen Wall",         radius = 10,            weight = 6, wall = 70, use = "Defensive",
		desc = "Raises a tall wall of earth to hide behind." },
	{ name = "Power Word: Shield",   power = "shield",   weight = 5, use = "Defensive",
		desc = "Absorbs the next 60 damage you take." },
	{ name = "Rocket Boots",         power = "moves",    weight = 6, price = 5, late = true, use = "Movement",
		desc = "Adds a good splash of fuel for driving, even past a full tank." },
	{ name = "Blink",                power = "teleport", weight = 4, late = true, use = "Movement",
		desc = "Teleport to a spot you click on the field." },
	{ name = "Goblin Jetpack",       power = "jet",      weight = 4, price = 15, late = true, use = "Movement",
		desc = "Fly for 3 seconds. Steer with WASD or the arrow keys, then aim from wherever you land." },
}

-- WoW icon for each item (Interface\Icons)
do
	local ICONS = {
		["Goblin Shell"] = "INV_Ammo_Bullet_02",          ["Thorium Shell"] = "INV_Ammo_Bullet_03",
		["Goblin Sapper Charge"] = "Spell_Fire_SelfDestruct", ["The Big One"] = "INV_Misc_Bomb_05",
		["Splintering Shell"] = "INV_Misc_Bomb_02",        ["Rocket Barrage"] = "Ability_Racial_RocketBarrage",
		["Scatter Shot"] = "Ability_GolemStormBolt",       ["Iron Grenade Cluster"] = "INV_Misc_Bomb_08",
		["Molten Eruption"] = "Spell_Shaman_LavaBurst",    ["Blizzard"] = "Spell_Frost_IceStorm",
		["Explosive Sheep"] = "Spell_Nature_Polymorph",    ["Bouncing Bomb"] = "INV_Misc_Bomb_06",
		["Arcane Missile"] = "Spell_Nature_StarFall",      ["Aimed Shot"] = "INV_Spear_07",
		["Rain of Fire"] = "Spell_Shadow_RainOfFire",      ["Drain Life"] = "Spell_Shadow_LifeDrain02",
		["Seaforium Charge"] = "INV_Misc_Bomb_03",          ["Goblin Drill Rocket"] = "Trade_Mining",
		["Earthen Wall"] = "Spell_Nature_StoneSkinTotem",  ["Power Word: Shield"] = "Spell_Holy_PowerWordShield",
		["Rocket Boots"] = "INV_Gizmo_RocketBoot_01",      ["Blink"] = "Spell_Arcane_Blink",
		["Goblin Jetpack"] = "INV_Gizmo_RocketBootExtreme",
	}
	for _, w in ipairs(WEAPONS) do w.icon = ICONS[w.name] or "INV_Misc_QuestionMark" end
end

-- Inline icon escape for font strings, borders trimmed
function WEAPONS.Icon(w, size)
	return ("|TInterface\\Icons\\%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(w.icon, size, size)
end

-- Biomes tint the grayscale dirt, the top layer, plants (flora), rocks (stone) and the sky.
-- trees: sprites trees cycle through (cacti keep their own colour); bush/rock: sprite for those props;
-- back: backdrop silhouette (hills, peaks, dunes); deco: floating islands in the sky.
local BIOMES = {
	{ name = "Elwynn Forest",   dirt = { 0.56, 0.41, 0.25 }, top = { 0.35, 0.55, 0.22 }, flora = { 0.35, 0.65, 0.3 }, trees = { "oak", "pine" } },
	{ name = "Eversong Woods",  dirt = { 0.62, 0.46, 0.3 }, top = { 0.9, 0.7, 0.25 }, flora = { 1, 0.75, 0.3 }, trees = { "oak" }, sky = { 1, 0.92, 0.85 } },
	{ name = "Tanaris",         dirt = { 0.95, 0.78, 0.5 }, top = { 1, 0.9, 0.62 }, flora = { 0.75, 0.6, 0.35 }, trees = { "cactus" }, back = "dunes", sky = { 1, 0.92, 0.8 } },
	{ name = "Durotar",         dirt = { 0.75, 0.4, 0.25 }, top = { 0.82, 0.52, 0.3 }, flora = { 0.6, 0.45, 0.3 }, trees = { "deadtree" }, rock = "spike", stone = { 0.9, 0.55, 0.45 }, back = "dunes", sky = { 1, 0.85, 0.75 } },
	{ name = "Dun Morogh",      dirt = { 0.55, 0.56, 0.64 }, top = { 0.95, 0.97, 1 }, flora = { 0.75, 0.9, 0.85 }, trees = { "pine" }, back = "peaks", sky = { 0.85, 0.9, 1 } },
	{ name = "Tirisfal Glades", dirt = { 0.4, 0.36, 0.38 }, top = { 0.45, 0.42, 0.3 }, flora = { 0.5, 0.47, 0.55 }, trees = { "deadtree", "oak" }, sky = { 0.75, 0.75, 0.9 } },
	{ name = "Searing Gorge",   dirt = { 0.32, 0.28, 0.28 }, top = { 0.9, 0.35, 0.1 }, flora = { 0.3, 0.28, 0.26 }, trees = { "deadtree" }, stone = { 0.5, 0.45, 0.42 }, back = "peaks", sky = { 1, 0.7, 0.6 } },
	{ name = "Icecrown",        dirt = { 0.35, 0.38, 0.45 }, top = { 0.8, 0.88, 1 }, flora = { 0.55, 0.65, 0.75 }, trees = { "deadtree" }, rock = "crystal", stone = { 0.6, 0.9, 1 }, back = "peaks", sky = { 0.75, 0.85, 1 } },
	{ name = "Sholazar Basin",  dirt = { 0.45, 0.33, 0.2 }, top = { 0.3, 0.65, 0.2 }, flora = { 0.3, 0.75, 0.3 }, trees = { "jungle", "oak" }, bush = "fern", sky = { 0.9, 1, 0.9 } },
	{ name = "Hellfire Peninsula", dirt = { 0.6, 0.3, 0.2 }, top = { 0.75, 0.4, 0.25 }, flora = { 0.55, 0.4, 0.3 }, trees = { "deadtree" }, rock = "spike", stone = { 0.75, 0.4, 0.3 }, back = "peaks", sky = { 1, 0.7, 0.6 } },
	{ name = "Zangarmarsh",     dirt = { 0.3, 0.3, 0.25 }, top = { 0.3, 0.55, 0.45 }, flora = { 0.45, 0.75, 0.8 }, trees = { "mushroom" }, bush = "fern", sky = { 0.75, 0.95, 0.95 } },
	{ name = "The Jade Forest", dirt = { 0.5, 0.4, 0.28 }, top = { 0.4, 0.75, 0.35 }, flora = { 0.45, 0.8, 0.4 }, trees = { "bamboo", "oak" }, back = "peaks", sky = { 0.9, 1, 0.95 } },
	{ name = "Nagrand",         dirt = { 0.5, 0.4, 0.28 }, top = { 0.45, 0.75, 0.3 }, flora = { 0.45, 0.75, 0.35 }, trees = { "oak" }, deco = "floatrock" },
	{ name = "The Waking Shores", dirt = { 0.28, 0.25, 0.25 }, top = { 0.4, 0.6, 0.3 }, flora = { 0.45, 0.65, 0.3 }, trees = { "pine" }, rock = "basalt", stone = { 0.4, 0.38, 0.38 }, back = "peaks", sky = { 1, 0.85, 0.8 } },
	{ name = "Hallowfall",      dirt = { 0.45, 0.38, 0.3 }, top = { 0.85, 0.75, 0.4 }, flora = { 0.95, 0.85, 0.45 }, trees = { "oak" }, sky = { 1, 0.95, 0.8 } },
}
for _, d in ipairs(RULEDEFS) do
	if d.key == "zone" then d.hi, d.list = #BIOMES, BIOMES end
end

-- Map props. The list part is the pick order; each match uses none, one or two kinds.
-- min/max: how many; w/h: size; block: stops shells; radius/dmg/knock: explodes when hit (knock as for weapons);
-- trigger: also when driven over. lean: how much it tilts with the slope (default 1, fully).
local PROPS = {
	"tree", "bush", "rock", "mine", "barrel",
	tree   = { min = 2, max = 6, w = 14, h = 28, block = true, lean = 0.12 },
	bush   = { min = 2, max = 5, w = 14, h = 7 },
	rock   = { min = 2, max = 4, w = 14, h = 14 },
	mine   = { min = 1, max = 3, w = 12, h = 6, radius = 22, dmg = 35, knock = 16, trigger = true }, -- Goblin Land Mine
	barrel = { min = 1, max = 2, w = 12, h = 12, radius = 34, dmg = 45, block = true, lean = 0.4 }, -- Blackpowder Barrel
}

-- Returns r, g, b and the tier name
local function Rarity(w)
	local wt = w.weight or 0
	if wt == 0 then return 1, 1, 1, "Standard issue" end
	if wt >= 6 then return 1, 1, 1, "Common" end
	if wt >= 4 then return 0.35, 1, 0.35, "Uncommon" end
	if wt >= 2 then return 0.35, 0.65, 1, "Rare" end
	return 0.8, 0.45, 1, "Epic"
end

-- Shop price by rarity tier: 100 gold buys 2 epics or 6 commons
local function Price(w)
	local wt = w.weight or 0
	if w.price then return w.price end
	return wt >= 6 and 15 or (wt >= 4 and 25 or (wt >= 2 and 35 or 50))
end

local game, lobby, joining, myName
-- groupHost: who has the group's one lobby or match (can be us). hostOk: our own HELLO came back
-- before anyone else's, so we won a simultaneous start.
local groupHost, hostOk
-- lastRules: the host's last settings; kept between matches, back to Classic after a reload
local lastTeams, lastRules = false, nil
local held, sessionWins, hostRules = {}, {}, {} -- hostRules[sender]: rules from their last RULES message

local function Me()
	myName = myName or (UnitName("player") .. "-" .. GetNormalizedRealmName())
	return myName
end

local function Print(...) print("|cffd4af37Goblin Shellshock:|r", ...) end

local function Short(name) return Ambiguate(name, "short") end

-- Deterministic PRNG (Park-Miller, exact in doubles)
local seed = 1
local function SetSeed(s) seed = s % 2147483646 + 1 end
local function Rand(lo, hi)
	seed = (seed * 16807) % 2147483647
	return lo + seed % (hi - lo + 1)
end

local function Channel()
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
	return IsInRaid() and "RAID" or "PARTY"
end

-- Returns false if the message was too long to send
local function Send(...)
	local msg = table.concat({ ... }, ":")
	if #msg > 254 then Print("Message too long, not sent: " .. msg:sub(1, 20)) return false end
	C_ChatInfo.SendAddonMessage(PREFIX, msg, Channel())
	return true
end

-- The other player running the group's lobby or match, if any. Hosts who left the group or went
-- offline don't count, so a crashed host can't block everyone.
local function OtherHost()
	local h = groupHost
	if not h or h == Me() then return nil end
	local unit = Ambiguate(h, "none")
	if not (UnitInParty(unit) or UnitInRaid(unit)) or not UnitIsConnected(unit) then return nil end
	return h
end

------------------------------------------------------------------------
-- UI helpers
------------------------------------------------------------------------
local function Panel(f)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.06, 0.06, 0.07, 0.95)
	for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local t = f:CreateTexture(nil, "BORDER")
		t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3])
		t:SetPoint(e[1])
		t:SetPoint(e[2])
		if e[3] then t:SetHeight(1) else t:SetWidth(1) end
	end
end

local function FlatButton(parent, w, h, text)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, h)
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.14, 0.14, 0.16)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.15)
	b:SetNormalFontObject("GameFontNormal")
	b:SetHighlightFontObject("GameFontHighlight")
	b:SetDisabledFontObject("GameFontDisable")
	b:SetText(text or "")
	return b
end

local function Draggable(f)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
end

------------------------------------------------------------------------
-- Game window
------------------------------------------------------------------------
local frame = CreateFrame("Frame", "GoblinShellshockFrame", UIParent)
frame:SetSize(W + 16, H + HUDH + 44)
frame:SetPoint("CENTER")
frame:SetFrameStrata("HIGH")
Draggable(frame)
frame:SetScript("OnHide", function() wipe(held) end)
frame:Hide()
Panel(frame)

local status
do
	local cog = frame:CreateTexture(nil, "OVERLAY")
	cog:SetSize(18, 18)
	cog:SetPoint("TOPLEFT", 6, -6)
	cog:SetTexture(MEDIA .. "cog")
	cog:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])

	local title = frame:CreateFontString(nil, "OVERLAY")
	title:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
	title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	title:SetPoint("LEFT", cog, "RIGHT", 4, 0)
	title:SetText("Goblin Shellshock")

	status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	status:SetPoint("LEFT", title, "RIGHT", 16, 0)

	-- Anything else about the turn goes after the status text
	frame.after = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.after:SetPoint("LEFT", status, "RIGHT", 12, 0)

	local close = CreateFrame("Button", nil, frame)
	close:SetSize(20, 20)
	close:SetPoint("TOPRIGHT", -4, -6)
	close:SetNormalFontObject("GameFontNormal")
	close:SetText("x")
	close:SetScript("OnClick", function() frame.Quit() end)

	-- Minimize keeps you in the match; the reminder under the toast brings the window back
	local mini = FlatButton(frame, 18, 18, "_")
	mini:SetPoint("TOPRIGHT", -26, -7)
	mini:SetScript("OnClick", function() frame:Hide() end)

	-- Window scale, 75% to 200%, saved in GoblinShellshockDB[key].
	-- Keeps the window on the same screen spot while it resizes (centre, or top for top-anchored ones);
	-- a window still hanging off another frame just scales in place.
	function frame.SetWinScale(win, key, s)
		s = max(0.75, min(2, floor(s * 20 + 0.5) / 20))
		local old, x, y = win:GetScale(), win:GetCenter()
		local point, rel = win:GetPoint(1)
		local top = point == "TOP"
		if top then y = win:GetTop() end
		win:SetScale(s)
		if x and (rel == nil or rel == UIParent) then
			win:ClearAllPoints()
			win:SetPoint(top and "TOP" or "CENTER", UIParent, "BOTTOMLEFT", x * old / s, y * old / s)
		end
		GoblinShellshockDB = GoblinShellshockDB or {}
		GoblinShellshockDB[key] = s
		if win.SyncScale then win.SyncScale() end
	end
	function frame.SetGameScale(s) frame.SetWinScale(frame, "scale", s) end

	local help = FlatButton(frame, 18, 18, "?")
	help:SetPoint("TOPRIGHT", -142, -7)
	help:SetScript("OnClick", function()
		if frame.help and frame.help:IsShown() then frame.help:Hide() else frame.Help() end
	end)
end

-- Mini scale slider (same as CCS) at the top right of `win`: flat track, the thumb shows the percent.
-- Previews while dragging and applies on release, so the window doesn't jump mid-drag.
-- Sets win.SyncScale, which moves the thumb to the window's current scale.
function frame.ScaleSlider(win, x, y)
	local key = win == frame and "scale" or "lobbyScale"
	local INSET, TW, MINS, MAXS, STEPS = 2, 36, 0.75, 2, 0.05
	local function Box(f, bg, edge)
		local e = f:CreateTexture(nil, "BACKGROUND")
		e:SetAllPoints()
		e:SetColorTexture(edge, edge, edge)
		local b = f:CreateTexture(nil, "BORDER")
		b:SetPoint("TOPLEFT", 1, -1)
		b:SetPoint("BOTTOMRIGHT", -1, 1)
		b:SetColorTexture(bg, bg, bg)
	end

	local slider = CreateFrame("Frame", nil, win)
	slider:SetSize(90, 18)
	slider:SetPoint("TOPRIGHT", x, y)
	slider:EnableMouse(true)
	Box(slider, 0.05, 0.3)
	local thumb = CreateFrame("Frame", nil, slider)
	thumb:SetSize(TW, 18 - 2 * INSET)
	Box(thumb, 0.22, 0.45)
	local text = thumb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("CENTER")
	local value = 1

	local function Refresh()
		local travel = max(0, slider:GetWidth() - 2 * INSET - TW)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPLEFT", INSET + travel * (value - MINS) / (MAXS - MINS), -INSET)
		text:SetText(floor(value * 100 + 0.5) .. "%")
	end
	local function FromCursor()
		local left = slider:GetLeft()
		if not left then return value end
		local x = GetCursorPosition() / slider:GetEffectiveScale()
		local travel = max(1, slider:GetWidth() - 2 * INSET - TW)
		local v = MINS + max(0, min(1, (x - left - INSET - TW / 2) / travel)) * (MAXS - MINS)
		return max(MINS, min(MAXS, MINS + floor((v - MINS) / STEPS + 0.5) * STEPS))
	end

	slider:SetScript("OnMouseDown", function(self, btn)
		if btn ~= "LeftButton" then return end
		value = FromCursor()
		Refresh()
		self:SetScript("OnUpdate", function()
			value = FromCursor()
			Refresh()
		end)
	end)
	slider:SetScript("OnMouseUp", function(self)
		if not self:GetScript("OnUpdate") then return end
		self:SetScript("OnUpdate", nil)
		frame.SetWinScale(win, key, value)
	end)

	function win.SyncScale()
		value = win:GetScale()
		Refresh()
	end
	win.SyncScale()
end
frame.ScaleSlider(frame, -48, -7)

local restartBtn = FlatButton(frame, 84, 18)
restartBtn:SetPoint("TOPRIGHT", -166, -7)
restartBtn:Hide()
-- After a match: same players, teams and rules again, skipping the lobby
restartBtn.again = FlatButton(frame, 84, 18, "Play again")
restartBtn.again:SetPoint("RIGHT", restartBtn, "LEFT", -4, 0)
restartBtn.again:Hide()

local field = CreateFrame("Frame", nil, frame)
field:SetSize(W, H)
field:SetPoint("BOTTOMLEFT", 8, HUDH + 8)
field:SetClipsChildren(true)

do
	local sky = field:CreateTexture(nil, "BACKGROUND", nil, -8)
	sky:SetAllPoints()
	sky:SetColorTexture(1, 1, 1)

	local hills = field:CreateTexture(nil, "BACKGROUND", nil, -6)
	hills:SetPoint("BOTTOMLEFT")
	hills:SetPoint("BOTTOMRIGHT")
	hills:SetHeight(180)
	field.sky, field.hills = sky, hills

	-- Top left of the field, stacked: shot and shop clock, turn number, whose turn it is and their team
	-- (set in DrawStatus)
	local over = CreateFrame("Frame", nil, field)
	over:SetAllPoints()
	over:SetFrameLevel(field:GetFrameLevel() + 10)
	frame.clock = over:CreateFontString(nil, "OVERLAY")
	frame.clock:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
	frame.clock:SetPoint("TOPLEFT", 6, -6)
	frame.turnText = over:CreateFontString(nil, "OVERLAY")
	frame.turnText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
	frame.turnText:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	frame.turnText:SetPoint("TOPLEFT", frame.clock, "BOTTOMLEFT", 0, -4)
	frame.whoText = over:CreateFontString(nil, "OVERLAY")
	frame.whoText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
	frame.whoText:SetPoint("TOPLEFT", frame.turnText, "BOTTOMLEFT", 0, -3)
	frame.teamText = over:CreateFontString(nil, "OVERLAY")
	frame.teamText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
	frame.teamText:SetPoint("TOPLEFT", frame.whoText, "BOTTOMLEFT", 0, -3)
end

-- Wind streaks drift across the sky (visual only, so math.random is fine)
local streaks = {}
for i = 1, 24 do
	local t = field:CreateTexture(nil, "BACKGROUND", nil, -4)
	t:SetColorTexture(1, 1, 1, 0.1 + random() * 0.12)
	t:SetHeight(1)
	streaks[i] = { tex = t, x = random(0, W), y = random(60, H - 10), f = 0.6 + random() * 0.8 }
end

local cols, grass = {}, {}
local function CreateCol(i)
	local t = field:CreateTexture(nil, "ARTWORK")
	t:SetTexture(MEDIA .. "dirt", "REPEAT", "REPEAT")
	t:SetWidth(COLW)
	t:SetPoint("BOTTOMLEFT", (i - 1) * COLW, 0)
	cols[i] = t
	local g = field:CreateTexture(nil, "ARTWORK", nil, 1)
	local s = i % 3 == 0 and 0.9 or 1
	g:SetColorTexture(0.35 * s, 0.55 * s, 0.22 * s)
	g:SetSize(COLW, 3)
	g:SetPoint("TOP", t, "TOP")
	grass[i] = g
	-- Soft shadow at the bottom of the column (sized in SetCol), so the ground deepens toward the base
	t.shadow = field:CreateTexture(nil, "ARTWORK", nil, 1)
	t.shadow:SetColorTexture(1, 1, 1, 1)
	t.shadow:SetWidth(COLW)
	t.shadow:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT")
end
for i = 1, NCOLS do CreateCol(i) end

-- Visual terrain heights ease toward the sim heights, so dirt visibly settles
local hv, hvv, terrainDirty = {}, {}, false

local function GroundAt(x) return hv[max(1, min(NCOLS, floor(x / COLW) + 1))] or 0 end

-- Ground at x blended between column centres, so a driving tank rides a slope instead of its
-- stair steps. Steps taller than CLIMB are cliffs and stay sharp.
function field.SmoothGround(x)
	local f = x / COLW - 0.5
	local c = floor(f)
	local a, b = hv[max(1, min(NCOLS, c + 1))] or 0, hv[max(1, min(NCOLS, c + 2))] or 0
	if abs(b - a) > CLIMB then return f - c < 0.5 and a or b end
	return a + (b - a) * (f - c)
end

-- Stands a w x h sprite on the ground at x, y, leaning `lean` times the slope under it (1 = follows
-- the ground). Rotates about its bottom centre and stays anchored by CENTER. Returns the angle.
function field.Stand(tex, x, y, w, h, lean)
	local a = 0
	if lean > 0 then
		local s = max(4, w / 2)
		a = lean * max(-0.7, min(0.7, atan2(GroundAt(x + s) - GroundAt(x - s), 2 * s)))
	end
	tex:SetPoint("CENTER", field, "BOTTOMLEFT", x - sin(a) * h / 2, y + cos(a) * h / 2)
	tex:SetRotation(a)
	return a
end

-- Laser sight for `laser` weapons: a straight red beam from the barrel tip along the aim,
-- running to the ground or the field edge. Only the shooter sees it, and only while aiming.
field.laser = field:CreateLine(nil, "OVERLAY")
field.laser:SetThickness(2)
field.laser:SetColorTexture(1, 0.15, 0.1, 0.75)
field.laser:SetBlendMode("ADD")
field.laser:Hide()
function field.Laser(t, v, shown)
	local L = field.laser
	local on = shown and v.x and t.alive and WEAPONS[t.weapon].laser and (game.solo or t.name == Me()) and not t.ai
		and not (game.over or game.shot or game.landed or game.shopping or game.retreat or game.targeting or game.jet)
	L:SetShown(on and true or false)
	if not on then return end
	local tilt, a = v.tilt or 0, rad(t.angle)
	local dx, dy = cos(a), sin(a)
	local sx = v.x - sin(tilt) * TURRET + dx * BARREL
	local sy = v.y + cos(tilt) * TURRET + dy * BARREL
	local len = 0
	while len < W + H do
		local px, py = sx + dx * (len + 4), sy + dy * (len + 4)
		if px < 0 or px > W or py > H or py < GroundAt(px) then break end
		len = len + 4
	end
	L:SetStartPoint("BOTTOMLEFT", field, sx, sy)
	L:SetEndPoint("BOTTOMLEFT", field, sx + dx * len, sy + dy * len)
end

-- Drill tunnel, visual only: soft dark blobs every 4px along the drill's path, wobbled and varied in
-- size so it reads as dug rather than ruled. Blobs shrink where the ground above them is thin, so the
-- entry and exit holes stay inside the dirt. Once the shot is over the tunnel closes up and fades
-- while the real cave-in settles the dirt.
field.bore, field.boreId = {}, 0
for i = 1, 48 do
	local b = field:CreateTexture(nil, "ARTWORK", nil, 2)
	b:SetTexture(MEDIA .. "glow")
	b:SetVertexColor(0.06, 0.04, 0.02)
	b:Hide()
	field.bore[i] = b
end
-- f: 0 open, 1 closed
function field.BoreLayout(f)
	local x1, y1, x2, y2 = unpack(field.boreSeg)
	local len = sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
	local dx, dy = len > 0 and (x2 - x1) / len or 0, len > 0 and (y2 - y1) / len or 0
	local n = floor(len / 4) + 1
	for i, b in ipairs(field.bore) do
		local d, wob = (i - 1) * 4, sin(i * 1.7) * 1.5 + sin(i * 0.45) * 2
		local x, y = x1 + dx * d - dy * wob, y1 + dy * d + dx * wob
		local size = (20 + sin(i * 2.3) * 5) * (1 - 0.6 * f)
		local r = size / 2
		local room = (min(GroundAt(x - r), GroundAt(x), GroundAt(x + r)) - y) * 2 + 4
		size = min(size, room)
		if i > n or size < 5 then
			b:Hide()
		else
			b:SetSize(size, size)
			b:SetPoint("CENTER", field, "BOTTOMLEFT", x, y)
			b:SetAlpha(0.9 * (1 - f))
			b:Show()
		end
	end
end
function field.Bore(s)
	local a, b = s.dig, s.tunnel
	if not (a or b) then return end
	if not field.boreOn or field.boreFading then
		field.boreId = field.boreId + 1 -- stops any fade still running
		field.boreOn, field.boreFading = true, nil
	end
	field.boreSeg = a and { a[1], a[2], s.x, s.y } or b
	field.BoreLayout(0)
end
function field.BoreFade()
	if not field.boreOn or field.boreFading then return end
	field.boreId, field.boreFading = field.boreId + 1, true
	local id, n = field.boreId, 0
	C_Timer.NewTicker(0.03, function(tk)
		if field.boreId ~= id then tk:Cancel() return end
		n = n + 1
		field.BoreLayout(n / 20)
		if n >= 20 then
			for _, b in ipairs(field.bore) do b:Hide() end
			field.boreOn, field.boreFading = nil, nil
		end
	end, 20)
end

local vis = {}
for i = 1, MAXPLAYERS do
	local v = { color = COLORS[i] }
	v.barrel = field:CreateLine(nil, "OVERLAY", nil, 1)
	v.barrel:SetThickness(3)
	v.body = field:CreateTexture(nil, "OVERLAY", nil, 2)
	v.body:SetSize(22, 11)
	v.body:SetTexture(MEDIA .. "tank")
	v.hpbg = field:CreateTexture(nil, "OVERLAY", nil, 3)
	v.hpbg:SetSize(22, 3)
	v.hpbg:SetColorTexture(0, 0, 0, 0.7)
	v.hp = field:CreateTexture(nil, "OVERLAY", nil, 4)
	v.hp:SetHeight(1)
	v.hp:SetPoint("LEFT", v.hpbg, "LEFT", 1, 0)
	v.label = field:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	v.label:SetPoint("BOTTOM", v.hpbg, "TOP", 0, 2)
	v.shield = field:CreateTexture(nil, "OVERLAY", nil, 6)
	v.shield:SetTexture(MEDIA .. "ring")
	v.shield:SetBlendMode("ADD")
	v.shield:SetVertexColor(0.4, 0.8, 1)
	v.shield:SetSize(36, 36)
	v.shield:Hide()
	v.parts = { v.barrel, v.body, v.hpbg, v.hp, v.label }
	vis[i] = v
end

local marker = field:CreateTexture(nil, "OVERLAY", nil, 5)
marker:SetSize(12, 12)
marker:SetTexture(MEDIA .. "arrow")
marker:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
marker:Hide()

-- Teleport target marker that follows the cursor
local ghost = field:CreateTexture(nil, "OVERLAY", nil, 6)
ghost:SetSize(14, 14)
ghost:SetTexture(MEDIA .. "arrow")
ghost:Hide()

local shellVis = {}
for i = 1, 8 do
	local halo = field:CreateTexture(nil, "OVERLAY", nil, 4)
	halo:SetTexture(MEDIA .. "glow")
	halo:SetBlendMode("ADD")
	halo:SetVertexColor(1, 0.7, 0.3)
	halo:SetSize(14, 14)
	halo:Hide()
	local body = field:CreateTexture(nil, "OVERLAY", nil, 5)
	body:SetTexture(MEDIA .. "shell")
	body:SetVertexColor(1, 0.92, 0.75)
	body:SetSize(12, 12)
	body:Hide()
	shellVis[i] = { halo = halo, body = body }
end

local function HideShells()
	for _, sv in ipairs(shellVis) do
		sv.halo:Hide()
		sv.body:Hide()
	end
	field.BoreFade()
end

local crateVis = {}
for i = 1, MAXCRATES do
	local box = field:CreateTexture(nil, "OVERLAY", nil, 1)
	box:SetSize(12, 12)
	box:SetTexture(MEDIA .. "crate")
	box:Hide()
	local chute = field:CreateTexture(nil, "OVERLAY", nil, 1)
	chute:SetSize(22, 11)
	chute:SetTexture(MEDIA .. "chute")
	chute:SetPoint("BOTTOM", box, "TOP", 0, 0)
	chute:Hide()
	crateVis[i] = { box = box, chute = chute }
end

local propVis = {} -- textures reused across matches, filled in StartGame

------------------------------------------------------------------------
-- Effects (visual only)
------------------------------------------------------------------------
-- Particles: one pool, kinds pick texture, blend, colour and gravity
local KINDS = {
	smoke = { tex = "glow", c = { 0.45, 0.45, 0.48 }, grav = -25, drift = true },
	dust  = { tex = "glow", c = { 0.5, 0.4, 0.28 }, grav = -10, drift = true },
	fire  = { tex = "glow", blend = "ADD", c = { 1, 0.55, 0.15 } },
	flame = { tex = "glow", blend = "ADD", c = { 1, 0.45, 0.1 }, grav = -40 },
	flash = { tex = "glow", blend = "ADD", c = { 1, 0.95, 0.7 } },
	ring  = { tex = "ring", blend = "ADD", c = { 1, 0.8, 0.5 } },
	tele  = { tex = "ring", blend = "ADD", c = { 0.4, 0.8, 1 } },
	ember = { tex = "glow", blend = "ADD", c = { 1, 0.6, 0.2 }, grav = 300, solid = true },
	dirt  = { c = { 0.36, 0.27, 0.16 }, grav = FALLG, solid = true },
	spark = { tex = "glow", blend = "ADD", c = { 1, 1, 1 }, grav = 90, drag = 1.5 },
}
local parts, partI = {}, 0

-- col optionally overrides the kind's colour
local function Particle(kind, x, y, vx, vy, life, s0, s1, a, col)
	partI = partI % 400 + 1
	local p = parts[partI]
	if not p then
		p = { tex = field:CreateTexture(nil, "OVERLAY", nil, 3) }
		parts[partI] = p
	end
	local k, t = KINDS[kind], p.tex
	local c = col or k.c
	if k.tex then
		t:SetTexture(MEDIA .. k.tex)
		t:SetVertexColor(c[1], c[2], c[3])
	else
		t:SetColorTexture(c[1], c[2], c[3])
		t:SetVertexColor(1, 1, 1)
	end
	t:SetBlendMode(k.blend or "BLEND")
	p.k, p.x, p.y, p.vx, p.vy, p.life, p.age, p.s0, p.s1, p.a = k, x, y, vx, vy, life, 0, s0, s1, a
	t:Show()
end

local floaters, floatI = {}, 0
for i = 1, 8 do
	local fs = field:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:Hide()
	floaters[i] = { fs = fs, age = 9 }
end

local function Floater(text, x, y, r, g, b)
	floatI = floatI % #floaters + 1
	local f = floaters[floatI]
	f.x, f.y, f.age = x, y, 0
	f.fs:SetText(text)
	f.fs:SetTextColor(r, g, b)
	f.fs:Show()
end

local shakeT, shakeA = 0, 0

local function Explosion(x, y, r, dirt)
	if dirt then
		for _ = 1, 14 do Particle("dirt", x, y, random(-80, 80), random(40, 200), 1, 3, 3, 1) end
		for _ = 1, 4 do Particle("dust", x + random(-r, r) / 2, y, random(-20, 20), random(5, 20), 1.2, r * 0.6, r * 1.4, 0.5) end
		return
	end
	Particle("flash", x, y, 0, 0, 0.12, r * 3, r * 4, 1)
	Particle("fire", x, y, 0, 0, 0.45, r * 1.2, r * 2.8, 1)
	Particle("ring", x, y, 0, 0, 0.35, r * 0.6, r * 3, 0.8)
	for _ = 1, 8 + floor(r / 3) do
		local a, s = rad(random(20, 160)), random(80, 240)
		local size = 2 + random() * 2
		Particle(random() < 0.6 and "dirt" or "ember", x, y, cos(a) * s, sin(a) * s, 0.6 + random() * 0.5, size, size, 1)
	end
	for _ = 1, 4 do
		Particle("smoke", x + random(-r, r) / 2, y + random(0, r) / 2, random(-15, 15), random(10, 30), 1.4 + random() * 0.6, r * 0.5, r * 1.5, 0.45)
	end
	shakeA = max(shakeT > 0 and shakeA or 0, min(6, r / 6))
	shakeT = max(shakeT, 0.3)
end

local function Dust(x, y, n)
	for _ = 1, n do Particle("dust", x, y, random(-40, 40), random(5, 20), 0.7, 4, 10, 0.5) end
end

-- Sky dressing and weather (visual only): stars, sun, moon, clouds, floating islands, rain, lightning
do
	local wx = { clouds = {}, drops = {}, isles = {}, bolt = {}, flashA = 0, boltA = 0, ambient = 0 }
	field.wx = wx
	local function Tex(layer, sub, file)
		local t = field:CreateTexture(nil, layer, nil, sub)
		if file then t:SetTexture(MEDIA .. file) end
		t:Hide()
		return t
	end
	wx.stars = Tex("BACKGROUND", -7)
	wx.stars:SetTexture(MEDIA .. "stars", "REPEAT", "CLAMP")
	wx.stars:SetAllPoints()
	wx.sun = Tex("BACKGROUND", -7, "sun")
	wx.sun:SetSize(90, 90)
	wx.sun:SetBlendMode("ADD")
	wx.moon = Tex("BACKGROUND", -7, "moon")
	wx.moon:SetSize(44, 44)
	for i = 1, 3 do wx.isles[i] = Tex("BACKGROUND", -7, "floatrock") end
	for i = 1, 8 do wx.clouds[i] = { tex = Tex("BACKGROUND", -5, "cloud") } end
	for i = 1, 90 do
		local t = Tex("OVERLAY", 7)
		t:SetColorTexture(0.75, 0.8, 0.9, 0.35)
		t:SetSize(1, 9)
		wx.drops[i] = { tex = t }
	end
	wx.flash = Tex("OVERLAY", 7)
	wx.flash:SetAllPoints()
	wx.flash:SetColorTexture(0.85, 0.9, 1)
	for i = 1, 10 do
		local l = field:CreateLine(nil, "OVERLAY", nil, 7)
		l:SetThickness(2)
		l:SetColorTexture(0.85, 0.9, 1)
		l:Hide()
		wx.bolt[i] = l
	end

	-- Sets up the whole backdrop for this sky and biome
	function field.ApplySky(sky, biome)
		local b = biome.sky or { 1, 1, 1 }
		local t, m = sky.top, sky.bottom
		field.sky:SetGradient("VERTICAL", CreateColor(m[1] * b[1], m[2] * b[2], m[3] * b[3], 1), CreateColor(t[1] * b[1], t[2] * b[2], t[3] * b[3], 1))
		field.hills:SetTexture(MEDIA .. (biome.back or "hills"), "REPEAT", "CLAMP")
		field.hills:SetTexCoord(0, W / 256, 0, 1)
		field.hills:SetVertexColor(sky.hill[1] * b[1], sky.hill[2] * b[2], sky.hill[3] * b[3])
		wx.sky = sky
		wx.stars:SetShown(sky.stars ~= nil)
		wx.stars:SetAlpha(sky.stars or 0)
		wx.stars:SetTexCoord(0, W / 256, 0, 1)
		wx.sun:SetShown(sky.sun ~= nil)
		if sky.sun then
			wx.sun:SetVertexColor(sky.sun[1], sky.sun[2], sky.sun[3])
			wx.sun:SetPoint("CENTER", field, "BOTTOMLEFT", W * 0.78, sky.sunY)
		end
		wx.moon:SetShown(sky.moon)
		wx.moon:SetPoint("CENTER", field, "BOTTOMLEFT", W * 0.2, H - 55)
		local l = sky.light
		for i, isle in ipairs(wx.isles) do
			isle:SetShown(biome.deco ~= nil)
			isle:SetSize(32 * (1.6 - i * 0.3), 24 * (1.6 - i * 0.3))
			isle:SetPoint("CENTER", field, "BOTTOMLEFT", W * (0.15 + 0.32 * i), H - 60 - 40 * (i % 2))
			isle:SetVertexColor(l, l, l)
		end
		local c = sky.cloud or { 1, 1, 1, 1 }
		for i, cl in ipairs(wx.clouds) do
			cl.tex:SetShown(i <= (sky.clouds or 0))
			cl.tex:SetVertexColor(c[1], c[2], c[3])
			cl.tex:SetAlpha(c[4])
			cl.s = 0.8 + random() * 0.9
			cl.tex:SetSize(64 * cl.s * 1.5, 32 * cl.s * 1.5)
			cl.x, cl.y = random(0, W), H - 30 - random(0, 70)
		end
		for i, d in ipairs(wx.drops) do
			d.tex:SetShown(i <= (sky.rain or 0))
			d.x, d.y = random(0, W), random(0, H)
		end
		wx.flash:Hide()
		for _, line in ipairs(wx.bolt) do line:Hide() end
	end

	-- Jagged bolt from the top of the field down to x, y with a bright flash
	function field.Bolt(x, y)
		local px, py, n = x + random(-40, 40), H, #wx.bolt
		for i, line in ipairs(wx.bolt) do
			local ny = H - (H - y) * i / n
			local nx = i == n and x or x + (px - x) * 0.3 + random(-14, 14)
			line:SetStartPoint("BOTTOMLEFT", field, px, py)
			line:SetEndPoint("BOTTOMLEFT", field, nx, ny)
			line:Show()
			px, py = nx, ny
		end
		wx.boltA, wx.flashA = 1, 0.6
	end

	function field.AnimateSky(e, wind)
		local sky = wx.sky
		if not sky then return end
		for i, cl in ipairs(wx.clouds) do
			if i <= (sky.clouds or 0) then
				cl.x = cl.x + (4 + wind * 1.5) * e / cl.s
				if cl.x > W + 60 then cl.x = -60 elseif cl.x < -60 then cl.x = W + 60 end
				cl.tex:SetPoint("CENTER", field, "BOTTOMLEFT", cl.x, cl.y)
			end
		end
		if sky.rain then
			local vx = wind * 6
			for i = 1, sky.rain do
				local d = wx.drops[i]
				d.y = d.y - 380 * e
				d.x = d.x + vx * e
				if d.y < GroundAt(d.x) then
					if random() < 0.15 then Particle("spark", d.x, d.y + 1, random(-15, 15), random(10, 25), 0.15, 2, 1, 0.4) end
					d.x, d.y = random(-40, W + 40), H + random(0, 40)
				end
				d.tex:SetRotation(-math.atan(vx / 380))
				d.tex:SetPoint("CENTER", field, "BOTTOMLEFT", d.x, d.y)
			end
		end
		if sky.storm then
			-- Distant sheet lightning now and then
			wx.ambient = wx.ambient - e
			if wx.ambient <= 0 then
				wx.ambient = 4 + random() * 7
				wx.flashA = max(wx.flashA, 0.25)
			end
		end
		if wx.flashA > 0 then
			wx.flashA = max(0, wx.flashA - 1.6 * e)
			wx.flash:SetAlpha(wx.flashA)
			wx.flash:SetShown(wx.flashA > 0)
		end
		if wx.boltA > 0 then
			wx.boltA = max(0, wx.boltA - 2.5 * e)
			for _, line in ipairs(wx.bolt) do
				line:SetAlpha(wx.boltA)
				line:SetShown(wx.boltA > 0)
			end
		end
	end
end

-- Burning ground along the impact
local function NapalmFx(x, y, reach)
	Explosion(x, y, 8)
	local n = max(6, floor(reach / 2.5))
	for k = 0, n do
		local fx = x + (2 * k / n - 1) * reach
		Particle("flame", fx, GroundAt(fx) + 3, random(-5, 5), random(10, 30), 1.2 + random() * 1.2, 6, 16, 0.9)
	end
	for _ = 1, 2 do Particle("smoke", x + random(-reach, reach), y + 10, random(-10, 10), random(15, 30), 2.2, 10, 28, 0.4) end
end

-- Shown where a shell lands; the sim applies the authoritative impacts later
local function ImpactFx(w, x, y)
	if w.napalm then NapalmFx(x, y, w.napalm) else Explosion(x, y, w.radius, w.wall) end
end

-- Tank destroyed: big blast, a few follow-up pops, wreck chunks in the tank's colour
local function TankDeath(x, y, c)
	Explosion(x, y, 55)
	Particle("flash", x, y, 0, 0, 0.25, 120, 180, 1)
	for k = 1, 3 do
		C_Timer.After(0.12 * k, function() Explosion(x + random(-20, 20), y + random(0, 25), 20 + random(0, 12)) end)
	end
	local dark = { c[1] * 0.5, c[2] * 0.5, c[3] * 0.5 }
	for _ = 1, 10 do Particle("dirt", x, y, random(-140, 140), random(120, 320), 1.4, 4, 4, 1, dark) end
	Particle("dirt", x, y, random(-60, 60), 340, 1.8, 7, 7, 1, c)
	for _ = 1, 10 do Particle("smoke", x, y, random(-10, 10), random(20, 45), 3, 10, 34, 0.55) end
	shakeT, shakeA = 0.6, 9
end

-- Victory banner across the field
local banner = CreateFrame("Frame", nil, field)
banner:SetPoint("LEFT", field, "LEFT", 0, 40)
banner:SetPoint("RIGHT", field, "RIGHT", 0, 40)
banner:SetHeight(96)
banner:SetFrameLevel(field:GetFrameLevel() + 10)
banner:Hide()
do
	local bg = banner:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.6)
	for _, p in ipairs({ "TOP", "BOTTOM" }) do
		local l = banner:CreateTexture(nil, "BORDER")
		l:SetPoint(p .. "LEFT")
		l:SetPoint(p .. "RIGHT")
		l:SetHeight(2)
		l:SetColorTexture(GOLD[1], GOLD[2], GOLD[3])
	end
	-- Separate frame for the big text so it can be scaled for the slam-in
	banner.slam = CreateFrame("Frame", nil, banner)
	banner.slam:SetSize(600, 60)
	banner.slam:SetPoint("CENTER", 0, 10)
	banner.big = banner.slam:CreateFontString(nil, "OVERLAY")
	banner.big:SetFont("Fonts\\FRIZQT__.TTF", 42, "THICKOUTLINE")
	banner.big:SetPoint("CENTER")
	banner.big:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	banner.sub = banner:CreateFontString(nil, "OVERLAY")
	banner.sub:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
	banner.sub:SetPoint("BOTTOM", 0, 12)
end

-- Turn announcement in the middle of the field
local ann = CreateFrame("Frame", nil, field)
ann:SetSize(600, 50)
ann:SetPoint("CENTER", 0, 60)
ann:SetFrameLevel(field:GetFrameLevel() + 11)
ann:Hide()
ann.text = ann:CreateFontString(nil, "OVERLAY")
ann.text:SetFont("Fonts\\FRIZQT__.TTF", 26, "THICKOUTLINE")
ann.text:SetPoint("CENTER")
ann.t = 0

-- Only shown to the player whose turn it is
local function Announce()
	local t = game.tanks[game.cur]
	if not (game.solo or t.name == Me()) or t.ai then return end -- not for the computer's turns
	local c = vis[t.i].color
	ann.text:SetText("Your turn!")
	ann.text:SetTextColor(c[1], c[2], c[3])
	ann.t = 1.6
	ann:Show()
	if not game.solo then
		PlaySound(SOUNDKIT.READY_CHECK)
		if not frame:IsShown() then Print("It's your turn! Type /gs to open the window.") end
	end
end

-- Fireworks
local FWCOLORS = { {1,0.3,0.3}, {0.3,0.7,1}, {0.4,1,0.4}, {1,0.85,0.3}, {0.9,0.4,1}, {1,1,1} }
local rockets, fwT = {}, 0

local function AnimateFireworks(e)
	for i = #rockets, 1, -1 do
		local r = rockets[i]
		r.fuse = r.fuse - e
		r.vy = r.vy - 150 * e
		r.x, r.y = r.x + r.vx * e, r.y + r.vy * e
		Particle("spark", r.x, r.y, random(-10, 10), random(-30, -10), 0.4, 3, 1, 0.8, r.c)
		if r.fuse <= 0 then
			tremove(rockets, i)
			Particle("flash", r.x, r.y, 0, 0, 0.15, 20, 50, 1, r.c)
			for k = 1, 28 do
				local a, s = k / 28 * 2 * math.pi, 90 + random() * 50
				Particle("spark", r.x, r.y, cos(a) * s, sin(a) * s, 1.1 + random() * 0.4, 4, 2, 1, r.c)
			end
		end
	end
end

local function ShowBanner()
	-- Sit above the scoreboard, which grows with the player count
	local y = max(40, 30 + 16 * #game.tanks + 8 + 52 - H / 2)
	banner:SetPoint("LEFT", field, "LEFT", 0, y)
	banner:SetPoint("RIGHT", field, "RIGHT", 0, y)
	banner.big:SetText(game.winTitle)
	banner.sub:SetText(game.winSub)
	local c = game.winColor or { 1, 1, 1 }
	banner.sub:SetTextColor(c[1], c[2], c[3])
	banner:SetAlpha(0)
	banner:Show()
end

-- t: seconds since the banner appeared
local function AnimateBanner(t, e)
	banner:SetAlpha(min(1, t / 0.2))
	local k = min(1, t / 0.35)
	local scale = k < 1 and 2.2 - 1.2 * (1 - (1 - k) ^ 3) or 1 + 0.03 * sin(t * 4)
	banner.slam:SetScale(scale)
	if k == 1 and not game.slammed then
		game.slammed = true
		shakeT, shakeA = 0.4, 5
	end
	if t < 7 then
		fwT = fwT - e
		if fwT <= 0 then
			tinsert(rockets, {
				x = random(40, W - 40), y = 0, vx = random(-20, 20), vy = random(260, 340),
				fuse = 0.6 + random() * 0.5, c = FWCOLORS[random(#FWCOLORS)],
			})
			fwT = 0.25 + random() * 0.35
		end
	end
end

-- Scoreboard (end of match, or hold Tab)
local sb = CreateFrame("Frame", nil, field)
sb:SetSize(380, 30 + 16 * MAXPLAYERS)
sb:SetPoint("BOTTOM", 0, 8)
sb:SetFrameLevel(field:GetFrameLevel() + 12)
Panel(sb)
sb:Hide()
do
	-- { header, x, justify }; numbers are right-aligned at x
	local SBCOLS = { { "Player", 10, "LEFT" }, { "Kills", 210 }, { "Damage", 270 }, { "Shots", 320 }, { "Wins", 370 } }
	local function Cell(font, c, y)
		local fs = sb:CreateFontString(nil, "OVERLAY", font)
		if c[3] then fs:SetPoint("TOPLEFT", c[2], -y) else fs:SetPoint("TOPRIGHT", sb, "TOPLEFT", c[2], -y) end
		return fs
	end
	for _, c in ipairs(SBCOLS) do Cell("GameFontNormalSmall", c, 8):SetText(c[1]) end
	sb.rows = {}
	for r = 1, MAXPLAYERS do
		local row = {}
		for k, c in ipairs(SBCOLS) do row[k] = Cell("GameFontHighlightSmall", c, 8 + 16 * r) end
		sb.rows[r] = row
	end
end

local function DrawScores()
	local list = {}
	for i, t in ipairs(game.tanks) do list[i] = t end
	table.sort(list, function(a, b)
		if a.kills ~= b.kills then return a.kills > b.kills end
		return a.dmg > b.dmg
	end)
	sb:SetHeight(30 + 16 * #list)
	for r, row in ipairs(sb.rows) do
		local t = list[r]
		for _, cell in ipairs(row) do cell:SetShown(t ~= nil) end
		if t then
			local c = vis[t.i].color
			row[1]:SetText(Short(t.name) .. (t.alive and "" or " |cff808080(dead)|r"))
			row[1]:SetTextColor(c[1], c[2], c[3])
			row[2]:SetText(t.kills)
			row[3]:SetText(t.dmg)
			row[4]:SetText(t.shots)
			row[5]:SetText(sessionWins[t.name] or 0)
		end
	end
	sb:Show()
end

-- Shop (before the match when the Shop rule is on). Left click buys, right click sells back.
-- Lists every crate item; the cart is local until Ready or the timer runs out.
local shop = CreateFrame("Frame", nil, frame)
shop:SetSize(560, 296)
shop:SetPoint("CENTER", field)
shop:SetFrameLevel(field:GetFrameLevel() + 20)
shop:EnableMouse(true)
Panel(shop)
shop:Hide()
do
	local title = shop:CreateFontString(nil, "OVERLAY")
	title:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
	title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	title:SetPoint("TOPLEFT", 12, -9)
	title:SetText("Goblin Supply Shop")
	shop.who = shop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	shop.who:SetPoint("LEFT", title, "RIGHT", 12, 0)
	shop.clock = shop:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	shop.clock:SetPoint("TOPRIGHT", -12, -10)
	shop.gold = shop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	shop.gold:SetPoint("RIGHT", shop.clock, "LEFT", -16, 0)

	-- Grouped by use, each under a small heading. Offensive fills both columns across the top;
	-- below it Utility and Defensive stack on the left, Movement sits on the right.
	shop.items = {}
	local n, y, band = 0, -32, -32
	for _, group in ipairs({ "Offensive", "Utility", "Defensive", "Movement" }) do
		local x, cols, k = 12, group == "Offensive" and 2 or 1, 0
		if group == "Utility" then band = y end
		if group == "Movement" then x, y = 284, band end
		local label = shop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("TOPLEFT", x + 2, y - 1)
		label:SetText(group)
		y = y - 13
		for i, w in ipairs(WEAPONS) do
			if w.weight and not w.crate and (w.use or "Offensive") == group then
				n, k = n + 1, k + 1
				local b = CreateFrame("Button", nil, shop)
				b:SetSize(264, 15)
				b:SetPoint("TOPLEFT", x + (k - 1) % cols * 272, y - floor((k - 1) / cols) * 16)
				b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
				local bg = b:CreateTexture(nil, "BACKGROUND")
				bg:SetAllPoints()
				bg:SetColorTexture(0.1, 0.1, 0.11)
				local hl = b:CreateTexture(nil, "HIGHLIGHT")
				hl:SetAllPoints()
				hl:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.12)
				b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				b.name:SetPoint("LEFT", 6, 0)
				b.name:SetText(WEAPONS.Icon(w, 14) .. " " .. w.name)
				local r, g, bl = Rarity(w)
				b.name:SetTextColor(r, g, bl)
				b.price = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
				b.price:SetPoint("RIGHT", -6, 0)
				b.price:SetText(Price(w) .. "g")
				b.count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				b.count:SetPoint("RIGHT", -40, 0)
				b.idx = i
				b:SetScript("OnClick", function(self, btn) shop.Pick(self.idx, btn == "RightButton") end)
				b:SetScript("OnEnter", function(self)
					local wp = WEAPONS[self.idx]
					shop.desc:SetText(wp.name .. ": |cffffffff" .. wp.desc .. "|r")
				end)
				b:SetScript("OnLeave", function() shop.desc:SetText("") end)
				shop.items[n] = b
			end
		end
		y = y - floor((k + cols - 1) / cols) * 16
	end

	shop.desc = shop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	shop.desc:SetPoint("TOPLEFT", 12, -32 - 12 * 18 - 6)
	shop.desc:SetPoint("TOPRIGHT", -12, -32 - 12 * 18 - 6)
	shop.desc:SetJustifyH("LEFT")
	local hint = shop:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOMLEFT", 12, 14)
	hint:SetText("Left click buys, right click sells back. Unspent gold buys random items.")
	shop.ready = FlatButton(shop, 110, 22, "Ready")
	shop.ready:SetPoint("BOTTOMRIGHT", -10, 8)
	shop.ready:SetScript("OnClick", function() shop.Submit() end)

	-- cart: item indices bought so far; spends from the match's gold rule
	function shop.Spent()
		local s = 0
		for _, k in ipairs(shop.cart) do s = s + Price(WEAPONS[k]) end
		return s
	end

	-- Whether one more of weapon k fits under its stack limit (owned plus already in the cart)
	function shop.Room(k)
		local w = WEAPONS[k]
		if w.power then return true end
		local n = max(0, game.tanks[shop.for_].ammo[k])
		for _, c in ipairs(shop.cart) do if c == k then n = n + 1 end end
		return n < 1
	end

	function shop.Pick(k, sell)
		local cart = shop.cart
		if sell then
			for j = #cart, 1, -1 do
				if cart[j] == k then tremove(cart, j) break end
			end
		elseif shop.Room(k) and shop.Spent() + Price(WEAPONS[k]) <= game.rules.gold then
			tinsert(cart, k)
		end
		shop.Draw()
	end

	function shop.Draw()
		local left = game.rules.gold - shop.Spent()
		shop.gold:SetFormattedText("Gold: |cffffffff%d|r", left)
		for _, b in ipairs(shop.items) do
			local have = 0
			for _, k in ipairs(shop.cart) do if k == b.idx then have = have + 1 end end
			local w = WEAPONS[b.idx]
			b.count:SetText(have > 0 and ("x" .. have * ((w.power or w.one) and 1 or CRATEAMMO)) or "")
			b:SetAlpha((have > 0 or (Price(w) <= left and shop.Room(b.idx))) and 1 or 0.4)
		end
	end

	shop:SetScript("OnUpdate", function()
		local s = game and game.shopping
		if not s then return end
		local left = max(0, ceil(s.ends - GetTime()))
		shop.clock:SetText((left <= 5 and "|cffff5040" or "") .. left .. "s")
		if left <= 0 then shop.Submit() end
	end)
end

------------------------------------------------------------------------
-- HUD and drawing
------------------------------------------------------------------------
local hud = CreateFrame("Frame", nil, frame)
hud:SetPoint("BOTTOMLEFT", 8, 6)
hud:SetSize(W, HUDH - 4)
do
	local bg = hud:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.1, 0.1, 0.11)

	local function Text(x, font)
		local fs = hud:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
		fs:SetPoint("LEFT", x, 0)
		return fs
	end
	local function Bar(x, w)
		local b = hud:CreateTexture(nil, "ARTWORK")
		b:SetPoint("LEFT", x, 0)
		b:SetSize(w, 10)
		b:SetColorTexture(0, 0, 0, 0.6)
		return b
	end

	hud.weapon = Text(8)

	-- Hovering the weapon name shows a flat tooltip with its description
	local hover = CreateFrame("Frame", nil, hud)
	hover:SetPoint("TOPLEFT")
	hover:SetPoint("BOTTOMLEFT")
	hover:SetWidth(196)
	hover:EnableMouse(true)
	local tip = CreateFrame("Frame", nil, hover)
	tip:SetFrameStrata("TOOLTIP")
	tip:SetWidth(240)
	tip:SetPoint("BOTTOMLEFT", hover, "TOPLEFT", 0, 6)
	Panel(tip)
	tip:Hide()
	tip.title = tip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	tip.title:SetPoint("TOPLEFT", 10, -9)
	tip.tier = tip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	tip.tier:SetPoint("TOPRIGHT", -10, -11)
	tip.desc = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tip.desc:SetPoint("TOPLEFT", tip.title, "BOTTOMLEFT", 0, -5)
	tip.desc:SetWidth(220)
	tip.desc:SetJustifyH("LEFT")
	tip.stats = tip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	tip.stats:SetPoint("TOPLEFT", tip.desc, "BOTTOMLEFT", 0, -6)
	hud.tip = tip

	function hud.ShowTip()
		local t = game.tanks[game.cur]
		local w, ammo = WEAPONS[t.weapon], t.ammo[t.weapon]
		local r, g, b, tier = Rarity(w)
		tip.title:SetText(WEAPONS.Icon(w, 18) .. " " .. w.name)
		tip.title:SetTextColor(r, g, b)
		tip.tier:SetText(tier)
		tip.desc:SetText(w.desc)
		local stats
		if w.power then
			stats = "Power-up: press Space to use"
		elseif w.dmg then
			stats = ("Damage %d%s   Radius %d"):format(w.dmg, w.napalm and " per blob" or "", w.napalm or w.radius)
		else
			stats = "No damage"
		end
		tip.stats:SetText(stats .. "   |cff9a9a9a" .. (ammo < 0 and "Unlimited" or ("x" .. ammo)) .. "|r")
		tip:SetHeight(9 + tip.title:GetStringHeight() + 5 + tip.desc:GetStringHeight() + 6 + tip.stats:GetStringHeight() + 10)
		tip:Show()
	end
	hover:SetScript("OnEnter", function() if game and not (hud.pick and hud.pick:IsShown()) then hud.ShowTip() end end)
	hover:SetScript("OnLeave", function() tip:Hide() end)
	hud.hover = hover

	-- Driving fuel meter: full = the Max fuel rule (Rocket Boots can overfill it)
	Text(202, "GameFontNormal"):SetText("Fuel")
	local fuelBg = Bar(232, 50)
	hud.fuelFill = hud:CreateTexture(nil, "OVERLAY")
	hud.fuelFill:SetPoint("LEFT", fuelBg, "LEFT", 1, 0)
	hud.fuelFill:SetHeight(8)
	hud.fuelFill:SetTexture(MEDIA .. "bar")
	hud.fuelFill:SetVertexColor(0.45, 0.95, 0.35)

	Text(294, "GameFontNormal"):SetText("Power")
	local powerBg = Bar(334, 74)
	hud.powerFill = hud:CreateTexture(nil, "OVERLAY")
	hud.powerFill:SetPoint("LEFT", powerBg, "LEFT", 1, 0)
	hud.powerFill:SetHeight(8)
	hud.powerFill:SetTexture(MEDIA .. "bar")
	hud.powerFill:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
	hud.power = Text(414)
	hud.angle = Text(442)
	Text(508, "GameFontNormal"):SetText("Wind")
	hud.windBg = Bar(540, 56)
	local mid = hud:CreateTexture(nil, "OVERLAY", nil, 1)
	mid:SetColorTexture(GOLD[1], GOLD[2], GOLD[3])
	mid:SetSize(1, 12)
	mid:SetPoint("CENTER", hud.windBg)
	hud.windFill = hud:CreateTexture(nil, "OVERLAY")
	hud.windFill:SetHeight(8)
	hud.windFill:SetColorTexture(0.5, 0.8, 1, 0.8)
	hud.windText = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hud.windText:SetPoint("BOTTOM", hud.windBg, "TOP", 0, 1)
end

local function ResizeField()
	frame:SetWidth(W + 16)
	field:SetWidth(W)
	hud:SetWidth(W)
	for i = #cols + 1, NCOLS do CreateCol(i) end
	for i = NCOLS + 1, #cols do
		cols[i]:Hide()
		cols[i].shadow:Hide()
		grass[i]:Hide()
	end
end

-- Subtle terrain shading. Slopes facing the upper-left light get a little brighter near the surface
-- and the far side a little darker, fading back to plain dirt further down; the slope is measured
-- over 20px so neighbouring columns blend instead of streaking. Each column also carries a soft
-- shadow over the bottom 90px of the field, its strength set by height alone so columns line up.
-- field.dirt / field.top: the biome colours, dimmed for the sky.
field.lo, field.hi = CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1)
field.s0, field.s1 = CreateColor(0, 0, 0, 0.45), CreateColor(0, 0, 0, 0)
function field.Shade(i)
	local d, h = field.dirt, hv[i]
	if not d or not h or h < 1 then return end
	local rise = ((hv[min(NCOLS, i + 5)] or h) - (hv[max(1, i - 5)] or h)) / (10 * COLW)
	local lit = 1 + 0.14 * max(-1, min(1, rise))
	field.lo:SetRGBA(d[1], d[2], d[3], 1)
	field.hi:SetRGBA(d[1] * lit, d[2] * lit, d[3] * lit, 1)
	cols[i]:SetGradient("VERTICAL", field.lo, field.hi)
	local g, f = field.top, (i % 3 == 0 and 0.9 or 1) * lit
	grass[i]:SetColorTexture(g[1] * f, g[2] * f, g[3] * f)
end
-- Re-shades columns lo..hi plus the 5 either side whose slope they feed into
function field.ShadeRange(lo, hi)
	for j = max(1, lo - 5), min(NCOLS, hi + 5) do field.Shade(j) end
end

local function SetCol(i, h)
	local c = cols[i]
	if h < 1 then
		c:Hide()
		c.shadow:Hide()
		grass[i]:Hide()
		return
	end
	c:SetHeight(h)
	c:SetTexCoord((i - 1) * COLW / 64, i * COLW / 64, (H - h) / 64, H / 64)
	c:Show()
	grass[i]:Show()
	-- Shadow: 0.45 at the bottom fading to nothing at 90px; a shorter column stops partway down the fade
	local sh = min(h, 90)
	field.s1:SetRGBA(0, 0, 0, 0.45 * (1 - sh / 90))
	c.shadow:SetHeight(sh)
	c.shadow:SetGradient("VERTICAL", field.s0, field.s1)
	c.shadow:Show()
end

local function DrawTerrain(snap)
	if not snap then terrainDirty = true return end
	for i = 1, NCOLS do
		hv[i], hvv[i] = game.h[i], 0
		SetCol(i, hv[i])
	end
	field.ShadeRange(1, NCOLS)
end

local function DrawTank(i)
	local t, v = game.tanks[i], vis[i]
	local shown = t and (t.alive or v.alive) and true or false -- v.alive: still drawn on its way to a pit
	if i == game.cur then field.Laser(t, v, shown) end
	for _, r in ipairs(v.parts) do r:SetShown(shown) end
	v.shield:SetShown(shown and t.shield > 0)
	if not shown then return end
	v.x, v.y = v.x or t.x, v.y or t.y
	v.hpv, v.lastHp = v.hpv or t.hp, v.lastHp or t.hp
	local x, y, a, maxhp = v.x, v.y, rad(t.angle), game.rules.hp
	local len, f, c = BARREL * (1 - 2 * (v.recoil or 0)), v.flash or 0, v.color
	-- Hull tilts with the ground around its bottom centre; the barrel keeps its own world angle
	local tilt = v.tilt or 0
	local ts, tc = sin(tilt), cos(tilt)
	v.body:SetPoint("CENTER", field, "BOTTOMLEFT", x - ts * 5.5, y + tc * 5.5)
	v.body:SetRotation(tilt)
	-- Sprite faces right; mirror it when aiming left so the exhaust stays at the back
	if t.angle > 90 then v.body:SetTexCoord(1, 0, 0, 1) else v.body:SetTexCoord(0, 1, 0, 1) end
	v.body:SetVertexColor(c[1] + (1 - c[1]) * f, c[2] + (1 - c[2]) * f, c[3] + (1 - c[3]) * f)
	local bx, by = x - ts * TURRET, y + tc * TURRET
	v.barrel:SetStartPoint("BOTTOMLEFT", field, bx, by)
	v.barrel:SetEndPoint("BOTTOMLEFT", field, bx + cos(a) * len, by + sin(a) * len)
	v.hpbg:SetPoint("BOTTOM", field, "BOTTOMLEFT", x, y + 24)
	v.hp:SetWidth(max(0.1, 20 * v.hpv / maxhp))
	v.hp:SetColorTexture(1 - v.hpv / maxhp, 0.3 + 0.6 * v.hpv / maxhp, 0.2)
	v.label:SetText(Short(t.name))
	if t.shield > 0 then
		v.shield:SetPoint("CENTER", field, "BOTTOMLEFT", x, y + 6)
		v.shield:SetAlpha((0.35 + 0.5 * t.shield / SHIELD) * (0.85 + 0.15 * sin(GetTime() * 5)))
	end
end

local function TimeLeft() return game.rules.time - (GetTime() - game.turnStart) end

local function DrawStatus()
	if game.solo then
		restartBtn:SetText("Lobby")
		restartBtn:Show()
	elseif game.host == Me() then
		local n = 0
		for _ in pairs(game.specs) do n = n + 1 end
		restartBtn:SetText(("Restart (%d)"):format(n)) -- n = spectators who'll join the new lobby
		restartBtn:Show()
	else
		restartBtn:Hide()
	end
	restartBtn.again:SetShown(game.over ~= nil and (game.solo or game.host == Me()))
	frame.after:SetText("")
	frame.turnText:SetText("")
	frame.whoText:SetText("")
	frame.teamText:SetText("")
	if game.over then
		status:SetText(game.over)
		frame.clock:SetText("")
		return
	end

	-- Clock: watch icon and m:ss, red for the last 5 seconds, dashes while a shot is in the air,
	-- blue while the shooter drives away after the shot
	local left = game.shopping and game.shopping.ends - GetTime() or (game.retreat and game.retreat - GetTime()) or TimeLeft()
	if game.shot or game.landed then
		frame.clock:SetText("|TInterface\\Icons\\INV_Misc_PocketWatch_01:16:16:0:0:64:64:5:59:5:59|t |cff808080-:--|r")
	else
		left = max(0, ceil(left))
		frame.clock:SetFormattedText("|TInterface\\Icons\\INV_Misc_PocketWatch_01:16:16:0:0:64:64:5:59:5:59|t %s%d:%02d|r",
			game.retreat and "|cff7fd4ff" or (left <= 5 and "|cffff5040" or "|cffffffff"), floor(left / 60), left % 60)
	end

	local t = game.tanks[game.cur]
	if not game.shopping then
		frame.turnText:SetText("Turn " .. game.turn)
		frame.whoText:SetText(Short(t.name))
		if game.teams then
			local c = TEAMCOLORS[t.team][1]
			frame.teamText:SetText("Team " .. t.team)
			frame.teamText:SetTextColor(c[1], c[2], c[3])
		end
	end
	if game.shopping then
		status:SetText("|cffd4af37Shopping|r")
	elseif game.targeting then
		status:SetText("|cff66ccffClick where to teleport|r  (right-click cancels)")
	elseif game.jet then
		status:SetText("|cff66ccffJetpack!|r  steer with WASD or the arrow keys")
	else
		-- With 3+ tanks alive (or on a solo computer tank's turn): how many players go before you,
		-- counting the one up now. Solo, "you" is the next tank the computer doesn't play.
		local wait, alive, n, mine = "", 0, 0, false
		for _, tk in ipairs(game.tanks) do
			if tk.alive then alive = alive + 1 end
		end
		if (alive >= 3 and not game.solo and t.name ~= Me()) or (game.solo and t.ai) then
			local k = #game.order
			for step = 0, k - 1 do
				local tk = game.tanks[game.order[(game.oi - 1 + step) % k + 1]]
				if (game.solo and not tk.ai and tk.alive) or (not game.solo and tk.name == Me()) then
					mine = tk.alive
					break
				end
				if tk.alive then n = n + 1 end
			end
		end
		if mine then wait = n == 1 and "|cff7fd4ffYou're next|r" or ("|cff7fd4ffYour turn in %d players|r"):format(n) end
		status:SetText(game.spectating and "|cff808080Watching|r" or "")
		frame.after:SetText(wait)
	end

	local cap = max(1, game.rules.moves * game.rules.dist)
	hud.fuelFill:SetWidth(max(0.1, 48 * min(1, t.fuel / cap)))
	hud.fuelFill:SetShown(t.fuel > 0)

	local w, ammo = WEAPONS[t.weapon], t.ammo[t.weapon]
	local r, g, b = Rarity(w)
	hud.weapon:SetFormattedText("|cff808080Q|r %s |cff%02x%02x%02x%s|r%s |cff808080E|r", WEAPONS.Icon(w, 16),
		floor(r * 255), floor(g * 255), floor(b * 255), w.name, ammo < 0 and "" or (" x" .. ammo))
	if hud.tip:IsShown() then hud.ShowTip() end -- follow Q/E while hovering
	hud.powerFill:SetWidth(max(1, 72 * t.power / 100))
	hud.power:SetText(floor(t.power + 0.5))
	hud.angle:SetFormattedText("Angle %d", floor(t.angle + 0.5))

	local wind = game.wind
	hud.windText:SetText(wind == 0 and "calm" or abs(wind))
	hud.windFill:SetShown(wind ~= 0)
	hud.windFill:ClearAllPoints()
	hud.windFill:SetPoint(wind < 0 and "RIGHT" or "LEFT", hud.windBg, "CENTER")
	hud.windFill:SetWidth(max(1, 27 * abs(wind) / max(20, game.windMax))) -- full bar = this match's strongest wind
end

local function DrawAll()
	DrawTerrain()
	for i = 1, MAXPLAYERS do DrawTank(i) end
	DrawStatus()
end

------------------------------------------------------------------------
-- Toast (movable, starts under the minimap) and lobby panel
------------------------------------------------------------------------
local TOASTW, TOASTTIME = 250, 30
local toast = CreateFrame("Frame", nil, UIParent)
toast:SetSize(TOASTW, 76)
toast:SetFrameStrata("HIGH")
Draggable(toast)
Panel(toast)
toast:Hide()

-- Saved position (GoblinShellshockDB.toast), else just under the minimap
local function PlaceToast()
	toast:ClearAllPoints()
	local p = GoblinShellshockDB and GoblinShellshockDB.toast
	if p then
		toast:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	elseif MinimapCluster then
		toast:SetPoint("TOP", MinimapCluster, "BOTTOM", 0, -6)
	else
		toast:SetPoint("TOPRIGHT", -16, -230)
	end
end
PlaceToast()

toast:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local p, _, rp, x, y = self:GetPoint()
	GoblinShellshockDB = GoblinShellshockDB or {}
	GoblinShellshockDB.toast = { p, rp, x, y }
end)

do
	local icon = toast:CreateTexture(nil, "OVERLAY")
	icon:SetSize(16, 16)
	icon:SetPoint("TOPLEFT", 8, -6)
	icon:SetTexture(MEDIA .. "cog")
	icon:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])

	local name = toast:CreateFontString(nil, "OVERLAY")
	name:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
	name:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
	name:SetText("Goblin Shellshock")

	local hint = toast:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOMRIGHT", -10, 14)
	hint:SetText("drag to move")

	local x = FlatButton(toast, 16, 16, "x")
	x:SetPoint("TOPRIGHT", -5, -5)
	x:SetScript("OnClick", function() toast:Hide() end)

	toast.text = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	toast.text:SetPoint("TOPLEFT", 10, -28)
	toast.text:SetPoint("TOPRIGHT", -10, -28)
	toast.text:SetJustifyH("LEFT")

	local b = CreateFrame("Button", nil, toast)
	b:SetSize(100, 20)
	b:SetPoint("BOTTOMLEFT", 10, 10)
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.15)
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	b.label:SetPoint("CENTER")
	b.label:SetTextColor(0.08, 0.06, 0.02)
	b:SetScript("OnClick", function()
		toast:Hide()
		if toast.action then toast.action() end
	end)
	toast.btn = b

	-- Thin gold bar along the bottom that runs down until the toast expires
	toast.timer = toast:CreateTexture(nil, "OVERLAY")
	toast.timer:SetPoint("BOTTOMLEFT", 1, 1)
	toast.timer:SetHeight(2)
	toast.timer:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.7)
end

toast:SetScript("OnUpdate", function(self)
	if not self.expire then return end
	local left = self.expire - GetTime()
	if left <= 0 then self:Hide() return end
	self.timer:SetWidth(max(1, (TOASTW - 2) * left / TOASTTIME))
end)

-- duration nil keeps the toast up until closed (used for the move preview)
local function ShowToast(text, label, fn, owner, duration)
	toast.text:SetText(text)
	toast.btn.label:SetText(label)
	toast.action, toast.owner = fn, owner
	toast.expire = duration and GetTime() + duration
	toast.timer:SetWidth(TOASTW - 2)
	toast:Show()
	UIFrameFadeIn(toast, 0.25, 0, 1)
end

local function HideToast(owner)
	if not owner or toast.owner == owner then toast:Hide() end
end

local LW, RW = 280, 250 -- player column, rules column
local lobbyFrame = CreateFrame("Frame", "GoblinShellshockLobby", UIParent)
lobbyFrame:SetSize(LW + RW, 170 + MAXPLAYERS * 25 + 40)
lobbyFrame:SetPoint("TOP", toast, "BOTTOM", 0, -6)
lobbyFrame:SetFrameStrata("HIGH")
Draggable(lobbyFrame)
Panel(lobbyFrame)
lobbyFrame:Hide()
-- Escape leaves the lobby, like the x (not UISpecialFrames, which would only hide it)
lobbyFrame:EnableKeyboard(true)
if not InCombatLockdown() then lobbyFrame:SetPropagateKeyboardInput(true) end
lobbyFrame:SetScript("OnKeyDown", function(self, key)
	if InCombatLockdown() then return end
	self:SetPropagateKeyboardInput(key ~= "ESCAPE")
	if key == "ESCAPE" then frame.Quit() end
end)

do
	local L = lobbyFrame
	local header = L:CreateTexture(nil, "ARTWORK")
	header:SetPoint("TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", -1, -1)
	header:SetHeight(31)
	header:SetColorTexture(0.11, 0.11, 0.13)

	local line = L:CreateTexture(nil, "ARTWORK", nil, 1)
	line:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
	line:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
	line:SetHeight(1)
	line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.6)

	local icon = L:CreateTexture(nil, "OVERLAY")
	icon:SetSize(20, 20)
	icon:SetPoint("LEFT", header, "LEFT", 8, 0)
	icon:SetTexture(MEDIA .. "cog")
	icon:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])

	local name = L:CreateFontString(nil, "OVERLAY")
	name:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
	name:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
	name:SetText("Goblin Shellshock |cffffffffLobby|r")

	local x = FlatButton(L, 18, 18, "x")
	x:SetPoint("RIGHT", header, "RIGHT", -6, 0)
	x:SetScript("OnClick", function() frame.Quit() end)
	local mini = FlatButton(L, 18, 18, "_")
	mini:SetPoint("RIGHT", header, "RIGHT", -26, 0)
	mini:SetScript("OnClick", function() L:Hide() end)

	L.count = L:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	L.count:SetPoint("RIGHT", header, "RIGHT", -50, 0)

	frame.ScaleSlider(L, -90, -7)

	L.host = L:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	L.host:SetPoint("TOPLEFT", 12, -42)

	-- Segmented toggles: gold underline marks the active one
	local function Segment(text, x, y, w)
		local b = FlatButton(L, w, 22, text)
		b:SetPoint("TOPLEFT", x, y)
		b.line = b:CreateTexture(nil, "OVERLAY")
		b.line:SetPoint("BOTTOMLEFT")
		b.line:SetPoint("BOTTOMRIGHT")
		b.line:SetHeight(2)
		b.line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3])
		return b
	end
	local half = (LW - 24) / 2
	L.ffa = Segment("Free for all", 10, -58, half)
	L.teams = Segment("Teams", 14 + half, -58, half)
	L.presets = {}
	local third = (LW - 28) / 3
	for k, p in ipairs(PRESETS) do L.presets[k] = Segment(p.name, 10 + (k - 1) * (third + 4), -84, third) end

	L.desc = L:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	L.desc:SetPoint("TOP", L, "TOPLEFT", LW / 2, -110)

	L.rows = {}
	for i = 1, MAXPLAYERS do
		local r = CreateFrame("Button", nil, L)
		r:SetSize(LW - 20, 24)
		r:SetPoint("TOPLEFT", 10, -126 - (i - 1) * 25)
		local bg = r:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.1, 0.1, 0.11)
		local hl = r:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.1)
		r.stripe = r:CreateTexture(nil, "ARTWORK")
		r.stripe:SetPoint("TOPLEFT")
		r.stripe:SetPoint("BOTTOMLEFT")
		r.stripe:SetWidth(3)
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(20, 10)
		r.icon:SetPoint("LEFT", 10, 0)
		r.icon:SetTexture(MEDIA .. "tank")
		r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		r.name:SetPoint("LEFT", 38, 0)
		r.pillBg = r:CreateTexture(nil, "ARTWORK")
		r.pillBg:SetSize(52, 16)
		r.pillBg:SetPoint("RIGHT", -6, 0)
		r.pill = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		r.pill:SetPoint("CENTER", r.pillBg)
		r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		r.tag:SetPoint("RIGHT", r.pillBg, "LEFT", -8, 0)
		-- Solo only: hands this tank to the computer, cycling off / Easy / Normal / Hard
		-- (gold underline while on). Centred under the host row's "Host" tag.
		r.ai = FlatButton(r, 96, 16, "Computer")
		r.ai:SetPoint("CENTER", r, "RIGHT", -79, 0)
		r.ai.line = r.ai:CreateTexture(nil, "OVERLAY")
		r.ai.line:SetPoint("BOTTOMLEFT")
		r.ai.line:SetPoint("BOTTOMRIGHT")
		r.ai.line:SetHeight(2)
		r.ai.line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3])
		L.rows[i] = r
	end

	L.hint = L:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	local below = -126 - MAXPLAYERS * 25 -- first free spot under the player rows
	L.hint:SetPoint("TOP", L, "TOPLEFT", LW / 2, below - 4)

	-- Solo only: add or remove hotseat tanks
	L.less = FlatButton(L, half, 20, "- Tank")
	L.less:SetPoint("TOPLEFT", 10, below - 20)
	L.more = FlatButton(L, half, 20, "+ Tank")
	L.more:SetPoint("TOPLEFT", 14 + half, below - 20)
	-- Group host only (same spot): pops the Join toast again for everyone not in the lobby yet
	L.announce = FlatButton(L, half * 2 + 4, 20, "Announce lobby again")
	L.announce:SetPoint("TOPLEFT", 10, below - 20)

	L.action = FlatButton(L, half, 24)
	L.action:SetPoint("BOTTOMLEFT", 10, 10)
	L.actionBg = L.action:CreateTexture(nil, "BORDER")
	L.actionBg:SetAllPoints()
	-- Own label so the colour isn't reset by the button's font objects on hover
	L.actionLabel = L.action:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	L.actionLabel:SetPoint("CENTER")
	L.close = FlatButton(L, half, 24, "Close lobby")
	L.close:SetPoint("BOTTOMLEFT", 14 + half, 10)

	-- Rules column: one stepper row per setting
	local sep = L:CreateTexture(nil, "ARTWORK")
	sep:SetPoint("TOPLEFT", LW, -40)
	sep:SetPoint("BOTTOMLEFT", LW, 10)
	sep:SetWidth(1)
	sep:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
	local head = L:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	head:SetPoint("TOPLEFT", LW + 12, -42)
	head:SetText("Rules")
	L.custom = L:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	L.custom:SetPoint("TOPRIGHT", -12, -44)
	L.rules = {}
	local y = -62
	for k, d in ipairs(RULEDEFS) do
		-- Category heading, with a little gap above all but the first
		if d.cat then
			if k > 1 then y = y - 6 end
			local cat = L:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			cat:SetPoint("TOPLEFT", LW + 12, y)
			cat:SetText(d.cat)
			local rule = L:CreateTexture(nil, "ARTWORK")
			rule:SetPoint("LEFT", cat, "RIGHT", 6, 0)
			rule:SetSize(RW - 24 - cat:GetStringWidth() - 6, 1)
			rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
			y = y - 16
		end
		local label = L:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("TOPLEFT", LW + 12, y - 4)
		label:SetText(d.label)
		local less = FlatButton(L, 18, 18, "<")
		less:SetPoint("TOPLEFT", LW + 116, y)
		local val = L:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		val:SetPoint("TOP", L, "TOPLEFT", LW + 116 + 18 + 43, y - 4)
		local more = FlatButton(L, 18, 18, ">")
		more:SetPoint("TOPLEFT", LW + 116 + 18 + 86, y)
		L.rules[k] = { label = label, less = less, more = more, val = val }
		if d.toggle then
			-- One button across the arrows and the value; non-hosts see the plain value instead
			local tog = FlatButton(L, 18 + 86 + 18, 18)
			tog:SetPoint("TOPLEFT", LW + 116, y)
			L.rules[k].toggle = tog
		end
		y = y - 21
	end
	L.note = L:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	L.note:SetPoint("TOPLEFT", LW + 12, y - 2)
	L.note:SetWidth(RW - 24)
	L.note:SetJustifyH("LEFT")
end

local function InRoster(list, name)
	for _, p in ipairs(list) do
		if p.name == name then return true end
	end
end

local function DrawLobby()
	if not lobby then lobbyFrame:Hide() return end
	local L = lobbyFrame
	local host, teams, players = lobby.host == Me(), lobby.teams, lobby.players
	L.host:SetText(lobby.solo and "|cffd4af37Solo test|r   you control every tank" or ("Hosted by |cffd4af37" .. Short(lobby.host) .. "|r   v" .. VERSION))
	L.count:SetFormattedText("%d/%d", #players, MAXPLAYERS)

	L.ffa.line:SetShown(not teams)
	L.teams.line:SetShown(teams)
	L.ffa:SetEnabled(host or not teams)
	L.teams:SetEnabled(host or teams)
	local rules, preset = lobby.rules, RULEDEFS.Preset(lobby.rules)
	for k, b in ipairs(L.presets) do
		b.line:SetShown(preset == k)
		b:SetEnabled(host or preset == k)
	end
	L.desc:SetText(preset and PRESETS[preset].desc or "Custom rules.")
	L.custom:SetText(preset and "" or "Custom")
	for k, d in ipairs(RULEDEFS) do
		local row, v = L.rules[k], rules[d.key]
		row.val:SetText(RULEDEFS.Show(d, v))
		row.less:SetShown(host and not row.toggle)
		row.more:SetShown(host and not row.toggle)
		if row.toggle then
			row.toggle:SetText(RULEDEFS.Show(d, v))
			row.toggle:SetShown(host)
			row.val:SetShown(not host)
		end
		row.less:SetEnabled(v > d.lo)
		row.more:SetEnabled(v < d.hi)
		local dim = (d.key == "gold" and rules.shop == 0) or (d.key == "mix" and not teams)
		row.label:SetAlpha(dim and 0.4 or 1)
		row.val:SetAlpha(dim and 0.4 or 1)
	end
	local sky = SKIES[rules.sky]
	L.note:SetText(sky and sky.desc or (rules.sky == 0 and "Random sky. Rain and storms bring stronger wind." or ""))
	L.less:SetShown(lobby.solo)
	L.more:SetShown(lobby.solo)
	L.less:SetEnabled(#players > 2)
	L.more:SetEnabled(#players < MAXPLAYERS)

	-- Teams mode lists Team 1 first; each row remembers its player for clicks
	local order = {}
	for team = 1, 2 do
		for i, p in ipairs(players) do
			if not teams or p.team == team then tinsert(order, { p = p, i = i }) end
		end
		if not teams then break end
	end
	local shade = { 0, 0 }
	for k, r in ipairs(L.rows) do
		local e = order[k]
		r.player = e and e.p
		if e then
			local p, c = e.p, COLORS[e.i]
			if teams then
				shade[p.team] = shade[p.team] + 1
				local set = TEAMCOLORS[p.team]
				c = set[(shade[p.team] - 1) % #set + 1]
			end
			r.stripe:SetColorTexture(c[1], c[2], c[3])
			r.icon:SetVertexColor(c[1], c[2], c[3])
			r.icon:Show()
			r.name:SetText(Short(p.name))
			r.name:SetTextColor(1, 1, 1)
			r.tag:SetText(p.name == lobby.host and "Host" or (p.name == Me() and "|cff9a9a9aYou|r" or ""))
			r.ai:SetShown(lobby.solo and p.name ~= Me())
			-- Under the "Host" tag; with teams it moves left so it clears the team pill
			r.ai:ClearAllPoints()
			if teams then
				r.ai:SetPoint("RIGHT", r.pillBg, "LEFT", -6, 0)
			else
				r.ai:SetPoint("CENTER", r, "RIGHT", -79, 0)
			end
			r.ai.line:SetShown(p.ai and true or false)
			r.ai:SetText(p.ai and ("|cffd4af37Computer: " .. frame.AILEVELS[p.ai].name .. "|r") or "|cff808080Computer|r")
			r.pillBg:SetShown(teams)
			r.pill:SetShown(teams)
			if teams then
				local tc = TEAMCOLORS[p.team][1]
				r.pillBg:SetColorTexture(tc[1], tc[2], tc[3], 0.25)
				r.pill:SetText("Team " .. p.team)
			end
		else
			r.stripe:SetColorTexture(0.25, 0.25, 0.27)
			r.icon:Hide()
			r.name:SetText("Open slot")
			r.name:SetTextColor(0.4, 0.4, 0.42)
			r.tag:SetText("")
			r.ai:Hide()
			r.pillBg:Hide()
			r.pill:Hide()
		end
	end

	if host then
		L.hint:SetText(teams and "Click a player to move them to the other team." or (lobby.solo and "Click Computer on a tank to let the computer play it (again for harder)." or "Waiting for players to join."))
	else
		L.hint:SetText(InRoster(players, Me()) and "Waiting for the host to start." or "Joining...")
	end

	-- Host gets a gold primary Start button; others get Leave
	local ready = host and #players >= 2
	L.actionLabel:SetText(host and "Start match" or "Leave")
	L.action:SetEnabled(not host or ready)
	L.actionBg:SetShown(ready)
	L.actionBg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.85)
	if ready then
		L.actionLabel:SetTextColor(0.08, 0.06, 0.02)
	elseif host then
		L.actionLabel:SetTextColor(0.5, 0.5, 0.5)
	else
		L.actionLabel:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	end
	L.close:SetShown(host)
	L.close:SetText(lobby.solo and "Close" or "Close lobby")
	L.announce:SetShown(host and not lobby.solo)
end

-- How-to-play card over the game window. Opens by itself on your first match, then from the ? button.
-- Built on first use.
function frame.Help()
	local h = frame.help
	if not h then
		local function K(s) return "|cff7fd4ff" .. s .. "|r" end -- keys stand out from the prose
		h = CreateFrame("Frame", nil, frame)
		h:SetWidth(320)
		h:SetPoint("CENTER", field)
		h:SetFrameLevel(frame:GetFrameLevel() + 50)
		h:EnableMouse(true)
		Panel(h)
		local title = h:CreateFontString(nil, "OVERLAY")
		title:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
		title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		title:SetPoint("TOPLEFT", 12, -10)
		title:SetText("How to play")
		local goal = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		goal:SetPoint("TOPLEFT", 12, -32)
		goal:SetWidth(296)
		goal:SetJustifyH("LEFT")
		goal:SetText("Take turns shelling each other. The last tank or team standing wins.")
		-- A one-entry row is a section heading
		local lines = {
			{ "Controls" },
			{ "Aim", K("Left") .. " / " .. K("Right") .. " set the angle, " .. K("Up") .. " / " .. K("Down") .. " set the power." },
			{ "Fire", K("Space") },
			{ "Items", K("Q") .. " / " .. K("E") .. " switch weapon or item. Hover its icon to see what it does." },
			{ "Move", "Hold " .. K("A") .. " / " .. K("D") .. " to drive. It uses fuel (the green bar next to Power), refilled a bit each turn. You can keep driving while your shot flies, and for up to 3 seconds of the timer after it lands." },
			{ "Scores", "Hold " .. K("Tab") },
			{ "Window", K("/gs") .. " shows or hides it." },
			{ "Effects" },
			{ "Wind", "Watch the wind gauge, it bends every shot. Rain and storms blow harder." },
			{ "Crates", "Supply crates drop now and then. Touch one for extra ammo." },
			{ "Portals", "In big matches two teleporters drop in late. Drive into one to come out of the other." },
			{ "Shop", "If the shop is on, spend your gold before the first shot." },
			{ "Timer", "Fire before the shot timer runs out or you lose the turn." },
			{ "Combat", "Entering combat hides the game." },
		}
		local y = -32 - goal:GetStringHeight() - 8
		for _, l in ipairs(lines) do
			if not l[2] then
				local s = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
				s:SetPoint("TOPLEFT", 12, y - 4)
				s:SetText(l[1])
				y = y - 4 - s:GetStringHeight() - 6
			else
				local k = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
				k:SetPoint("TOPLEFT", 12, y)
				k:SetText(l[1])
				local v = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				v:SetPoint("TOPLEFT", 64, y)
				v:SetWidth(244)
				v:SetJustifyH("LEFT")
				v:SetText(l[2])
				y = y - v:GetStringHeight() - 7
			end
		end
		local ok = FlatButton(h, 90, 22, "Got it")
		ok:SetPoint("TOP", h, "TOP", 0, y - 6)
		ok:SetScript("OnClick", function() h:Hide() end)
		h:SetHeight(-y + 40)
		frame.help = h
	end
	h:Show()
end

local function ShowLobby()
	DrawLobby()
	lobbyFrame:Show()
end

------------------------------------------------------------------------
-- Simulation (integer state only: terrain, positions, hp, crates)
------------------------------------------------------------------------
-- Returns heights and the style name. Styles change the control point spacing,
-- height range and smoothing, then add a shape on top. pick: the Terrain rule (0 = random).
local function GenTerrain(pick)
	local STYLES = { "hills", "mountain", "valley", "mesas", "twin peaks" }
	local style = pick > 0 and pick or Rand(1, #STYLES)
	local step, lo, hi, smooth = 30, 60, 200, 3
	if style == 3 then
		lo, hi = 110, 210
	elseif style == 4 then
		step, smooth = 40, 0
	end

	local h, pts = {}, {}
	for k = 0, NCOLS / step do pts[k] = Rand(lo, hi) end
	for i = 1, NCOLS do
		local k = floor((i - 1) / step)
		local a, b = pts[k], pts[k + 1] or pts[k]
		h[i] = a + floor((b - a) * ((i - 1) % step) / step)
	end
	for _ = 1, smooth do
		local s = {}
		for i = 1, NCOLS do
			local sum = 0
			for j = i - 3, i + 3 do sum = sum + h[max(1, min(NCOLS, j))] end
			s[i] = floor(sum / 7)
		end
		h = s
	end

	local q = NCOLS / 4
	for i = 1, NCOLS do
		local v = h[i]
		if style == 2 then
			v = v + floor(110 * max(0, q - abs(i - 2 * q)) / q)
		elseif style == 3 then
			v = v - floor(100 * max(0, 1.2 * q - abs(i - 2 * q)) / (1.2 * q))
		elseif style == 4 then
			v = floor(v / 35) * 35 + 20
		elseif style == 5 then
			v = v + floor(80 * max(0, 0.6 * q - abs(i - q), 0.6 * q - abs(i - 3 * q)) / (0.6 * q))
		end
		h[i] = max(20, min(H - 70, v))
	end
	return h, STYLES[style]
end

local function Checksum()
	local c = 0
	for i = 1, NCOLS do c = (c * 31 + game.h[i]) % 2147483647 end
	for _, t in ipairs(game.tanks) do
		c = (c * 31 + t.hp) % 2147483647
		c = (c * 31 + t.col) % 2147483647
		c = (c * 31 + t.shield) % 2147483647
	end
	for _, k in ipairs(game.crates) do c = (c * 31 + k.col * 32 + k.w) % 2147483647 end
	for _, p in ipairs(game.props) do c = (c * 31 + (p.alive and p.col or 0)) % 2147483647 end
	return c
end

-- Sparse scenery: sometimes none, otherwise one or two kinds with a few of each
local function PlaceProps()
	local props = {}
	game.props = props
	if Rand(1, 6) == 1 then return end
	local function Free(col)
		for _, t in ipairs(game.tanks) do
			if abs(t.col - col) < 12 then return false end
		end
		for _, p in ipairs(props) do
			if abs(p.col - col) < 6 then return false end
		end
		return true
	end
	local first
	for _ = 1, Rand(1, 2) do
		local kind = PROPS[Rand(1, #PROPS)]
		if kind ~= first then
			first = first or kind
			local def = PROPS[kind]
			for _ = 1, Rand(def.min, def.max) do
				for _ = 1, 10 do -- a few tries to find a free spot
					local col = Rand(8, NCOLS - 8)
					if Free(col) then
						tinsert(props, { kind = kind, col = col, y = game.h[col], alive = true })
						break
					end
				end
			end
		end
	end
end

-- Weighted random item index (shared PRNG, so the same on every client)
-- rounds: rounds played so far (crate drops only); `late` items gain 1 weight per 3 rounds, up to +8
-- given: for starting items and the shop's leftover gold, which skip crate-only items
local function PickItem(rounds, given)
	local function Weight(w)
		if given and w.crate then return 0 end
		return (w.weight or 0) + (w.late and min(8, floor((rounds or 0) / 3)) or 0)
	end
	local total = 0
	for _, w in ipairs(WEAPONS) do total = total + Weight(w) end
	local r = Rand(1, total)
	for i, w in ipairs(WEAPONS) do
		r = r - Weight(w)
		if r <= 0 then return i end
	end
end

-- Weapons stack to CRATEAMMO (The Big One to 1); anything past that is lost
local function GiveItem(t, i)
	local w = WEAPONS[i]
	local n = max(0, t.ammo[i]) + ((w.power or w.one) and 1 or CRATEAMMO)
	t.ammo[i] = w.power and n or min(n, w.one and 1 or CRATEAMMO)
end

local function SpawnCrate(col, w)
	local c = { col = col, w = w, y = game.h[col] }
	for _, v in ipairs(crateVis) do
		if not v.used then c.v = v break end
	end
	c.v.used, c.v.y = true, H + 20
	c.v.box:Show()
	c.v.chute:Show()
	tinsert(game.crates, c)
end

-- Visual pickup: flash and name floater where the crate box is
function crateVis.Pop(v, x)
	v.used, v.to, v.wait = nil, nil, nil
	v.box:Hide()
	v.chute:Hide()
	Particle("flash", x, v.y + 6, 0, 0, 0.2, 10, 30, 1)
	local r, g, b = Rarity(v.item)
	Floater(Short(v.who) .. ": " .. v.item.name, x, v.y + 20, r, g, b)
end

-- The item is given right away (sim); the pop waits for the picture to catch up:
-- a crate still in the air falls onto its tank, one driven into waits for the tank to arrive.
-- touch: picked up by driving or landing (false when a blast collects it).
local function Collect(i, t, touch)
	local c = tremove(game.crates, i)
	GiveItem(t, c.w)
	local v = c.v
	v.item, v.who, v.x = WEAPONS[c.w], t.name, (c.col - 0.5) * COLW
	if v.chute:IsShown() then
		v.to = t.i
	elseif touch then
		v.wait = t.i
	else
		crateVis.Pop(v, v.x)
	end
end

-- Calls fn(col, dy) for every column inside a circle of radius r at x
local function Circle(x, r, fn)
	for col = max(1, floor((x - r) / COLW) + 1), min(NCOLS, floor((x + r) / COLW) + 1) do
		local dx = (col - 0.5) * COLW - x
		local d2 = r * r - dx * dx
		if d2 > 0 then fn(col, floor(sqrt(d2))) end
	end
end

local function Carve(x, y, r)
	local h = game.h
	Circle(x, r, function(col, dy)
		local lo, hi = max(0, y - dy), y + dy
		local hc = h[col]
		if hc > lo then h[col] = hc <= hi and lo or hc - (hi - lo) end
	end)
end

local function RaiseWall(x, r, height)
	local h = game.h
	for col = max(1, floor((x - r) / COLW) + 1), min(NCOLS, floor((x + r) / COLW) + 1) do
		h[col] = min(H - 20, h[col] + height)
	end
end

-- Applies damage through any shield; credits damage and kills to `by`. Returns hp lost.
local function Hurt(t, d, by)
	local absorb = min(t.shield, d)
	t.shield = t.shield - absorb
	local lost = min(t.hp, d - absorb)
	t.hp = t.hp - lost
	if by and t ~= by then by.dmg = by.dmg + lost end
	if t.hp <= 0 and t.alive then
		t.alive = false
		if by and t ~= by then by.kills = by.kills + 1 end
	end
	return lost
end

-- Blast knockback: slides a tank up to n columns away from the blast. Stops at the map edges,
-- other tanks and climbs it couldn't drive up; buried tanks stay put.
local function Nudge(t, dir, n)
	local h, col = game.h, t.col
	if h[col] > t.y then return end
	for _ = 1, n do
		local nx, free = col + dir, true
		for _, o in ipairs(game.tanks) do
			if o ~= t and o.alive and abs(o.col - nx) < TANKW / COLW + 2 then free = false end
		end
		if not free or nx < 5 or nx > NCOLS - 4 or h[nx] - h[col] > CLIMB then break end
		col = nx
		if h[col] <= 0 then break end -- a chasm down to the bottom: in it goes
	end
	t.col, t.x, t.y = col, (col - 0.5) * COLW, h[col]
end

-- Returns damage dealt to tanks other than `by`. Tanks are nudged away from the blast,
-- up to `knock` columns (default 4, so 8px) for a close hit.
-- direct: a blast on a tank's hitbox deals 60-100% damage by how close it is to the hitbox centre,
-- instead of the usual falloff.
local function Damage(x, y, r, dmg, by, knock, direct)
	local reach, dealt = r + TANKW / 2, 0
	for _, t in ipairs(game.tanks) do
		if t.alive then
			local dx, dy = t.x - x, t.y + TANKH / 2 - y
			local d2 = dx * dx + dy * dy
			local onHit = direct and abs(dx) <= HITW / 2 + 2 and y >= t.y - 3 and y <= t.y + HITH + 2
			if onHit or d2 < reach * reach then
				local hy = t.y + HITH / 2 - y
				local near = onHit and 1 - 0.4 * min(1, sqrt(dx * dx + hy * hy) / (HITW / 2 + 2))
					or (reach - sqrt(d2)) / reach
				local lost = Hurt(t, floor(dmg * near), by)
				if t ~= by then dealt = dealt + lost end
				if t.alive and dx ~= 0 then
					Nudge(t, dx > 0 and 1 or -1, floor((knock or 4) * near + 0.5))
					frame.Warp(t) -- shoved into a teleporter
				end
			end
		end
	end
	return dealt
end

-- Napalm: falls off with horizontal distance along the ground
-- Falloff only halves the damage at the edge, so how many blobs land on a tank matters more than where
local function Burn(x, y, reach, dmg, by, cap)
	local dealt = 0
	for _, t in ipairs(game.tanks) do
		local dx = abs(t.x - x)
		if t.alive and dx < reach and abs(t.y - y) <= 30 then
			local amt = floor(dmg * (0.5 + 0.5 * (reach - dx) / reach))
			if cap then
				amt = min(amt, cap - t.burnt)
				t.burnt = t.burnt + amt
			end
			local lost = Hurt(t, amt, by)
			if t ~= by then dealt = dealt + lost end
		end
	end
	return dealt
end

-- Settle anything resting on the ground after the terrain changed.
-- Tanks only fall: a wall raised on top buries them instead of lifting them.
-- A tank that ends up on the bottom of the map falls out and dies; `by` gets the kill.
local function Settle(by)
	local h = game.h
	for _, t in ipairs(game.tanks) do
		t.y = min(t.y, h[t.col])
		if t.alive and t.y <= 0 then
			t.fell, t.shield = true, 0
			Hurt(t, t.hp, by)
		end
	end
	for _, c in ipairs(game.crates) do c.y = h[c.col] end
	for _, p in ipairs(game.props) do p.y = h[p.col] end
end

-- Drill tunnel from (x1, y1) to (x2, y2), 16px across. Each column loses the tunnel's height once,
-- so the earth above drops into it and anything standing there falls with it.
function frame.Tunnel(x1, y1, x2, y2)
	local h, lo, hi = game.h, {}, {}
	local n = max(1, floor(sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) / 3))
	for k = 0, n do
		local y = floor(y1 + (y2 - y1) * k / n)
		Circle(x1 + (x2 - x1) * k / n, 8, function(col, dy)
			lo[col] = min(lo[col] or y - dy, y - dy)
			hi[col] = max(hi[col] or y + dy, y + dy)
		end)
	end
	for col, l in pairs(lo) do
		l = max(0, l)
		local hc = h[col]
		if hc > l then h[col] = hc <= hi[col] and l or hc - (hi[col] - l) end
	end
	Settle(game.tanks[game.cur])
end

local Detonate

-- Props caught in a blast are destroyed; mines and barrels go off in turn (chains)
local function HitProps(x, y, r, by)
	for _, p in ipairs(game.props) do
		local def = PROPS[p.kind]
		local dx, dy, reach = (p.col - 0.5) * COLW - x, p.y + def.h / 2 - y, r + def.w / 2
		if p.alive and dx * dx + dy * dy < reach * reach then
			p.alive = false
			if def.radius then Detonate(p, by) end
		end
	end
end

function Detonate(p, by)
	local def = PROPS[p.kind]
	local x, y = (p.col - 0.5) * COLW, p.y + 2
	Carve(x, y, def.radius)
	Damage(x, y, def.radius, def.dmg, by, def.knock)
	HitProps(x, y, def.radius, by)
	Explosion(x, y, def.radius)
end

local function Impact(w, x, y)
	local by = game.tanks[game.cur]
	if w.wall then
		RaiseWall(x, w.radius, w.wall)
	else
		Carve(x, y, w.radius)
	end

	local dealt = 0
	if w.napalm then
		dealt = Burn(x, y, w.napalm, w.dmg, by, w.cap)
	elseif w.dmg then
		dealt = Damage(x, y, w.radius, w.dmg, by, w.knock, w.direct)
	end
	if w.leech and by.alive and dealt > 0 then
		local heal = min(game.rules.hp - by.hp, dealt)
		by.hp = by.hp + heal
		local v = vis[by.i]
		if heal > 0 and v.x then Floater("+" .. heal, v.x, v.y + 34, 0.4, 1, 0.4) end
	end

	local reach = (w.napalm or w.radius) + 8
	for i = #game.crates, 1, -1 do
		local c = game.crates[i]
		local dx, dy = (c.col - 0.5) * COLW - x, c.y + 6 - y
		if dx * dx + dy * dy < reach * reach then Collect(i, by) end
	end
	if not w.wall then HitProps(x, y, w.napalm or w.radius, by) end
	Settle(by)
end

local function TankNear(col)
	for _, t in ipairs(game.tanks) do
		if t.alive and abs(t.col - col) <= TANKW / COLW / 2 then return true end
	end
end

-- Tanks, crates (12x12 box, collected by the blast) and blocking props (trees, barrels) stop shells
-- skip: a tank to ignore (the shooter, while the shell is still leaving the barrel)
local function HitsSolid(x, y, skip)
	for _, t in ipairs(game.tanks) do
		if t.alive and t ~= skip and abs(x - t.x) <= HITW / 2 and y >= t.y - 1 and y <= t.y + HITH then return true end
	end
	for _, c in ipairs(game.crates) do
		if abs(x - (c.col - 0.5) * COLW) <= 6 and y >= c.y and y <= c.y + 12 then return true end
	end
	for _, p in ipairs(game.props) do
		local def = PROPS[p.kind]
		if p.alive and def.block and abs(x - (p.col - 0.5) * COLW) <= def.w / 2 - 2
			and y >= p.y and y <= p.y + def.h - 2 then return true end
	end
end

local function Blocked(t, col)
	for _, o in ipairs(game.tanks) do
		if o ~= t and o.alive and abs(o.col - col) < TANKW / COLW + 2 then return true end
	end
end

local function CollectNear(t, col)
	for k = #game.crates, 1, -1 do
		if abs(game.crates[k].col - col) <= 6 then Collect(k, t, true) end
	end
end

-- A tank's weight packs down a small lip it can't climb (a crater rim, a ragged blast edge): the
-- column ahead sinks to the most it can climb, as long as neither it nor the next few columns stand
-- more than 23px (CLIMB + 16) above the tank. Tall steps and steep slopes still stop it.
function frame.Crush(col, dir)
	local h, base = game.h, game.h[col]
	for k = 1, 6 do
		local c = col + dir * k
		if c >= 1 and c <= NCOLS and h[c] - base > CLIMB + 16 then return end
	end
	h[col + dir] = base + CLIMB
	-- Rounds off the rim beyond it: the next few columns ease down toward their neighbours (never up)
	for k = 2, 4 do
		local c = col + dir * k
		if c >= 2 and c < NCOLS then h[c] = min(h[c], floor((h[c - 1] + h[c] * 2 + h[c + 1]) / 4)) end
	end
	Dust((col + dir - 0.5) * COLW, base + CLIMB, 3)
	return true
end

-- Thin spikes under the hull (a column or two standing over 3px above the ground 2 columns either
-- side, and poking up into the tank at height y) get flattened to 2px above that ground
function frame.Flatten(col, y)
	local h = game.h
	for c = max(3, col - 4), min(NCOLS - 2, col + 4) do
		local around = max(h[c - 2], h[c + 2])
		if h[c] > y and h[c] - around > 3 then h[c] = around + 2 end
	end
end

-- Drives up to n columns, one fuel each; stops at steep climbs it can't crush, edges, other tanks and chasms.
-- Driving onto a land mine stops the tank there and sets it off; driving into a teleporter stops
-- it there and warps it. Returns the columns driven, and whether a mine or teleporter stopped it.
local function MoveTank(t, dir, n)
	local h, col, mine, moved, portal = game.h, t.col, nil, 0, nil
	if h[col] - t.y >= TANKH then return 0 end -- fully buried: shoot your way out
	for _ = 1, min(n, t.fuel) do
		local nx = col + dir
		if nx < 5 or nx > NCOLS - 4 or Blocked(t, nx) then break end
		if h[nx] - h[col] > CLIMB and not frame.Crush(col, dir) then break end
		col, moved = nx, moved + 1
		if h[col] <= 0 then break end -- a chasm down to the bottom: you drive in and fall out
		frame.Flatten(col, h[col])
		CollectNear(t, col)
		for _, p in ipairs(game.props) do
			if p.alive and PROPS[p.kind].trigger and abs(p.col - col) <= 4 then mine = p end
		end
		if mine then break end
		-- Teleporters column by column, so the lock clears the moment the tank is out of the box
		local k = frame.PortalAt(col)
		if t.portal and t.portal ~= k then t.portal = nil end
		if k and t.portal ~= k then portal = true break end
	end
	if moved == 0 then return 0 end
	t.fuel = t.fuel - moved
	t.col, t.x, t.y = col, (col - 0.5) * COLW, h[col]
	if mine then
		mine.alive = false
		Detonate(mine, nil)
	end
	Settle() -- also catches driving into a pit that reaches the bottom
	if portal then frame.Warp(t) end
	return moved, mine ~= nil or portal == true
end

local function ValidTeleport(t, col)
	return col >= 5 and col <= NCOLS - 4 and not Blocked(t, col)
end

-- Teleporters (big matches only): a linked pair, game.portals[1] left and [2] right.
-- A tank inside one's box comes out of the other; t.portal remembers the one it came out of,
-- which it has to leave before it can use it again.

-- Which teleporter's box (6 columns either side of its centre) a column is in, if any
function frame.PortalAt(col)
	for k, p in ipairs(game.portals or {}) do
		if abs(col - p.col) <= 6 then return k end
	end
end

-- About 20 turns into a 6+ tank match: one lands near the middle of each half
function frame.SpawnPortals()
	local a = floor(NCOLS / 4) + Rand(-12, 12)
	local b = floor(NCOLS * 3 / 4) + Rand(-12, 12)
	game.portals = { { col = a }, { col = b } }
	for _, t in ipairs(game.tanks) do t.portal = frame.PortalAt(t.col) end -- landed on: step off first
	frame.PortalsArrive()
end

-- After a tank changes column: unlock a teleporter it has left, and warp it if it's inside the
-- other one. A tank parked on the exit just pushes the arrival to the nearest free spot beside it.
function frame.Warp(t)
	if not (game.portals and t.alive) then return end
	local k = frame.PortalAt(t.col)
	if t.portal and t.portal ~= k then t.portal = nil end
	if not k or t.portal == k then return end
	local o, col = game.portals[3 - k], nil
	for d = 0, 40 do
		if ValidTeleport(t, o.col - d) then col = o.col - d break end
		if ValidTeleport(t, o.col + d) then col = o.col + d break end
	end
	if not col then return end
	vis[t.i].warp = { at = (game.portals[k].col - 0.5) * COLW, to = (col - 0.5) * COLW }
	t.col, t.x, t.y, t.portal = col, (col - 0.5) * COLW, game.h[col], 3 - k
	CollectNear(t, o.col)
	Settle()
end

local function ApplyPower(t, i, arg)
	local w = WEAPONS[i]
	t.ammo[i] = t.ammo[i] - 1
	if t.ammo[i] == 0 and t.weapon == i then t.weapon = 1 end
	local v = vis[t.i]
	if w.power == "shield" then
		t.shield = SHIELD
	elseif w.power == "moves" then
		t.fuel = t.fuel + 2 * game.rules.dist
	elseif w.power == "jet" then
		-- Touchdown after a flight (the drawn tank drops from where it flew to)
		t.col, t.x, t.y = arg, (arg - 0.5) * COLW, game.h[arg]
		CollectNear(t, arg)
		Settle() -- landing in a pit to the bottom still falls out
		frame.Warp(t)
	else
		Particle("tele", v.x or t.x, (v.y or t.y) + 6, 0, 0, 0.4, 10, 50, 1)
		t.col, t.x, t.y = arg, (arg - 0.5) * COLW, game.h[arg]
		CollectNear(t, arg)
		v.x, v.y, v.fy = t.x, t.y + 40, 0
		Particle("tele", t.x, t.y + 6, 0, 0, 0.4, 50, 10, 1)
		frame.Warp(t)
	end
	if v.x then Floater(w.name, v.x, v.y + 34, 0.4, 0.8, 1) end
end

local function IsMine(t) return game.solo or t.name == Me() end

local function CanAim()
	return game and not game.over and not game.shot and not game.landed and not game.shopping and not game.retreat
		and not game.jet and IsMine(game.tanks[game.cur]) and not game.tanks[game.cur].ai and TimeLeft() > 0
end

-- Driving is allowed while aiming, while your shot is in the air, and for a few seconds after it
-- lands (game.retreat)
function frame.CanMove()
	if not game or game.over or game.shopping or game.targeting or game.landed or game.jet then return false end
	local t = game.tanks[game.cur]
	if not IsMine(t) or t.ai or t.fuel < 1 then return false end
	if game.retreat then return GetTime() < game.retreat end
	return TimeLeft() > 0
end

-- Held A / D drives column by column locally; each stretch goes out as one MOVE with its length
function frame.FlushDrive()
	local dv = game and game.drive
	if not dv then return end
	game.drive = nil
	if dv.n > 0 and not game.solo then Send("MOVE", game.turn, dv.dir, dv.n) end
end

local function EndTargeting()
	if game then game.targeting = nil end
	field:EnableMouse(false)
	ghost:Hide()
end

-- Thunderstorm: lightning hits a random spot (shared PRNG, so the same everywhere)
local function Lightning()
	local col = Rand(5, NCOLS - 4)
	local x, y = (col - 0.5) * COLW, game.h[col]
	Carve(x, y, 12)
	Damage(x, y, 12, 25, nil)
	HitProps(x, y, 12, nil)
	Settle()
	field.Bolt(x, y)
	Explosion(x, y, 12)
end

local function EndTurn()
	game.landed, game.hit, game.sec, game.retreat, game.retreatT, game.drive, game.queue = nil, nil, nil, nil, nil, nil, nil
	game.jet = nil
	EndTargeting()
	if game.sky.storm and Rand(1, 3) == 1 then Lightning() end
	local alive, last, lastI, nteams, seen = 0, nil, nil, 0, {}
	for i, t in ipairs(game.tanks) do
		if t.alive then
			alive, last, lastI = alive + 1, t, i
			if not seen[t.team] then seen[t.team], nteams = true, nteams + 1 end
		end
	end
	if nteams <= 1 then
		if groupHost == game.host then groupHost = nil end -- finished: anyone may host next
		if not last then
			game.over, game.winTitle, game.winSub = "Draw!", "DRAW!", "Nobody survived"
		elseif game.teams then
			game.over = "Team " .. last.team .. " wins!"
			game.winTitle = "TEAM " .. last.team .. " WINS!"
			game.winSub = "Last tank standing: " .. Short(last.name)
			game.winColor = TEAMCOLORS[last.team][1]
		else
			game.over = Short(last.name) .. " wins!"
			game.winTitle = game.over
			game.winSub = (last.name == Me() and not game.solo) and "You are victorious!" or "Last tank standing"
			game.winColor = vis[lastI].color
		end
		if last then
			for _, t in ipairs(game.tanks) do
				if t.team == last.team then sessionWins[t.name] = (sessionWins[t.name] or 0) + 1 end
			end
		end
		Print(game.over)
		toast.HostUpdate()
	else
		local n = #game.order
		repeat
			game.oi = game.oi % n + 1
			game.cur = game.order[game.oi]
		until game.tanks[game.cur].alive
		game.turn = game.turn + 1
		game.turnStart = GetTime()
		game.wind = Rand(-game.windMax, game.windMax)
		-- Same odds every turn, so each tank sees as many crates as in a 1v1 (the rule's "per N rounds"),
		-- however many play; more tanks also means room for more crates on the field
		if game.rules.crates > 0 and Rand(1, game.rules.crates * 2) == 1
			and #game.crates < min(MAXCRATES, 2 + floor(alive / 2)) then
			local col = Rand(10, NCOLS - 10)
			local w = PickItem(floor((game.turn - 1) / max(1, alive)))
			SpawnCrate(col, w)
			-- Dropped onto a tank: it catches it
			for _, o in ipairs(game.tanks) do
				if o.alive and abs(o.col - col) <= 6 then Collect(#game.crates, o, true) break end
			end
		end
		-- Big matches (6+ tanks): from turn 18 (the counter at the top left) a pair of teleporters
		-- may drop in, 1 in 3 each turn, so usually by turn 20 or so
		if #game.tanks >= 6 and not game.portals and game.turn >= 18 and Rand(1, 3) == 1 then
			frame.SpawnPortals()
		end
		local t = game.tanks[game.cur]
		-- Fuel is counted in columns: each "move" in the rules is worth one Move distance
		local r = game.rules
		-- Far from every enemy: extra fuel (and room for it), 1 column per 4 past 100 columns away,
		-- up to one more move's worth. Only when the rules give fuel at all.
		local near = NCOLS
		for _, o in ipairs(game.tanks) do
			if o.alive and o.team ~= t.team then near = min(near, abs(o.col - t.col)) end
		end
		local bonus = r.gain > 0 and min(r.dist, floor(max(0, near - 100) / 4)) or 0
		t.fuel = max(t.fuel, min(r.moves * r.dist + bonus, t.fuel + r.gain * r.dist + bonus))
		Announce()
	end
	DrawAll()
end

-- Current player ran out of time: drop any shot in flight and pass the turn
local function Skip()
	game.shot = nil
	HideShells()
	local v = vis[game.cur]
	if v.x then Floater("Time's up", v.x, v.y + 34, 1, 0.8, 0.3) end
	EndTurn()
end

-- After the shot resolves the shooter may keep driving for what's left of the shot timer, cut to
-- 3 seconds at most, unless the match is decided, they died or they're out of fuel (all of which
-- every client agrees on). Others wait for the shooter's DONE; retreatT is when that wait began.
function frame.AfterShot()
	local me, seen, n = game.tanks[game.cur], {}, 0
	for _, t in ipairs(game.tanks) do
		if t.alive and not seen[t.team] then seen[t.team], n = true, n + 1 end
	end
	if n <= 1 or not me.alive or me.fuel < 1 or me.ai then EndTurn() return end -- solo AI never drives off
	local now = GetTime()
	game.landed, game.hit, game.retreatT = nil, nil, now
	game.retreat = min(now + 3, game.turnStart + game.rules.time) -- in the past: DONE goes out at once
	DrawAll()
end

-- pts is a flat list x1, y1, x2, y2, ... A drill shot that dug leads with its tunnel's
-- start and end (so 2 pairs: it dug and flew off the map, 3: it dug and blew up)
local function Resolve(pts)
	local w, first = game.fired, 1
	for _, t in ipairs(game.tanks) do t.burnt = 0 end
	if w.drill and #pts >= 4 then
		frame.Tunnel(pts[1], pts[2], pts[3], pts[4])
		first = 5
	end
	for i = first, #pts - 1, 2 do Impact(w, pts[i], pts[i + 1]) end
	return Checksum()
end

local function TryRemoteResolve()
	local hit = game.hit
	if not (game.landed and hit) then return end
	if Resolve(hit.pts) ~= hit.sum then Print("Desync detected on turn " .. game.turn .. ".") end
	frame.AfterShot()
end

local function NewShell(x, y, vx, vy) return { x = x, y = y, vx = vx, vy = vy, steps = 0 } end

-- Launch speed for a power (1-100) and weapon. Wider maps (more players) add a boost that grows
-- with power, so low power aims the same but full power reaches further: +27% at 100 on a 10 player map
function frame.ShotSpeed(power, w)
	local p = power / 100
	return power * SPEED * (w.speed or 1) * (1 + 0.25 * (W / BASEW - 1) * p * p)
end

local function Launch()
	local t = game.tanks[game.cur]
	local wi = t.weapon
	local w = WEAPONS[wi]
	local a, v = rad(t.angle), frame.ShotSpeed(t.power, w)
	local tx, ty = t.x + cos(a) * BARREL, t.y + TURRET + sin(a) * BARREL
	if t.ammo[wi] > 0 then t.ammo[wi] = t.ammo[wi] - 1 end
	if t.ammo[wi] == 0 then t.weapon = 1 end
	t.shots = t.shots + 1
	game.fired = w

	local shells = {}
	if w.pellets then
		for k = 1, w.pellets do
			local pa = a + rad((k - (w.pellets + 1) / 2) * 3)
			shells[k] = NewShell(tx, ty, cos(pa) * v, sin(pa) * v)
			shells[k].child = true
		end
	else
		shells[1] = NewShell(tx, ty, cos(a) * v, sin(a) * v)
	end
	game.shot = { w = w, acc = 0, impacts = {}, shells = shells }

	Particle("flash", tx, ty, 0, 0, 0.12, 14, 22, 1)
	for k = 1, 3 do Particle("smoke", tx, ty, cos(a) * 25 * k, sin(a) * 25 * k, 0.8, 4, 12, 0.4) end
	vis[game.cur].recoil = 0.15
	DrawStatus()
end

local function StepShell(s, w)
	local h = game.h
	if s.roll then
		-- Integer momentum: downhill gains, uphill and flat lose
		s.tick = s.tick + 1
		if s.tick % 3 > 0 then return end
		local nx = s.col + s.dir
		if nx < 1 or nx > NCOLS then return "hit" end
		s.m = min(60, s.m + h[s.col] - h[nx] - 1)
		if s.m <= 0 or TankNear(nx) then return "hit" end
		s.col, s.x, s.y = nx, (nx - 0.5) * COLW, h[nx]
		return
	end
	if s.dig then
		-- Boring: a straight line with no gravity or wind, until it breaks out or the drill is spent
		s.x, s.y = s.x + s.vx * STEP, s.y + s.vy * STEP
		s.steps = s.steps + 1
		s.dug = s.dug + sqrt(s.vx * s.vx + s.vy * s.vy) * STEP
		local stop = s.x < 0 or s.x >= W or s.y <= 2 or s.dug >= w.drill
			or HitsSolid(s.x, s.y, s.steps <= 10 and game.tanks[game.cur])
		if stop or s.y > h[floor(s.x / COLW) + 1] then
			s.x = max(0, min(W - 1, s.x))
			s.tunnel = { s.dig[1], s.dig[2], floor(s.x + 0.5), max(0, floor(s.y + 0.5)) }
			s.dig, s.drilled = nil, true
			if stop then return "hit" end
		elseif random() < 0.4 then
			Particle("dirt", s.x, s.y, random(-40, 40), random(20, 90), 0.6, 3, 3, 1)
		end
		return
	end
	if w.home and s.vy < 0 then
		local me, best = game.tanks[game.cur], nil
		for _, t in ipairs(game.tanks) do
			if t.alive and t.team ~= me.team and (not best or abs(t.x - s.x) < abs(best.x - s.x)) then best = t end
		end
		-- Steers its sideways speed toward one that closes the gap (less as it gets near, so it
		-- doesn't overshoot), turning up to 300px/s per second
		if best then
			local want = max(-260, min(260, (best.x - s.x) * 2.5))
			s.vx = s.vx + max(-300 * STEP, min(300 * STEP, want - s.vx))
		end
	end
	s.vy = s.vy - G * STEP
	s.vx = s.vx + game.wind * WINDK * STEP
	s.x, s.y = s.x + s.vx * STEP, s.y + s.vy * STEP
	s.steps = s.steps + 1
	if s.x < 0 or s.x >= W or s.steps > 120 * 30 then return "out" end
	-- Enemies right next to you count from the first step; your own tank only once the shell is clear
	if HitsSolid(s.x, s.y, s.steps <= 10 and game.tanks[game.cur]) then return "hit" end
	local col = floor(s.x / COLW) + 1
	if s.y <= h[col] then
		if w.roll then
			s.roll, s.col, s.dir, s.m, s.tick = true, col, s.vx < 0 and -1 or 1, 20, 0
			s.x, s.y = (col - 0.5) * COLW, h[col]
			return
		end
		if w.drill and not s.drilled then
			s.dig, s.dug = { floor(s.x + 0.5), max(0, floor(s.y + 0.5)) }, 0
			s.vx, s.vy = s.vx * 0.7, s.vy * 0.7
			return
		end
		if w.bounce and (s.bounces or 0) < w.bounce then
			s.bounces, s.bounced = (s.bounces or 0) + 1, true
			local px, py = s.x - s.vx * STEP, s.y - s.vy * STEP
			local pc = floor(px / COLW) + 1
			if pc ~= col and py <= h[col] and h[col] - h[pc] > 4 then
				-- Flew sideways into a steep face: bounces back off the wall
				s.x, s.y, s.vx = px, py, -s.vx * 0.6
			else
				s.y, s.vy, s.vx = h[col] + 1, abs(s.vy) * 0.6, s.vx * 0.8
			end
			return
		end
		return "hit"
	end
end

-- Bomblets after the main shell lands (cluster, volcano) or shells dropping from the sky (hail)
local function Burst(shells, w, x, y, vx)
	if w.burst then
		local dir = vx < 0 and -1 or 1
		for k = 1, w.burst do
			local f = (k - 1) / (w.burst - 1)
			local a = rad(w.carry and 90 - dir * w.spread * f or 90 - w.spread / 2 + w.spread * f)
			local c = NewShell(x, y + 3, cos(a) * w.burstV + vx * (w.carry or 0), sin(a) * w.burstV)
			c.child, c.steps = true, 11
			tinsert(shells, c)
		end
	elseif w.hail then
		for k = 1, w.hail do
			local c = NewShell(x + (k - (w.hail + 1) / 2) * 30, H + 10, 0, -40)
			c.child, c.steps = true, 11
			tinsert(shells, c)
		end
	end
end

-- Advances every shell one step; returns true when all have landed
local function StepShot(shot)
	local shells, w = shot.shells, shot.w
	for i = #shells, 1, -1 do
		local s = shells[i]
		local r = StepShell(s, w)
		if r then
			if s.tunnel then
				for _, v in ipairs(s.tunnel) do tinsert(shot.impacts, v) end
			end
			if r == "hit" then
				local x, y = floor(s.x + 0.5), max(0, floor(s.y + 0.5))
				tinsert(shot.impacts, x)
				tinsert(shot.impacts, y)
				ImpactFx(w, x, y)
				if not s.child then Burst(shells, w, x, y, s.vx) end
			end
			tremove(shells, i)
		elseif w.drops and not s.child and s.steps >= w.fuse / STEP then
			-- Airburst: the shell pops and rains burning blobs
			for k = 1, w.drops do
				local c = NewShell(s.x, s.y, s.vx * 0.4 + (k - (w.drops + 1) / 2) * 15, min(s.vy, 0) * 0.3 - 20)
				c.child, c.steps, c.blob = true, 11, true
				tinsert(shells, c)
			end
			Particle("flash", s.x, s.y, 0, 0, 0.2, 20, 60, 1)
			Particle("fire", s.x, s.y, 0, 0, 0.5, 20, 50, 1)
			for _ = 1, 3 do Particle("smoke", s.x, s.y, random(-15, 15), random(0, 15), 1.5, 10, 26, 0.4) end
			tremove(shells, i)
		elseif w.split and not s.child and s.vy <= 0 then
			s.child = true
			for d = 1, floor(w.split / 2) do
				for _, sign in ipairs({ -1, 1 }) do
					local c = NewShell(s.x, s.y, s.vx + sign * d * 30, s.vy)
					c.child, c.steps = true, s.steps
					tinsert(shells, c)
				end
			end
			Particle("flash", s.x, s.y, 0, 0, 0.15, 10, 24, 1)
		end
	end
	return #shells == 0
end

local function Landed()
	local shot = game.shot
	game.shot = nil
	HideShells()
	if IsMine(game.tanks[game.cur]) then
		frame.FlushDrive() -- driving during the flight goes out before the HIT
		local sum = Resolve(shot.impacts)
		if not game.solo then Send("HIT", game.turn, sum, unpack(shot.impacts)) end
		frame.AfterShot()
	else
		game.landed = true
		TryRemoteResolve()
	end
end

local function Fire()
	local t = game.tanks[game.cur]
	t.angle, t.power = floor(t.angle + 0.5), floor(t.power + 0.5)
	frame.FlushDrive() -- any driving goes out before the shot
	if not game.solo then Send("FIRE", game.turn, t.angle, t.power, t.weapon) end
	Launch()
end

-- Space on a power-up: shield and moves apply now, teleport waits for a click, the jetpack takes off
local function UseItem()
	local t = game.tanks[game.cur]
	local i = t.weapon
	frame.FlushDrive()
	if WEAPONS[i].power == "teleport" then
		game.targeting = true
		field:EnableMouse(true)
		DrawStatus()
		return
	end
	if WEAPONS[i].power == "jet" then
		local v = vis[t.i]
		game.jet = { i = i, t0 = GetTime(), x = v.x or t.x, y = (v.y or t.y) + 4, path = {}, ps = 0 }
		v.jet = game.jet
		DrawStatus()
		return
	end
	if not game.solo then Send("USE", game.turn, i, 0) end
	ApplyPower(t, i, 0)
	DrawAll()
end

local function CursorCol()
	local x = GetCursorPosition() / field:GetEffectiveScale() - field:GetLeft()
	return max(1, min(NCOLS, floor(x / COLW) + 1))
end

field:SetScript("OnMouseDown", function(_, button)
	if not (game and game.targeting) then return end
	local t, col = game.tanks[game.cur], CursorCol()
	EndTargeting()
	if button == "LeftButton" and ValidTeleport(t, col) and CanAim() then
		if not game.solo then Send("USE", game.turn, t.weapon, col) end
		ApplyPower(t, t.weapon, col)
		DrawAll()
	else
		DrawStatus()
	end
end)

-- Jetpack flight, shooter only: WASD or the arrows steer for 3 seconds (less if the shot timer is
-- nearly out). The path is sampled every 0.2s; at the end the tank lands on the nearest free column
-- below it and one JET message carries the landing and the path, which the others replay.
function frame.Jet(e)
	local j = game.jet
	if not j then return end
	local t = game.tanks[game.cur]
	-- Fuel out after 3s (sooner near the end of the shot timer, so the coast fits): the engine cuts
	-- and the tank keeps its momentum, arcing down under gravity until it touches the ground
	local age = GetTime() - j.t0
	if not j.coast and (age >= 3 or TimeLeft() < 2) then j.coast = true end
	local dx, dy = 0, 0
	if not j.coast then
		dx = ((held.D or held.RIGHT) and 1 or 0) - ((held.A or held.LEFT) and 1 or 0)
		dy = ((held.W or held.UP) and 1 or 0) - ((held.S or held.DOWN) and 1 or 0)
		-- Inertia: velocity eases toward the steering (about a third of a second to get going or stop)
		local k = min(1, 3 * e)
		j.vx = (j.vx or 0) + (dx * 90 - (j.vx or 0)) * k
		j.vy = (j.vy or 0) + (dy * 80 - (j.vy or 0)) * k
	else
		j.vx, j.vy = j.vx or 0, (j.vy or 0) - G * e
	end
	local nx = max(5 * COLW, min((NCOLS - 4) * COLW, j.x + j.vx * e))
	if nx ~= j.x + j.vx * e then j.vx = 0 end -- bumped a map edge
	j.x = nx
	local col = max(1, min(NCOLS, floor(j.x / COLW) + 1))
	local ny = j.y + j.vy * e
	local down = ny <= game.h[col]
	if down or ny > H - 30 then j.vy = 0 end -- touched the ground or the ceiling
	j.y = max(game.h[col], min(H - 30, ny))
	j.ps = j.ps - e
	if j.ps <= 0 and #j.path < 23 then -- 23 points plus touchdown keeps the JET message under 255
		j.ps = 0.2
		tinsert(j.path, floor(j.x + 0.5) .. "." .. floor(j.y + 0.5))
	end
	if not (j.coast and down) and age < 6 and TimeLeft() > 0 and t.alive then return end
	game.jet = nil
	local land
	for d = 0, NCOLS do
		if ValidTeleport(t, col - d) then land = col - d break end
		if ValidTeleport(t, col + d) then land = col + d break end
	end
	land = land or t.col
	tinsert(j.path, floor(j.x + 0.5) .. "." .. floor(j.y + 0.5))
	if not game.solo then Send("JET", game.turn, j.i, land, table.concat(j.path, "_")) end
	vis[t.i].jet = nil
	ApplyPower(t, j.i, land)
	DrawAll()
end

-- Places a flying tank's drawing: live from the flight, or replaying a received path at 1.5x speed.
-- Returns true while it's in charge of the tank's position.
function frame.JetVis(v, e)
	local j = v.jet
	if not j then return false end
	if j.pts then
		local k = (GetTime() - j.t0) * 1.5 / 0.2 + 1
		local n = #j.pts
		if k >= n then
			v.jet = nil
			v.x, v.y = j.pts[n][1], j.pts[n][2]
			return false
		end
		local a, b, f = j.pts[floor(k)], j.pts[floor(k) + 1], k - floor(k)
		v.x, v.y = a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f
		v.jvx = (b[1] - a[1]) / 0.2 -- flight speed (before the replay's speed-up), for the lean
	elseif game.jet == j then
		v.x, v.y, v.jvx = j.x, j.y, j.vx or 0
	else
		v.jet = nil -- the flight ended some other way (the turn moved on)
		return false
	end
	v.fy = 0
	if not j.coast and random() < e * 40 then -- no flames once the engine has cut out
		Particle("flame", v.x + random(-3, 3), v.y, random(-8, 8), -random(40, 70), 0.3, 5, 2, 0.9)
		Particle("smoke", v.x, v.y - 2, random(-6, 6), -random(10, 25), 0.8, 3, 8, 0.3)
	end
	return true
end

-- Solo AI ----------------------------------------------------------------

-- Difficulty (t.ai is the index): err = most degrees / power points it's randomly off by,
-- best = chance it reaches for its strongest shell instead of the Goblin Shell, think = seconds before it aims
frame.AILEVELS = {
	{ name = "Easy",   err = 9, best = 0.3, think = 1.4 },
	{ name = "Normal", err = 4, best = 0.7, think = 0.9 },
	{ name = "Hard",   err = 1, best = 1,   think = 0.5 },
}

-- Where a shot from t at this angle and power comes down: a quick, coarse copy of the shell's flight
-- (gravity and wind, 1/30s steps), stopping at the ground or the map edge
function frame.AISim(t, angle, power, w)
	local a, v = rad(angle), frame.ShotSpeed(power, w)
	local x, y = t.x + cos(a) * BARREL, t.y + TURRET + sin(a) * BARREL
	local vx, vy, dt = cos(a) * v, sin(a) * v, 1 / 30
	for k = 1, 300 do
		vy = vy - G * dt
		vx = vx + game.wind * WINDK * dt
		x, y = x + vx * dt, y + vy * dt
		if x < 0 or x >= W then return x end
		if k > 2 and y <= (game.h[floor(x / COLW) + 1] or 0) then return x end
	end
	return x
end

-- Picks a target (nearest enemy), a weapon (often its hardest hitter that flies like a normal
-- shell and won't catch itself in the blast) and the angle and power that land closest, plus
-- random error by difficulty so it can be beaten
function frame.AIPlan(t)
	local lv = frame.AILEVELS[t.ai] or frame.AILEVELS[2]
	local foe
	for _, o in ipairs(game.tanks) do
		if o.alive and o.team ~= t.team and (not foe or abs(o.x - t.x) < abs(foe.x - t.x)) then foe = o end
	end
	if not foe then return { angle = t.angle, power = t.power, weapon = 1 } end
	local wi = 1
	if random() < lv.best then
		for i, w in ipairs(WEAPONS) do
			if t.ammo[i] > 0 and w.dmg and not (w.power or w.wall or w.roll or w.bounce or w.fuse)
				and w.dmg > WEAPONS[wi].dmg and abs(foe.x - t.x) > (w.radius or 0) + 30 then
				wi = i
			end
		end
	end
	local w, dir = WEAPONS[wi], foe.x > t.x and 1 or -1
	local best, ba, bp = math.huge, 45, 60
	for a = 15, 80, 5 do
		local angle = dir > 0 and a or 180 - a
		for power = 20, 100, 2 do
			local err = abs(frame.AISim(t, angle, power, w) - foe.x)
			if err < best then best, ba, bp = err, angle, power end
		end
	end
	-- Fine pass around the best coarse pick, a degree and a power point at a time
	local ca, cp = ba, bp
	for angle = ca - 4, ca + 4 do
		for power = max(1, cp - 2), min(100, cp + 2) do
			local err = abs(frame.AISim(t, angle, power, w) - foe.x)
			if err < best then best, ba, bp = err, angle, power end
		end
	end
	return {
		angle = max(0, min(180, ba + random(-lv.err, lv.err))),
		power = max(1, min(100, bp + random(-lv.err, lv.err))),
		weapon = wi, think = lv.think,
	}
end

-- On a solo AI tank's turn: think for a moment, swing the barrel and power to the plan, then fire
function frame.AI(e)
	local t = game.solo and game.tanks[game.cur]
	if not (t and t.ai and t.alive) or game.over or game.shot or game.landed or game.shopping
		or game.retreat or game.jet then return end
	local p = game.ai
	if not p or p.turn ~= game.turn then
		p = frame.AIPlan(t)
		p.turn, p.t0 = game.turn, GetTime()
		game.ai = p
		t.weapon = p.weapon
		DrawStatus()
	end
	local age = GetTime() - p.t0
	if age < (p.think or 0.9) then return end
	t.angle = t.angle + max(-60 * e, min(60 * e, p.angle - t.angle))
	t.power = t.power + max(-40 * e, min(40 * e, p.power - t.power))
	DrawStatus()
	if (abs(t.angle - p.angle) < 0.5 and abs(t.power - p.power) < 0.5) or age > 6 then
		t.angle, t.power = p.angle, p.power
		Fire()
	end
end

local function CycleWeapon(d)
	local t = game.tanks[game.cur]
	local i = t.weapon
	repeat i = (i - 1 + d) % #WEAPONS + 1 until t.ammo[i] ~= 0
	t.weapon = i
	DrawStatus()
end

-- Clicking the weapon name opens a list of everything you carry, 10 to a column; click one to pick it.
-- Closes again on a second click, a pick, or once you can't aim any more.
do
	local pick = CreateFrame("Frame", nil, hud)
	pick:SetFrameLevel(hud:GetFrameLevel() + 30)
	pick:SetPoint("BOTTOMLEFT", hud, "TOPLEFT", 0, 6)
	pick:EnableMouse(true)
	Panel(pick)
	pick:Hide()
	pick.rows = {}
	hud.pick = pick

	function pick.Open()
		local t = game.tanks[game.cur]
		local n = 0
		for i, w in ipairs(WEAPONS) do
			if t.ammo[i] ~= 0 then
				n = n + 1
				local b = pick.rows[n]
				if not b then
					b = CreateFrame("Button", nil, pick)
					b:SetSize(200, 16)
					b.sel = b:CreateTexture(nil, "BACKGROUND")
					b.sel:SetAllPoints()
					b.sel:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.2)
					local hl = b:CreateTexture(nil, "HIGHLIGHT")
					hl:SetAllPoints()
					hl:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.12)
					b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					b.name:SetPoint("LEFT", 4, 0)
					b.count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					b.count:SetPoint("RIGHT", -4, 0)
					b:SetScript("OnClick", function(self)
						if CanAim() then
							game.tanks[game.cur].weapon = self.idx
							DrawStatus()
						end
						pick:Hide()
					end)
					pick.rows[n] = b
				end
				b.idx = i
				b.name:SetText(WEAPONS.Icon(w, 14) .. " " .. w.name)
				local r, g, bl = Rarity(w)
				b.name:SetTextColor(r, g, bl)
				b.count:SetText(t.ammo[i] < 0 and "" or ("x" .. t.ammo[i]))
				b:SetPoint("TOPLEFT", 6 + floor((n - 1) / 10) * 204, -6 - (n - 1) % 10 * 16)
				b:Show()
			end
		end
		for k = n + 1, #pick.rows do pick.rows[k]:Hide() end
		pick:SetSize(8 + ceil(n / 10) * 204, 12 + min(n, 10) * 16)
		hud.tip:Hide()
		pick:Show()
	end

	pick:SetScript("OnUpdate", function()
		if not CanAim() then pick:Hide() return end
		local cur = game.tanks[game.cur].weapon
		for _, b in ipairs(pick.rows) do b.sel:SetShown(b.idx == cur) end
	end)
	hud.hover:SetScript("OnMouseDown", function()
		if pick:IsShown() then pick:Hide() elseif CanAim() then pick.Open() end
	end)
end

-- Held A / D: one column at a time at the drawn tank's speed (20 columns a second).
-- A stretch ends (and is sent) on release, a turn around, a land mine or anything that ends the turn.
function frame.Drive(elapsed)
	local dir = (held.D and 1 or 0) - (held.A and 1 or 0)
	local dv = game.drive
	if dir == 0 or not frame.CanMove() then
		frame.FlushDrive()
		return
	end
	if dv and dv.dir ~= dir then
		frame.FlushDrive()
		dv = nil
	end
	if not dv then
		dv = { dir = dir, n = 0, acc = 0 }
		game.drive = dv
	end
	-- Speed is along the ground: a column up or down a slope costs its path length, so hills take longer
	dv.acc = min(dv.acc + 20 * elapsed, 5)
	local t, start = game.tanks[game.cur], dv.n
	while true do
		-- Capped at CLIMB: a bigger drop is a fall, not a slope (and has to stay affordable)
		local rise = max(-CLIMB, min(CLIMB, (game.h[t.col + dir] or t.y) - t.y))
		local cost = sqrt(COLW * COLW + rise * rise) / COLW
		if dv.acc < cost then break end
		dv.acc = dv.acc - cost
		local moved, mine = MoveTank(t, dir, 1)
		if moved == 0 then
			dv.acc = 0
			break
		end
		dv.n = dv.n + 1
		if mine or not t.alive then
			-- The receiving side stops a stretch at a mine or teleporter too, so start a fresh one after it
			frame.FlushDrive()
			-- A mine or a chasm ends the turn the hard way (once any shot in the air has landed)
			if not t.alive then
				if not game.shot then EndTurn() end
				return
			end
			DrawAll()
			return
		end
	end
	if dv.n > start then DrawAll() end
end

-- roster: list of { name, team } in placement order (host sends team 1 first); rules: see RULEDEFS
local function StartGame(s, roster, teams, rules, solo, host)
	local n = #roster
	W = BASEW + PERPLAYERW * max(0, n - 2)
	NCOLS = W / COLW
	ResizeField()
	SetSeed(s)
	-- Order of Rand calls matters: terrain, biome, sky, spawn slots, props, items, turn order, first player, wind,
	-- then the shop fill
	local h, style = GenTerrain(rules.terrain)
	local biome = BIOMES[rules.zone > 0 and rules.zone or Rand(1, #BIOMES)]
	local sky = SKIES[rules.sky > 0 and rules.sky or Rand(1, #SKIES)]

	-- Spawn slots: the outer tanks keep their spots near the map edges, but with 4+ players the gaps
	-- shrink toward the edges (outermost 0.4 of the middle one), so the middle tanks get more room.
	local pos, d, x = {}, NCOLS / (n + 1), 0
	for k = 1, n do
		pos[k] = x
		if k < n then
			local edge = n >= 4 and abs(k + 0.5 - (n + 1) / 2) / ((n - 2) / 2) or 0
			x = x + 1 - 0.6 * edge
		end
	end
	for k = 1, n do pos[k] = floor(d + pos[k] * (NCOLS - 2 * d) / max(1, x)) end
	-- Random slot per player; in teams each team keeps one side (which side is random),
	-- unless the Team spawns rule mixes them across the map
	local function Shuffle(list)
		for j = #list, 2, -1 do
			local r = Rand(1, j)
			list[j], list[r] = list[r], list[j]
		end
	end
	local spawn, groups, sides = {}, { {}, {} }, teams and rules.mix == 0
	for i, p in ipairs(roster) do tinsert(groups[sides and p.team or 1], i) end
	if sides and Rand(1, 2) == 2 then groups[1], groups[2] = groups[2], groups[1] end
	local k = 0
	for _, list in ipairs(groups) do
		Shuffle(list)
		for _, i in ipairs(list) do
			k = k + 1
			spawn[i] = pos[k]
		end
	end
	local preset = RULEDEFS.Preset(rules)
	game = {
		h = h, tanks = {}, crates = {}, props = {}, order = {}, specs = {}, turn = 1, oi = 1, rules = rules,
		solo = solo, teams = teams, host = host, spectating = not solo and not InRoster(roster, Me()),
		biome = biome, sky = sky, windMax = floor(rules.wind * (sky.windK or 1)),
		mapName = biome.name .. ", " .. sky.name .. " (" .. style .. ")",
		rulesName = preset and PRESETS[preset].name or "Custom",
	}
	local shade = { 0, 0 }
	for i, p in ipairs(roster) do
		local col = spawn[i]
		-- Starting pad: small flat spot at the local average, easing back into the terrain
		local hs, sum, cnt = game.h, 0, 0
		for c = max(1, col - 6), min(NCOLS, col + 6) do sum, cnt = sum + hs[c], cnt + 1 end
		local base = floor(sum / cnt)
		for c = max(1, col - 15), min(NCOLS, col + 15) do
			local d = abs(c - col)
			if d <= 3 then
				hs[c] = base
			else
				hs[c] = base + floor((hs[c] - base) * (d - 3) / 12)
			end
		end
		local ammo = {}
		for k in ipairs(WEAPONS) do ammo[k] = k == 1 and -1 or 0 end
		game.tanks[i] = {
			i = i, name = p.name, team = teams and p.team or i, col = col, x = (col - 0.5) * COLW, y = game.h[col],
			hp = rules.hp, shield = 0, alive = true, angle = col < NCOLS / 2 and 45 or 135, power = 60,
			fuel = 0, weapon = 1, ammo = ammo, dmg = 0, kills = 0, shots = 0,
			ai = solo and p.ai or nil, -- solo only: the computer plays this tank
		}
		local v, color = vis[i], COLORS[i]
		if teams then
			shade[p.team] = shade[p.team] + 1
			local set = TEAMCOLORS[p.team]
			color = set[(shade[p.team] - 1) % #set + 1]
		end
		v.color = color
		v.barrel:SetColorTexture(color[1] * 0.6, color[2] * 0.6, color[3] * 0.6)
		v.label:SetTextColor(teams and color[1] or 1, teams and color[2] or 1, teams and color[3] or 1)
	end
	PlaceProps()
	for _, t in ipairs(game.tanks) do
		for _ = 1, rules.start do GiveItem(t, PickItem(nil, true)) end
	end

	-- Turn order: shuffled, or alternating teams (each team shuffled)
	if teams then
		local a, b = {}, {}
		for i, t in ipairs(game.tanks) do tinsert(t.team == 1 and a or b, i) end
		Shuffle(a)
		Shuffle(b)
		for k = 1, max(#a, #b) do
			if a[k] then tinsert(game.order, a[k]) end
			if b[k] then tinsert(game.order, b[k]) end
		end
	else
		for i = 1, n do game.order[i] = i end
		Shuffle(game.order)
	end
	-- Random first player (shared PRNG); rotating the order keeps teams alternating
	game.oi = Rand(1, #game.order)
	game.cur = game.order[game.oi]
	game.tanks[game.cur].fuel = min(rules.moves, rules.gain) * rules.dist
	game.wind = Rand(-game.windMax, game.windMax)
	game.turnStart = GetTime()

	for _, v in ipairs(vis) do
		v.x, v.y, v.fy, v.hpv, v.lastHp, v.alive, v.flash, v.recoil, v.tilt = nil, nil, 0, nil, nil, nil, 0, 0, 0
		v.fall, v.jet, v.warp = nil, nil, nil
		if v.faller then v.faller:Hide() end
	end
	for _, v in ipairs(crateVis) do
		v.used, v.to, v.wait = nil, nil, nil
		v.box:Hide()
		v.chute:Hide()
	end

	-- Sky and biome colours; darker skies dim the land
	field.ApplySky(sky, biome)
	local lt = sky.light
	field.dirt = { biome.dirt[1] * lt, biome.dirt[2] * lt, biome.dirt[3] * lt }
	field.top = { biome.top[1] * lt, biome.top[2] * lt, biome.top[3] * lt }
	for i = 1, NCOLS do field.Shade(i) end

	-- Prop sprites, picked and tinted by biome
	for _, v in ipairs(propVis) do
		v.tex:Hide()
		v.light:Hide()
	end
	for i, p in ipairs(game.props) do
		local v = propVis[i]
		if not v then
			v = { tex = field:CreateTexture(nil, "ARTWORK", nil, 2), light = field:CreateTexture(nil, "OVERLAY", nil, 1) }
			v.light:SetTexture(MEDIA .. "glow")
			v.light:SetBlendMode("ADD")
			v.light:SetVertexColor(1, 0.15, 0.1)
			v.light:SetSize(6, 6)
			propVis[i] = v
		end
		local def, tex, tint = PROPS[p.kind], p.kind, { 1, 1, 1 }
		if p.kind == "tree" then
			tex = biome.trees[p.col % #biome.trees + 1] -- mixed woods, same on every client
			if tex ~= "cactus" then tint = biome.flora end
		elseif p.kind == "bush" then
			tex, tint = biome.bush or "bush", biome.flora
		elseif p.kind == "rock" then
			tex, tint = biome.rock or "rock", biome.stone or { 0.75, 0.75, 0.78 }
		end
		v.tex:SetTexture(MEDIA .. tex)
		v.tex:SetSize(def.w, def.h)
		v.tex:SetVertexColor(tint[1] * lt, tint[2] * lt, tint[3] * lt)
		tint = { tint[1] * lt, tint[2] * lt, tint[3] * lt }
		v.tex:Show()
		v.light:SetShown(p.kind == "mine")
		v.alive, v.y, v.tint = true, p.y, tint
		p.v = v
	end

	HideShells()
	EndTargeting()
	banner:Hide()
	sb:Hide()
	shop:Hide()
	wipe(rockets)
	DrawTerrain(true)
	frame.ticker:Show()
	if not game.spectating then
		frame:Show()
		if not GoblinShellshockDB.helpSeen then
			GoblinShellshockDB.helpSeen = true
			frame.Help()
		end
		Print(("%s, %s rules. Arrows aim, Space fires, Q/E item, A/D move, hold Tab for scores. %ds per shot."):format(game.mapName, game.rulesName, rules.time))
	end
	if rules.shop == 1 then
		-- carts[i]: tank i's purchases once its BUY is in. Solo shops for each tank in turn.
		game.shopping = { carts = {}, ends = GetTime() + SHOPTIME }
		for i, t in ipairs(game.tanks) do
			if solo or t.name == Me() then shop.Open(i) break end
		end
		DrawAll()
		return
	end
	DrawAll()
	Announce()
end

-- Shop finished: every tank gets its cart, then leftover gold buys random affordable items
-- (shared PRNG, in tank order), and the first turn starts.
function shop.Finish()
	local s = game.shopping
	game.shopping = nil
	shop:Hide()
	for i, t in ipairs(game.tanks) do
		local left = game.rules.gold
		for _, k in ipairs(s.carts[i] or {}) do
			GiveItem(t, k)
			left = left - Price(WEAPONS[k])
		end
		local tries = 0
		while left >= 15 and tries < 200 do
			tries = tries + 1
			local k = PickItem(nil, true)
			local w = WEAPONS[k]
			if Price(w) <= left and (w.power or max(0, t.ammo[k]) < (w.one and 1 or CRATEAMMO)) then
				GiveItem(t, k)
				left = left - Price(WEAPONS[k])
			end
		end
		-- Change too small for anything else goes on Rocket Boots
		for k, w in ipairs(WEAPONS) do
			if w.power == "moves" then
				while left >= Price(w) do
					GiveItem(t, k)
					left = left - Price(w)
				end
			end
		end
	end
	game.turnStart = GetTime()
	DrawAll()
	Announce()
end

-- Shows the shop for tank i
function shop.Open(i)
	-- Solo AI tanks skip the shop: all their gold goes on random items
	while game.shopping and game.solo and game.tanks[i] and game.tanks[i].ai do
		shop.Receive(i, {})
		i = i + 1
	end
	if not (game.shopping and game.tanks[i]) then return end
	shop.for_, shop.cart, shop.sent = i, {}, nil
	shop.who:SetText(game.solo and ("for " .. Short(game.tanks[i].name)) or "")
	shop.Draw()
	shop:Show()
end

-- Validates and stores tank i's cart; finishes once every tank is in
function shop.Receive(i, list)
	local s = game.shopping
	if not s or s.carts[i] then return end
	local cart, cost = {}, 0
	for _, k in ipairs(list) do
		local w = WEAPONS[k]
		if w and w.weight and not w.crate then
			cost = cost + Price(w)
			if cost > game.rules.gold then break end
			tinsert(cart, k)
		end
	end
	s.carts[i] = cart
	for j = 1, #game.tanks do
		if not s.carts[j] then return end
	end
	shop.Finish()
end

-- Ready (or time's up). In a group the cart only counts once our own BUY echoes back,
-- so every client applies carts in the same order as the host's SHOPEND.
function shop.Submit()
	if shop.sent or not (game and game.shopping) then return end
	shop.sent = true
	shop:Hide()
	if game.solo then
		local i = shop.for_
		shop.Receive(i, shop.cart)
		if game.shopping and game.tanks[i + 1] then
			game.shopping.ends = GetTime() + SHOPTIME
			shop.Open(i + 1)
		end
	else
		Send("BUY", table.concat(shop.cart, "."))
	end
end

------------------------------------------------------------------------
-- Lobby / networking
------------------------------------------------------------------------
-- Names on the host's realm go without the realm to keep 10 players inside one message
local function EncodeRoster(list)
	local out = {}
	for i, p in ipairs(list) do out[i] = p.team .. Ambiguate(p.name, "none") end
	return table.concat(out, ",")
end

-- sender: the host, whose realm fills in names sent without one
local function ParseRoster(s, sender)
	local list, realm = {}, sender:match("%-(.+)$")
	for _, e in ipairs({ strsplit(",", s or "") }) do
		if #e > 1 then
			local name = e:sub(2)
			if not name:find("-", 1, true) and realm then name = name .. "-" .. realm end
			tinsert(list, { team = tonumber(e:sub(1, 1)) or 1, name = name })
		end
	end
	return list
end

-- Redraws now; sends RULES + LOBBY once clicks settle, so fast rule tweaking doesn't flood the channel
local function BroadcastLobby()
	DrawLobby()
	if lobby.solo or lobby.queued then return end
	lobby.queued = true
	local l = lobby
	C_Timer.After(0.4, function()
		l.queued = nil
		if lobby ~= l then return end
		Send("RULES", RULEDEFS.Encode(l.rules))
		Send("LOBBY", l.teams and "t" or "f", EncodeRoster(l.players))
	end)
end

-- Host only. names: players to seat, auto-balanced into alternating teams. solo: local hotseat test.
local function OpenLobby(names, solo)
	local other = not solo and OtherHost()
	if other then Print(Short(other) .. " is already hosting a lobby or match in your group.") return end
	game = nil
	frame:Hide()
	lobby = { host = Me(), teams = lastTeams, rules = RULEDEFS.Copy(lastRules or PRESETS[1]), players = {}, solo = solo }
	for i, name in ipairs(names) do
		if i <= MAXPLAYERS then tinsert(lobby.players, { name = name, team = (i - 1) % 2 + 1 }) end
	end
	if not solo then
		groupHost, hostOk = Me(), nil
		Send("HELLO", VERSION)
	end
	BroadcastLobby()
	ShowLobby()
end

local function CloseLobby()
	if not lobby then return end
	if lobby.solo then
		-- nothing to tell anyone
	elseif lobby.host == Me() then
		Send("CLOSE")
		groupHost = nil
	elseif joining then
		Send("LEAVE")
	end
	lobby, joining = nil, nil
	lobbyFrame:Hide()
	toast.HostUpdate()
end

-- Leaving: the x, Escape and /gs quit. Hosting a running match ends it for everyone (nobody else can call time)
function frame.Quit()
	if game and game.host == Me() and not game.solo and not game.over then
		Send("CLOSE")
		groupHost = nil
	end
	game = nil
	frame:Hide()
	CloseLobby()
	toast.HostUpdate()
end

local function StartMatch()
	local count = { 0, 0 }
	for _, p in ipairs(lobby.players) do count[p.team] = count[p.team] + 1 end
	if #lobby.players < 2 then Print("Need at least 2 players.") return end
	if lobby.teams and (count[1] == 0 or count[2] == 0) then Print("Both teams need a player.") return end

	local roster = {}
	for team = 1, 2 do
		for _, p in ipairs(lobby.players) do
			if not lobby.teams or p.team == team then tinsert(roster, p) end
		end
		if not lobby.teams then break end
	end
	local teams, rules, solo, s = lobby.teams, lobby.rules, lobby.solo, random(1, 2147483646)
	lastTeams, lastRules = teams, RULEDEFS.Copy(rules)
	if not solo then
		Send("RULES", RULEDEFS.Encode(rules))
		if not Send("START", VERSION, s, teams and "t" or "f", EncodeRoster(roster)) then
			Print("Too many long cross-realm names to start. Remove a player and try again.")
			return
		end
	end
	lobby = nil
	lobbyFrame:Hide()
	StartGame(s, roster, teams, RULEDEFS.Copy(rules), solo, Me())
end

local function HostStart()
	if not IsInGroup() then Print("Join a group, or use /gs solo.") return end
	if lobby and lobby.solo then CloseLobby() end
	if lobby and lobby.host == Me() then ShowLobby() return end
	OpenLobby({ Me() })
end

-- Solo test lobby: you plus hotseat tanks
local function SoloLobby()
	if lobby and lobby.solo then ShowLobby() return end
	CloseLobby()
	OpenLobby({ Me(), "Player 2" }, true)
end

do
	local L = lobbyFrame
	local function IsHost() return lobby and lobby.host == Me() end
	L.ffa:SetScript("OnClick", function()
		if IsHost() and lobby.teams then lobby.teams = false BroadcastLobby() end
	end)
	L.teams:SetScript("OnClick", function()
		if IsHost() and not lobby.teams then lobby.teams = true BroadcastLobby() end
	end)
	for k, b in ipairs(L.presets) do
		b:SetScript("OnClick", function()
			if not IsHost() then return end
			-- Presets don't touch the map look or team spawns
			local old = lobby.rules
			lobby.rules = RULEDEFS.Copy(PRESETS[k])
			for key in pairs(RULEDEFS.KEEP) do lobby.rules[key] = old[key] end
			BroadcastLobby()
		end)
	end
	for k, d in ipairs(RULEDEFS) do
		local row = L.rules[k]
		local function Step(dir)
			if not IsHost() then return end
			local r = lobby.rules
			r[d.key] = RULEDEFS.Step(d, r[d.key], dir)
			BroadcastLobby()
		end
		row.less:SetScript("OnClick", function() Step(-1) end)
		row.more:SetScript("OnClick", function() Step(1) end)
		if row.toggle then
			row.toggle:SetScript("OnClick", function() Step(lobby.rules[d.key] == d.lo and 1 or -1) end)
		end
	end
	L.more:SetScript("OnClick", function()
		if not (lobby and lobby.solo) or #lobby.players >= MAXPLAYERS then return end
		local k = 2
		while InRoster(lobby.players, "Player " .. k) do k = k + 1 end
		tinsert(lobby.players, { name = "Player " .. k, team = #lobby.players % 2 + 1 })
		DrawLobby()
	end)
	L.less:SetScript("OnClick", function()
		if not (lobby and lobby.solo) or #lobby.players <= 2 then return end
		tremove(lobby.players)
		DrawLobby()
	end)
	for _, r in ipairs(L.rows) do
		r:SetScript("OnClick", function(self)
			if not (IsHost() and lobby.teams and self.player) then return end
			self.player.team = 3 - self.player.team
			BroadcastLobby()
		end)
		r.ai:SetScript("OnClick", function(self)
			local p = self:GetParent().player
			if not (lobby and lobby.solo and p) then return end
			p.ai = (p.ai or 0) < #frame.AILEVELS and (p.ai or 0) + 1 or nil
			DrawLobby()
		end)
	end
	L.action:SetScript("OnClick", function()
		if IsHost() then StartMatch() else CloseLobby() end
	end)
	L.close:SetScript("OnClick", CloseLobby)
	-- Resends HELLO; players already in the lobby ignore it. 10s cooldown so it can't spam the group.
	L.announce:SetScript("OnClick", function()
		if not IsHost() or lobby.solo then return end
		if (L.announced or 0) > GetTime() then Print("Wait a few seconds before announcing again.") return end
		L.announced = GetTime() + 10
		Send("HELLO", VERSION)
		Print("Lobby announced to your group.")
	end)
end

restartBtn:SetScript("OnClick", function()
	if not (game and game.host == Me()) then return end
	local names, bots = {}, {}
	for _, t in ipairs(game.tanks) do
		tinsert(names, t.name)
		bots[t.name] = t.ai
	end
	for name in pairs(game.specs) do tinsert(names, name) end
	OpenLobby(names, game.solo)
	if lobby and lobby.solo then -- keep which tanks the computer plays
		for _, p in ipairs(lobby.players) do p.ai = bots[p.name] end
		DrawLobby()
	end
end)

restartBtn.again:SetScript("OnClick", function()
	if not (game and game.over and game.host == Me()) then return end
	local other = not game.solo and OtherHost()
	if other then Print(Short(other) .. " is already hosting a lobby or match in your group.") return end
	-- Rebuild the lobby this match came from and start it straight away (same seat order)
	local players = {}
	for _, t in ipairs(game.tanks) do tinsert(players, { name = t.name, team = game.teams and t.team or 1, ai = t.ai }) end
	lobby = { host = Me(), teams = game.teams, rules = RULEDEFS.Copy(game.rules), players = players, solo = game.solo }
	if not game.solo then groupHost = Me() end
	StartMatch()
	if lobby then ShowLobby() end -- couldn't start: fall back to the lobby
end)

-- Minimized reminder: while you're in a lobby or match but its window is hidden (minimized, or after
-- combat), a small panel under the toast says so, with buttons to reopen it or leave.
-- Leaving as the host closes it for everyone.
do
	local r = CreateFrame("Button", nil, UIParent)
	r:SetSize(TOASTW, 52)
	r:SetPoint("TOP", toast, "BOTTOM", 0, -6)
	r:SetFrameStrata("HIGH")
	Panel(r)
	r:Hide()
	local icon = r:CreateTexture(nil, "OVERLAY")
	icon:SetSize(14, 14)
	icon:SetPoint("TOPLEFT", 8, -7)
	icon:SetTexture(MEDIA .. "cog")
	icon:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
	r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.text:SetPoint("LEFT", icon, "RIGHT", 5, 0)
	local open = FlatButton(r, 90, 18, "Open")
	open:SetPoint("BOTTOMLEFT", 8, 7)
	local close = FlatButton(r, 90, 18, "Close game")
	close:SetPoint("BOTTOMRIGHT", -8, 7)
	toast.hosting = r

	function toast.HostUpdate()
		local what, leave
		local mine = lobby and lobby.host == Me()
		if lobby and (mine or joining == lobby.host) then
			if mine then
				what, leave = "Your Goblin Shellshock lobby is still open.", "Close lobby"
			else
				what, leave = "You're in " .. Short(lobby.host) .. "'s lobby.", "Leave"
			end
		elseif game and (not game.spectating or game.specSent) then
			if game.over then
				what, leave = "Your Goblin Shellshock match has ended.", "Close"
			elseif game.spectating then
				what, leave = "You're watching a Goblin Shellshock match.", "Stop watching"
			elseif game.host == Me() and not game.solo then
				what, leave = "Your Goblin Shellshock match is still running.", "End match"
			else
				what, leave = "Your Goblin Shellshock match is minimized.", "Leave"
			end
		end
		local show = what and not frame:IsShown() and not lobbyFrame:IsShown()
			and not InCombatLockdown() and not UnitAffectingCombat("player")
		if show then
			r.text:SetText(what)
			close:SetText(leave)
		end
		r:SetShown(show and true or false)
	end

	local function Reopen()
		if InCombatLockdown() then return end
		if lobby then ShowLobby() elseif game then frame:Show() end
	end
	r:SetScript("OnClick", Reopen)
	open:SetScript("OnClick", Reopen)
	close:SetScript("OnClick", function() frame.Quit() end)
end

frame:SetScript("OnShow", function()
	if game and game.spectating and not game.specSent then
		game.specSent = true
		Send("SPEC")
	end
end)
-- Hooked after the scripts above are set, so they don't replace these
frame:HookScript("OnShow", toast.HostUpdate)
frame:HookScript("OnHide", toast.HostUpdate)
-- Animation stops while the window is hidden, so drop any wreck mid-fall instead of leaving it on screen
frame:HookScript("OnHide", function()
	for _, v in ipairs(vis) do
		v.fall = nil
		if v.faller then v.faller:Hide() end
	end
end)
lobbyFrame:HookScript("OnShow", toast.HostUpdate)
lobbyFrame:HookScript("OnHide", toast.HostUpdate)

-- Join and spectate popups that come unasked can be turned off in Options; /gs still shows them
function frame.JoinPopups() return frame.forceJoin or GoblinShellshockDB.joinPopups ~= false end

local function OnMessage(msg, sender)
	local cmd, a, b, c, d, e = strsplit(":", msg)
	-- One lobby or match per group. The channel delivers in the same order to everyone, so the first
	-- HELLO wins: a host whose own HELLO comes back first keeps the lobby; one who sees another HELLO
	-- first lost a simultaneous start and closes. Later starters get BUSY from the current host.
	if cmd == "HELLO" and sender == Me() then
		if groupHost == Me() then hostOk = true end
		return
	elseif cmd == "HELLO" and groupHost == Me() then
		if hostOk then Send("BUSY", sender) return end
		Print(Short(sender) .. " opened a lobby at the same moment and got there first.")
		CloseLobby()
	elseif cmd == "BUSY" then
		if a == Me() and lobby and lobby.host == Me() and not lobby.solo then
			Print(Short(sender) .. " is already hosting a lobby or match in your group.")
			CloseLobby()
			groupHost = sender
		end
		return
	elseif (cmd == "HELLO" or cmd == "LOBBY" or cmd == "START") and OtherHost() and OtherHost() ~= sender then
		return -- someone else already has the group's lobby or match
	end
	if cmd == "HELLO" or cmd == "LOBBY" or cmd == "START" then groupHost = sender end

	if cmd == "HELLO" then
		if a ~= VERSION then
			local why = ("%s opened a lobby on Goblin Shellshock v%s. You have v%s, so you can't join until you're on the same version."):format(Short(sender), a or "?", VERSION)
			Print(why)
			if frame.JoinPopups() then
				ShowToast(("%s's lobby is v%s, you have v%s."):format(Short(sender), a or "?", VERSION), "OK", nil, sender, TOASTTIME)
			end
			return
		end
		-- A re-announce: already in (or joining) this lobby, so no popup
		if lobby and lobby.host == sender and (joining == sender or InRoster(lobby.players, Me())) then return end
		if not frame.JoinPopups() then
			Print(Short(sender) .. " opened a lobby. Type /gs to join.")
			return
		end
		ShowToast(Short(sender) .. " opened a Goblin Shellshock lobby.", "Join", function()
			if InCombatLockdown() then Print("Not available in combat.") return end
			joining = sender
			Send("JOIN", VERSION)
			if not (lobby and lobby.host == sender) then
				lobby = { host = sender, teams = false, rules = hostRules[sender] or RULEDEFS.Copy(PRESETS[1]), players = {} }
			end
			ShowLobby()
		end, sender, TOASTTIME)
	elseif cmd == "JOIN" then
		if not (lobby and lobby.host == Me()) then return end
		if a ~= VERSION then
			Print(("%s tried to join on v%s (you have v%s)."):format(Short(sender), a or "?", VERSION))
			return
		end
		if #lobby.players >= MAXPLAYERS or InRoster(lobby.players, sender) then return end
		local count = { 0, 0 }
		for _, p in ipairs(lobby.players) do count[p.team] = count[p.team] + 1 end
		tinsert(lobby.players, { name = sender, team = count[1] <= count[2] and 1 or 2 })
		BroadcastLobby()
	elseif cmd == "LEAVE" then
		if not (lobby and lobby.host == Me()) then return end
		for i = #lobby.players, 1, -1 do
			if lobby.players[i].name == sender then tremove(lobby.players, i) end
		end
		BroadcastLobby()
	elseif cmd == "LOBBY" then
		if (lobby and lobby.solo) or (game and game.solo) then return end -- don't clobber a solo test
		-- The match host reopening a lobby ends their running match here too
		if game and game.host == sender then
			game = nil
			frame:Hide()
		end
		lobby = { host = sender, teams = a == "t", rules = hostRules[sender] or RULEDEFS.Copy(PRESETS[1]), players = ParseRoster(b, sender) }
		if InRoster(lobby.players, Me()) then
			joining = sender
			HideToast(sender)
			ShowLobby()
		elseif joining == sender then
			ShowLobby()
		else
			lobbyFrame:Hide()
		end
	elseif cmd == "CLOSE" then
		if groupHost == sender then groupHost = nil end
		if lobby and lobby.host == sender then
			lobby, joining = nil, nil
			lobbyFrame:Hide()
		end
		-- The host quit their running match: it can't go on without them
		if game and game.host == sender and not game.over then
			game = nil
			frame:Hide()
			Print(Short(sender) .. " ended the match.")
		end
		HideToast(sender)
	elseif cmd == "START" then
		if a ~= VERSION then
			Print(("%s started a match on v%s. You have v%s, so you can't watch it."):format(Short(sender), a or "?", VERSION))
			return
		end
		if (lobby and lobby.solo) or (game and game.solo) then return end -- don't clobber a solo test
		local roster = ParseRoster(d, sender)
		lobby, joining = nil, nil
		lobbyFrame:Hide()
		HideToast(sender)
		StartGame(tonumber(b), roster, c == "t", RULEDEFS.Copy(hostRules[sender] or PRESETS[1]), false, sender)
		if game.spectating and not frame.JoinPopups() then
			Print(Short(sender) .. "'s match has started. Type /gs to watch.")
		elseif game.spectating then
			ShowToast(Short(sender) .. "'s match has started.", "Spectate", function() frame:Show() end, sender, TOASTTIME)
		end
	elseif cmd == "RULES" then
		hostRules[sender] = RULEDEFS.Decode(a)
		if lobby and lobby.host == sender then
			lobby.rules = hostRules[sender]
			DrawLobby()
		end
	elseif cmd == "VQ" then
		Send("VR", sender, VERSION) -- /gs version from someone: tell them ours
	elseif cmd == "VR" then
		local seen = lobbyFrame.versions
		if a == Me() and seen then seen[sender] = b or "?" end
	elseif cmd == "SCAN" then
		-- Someone typed /gs: tell just them what we're hosting
		if groupHost ~= Me() then return end
		if lobby and lobby.host == Me() and not lobby.solo then
			Send("OPEN", sender, VERSION, "l")
		elseif game and game.host == Me() and not game.solo and not game.over then
			Send("OPEN", sender, VERSION, "m")
		end
	elseif cmd == "OPEN" then
		if a ~= Me() then return end
		lobbyFrame.scanning = nil
		if c == "l" then
			-- Same Join popup as a fresh lobby, worded for a lobby that's been up a while. We asked
			-- for it, so it shows even with the automatic popups off.
			frame.forceJoin = true
			OnMessage("HELLO:" .. (b or "?"), sender)
			frame.forceJoin = nil
			if b == VERSION then toast.text:SetText(Short(sender) .. " has a lobby open. Want to join?") end
		elseif c == "m" then
			groupHost = sender
			Print(Short(sender) .. "'s match is in progress. You can join their next lobby.")
		end
	elseif cmd == "SPEC" then
		if game and game.host == Me() and not InRoster(game.tanks, sender) then
			game.specs[sender] = true
			DrawStatus()
		end
	elseif not game or game.over then
		return
	elseif cmd == "BUY" then
		for i, t in ipairs(game.tanks) do
			if t.name == sender then
				local list = {}
				for _, v in ipairs({ strsplit(".", a or "") }) do tinsert(list, tonumber(v)) end
				shop.Receive(i, list)
			end
		end
	elseif cmd == "SHOPEND" then
		if game.shopping and sender == game.host then shop.Finish() end
	elseif game.shopping then
		return
	elseif cmd == "FIRE" then
		local t, wi = game.tanks[game.cur], tonumber(d)
		if tonumber(a) ~= game.turn or sender ~= t.name or game.shot or game.landed then return end
		if not (wi and WEAPONS[wi] and not WEAPONS[wi].power and t.ammo[wi] ~= 0) then return end
		t.angle, t.power, t.weapon = tonumber(b), tonumber(c), wi
		Launch()
	elseif cmd == "USE" then
		local t, i, arg = game.tanks[game.cur], tonumber(b), tonumber(c)
		if tonumber(a) ~= game.turn or sender ~= t.name or game.shot or game.landed then return end
		local w = i and WEAPONS[i]
		if not (w and w.power and t.ammo[i] > 0) then return end
		if w.power == "teleport" and not (arg and ValidTeleport(t, arg)) then return end
		if w.power == "jet" then return end -- comes as JET
		ApplyPower(t, i, arg)
		DrawAll()
	elseif cmd == "JET" then
		local t, i, col = game.tanks[game.cur], tonumber(b), tonumber(c)
		if tonumber(a) ~= game.turn or sender ~= t.name or game.shot or game.landed then return end
		local w = i and WEAPONS[i]
		if not (w and w.power == "jet" and t.ammo[i] > 0 and col and ValidTeleport(t, col)) then return end
		-- Replay the flight on the drawn tank, starting from where it stands
		local v, pts = vis[t.i], {}
		if v.x then pts[1] = { v.x, v.y } end
		for _, p in ipairs({ strsplit("_", d or "") }) do
			local x, y = strsplit(".", p)
			if tonumber(x) and tonumber(y) then tinsert(pts, { tonumber(x), tonumber(y) }) end
		end
		if #pts >= 2 then v.jet = { pts = pts, t0 = GetTime() } end
		ApplyPower(t, i, col)
		DrawAll()
	elseif cmd == "MOVE" or cmd == "DONE" then
		local t = game.tanks[game.cur]
		if tonumber(a) ~= game.turn or sender ~= t.name then return end
		-- Anything after the HIT can arrive before our copy of the shot has landed: replay it after.
		-- Driving before the HIT (during the flight) applies right away, in order.
		if game.hit then
			game.queue = game.queue or {}
			tinsert(game.queue, { msg, sender })
			return
		end
		if cmd == "DONE" then
			if game.retreat then EndTurn() end
			return
		end
		MoveTank(t, tonumber(b) == 1 and 1 or -1, tonumber(c) or 0)
		if t.alive then
			DrawAll()
		elseif not (game.shot or game.landed) then
			EndTurn() -- otherwise the shot still lands first
		end
	elseif cmd == "HIT" then
		if tonumber(a) ~= game.turn or sender ~= game.tanks[game.cur].name then return end
		local pts = { select(4, strsplit(":", msg)) }
		for i, v in ipairs(pts) do pts[i] = tonumber(v) end
		game.hit = { sum = tonumber(b), pts = pts }
		TryRemoteResolve()
	elseif cmd == "SKIP" then
		if tonumber(a) ~= game.turn or sender ~= game.host then return end
		Skip()
	end
end

------------------------------------------------------------------------
-- Input, events, loop
------------------------------------------------------------------------
local KEYS = { LEFT = true, RIGHT = true, UP = true, DOWN = true, SPACE = true, Q = true, E = true, A = true, D = true,
	W = true, S = true } -- W / S only steer a jetpack

frame:EnableKeyboard(true)
if not InCombatLockdown() then frame:SetPropagateKeyboardInput(true) end
frame:SetScript("OnKeyDown", function(self, key)
	if InCombatLockdown() then return end
	if key == "TAB" and game then
		self:SetPropagateKeyboardInput(false)
		DrawScores()
		return
	end
	-- Escape closes the help first, then leaves the match like the x
	if key == "ESCAPE" then
		self:SetPropagateKeyboardInput(false)
		if frame.help and frame.help:IsShown() then frame.help:Hide() else frame.Quit() end
		return
	end
	local drive = key == "A" or key == "D"
	local jet = game and game.jet and key ~= "SPACE" and key ~= "Q" and key ~= "E"
	local fly = key == "W" or key == "S"
	local capture = KEYS[key] and (jet or (not fly and (CanAim() or (drive and frame.CanMove()))))
	self:SetPropagateKeyboardInput(not capture)
	if not capture or game.targeting then return end
	if jet then
		held[key] = true -- steering the jetpack (in the loop)
		return
	end
	if key == "SPACE" then
		if WEAPONS[game.tanks[game.cur].weapon].power then UseItem() else Fire() end
	elseif key == "Q" or key == "E" then
		CycleWeapon(key == "E" and 1 or -1)
	else
		held[key] = true -- arrows aim, A / D drive (both in the loop)
	end
end)
frame:SetScript("OnKeyUp", function(_, key)
	held[key] = nil
	if key == "TAB" and game and not game.over then sb:Hide() end
end)

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

local driver = CreateFrame("Frame")
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("CHAT_MSG_ADDON")
driver:RegisterEvent("PLAYER_REGEN_DISABLED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:SetScript("OnEvent", function(_, event, prefix, msg, _, sender)
	-- Raids carry a lot of other addons' traffic, so bail on foreign prefixes first
	if event == "CHAT_MSG_ADDON" then
		if prefix ~= PREFIX then return end
	elseif event == "ADDON_LOADED" then
		if prefix == "GoblinShellshock" then
			driver:UnregisterEvent("ADDON_LOADED")
			GoblinShellshockDB = GoblinShellshockDB or {}
			PlaceToast()
			if GoblinShellshockDB.scale then
				frame:SetScale(GoblinShellshockDB.scale)
				frame.SyncScale()
			end
			if GoblinShellshockDB.lobbyScale then
				lobbyFrame:SetScale(GoblinShellshockDB.lobbyScale)
				lobbyFrame.SyncScale()
			end
			frame.InitMinimap()
		end
		return
	elseif event == "PLAYER_REGEN_ENABLED" then
		toast.HostUpdate() -- bring the host reminder back after the fight
		return
	else -- PLAYER_REGEN_DISABLED
		frame:Hide()
		lobbyFrame:Hide()
		toast.hosting:Hide()
		return
	end
	if not sender:find("-", 1, true) then sender = sender .. "-" .. GetNormalizedRealmName() end
	-- Our own BUY and SHOPEND echo back; acting on the echo keeps shop results in channel order
	if sender ~= Me() or msg:find("^BUY") or msg:find("^SHOPEND") or msg:find("^HELLO") then OnMessage(msg, sender) end
end)

------------------------------------------------------------------------
-- Animation (visual only; never touches sim state)
------------------------------------------------------------------------
local function AnimateTerrain(e)
	if not terrainDirty then return end
	local busy, lo, hi
	for i = 1, NCOLS do
		local h, v = game.h[i], hv[i]
		if v ~= h then
			busy, lo, hi = true, lo or i, i
			if v > h then
				hvv[i] = hvv[i] + FALLG * e
				v = max(h, v - hvv[i] * e)
			else
				v = min(h, v + 200 * e)
			end
			if v == h then hvv[i] = 0 end
			hv[i] = v
			SetCol(i, v)
		end
	end
	if lo then field.ShadeRange(lo, hi) end
	terrainDirty = busy
end

local function AnimateTanks(e)
	for i, t in ipairs(game.tanks) do
		local v = vis[i]
		if v.x then
			-- A tank that fell out keeps driving or sliding until it's over the pit, then drops
			-- and down to the bottom of the map, then keeps going
			local waiting = t.fell and v.alive and v.y > 0.5
			if v.alive and not t.alive and not waiting then
				if t.fell then
					-- Fell out of the map: keeps its speed and tumbles on down through the window
					v.fall = { x = v.x, y = v.y + 5, vx = random(-25, 25), vy = -max(v.fy or 0, 120), spin = 0,
						rate = (random(2) == 1 and 1 or -1) * (3 + random() * 3) }
					Dust(v.x, v.y, 6)
				else
					TankDeath(v.x, v.y + 5, v.color)
				end
			end
			if not waiting then v.alive = t.alive end
			if t.hp < v.lastHp and not t.fell then -- no damage number for falling out
				Floater("-" .. (v.lastHp - t.hp), v.x, v.y + 34, 1, 0.35, 0.3)
				v.flash = 1
			end
			v.lastHp = t.hp
			v.hpv = t.hp > v.hpv and t.hp or max(t.hp, v.hpv - 40 * e)
			v.flash = max(0, v.flash - 4 * e)
			v.recoil = max(0, v.recoil - e)

			-- Goblin engines: little exhaust puffs from the stack
			v.puff = (v.puff or 0) - e
			if v.puff <= 0 and t.alive then
				v.puff = 0.5 + random() * 0.6
				local back = t.angle > 90 and 7 or -7
				Particle("smoke", v.x + back, v.y + 11, back * 0.6, random(12, 22), 1, 2, 6, 0.3)
			end

			-- Damage smoke from the hull once it's lost 15% health: more, bigger and blacker the closer
			-- it is to dying, with embers in it at the end
			local hurt = t.alive and v.alive and 1 - t.hp / game.rules.hp or 0
			v.smoke = (v.smoke or 0) - e
			if hurt > 0.15 and v.smoke <= 0 then
				v.smoke = (0.9 - 0.75 * hurt) * (0.8 + random() * 0.4)
				local g = 0.5 - 0.42 * hurt
				Particle("smoke", v.x + random(-4, 4), v.y + 8, random(-6, 6), 14 + 12 * hurt,
					1.2 + 1.3 * hurt, 4 + 6 * hurt, 10 + 22 * hurt, 0.25 + 0.4 * hurt, { g, g, g * 1.05 })
				if hurt > 0.75 and random() < 0.35 then
					Particle("ember", v.x + random(-3, 3), v.y + 8, random(-15, 15), random(30, 60), 0.5, 2, 1, 0.9)
				end
			end

			-- On a jetpack the flight (or its replay) places the tank instead
			if not frame.JetVis(v, e) then
				-- Glides at a steady speed along the ground, so it goes slower across while on a slope.
				-- Warping: glide to the teleporter first, then pop out of the other one.
				local tx = v.warp and v.warp.at or t.x
				if v.x ~= tx then
					local dx = tx - v.x
					local s = dx > 0 and 2 or -2
					local grade = min(CLIMB, abs(GroundAt(v.x + s) - GroundAt(v.x))) / 2 -- a cliff edge isn't a slope
					local step = 40 * e / sqrt(1 + grade * grade)
					v.x = abs(dx) <= step and tx or v.x + (dx > 0 and step or -step)
				end
				if v.warp and v.x == tx then
					Particle("tele", v.x, v.y + 6, 0, 0, 0.4, 10, 50, 1)
					v.x, v.y, v.fy = v.warp.to, GroundAt(v.warp.to) + 20, 0
					Particle("tele", v.x, v.y, 0, 0, 0.4, 50, 10, 1)
					v.warp = nil
				end
				-- Resting spot: the sim height when parked (it can be below the dirt when buried)
				local ground = v.x == t.x and min(hv[t.col], t.y) or field.SmoothGround(v.x)
				-- Downhill it follows the ground; only a drop taller than a climb (or one already under way) is a fall
				if v.y > ground + CLIMB + 1 or (v.fy > 0 and v.y > ground + 0.5) then
					v.fy = v.fy + FALLG * e
					v.y = max(ground, v.y - v.fy * e)
					if v.y == ground then
						if v.fy > 150 then Dust(v.x, v.y, 5) end
						v.fy = 0
					end
				else
					v.y, v.fy = ground, 0
				end
			end
			-- Hull leans with the slope under the treads, eased so it doesn't jitter;
			-- on a jetpack it leans into the direction it's flying instead
			local slope = v.jet and -0.35 * max(-1, min(1, (v.jvx or 0) / 90))
				or max(-1, min(1, atan2(GroundAt(v.x + 7) - GroundAt(v.x - 7), 14)))
			v.tilt = (v.tilt or 0) + (slope - (v.tilt or 0)) * min(1, 10 * e)
			DrawTank(i)
		end

		-- The falling wreck lives on its own frame over everything, since the field clips its children
		local fv = v.fall
		if fv then
			local f = v.faller
			if not f then
				f = CreateFrame("Frame", nil, UIParent)
				f:SetSize(1, 1)
				f:SetFrameStrata("FULLSCREEN_DIALOG")
				f.body = f:CreateTexture(nil, "ARTWORK", nil, 1)
				f.body:SetSize(22, 11)
				f.body:SetTexture(MEDIA .. "tank")
				f.body:SetPoint("CENTER")
				f.barrel = f:CreateLine(nil, "ARTWORK")
				f.barrel:SetThickness(3)
				v.faller = f
			end
			local c = v.color
			f:SetScale(frame:GetEffectiveScale() / UIParent:GetEffectiveScale())
			f.body:SetVertexColor(c[1], c[2], c[3])
			if t.angle > 90 then f.body:SetTexCoord(1, 0, 0, 1) else f.body:SetTexCoord(0, 1, 0, 1) end
			f.barrel:SetColorTexture(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6)
			fv.vy = fv.vy - 500 * e
			fv.x, fv.y = fv.x + fv.vx * e, fv.y + fv.vy * e
			fv.spin = fv.spin + fv.rate * e
			f:ClearAllPoints()
			f:SetPoint("CENTER", field, "BOTTOMLEFT", fv.x, fv.y)
			f.body:SetRotation(fv.spin)
			local a = rad(t.angle) + fv.spin
			f.barrel:SetStartPoint("CENTER", f, 0, 0)
			f.barrel:SetEndPoint("CENTER", f, cos(a) * BARREL, sin(a) * BARREL)
			f:Show()
			-- Past the window's bottom edge: the win banner may go. Off the screen: done.
			if fv.y < frame:GetBottom() - field:GetBottom() - 12 then fv.out, game.fellOut = true, true end
			if fv.y < -field:GetBottom() - 30 then
				v.fall = nil
				f:Hide()
			end
		end
	end
end

local function AnimateCrates(e)
	for _, c in ipairs(game.crates) do
		local v = c.v
		local x, ground = (c.col - 0.5) * COLW, hv[c.col]
		local sway = 0
		if v.chute:IsShown() then
			v.y = max(ground, v.y - 45 * e)
			sway = sin(GetTime() * 3) * 3
			if v.y == ground then
				v.chute:Hide()
				Dust(x, ground, 3)
			end
		else
			v.y = ground
		end
		-- Hangs straight under the chute, then sits flush with the slope once landed
		field.Stand(v.box, x + sway, v.y, 12, 12, v.chute:IsShown() and 0 or 1)
	end
	-- Already collected while airborne: drift onto the tank and pop on touch
	for _, v in ipairs(crateVis) do
		local tv = v.to and vis[v.to]
		if tv and tv.x then
			local dx = tv.x - v.x
			v.x = v.x + max(-60 * e, min(60 * e, dx))
			v.y = max(tv.y + TANKH, v.y - 45 * e)
			field.Stand(v.box, v.x, v.y, 12, 12, 0)
			if v.y <= tv.y + TANKH and abs(dx) < 4 then crateVis.Pop(v, v.x) end
		elseif v.to then
			crateVis.Pop(v, v.x)
		end
		-- Driven into: stays put until the drawn tank actually reaches it
		local wv = v.wait and vis[v.wait]
		if wv and (not wv.x or abs(wv.x - v.x) <= HITW / 2 + 4) then crateVis.Pop(v, v.x) end
	end
end

-- Props ride the visual ground; destroyed ones burst into bits in their colour
local function AnimateProps()
	for _, p in ipairs(game.props) do
		local v, x = p.v, (p.col - 0.5) * COLW
		if v.alive and not p.alive then
			local c = p.kind == "mine" and { 0.3, 0.3, 0.32 } or (p.kind == "barrel" and { 0.6, 0.15, 0.1 }) or v.tint
			for _ = 1, 10 do Particle("dirt", x, v.y + 6, random(-70, 70), random(60, 200), 1, 3, 3, 1, c) end
			v.tex:Hide()
			v.light:Hide()
		end
		v.alive = p.alive
		if p.alive then
			v.y = hv[p.col]
			local def = PROPS[p.kind]
			local a = field.Stand(v.tex, x, v.y - 1, def.w, def.h, def.lean or 1)
			if p.kind == "mine" then
				v.light:SetPoint("CENTER", field, "BOTTOMLEFT", x - sin(a) * 6, v.y - 1 + cos(a) * 6)
				v.light:SetAlpha(sin(GetTime() * 4) > 0.6 and 1 or 0.15)
			end
		end
	end
end

-- Teleporters: a stone pad with a glowing ring above it, blue on the left, orange on the right.
-- They drop out of the sky trailing sparks and thump down with a burst of dust.
frame.PORTALCOLORS = { { 0.3, 0.75, 1 }, { 1, 0.55, 0.15 } }
function frame.PortalsArrive()
	field.portalVis = field.portalVis or {}
	for k = 1, 2 do
		local pv = field.portalVis[k]
		if not pv then
			local c = frame.PORTALCOLORS[k]
			pv = {
				pad = field:CreateTexture(nil, "ARTWORK", nil, 3),
				core = field:CreateTexture(nil, "ARTWORK", nil, 4),
				ring = field:CreateTexture(nil, "ARTWORK", nil, 5),
			}
			pv.pad:SetColorTexture(0.2, 0.19, 0.22)
			pv.pad:SetSize(24, 4)
			pv.core:SetTexture(MEDIA .. "glow")
			pv.core:SetBlendMode("ADD")
			pv.core:SetVertexColor(c[1], c[2], c[3])
			pv.core:SetSize(20, 34)
			pv.ring:SetTexture(MEDIA .. "ring")
			pv.ring:SetBlendMode("ADD")
			pv.ring:SetVertexColor(c[1], c[2], c[3])
			pv.ring:SetSize(22, 36)
			field.portalVis[k] = pv
		end
		pv.y, pv.vy, pv.landed, pv.spark = H + 30 + k * 25, 0, false, 0
		pv.pad:Show()
		pv.core:Show()
		pv.ring:Show()
	end
end

function frame.AnimatePortals(e)
	local ps = field.portalVis
	if not ps then return end
	for k, pv in ipairs(ps) do
		local p = game.portals and game.portals[k]
		pv.pad:SetShown(p ~= nil)
		pv.core:SetShown(p ~= nil)
		pv.ring:SetShown(p ~= nil)
		if p then
			local x, ground, c = (p.col - 0.5) * COLW, hv[p.col] or 0, frame.PORTALCOLORS[k]
			if not pv.landed then
				pv.vy = pv.vy + FALLG * 0.5 * e
				pv.y = pv.y - pv.vy * e
				if random() < e * 30 then Particle("spark", x + random(-6, 6), pv.y + 20, 0, 30, 0.5, 3, 1, 0.9, c) end
				if pv.y <= ground then
					pv.landed = true
					Dust(x, ground, 8)
					Particle("flash", x, ground + 18, 0, 0, 0.25, 20, 50, 0.8, c)
				end
			end
			if pv.landed then pv.y = ground end
			local pulse = sin(GetTime() * 4 + k)
			-- Pad sits flush with the slope once landed, and the ring stands square to the pad
			local a = field.Stand(pv.pad, x, pv.y, 24, 4, pv.landed and 1 or 0)
			local rx, ry = x - sin(a) * 20, pv.y + cos(a) * 20
			pv.core:SetPoint("CENTER", field, "BOTTOMLEFT", rx, ry)
			pv.ring:SetPoint("CENTER", field, "BOTTOMLEFT", rx, ry)
			pv.core:SetRotation(a)
			pv.ring:SetRotation(a)
			pv.core:SetAlpha(0.35 + 0.15 * pulse)
			pv.ring:SetAlpha(0.8 + 0.2 * pulse)
			-- Sparks swirling up the ring
			pv.spark = pv.spark - e
			if pv.landed and pv.spark <= 0 then
				pv.spark = 0.07
				local s = GetTime() * 5 + k * 3
				Particle("spark", rx + cos(s) * 9, ry + sin(s) * 16, 0, 15, 0.6, 3, 1, 0.8, c)
			end
		end
	end
end

local function AnimateParticles(e)
	local wind = game and game.wind or 0
	for _, p in ipairs(parts) do
		if p.age < p.life then
			p.age = p.age + e
			local f, k = p.age / p.life, p.k
			p.vy = p.vy - (k.grav or 0) * e
			if k.drift then p.vx = p.vx + (wind * WINDK - p.vx) * min(1, 2 * e) end
			if k.drag then
				local d = max(0, 1 - k.drag * e)
				p.vx, p.vy = p.vx * d, p.vy * d
			end
			p.x, p.y = p.x + p.vx * e, p.y + p.vy * e
			if k.solid and game and p.vy < 0 and p.y < GroundAt(p.x) then f = 1 end
			if f >= 1 then
				p.age = p.life
				p.tex:Hide()
			else
				local s = p.s0 + (p.s1 - p.s0) * f
				p.tex:SetSize(s, s)
				p.tex:SetAlpha(p.a * (1 - f))
				p.tex:SetPoint("CENTER", field, "BOTTOMLEFT", p.x, p.y)
			end
		end
	end
	for _, f in ipairs(floaters) do
		if f.age < 1.2 then
			f.age = f.age + e
			f.fs:SetPoint("BOTTOM", field, "BOTTOMLEFT", f.x, f.y + 20 * f.age)
			f.fs:SetAlpha(max(0, 1 - f.age / 1.2))
			if f.age >= 1.2 then f.fs:Hide() end
		end
	end
end

local function Animate(e)
	AnimateParticles(e)

	local w = game and game.wind or 0
	local speed, len = w == 0 and 6 or w * 8, 3 + abs(w) * 0.8
	for _, p in ipairs(streaks) do
		p.x = p.x + speed * p.f * e
		if p.x > W + 20 then p.x = -20 elseif p.x < -20 then p.x = W + 20 end
		p.tex:SetWidth(len * p.f)
		p.tex:SetPoint("CENTER", field, "BOTTOMLEFT", p.x, p.y)
	end

	if shakeT > 0 then
		shakeT = shakeT - e
		local a = shakeT > 0 and shakeA * shakeT / 0.3 or 0
		field:SetPoint("BOTTOMLEFT", 8 + (random() * 2 - 1) * a, HUDH + 8 + (random() * 2 - 1) * a)
	end

	field.AnimateSky(e, w)
	if not game then marker:Hide() return end
	AnimateTerrain(e)
	AnimateTanks(e)
	AnimateCrates(e)
	AnimateProps()
	frame.AnimatePortals(e)
	AnimateFireworks(e)

	if ann.t > 0 then
		ann.t = ann.t - e
		local age = 1.6 - ann.t
		ann:SetAlpha(min(1, age / 0.15, max(0, ann.t) / 0.4))
		ann:SetScale(1 + 0.25 * max(0, 1 - age / 0.2))
		if ann.t <= 0 then ann:Hide() end
	end

	if game.targeting then
		local col = CursorCol()
		local ok = ValidTeleport(game.tanks[game.cur], col)
		ghost:SetPoint("BOTTOM", field, "BOTTOMLEFT", (col - 0.5) * COLW, hv[col] + 4 + sin(GetTime() * 8) * 2)
		ghost:SetVertexColor(ok and 0.4 or 1, ok and 1 or 0.3, ok and 0.6 or 0.3)
		ghost:Show()
	end

	-- Victory: short pause so the final blast reads, then banner, fireworks and scores.
	-- A tank falling out of the map holds it until it drops out of the window, then it plays at once.
	local falling
	for k, fv in ipairs(vis) do
		local tk = game.tanks[k]
		if (fv.fall and not fv.fall.out) or (fv.alive and tk and tk.fell) then falling = true end
	end
	if game.over and not falling then
		game.overT = game.overT or (GetTime() - (game.fellOut and 0.8 or 0))
		local t = GetTime() - game.overT - 0.8
		if t >= 0 then
			if not banner:IsShown() then ShowBanner() end
			AnimateBanner(t, e)
			if t > 1.5 and not sb:IsShown() then DrawScores() end
		end
	end

	local v = vis[game.cur]
	if game.over or game.shot or not v.x then
		marker:Hide()
	else
		marker:SetPoint("BOTTOM", field, "BOTTOMLEFT", v.x, v.y + 42 + sin(GetTime() * 6) * 2)
		marker:Show()
	end
end

local trailT = 0

-- Per-frame work only runs while a match exists (StartGame shows the ticker); idle costs nothing.
-- Visuals are skipped while the window is hidden; the sim and timers keep going.
frame.ticker = CreateFrame("Frame")
frame.ticker:Hide()
frame.ticker:SetScript("OnUpdate", function(self, elapsed)
	if not game then self:Hide() return end
	if frame:IsShown() then Animate(elapsed) end

	-- Driving that arrived while our copy of the shot was still in the air
	if game.queue and not (game.shot or game.landed) then
		local q = game.queue
		game.queue = nil
		for _, m in ipairs(q) do
			if game then OnMessage(m[1], m[2]) end
		end
		if not game then return end
	end
	frame.Drive(elapsed)
	if not game then return end
	frame.Jet(elapsed)
	frame.AI(elapsed)
	if not game then return end

	-- Shop timer: the host calls time for anyone whose cart never arrived
	if game.shopping then
		local left = game.shopping.ends - GetTime()
		if left <= -GRACE and game.host == Me() and not game.solo and not game.shopping.called then
			game.shopping.called = true
			Send("SHOPEND")
		end
		if ceil(left) ~= game.sec then
			game.sec = ceil(left)
			DrawStatus()
		end
	-- Drive-away window after the shot: the shooter ends it with DONE; the host steps in if that never comes
	elseif game.retreat then
		local left = game.retreat - GetTime()
		if IsMine(game.tanks[game.cur]) then
			if left <= 0 then
				frame.FlushDrive()
				if not game.solo then Send("DONE", game.turn) end
				EndTurn()
			end
		elseif GetTime() > game.retreatT + 5 + GRACE + 1 and game.host == Me() then
			Send("SKIP", game.turn)
			Skip()
		end
		if game.retreat and ceil(max(0, left)) ~= game.sec then
			game.sec = ceil(max(0, left))
			DrawStatus()
		end
	-- Turn timer: solo skips locally, otherwise only the host sends SKIP
	elseif not (game.over or game.shot or game.landed) then
		local left = TimeLeft()
		if left <= 0 and game.solo then
			Skip()
		elseif left <= -GRACE and game.host == Me() then
			Send("SKIP", game.turn)
			Skip()
		end
		local sec = ceil(left)
		if sec ~= game.sec and not game.over then
			game.sec = sec
			DrawStatus()
		end
	end

	local shot = game.shot
	if shot then
		shot.acc = shot.acc + min(elapsed, 0.25)
		while shot.acc >= STEP do
			shot.acc = shot.acc - STEP
			if StepShot(shot) then Landed() return end
		end
		if not frame:IsShown() then return end
		trailT = trailT + elapsed
		local push = trailT >= 0.03
		if push then trailT = 0 end
		for i, sv in ipairs(shellVis) do
			local s = shot.shells[i]
			sv.halo:SetShown(s ~= nil)
			sv.body:SetShown(s ~= nil and not s.blob)
			if s then
				-- Napalm blobs are just a hot glow with a flame trail
				sv.halo:SetSize(s.blob and 12 or 14, s.blob and 12 or 14)
				sv.halo:SetVertexColor(1, s.blob and 0.45 or 0.7, s.blob and 0.1 or 0.3)
				sv.halo:SetPoint("CENTER", field, "BOTTOMLEFT", s.x, s.y)
				sv.body:SetPoint("CENTER", field, "BOTTOMLEFT", s.x, s.y + (s.roll and 3 or 0))
				sv.body:SetRotation(s.roll and -s.x / 3 or atan2(s.vy, s.vx))
				if s.bounced then
					s.bounced = nil
					Dust(s.x, s.y, 4)
				end
				field.Bore(s)
				if push and s.blob then
					Particle("flame", s.x, s.y, random(-5, 5), random(0, 10), 0.35, 6, 2, 0.8)
				elseif push then
					Particle("smoke", s.x, s.y, 0, 0, 0.9, 3, 10, 0.35)
					Particle("ember", s.x, s.y, random(-15, 15), random(-5, 20), 0.25, 3, 1, 0.8)
				end
			end
		end
	elseif frame:IsShown() and CanAim() and not game.targeting then
		local da = ((held.LEFT and 1 or 0) - (held.RIGHT and 1 or 0)) * 60 * elapsed
		local dp = ((held.UP and 1 or 0) - (held.DOWN and 1 or 0)) * 40 * elapsed
		if da ~= 0 or dp ~= 0 then
			local t = game.tanks[game.cur]
			t.angle = min(180, max(0, t.angle + da))
			t.power = min(100, max(1, t.power + dp))
			DrawStatus()
		end
	end
end)

SLASH_GOBLINSHELLSHOCK1 = "/shellshock"
SLASH_GOBLINSHELLSHOCK2 = "/gs"
SlashCmdList.GOBLINSHELLSHOCK = function(msg)
	msg = strtrim(msg:lower())
	if msg == "quit" then
		frame.Quit()
		return
	end
	if InCombatLockdown() then Print("Not available in combat.") return end
	if msg == "version" or msg == "ver" then
		if not IsInGroup() then Print("You have v" .. VERSION .. ". Join a group to check theirs.") return end
		if lobbyFrame.versions then return end -- already asking
		-- Everyone with the addon answers; after 3s list the group by version
		lobbyFrame.versions = { [Me()] = VERSION }
		Send("VQ")
		C_Timer.After(3, function()
			local seen, by, none = lobbyFrame.versions, {}, {}
			lobbyFrame.versions = nil
			local raid, n = IsInRaid(), GetNumGroupMembers()
			for i = 1, n do
				local unit = raid and ("raid" .. i) or (i == 1 and "player" or ("party" .. (i - 1)))
				local nm, realm = UnitFullName(unit) -- realm comes back without spaces, like addon senders
				if nm then
					local name = nm .. "-" .. ((realm and realm ~= "") and realm or GetNormalizedRealmName())
					local v = seen[name]
					if v then
						by[v] = by[v] or {}
						tinsert(by[v], Short(name))
					else
						tinsert(none, Short(name))
					end
				end
			end
			Print("Version check (you have v" .. VERSION .. "):")
			for v, names in pairs(by) do
				print(("  %sv%s|r: %s"):format(v == VERSION and "|cff40ff40" or "|cffffd040", v, table.concat(names, ", ")))
			end
			if #none > 0 then print("  |cff808080No addon (or too old to answer)|r: " .. table.concat(none, ", ")) end
		end)
	elseif msg == "solo" then
		SoloLobby()
	elseif msg == "start" then
		HostStart()
	elseif msg == "toast" then
		ShowToast("Drag this popup where you want it. /gs toast reset puts it back.", "Done")
	elseif msg:match("^scale") then
		local s = tonumber(msg:match("^scale%s+(%S+)")) or 1
		frame.SetGameScale(s)
		Print(("Window scale %d%%."):format(frame:GetScale() * 100 + 0.5))
	elseif msg == "toast reset" then
		GoblinShellshockDB.toast = nil
		PlaceToast()
		Print("Popup position reset.")
	elseif game then
		frame:SetShown(not frame:IsShown())
	elseif lobby and lobby.host ~= Me() and not lobby.solo and joining ~= lobby.host
		and not InRoster(lobby.players, Me()) then
		-- Someone else's lobby we never joined (the popup was closed): offer the Join popup again
		local host = lobby.host
		frame.forceJoin = true
		OnMessage("HELLO:" .. VERSION, host)
		frame.forceJoin = nil
		toast.text:SetText(Short(host) .. " has a lobby open. Want to join?")
	elseif lobby then
		ShowLobby()
	elseif not IsInGroup() then
		Print("Not in a party or raid.")
	elseif not lobbyFrame.scanning then
		-- Ask the group's host (if any) to tell us about their lobby or match
		lobbyFrame.scanning = true
		Send("SCAN")
		C_Timer.After(2, function()
			if lobbyFrame.scanning then
				lobbyFrame.scanning = nil
				Print("No lobby open in your group.")
			end
		end)
	end
end

-- Minimap button (LibDBIcon). Left-click does what /gs does: finds the group's lobby or match, or
-- opens yours. Right-click hosts one (a solo lobby outside a group). Shift-right-click hides it.
-- The icon switches to a burning one while a lobby or match is up in the group.
function frame.InitMinimap()
	local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
	local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
	if not (LDB and DBIcon) then return end
	local db = GoblinShellshockDB
	db.minimap = db.minimap or { hide = false }
	-- What's up in the group, if anything (solo test lobbies and matches don't count)
	local function Busy()
		if lobby and not lobby.solo then
			return lobby.host == Me() and "Your lobby is open." or (Short(lobby.host) .. "'s lobby is open.")
		elseif game and not game.solo and not game.over then
			return game.host == Me() and "Your match is running." or (Short(game.host) .. "'s match is running.")
		end
		local h = OtherHost()
		if h then return Short(h) .. " has a lobby or match up." end
	end
	local obj = LDB:NewDataObject("GoblinShellshock", {
		type = "launcher",
		label = "Goblin Shellshock",
		icon = MEDIA .. "icon",
		OnClick = function(_, btn)
			if btn == "RightButton" and IsShiftKeyDown() then
				frame.SetMinimap(false)
				Print("Minimap button hidden. Turn it back on under Options > AddOns > Goblin Shellshock.")
			elseif btn == "RightButton" then
				if InCombatLockdown() then Print("Not available in combat.") return end
				if IsInGroup() then HostStart() else SoloLobby() end
			else
				SlashCmdList.GOBLINSHELLSHOCK("")
			end
		end,
		OnTooltipShow = function(tt)
			tt:AddLine("Goblin Shellshock", GOLD[1], GOLD[2], GOLD[3])
			local busy = Busy()
			if busy then tt:AddLine(busy, 1, 0.55, 0.3) end
			tt:AddLine("Left-click: find your group's game, or open yours", 1, 1, 1)
			tt:AddLine("Right-click: host a game (solo outside a group)", 1, 1, 1)
			tt:AddLine("Shift-right-click: hide this button", 0.6, 0.6, 0.6)
		end,
	})
	DBIcon:Register("GoblinShellshock", obj, db.minimap)
	function frame.SetMinimap(on)
		db.minimap.hide = not on
		if on then DBIcon:Show("GoblinShellshock") else DBIcon:Hide("GoblinShellshock") end
		if frame.options and frame.options.mmCheck then frame.options.mmCheck:SetChecked(on) end
	end
	-- Polled, so it also catches a host leaving the group or going offline
	C_Timer.NewTicker(1, function()
		local icon = MEDIA .. (Busy() and "icon_live" or "icon")
		if obj.icon ~= icon then obj.icon = icon end
	end)
end

-- Options and the command list under Options > AddOns. Built the first time the page opens.
if Settings and Settings.RegisterCanvasLayoutCategory then
	frame.options = CreateFrame("Frame")
	frame.options:SetScript("OnShow", function(self)
		self:SetScript("OnShow", nil)
		local title = self:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		title:SetPoint("TOPLEFT", 16, -16)
		title:SetText("Goblin Shellshock v" .. VERSION)
		local function Check(y, label, get, set)
			local cb = CreateFrame("CheckButton", nil, self, "UICheckButtonTemplate")
			cb:SetPoint("TOPLEFT", 12, y)
			cb:SetChecked(get())
			cb:SetScript("OnClick", function(b) set(b:GetChecked() and true or false) end)
			local fs = self:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
			fs:SetText(label)
			return cb
		end
		Check(-44, "Pop up when someone in your group opens a lobby (/gs still finds it when off)",
			function() return GoblinShellshockDB.joinPopups ~= false end,
			function(on) GoblinShellshockDB.joinPopups = on end)
		self.mmCheck = Check(-72, "Show the minimap button",
			function() return not (GoblinShellshockDB.minimap and GoblinShellshockDB.minimap.hide) end,
			function(on) if frame.SetMinimap then frame.SetMinimap(on) end end)
		local cmds = {
			{ "/gs", "In a party or raid: find the group's lobby or match. Opens the window if you're already in one." },
			{ "/gs start", "Open a lobby for your group." },
			{ "/gs solo", "Open a solo lobby to try things out with hotseat tanks." },
			{ "/gs version", "List which version everyone in your group has." },
			{ "/gs quit","Leave the lobby or match. If you host a running match, it ends for everyone." },
			{ "/gs scale 0.75-2", "Resize the game window." },
			{ "/gs toast", "Show the popup so you can drag it where you want it." },
			{ "/gs toast reset", "Put the popup back in its default spot." },
		}
		local y = -116
		for _, c in ipairs(cmds) do
			local cmd = self:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			cmd:SetPoint("TOPLEFT", 16, y)
			cmd:SetText(c[1])
			cmd:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
			local desc = self:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			desc:SetPoint("TOPLEFT", 160, y)
			desc:SetPoint("RIGHT", -16, 0)
			desc:SetJustifyH("LEFT")
			desc:SetText(c[2])
			y = y - max(cmd:GetStringHeight(), desc:GetStringHeight()) - 10
		end
		local alias = self:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		alias:SetPoint("TOPLEFT", 16, y - 6)
		alias:SetText("/shellshock works anywhere /gs does.")
	end)
	Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(frame.options, "Goblin Shellshock"))
end
