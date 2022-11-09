local _, Skada = ...
local Private = Skada.Private

local pairs, format, uformat = pairs, string.format, Private.uformat
local GetSpellLink = Private.spell_link or GetSpellLink
local new, clear = Private.newTable, Private.clearTable
local cc_table = {} -- holds stuff from cleu

local function format_valuetext(d, columns, total, metadata, subview)
	d.valuetext = Skada:FormatValueCols(
		columns.Count and d.value,
		columns[subview and "sPercent" or "Percent"] and Skada:FormatPercent(d.value, total)
	)

	if metadata and d.value > metadata.maxvalue then
		metadata.maxvalue = d.value
	end
end

-- ======= --
-- CC Done --
-- ======= --
Skada:RegisterModule("CC Done", function(L, P, _, C)
	local mod = Skada:NewModule("CC Done")
	local playermod = mod:NewModule("Crowd Control Spells")
	local targetmod = mod:NewModule("Crowd Control Targets")
	local sourcemod = playermod:NewModule("Crowd Control Sources")
	local cc_spells = Skada.extra_cc_spells -- extended list
	local get_actor_cc_targets = nil
	local get_cc_done_sources = nil
	local mod_cols = nil

	local function log_ccdone(set)
		local player = Skada:GetPlayer(set, cc_table.actorid, cc_table.actorname, cc_table.actorflags)
		if not player then return end

		-- increment the count.
		player.ccdone = (player.ccdone or 0) + 1
		set.ccdone = (set.ccdone or 0) + 1

		-- saving this to total set may become a memory hog deluxe.
		if set == Skada.total and not P.totalidc then return end

		-- record the spell.
		local spell = player.ccdonespells and player.ccdonespells[cc_table.spellid]
		if not spell then
			player.ccdonespells = player.ccdonespells or {}
			player.ccdonespells[cc_table.spellid] = {count = 0}
			spell = player.ccdonespells[cc_table.spellid]
		end
		spell.count = spell.count + 1

		-- record the target.
		if cc_table.dstName then
			spell.targets = spell.targets or {}
			spell.targets[cc_table.dstName] = (spell.targets[cc_table.dstName] or 0) + 1
		end
	end

	local function aura_applied(t)
		if t.spellid and cc_spells[t.spellid] then
			cc_table.actorid = t.srcGUID
			cc_table.actorname = t.srcName
			cc_table.actorflags = t.srcFlags

			cc_table.spellid = t.spellstring
			cc_table.dstName = Skada:FixPetsName(t.dstGUID, t.dstName, t.dstFlags)
			cc_table.srcName = nil

			Skada:FixPets(cc_table)
			Skada:DispatchSets(log_ccdone)
		end
	end

	function playermod:Enter(win, id, label)
		win.actorid, win.actorname = id, label
		win.title = uformat(L["%s's control spells"], label)
	end

	function playermod:Update(win, set)
		win.title = uformat(L["%s's control spells"], win.actorname)

		local actor = set and set:GetActor(win.actorname, win.actorid)
		local total = actor and actor.ccdone
		local spells = (total and total > 0) and actor.ccdonespells

		if not spells then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		for spellid, spell in pairs(spells) do
			nr = nr + 1

			local d = win:spell(nr, spellid, false)
			d.value = spell.count
			format_valuetext(d, mod_cols, total, win.metadata, true)
		end
	end

	function targetmod:Enter(win, id, label)
		win.actorid, win.actorname = id, label
		win.title = uformat(L["%s's control targets"], label)
	end

	function targetmod:Update(win, set)
		win.title = uformat(L["%s's control targets"], win.actorname)

		local targets, total, actor = get_actor_cc_targets(set, win.actorid, win.actorname)
		if not targets or not actor or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		for targetname, target in pairs(targets) do
			nr = nr + 1

			local d = win:actor(nr, target, true, targetname)
			d.value = target.count
			format_valuetext(d, mod_cols, total, win.metadata, true)
		end
	end

	function sourcemod:Enter(win, id, label)
		win.spellid, win.spellname = id, label
		win.title = uformat(L["%s's sources"], label)
	end

	function sourcemod:Update(win, set)
		win.title = uformat(L["%s's sources"], win.spellname)
		if not set or not win.spellid then return end

		local total, sources = get_cc_done_sources(set, win.spellid)
		if not sources or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		for sourcename, source in pairs(sources) do
			nr = nr + 1

			local d = win:actor(nr, source, source.enemy, sourcename)
			d.value = source.count
			format_valuetext(d, mod_cols, total, win.metadata, true)
		end
	end

	function mod:Update(win, set)
		win.title = win.class and format("%s (%s)", L["CC Done"], L[win.class]) or L["CC Done"]

		local total = set and set:GetTotal(win.class, nil, "ccdone")
		if not total or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actors = set.actors

		for i = 1, #actors do
			local actor = actors[i]
			if win:show_actor(actor, set, true) and actor.ccdone then
				nr = nr + 1

				local d = win:actor(nr, actor, actor.enemy)
				d.value = actor.ccdone
				format_valuetext(d, mod_cols, total, win.metadata)
			end
		end
	end

	function mod:GetSetSummary(set, win)
		return set and set:GetTotal(win and win.class, nil, "ccdone") or 0
	end

	function mod:AddToTooltip(set, tooltip)
		if set.ccdone and set.ccdone > 0 then
			tooltip:AddDoubleLine(L["CC Done"], set.ccdone, 1, 1, 1)
		end
	end

	function mod:OnEnable()
		playermod.metadata = {click1 = sourcemod}
		self.metadata = {
			showspots = true,
			ordersort = true,
			click1 = playermod,
			click2 = targetmod,
			click4 = Skada.FilterClass,
			click4_label = L["Toggle Class Filter"],
			columns = {Count = true, Percent = false, sPercent = false},
			icon = [[Interface\Icons\spell_frost_chainsofice]]
		}

		mod_cols = self.metadata.columns

		-- no total click.
		sourcemod.nototal = true
		playermod.nototal = true
		targetmod.nototal = true

		Skada:RegisterForCL(
			aura_applied,
			{src_is_interesting = true},
			"SPELL_AURA_APPLIED",
			"SPELL_AURA_REFRESH"
		)

		Skada:AddMode(self, "Crowd Control")
	end

	function mod:OnDisable()
		Skada:RemoveMode(self)
	end

	get_cc_done_sources = function(self, spellid, tbl)
		if not self.ccdone or not spellid then return end

		tbl = clear(tbl or C)

		local total = 0
		local actors = self.actors
		for i = 1, #actors do
			local actor = actors[i]
			local spell = actor and not actor.enemy and actor.ccdonespells and actor.ccdonespells[spellid]
			if spell and spell.count then
				tbl[actor.name] = new()
				tbl[actor.name].id = actor.id
				tbl[actor.name].class = actor.class
				tbl[actor.name].role = actor.role
				tbl[actor.name].spec = actor.spec
				tbl[actor.name].enemy = actor.enemy
				tbl[actor.name].count = spell.count
				total = total + spell.count
			end
		end

		return total, tbl
	end

	get_actor_cc_targets = function(self, id, name, tbl)
		local actor = self:GetActor(name, id)
		local spells = actor and actor.ccdone and actor.ccdonespells
		if not spells then return end

		tbl = clear(tbl or C)
		for _, spell in pairs(spells) do
			if spell.targets then
				for targetname, count in pairs(spell.targets) do
					local t = tbl[targetname]
					if not t then
						t = new()
						t.count = count
						tbl[targetname] = t
					else
						t.count = t.count + count
					end
					self:_fill_actor_table(t, targetname)
				end
			end
		end

		return tbl, actor.ccdone, actor
	end
end)

