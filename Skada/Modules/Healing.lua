local _, Skada = ...
local Private = Skada.Private

-- cache frequently used globals
local pairs, max = pairs, math.max
local format, uformat = string.format, Private.uformat

local function format_valuetext(d, columns, total, hps, metadata, subview)
	d.valuetext = Skada:FormatValueCols(
		columns.Healing and Skada:FormatNumber(d.value),
		columns[subview and "sHPS" or "HPS"] and hps and Skada:FormatNumber(hps),
		columns[subview and "sPercent" or "Percent"] and Skada:FormatPercent(d.value, total)
	)

	if metadata and d.value > metadata.maxvalue then
		metadata.maxvalue = d.value
	end
end

-- ============== --
-- Healing module --
-- ============== --

Skada:RegisterModule("Healing", function(L, P)
	local mod = Skada:NewModule("Healing")
	local playermod = mod:NewModule("Healing spell list")
	local targetmod = mod:NewModule("Healed target list")
	local spellmod = targetmod:NewModule("Healing spell list")
	local spellschools = Skada.spellschools
	local ignoredSpells = Skada.dummyTable -- Edit Skada\Core\Tables.lua
	local passiveSpells = Skada.dummyTable -- Edit Skada\Core\Tables.lua
	local wipe, del, clear = wipe, Private.delTable, Private.clearTable
	local mod_cols = nil

	local function log_spellcast(set, actorid, actorname, actorflags, spellid, spellschool)
		if not set or (set == Skada.total and not P.totalidc) then return end

		local player = Skada:FindPlayer(set, actorid, actorname, actorflags)
		if player and player.healspells and player.healspells[spellid] then
			-- because some HoTs don't have an initial amount
			-- we start from 1 and not from 0 if casts wasn't
			-- previously set. Otherwise we just increment.
			player.healspells[spellid].casts = (player.healspells[spellid].casts or 1) + 1

			-- fix possible missing spell school.
			if not player.healspells[spellid].school and spellschool then
				player.healspells[spellid].school = spellschool
			end
		end
	end

	local heal = {}
	local function log_heal(set, ishot)
		if not heal.spellid or not heal.amount then return end

		local player = Skada:GetPlayer(set, heal.actorid, heal.actorname, heal.actorflags)
		if not player then return end

		-- get rid of overheal
		local amount = max(0, heal.amount - heal.overheal)
		if player.role == "HEALER" and amount > 0 and not heal.petname and not passiveSpells[heal.spellid] then
			Skada:AddActiveTime(set, player, heal.dstName)
		end

		-- record the healing
		player.heal = (player.heal or 0) + amount
		set.heal = (set.heal or 0) + amount

		-- record the overheal
		local overheal = (heal.overheal > 0) and heal.overheal or nil
		if overheal then
			player.overheal = (player.overheal or 0) + overheal
			set.overheal = (set.overheal or 0) + overheal
		end

		-- saving this to total set may become a memory hog deluxe.
		if set == Skada.total and not P.totalidc then return end

		-- record the spell
		local spell = player.healspells and player.healspells[heal.spellid]
		if not spell then
			player.healspells = player.healspells or {}
			player.healspells[heal.spellid] = {school = heal.school, amount = 0}
			spell = player.healspells[heal.spellid]
		elseif not spell.school and heal.school then
			spell.school = heal.school
		end

		spell.count = (spell.count or 0) + 1
		spell.amount = spell.amount + amount

		if overheal then
			spell.o_amt = (spell.o_amt or 0) + overheal
		end

		if (not spell.min or amount < spell.min) and amount > 0 then
			spell.min = amount
		end
		if (not spell.max or amount > spell.max) and amount > 0 then
			spell.max = amount
		end

		if heal.critical then
			spell.c_num = (spell.c_num or 0) + 1
			spell.c_amt = (spell.c_amt or 0) + amount

			if not spell.c_max or amount > spell.c_max then
				spell.c_max = amount
			end

			if not spell.c_min or amount < spell.c_min then
				spell.c_min = amount
			end
		end

		-- record the target
		if not heal.dstName then return end
		local target = spell.targets and spell.targets[heal.dstName]
		if not target then
			spell.targets = spell.targets or {}
			spell.targets[heal.dstName] = {amount = 0}
			target = spell.targets[heal.dstName]
		end
		target.amount = target.amount + amount

		if overheal then
			target.o_amt = (target.o_amt or 0) + overheal
		end
	end

	local function spell_cast(_, _, srcGUID, srcName, srcFlags, dstGUID, _, _, spellid, _, spellschool)
		if srcGUID and dstGUID and spellid and not ignoredSpells[spellid] then
			srcGUID, srcName = Skada:FixMyPets(srcGUID, srcName, srcFlags)
			Skada:DispatchSets(log_spellcast, srcGUID, srcName, srcFlags, spellid, spellschool)
		end
	end

	local function spell_heal(_, eventtype, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, spellid, ...)
		if not spellid or ignoredSpells[spellid] then return end

		heal.actorid, heal.actorname, heal.actorflags = Skada:FixMyPets(srcGUID, srcName, srcFlags)
		heal.dstName = Skada:FixPetsName(dstGUID, dstName, dstFlags)

		heal.spellid = (eventtype == "SPELL_PERIODIC_HEAL") and -spellid or spellid
		_, heal.school, heal.amount, heal.overheal, _, heal.critical = ...

		Skada:DispatchSets(log_heal)
	end

	local function healing_tooltip(win, id, label, tooltip)
		local set = win:GetSelectedSet()
		local actor = set and set:GetActor(label, id)
		if not actor then return end

		local totaltime = set:GetTime()
		local activetime = actor:GetTime(set, true)
		local hps, amount = actor:GetHPS(set)

		tooltip:AddDoubleLine(L["Activity"], Skada:FormatPercent(activetime, totaltime), nil, nil, nil, 1, 1, 1)
		tooltip:AddDoubleLine(L["Segment Time"], Skada:FormatTime(totaltime), 1, 1, 1)
		tooltip:AddDoubleLine(L["Active Time"], Skada:FormatTime(activetime), 1, 1, 1)
		tooltip:AddDoubleLine(L["Healing"], Skada:FormatNumber(amount), 1, 1, 1)

		local suffix = Skada:FormatTime(P.timemesure == 1 and activetime or totaltime)
		tooltip:AddDoubleLine(Skada:FormatNumber(amount) .. "/" .. suffix, Skada:FormatNumber(hps), 1, 1, 1)
	end

	local function playermod_tooltip(win, id, label, tooltip)
		local set = win:GetSelectedSet()
		if not set then return end

		local actor = set:GetActor(win.actorname, win.actorid)
		local spell = actor and actor.healspells and actor.healspells[id]
		if not spell then return end

		tooltip:AddLine(actor.name .. " - " .. label)
		if spell.school and spellschools[spell.school] then
			tooltip:AddLine(spellschools(spell.school))
		end

		if spell.casts and spell.casts > 0 then
			tooltip:AddDoubleLine(L["Casts"], spell.casts, 1, 1, 1)
		end

		local average = nil
		if spell.count and spell.count > 0 then
			tooltip:AddDoubleLine(L["Hits"], spell.count, 1, 1, 1)
			average = spell.amount / spell.count

			if spell.c_num and spell.c_num > 0 then
				tooltip:AddDoubleLine(L["Critical"], Skada:FormatPercent(spell.c_num, spell.count), 0.67, 1, 0.67)
			end

			if spell.o_amt and spell.o_amt > 0 then
				tooltip:AddDoubleLine(L["Overheal"], Skada:FormatPercent(spell.o_amt, spell.o_amt + spell.amount), 1, 0.67, 0.67)
			end
		end

		local separator = nil

		if spell.min then
			tooltip:AddLine(" ")
			separator = true

			local spellmin = spell.min
			if spell.c_min and spell.c_min < spellmin then
				spellmin = spell.c_min
			end
			tooltip:AddDoubleLine(L["Minimum"], Skada:FormatNumber(spellmin), 1, 1, 1)
		end

		if spell.max then
			if not separator then
				tooltip:AddLine(" ")
				separator = true
			end

			local spellmax = spell.max
			if spell.c_max and spell.c_max > spellmax then
				spellmax = spell.c_max
			end
			tooltip:AddDoubleLine(L["Maximum"], Skada:FormatNumber(spellmax), 1, 1, 1)
		end

		if average then
			if not separator then
				tooltip:AddLine(" ")
				separator = true
			end

			tooltip:AddDoubleLine(L["Average"], Skada:FormatNumber(average), 1, 1, 1)
		end
	end

	function spellmod:Enter(win, id, label)
		win.targetid, win.targetname = id, label
		win.title = L["actor heal spells"](win.actorname or L["Unknown"], label)
	end

	function spellmod:Update(win, set)
		win.title = L["actor heal spells"](win.actorname or L["Unknown"], win.targetname or L["Unknown"])
		if not set or not win.targetname then return end

		local actor, enemy = set:GetActor(win.actorname, win.actorid)
		local total = actor and actor:GetHealOnTarget(win.targetname)
		local spells = (total and total > 0) and actor.healspells

		if not spells then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actortime = mod_cols.sHPS and actor:GetTime(set)

		for spellid, spell in pairs(spells) do
			local tar = spell.targets and spell.targets[win.targetname]
			local amount = tar and (enemy and tar or tar.amount)
			if amount then
				nr = nr + 1

				local d = win:spell(nr, spellid, spell, nil, true)
				d.value = amount
				format_valuetext(d, mod_cols, total, actortime and (d.value / actortime), win.metadata, true)
			end
		end
	end

	function playermod:Enter(win, id, label)
		win.actorid, win.actorname = id, label
		win.title = L["actor heal spells"](label)
	end

	function playermod:Update(win, set)
		win.title = L["actor heal spells"](win.actorname or L["Unknown"])
		if not set or not win.actorname then return end

		local actor, enemy = set:GetActor(win.actorname, win.actorid)
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

			local d = win:spell(nr, spellid, spell, nil, true)
			d.value = spell.amount
			format_valuetext(d, mod_cols, total, actortime and (d.value / actortime), win.metadata, true)
		end
	end

	function targetmod:Enter(win, id, label)
		win.actorid, win.actorname = id, label
		win.title = format(L["%s's healed targets"], label)
	end

	function targetmod:Update(win, set)
		win.title = uformat(L["%s's healed targets"], win.actorname)

		local targets, total, actor = set:GetActorHealTargets(win.actorid, win.actorname)
		if not targets or not actor or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actortime = mod_cols.sHPS and actor:GetTime(set)

		for targetname, target in pairs(targets) do
			nr = nr + 1

			local d = win:actor(nr, target, nil, targetname)
			d.value = target.amount
			format_valuetext(d, mod_cols, total, actortime and (d.value / actortime), win.metadata, true)
		end
	end

	function mod:Update(win, set)
		win.title = win.class and format("%s (%s)", L["Healing"], L[win.class]) or L["Healing"]

		local total = set and set:GetHeal(win.class)
		if not total or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actors = set.actors

		for i = 1, #actors do
			local actor = actors[i]
			if win:show_actor(actor, set, true) and actor.heal then
				local hps, amount = actor:GetHPS(set, nil, not mod_cols.sHPS)
				if amount > 0 then
					nr = nr + 1

					local d = win:actor(nr, actor, actor.enemy)
					d.value = amount
					format_valuetext(d, mod_cols, total, hps, win.metadata)
					win:color(d, set, actor.enemy)
				end
			end
		end
	end

	function mod:GetSetSummary(set, win)
		local hps, amount = set:GetHPS(win and win.class)
		local valuetext = Skada:FormatValueCols(
			mod_cols.Healing and Skada:FormatNumber(amount),
			mod_cols.HPS and Skada:FormatNumber(hps)
		)
		return amount, valuetext
	end

	function mod:OnEnable()
		playermod.metadata = {tooltip = playermod_tooltip}
		targetmod.metadata = {showspots = true, click1 = spellmod}
		self.metadata = {
			showspots = true,
			post_tooltip = healing_tooltip,
			click1 = playermod,
			click2 = targetmod,
			click4 = Skada.FilterClass,
			click4_label = L["Toggle Class Filter"],
			columns = {Healing = true, HPS = true, Percent = true, sHPS = false, sPercent = true},
			icon = [[Interface\Icons\spell_nature_healingtouch]]
		}

		mod_cols = self.metadata.columns

		-- no total click.
		playermod.nototal = true
		targetmod.nototal = true

		local flags_src = {src_is_interesting = true}

		Skada:RegisterForCL(
			spell_cast,
			flags_src,
			"SPELL_CAST_START",
			"SPELL_CAST_SUCCESS"
		)

		Skada:RegisterForCL(
			spell_heal,
			flags_src,
			"SPELL_HEAL",
			"SPELL_PERIODIC_HEAL"
		)

		Skada.RegisterMessage(self, "COMBAT_PLAYER_LEAVE", "CombatLeave")
		Skada:AddMode(self, L["Absorbs and Healing"])

		-- table of ignored spells:
		if Skada.ignoredSpells then
			if Skada.ignoredSpells.heals then
				ignoredSpells = Skada.ignoredSpells.heals
			end
			if Skada.ignoredSpells.activeTime then
				passiveSpells = Skada.ignoredSpells.activeTime
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

	function mod:SetComplete(set)
		local total = (set.heal or 0) + (set.overheal or 0)
		if total == 0 then return end

		-- clean healspells table!
		for i = 1, #set.actors do
			local actor = set.actors[i]
			local amount = actor and not actor.enemy and ((actor.heal or 0) + (actor.overheal or 0))
			if (actor and not amount and actor.healspells) or amount == 0 then
				actor.heal, actor.overheal = nil, nil
				actor.healspells = del(actor.healspells, true)
			end
		end
	end
end)

