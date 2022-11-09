local _, Skada = ...
local Private = Skada.Private

-- frequently used globals --
local pairs, type, format, max = pairs, type, string.format, math.max
local wipe, uformat, new, clear = wipe, Private.uformat, Private.newTable, Private.clearTable
local setPrototype, enemyPrototype = Skada.setPrototype, Skada.enemyPrototype

---------------------------------------------------------------------------
-- Enemy Damage Taken

Skada:RegisterModule("Enemy Damage Taken", function(L, P, _, C)
	local mod = Skada:NewModule("Enemy Damage Taken")
	local sourcemod = mod:NewModule("Damage source list")
	local sourcespellmod = sourcemod:NewModule("Damage spell list")
	local spellmod = mod:NewModule("Damage spell list")
	local spellsourcemod = spellmod:NewModule("Damage spell sources")
	local usefulmod = mod:NewModule("Useful Damage")
	local ignored_spells = Skada.dummyTable -- Edit Skada\Core\Tables.lua
	local mod_cols = nil

	local instanceDiff, customGroupsTable, customUnitsTable, customUnitsInfo
	local UnitIterator, GetCreatureId = Skada.UnitIterator, Skada.GetCreatureId
	local UnitHealthInfo, UnitPowerInfo = Skada.UnitHealthInfo, Skada.UnitPowerInfo
	local UnitExists, UnitGUID = UnitExists, UnitGUID
	local UnitHealthMax, UnitPowerMax = UnitHealthMax, UnitPowerMax
	local tContains, del = tContains, Private.delTable

	-- this table holds the units to which the damage done is
	-- collected into a new fake unit.
	local customGroups = {}

	-- this table holds units that should create a fake unit
	-- at certain health percentage. Useful in case you want
	-- to collect damage done to the units at certain phases.
	local customUnits = {}

	-- table of acceptable/trackable instance difficulties
	-- uncomments those you want to use or add custom ones.
	local allowed_diffs = {
		-- ["5n"] = true, -- 5man Normal
		-- ["5h"] = true, -- 5man Heroic
		-- ["mc"] = true, -- Mythic Dungeons
		-- ["tw"] = true, -- Time Walker
		-- ["wb"] = true, -- World Boss
		["10n"] = true, -- 10man Normal
		["10h"] = true, -- 10man Heroic
		["25n"] = true, -- 25man Normal
		["25h"] = true, -- 25man Heroic
	}

	local function format_valuetext(d, columns, total, dtps, metadata, subview)
		d.valuetext = Skada:FormatValueCols(
			columns.Damage and Skada:FormatNumber(d.value),
			columns[subview and "sDTPS" or "DTPS"] and Skada:FormatNumber(dtps),
			columns[subview and "sPercent" or "Percent"] and Skada:FormatPercent(d.value, total)
		)

		if metadata and d.value > metadata.maxvalue then
			metadata.maxvalue = d.value
		end
	end

	local function get_instance_diff()
		if not instanceDiff then
			instanceDiff = Skada:GetInstanceDiff() or "NaN"
		end
		return instanceDiff
	end

	local function custom_units_max_value(id, guid, unit)
		if id and customUnitsInfo and customUnitsInfo[id] then
			return customUnitsInfo[id]
		end

		local maxval
		for uid in UnitIterator() do
			if UnitExists(uid .. "target") and UnitGUID(uid .. "target") == guid then
				maxval = (unit.power ~= nil) and UnitPowerMax(uid .. "target", unit.power) or UnitHealthMax(uid .. "target")
				if maxval and maxval > 0 then break end -- break only if found!
			end
		end

		if not maxval then
			if unit.power ~= nil then
				_, _, maxval = UnitPowerInfo(nil, guid, unit.power)
			else
				_, _, maxval = UnitHealthInfo(nil, guid)
			end
		end

		if not maxval and unit.values then
			maxval = unit.values[get_instance_diff()]
		end

		if maxval and maxval > 0 then
			customUnitsInfo = customUnitsInfo or {}
			customUnitsInfo[id] = maxval
		end

		return maxval
	end

	local function is_custom_unit(guid, name, amount, overkill)
		if guid and customUnitsTable and customUnitsTable[guid] then
			return (customUnitsTable[guid] ~= -1)
		end

		local id = GetCreatureId(guid)
		local unit = id and customUnits[id]
		if unit then
			customUnitsTable = customUnitsTable or {}

			if unit.diff ~= nil and ((type(unit.diff) == "table" and not tContains(unit.diff, get_instance_diff())) or (type(unit.diff) == "string" and get_instance_diff() ~= unit.diff)) then
				customUnitsTable[guid] = -1
				return false
			end

			-- get the unit max value.
			local maxval = custom_units_max_value(id, guid, unit)
			if not maxval or maxval == 0 then
				customUnitsTable[guid] = -1
				return false
			end

			-- calculate the current value and the point where to stop.
			local curval = maxval - amount - overkill
			local minval = floor(maxval * (unit.stop or 0))

			-- ignore units below minimum required.
			if curval <= minval then
				customUnitsTable[guid] = -1
				return false
			end

			local t = new()
			t.oname = name or L["Unknown"]
			t.name = unit.name
			t.guid = guid
			t.curval = curval
			t.minval = minval
			t.maxval = floor(maxval * (unit.start or 1))
			t.full = maxval
			t.power = (unit.power ~= nil)
			t.useful = unit.useful

			if unit.name == nil then
				local str = unit.text or (unit.stop and L["%s - %s%% to %s%%"] or L["%s below %s%%"])
				t.name = format(str, t.oname, (unit.start or 1) * 100, (unit.stop or 0) * 100)
			end

			customUnitsTable[guid] = t
			return true
		end

		return false
	end

	local function log_custom_unit(set, name, playername, spellid, amount, absorbed)
		local e = Skada:GetEnemy(set, name)
		if not e then return end

		e.fake = true
		e.damaged = (e.damaged or 0) + amount
		e.totaldamaged = (e.totaldamaged or 0) + amount
		if absorbed > 0 then
			e.totaldamaged = e.totaldamaged + absorbed
		end

		-- spell
		local spell = e.damagedspells and e.damagedspells[spellid]
		if not spell then
			e.damagedspells = e.damagedspells or {}
			e.damagedspells[spellid] = {amount = amount}
			spell = e.damagedspells[spellid]
		else
			spell.amount = spell.amount + amount
		end

		if spell.total then
			spell.total = spell.total + amount + absorbed
		elseif absorbed > 0 then
			spell.total = spell.amount + absorbed
		end

		-- source
		local source = spell.sources and spell.sources[playername]
		if not source then
			spell.sources = spell.sources or {}
			spell.sources[playername] = {amount = amount}
			source = spell.sources[playername]
		else
			source.amount = source.amount + amount
		end

		if source.total then
			source.total = source.total + amount + absorbed
		elseif absorbed > 0 then
			source.total = source.amount + absorbed
		end
	end

	local function log_custom_group(set, id, name, playername, spellid, amount, overkill, absorbed)
		if not (name and customGroups[name]) then return end -- not a custom group.
		if customGroups[name] == L["Halion and Inferno"] and get_instance_diff() ~= "25h" then return end -- rs25hm only
		if customGroupsTable and customGroupsTable[id] then return end -- a custom unit with useful damage.

		amount = (customGroups[name] == L["Princes overkilling"]) and overkill or amount
		log_custom_unit(set, customGroups[name], playername, spellid, amount, absorbed)
	end

	local dmg = {}
	local function log_damage(set)
		if not set or (set == Skada.total and not P.totalidc) then return end

		local absorbed = dmg.absorbed or 0
		if (dmg.amount + absorbed) == 0 then return end

		local e = Skada:GetEnemy(set, dmg.actorname, dmg.actorid, dmg.actorflags)
		if not e then return end

		e.damaged = (e.damaged or 0) + dmg.amount
		set.edamaged = (set.edamaged or 0) + dmg.amount

		if e.totaldamaged then
			e.totaldamaged = e.totaldamaged + dmg.amount + absorbed
		elseif absorbed > 0 then
			e.totaldamaged = e.damaged + absorbed
		end

		if set.etotaldamaged then
			set.etotaldamaged = set.etotaldamaged + dmg.amount + absorbed
		elseif absorbed > 0 then
			set.etotaldamaged = set.edamaged + absorbed
		end

		-- damage spell.
		local spell = e.damagedspells and e.damagedspells[dmg.spellid]
		if not spell then
			e.damagedspells = e.damagedspells or {}
			e.damagedspells[dmg.spellid] = {amount = dmg.amount}
			spell = e.damagedspells[dmg.spellid]
		else
			spell.amount = spell.amount + dmg.amount
		end

		if spell.total then
			spell.total = spell.total + dmg.amount + absorbed
		elseif absorbed > 0 then
			spell.total = spell.amount + absorbed
		end

		local overkill = dmg.overkill or 0
		if overkill > 0 then
			spell.o_amt = (spell.o_amt or 0) + overkill
		end

		-- damage source.
		if not dmg.srcName then return end

		-- the source
		local source = spell.sources and spell.sources[dmg.srcName]
		if not source then
			spell.sources = spell.sources or {}
			spell.sources[dmg.srcName] = {amount = dmg.amount}
			source = spell.sources[dmg.srcName]
		else
			source.amount = source.amount + dmg.amount
		end

		if source.total then
			source.total = source.total + dmg.amount + absorbed
		elseif absorbed > 0 then
			source.total = source.amount + absorbed
		end

		if overkill > 0 then
			source.o_amt = (source.o_amt or 0) + dmg.overkill
		end

		-- the rest of the code is only for allowed instance diffs.
		if not allowed_diffs[get_instance_diff()] then return end

		if is_custom_unit(dmg.actorid, dmg.actorname, dmg.amount, overkill) then
			local unit = customUnitsTable[dmg.actorid]
			-- started with less than max?
			if unit.full then
				local amount = unit.full - unit.curval
				if unit.useful then
					e.usefuldamaged = (e.usefuldamaged or 0) + amount
					spell.useful = (spell.useful or 0) + amount
					source.useful = (source.useful or 0) + amount
				end
				if unit.maxval == unit.full then
					log_custom_unit(set, unit.name, dmg.srcName, dmg.spellid, amount, absorbed)
				end
				unit.full = nil
			elseif unit.curval >= unit.maxval then
				local amount = dmg.amount - overkill
				unit.curval = unit.curval - amount

				if unit.curval <= unit.maxval then
					log_custom_unit(set, unit.name, dmg.srcName, dmg.spellid, unit.maxval - unit.curval, absorbed)
					amount = amount - (unit.maxval - unit.curval)
					if customGroups[unit.oname] and unit.useful then
						log_custom_group(set, unit.guid, unit.oname, dmg.srcName, dmg.spellid, amount, overkill, absorbed)
						customGroupsTable = customGroupsTable or {}
						customGroupsTable[unit.guid] = true
					end
					if customGroups[unit.name] then
						log_custom_group(set, unit.guid, unit.name, dmg.srcName, dmg.spellid, unit.maxval - unit.curval, overkill, absorbed)
					end
				end
				if unit.useful then
					e.usefuldamaged = (e.usefuldamaged or 0) + amount
					spell.useful = (spell.useful or 0) + amount
					source.useful = (source.useful or 0) + amount
				end
			elseif unit.curval >= unit.minval then
				local amount = dmg.amount - overkill
				unit.curval = unit.curval - amount

				if customGroups[unit.name] then
					log_custom_group(set, unit.guid, unit.name, dmg.srcName, dmg.spellid, amount, overkill, absorbed)
				end

				if unit.curval <= unit.minval then
					log_custom_unit(set, unit.name, dmg.srcName, dmg.spellid, amount - (unit.minval - unit.curval), absorbed)

					-- remove it
					local guid = unit.guid
					customUnitsTable[guid] = del(customUnitsTable[guid])
					customUnitsTable[guid] = -1
				else
					log_custom_unit(set, unit.name, dmg.srcName, dmg.spellid, amount, absorbed)
				end
			elseif unit.power then
				log_custom_unit(set, unit.name, dmg.srcName, dmg.spellid, dmg.amount - (unit.useful and overkill or 0), absorbed)
			end
		end

		-- custom groups
		log_custom_group(set, dmg.actorid, dmg.actorname, dmg.srcName, dmg.spellid, dmg.amount, overkill, absorbed)
	end

	local function spell_damage(t)
		if t.srcName and t.dstName and t.spellid and not ignored_spells[t.spellid] and (not t.misstype or t.misstype == "ABSORB") then
			dmg.actorid = t.dstGUID
			dmg.actorname = t.dstName
			dmg.actorflags = t.dstFlags

			dmg.spellid = t.spellstring
			dmg.amount = t.amount
			dmg.overkill = t.overkill
			dmg.absorbed = t.absorbed

			_, dmg.srcName = Skada:FixMyPets(t.srcGUID, t.srcName, t.srcFlags)
			Skada:DispatchSets(log_damage)
		end
	end

	local function sourcemod_tooltip(win, id, label, tooltip)
		local set = win:GetSelectedSet()
		if not set then return end

		local damage, overkill, useful = set:GetActorDamageFromSource(win.targetid, win.targetname, label)
		if damage == 0 then return end

		tooltip:AddLine(format(L["%s's damage breakdown"], label))
		tooltip:AddDoubleLine(L["Damage Done"], Skada:FormatNumber(damage), 1, 1, 1)
		if useful > 0 then
			tooltip:AddDoubleLine(L["Useful Damage"], format("%s (%s)", Skada:FormatNumber(useful), Skada:FormatPercent(useful, damage)), 1, 1, 1)

			-- override overkill
			overkill = max(0, damage - useful)
			tooltip:AddDoubleLine(L["Overkill"], format("%s (%s)", Skada:FormatNumber(overkill), Skada:FormatPercent(overkill, damage)), 1, 1, 1)
		elseif overkill > 0 then
			tooltip:AddDoubleLine(L["Overkill"], format("%s (%s)", Skada:FormatNumber(overkill), Skada:FormatPercent(overkill, damage)), 1, 1, 1)
		end
	end

	local function usefulmod_tooltip(win, id, label, tooltip)
		local set = win:GetSelectedSet()
		local e = set and set:GetEnemy(label, id)
		local amount, total, useful = e:GetDamageTakenBreakdown(set)
		if not useful or useful == 0 then return end

		tooltip:AddLine(format(L["%s's damage breakdown"], label))
		tooltip:AddDoubleLine(L["Damage Done"], Skada:FormatNumber(total), 1, 1, 1)
		tooltip:AddDoubleLine(L["Useful Damage"], format("%s (%s)", Skada:FormatNumber(useful), Skada:FormatPercent(useful, total)), 1, 1, 1)
		local overkill = max(0, total - useful)
		tooltip:AddDoubleLine(L["Overkill"], format("%s (%s)", Skada:FormatNumber(overkill), Skada:FormatPercent(overkill, total)), 1, 1, 1)
	end

	function spellsourcemod:Enter(win, id, label)
		win.spellid, win.spellname = id, label
		win.title = uformat(L["%s's <%s> sources"], win.targetname, label)
	end

	function spellsourcemod:Update(win, set)
		win.title = uformat(L["%s's <%s> sources"], win.targetname, win.spellname)
		if win.class then
			win.title = format("%s (%s)", win.title, L[win.class])
		end

		if not win.spellid then return end

		local actor = set and set:GetEnemy(win.targetname, win.targetid)
		if not (actor and actor.GetDamageSpellSources) then return end

		local sources, total = actor:GetDamageSpellSources(set, win.spellid)
		if not sources or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actortime = mod_cols.sDTPS and actor:GetTime(set)

		for sourcename, source in pairs(sources) do
			if not win.class or win.class == source.class then
				nr = nr + 1

				local d = win:actor(nr, source, source.enemy, sourcename)
				d.value = source.amount
				format_valuetext(d, mod_cols, total, actortime and (d.value / actortime), win.metadata, true)
			end
		end
	end

	function sourcemod:Enter(win, id, label)
		win.targetid, win.targetname = id, label
		win.title = format(L["%s's damage sources"], label)
	end

	function sourcemod:Update(win, set)
		win.title = uformat(L["%s's damage sources"], win.targetname)
		if win.class then
			win.title = format("%s (%s)", win.title, L[win.class])
		end

		local sources, total, actor = set:GetActorDamageSources(win.targetid, win.targetname)
		if not sources or not actor or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actortime = mod_cols.sDTPS and actor:GetTime(set)

		for sourcename, source in pairs(sources) do
			if not win.class or win.class == source.class then
				nr = nr + 1

				local d = win:actor(nr, source, source.enemy, sourcename)
				d.value = P.absdamage and source.total or source.amount
				format_valuetext(d, mod_cols, total, actortime and (d.value / actortime), win.metadata, true)
			end
		end
	end

	function sourcespellmod:Enter(win, id, label)
		win.actorid, win.actorname = id, label
		win.title = L["actor damage"](label or L["Unknown"], win.targetname or L["Unknown"])
	end

	function sourcespellmod:Update(win, set)
		win.title = L["actor damage"](win.actorname or L["Unknown"], win.targetname or L["Unknown"])
		if not win.actorname or not win.targetname then return end

		local actor = set and set:GetEnemy(win.targetname, win.targetid)
		local sources = actor and actor:GetDamageSources(set)
		local source = sources and sources[win.actorname]
		if not source then return end

		local total = P.absdamage and source.total or source.amount
		if not total or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actortime = mod_cols.sDTPS and actor:GetTime(set)
		local spells = actor.damagedspells

		for spellid, spell in pairs(spells) do
			local src = spell.sources and spell.sources[win.actorname]
			if src then
				nr = nr + 1

				local d = win:spell(nr, spellid)
				d.value = P.absdamage and src.total or src.amount
				format_valuetext(d, mod_cols, total, actortime and (d.value / actortime), win.metadata, true)
			end
		end
	end

	function spellmod:Enter(win, id, label)
		win.targetid, win.targetname = id, label
		win.title = format(L["Damage taken by %s"], label)
	end

	function spellmod:Update(win, set)
		win.title = uformat(L["Damage taken by %s"], win.targetname)

		local actor = set and set:GetEnemy(win.targetname, win.targetid)
		local total = actor and actor:GetDamageTaken()
		local spells = (total and total > 0) and actor.damagedspells

		if not spells then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actortime = mod_cols.sDTPS and actor:GetTime(set)

		for spellid, spell in pairs(spells) do
			nr = nr + 1

			local d = win:spell(nr, spellid)
			d.value = P.absdamage and spell.total or spell.amount
			format_valuetext(d, mod_cols, total, actortime and (d.value / actortime), win.metadata, true)
		end
	end

	function usefulmod:Enter(win, id, label)
		win.targetid, win.targetname = id, label
		win.title = format(L["Useful damage on %s"], label)
	end

	function usefulmod:Update(win, set)
		win.title = uformat(L["Useful damage on %s"], win.targetname)
		if win.class then
			win.title = format("%s (%s)", win.title, L[win.class])
		end

		local actor = set and set:GetEnemy(win.targetname, win.targetid)
		local total = actor and actor.usefuldamaged
		local sources = (total and total > 0) and actor:GetDamageSources(set)

		if not sources then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actortime = mod_cols.sDTPS and actor:GetTime(set)

		for sourcename, source in pairs(sources) do
			if win:show_actor(source, set) and source.useful and source.useful > 0 then
				nr = nr + 1

				local d = win:actor(nr, source, nil, sourcename)
				d.value = source.useful
				format_valuetext(d, mod_cols, total, actortime and (d.value / actortime), win.metadata, true)
			end
		end
	end

	function mod:Update(win, set)
		win.title = L["Enemy Damage Taken"]

		local total = set and set:GetDamageTaken(win.class, true)
		if not total or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actors = set.actors

		for i = 1, #actors do
			local actor = actors[i]
			if actor and actor.enemy then
				local dtps, amount = actor:GetDTPS(set, nil, not mod_cols.sDTPS)
				if amount > 0 then
					nr = nr + 1

					local d = win:actor(nr, actor, true)
					d.value = amount
					format_valuetext(d, mod_cols, total, dtps, win.metadata)
				end
			end
		end
	end

	function mod:GetSetSummary(set, win)
		local dtps, amount = set:GetDTPS(win and win.class, true)
		local valuetext = Skada:FormatValueCols(
			mod_cols.Damage and Skada:FormatNumber(amount or 0),
			mod_cols.DTPS and Skada:FormatNumber(dtps)
		)
		return amount, valuetext
	end

	function mod:OnEnable()
		spellsourcemod.metadata = {
			showspots = true,
			click4 = Skada.FilterClass,
			click4_label = L["Toggle Class Filter"]
		}
		usefulmod.metadata = {
			showspots = true,
			click4 = Skada.FilterClass,
			click4_label = L["Toggle Class Filter"]
		}
		sourcemod.metadata = {
			showspots = true,
			click1 = sourcespellmod,
			click4 = Skada.FilterClass,
			post_tooltip = sourcemod_tooltip,
			click4_label = L["Toggle Class Filter"]
		}
		spellmod.metadata = {click1 = spellsourcemod, valueorder = true}
		self.metadata = {
			click1 = sourcemod,
			click2 = spellmod,
			click3 = usefulmod,
			post_tooltip = usefulmod_tooltip,
			columns = {Damage = true, DTPS = false, Percent = true, sDTPS = false, sPercent = true},
			icon = [[Interface\Icons\spell_fire_felflamebolt]]
		}

		mod_cols = self.metadata.columns

		-- no total click.
		sourcemod.nototal = true
		spellmod.nototal = true
		usefulmod.nototal = true

		Skada:RegisterForCL(
			spell_damage,
			{src_is_interesting = true, dst_is_not_interesting = true},
			-- damage events
			"DAMAGE_SHIELD",
			"DAMAGE_SPLIT",
			"RANGE_DAMAGE",
			"SPELL_BUILDING_DAMAGE",
			"SPELL_DAMAGE",
			"SPELL_PERIODIC_DAMAGE",
			"SWING_DAMAGE",
			"ENVIRONMENTAL_DAMAGE",
			-- missed events
			"DAMAGE_SHIELD_MISSED",
			"RANGE_MISSED",
			"SPELL_BUILDING_MISSED",
			"SPELL_MISSED",
			"SPELL_PERIODIC_MISSED",
			"SWING_MISSED"
		)

		Skada.RegisterMessage(self, "COMBAT_PLAYER_LEAVE", "CombatLeave")
		Skada:AddMode(self, L["Enemies"])

		-- table of ignored spells:
		if Skada.ignored_spells and Skada.ignored_spells.damage then
			ignored_spells = Skada.ignored_spells.damage
		end
	end

	function mod:OnDisable()
		Skada.UnregisterAllMessages(self)
		Skada:RemoveMode(self)
	end

	function mod:CombatLeave()
		instanceDiff = nil
		wipe(dmg)
		clear(customUnitsInfo)
		clear(customUnitsTable)
		clear(customGroupsTable)
	end

	function mod:OnInitialize()
		-- ----------------------------
		-- Custom Groups
		-- ----------------------------

		-- The Lich King: Useful targets
		customGroups[L["The Lich King"]] = L["Important targets"]
		customGroups[L["Raging Spirit"]] = L["Important targets"]
		customGroups[L["Ice Sphere"]] = L["Important targets"]
		customGroups[L["Val'kyr Shadowguard"]] = L["Important targets"]
		customGroups[L["Wicked Spirit"]] = L["Important targets"]

		-- Professor Putricide: Oozes
		customGroups[L["Gas Cloud"]] = L["Oozes"]
		customGroups[L["Volatile Ooze"]] = L["Oozes"]

		-- Blood Prince Council: Princes overkilling
		customGroups[L["Prince Valanar"]] = L["Princes overkilling"]
		customGroups[L["Prince Taldaram"]] = L["Princes overkilling"]
		customGroups[L["Prince Keleseth"]] = L["Princes overkilling"]

		-- Lady Deathwhisper: Adds
		customGroups[L["Cult Adherent"]] = L["Adds"]
		customGroups[L["Empowered Adherent"]] = L["Adds"]
		customGroups[L["Reanimated Adherent"]] = L["Adds"]
		customGroups[L["Cult Fanatic"]] = L["Adds"]
		customGroups[L["Deformed Fanatic"]] = L["Adds"]
		customGroups[L["Reanimated Fanatic"]] = L["Adds"]
		customGroups[L["Darnavan"]] = L["Adds"]

		-- Halion: Halion and Inferno
		customGroups[L["Halion"]] = L["Halion and Inferno"]
		customGroups[L["Living Inferno"]] = L["Halion and Inferno"]

		-- ----------------------------
		-- Custom Units
		-- ----------------------------

		-- ICC: Valkyrs overkilling
		customUnits[36609] = {
			name = L["Valkyrs overkilling"],
			diff = {"10h", "25h"}, start = 0.5, useful = true,
			values = {["10h"] = 1417500, ["25h"] = 2992000}
		}
	end

	---------------------------------------------------------------------------

	function enemyPrototype:GetDamageSpellSources(set, spellid, tbl)
		local spell = set and spellid and self.damagedspells and self.damagedspells[spellid]
		if not spell or not spell.sources then return end

		tbl = clear(tbl or C)
		for name, source in pairs(spell.sources) do
			local t = tbl[name]
			if not t then
				t = new()
				t.amount = P.absdamage and source.total or source.amount or 0
				tbl[name] = t
			else
				t.amount = t.amount + (P.absdamage and source.total or source.amount or 0)
			end

			set:_fill_actor_table(t, name)
		end

		return tbl, P.absdamage and spell.total or spell.amount
	end

	function enemyPrototype:GetDamageTakenBreakdown(set)
		local sources = self:GetDamageSources(set)
		if not sources then return end

		local amount, total, useful = 0, 0, 0
		for _, src in pairs(sources) do
			if src.amount then
				amount = amount + src.amount
			end
			if src.total then
				total = total + src.total
			end
			if src.useful then
				useful = useful + src.useful
			end
		end
		return amount, total, useful
	end
end)