-- ======== --
-- CC Taken --
-- ======== --
Skada:RegisterModule("CC Taken", function(L, P, _, C)
	local mod = Skada:NewModule("CC Taken")
	local playermod = mod:NewModule("Crowd Control Spells")
	local sourcemod = mod:NewModule("Crowd Control Sources")
	local targetmod = playermod:NewModule("Crowd Control Targets")
	local get_actor_cc_sources = nil
	local get_cc_taken_targets = nil
	local mod_cols = nil

	-- few raid spells added to the extended list of cc spells
	local cc_spells = setmetatable({
		-- add raid spells to be considered: [spellid] = [school]
	}, {__index = Skada.extra_cc_spells})

	local function log_cctaken(set)
		local player = Skada:GetPlayer(set, cc_table.actorid, cc_table.actorname, cc_table.actorflags)
		if not player then return end

		-- increment the count.
		player.cctaken = (player.cctaken or 0) + 1
		set.cctaken = (set.cctaken or 0) + 1

		-- saving this to total set may become a memory hog deluxe.
		if set == Skada.total and not P.totalidc then return end

		-- record the spell.
		local spell = player.cctakenspells and player.cctakenspells[cc_table.spellid]
		if not spell then
			player.cctakenspells = player.cctakenspells or {}
			player.cctakenspells[cc_table.spellid] = {count = 0}
			spell = player.cctakenspells[cc_table.spellid]
		end
		spell.count = spell.count + 1

		-- record the source.
		if cc_table.srcName then
			spell.sources = spell.sources or {}
			spell.sources[cc_table.srcName] = (spell.sources[cc_table.srcName] or 0) + 1
		end
	end

	local function aura_applied(t)
		if t.spellid and cc_spells[t.spellid] then
			cc_table.actorid = t.dstGUID
			cc_table.actorname = t.dstName
			cc_table.actorflags = t.dstFlags

			cc_table.spellid = t.spellstring
			cc_table.srcName = Skada:FixPetsName(t.srcGUID, t.srcName, t.srcFlags)
			cc_table.dstName = nil

			Skada:DispatchSets(log_cctaken)
		end
	end

	function playermod:Enter(win, id, label)
		win.actorid, win.actorname = id, label
		win.title = uformat(L["%s's control spells"], label)
	end

	function playermod:Update(win, set)
		win.title = uformat(L["%s's control spells"], win.actorname)

		local actor = set and set:GetActor(win.actorname, win.actorid)
		local total = actor and actor.cctaken
		local spells = (total and total > 0) and actor.cctakenspells

		if not spells then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		for spellid, spell in pairs(spells) do
			nr = nr + 1

			local d = win:spell(nr, spellid, false)
			d.value = spell.count
			format_valuetext(d, mod_cols, total, win.metadata, true)
		end
	end

	function sourcemod:Enter(win, id, label)
		win.actorid, win.actorname = id, label
		win.title = uformat(L["%s's control sources"], label)
	end

	function sourcemod:Update(win, set)
		win.title = uformat(L["%s's control sources"], win.actorname)

		local sources, total, actor = get_actor_cc_sources(set, win.actorid, win.actorname)
		if not sources or not actor or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		for sourcename, source in pairs(sources) do
			nr = nr + 1

			local d = win:actor(nr, source, true, sourcename)
			d.value = source.count
			format_valuetext(d, mod_cols, total, win.metadata, true)
		end
	end

	function targetmod:Enter(win, id, label)
		win.spellid, win.spellname = id, label
		win.title = uformat(L["%s's targets"], label)
	end

	function targetmod:Update(win, set)
		win.title = uformat(L["%s's targets"], win.spellname)
		if not set or not win.spellid then return end

		local total, targets = get_cc_taken_targets(set, win.spellid)
		if not targets or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		for targetname, target in pairs(targets) do
			nr = nr + 1

			local d = win:actor(nr, target, target.enemy, targetname)
			d.value = target.count
			format_valuetext(d, mod_cols, total, win.metadata, true)
		end
	end

	function mod:Update(win, set)
		win.title = win.class and format("%s (%s)", L["CC Taken"], L[win.class]) or L["CC Taken"]

		local total = set and set:GetTotal(win.class, nil, "cctaken")
		if not total or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actors = set.actors

		for i = 1, #actors do
			local actor = actors[i]
			if win:show_actor(actor, set, true) and actor.cctaken then
				nr = nr + 1

				local d = win:actor(nr, actor, actor.enemy)
				d.value = actor.cctaken
				format_valuetext(d, mod_cols, total, win.metadata)
			end
		end
	end

	function mod:GetSetSummary(set, win)
		return set and set:GetTotal(win and win.class, nil, "cctaken") or 0
	end

	function mod:AddToTooltip(set, tooltip)
		if set.cctaken and set.cctaken > 0 then
			tooltip:AddDoubleLine(L["CC Taken"], set.cctaken, 1, 1, 1)
		end
	end

	function mod:OnEnable()
		playermod.metadata = {click1 = targetmod}
		self.metadata = {
			showspots = true,
			ordersort = true,
			click1 = playermod,
			click2 = sourcemod,
			click4 = Skada.FilterClass,
			click4_label = L["Toggle Class Filter"],
			columns = {Count = true, Percent = false, sPercent = false},
			icon = [[Interface\Icons\spell_magic_polymorphrabbit]]
		}

		mod_cols = self.metadata.columns

		-- no total click.
		playermod.nototal = true
		sourcemod.nototal = true
		targetmod.nototal = true

		Skada:RegisterForCL(
			aura_applied,
			{dst_is_interesting_nopets = true},
			"SPELL_AURA_APPLIED",
			"SPELL_AURA_REFRESH"
		)

		Skada:AddMode(self, "Crowd Control")
	end

	function mod:OnDisable()
		Skada:RemoveMode(self)
	end

	get_cc_taken_targets = function(self, spellid, tbl)
		if not self.cctaken or not spellid then return end

		tbl = clear(tbl or C)

		local total = 0
		local actors = self.actors
		for i = 1, #actors do
			local actor = actors[i]
			local spell = actor and not actor.enemy and actor.cctakenspells and actor.cctakenspells[spellid]
			if spell and spell.count then
				tbl[actor.name] = new()
				tbl[actor.name].id = actor.id
				tbl[actor.name].class = actor.class
				tbl[actor.name].role = actor.role
				tbl[actor.name].spec = actor.spec
				tbl[actor.name].enemy = actor.enemy
				tbl[actor.name].count = spell.count
				total = total + spell.count
			end
		end

		return total, tbl
	end

	get_actor_cc_sources = function(self, id, name, tbl)
		local actor = self:GetActor(name, id)
		local spells = actor and actor.cctaken and actor.cctakenspells
		if not spells then return end

		tbl = clear(tbl or C)
		for _, spell in pairs(spells) do
			if spell.sources then
				for sourcename, count in pairs(spell.sources) do
					local t = tbl[sourcename]
					if not t then
						t = new()
						t.count = count
						tbl[sourcename] = t
					else
						t.count = t.count + count
					end
					self:_fill_actor_table(t, sourcename)
				end
			end
		end

		return tbl, actor.cctaken, actor
	end
end)

