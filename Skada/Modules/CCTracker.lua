local _, Skada = ...
local Private = Skada.Private

local pairs, format, uformat = pairs, string.format, Private.uformat
local GetSpellLink = Private.spell_link or GetSpellLink
local new, clear = Private.newTable, Private.clearTable
local cc_table = {} -- holds stuff from cleu

local CCSpells = {
	[118] = 0x40, -- Polymorph
	[52719] = 0x01, -- Concussion Blow
	[20066] = 0x02, -- Repentance
	[2637] = 0x08, -- Hibernate
	[28271] = 0x40, -- Polymorph: Turtle
	[28272] = 0x40, -- Polymorph: Pig
	[3355] = 0x10, -- Freezing Trap Effect
	[33786] = 0x08, -- Cyclone
	[339] = 0x08, -- Entangling Roots
	[45524] = 0x10, -- Chains of Ice
	[51722] = 0x01, -- Dismantle
	[6358] = 0x20, -- Seduction (Succubus)
	[676] = 0x01, -- Disarm
	[6770] = 0x01, -- Sap
	[710] = 0x20, -- Banish
	[9484] = 0x02, -- Shackle Undead
}

-- extended CC list for only CC Done and CC Taken modules
local ExtraCCSpells = {
	-- Death Knight
	[47476] = 0x20, -- Strangulate
	[79092] = 0x10, -- Hungering Cold
	[47481] = 0x01, -- Gnaw
	[49560] = 0x01, -- Death Grip
	-- Druid
	[339] = 0x08, -- Entangling Roots
	[19975] = 0x08, -- Entangling Roots (Nature's Grasp)
	[66070] = 0x08, -- Entangling Roots (Force of Nature)
	[16979] = 0x01, -- Feral Charge - Bear
	[45334] = 0x01, -- Feral Charge Effect
	[22570] = 0x01, -- Maim
	-- Hunter
	[5116] = 0x01, -- Concussive Shot
	[19503] = 0x01, -- Scatter Shot
	[19386] = 0x08, -- Wyvern Sting
	[4167] = 0x01, -- Web (Spider)
	[24394] = 0x01, -- Intimidation
	[19577] = 0x08, -- Intimidation (stun)
	[50541] = 0x01, -- Clench (Scorpid)
	[26090] = 0x08, -- Pummel (Gorilla)
	[1513] = 0x08, -- Scare Beast
	[64803] = 0x01, -- Entrapment
	-- Mage
	[61305] = 0x40, -- Polymorph Cat
	[61721] = 0x40, -- Polymorph Rabbit
	[61780] = 0x40, -- Polymorph Turkey
	[31661] = 0x04, -- Dragon's Breath
	[44572] = 0x10, -- Deep Freeze
	[122] = 0x10, -- Frost Nova
	[33395] = 0x10, -- Freeze (Frost Water Elemental)
	[55021] = 0x40, -- Silenced - Improved Counterspell
	-- Paladin
	[853] = 0x02, -- Hammer of Justice
	[10326] = 0x02, -- Turn Evil
	[2812] = 0x02, -- Holy Wrath
	[31935] = 0x02, -- Avengers Shield
	-- Priest
	[8122] = 0x20, -- Psychic Scream
	[605] = 0x20, -- Dominate Mind (Mind Control)
	[15487] = 0x20, -- Silence
	[64044] = 0x20, -- Psychic Horror
	-- Rogue
	[408] = 0x01, -- Kidney Shot
	[2094] = 0x01, -- Blind
	[1833] = 0x01, -- Cheap Shot
	[1776] = 0x01, -- Gouge
	[1330] = 0x01, -- Garrote - Silence
	-- Shaman
	[51514] = 0x08, -- Hex
	[8056] = 0x10, -- Frost Shock
	[64695] = 0x08, -- Earthgrab (Earthbind Totem with Storm, Earth and Fire talent)
	[3600] = 0x08, -- Earthbind (Earthbind Totem)
	[8034] = 0x10, -- Frostbrand Weapon
	-- Warlock
	[5484] = 0x20, -- Howl of Terror
	[30283] = 0x20, -- Shadowfury
	[22703] = 0x04, -- Infernal Awakening
	[6789] = 0x20, -- Death Coil
	[24259] = 0x20, -- Spell Lock
	-- Warrior
	[5246] = 0x01, -- Initmidating Shout
	[46968] = 0x01, -- Shockwave
	[6552] = 0x01, -- Pummel
	[58357] = 0x01, -- Heroic Throw silence
	[7922] = 0x01, -- Charge
	[12323] = 0x01, -- Piercing Howl
	-- Racials
	[20549] = 0x01, -- War Stomp (Tauren)
	[28730] = 0x40, -- Arcane Torrent (Bloodelf)
	[47779] = 0x40, -- Arcane Torrent (Bloodelf)
	[50613] = 0x40, -- Arcane Torrent (Bloodelf)
	-- Engineering
	[67890] = 0x04 -- Cobalt Frag Bomb
}

local function get_spell_school(spellid)
	if CCSpells[spellid] and CCSpells[spellid] ~= true then
		return CCSpells[spellid]
	end
	if ExtraCCSpells[spellid] and ExtraCCSpells[spellid] ~= true then
		return ExtraCCSpells[spellid]
	end
end

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
	local get_actor_cc_targets = nil
	local get_cc_done_sources = nil
	local mod_cols = nil

	local function log_ccdone(set)
		local player = Skada:GetPlayer(set, cc_table.srcGUID, cc_table.srcName, cc_table.srcFlags)
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
		if t.spellid and CCSpells[t.spellid] or ExtraCCSpells[t.spellid] then
			cc_table.srcGUID, cc_table.srcName, cc_table.srcFlags = Skada:FixMyPets(t.srcGUID, t.srcName, t.srcFlags)
			cc_table.dstName = Skada:FixPetsName(t.dstGUID, t.dstName, t.dstFlags)
			cc_table.spellid = t.spellid

			cc_table.dstGUID = nil
			cc_table.dstFlags = nil
			cc_table.extraspellid = nil

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

			local d = win:spell(nr, spellid, nil, get_spell_school(spellid))
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

		Skada:AddMode(self, L["Crowd Control"])
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

	local RaidCCSpells = {}

	local function log_cctaken(set)
		local player = Skada:GetPlayer(set, cc_table.dstGUID, cc_table.dstName, cc_table.dstFlags)
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
		if t.spellid and CCSpells[t.spellid] or ExtraCCSpells[t.spellid] or RaidCCSpells[t.spellid] then
			cc_table.dstGUID = t.dstGUID
			cc_table.dstName = t.dstName
			cc_table.dstFlags = t.dstFlags

			cc_table.srcName = t.srcName
			cc_table.spellid = t.spellid

			cc_table.srcGUID = nil
			cc_table.srcFlags = nil
			cc_table.extraspellid = nil

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

			local d = win:spell(nr, spellid, nil, get_spell_school(spellid) or RaidCCSpells[spellid])
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

		Skada:AddMode(self, L["Crowd Control"])
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

-- =========== --
-- CC Breakers --
-- =========== --
Skada:RegisterModule("CC Breaks", function(L, P, _, C, M)
	local mod = Skada:NewModule("CC Breaks")
	local playermod = mod:NewModule("Crowd Control Spells")
	local targetmod = mod:NewModule("Crowd Control Targets")
	local get_actor_cc_break_targets = nil
	local mod_cols = nil

	local UnitName, UnitInRaid, IsInRaid = UnitName, UnitInRaid, IsInRaid
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
		if not t.spellid or not CCSpells[t.spellid] then return end

		local srcGUID, srcName, srcFlags = t.srcGUID, t.srcName, t.srcFlags
		local _srcGUID, _srcName, _srcFlags = Skada:FixMyPets(srcGUID, srcName, srcFlags)

		cc_table.srcGUID = _srcGUID
		cc_table.srcName = _srcName
		cc_table.srcFlags = _srcFlags
		cc_table.dstName = t.dstName

		cc_table.dstGUID = nil
		cc_table.dstFlags = nil

		cc_table.spellid = t.spellid
		cc_table.extraspellid = t.extraspellid

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

			local d = win:spell(nr, spellid, nil, get_spell_school(spellid))
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

		Skada:AddMode(self, L["Crowd Control"])
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