-- ================== --
-- Overhealing module --
-- ================== --

Skada:RegisterModule("Overhealing", function(L)
	local mod = Skada:NewModule("Overhealing")
	local playermod = mod:NewModule("Overheal spell list")
	local targetmod = mod:NewModule("Overhealed target list")
	local spellmod = targetmod:NewModule("Overheal spell list")
	local mod_cols = nil

	local function fmt_valuetext(d, columns, total, dps, metadata, subview)
		d.valuetext = Skada:FormatValueCols(
			columns.Overhealing and Skada:FormatNumber(d.value),
			columns[subview and "sHPS" or "HPS"] and Skada:FormatNumber(dps),
			columns[subview and "sPercent" or "Percent"] and Skada:FormatPercent(d.value, total)
		)

		if metadata and d.value > metadata.maxvalue then
			metadata.maxvalue = d.value
		end
	end

	function spellmod:Enter(win, id, label)
		win.targetid, win.targetname = id, label
		win.title = L["actor overheal spells"](win.actorname or L["Unknown"], label)
	end

	function spellmod:Update(win, set)
		win.title = L["actor overheal spells"](win.actorname or L["Unknown"], win.targetname or L["Unknown"])
		if not set or not win.targetname then return end

		local actor, enemy = set:GetActor(win.actorname, win.actorid)
		if not actor or enemy then return end

		local spells, total = actor:GetOverhealSpellsOnTarget(win.targetname)
		if not spells or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actortime = mod_cols.sHPS and actor:GetTime(set)

		for spellid, spell in pairs(spells) do
			nr = nr + 1

			local d = win:spell(nr, spellid, spell, nil, true)
			d.value = spell.o_amt
			fmt_valuetext(d, mod.metadata.columns, spell.amount + d.value, actortime and (d.value / actortime), win.metadata, true)
		end
	end

	function playermod:Enter(win, id, label)
		win.actorid, win.actorname = id, label
		win.title = L["actor overheal spells"](label)
	end

	function playermod:Update(win, set)
		win.title = L["actor overheal spells"](win.actorname or L["Unknown"])
		if not set or not win.actorname then return end

		local actor, enemy = set:GetActor(win.actorname, win.actorid)
		if not actor or enemy then return end

		local spells, total = actor:GetOverhealSpells()
		if not spells or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actortime = mod_cols.sHPS and actor:GetTime(set)

		for spellid, spell in pairs(spells) do
			nr = nr + 1

			local d = win:spell(nr, spellid, spell, nil, true)
			d.value = spell.o_amt
			fmt_valuetext(d, mod_cols, spell.amount + d.value, actortime and (d.value / actortime), win.metadata, true)
		end
	end

	function targetmod:Enter(win, id, label)
		win.actorid, win.actorname = id, label
		win.title = format(L["%s's overheal targets"], label)
	end

	function targetmod:Update(win, set)
		win.title = uformat(L["%s's overheal targets"], win.actorname)
		if not set or not win.actorname then return end

		local actor, enemy = set:GetActor(win.actorname, win.actorid)
		local total = actor and actor.overheal
		local targets = (total and total > 0) and actor:GetOverhealTargets(set)

		if not targets then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actortime = mod_cols.sHPS and actor:GetTime(set)

		for targetname, target in pairs(targets) do
			nr = nr + 1

			local d = win:actor(nr, target, nil, targetname)
			d.value = target.amount
			fmt_valuetext(d, mod_cols, total, actortime and (d.value / actortime), win.metadata, true)
		end
	end

	function mod:Update(win, set)
		win.title = win.class and format("%s (%s)", L["Overhealing"], L[win.class]) or L["Overhealing"]

		local total = set and set:GetOverheal(win.class)
		if not total or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actors = set.actors

		for i = 1, #actors do
			local actor = actors[i]
			if win:show_actor(actor, set, true) and actor.overheal then
				local ohps, overheal = actor:GetOHPS(set, nil, not mod_cols.HPS)
				if overheal > 0 then
					nr = nr + 1

					local d = win:actor(nr, actor, actor.enemy)
					d.value = actor.overheal
					fmt_valuetext(d, mod_cols, actor.heal + d.value, ohps, win.metadata)
				end
			end
		end
	end

	function mod:GetSetSummary(set, win)
		local ohps, overheal = set:GetOHPS(win and win.class)
		local valuetext = Skada:FormatValueCols(
			mod_cols.Overhealing and Skada:FormatNumber(overheal),
			mod_cols.HPS and Skada:FormatNumber(ohps)
		)
		return overheal, valuetext
	end

	function mod:OnEnable()
		targetmod.metadata = {click1 = spellmod}
		self.metadata = {
			showspots = true,
			click1 = playermod,
			click2 = targetmod,
			click4 = Skada.FilterClass,
			click4_label = L["Toggle Class Filter"],
			columns = {Overhealing = true, HPS = true, Percent = true, sHPS = false, sPercent = true},
			icon = [[Interface\Icons\spell_holy_holybolt]]
		}

		mod_cols = self.metadata.columns

		-- no total click.
		playermod.nototal = true
		targetmod.nototal = true

		Skada:AddMode(self, L["Absorbs and Healing"])
	end

	function mod:OnDisable()
		Skada:RemoveMode(self)
	end
end, "Healing")