-- ========= --
-- CC Breaks --
-- ========= --
Skada:RegisterModule("CC Breaks", function(L, P, _, C, M)
	local mod = Skada:NewModule("CC Breaks")
	local playermod = mod:NewModule("Crowd Control Spells")
	local targetmod = mod:NewModule("Crowd Control Targets")
	local cc_spells = Skada.cc_spells
	local get_actor_cc_break_targets = nil
	local mod_cols = nil

	local UnitName, UnitInRaid, IsInRaid = UnitName, UnitInRaid, Skada.IsInRaid
	local GetPartyAssignment, UnitIterator = GetPartyAssignment, Skada.UnitIterator

	local function log_ccbreak(set)
		local player = Skada:GetPlayer(set, cc_table.srcGUID, cc_table.srcName, cc_table.srcFlags)
		if not player then return end

		-- increment the count.
		player.ccbreak = (player.ccbreak or 0) + 1
		set.ccbreak = (set.ccbreak or 0) + 1

		-- saving this to total set may become a memory hog deluxe.
		if set == Skada.total and not P.totalidc then return end

		-- record the spell.
		local spell = player.ccbreakspells and player.ccbreakspells[cc_table.spellid]
		if not spell then
			player.ccbreakspells = player.ccbreakspells or {}
			player.ccbreakspells[cc_table.spellid] = {count = 0}
			spell = player.ccbreakspells[cc_table.spellid]
		end
		spell.count = spell.count + 1

		-- record the target.
		if cc_table.dstName then
			spell.targets = spell.targets or {}
			spell.targets[cc_table.dstName] = (spell.targets[cc_table.dstName] or 0) + 1
		end
	end

	local function aura_broken(t)
		if not t.spellid or not cc_spells[t.spellid] then return end

		local srcGUID, srcName, srcFlags = t.srcGUID, t.srcName, t.srcFlags
		local _srcGUID, _srcName, _srcFlags = Skada:FixMyPets(srcGUID, srcName, srcFlags)

		cc_table.srcGUID = _srcGUID
		cc_table.srcName = _srcName
		cc_table.srcFlags = _srcFlags
		cc_table.dstName = t.dstName
		cc_table.spellid = t.spellstring

		cc_table.dstGUID = nil
		cc_table.dstFlags = nil

		Skada:DispatchSets(log_ccbreak)

		-- Optional announce
		if M.ccannounce and IsInRaid() and UnitInRaid(srcName) then
			if Skada.insType == "pvp" then return end

			-- Ignore main tanks and main assist?
			if M.ccignoremaintanks then
				-- Loop through our raid and return if src is a main tank.
				for unit in UnitIterator(true) do -- exclude pets
					if UnitName(unit) == srcName and (GetPartyAssignment("MAINTANK", unit) or GetPartyAssignment("MAINASSIST", unit)) then
						return
					end
				end
			end

			-- Prettify pets.
			if srcName ~= _srcName then
				srcName = format("%s <%s>", srcName, _srcName)
			end

			-- Go ahead and announce it.
			if t.extraspellid or t.extraspellname then
				Skada:SendChat(format(L["%s on %s removed by %s's %s"], t.spellname, t.dstName, srcName, GetSpellLink(t.extraspellid or t.extraspellname)), "RAID", "preset")
			else
				Skada:SendChat(format(L["%s on %s removed by %s"], t.spellname, t.dstName, srcName), "RAID", "preset")
			end
		end
	end

	function playermod:Enter(win, id, label)
		win.actorid, win.actorname = id, label
		win.title = uformat(L["%s's control spells"], label)
	end

	function playermod:Update(win, set)
		win.title = uformat(L["%s's control spells"], win.actorname)

		local actor = set and set:GetActor(win.actorname, win.actorid)
		local total = actor and actor.ccbreak
		local spells = (total and total > 0) and actor.ccbreakspells

		if not spells then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		for spellid, spell in pairs(spells) do
			nr = nr + 1

			local d = win:spell(nr, spellid, false)
			d.value = spell.count
			format_valuetext(d, mod_cols, total, win.metadata, true)
		end
	end

	function targetmod:Enter(win, id, label)
		win.actorid, win.actorname = id, label
		win.title = uformat(L["%s's control targets"], label)
	end

	function targetmod:Update(win, set)
		win.title = uformat(L["%s's control targets"], win.actorname)

		local targets, total, actor = get_actor_cc_break_targets(set, win.actorid, win.actorname)
		if not targets or not actor or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		for targetname, target in pairs(targets) do
			nr = nr + 1

			local d = win:actor(nr, target, true, targetname)
			d.value = target.count
			format_valuetext(d, mod_cols, total, win.metadata, true)
		end
	end

	function mod:Update(win, set)
		win.title = win.class and format("%s (%s)", L["CC Breaks"], L[win.class]) or L["CC Breaks"]

		local total = set and set:GetTotal(win.class, nil, "ccbreak")
		if not total or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actors = set.actors

		for i = 1, #actors do
			local actor = actors[i]
			if win:show_actor(actor, set, true) and actor.ccbreak then
				nr = nr + 1

				local d = win:actor(nr, actor, actor.enemy)
				d.value = actor.ccbreak
				format_valuetext(d, mod_cols, total, win.metadata)
			end
		end
	end

	function mod:GetSetSummary(set, win)
		return set and set:GetTotal(win and win.class, nil, "ccbreak") or 0
	end

	function mod:AddToTooltip(set, tooltip)
		if set.ccbreak and set.ccbreak > 0 then
			tooltip:AddDoubleLine(L["CC Breaks"], set.ccbreak, 1, 1, 1)
		end
	end

	function mod:OnEnable()
		self.metadata = {
			showspots = true,
			ordersort = true,
			click1 = playermod,
			click2 = targetmod,
			click4 = Skada.FilterClass,
			click4_label = L["Toggle Class Filter"],
			columns = {Count = true, Percent = false, sPercent = false},
			icon = [[Interface\Icons\spell_holy_sealofvalor]]
		}

		mod_cols = self.metadata.columns

		-- no total click.
		playermod.nototal = true
		targetmod.nototal = true

		Skada:RegisterForCL(
			aura_broken,
			{src_is_interesting = true},
			"SPELL_AURA_BROKEN",
			"SPELL_AURA_BROKEN_SPELL"
		)

		Skada:AddMode(self, "Crowd Control")
	end

	function mod:OnDisable()
		Skada:RemoveMode(self)
	end

	function mod:OnInitialize()
		Skada.options.args.modules.args.ccoptions = {
			type = "group",
			name = self.localeName,
			desc = format(L["Options for %s."], self.localeName),
			args = {
				header = {
					type = "description",
					name = self.localeName,
					fontSize = "large",
					image = [[Interface\Icons\spell_holy_sealofvalor]],
					imageWidth = 18,
					imageHeight = 18,
					imageCoords = {0.05, 0.95, 0.05, 0.95},
					width = "full",
					order = 0
				},
				sep = {
					type = "description",
					name = " ",
					width = "full",
					order = 1
				},
				ccannounce = {
					type = "toggle",
					name = format(L["Announce %s"], self.localeName),
					order = 10,
					width = "double"
				},
				ccignoremaintanks = {
					type = "toggle",
					name = L["Ignore Main Tanks"],
					order = 20,
					width = "double"
				}
			}
		}
	end

	get_actor_cc_break_targets = function(self, id, name, tbl)
		local actor = self:GetActor(name, id)
		local spells = actor and actor.ccbreak and actor.ccbreakspells
		if not spells then return end

		tbl = clear(tbl or C)
		for _, spell in pairs(spells) do
			if spell.targets then
				for targetname, count in pairs(spell.targets) do
					local t = tbl[targetname]
					if not t then
						t = new()
						t.count = count
						tbl[targetname] = t
					else
						t.count = t.count + count
					end
					self:_fill_actor_table(t, targetname)
				end
			end
		end

		return tbl, actor.ccbreak, actor
	end
end)
