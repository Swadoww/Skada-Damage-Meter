local folder, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale(folder)

local GetAddOnMetadata = GetAddOnMetadata
ns.version = GetAddOnMetadata(folder, "Version")
ns.website = GetAddOnMetadata(folder, "X-Website")
ns.discord = GetAddOnMetadata(folder, "X-Discord")
ns.logo = [[Interface\ICONS\spell_lightning_lightningbolt01]]
ns.revisited = true -- Skada-Revisited flag

-- holds private stuff
local Private = ns.Private or {}
ns.Private = Private

-- cache frequently used globals
local pairs, ipairs = pairs, ipairs
local select, next, max = select, next, math.max
local band, tonumber, type = bit.band, tonumber, type
local format, strmatch, gsub = string.format, string.match, string.gsub
local setmetatable = setmetatable
local EmptyFunc = Multibar_EmptyFunc
local _

-- common weak table
Private.weaktable = {__mode = "kv"}

-------------------------------------------------------------------------------
-- flags/bitmasks

do
	-- self-affilation
	local BITMASK_MINE = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x00000001
	Private.BITMASK_MINE = BITMASK_MINE

	-- party/raid affiliation
	local BITMASK_PARTY = COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x00000002
	local BITMASK_RAID = COMBATLOG_OBJECT_AFFILIATION_RAID or 0x00000004
	Private.BITMASK_GROUP = BITMASK_MINE + BITMASK_PARTY + BITMASK_RAID

	-- pets and guardians
	local BITMASK_TYPE_PET = COMBATLOG_OBJECT_TYPE_PET or 0x00001000
	local BITMASK_TYPE_GUARDIAN = COMBATLOG_OBJECT_TYPE_GUARDIAN or 0x00002000
	Private.BITMASK_PETS = BITMASK_TYPE_PET + BITMASK_TYPE_GUARDIAN

	-- friendly and hostile units
	Private.BITMASK_FRIENDLY = COMBATLOG_OBJECT_REACTION_FRIENDLY or 0x00000010
	Private.BITMASK_HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040
end

-------------------------------------------------------------------------------
-- class, roles ans specs registration