---------------------------------------------------------------------------
-- Enemy Damage Done

Skada:RegisterModule("Enemy Damage Done", function(L, P, _, C)
	local mod = Skada:NewModule("Enemy Damage Done")
	local targetmod = mod:NewModule("Damage target list")
	local targetspellmod = targetmod:NewModule("Damage spell targets")
	local spellmod = mod:NewModule("Damage spell list")
	local spelltargetmod = spellmod:NewModule("Damage spell targets")
	local ignored_spells = Skada.dummyTable -- Edit Skada\Core\Tables.lua
	local passive_spells = Skada.dummyTable -- Edit Skada\Core\Tables.lua
	local mod_cols = nil

	local function format_valuetext(d, columns, total, dps, metadata, subview)
		d.valuetext = Skada:FormatValueCols(
			columns.Damage and Skada:FormatNumber(d.value),
			columns[subview and "sDPS" or "DPS"] and dps and Skada:FormatNumber(dps),
			columns[subview and "sPercent" or "Percent"] and Skada:FormatPercent(d.value, total)
		)

		if metadata and d.value > metadata.maxvalue then
			metadata.maxvalue = d.value
		end
	end

	local function add_actor_time(set, actor, spellid, target)
		if not spellid or passive_spells[spellid] then
			return -- missing spellid or passive spell?
		elseif not Skada.validclass[actor.class] or actor.role == "HEALER" then
			return -- missing/invalid actor class or actor is a healer?
		else
			Skada:AddActiveTime(set, actor, target)
		end
	end

	local dmg = {}
	local function log_damage(set)
		if not set or (set == Skada.total and not P.totalidc) then return end

		local absorbed = dmg.absorbed or 0
		if (dmg.amount + absorbed) == 0 then return end

		local e = Skada:GetEnemy(set, dmg.actorname, dmg.actorid, dmg.actorflags)
		if not e then
			return
		elseif (set.type == "arena" or set.type == "pvp") and dmg.amount > 0 then
			add_actor_time(set, e, dmg.spell, dmg.dstName)
		end

		e.damage = (e.damage or 0) + dmg.amount
		set.edamage = (set.edamage or 0) + dmg.amount

		if e.totaldamage then
			e.totaldamage = e.totaldamage + dmg.amount + absorbed
		elseif absorbed > 0 then
			e.totaldamage = e.damage + absorbed
		end

		if set.etotaldamage then
			set.etotaldamage = set.etotaldamage + dmg.amount + absorbed
		elseif absorbed > 0 then
			set.etotaldamage = set.edamage + absorbed
		end

		local overkill = dmg.overkill or 0
		if overkill > 0 then
			set.eoverkill = (set.eoverkill or 0) + dmg.overkill
			e.overkill = (e.overkill or 0) + dmg.overkill
		end

		-- damage spell.
		local spell = e.damagespells and e.damagespells[dmg.spellid]
		if not spell then
			e.damagespells = e.damagespells or {}
			e.damagespells[dmg.spellid] = {amount = dmg.amount}
			spell = e.damagespells[dmg.spellid]
		else
			spell.amount = spell.amount + dmg.amount
		end

		if spell.total then
			spell.total = spell.total + dmg.amount + absorbed
		elseif absorbed > 0 then
			spell.total = spell.amount + absorbed
		end

		if overkill > 0 then
			spell.o_amt = (spell.o_amt or 0) + dmg.overkill
		end

		-- damage target.
		if not dmg.dstName then return end

		local target = spell.targets and spell.targets[dmg.dstName]
		if not target then
			spell.targets = spell.targets or {}
			spell.targets[dmg.dstName] = {amount = dmg.amount}
			target = spell.targets[dmg.dstName]
		else
			target.amount = target.amount + dmg.amount
		end

		if target.total then
			target.total = target.total + dmg.amount + absorbed
		elseif absorbed > 0 then
			target.total = target.amount + absorbed
		end

		if overkill > 0 then
			target.o_amt = (target.o_amt or 0) + dmg.overkill
		end
	end

	local function spell_damage(t)
		if t.srcName and t.dstName and t.spellid and not ignored_spells[t.spellid] and (not t.misstype or t.misstype == "ABSORB") then
			dmg.actorid = t.srcGUID
			dmg.actorname = t.srcName
			dmg.actorflags = t.srcFlags

			dmg.spell = t.spellid
			dmg.spellid = t.spellstring
			dmg.amount = t.amount
			dmg.overkill = t.overkill
			dmg.absorbed = t.absorbed

			dmg.dstName = Skada:FixPetsName(t.dstGUID, t.dstName, t.dstFlags)
			Skada:DispatchSets(log_damage)
		end
	end

	function targetspellmod:Enter(win, id, label)
		win.actorid, win.actorname = id, label
		win.title = L["actor damage"](win.targetname or L["Unknown"], label)
	end

	function targetspellmod:Update(win, set)
		win.title = L["actor damage"](win.targetname or L["Unknown"], win.actorname or L["Unknown"])
		if not (win.targetname and win.actorname) then return end

		local actor = set and set:GetEnemy(win.targetname, win.targetid)
		if not (actor and actor.GetDamageTargetSpells) then return end
		local spells, total = actor:GetDamageTargetSpells(win.actorname)

		if not spells or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actortime = mod_cols.sDPS and actor:GetTime(set)

		for spellid, spell in pairs(spells) do
			nr = nr + 1

			local d = win:spell(nr, spellid)
			d.value = spell.amount
			format_valuetext(d, mod_cols, total, actortime and (d.value / actortime), win.metadata, true)
		end
	end

	function spelltargetmod:Enter(win, id, label)
		win.spellid, win.spellname = id, label
		win.title = uformat(L["%s's <%s> targets"], win.targetname, label)
	end

	function spelltargetmod:Update(win, set)
		win.title = uformat(L["%s's <%s> targets"], win.targetname, win.spellname)
		if win.class then
			win.title = format("%s (%s)", win.title, L[win.class])
		end

		if not win.spellid then return end

		local actor = set and set:GetEnemy(win.targetname, win.targetid)
		if not (actor and actor.GetDamageSpellTargets) then return end

		local targets, total = actor:GetDamageSpellTargets(set, win.spellid)
		if not targets or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actortime = mod_cols.sDPS and actor:GetTime(set)

		for targetname, target in pairs(targets) do
			if not win.class or win.class == target.class then
				nr = nr + 1

				local d = win:actor(nr, target, nil, targetname)
				d.value = target.amount
				format_valuetext(d, mod_cols, total, actortime and (d.value / actortime), win.metadata, true)
			end
		end
	end

	function targetmod:Enter(win, id, label)
		win.targetid, win.targetname = id, label
		win.title = format(L["%s's targets"], label)
	end

	function targetmod:Update(win, set)
		win.title = uformat(L["%s's targets"], win.targetname)
		if win.class then
			win.title = format("%s (%s)", win.title, L[win.class])
		end

		local targets, total, actor = set:GetActorDamageTargets(win.targetid, win.targetname)
		if not targets or not actor or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actortime = mod_cols.sDPS and actor:GetTime(set)

		for targetname, target in pairs(targets) do
			if not win.class or win.class == target.class then
				nr = nr + 1

				local d = win:actor(nr, target, true, targetname)
				d.value = P.absdamage and target.total or target.amount
				format_valuetext(d, mod_cols, total, actortime and (d.value / actortime), win.metadata, true)
			end
		end
	end

	function spellmod:Enter(win, id, label)
		win.targetid, win.targetname = id, label
		win.title = L["actor damage"](label)
	end

	function spellmod:Update(win, set)
		win.title = L["actor damage"](win.targetname or L["Unknown"])

		local actor = set and set:GetEnemy(win.targetname, win.targetid)
		local total = actor and actor:GetDamage()
		local spells = (total and total > 0) and actor.damagespells

		if not spells then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actortime = mod_cols.sDPS and actor:GetTime(set)

		for spellid, spell in pairs(spells) do
			nr = nr + 1

			local d = win:spell(nr, spellid)
			d.value = P.absdamage and spell.total or spell.amount
			format_valuetext(d, mod_cols, total, actortime and (d.value / actortime), win.metadata, true)
		end
	end

	function mod:Update(win, set)
		win.title = L["Enemy Damage Done"]

		local total = set and set:GetEnemyDamage()
		if not total or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actors = set.actors -- enemies

		for i = 1, #actors do
			local actor = actors[i]
			if actor and actor.enemy and not actor.fake then
				local dps, amount = actor:GetDPS(set)
				if amount > 0 then
					nr = nr + 1

					local d = win:actor(nr, actor, true)
					d.value = amount
					format_valuetext(d, mod_cols, total, dps, win.metadata)
				end
			end
		end
	end

	function mod:GetSetSummary(set, win)
		local dps, amount = set:GetEnemyDPS(win and win.class)
		local valuetext = Skada:FormatValueCols(
			mod_cols.Damage and Skada:FormatNumber(amount or 0),
			mod_cols.DPS and Skada:FormatNumber(dps)
		)
		return amount, valuetext
	end

	function mod:OnEnable()
		spelltargetmod.metadata = {
			showspots = true,
			click4 = Skada.FilterClass,
			click4_label = L["Toggle Class Filter"]
		}
		targetmod.metadata = {
			showspots = true,
			click1 = targetspellmod,
			click4 = Skada.FilterClass,
			click4_label = L["Toggle Class Filter"]
		}
		spellmod.metadata = {click1 = spelltargetmod, valueorder = true}
		self.metadata = {
			click1 = targetmod,
			click2 = spellmod,
			columns = {Damage = true, DPS = false, Percent = true, sDPS = false, sPercent = true},
			icon = [[Interface\Icons\spell_shadow_shadowbolt]]
		}

		mod_cols = self.metadata.columns

		-- no total click.
		targetmod.nototal = true
		spellmod.nototal = true

		Skada:RegisterForCL(
			spell_damage,
			{dst_is_interesting = true, src_is_not_interesting = true},
			-- damage events
			"DAMAGE_SHIELD",
			"DAMAGE_SPLIT",
			"RANGE_DAMAGE",
			"SPELL_BUILDING_DAMAGE",
			"SPELL_DAMAGE",
			"SPELL_PERIODIC_DAMAGE",
			"SWING_DAMAGE",
			-- missed events
			"DAMAGE_SHIELD_MISSED",
			"RANGE_MISSED",
			"SPELL_BUILDING_MISSED",
			"SPELL_MISSED",
			"SPELL_PERIODIC_MISSED",
			"SWING_MISSED"
		)

		Skada.RegisterMessage(self, "COMBAT_PLAYER_LEAVE", "CombatLeave")
		Skada:AddMode(self, L["Enemies"])

		-- table of ignored damage/time spells:
		if Skada.ignored_spells then
			if Skada.ignored_spells.damaged then
				ignored_spells = Skada.ignored_spells.damaged
			end
			if Skada.ignored_spells.activeTime then
				passive_spells = Skada.ignored_spells.activeTime
			end
		end
	end

	function mod:OnDisable()
		Skada.UnregisterAllMessages(self)
		Skada:RemoveMode(self)
	end

	function mod:CombatLeave()
		wipe(dmg)
	end

	---------------------------------------------------------------------------

	function setPrototype:GetEnemyDamage(class)
		return P.absdamage and self:GetTotal(class, nil, "etotaldamage") or self:GetTotal(class, nil, "edamage")
	end

	function setPrototype:GetEnemyDPS(class)
		local total = self:GetEnemyDamage(class)
		if not total or total == 0 then
			return 0, total
		end
		return total / self:GetTime(), total
	end

	function enemyPrototype:GetDamageTargetSpells(name, tbl)
		local spells = name and self.damagespells
		if not spells then return end

		tbl = clear(tbl or C)

		local total = 0
		for spellid, spell in pairs(spells) do
			local amount = spell.targets and spell.targets[name] and (P.absdamage and spell.targets[name].total or spell.targets[name].amount)
			if amount then
				local t = tbl[spellid]
				if not tbl[spellid] then
					t = new()
					t.amount = amount
					tbl[spellid] = t
				else
					t.amount = t.amount + amount
				end

				total = total + amount
			end
		end
		return tbl, total
	end

	function enemyPrototype:GetDamageSpellTargets(set, spellid, tbl)
		local spell = set and spellid and self.damagespells and self.damagespells[spellid]
		if not spell or not spell.targets then return end

		tbl = clear(tbl or C)

		local total = P.absdamage and spell.total or spell.amount or 0
		for name, target in pairs(spell.targets) do
			local amount = P.absdamage and target.total or target.amount
			local t = tbl[name]
			if not t then
				t = new()
				t.amount = amount
				tbl[name] = t
			else
				t.amount = t.amount + amount
			end
			set:_fill_actor_table(t, name)
		end
		return tbl, total
	end
end)