-- ==================== --
-- Total healing module --
-- ==================== --

Skada:RegisterModule("Total Healing", function(L)
	local mod = Skada:NewModule("Total Healing")
	local playermod = mod:NewModule("Healing spell list")
	local targetmod = mod:NewModule("Healed target list")
	local spellmod = targetmod:NewModule("Healing spell list")
	local spellschools = Skada.spellschools
	local mod_cols = nil

	local function spell_tooltip(win, id, label, tooltip)
		local set = win:GetSelectedSet()
		local actor = set and set:GetActor(win.actorname, win.actorid)
		local spell = actor and actor.healspells and actor.healspells[id]
		if not spell then return end

		tooltip:AddLine(actor.name .. " - " .. label)
		if spell.school and spellschools[spell.school] then
			tooltip:AddLine(spellschools(spell.school))
		end

		if spell.casts then
			tooltip:AddDoubleLine(L["Casts"], spell.casts, 1, 1, 1)
		end

		local total = spell.amount + (spell.o_amt or 0)
		tooltip:AddDoubleLine(L["Total"], Skada:FormatNumber(total), 1, 1, 1)
		if spell.amount > 0 then
			tooltip:AddDoubleLine(L["Healing"], format("%s (%s)", Skada:FormatNumber(spell.amount), Skada:FormatPercent(spell.amount, total)), 0.67, 1, 0.67)
		end
		if spell.o_amt and spell.o_amt > 0 then
			tooltip:AddDoubleLine(L["Overheal"], format("%s (%s)", Skada:FormatNumber(spell.o_amt), Skada:FormatPercent(spell.o_amt, total)), 1, 0.67, 0.67)
		end

		local separator = nil

		if spell.min then
			tooltip:AddLine(" ")
			separator = true

			local spellmin = spell.min
			if spell.c_min and spell.c_min < spellmin then
				spellmin = spell.c_min
			end
			tooltip:AddDoubleLine(L["Minimum"], Skada:FormatNumber(spellmin), 1, 1, 1)
		end

		if spell.max then
			if not separator then
				tooltip:AddLine(" ")
				separator = true
			end

			local spellmax = spell.max
			if spell.c_max and spell.c_max > spellmax then
				spellmax = spell.c_max
			end
			tooltip:AddDoubleLine(L["Maximum"], Skada:FormatNumber(spellmax), 1, 1, 1)
		end

		if spell.count and spell.count > 0 then
			if not separator then
				tooltip:AddLine(" ")
				separator = true
			end

			tooltip:AddDoubleLine(L["Average"], Skada:FormatNumber(spell.amount / spell.count), 1, 1, 1)
		end
	end

	function spellmod:Enter(win, id, label)
		win.targetid, win.targetname = id, label
		win.title = L["actor heal spells"](win.actorname or L["Unknown"], label)
	end

	function spellmod:Update(win, set)
		win.title = L["actor heal spells"](win.actorname or L["Unknown"], win.targetname or L["Unknown"])
		if not set or not win.targetname then return end

		local actor, enemy = set:GetActor(win.actorname, win.actorid)
		local total = actor and actor:GetTotalHealOnTarget(win.targetname)
		local spells = (total and total > 0) and actor.healspells

		if not spells then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actortime = mod_cols.sHPS

		for spellid, spell in pairs(spells) do
			local tar = spell.targets and spell.targets[win.targetname]
			if tar then
				nr = nr + 1

				local d = win:spell(nr, spellid, spell, nil, true)
				d.value = enemy and tar or (tar.amount + (tar.o_amt or 0))
				format_valuetext(d, mod_cols, total, actortime and (d.value / actortime), win.metadata, true)
			end
		end
	end

	function playermod:Enter(win, id, label)
		win.actorid, win.actorname = id, label
		win.title = L["actor heal spells"](label)
	end

	function playermod:Update(win, set)
		win.title = L["actor heal spells"](win.actorname or L["Unknown"])
		if not win.actorname then return end

		local actor = set and set:GetActor(win.actorname, win.actorid)
		local total = actor and actor:GetTotalHeal()
		local spells = (total and total > 0) and actor.healspells

		if not spells then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actortime = mod_cols.sHPS and actor:GetTime(set)

		for spellid, spell in pairs(spells) do
			local amount = spell.amount + (spell.o_amt or 0)
			if amount > 0 then
				nr = nr + 1

				local d = win:spell(nr, spellid, spell, nil, true)
				d.value = amount
				format_valuetext(d, mod_cols, total, actortime and (d.value / actortime), win.metadata, true)
			end
		end
	end

	function targetmod:Enter(win, id, label)
		win.actorid, win.actorname = id, label
		win.title = format(L["%s's healed targets"], label)
	end

	function targetmod:Update(win, set)
		win.title = uformat(L["%s's healed targets"], win.actorname)

		local actor = set and set:GetActor(win.actorname, win.actorid)
		local total = actor and actor:GetTotalHeal()
		local targets = (total and total > 0) and actor:GetTotalHealTargets(set)

		if not targets then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actortime = mod_cols.sHPS and actor:GetTime(set)

		for targetname, target in pairs(targets) do
			nr = nr + 1

			local d = win:actor(nr, target, nil, targetname)
			d.value = target.amount
			format_valuetext(d, mod_cols, total, actortime and (d.value / actortime), win.metadata, true)
		end
	end

	function mod:Update(win, set)
		win.title = win.class and format("%s (%s)", L["Total Healing"], L[win.class]) or L["Total Healing"]

		local total = set and set:GetTotalHeal(win.class)
		if not total or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actors = set.actors

		for i = 1, #actors do
			local actor = actors[i]
			if win:show_actor(actor, set, true) and (actor.heal or actor.overheal) then
				local hps, amount = actor:GetTHPS(set, nil, not mod_cols.HPS)
				if amount > 0 then
					nr = nr + 1

					local d = win:actor(nr, actor, actor.enemy)
					d.value = amount
					format_valuetext(d, mod_cols, total, hps, win.metadata)
					win:color(d, set, actor.enemy)
				end
			end
		end
	end

	function mod:GetSetSummary(set, win)
		local ops, amount = set:GetTHPS(win and win.class)
		local valuetext = Skada:FormatValueCols(
			mod_cols.Healing and Skada:FormatNumber(amount),
			mod_cols.HPS and Skada:FormatNumber(ops)
		)
		return amount, valuetext
	end

	function mod:OnEnable()
		targetmod.metadata = {showspots = true, click1 = spellmod}
		playermod.metadata = {tooltip = spell_tooltip}
		self.metadata = {
			showspots = true,
			click1 = playermod,
			click2 = targetmod,
			click4 = Skada.FilterClass,
			click4_label = L["Toggle Class Filter"],
			columns = {Healing = true, HPS = true, Percent = true, sHPS = false, sPercent = true},
			icon = [[Interface\Icons\spell_holy_flashheal]]
		}

		mod_cols = self.metadata.columns

		-- no total click.
		playermod.nototal = true
		targetmod.nototal = true

		Skada:AddMode(self, L["Absorbs and Healing"])
	end

	function mod:OnDisable()
		Skada:RemoveMode(self)
	end
end, "Healing")