function Private.register_classes()
	Private.register_classes = nil

	-- class, role and spec icons (sprite)
	ns.classicons = [[Interface\AddOns\Skada\Media\Textures\icons]]
	ns.roleicons = ns.classicons
	ns.specicons = ns.classicons

	-- class colors/names and valid classes
	local classcolors, validclass = {}, {}
	for class, info in pairs(CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS) do
		classcolors[class] = {r = info.r, g = info.g, b = info.b, colorStr = info.colorStr}
		classcolors[class].colorStr = classcolors[class].colorStr or Private.RGBPercToHex(info.r, info.g, info.b, true)
		L[class] = LOCALIZED_CLASS_NAMES_MALE[class]
		validclass[class] = true
	end
	ns.validclass = validclass -- used to validate classes

	-- custom class colors
	classcolors.BOSS = {r = 0.203, g = 0.345, b = 0.525, colorStr = "ff345886"}
	classcolors.ENEMY = {r = 0.94117, g = 0, b = 0.0196, colorStr = "fff00005"}
	classcolors.MONSTER = {r = 0.549, g = 0.388, b = 0.404, colorStr = "ff8c6367"}
	classcolors.PET = {r = 0.3, g = 0.4, b = 0.5, colorStr = "ff4c0566"}
	classcolors.PLAYER = {r = 0.94117, g = 0, b = 0.0196, colorStr = "fff00005"}
	classcolors.ARENA_GOLD = {r = 1, g = 0.82, b = 0, colorStr = "ffffd100"}
	classcolors.ARENA_GREEN = {r = 0.1, g = 1, b = 0.1, colorStr = "ff19ff19"}

	local P = ns.db.profile

	-- returns class color or "arg" wrapped in class color
	local classcolors_mt = {
		__index = function(t, class)
			local color = {r = 0.353, g = 0.067, b = 0.027, colorStr = "ff5a1107"} -- unknown
			t[class] = color
			return color
		end,
		__call = function(t, class, arg)
			local color = P.usecustomcolors and P.customcolors and P.customcolors[class] or t[class]
			if not color.colorStr then
				color.colorStr = Private.RGBPercToHex(color.r, color.g, color.b, true)
			end
			return (arg == nil) and color or (type(arg) == "string") and format("\124c%s%s\124r", color.colorStr, arg) or color.colorStr
		end
	}
	ns.classcolors = setmetatable(classcolors, classcolors_mt)

	-- common __call for coordinates
	local coords__call = function(t, key)
		local coords = t[key]
		return coords[1], coords[2], coords[3], coords[4]
	end

	-- class icons and coordinates
	local classcoords_mt = {
		__index = function(t, class)
			local coords = {384/512, 448/512, 64/512, 128/512} -- unknown
			t[class] = coords
			return coords
		end,
		__call = coords__call
	}
	ns.classcoords = setmetatable({
		-- default classes
		DEATHKNIGHT = {64/512, 128/512, 128/512, 192/512},
		DEMONHUNTER = {192/512, 256/512, 128/512, 192/512},
		DRUID = {192/512, 256/512, 0/512, 64/512},
		HUNTER = {0/512, 64/512, 64/512, 128/512},
		MAGE = {64/512, 128/512, 0/512, 64/512},
		MONK = {128/512, 192/512, 128/512, 192/512},
		PALADIN = {0/512, 64/512, 128/512, 192/512},
		PRIEST = {128/512, 192/512, 64/512, 128/512},
		ROGUE = {128/512, 192/512, 0/512, 64/512},
		SHAMAN = {64/512, 128/512, 64/512, 128/512},
		WARLOCK = {192/512, 256/512, 64/512, 128/512},
		WARRIOR = {0/512, 64/512, 0/512, 64/512},
		-- custom classes
		BOSS = {320/512, 384/512, 0/512, 64/512},
		ENEMY = {448/512, 512/512, 0/512, 64/512},
		MONSTER = {384/512, 448/512, 0/512, 64/512},
		PET = {320/512, 384/512, 64/512, 128/512},
		PLAYER = {448/512, 512/512, 64/512, 128/512}
	}, classcoords_mt)

	-- role icons and coordinates
	local rolecoords_mt = {
		__index = function(t, role)
			local coords = {480/512, 512/512, 128/512, 160/512}
			t[role] = coords
			return coords
		end,
		__call = coords__call
	}
	ns.rolecoords = setmetatable({
		DAMAGER = {480/512, 512/512, 128/512, 160/512},
		HEALER = {480/512, 512/512, 160/512, 192/512},
		LEADER = {448/512, 480/512, 128/512, 160/512},
		TANK = {448/512, 480/512, 160/512, 192/512}
	}, rolecoords_mt)

	-- spec icons and coordinates
	local speccoords_mt = {__call = coords__call}
	ns.speccoords = setmetatable({
		[62] = {192/512, 256/512, 192/512, 256/512}, --> Mage: Arcane
		[63] = {256/512, 320/512, 192/512, 256/512}, --> Mage: Fire
		[64] = {320/512, 384/512, 192/512, 256/512}, --> Mage: Frost
		[65] = {64/512, 128/512, 384/512, 448/512}, --> Paladin: Holy
		[66] = {128/512, 192/512, 384/512, 448/512}, --> Paladin: Protection
		[70] = {192/512, 256/512, 384/512, 448/512}, --> Paladin: Retribution
		[71] = {0/512, 64/512, 192/512, 256/512}, --> Warrior: Arms
		[72] = {64/512, 128/512, 192/512, 256/512}, --> Warrior: Fury
		[73] = {128/512, 192/512, 192/512, 256/512}, --> Warrior: Protection
		[102] = {64/512, 128/512, 256/512, 320/512}, --> Druid: Balance
		[103] = {128/512, 192/512, 256/512, 320/512}, --> Druid: Feral
		[104] = {192/512, 256/512, 256/512, 320/512}, --> Druid: Guardian
		[105] = {256/512, 320/512, 256/512, 320/512}, --> Druid: Restoration
		[250] = {256/512, 320/512, 384/512, 448/512}, --> Death Knight: Blood
		[251] = {320/512, 384/512, 384/512, 448/512}, --> Death Knight: Frost
		[252] = {384/512, 448/512, 384/512, 448/512}, --> Death Knight: Unholy
		[253] = {320/512, 384/512, 256/512, 320/512}, --> Hunter: Beastmastery
		[254] = {384/512, 448/512, 256/512, 320/512}, --> Hunter: Marksmalship
		[255] = {448/512, 512/512, 256/512, 320/512}, --> Hunter: Survival
		[256] = {192/512, 256/512, 320/512, 384/512}, --> Priest: Discipline
		[257] = {256/512, 320/512, 320/512, 384/512}, --> Priest: Holy
		[258] = {320/512, 384/512, 320/512, 384/512}, --> Priest: Shadow
		[259] = {384/512, 448/512, 192/512, 256/512}, --> Rogue: Assassination
		[260] = {448/512, 512/512, 192/512, 256/512}, --> Rogue: Combat
		[261] = {0/512, 64/512, 256/512, 320/512}, --> Rogue: Subtlty
		[262] = {0/512, 64/512, 320/512, 384/512}, --> Shaman: Elemental
		[263] = {64/512, 128/512, 320/512, 384/512}, --> Shaman: Enhancement
		[264] = {128/512, 192/512, 320/512, 384/512}, --> Shaman: Restoration
		[265] = {384/512, 448/512, 320/512, 384/512}, --> Warlock: Affliction
		[266] = {448/512, 512/512, 320/512, 384/512}, --> Warlock: Demonology
		[267] = {0/512, 64/512, 384/512, 448/512}, --> Warlock: Destruction
		[268] = {448/512, 512/512, 384/512, 448/512}, --> Monk: Brewmaster
		[269] = {64/512, 128/512, 448/512, 512/512}, --> Monk: Windwalker
		[270] = {0/512, 64/512, 448/512, 512/512}, --> Monk: Mistweaver
		[577] = {128/512, 192/512, 448/512, 512/512}, --> Demon Hunter: Havoc
		[581] = {192/512, 256/512, 448/512, 512/512} --> Demon Hunter: Vengeance
	}, speccoords_mt)

	--------------------------
	-- custom class options --
	--------------------------

	local function no_custom()
		return not P.usecustomcolors
	end

	local colorsOpt = {
		type = "group",
		name = L["Colors"],
		desc = format(L["Options for %s."], L["Colors"]),
		order = 1000,
		get = function(i)
			local color = classcolors[i[#i]]
			if P.customcolors and P.customcolors[i[#i]] then
				color = P.customcolors[i[#i]]
			end
			return color.r, color.g, color.b
		end,
		set = function(i, r, g, b)
			local class = i[#i]
			P.customcolors = P.customcolors or {}
			P.customcolors[class] = P.customcolors[class] or {}
			P.customcolors[class].r = r
			P.customcolors[class].g = g
			P.customcolors[class].b = b
			P.customcolors[class].colorStr = Private.RGBPercToHex(r, g, b, true)
		end,
		args = {
			enable = {
				type = "toggle",
				name = L["Enable"],
				width = "double",
				order = 10,
				get = function()
					return P.usecustomcolors
				end,
				set = function(_, val)
					if val then
						P.usecustomcolors = true
					else
						P.usecustomcolors = nil
						P.customcolors = nil -- free it
					end
				end
			},
			class = {
				type = "group",
				name = L["Class Colors"],
				order = 20,
				hidden = no_custom,
				disabled = no_custom,
				args = {}
			},
			custom = {
				type = "group",
				name = L["Custom Colors"],
				order = 30,
				hidden = no_custom,
				disabled = no_custom,
				args = {}
			},
			reset = {
				type = "execute",
				name = L["Reset"],
				width = "double",
				order = 90,
				disabled = no_custom,
				confirm = function() return L["Are you sure you want to reset all colors?"] end,
				func = function()
					P.customcolors = wipe(P.customcolors or {})
				end
			}
		}
	}

	for class, data in pairs(classcolors) do
		if validclass[class] then
			colorsOpt.args.class.args[class] = {
				type = "color",
				name = L[class],
				desc = format(L["Color for %s."], L[class])
			}
		else
			colorsOpt.args.custom.args[class] = {
				type = "color",
				name = L[class],
				desc = format(L["Color for %s."], L[class])
			}
		end
	end

	ns.options.args.tweaks.args.advanced.args.colors = colorsOpt
end

-------------------------------------------------------------------------------
-- spell schools registration

function Private.register_schools()
	Private.register_schools = nil

	local spellschools = {}

	-- handles adding spell schools
	local order = {}
	local function add_school(key, name, r, g, b)
		if key and name and not spellschools[key] then
			spellschools[key] = {r = r or 1, g = g or 1, b = b or 1, name = strmatch(name, "%((.+)%)") or name}
			order[#order + 1] = key
		end
	end

	-- main school
	local SCHOOL_NONE = SCHOOL_MASK_NONE or 0x00 -- None
	local SCHOOL_PHYSICAL = SCHOOL_MASK_PHYSICAL or 0x01 -- Physical
	local SCHOOL_HOLY = SCHOOL_MASK_HOLY or 0x02 -- Holy
	local SCHOOL_FIRE = SCHOOL_MASK_FIRE or 0x04 -- Fire
	local SCHOOL_NATURE = SCHOOL_MASK_NATURE or 0x08 -- Nature
	local SCHOOL_FROST = SCHOOL_MASK_FROST or 0x10 -- Frost
	local SCHOOL_SHADOW = SCHOOL_MASK_SHADOW or 0x20 -- Shadow
	local SCHOOL_ARCANE = SCHOOL_MASK_ARCANE or 0x40 -- Arcane

	-- Single Schools
	add_school(SCHOOL_NONE, STRING_SCHOOL_UNKNOWN, 1, 1, 1) -- Unknown
	add_school(SCHOOL_PHYSICAL, STRING_SCHOOL_PHYSICAL, 1, 1, 0) -- Physical
	add_school(SCHOOL_HOLY, STRING_SCHOOL_HOLY, 1, 0.9, 0.5) -- Holy
	add_school(SCHOOL_FIRE, STRING_SCHOOL_FIRE, 1, 0.5, 0) -- Fire
	add_school(SCHOOL_NATURE, STRING_SCHOOL_NATURE, 0.3, 1, 0.3) -- Nature
	add_school(SCHOOL_FROST, STRING_SCHOOL_FROST, 0.5, 1, 1) -- Frost
	add_school(SCHOOL_SHADOW, STRING_SCHOOL_SHADOW, 0.5, 0.5, 1) -- Shadow
	add_school(SCHOOL_ARCANE, STRING_SCHOOL_ARCANE, 1, 0.5, 1) -- Arcane

	-- reference to CombatLog_String_SchoolString
	local colorFunc = CombatLog_Color_ColorArrayBySchool
	local function get_school_name(key)
		if not nameFunc then -- late availability
			nameFunc = CombatLog_String_SchoolString
		end

		local name = nameFunc(key)
		local isnone = (name == STRING_SCHOOL_UNKNOWN)
		return strmatch(name, "%((.+)%)") or name, isnone
	end

	-- reference to COMBATLOG_DEFAULT_COLORS.schoolColoring
	local colorTable = COMBATLOG_DEFAULT_COLORS and COMBATLOG_DEFAULT_COLORS.schoolColoring
	local function get_school_color(key)
		if not colorTable then -- late availability
			colorTable = COMBATLOG_DEFAULT_COLORS and COMBATLOG_DEFAULT_COLORS.schoolColoring
		end

		local r, g, b = 1.0, 1.0, 1.0

		if colorTable and colorTable[key] then
			r = colorTable[key].r or r
			g = colorTable[key].g or g
			b = colorTable[key].b or b
		elseif colorTable then
			for i = #order, 1, -1 do
				local k = order[i]
				if band(key, k) == k then
					r = colorTable[k].r or r
					g = colorTable[k].g or g
					b = colorTable[k].b or b
					break
				end
			end
		end

		return r, g, b
	end

	ns.spellschools = setmetatable(spellschools, {
		__index = function(t, key)
			local name, isnone = get_school_name(key)
			if not isnone then
				local r, g, b = get_school_color(key)
				t[key] = {name = name, r = r, g = g, b = b}
				return t[key]
			end
			return t[0x00] -- unknown
		end,
		__call = function(t, key)
			local school = t[key]
			return school.name, school.r, school.g, school.b
		end
	})
end

-------------------------------------------------------------------------------
-- register LibSharedMedia stuff

function Private.register_medias()
	Private.register_medias = nil

	local LSM = LibStub("LibSharedMedia-3.0", true)
	if not LSM then
		ns.MediaFetch = EmptyFunc
		ns.MediaList = EmptyFunc
		return
	end

	-- fonts
	LSM:Register("font", "ABF", [[Interface\Addons\Skada\Media\Fonts\ABF.ttf]])
	LSM:Register("font", "Accidental Presidency", [[Interface\Addons\Skada\Media\Fonts\Accidental Presidency.ttf]])
	LSM:Register("font", "Adventure", [[Interface\Addons\Skada\Media\Fonts\Adventure.ttf]])
	LSM:Register("font", "Diablo", [[Interface\Addons\Skada\Media\Fonts\Diablo.ttf]])
	LSM:Register("font", "FORCED SQUARE", [[Interface\Addons\Skada\Media\Fonts\FORCED SQUARE.ttf]])
	LSM:Register("font", "Hooge", [[Interface\Addons\Skada\Media\Fonts\Hooge.ttf]])

	-- statusbars
	LSM:Register("statusbar", "Aluminium", [[Interface\Addons\Skada\Media\Statusbar\Aluminium]])
	LSM:Register("statusbar", "Armory", [[Interface\Addons\Skada\Media\Statusbar\Armory]])
	LSM:Register("statusbar", "BantoBar", [[Interface\Addons\Skada\Media\Statusbar\BantoBar]])
	LSM:Register("statusbar", "Flat", [[Interface\Addons\Skada\Media\Statusbar\Flat]])
	LSM:Register("statusbar", "Gloss", [[Interface\Addons\Skada\Media\Statusbar\Gloss]])
	LSM:Register("statusbar", "Graphite", [[Interface\Addons\Skada\Media\Statusbar\Graphite]])
	LSM:Register("statusbar", "Grid", [[Interface\Addons\Skada\Media\Statusbar\Grid]])
	LSM:Register("statusbar", "Healbot", [[Interface\Addons\Skada\Media\Statusbar\Healbot]])
	LSM:Register("statusbar", "LiteStep", [[Interface\Addons\Skada\Media\Statusbar\LiteStep]])
	LSM:Register("statusbar", "Minimalist", [[Interface\Addons\Skada\Media\Statusbar\Minimalist]])
	LSM:Register("statusbar", "Otravi", [[Interface\Addons\Skada\Media\Statusbar\Otravi]])
	LSM:Register("statusbar", "Outline", [[Interface\Addons\Skada\Media\Statusbar\Outline]])
	LSM:Register("statusbar", "Round", [[Interface\Addons\Skada\Media\Statusbar\Round]])
	LSM:Register("statusbar", "Serenity", [[Interface\AddOns\Skada\Media\Statusbar\Serenity]])
	LSM:Register("statusbar", "Smooth", [[Interface\Addons\Skada\Media\Statusbar\Smooth]])
	LSM:Register("statusbar", "Solid", [[Interface\Buttons\WHITE8X8]])
	LSM:Register("statusbar", "TukTex", [[Interface\Addons\Skada\Media\Statusbar\TukTex]])

	-- borders
	LSM:Register("border", "Glow", [[Interface\Addons\Skada\Media\Border\Glow]])
	LSM:Register("border", "Roth", [[Interface\Addons\Skada\Media\Border\Roth]])

	-- sounds
	LSM:Register("sound", "Cartoon FX", [[Sound\Doodad\Goblin_Lottery_Open03.wav]])
	LSM:Register("sound", "Cheer", [[Sound\Event Sounds\OgreEventCheerUnique.wav]])
	LSM:Register("sound", "Explosion", [[Sound\Doodad\Hellfire_Raid_FX_Explosion05.wav]])
	LSM:Register("sound", "Fel Nova", [[Sound\Spells\SeepingGaseous_Fel_Nova.wav]])
	LSM:Register("sound", "Fel Portal", [[Sound\Spells\Sunwell_Fel_PortalStand.wav]])
	LSM:Register("sound", "Humm", [[Sound\Spells\SimonGame_Visual_GameStart.wav]])
	LSM:Register("sound", "Rubber Ducky", [[Sound\Doodad\Goblin_Lottery_Open01.wav]])
	LSM:Register("sound", "Shing!", [[Sound\Doodad\PortcullisActive_Closed.wav]])
	LSM:Register("sound", "Short Circuit", [[Sound\Spells\SimonGame_Visual_BadPress.wav]])
	LSM:Register("sound", "Simon Chime", [[Sound\Doodad\SimonGame_LargeBlueTree.wav]])
	LSM:Register("sound", "War Drums", [[Sound\Event Sounds\Event_wardrum_ogre.wav]])
	LSM:Register("sound", "Wham!", [[Sound\Doodad\PVP_Lordaeron_Door_Open.wav]])
	LSM:Register("sound", "You Will Die!", [[Sound\Creature\CThun\CThunYouWillDIe.wav]])

	-- fetches media by type
	ns.MediaFetch = function(self, mediatype, key, default)
		return (key and LSM:Fetch(mediatype, key)) or (default and LSM:Fetch(mediatype, default)) or default
	end

	-- lists media by type
	ns.MediaList = function(self, mediatype)
		return LSM:HashTable(mediatype)
	end
end

-------------------------------------------------------------------------------
-- color manipulation

-- converts RGB colors to HEX.
function Private.RGBPercToHex(r, g, b, prefix)
	r = r and r <= 1 and r >= 0 and r or 0
	g = g and g <= 1 and g >= 0 and g or 0
	b = b and b <= 1 and b >= 0 and b or 0
	return format(prefix and "ff%02x%02x%02x" or "%02x%02x%02x", r * 255, g * 255, b * 255)
end

-- generates a color depending on the given percent
function Private.PercentToRGB(perc, reverse, hex)
	-- clamp first
	perc = min(100, max(0, perc or 0))

	-- start with full red
	local r, g, b = 1, 0, 0

	-- reversed?
	if reverse then
		r, g = 0, 1

		if perc <= 50 then -- increment red channel
			r = r + (perc * 0.02)
		else -- set red to 1 and decrement green channel
			r, g = 1, g - ((perc - 50) * 0.02)
		end
	elseif perc <= 50 then -- increment green channel
		g = g + (perc * 0.02)
	else -- set green to 1 and decrement red channel
		r, g = r - ((perc - 50) * 0.02), 1
	end

	-- return hex? channels will be as of 2nd param.
	if hex then
		return Private.RGBPercToHex(r, g, b, true), r, g, b
	end

	-- return only channels.
	return r, g, b
end

-------------------------------------------------------------------------------
-- table functions

-- alternative to table.remove
local error = error
local tremove = table.remove
function Private.tremove(t, index)
	if index then
		return tremove(t, index)
	elseif type(t) ~= "table" then
		error("bad argument #1 to 'tremove' (table expected, got number)")
	end

	local n = #t
	local val = t[n]
	t[n] = nil
	return val
end

-- returns the length of the given table
function Private.tLength(t)
	local len = 0
	if t then
		for _ in pairs(t) do
			len = len + 1
		end
	end
	return len
end

-- copies a table from another
function Private.tCopy(to, from, ...)
	for k, v in pairs(from) do
		local skip = false
		if ... then
			if type(...) == "table" then
				for _, j in ipairs(...) do
					if j == k then
						skip = true
						break
					end
				end
			else
				for i = 1, select("#", ...) do
					if select(i, ...) == k then
						skip = true
						break
					end
				end
			end
		end
		if not skip then
			if type(v) == "table" then
				to[k] = {}
				Private.tCopy(to[k], v, ...)
			else
				to[k] = v
			end
		end
	end
end

-- creates a table pool
function Private.table_pool()
	local pool = {tables = {}, new = true, del = true, clear = true}
	local tables = setmetatable(pool.tables, Private.weaktable)

	-- reuses or creates a table
	pool.new = function()
		local t = next(tables)
		if t then tables[t] = nil end
		return t or {}
	end

	-- deletes a table to be reused later
	pool.del = function(t, deep)
		if type(t) ~= "table" then return end

		for k, v in pairs(t) do
			if deep and type(v) == "table" then
				pool.del(v)
			end
			t[k] = nil
		end

		t[""] = true
		t[""] = nil
		setmetatable(t, nil)
		tables[t] = true

		return nil
	end

	-- clears/wipes the given table
	pool.clear = function(t)
		if type(t) == "table" then
			for k, v in pairs(t) do
				t[k] = pool.del(v, true)
			end
		end
		return t
	end

	return pool
end

-- create addon's default table pool
do
	local _pool = Private.table_pool()
	Private.newTable = _pool.new
	Private.delTable = _pool.del
	Private.clearTable = _pool.clear
end

-- prevents duplicates in a table to format strings
function Private.prevent_duplicate(value, tbl, key)
	local num = 0
	if type(tbl) == "table" then
		local is_array = (#tbl > 0)
		for k, v in pairs(tbl) do
			local val = is_array and v[key] or k
			if val == value and num == 0 then
				num = 1
			elseif val then
				local n, c = strmatch(val, "^(.-)%s*%((%d+)%)$")
				if n == value then
					num = max(num, tonumber(c), 0)
				end
			end
		end
		if num > 0 then
			value = format("%s (%d)", value, num + 1)
		end
	end
	return value
end

-------------------------------------------------------------------------------
-- string functions

do
	-- we a fake frame/fontstring to escape the string
	local escapeFrame = nil
	function Private.EscapeStr(str)
		if not escapeFrame then
			escapeFrame = CreateFrame("Frame")
			escapeFrame.fs = escapeFrame:CreateFontString(nil, "ARTWORK", "ChatFontNormal")
			escapeFrame:Hide()
		end

		escapeFrame.fs:SetText(str)
		str = escapeFrame.fs:GetText()
		escapeFrame.fs:SetText("")
		return str
	end

	local function replace(cap1)
		return cap1 == "%" and UNKNOWN
	end

	local pcall = pcall
	function Private.uformat(fstr, ...)
		local ok, str = pcall(format, fstr, ...)
		return ok and str or gsub(gsub(fstr, "(%%+)([^%%%s<]+)", replace), "%%%%", "%%")
	end

	function Private.WrapTextInColorCode(text, colorHexString)
		return format("\124c%s%s\124r", colorHexString, text)
	end
end

-------------------------------------------------------------------------------
-- Save/Restore frame positions to/from db

do
	local floor = math.floor
	local GetScreenWidth, GetScreenHeight = GetScreenWidth, GetScreenHeight

	function Private.SavePosition(f, db)
		if f and f.GetCenter and db then
			local x, y = f:GetCenter()
			local scale = f:GetEffectiveScale()
			local uscale = UIParent:GetScale()

			db.x = ((x * scale) - (GetScreenWidth() * uscale) * 0.5) / uscale
			db.y = ((y * scale) - (GetScreenHeight() * uscale) * 0.5) / uscale
			db.scale = floor(f:GetScale() * 100) * 0.01
		end
	end

	function Private.RestorePosition(f, db)
		if f and f.SetPoint and db then
			local scale = f:GetEffectiveScale()
			local uscale = UIParent:GetScale()
			local x = (db.x or 0) * uscale / scale
			local y = (db.y or 0) * uscale / scale

			f:ClearAllPoints()
			f:SetPoint("CENTER", UIParent, "CENTER", x, y)
			f:SetScale(db.scale or 1)
		end
	end
end

-------------------------------------------------------------------------------
-- toast and notifications

do
	local LibToast = LibStub("SpecializedLibToast-1.0", true)
	local toast_opt = nil

	-- initialize LibToast
	function Private.register_toast()
		Private.register_toast = nil -- remove it

		if not LibToast then
			ns.Notify = ns.Print
			return
		end

		-- install default options
		local P = ns.db.profile
		P.toast = P.toast or ns.defaults.toast

		LibToast:Register(format("%sToastFrame", folder), function(toast, text, title, icon, urgency)
			toast:SetTitle(title or folder)
			toast:SetText(text or L["A damage meter."])
			toast:SetIconTexture(icon or ns.logo)
			toast:SetUrgencyLevel(urgency or "normal")
		end)
		if P.toast then
			LibToast.config.hide_toasts = P.toast.hide_toasts
			LibToast.config.spawn_point = P.toast.spawn_point or "TOP"
			LibToast.config.duration = P.toast.duration or 7
			LibToast.config.opacity = P.toast.opacity or 0.75
		end

		-- shows notifications or simply uses Print method.
		local toast_name = format("%sToastFrame", folder)
		function ns:Notify(text, title, icon, urgency)
			if not (LibToast and LibToast:Spawn(toast_name, text, title, icon, urgency)) then
				self:Print(text)
			end
		end
	end

	-- returns toast options
	function Private.toast_options()
		Private.toast_options = nil -- remove it

		if not LibToast or toast_opt then
			return toast_opt
		end

		toast_opt = {
			type = "group",
			name = L["Notifications"],
			get = function(i)
				return ns.db.profile.toast[i[#i]] or LibToast.config[i[#i]]
			end,
			set = function(i, val)
				ns.db.profile.toast[i[#i]] = val
				LibToast.config[i[#i]] = val
			end,
			order = 990,
			args = {
				toastdesc = {
					type = "description",
					name = L["opt_toast_desc"],
					fontSize = "medium",
					width = "full",
					order = 0
				},
				empty_1 = {
					type = "description",
					name = " ",
					width = "full",
					order = 1
				},
				hide_toasts = {
					type = "toggle",
					name = L["Disable"],
					order = 10
				},
				spawn_point = {
					type = "select",
					name = L["Position"],
					order = 20,
					values = {
						TOPLEFT = L["Top Left"],
						TOPRIGHT = L["Top Right"],
						BOTTOMLEFT = L["Bottom Left"],
						BOTTOMRIGHT = L["Bottom Right"],
						TOP = L["Top"],
						BOTTOM = L["Bottom"],
						LEFT = L["Left"],
						RIGHT = L["Right"]
					}
				},
				duration = {
					type = "range",
					name = L["Duration"],
					min = 5,
					max = 15,
					step = 1,
					order = 30
				},
				opacity = {
					type = "range",
					name = L["Opacity"],
					min = 0,
					max = 1,
					step = 0.01,
					isPercent = true,
					order = 40
				},
				empty_2 = {
					type = "description",
					name = " ",
					width = "full",
					order = 50
				},
				test = {
					type = "execute",
					name = L["Test Notifications"],
					func = function() Skada:Notify() end,
					disabled = function() return ns.db.profile.toast.hide_toasts end,
					width = "double",
					order = 60
				}
			}
		}

		return toast_opt
	end
end

-------------------------------------------------------------------------------
-- Total segment stuff!

do
	local total_opt = nil

	function Private.total_options()
		Private.total_options = nil -- remove it

		if total_opt then
			return total_opt
		end

		local values = {al = 0x10, rb = 0x01, rt = 0x02, db = 0x04, dt = 0x08}
		local disabled = function()
			return band(ns.db.profile.totalflag, values.al) ~= 0
		end

		total_opt = {
			type = "group",
			name = L["Total Segment"],
			desc = format(L["Options for %s."], L["Total Segment"]),
			order = 970,
			args = {
				collection = {
					type = "group",
					name = L["Data Collection"],
					inline = true,
					order = 10,
					get = function(i)
						return (band(ns.db.profile.totalflag, values[i[#i]]) ~= 0)
					end,
					set = function(i, val)
						local v = values[i[#i]]
						if val and band(ns.db.profile.totalflag, v) == 0 then
							ns.db.profile.totalflag = ns.db.profile.totalflag + v
						elseif not val and band(ns.db.profile.totalflag, v) ~= 0 then
							ns.db.profile.totalflag = ns.db.profile.totalflag - v
						end
					end,
					args = {
						al = {
							type = "toggle",
							name = L["All Segments"],
							desc = L["opt_tweaks_total_all_desc"],
							width = "full",
							order = 10
						},
						rb = {
							type = "toggle",
							name = L["Raid Bosses"],
							desc = format(L["opt_tweaks_total_fmt_desc"], L["Raid Bosses"]),
							order = 20,
							disabled = disabled
						},
						rt = {
							type = "toggle",
							name = L["Raid Trash"],
							desc = format(L["opt_tweaks_total_fmt_desc"], L["Raid Trash"]),
							order = 30,
							disabled = disabled
						},
						db = {
							type = "toggle",
							name = L["Dungeon Bosses"],
							desc = format(L["opt_tweaks_total_fmt_desc"], L["Dungeon Bosses"]),
							order = 40,
							disabled = disabled
						},
						dt = {
							type = "toggle",
							name = L["Dungeon Trash"],
							desc = format(L["opt_tweaks_total_fmt_desc"], L["Dungeon Trash"]),
							order = 50,
							disabled = disabled
						}
					}
				},
				totalidc = {
					type = "toggle",
					name = L["Detailed total segment"],
					desc = L["opt_tweaks_total_full_desc"],
					order = 20
				}
			}
		}

		return total_opt
	end

	function Private.total_noclick(set, mode)
		return (not ns.db.profile.totalidc and set == "total" and type(mode) == "table" and mode.nototal == true)
	end

	local function total_record(set)
		local totalflag = Skada.total and set and ns.db.profile.totalflag

		-- something missing
		if not totalflag then
			return false
		end

		-- raid bosses - 0x01
		if band(totalflag, 0x01) ~= 0 then
			if set.type == "raid" and set.gotboss then
				return true
			end
		end

		-- raid trash - 0x02
		if band(totalflag, 0x02) ~= 0 then
			if set.type == "raid" and not set.gotboss then
				return true
			end
		end

		-- dungeon boss - 0x04
		if band(totalflag, 0x04) ~= 0 then
			if set.type == "party" and set.gotboss then
				return true
			end
		end

		-- dungeon trash - 0x08
		if band(totalflag, 0x08) ~= 0 then
			if set.type == "party" and not set.gotboss then
				return true
			end
		end

		-- any combat - 0x10
		if band(totalflag, 0x10) ~= 0 then
			return true
		end

		-- battlegrouns/arenas or nothing
		return (set.type == "pvp" or set.type == "arena")
	end

	function ns:DispatchSets(func, ...)
		if not self.current or type(func) ~= "function" then return end

		func(self.current, ...) -- record to current
		if total_record(self.current) then -- record to total
			func(self.total, ...)
		end

		-- record to phases
		if not self.tempsets then return end
		for i = 1, #self.tempsets do
			local set = self.tempsets[i]
			if set and not set.stopped then
				func(set, ...)
			end
		end
	end
end

-------------------------------------------------------------------------------
-- creates generic dialog

local dialog_name = format("%sCommonConfirmDialog", folder)
function Private.confirm_dialog(text, accept, cancel, override)
	if type(cancel) == "table" and override == nil then
		override = cancel
		cancel = nil
	end

	local t = wipe(StaticPopupDialogs[dialog_name] or {})
	StaticPopupDialogs[dialog_name] = t

	local dialog, strata
	t.OnAccept = function(self)
		if type(accept) == "function" then
			(accept)(self)
		end
		if dialog and strata then
			dialog:SetFrameStrata(strata)
		end
	end
	t.OnCancel = function(self)
		if type(cancel) == "function" then
			(cancel)(self)
		end
		if dialog and strata then
			dialog:SetFrameStrata(strata)
		end
	end

	t.preferredIndex = STATICPOPUP_NUMDIALOGS
	t.text = text
	t.button1 = ACCEPT
	t.button2 = CANCEL
	t.timeout = 0
	t.whileDead = 1
	t.hideOnEscape = 1

	if type(override) == "table" then
		Private.tCopy(t, override)
	end

	dialog = StaticPopup_Show(dialog_name)
	if dialog then
		strata = dialog:GetFrameStrata()
		dialog:SetFrameStrata("TOOLTIP")
	end
end

-------------------------------------------------------------------------------
-- data serialization

do
	local AS = LibStub("AceSerializer-3.0")
	local LC = LibStub("LibCompress")
	local LD = LibStub("LibDeflate")
	local LL = {level = 9}
	local encodeTable = nil

	local strbyte, strchar = string.byte, string.char
	local lshift, tconcat = bit.lshift, table.concat

	-- only used for backwards compatibility
	local function hex_decode(str)
		str = gsub(gsub(str, "%[.-%]", ""), "[^0123456789ABCDEF]", "")
		if (#str == 0) or (#str % 2 ~= 0) then
			return false, "Invalid Hex string"
		end

		local t, bl, bh = {}
		local i = 1
		repeat
			bl = strbyte(str, i)
			bl = bl >= 65 and bl - 55 or bl - 48
			i = i + 1
			bh = strbyte(str, i)
			bh = bh >= 65 and bh - 55 or bh - 48
			i = i + 1
			t[#t + 1] = strchar(lshift(bh, 4) + bl)
		until i >= #str
		return tconcat(t)
	end

	function Private.serialize(hex, title, ...)
		local result = LD:CompressDeflate(AS:Serialize(...), LL)
		if hex then
			return LD:EncodeForPrint(result)
		end
		return LD:EncodeForWoWChatChannel(result)
	end

	function Private.deserialize(data, hex)
		local result = hex and LD:DecodeForPrint(data) or LD:DecodeForWoWChatChannel(data)
		result = result and LD:DecompressDeflate(result) or nil
		if result then
			return AS:Deserialize(result)
		end

		-- backwards compatibility
		local err
		if hex then
			data, err = hex_decode(data)
		else
			encodeTable = encodeTable or LC:GetAddonEncodeTable()
			data, err = encodeTable:Decode(data), "Error decoding"
		end

		if data then
			data, err = LC:DecompressHuffman(data)
			if data then
				return AS:Deserialize(data)
			end
		end
		return false, err
	end
end

-------------------------------------------------------------------------------
-- custom "GetSpellInfo" and "GetSpellLink"

do
	local GetSpellInfo, GetSpellLink = GetSpellInfo, GetSpellLink
	local customSpells = {
		[3] = {L["Falling"], [[Interface\ICONS\ability_rogue_quickrecovery]]},
		[4] = {L["Drowning"], [[Interface\ICONS\spell_shadow_demonbreath]]},
		[5] = {L["Fatigue"], [[Interface\ICONS\spell_nature_sleep]]},
		[6] = {L["Fire"], [[Interface\ICONS\spell_fire_fire]]},
		[7] = {L["Lava"], [[Interface\ICONS\spell_shaman_lavaflow]]},
		[8] = {L["Slime"], [[Interface\ICONS\inv_misc_slime_01]]}
	}
	local customIcons = {
		[75] = [[Interface\ICONS\inv_weapon_bow_07]], --> Auto Shot
		[6603] = [[Interface\ICONS\inv_sword_04]], --> Melee
		[3026] = [[Interface\ICONS\spell_shadow_soulgem]], --> Use Soulstone
		[54755] = [[Interface\ICONS\inv_glyph_majordruid]], --> Glyph of Rejuvenation
		[56160] = [[Interface\ICONS\inv_glyph_majorpriest]], --> Glyph of Power Word: Shield
		[61607] = [[Interface\ICONS\ability_hunter_rapidkilling]] --> Mark of Blood
	}

	function Private.spell_info(spellid)
		if spellid then
			local res1, res2, res3, res4, res5, res6, res7, res8, res9
			if customSpells[spellid] then
				res1, res3 = customSpells[spellid][1], customSpells[spellid][2]
			else
				res1, res2, res3, res4, res5, res6, res7, res8, res9 = GetSpellInfo(spellid)
				if spellid == 6603 then
					res1 = L["Melee"]
				end
				res3 = customIcons[spellid] or res3
			end
			return res1, res2, res3, res4, res5, res6, res7, res8, res9
		end
	end

	function Private.spell_link(spellid)
		if not customSpells[spellid] then
			return GetSpellLink(spellid)
		end
	end
end

-------------------------------------------------------------------------------
-- creatures, players and pets checkers

do
	local strsub = string.sub
	local UnitIsPlayer = UnitIsPlayer

	-- add extra bitmasks if needed
	local BITMASK_PETS = Private.BITMASK_PETS
	local BITMASK_FRIENDLY = Private.BITMASK_FRIENDLY
	local BITMASK_TYPE_NPC = COMBATLOG_OBJECT_TYPE_NPC or 0x00000800
	Private.BITMASK_TYPE_NPC = BITMASK_TYPE_NPC
	local BITMASK_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400
	Private.BITMASK_TYPE_PLAYER = BITMASK_PLAYER

	-- checks if the given guid/flags are those of a creature.
	function Private.is_creature(guid, flags)
		if tonumber(guid) then
			return (band(strsub(guid, 1, 5), 0x00F) == 3 or band(strsub(guid, 1, 5), 0x00F) == 5)
		end
		if tonumber(flags) then
			return (band(flags, BITMASK_TYPE_NPC) ~= 0)
		end
		return false
	end

	-- tables that will cache info about players and pets
	local players = Private.players or {} -- [guid] = unit
	Private.players = players
	local pets = Private.pets or {} -- [guid] = {id = ownerGUID, name = ownerName}
	Private.pets = pets

	do
		-- tables used to cached results in order to speed up check
		local __t1 = setmetatable({}, Private.weaktable) -- cached players
		local __t2 = setmetatable({}, Private.weaktable) -- cached pets

		-- checks if the guid is a player (extra: helps is_pet)
		function Private.is_player(guid, name, flags)
			-- already cached?
			if __t1[guid] ~= nil then
				return __t1[guid]
			end

			-- group member?
			if players[guid] then
				__t1[guid] = 1
				__t2[guid] = (__t2[guid] == nil) and false or __t2[guid]
				return __t1[guid]
			end

			-- group pet?
			if pets[guid] then
				__t1[guid] = false
				__t2[guid] = __t2[guid] or 1
				return __t1[guid]
			end

			-- player by UnitIsPlayer?
			if name and UnitIsPlayer(name) then
				__t1[guid] = true
				__t2[guid] = (__t2[guid] == nil) and false or __t2[guid]
				return __t1[guid]
			end

			-- player by flgs?
			if tonumber(flags) and band(flags, BITMASK_PLAYER) ~= 0 then
				__t1[guid] = true
				__t2[guid] = (__t2[guid] == nil) and false or __t2[guid]
				return __t1[guid]
			end

			-- just set it to false
			__t1[guid] = false
			return __t1[guid]
		end

		-- checks if the guid is a pet (extra: helps is_player)
		function Private.is_pet(guid, flags)
			-- already cached?
			if __t2[guid] ~= nil then
				return __t2[guid]
			end

			-- just in case
			if players[guid] then
				__t2[guid] = false
				__t1[guid] = 1
				return __t2[guid]
			end

			-- grouped pet?
			if pets[guid] then
				__t2[guid] = 1
				__t1[guid] = false
				return __t2[guid]
			end

			-- ungrouped pet?
			if tonumber(flags) and (band(flags, BITMASK_PETS) ~= 0) then
				__t2[guid] = (band(flags, BITMASK_FRIENDLY) ~= 0) and 1 or true
				__t1[guid] = false
				return __t2[guid]
			end

			__t2[guid] = false
			return __t2[guid]
		end
	end

	do
		local new = Private.newTable
		local del = Private.delTable

		-- adds a pet to the table.
		function Private.assign_pet(ownerGUID, ownerName, petGUID)
			pets[petGUID] = pets[petGUID] or new()
			pets[petGUID].id = ownerGUID
			pets[petGUID].name = ownerName
		end

		-- simply removes the pet from the table.
		function Private.dismiss_pet(petGUID)
			pets[petGUID] = del(pets[petGUID])
		end
	end
end

-------------------------------------------------------------------------------
-- generic import and export window

do
	local AceGUI = nil

	local frame_name = format("%sImportExportFrame", folder)
	local function open_window(title, data, clickfunc)
		AceGUI = AceGUI or LibStub("AceGUI-3.0")
		local frame = AceGUI:Create("Frame")
		frame:SetTitle(L["Import/Export"])
		frame:SetLayout("Flow")
		frame:SetCallback("OnClose", function(widget)
			AceGUI:Release(widget)
			collectgarbage()
		end)
		frame:SetWidth(535)
		frame:SetHeight(350)

		local editbox = AceGUI:Create("MultiLineEditBox")
		editbox.editBox:SetFontObject(GameFontHighlightSmall)
		editbox:SetLabel(title)
		editbox:SetFullWidth(true)
		editbox:SetFullHeight(true)
		frame:AddChild(editbox)

		if type(data) == "function" then
			clickfunc = data
			data = nil
		end

		if data then
			frame:SetStatusText(L["Press CTRL-C to copy the text to your clipboard."])
			editbox:DisableButton(true)
			editbox:SetText(data)
			editbox.editBox:SetFocus()
			editbox.editBox:HighlightText()
			editbox:SetCallback("OnLeave", function(widget)
				widget.editBox:HighlightText()
				widget.editBox:SetFocus()
			end)
			editbox:SetCallback("OnEnter", function(widget)
				widget.editBox:HighlightText()
				widget.editBox:SetFocus()
			end)
		else
			frame:SetStatusText(L["Press CTRL-V to paste the text from your clipboard."])
			editbox:DisableButton(false)
			editbox.editBox:SetFocus()
			editbox.button:SetScript("OnClick", function(widget)
				clickfunc(editbox:GetText())
				AceGUI:Release(frame)
				collectgarbage()
			end)
		end
		-- close on escape
		_G[frame_name] = frame.frame
		UISpecialFrames[#UISpecialFrames + 1] = frame_name
	end

	function Private.open_import_export(title, data, clickfunc)
		return open_window(title, data, clickfunc)
	end
end

-------------------------------------------------------------------------------
-- prototypes and binding functions

do
	local getmetatable = getmetatable

	-- fight/set prototype
	local setPrototype = {}
	ns.setPrototype = setPrototype

	-- common actors prototype
	local actorPrototype = {}
	local actorPrototype_mt = {__index = actorPrototype}
	ns.actorPrototype = actorPrototype

	-- player prototype
	local playerPrototype = setmetatable({}, actorPrototype_mt)
	ns.playerPrototype = playerPrototype

	-- enemy prototype
	local enemyPrototype = setmetatable({}, actorPrototype_mt)
	ns.enemyPrototype = enemyPrototype

	local function bind_set_actors(actors, set)
		if not actors then return end
		for i = 1, #actors do
			local actor = actors[i]
			if actor and actor.enemy then
				enemyPrototype:Bind(actor, set)
			elseif actor and not actor.enemy then
				playerPrototype:Bind(actor, set)
			end
		end
	end

	-- bind a set table to the set prototype
	function setPrototype:Bind(obj)
		if obj and getmetatable(obj) ~= self then
			setmetatable(obj, self)
			self.__index = self
			bind_set_actors(obj.actors, obj)
		end
		self.arena = (ns.forPVP and obj and obj.type == "arena")
		return obj
	end

	-- bind an actor table to the prototype
	function actorPrototype:Bind(obj, set)
		if obj and getmetatable(obj) ~= self then
			setmetatable(obj, self)
			self.__index = self
		end
		return obj
	end
end