---------------------------------------------------------------------------
-- Enemy Healing Done

Skada:RegisterModule("Enemy Healing Done", function(L, P)
	local mod = Skada:NewModule("Enemy Healing Done")
	local targetmod = mod:NewModule("Healed target list")
	local spellmod = mod:NewModule("Healing spell list")
	local ignored_spells = Skada.dummyTable -- Edit Skada\Core\Tables.lua
	local passive_spells = Skada.dummyTable -- Edit Skada\Core\Tables.lua
	local mod_cols = nil

	local function format_valuetext(d, columns, total, dps, metadata, subview)
		d.valuetext = Skada:FormatValueCols(
			columns.Healing and Skada:FormatNumber(d.value),
			columns[subview and "sHPS" or "HPS"] and dps and Skada:FormatNumber(dps),
			columns[subview and "sPercent" or "Percent"] and Skada:FormatPercent(d.value, total)
		)

		if metadata and d.value > metadata.maxvalue then
			metadata.maxvalue = d.value
		end
	end

	local function add_actor_time(set, actor, spellid, target)
		if passive_spells[spellid] then
			return -- missing spellid or passive spell?
		elseif not actor.class or not Skada.validclass[actor.class] or actor.role ~= "HEALER" then
			return -- missing/invalid actor class or actor is not a healer?
		else
			Skada:AddActiveTime(set, actor, target)
		end
	end

	local heal = {}
	local function log_heal(set)
		if not set or (set == Skada.total and not P.totalidc) then return end
		if not heal.amount or heal.amount == 0 then return end

		local e = Skada:GetEnemy(set, heal.actorname, heal.actorid, heal.actorflags)
		if not e then
			return
		elseif (set.type == "arena" or set.type == "pvp") then
			add_actor_time(set, e, heal.spell, heal.dstName)
		end

		set.eheal = (set.eheal or 0) + heal.amount
		e.heal = (e.heal or 0) + heal.amount

		local spell = e.healspells and e.healspells[heal.spellid]
		if not spell then
			e.healspells = e.healspells or {}
			e.healspells[heal.spellid] = {amount = heal.amount}
			spell = e.healspells[heal.spellid]
		else
			spell.amount = spell.amount + heal.amount
		end

		if heal.dstName then
			spell.targets = spell.targets or {}
			spell.targets[heal.dstName] = (spell.targets[heal.dstName] or 0) + heal.amount
		end
	end

	local function spell_heal(t)
		if t.spellid and not ignored_spells[t.spellid] then
			heal.actorid = t.srcGUID
			heal.actorname = t.srcName
			heal.actorflags = t.srcFlags
			heal.dstName = t.dstName

			heal.spell = t.spellid
			heal.spellid = t.spellstring
			heal.amount = max(0, t.amount - t.overheal)

			Skada:DispatchSets(log_heal)
		end
	end

	function targetmod:Enter(win, id, label)
		win.targetid, win.targetname = id, label
		win.title = format(L["%s's healed targets"], label)
	end

	function targetmod:Update(win, set)
		win.title = uformat(L["%s's healed targets"], win.targetname)

		local targets, total, actor = set:GetActorHealTargets(win.targetid, win.targetname)
		if not targets or not actor or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actortime = mod_cols.sHPS and actor:GetTime(set)

		for targetname, target in pairs(targets) do
			nr = nr + 1

			local d = win:actor(nr, target, true, targetname)
			d.value = target.amount
			format_valuetext(d, mod_cols, total, actortime and (d.value / actortime), win.metadata, true)
		end
	end

	function spellmod:Enter(win, id, label)
		win.targetid, win.targetname = id, label
		win.title = L["actor heal spells"](label)
	end

	function spellmod:Update(win, set)
		win.title = L["actor heal spells"](win.targetname or L["Unknown"])

		local actor = set and set:GetEnemy(win.targetname, win.targetid)
		local total = actor and actor.heal
		local spells = (total and total > 0) and actor.healspells

		if not spells then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actortime = mod_cols.sHPS and actor:GetTime(set)

		for spellid, spell in pairs(spells) do
			nr = nr + 1

			local d = win:spell(nr, spellid, true)
			d.value = spell.amount
			format_valuetext(d, mod_cols, total, actortime and (d.value / actortime), win.metadata, true)
		end
	end

	function mod:Update(win, set)
		win.title = L["Enemy Healing Done"]
		if win.class then
			win.title = format("%s (%s)", win.title, L[win.class])
		end

		local total = set and set:GetHeal(win.class, true)
		if not total or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actors = set.actors -- enemies

		for i = 1, #actors do
			local actor = actors[i]
			if actor and actor.enemy and not actor.fake then
				local hps, amount = actor:GetHPS(set)
				if amount > 0 then
					nr = nr + 1

					local d = win:actor(nr, actor, true)
					d.value = amount
					format_valuetext(d, mod_cols, total, hps, win.metadata)
				end
			end
		end
	end

	function mod:GetSetSummary(set, win)
		local hps, amount = set:GetHPS(win and win.class, true)
		local valuetext = Skada:FormatValueCols(
			mod_cols.Healing and Skada:FormatNumber(amount or 0),
			mod_cols.HPS and Skada:FormatNumber(hps)
		)
		return amount, valuetext
	end

	function mod:OnEnable()
		spellmod.metadata = {valueorder = true}
		self.metadata = {
			showspots = true,
			click1 = spellmod,
			click2 = targetmod,
			click4 = Skada.FilterClass,
			click4_label = L["Toggle Class Filter"],
			columns = {Healing = true, HPS = true, Percent = true, sHPS = false, sPercent = true},
			icon = [[Interface\Icons\spell_holy_blessedlife]]
		}

		mod_cols = self.metadata.columns

		-- no total click.
		spellmod.nototal = true
		targetmod.nototal = true

		Skada:RegisterForCL(
			spell_heal,
			{src_is_not_interesting = true, dst_is_not_interesting = true},
			"SPELL_HEAL",
			"SPELL_PERIODIC_HEAL"
		)

		Skada.RegisterMessage(self, "COMBAT_PLAYER_LEAVE", "CombatLeave")
		Skada:AddMode(self, L["Enemies"])

		-- table of ignored heal/time spells:
		if Skada.ignored_spells then
			if Skada.ignored_spells.heals then
				ignored_spells = Skada.ignored_spells.heals
			end
			if Skada.ignored_spells.activeTime then
				passive_spells = Skada.ignored_spells.activeTime
			end
		end
	end

	function mod:OnDisable()
		Skada.UnregisterAllMessages(self)
		Skada:RemoveMode(self)
	end

	function mod:CombatLeave()
		wipe(heal)
	end
end)