-- ================ --
-- Healing taken --
-- ================ --

Skada:RegisterModule("Healing Taken", function(L, P)
	local mod = Skada:NewModule("Healing Taken")
	local sourcemod = mod:NewModule("Healing source list")
	local sourcespellmod = sourcemod:NewModule("Healing spell list")
	local spellmod = mod:NewModule("Healing spell list")
	local spellsourcemod = sourcemod:NewModule("Healing source list")
	local new, clear = Private.newTable, Private.clearTable
	local C = Skada.cacheTable2
	local mod_cols = nil

	local get_set_healed_actors = nil
	local get_actor_heal_sources = nil
	local get_actor_healed_spells = nil
	local get_actor_heal_spell_sources = nil

	local function healing_tooltip(win, id, label, tooltip)
		local set = win:GetSelectedSet()
		local total = set and set:GetAbsorbHeal()
		local actors = (total and total > 0) and get_set_healed_actors(set)

		local info, actor = nil, nil
		if not actors then
			return
		else
			actor = set:GetActor(label, id)
			if not actor then return end

			for n, p in pairs(actors) do
				if n == label and p.id == id then
					info = p
					break
				end
			end
		end

		local totaltime = set:GetTime()
		local activetime = actor:GetTime(set, true)

		tooltip:AddDoubleLine(L["Activity"], Skada:FormatPercent(activetime, totaltime), nil, nil, nil, 1, 1, 1)
		tooltip:AddDoubleLine(L["Segment Time"], Skada:FormatTime(totaltime), 1, 1, 1)
		tooltip:AddDoubleLine(L["Active Time"], Skada:FormatTime(activetime), 1, 1, 1)
		tooltip:AddDoubleLine(L["Healing Taken"], Skada:FormatNumber(info.amount), 1, 1, 1)

		if P.timemesure == 1 then
			tooltip:AddDoubleLine(Skada:FormatNumber(info.amount) .. "/" .. activetime, Skada:FormatNumber(info.amount / activetime), 1, 1, 1)
		else
			tooltip:AddDoubleLine(Skada:FormatNumber(info.amount) .. "/" .. totaltime, Skada:FormatNumber(info.amount / totaltime), 1, 1, 1)
		end
	end

	function sourcemod:Enter(win, id, label)
		win.actorid, win.actorname = id, label
		win.title = format(L["%s's heal sources"], label)
	end

	function sourcemod:Update(win, set)
		win.title = uformat(L["%s's heal sources"], win.actorname)
		if not set or not win.actorname then return end

		local actor, enemy = set:GetActor(win.actorname, win.actorid, true)
		if not actor or enemy then return end -- unavailable for enemies

		local sources, total = get_actor_heal_sources(actor, set)
		if not sources or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actortime = mod_cols.sHPS and actor:GetTime(set)

		for sourcename, source in pairs(C) do
			nr = nr + 1

			local d = win:actor(nr, source, nil, sourcename)
			d.value = source.amount
			format_valuetext(d, mod_cols, total, actortime and (d.value / actortime), win.metadata, true)
		end
	end

	function spellmod:Enter(win, id, label)
		win.actorid, win.actorname = id, label
		win.title = L["actor heal spells"](label)
	end

	function spellmod:Update(win, set)
		win.title = L["actor heal spells"](win.actorname or L["Unknown"])
		if not set or not win.actorname then return end

		local actor, enemy = set:GetActor(win.actorname, win.actorid, true)
		if not actor or enemy then return end -- unavailable for enemies

		local spells, total = get_actor_healed_spells(actor, set)
		if not spells or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actortime = mod_cols.sHPS and actor:GetTime(set)

		for spellid, spell in pairs(spells) do
			nr = nr + 1

			local d = win:spell(nr, spellid, spell)
			d.value = spell.amount
			format_valuetext(d, mod_cols, total, actortime and (d.value / actortime), win.metadata, true)
		end
	end

	function sourcespellmod:Enter(win, id, label)
		win.targetid, win.targetname = id, label
		win.title = L["actor heal spells"](label, win.actorname or L["Unknown"])
	end

	function sourcespellmod:Update(win, set)
		win.title = L["actor heal spells"](win.targetname or L["Unknown"], win.actorname or L["Unknown"])
		if not set or not win.actorname then return end

		local actor, enemy = set:GetActor(win.targetname, win.targetid)
		if enemy then return end -- unavailable for enemies yet

		local total = actor and actor:GetAbsorbHealOnTarget(win.actorname)
		if not total or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actortime = mod_cols.sHPS and actor:GetTime(set)

		local spells = actor.absorbspells -- absorb spells
		if spells then
			for spellid, spell in pairs(spells) do
				local amt = spell.targets and spell.targets[win.actorname] and spell.targets[win.actorname].amount
				if amt then
					nr = nr + 1

					local d = win:spell(nr, spellid, spell)
					d.value = amt
					format_valuetext(d, mod_cols, total, actortime and (d.value / actortime), win.metadata, true)
				end
			end
		end

		if actor.healspells then
			for spellid, spell in pairs(actor.healspells) do
				local tar = spell.targets and spell.targets[win.actorname]
				if tar then
					nr = nr + 1

					local d = win:spell(nr, spellid, spell, nil, true)
					d.value = enemy and tar or tar.amount
					format_valuetext(d, mod_cols, total, actortime and (d.value / actortime), win.metadata, true)
				end
			end
		end
	end

	function spellsourcemod:Enter(win, id, label)
		win.spellid, win.spellname = id, label
		win.title = uformat(L["%s's <%s> sources"], win.actorname, label)
	end

	function spellsourcemod:Update(win, set)
		win.title = uformat(L["%s's <%s> sources"], win.actorname, win.spellname)
		if not set or not win.actorname or not win.spellid then return end

		local actor, enemy = set:GetActor(win.actorname, win.actorid, true)
		if not actor or enemy then return end

		local sources, total = get_actor_heal_spell_sources(actor, set, win.spellid)
		if not sources or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actortime = mod_cols.sHPS and actor:GetTime(set)

		for sourcename, source in pairs(sources) do
			nr = nr + 1

			local d = win:actor(nr, source, nil, sourcename)
			d.value = source.amount
			format_valuetext(d, mod_cols, total, actortime and (d.value / actortime), win.metadata, true)
		end
	end

	function mod:Update(win, set)
		win.title = win.class and format("%s (%s)", L["Healing Taken"], L[win.class]) or L["Healing Taken"]

		local total = set and set:GetAbsorbHeal()
		local actors = (total and total > 0) and get_set_healed_actors(set)

		if not actors then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local settime = set:GetTime()

		for actorname, actor in pairs(actors) do
			if not win.class or win.class == actor.class then
				nr = nr + 1

				local d = win:actor(nr, actor, actor.enemy, actorname)
				d.value = actor.amount
				format_valuetext(d, mod_cols, total, d.value / (actor.time or settime), win.metadata)
			end
		end
	end

	function mod:OnEnable()
		spellsourcemod.metadata = {showspots = true}
		sourcemod.metadata = {showspots = true, click1 = sourcespellmod}
		spellmod.metadata = {click1 = spellsourcemod}
		self.metadata = {
			showspots = true,
			post_tooltip = healing_tooltip,
			click1 = sourcemod,
			click2 = spellmod,
			click4 = Skada.FilterClass,
			click4_label = L["Toggle Class Filter"],
			columns = {Healing = true, HPS = true, Percent = true, sHPS = false, sPercent = true},
			icon = [[Interface\Icons\spell_nature_resistnature]]
		}

		mod_cols = self.metadata.columns

		Skada:AddMode(self, L["Absorbs and Healing"])
	end

	function mod:OnDisable()
		Skada:RemoveMode(self)
	end

	---------------------------------------------------------------------------

	get_set_healed_actors = function(self, tbl)
		local total = (self.heal or 0) + (self.absorb or 0)
		if self.arena then
			total = total + (self.eheal or 0) + (self.eabsorb or 0)
		end
		if total == 0 then return end

		tbl = clear(tbl or C)

		local actors = self.actors
		for i = 1, #actors do
			local actor = actors[i]

			local spells = actor and (not actor.enemy or self.arena) and actor.absorbspells -- absorb spells
			if spells then
				for _, spell in pairs(spells) do
					if spell.targets then
						for name, target in pairs(spell.targets) do
							if target.amount > 0 then
								local t = tbl[name]
								if not t then
									t = new()
									t.amount = target.amount
									tbl[name] = t
								else
									t.amount = t.amount + target.amount
								end

								self:_fill_actor_table(t, name, true)
							end
						end
					end
				end
			end

			spells = actor and (not actor.enemy or self.arena) and actor.healspells -- heal spells
			if spells then
				for _, spell in pairs(spells) do
					if spell.targets then
						for name, target in pairs(spell.targets) do
							if target.amount > 0 then
								local t = tbl[name]
								if not t then
									t = new()
									t.amount = target.amount
									tbl[name] = t
								else
									t.amount = t.amount + target.amount
								end

								self:_fill_actor_table(t, name, true)
							end
						end
					end
				end
			end
		end

		return tbl, total
	end

	get_actor_heal_sources = function(self, set, tbl)
		if not set or not set.actors then return end

		tbl = clear(tbl or C)
		local total = 0

		local actors = set.actors
		for i = 1, #actors do
			local actor = actors[i]

			local spells = actor and (not actor.enemy or set.arena) and actor.absorbspells -- absorb spells
			if spells then
				for spellid, spell in pairs(spells) do
					local amount = spell.targets and spell.targets[self.name] and spell.targets[self.name].amount
					if amount and amount > 0 then
						total = total + amount

						local t = tbl[actor.name]
						if not t then
							t = new()
							t.id = actor.id
							t.class = actor.class
							t.role = actor.role
							t.spec = actor.spec
							t.enemy = actor.enemy
							t.amount = amount
							tbl[actor.name] = t
						else
							t.amount = t.amount + amount
						end
					end
				end
			end

			spells = actor and (not actor.enemy or set.arena) and actor.healspells -- heal spells
			if spells then
				for spellid, spell in pairs(spells) do
					local amount = spell.targets and spell.targets[self.name] and spell.targets[self.name].amount
					if amount and amount > 0 then
						total = total + amount

						local t = tbl[actor.name]
						if not t then
							t = new()
							t.id = actor.id
							t.class = actor.class
							t.role = actor.role
							t.spec = actor.spec
							t.enemy = actor.enemy
							t.amount = amount
							tbl[actor.name] = t
						else
							t.amount = t.amount + amount
						end
					end
				end
			end
		end

		return tbl, total
	end

	get_actor_healed_spells = function(self, set, tbl)
		if not set or not set.actors then return end

		tbl = clear(tbl or C)
		local total = 0

		local actors = set.actors
		for i = 1, #actors do
			local actor = actors[i]

			local spells = actor and (not actor.enemy or set.arena) and actor.absorbspells -- absorb spells
			if spells then
				for spellid, spell in pairs(spells) do
					local amount = spell.targets and spell.targets[self.name] and spell.targets[self.name].amount
					if amount and amount > 0 then
						total = total + amount

						local t = tbl[spellid]
						if not t then
							t = new()
							t.school = spell.school
							t.amount = amount
							tbl[spellid] = t
						else
							t.amount = t.amount + amount
						end
					end
				end
			end

			spells = actor and (not actor.enemy or set.arena) and actor.healspells -- heal spells
			if spells then
				for spellid, spell in pairs(spells) do
					local amount = spell.targets and spell.targets[self.name] and spell.targets[self.name].amount
					if amount and amount > 0 then
						total = total + amount

						local t = tbl[spellid]
						if not t then
							t = new()
							t.school = spell.school
							t.amount = amount
							tbl[spellid] = t
						else
							t.amount = t.amount + amount
						end
					end
				end
			end
		end

		return tbl, total
	end

	get_actor_heal_spell_sources = function(self, set, spellid)
		if not set or not set.actors or not spellid then return end

		tbl = clear(tbl or C)
		local total = 0

		local actors = set.actors
		for i = 1, #actors do
			local actor = actors[i]

			local spells = actor and (not actor.enemy or set.arena) and actor.absorbspells -- absorb spells
			if spells then
				for id, spell in pairs(spells) do
					local amount = (id == spellid) and spell.targets and spell.targets[self.name] and spell.targets[self.name].amount
					if amount and amount > 0 then
						total = total + amount

						local t = tbl[actor.name]
						if not t then
							t = new()
							t.id = actor.id
							t.class = actor.class
							t.role = actor.role
							t.spec = actor.spec
							t.enemy = actor.enemy
							t.amount = amount
							tbl[actor.name] = t
						else
							t.amount = t.amount + amount
						end
					end
				end
			end

			spells = actor and (not actor.enemy or set.arena) and actor.healspells -- heal spells
			if spells then
				for id, spell in pairs(spells) do
					local amount = (id == spellid) and spell.targets and spell.targets[self.name] and spell.targets[self.name].amount
					if amount and amount > 0 then
						total = total + amount

						local t = tbl[actor.name]
						if not t then
							t = new()
							t.id = actor.id
							t.class = actor.class
							t.role = actor.role
							t.spec = actor.spec
							t.enemy = actor.enemy
							t.amount = amount
							tbl[actor.name] = t
						else
							t.amount = t.amount + amount
						end
					end
				end
			end
		end

		return tbl, total
	end
end, "Absorbs", "Healing")
