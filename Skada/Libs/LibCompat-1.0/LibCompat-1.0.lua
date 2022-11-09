--
-- **LibCompat-1.0** provides few handy functions that can be embed to addons.
-- This library was originally created for Skada as of 1.8.50.
-- @author: Kader B (https://github.com/bkader/LibCompat-1.0)
--

local MAJOR, MINOR = "LibCompat-1.0-Skada", 36
local lib, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.embeds = lib.embeds or {}
lib.EmptyFunc = Multibar_EmptyFunc

local _G, pairs, type, max = _G, pairs, type, math.max
local format, tonumber = format or string.format, tonumber
local _

local Dispatch
local GetUnitIdFromGUID

-------------------------------------------------------------------------------

do
	local pcall = pcall

	function Dispatch(func, ...)
		if type(func) ~= "function" then
			print("\124cffff9900Error\124r: Dispatch requires a function.")
			return
		end
		return func(...)
	end

	local function QuickDispatch(func, ...)
		if type(func) ~= "function" then return end
		local ok, err = pcall(func, ...)
		if not ok then
			print("\124cffff9900Error\124r:" .. (err or "<no error given>"))
			return
		end
		return true
	end

	lib.Dispatch = Dispatch
	lib.QuickDispatch = QuickDispatch
end

-------------------------------------------------------------------------------

do
	local setmetatable, rawset = setmetatable, rawset
	local UnitExists, UnitAffectingCombat, UnitIsDeadOrGhost = _G.UnitExists, _G.UnitAffectingCombat, _G.UnitIsDeadOrGhost
	local UnitHealth, UnitHealthMax, UnitPower, UnitPowerMax = _G.UnitHealth, _G.UnitHealthMax, _G.UnitPower, _G.UnitPowerMax
	local GetNumRaidMembers, GetNumPartyMembers = _G.GetNumRaidMembers, _G.GetNumPartyMembers
	local GetNumGroupMembers, GetNumSubgroupMembers = _G.GetNumGroupMembers, _G.GetNumSubgroupMembers
	local IsInGroup, IsInRaid = _G.IsInGroup, _G.IsInRaid

	local function GetGroupTypeAndCount()
		if IsInRaid() then
			return "raid", 1, GetNumGroupMembers()
		elseif IsInGroup() then
			return "party", 0, GetNumSubgroupMembers()
		else
			return "solo", 0, 0
		end
	end

	local UnitIterator
	do
		local nmem, step, count

		local function SelfIterator(excPets)
			while step do
				local unit, owner
				if step == 1 then
					unit, owner, step = "player", nil, 2
				elseif step == 2 then
					if not excPets then
						unit, owner = "pet", "player"
					end
					step = nil
				end
				if unit and UnitExists(unit) then
					return unit, owner
				end
			end
		end

		local function PartyIterator(excPets)
			while step do
				local unit, owner
				if step <= 2 then
					unit, owner = SelfIterator(excPets)
					step = step or 3
				elseif step == 3 then
					unit, owner, step = format("party%d", count), nil, 4
				elseif step == 4 then
					if not excPets then
						unit, owner = format("partypet%d", count), format("party%d", count)
					end
					count = count + 1
					step = count <= nmem and 3 or nil
				end
				if unit and UnitExists(unit) then
					return unit, owner
				end
			end
		end

		local function RaidIterator(excPets)
			while step do
				local unit, owner
				if step == 1 then
					unit, owner, step = format("raid%d", count), nil, 2
				elseif step == 2 then
					if not excPets then
						unit, owner = format("raidpet%d", count), format("raid%d", count)
					end
					count = count + 1
					step = count <= nmem and 1 or nil
				end
				if unit and UnitExists(unit) then
					return unit, owner
				end
			end
		end

		function UnitIterator(excPets)
			nmem, step = GetNumGroupMembers(), 1
			if nmem == 0 then
				return SelfIterator, excPets
			end
			count = 1
			if IsInRaid() then
				return RaidIterator, excPets
			end
			return PartyIterator, excPets
		end
	end

	local function IsGroupDead()
		for unit in UnitIterator(true) do
			if not UnitIsDeadOrGhost(unit) then
				return false
			end
		end
		return true
	end

	local function IsGroupInCombat()
		for unit in UnitIterator() do
			if UnitAffectingCombat(unit) then
				return true
			end
		end
		return false
	end

	local function GroupIterator(func, ...)
		for unit, owner in UnitIterator() do
			Dispatch(func, unit, owner, ...)
		end
	end

	local MAX_BOSS_FRAMES = MAX_BOSS_FRAMES or 5

	function GetUnitIdFromGUID(guid, filter)
		if filter == nil or filter == "boss" then
			for i = 1, MAX_BOSS_FRAMES do
				if UnitExists("boss" .. i) and UnitGUID("boss" .. i) == guid then
					return "boss" .. i
				end
			end
			if filter == "boss" then return end
		end

		if filter == nil or filter == "group" then
			for unit in UnitIterator() do
				if UnitGUID(unit) == guid then
					return unit
				elseif UnitExists(unit .. "target") and UnitGUID(unit .. "target") == guid then
					return unit .. "target"
				end
			end
			if filter == "group" then return end
		end

		if filter == nil or filter == "player" then
			if UnitExists("target") and UnitGUID("target") == guid then
				return "target"
			elseif UnitExists("focus") and UnitGUID("focus") == guid then
				return "focus"
			elseif UnitExists("targettarget") and UnitGUID("targettarget") == guid then
				return "targettarget"
			elseif UnitExists("focustarget") and UnitGUID("focustarget") == guid then
				return "focustarget"
			elseif UnitExists("mouseover") and UnitGUID("mouseover") == guid then
				return "mouseover"
			elseif filter == "player" then return end
		end

		if filter == "arena" then
			for i = 1, 5 do
				if UnitExists("arena" .. i) and UnitGUID("arena" .. i) == guid then
					return "arena" .. i
				end
			end
		end
	end

	local function GetClassFromGUID(guid, filter)
		local unit = GetUnitIdFromGUID(guid, filter)
		local class
		if unit and unit:find("pet") then
			class = "PET"
		elseif unit and unit:find("boss") then
			class = "BOSS"
		elseif unit then
			_, class = UnitClass(unit)
		end
		return class, unit
	end

	local function GetCreatureId(guid)
		if guid then
			local _, _, _, _, _, id = strsplit("-", guid)
			return tonumber(id) or 0
		end
		return 0
	end

	local unknownUnits = {[_G.UKNOWNBEING] = true, [_G.UNKNOWNOBJECT] = true}

	local function UnitHealthInfo(unit, guid, filter)
		unit = (unit and not unknownUnits[unit]) and unit or (guid and GetUnitIdFromGUID(guid, filter))
		local percent, health, maxhealth
		if unit and UnitExists(unit) then
			health, maxhealth = UnitHealth(unit), UnitHealthMax(unit)
			if health and maxhealth then
				percent = 100 * health / max(1, maxhealth)
			end
		end
		return percent, health, maxhealth
	end

	local function UnitPowerInfo(unit, guid, powerType, filter)
		unit = (unit and not unknownUnits[unit]) and unit or (guid and GetUnitIdFromGUID(guid, filter))
		local percent, power, maxpower
		if unit and UnitExists(unit) then
			power, maxpower = UnitPower(unit, powerType), UnitPowerMax(unit, powerType)
			if power and maxpower then
				percent = 100 * power / max(1, maxpower)
			end
		end
		return percent, power, maxpower
	end

	lib.IsInRaid = IsInRaid
	lib.IsInGroup = IsInGroup
	lib.GetNumGroupMembers = GetNumGroupMembers
	lib.GetNumSubgroupMembers = GetNumSubgroupMembers
	lib.GetGroupTypeAndCount = GetGroupTypeAndCount
	lib.IsGroupDead = IsGroupDead
	lib.IsGroupInCombat = IsGroupInCombat
	lib.GroupIterator = GroupIterator
	lib.UnitIterator = UnitIterator
	lib.GetUnitIdFromGUID = GetUnitIdFromGUID
	lib.GetClassFromGUID = GetClassFromGUID
	lib.GetCreatureId = GetCreatureId
	lib.UnitHealthInfo = UnitHealthInfo
	lib.UnitPowerInfo = UnitPowerInfo
end

-------------------------------------------------------------------------------
-- Specs and Roles

do
	local UnitExists, UnitGUID = UnitExists, UnitGUID
	local IS_RETAIL = (_G.WOW_PROJECT_ID == _G.WOW_PROJECT_MAINLINE)

	local cachedSpecs, cachedRoles = {}, {}

	if IS_RETAIL then
		local LGT = LibStub("LibGroupInSpecT-1.1")

		setmetatable(cachedSpecs, {__index = function(self, guid)
			local info = LGT:GetCachedInfo(guid)
			local spec = info and info.global_spec_id or nil
			rawset(self, guid, spec)
			return spec
		end})

		setmetatable(cachedRoles, {__index = function(self, guid)
			local info = LGT:GetCachedInfo(guid)
			local role = info and info.spec_role or nil
			rawset(self, guid, role)
			return role
		end})

		LGT:RegisterCallback("GroupInSpecT_Update", function(_, guid, _, info)
			if not guid or not info then return end
			cachedSpecs[guid] = info.global_spec_id or cachedSpecs[guid]
			cachedRoles[guid] = info.spec_role or cachedRoles[guid]
		end)

		LGT:RegisterCallback("GroupInSpecT_Remove", function(_, guid)
			if not guid then return end
			cachedSpecs[guid] = nil
			cachedRoles[guid] = nil
		end)
	else
		local UnitClass, GetSpellInfo = UnitClass, GetSpellInfo
		local UnitGroupRolesAssigned = UnitGroupRolesAssigned
		local MAX_TALENT_TABS = _G.MAX_TALENT_TABS or 3

		local LGT = LibStub("LibGroupTalents-1.0")
		local LGTRoleTable = {melee = "DAMAGER", caster = "DAMAGER", healer = "HEALER", tank = "TANK"}

		-- list of class to specs
		local specsTable = {
			MAGE = {62, 63, 64},
			PRIEST = {256, 257, 258},
			ROGUE = {259, 260, 261},
			WARLOCK = {265, 266, 267},
			WARRIOR = {71, 72, 73},
			PALADIN = {65, 66, 70},
			DEATHKNIGHT = {250, 251, 252},
			DRUID = {102, 103, 104, 105},
			HUNTER = {253, 254, 255},
			SHAMAN = {262, 263, 264}
		}

		local guardianSpells = {
			[16929] = 2, -- Thick Hide
			[57880] = 1 -- Natural Reactions
		}
		local function GetFeralSubSpec(unit, talentGroup)
			for spellid, points in pairs(guardianSpells) do
				local pts = LGT:UnitHasTalent(unit, GetSpellInfo(spellid), talentGroup) or 0
				if pts <= points then
					return 2
				end
			end
			return 3
		end

		-- cached specs
		setmetatable(cachedSpecs, {__index = function(self, guid)
			local unit = guid and (GetUnitIdFromGUID(guid, "group") or GetUnitIdFromGUID(guid, "player"))
			if not unit then return end

			local _, class = UnitClass(unit)
			if not class or not specsTable[class] then return end

			local talentGroup = LGT:GetActiveTalentGroup(unit)
			local maxPoints, index = 0, 0

			for i = 1, MAX_TALENT_TABS do
				local _, _, pointsSpent = LGT:GetTalentTabInfo(unit, i, talentGroup)
				if pointsSpent ~= nil then
					if maxPoints < pointsSpent then
						maxPoints = pointsSpent
						if class == "DRUID" and i >= 2 then
							if i == 3 then
								index = 4
							elseif i == 2 then
								index = GetFeralSubSpec(unit, talentGroup)
							end
						else
							index = i
						end
					end
				end
			end

			local spec = specsTable[class][index]
			rawset(self, guid, spec)
			return spec
		end})

		-- cached roles
		setmetatable(cachedRoles, {__index = function(self, guid)
			local unit = guid and (GetUnitIdFromGUID(guid, "group") or GetUnitIdFromGUID(guid, "player"))
			if not unit then return end

			local role = nil

			-- For LFG using "UnitGroupRolesAssigned" is enough.
			local isTank, isHealer, isDamager = UnitGroupRolesAssigned(unit)
			if isTank then
				role = "TANK"
			elseif isHealer then
				role = "HEALER"
			elseif isDamager then
				role = "DAMAGER"
			else
				local _, class = UnitClass(unit)
				-- speedup things using classes.
				if class == "HUNTER" or class == "MAGE" or class == "ROGUE" or class == "WARLOCK" then
					role = "DAMAGER"
				else
					role = LGTRoleTable[LGT:GetUnitRole(unit)] or "NONE"
				end
			end

			rawset(self, guid, role)
			return role
		end})

		LGT:RegisterCallback("LibGroupTalents_Update", function(_, guid, unit, _, n1, n2, n3)
			if not guid or not unit then return end

			local _, class = UnitClass(unit)
			if class and specsTable[class] then
				local nx = max(n1, n2, n3) -- highest in points spent
				local index = nx == n1 and 1 or nx == n2 and 2 or nx == n3 and 3

				if class == "DRUID" and index == 3 then
					index = 4
				elseif class == "DRUID" and index == 2 then
					local points = LGT:UnitHasTalent(unit, GetSpellInfo(57881))
					index = (points and points > 0) and 3 or 2
				end

				cachedSpecs[guid] = specsTable[class][index]
			end
		end)

		LGT:RegisterCallback("LibGroupTalents_RoleChange", function(_, guid, _, role, oldrole)
			if not guid or role == oldrole then return end
			cachedRoles[guid] = LGTRoleTable[role] or role
		end)
	end

	local function GetUnitSpec(guid)
		return cachedSpecs[guid]
	end

	local function GetUnitRole(guid)
		return cachedRoles[guid]
	end


	lib.GetUnitSpec = GetUnitSpec
	lib.GetUnitRole = GetUnitRole
end

-------------------------------------------------------------------------------
-- Pvp

do
	local IsInInstance, instanceType = IsInInstance, nil

	local function IsInPvP()
		_, instanceType = IsInInstance()
		return (instanceType == "pvp" or instanceType == "arena")
	end

	lib.IsInPvP = IsInPvP
end

-------------------------------------------------------------------------------

local mixins = {
	"EmptyFunc",
	"Dispatch",
	"QuickDispatch",
	-- roster util
	"IsInRaid",
	"IsInGroup",
	"IsInPvP",
	"GetNumGroupMembers",
	"GetNumSubgroupMembers",
	"GetGroupTypeAndCount",
	"IsGroupDead",
	"IsGroupInCombat",
	"GroupIterator",
	"UnitIterator",
	-- unit util
	"GetUnitIdFromGUID",
	"GetClassFromGUID",
	"GetCreatureId",
	"UnitHealthInfo",
	"UnitPowerInfo",
	"GetUnitSpec",
	"GetUnitRole"
}

function lib:Embed(target)
	for _, v in pairs(mixins) do
		target[v] = self[v]
	end
	self.embeds[target] = true
	return target
end

for addon in pairs(lib.embeds) do
	lib:Embed(addon)
end
