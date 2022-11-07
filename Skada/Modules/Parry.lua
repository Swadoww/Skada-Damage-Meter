local _, Skada = ...
local Private = Skada.Private
if not Private.IsWotLK() then return end
Skada:RegisterModule("Parry-Haste", function(L, P, _, _, M)
	local mode = Skada:NewModule("Parry-Haste")
	local mode_target = mode:NewModule("Parry target list")
	local pairs, format, uformat = pairs, string.format, Private.uformat
	local mode_cols = nil

	local parrybosses = {
		[L["Acidmaw"]] = true,
		[L["Dreadscale"]] = true,
		[L["Icehowl"]] = true,
		[L["Onyxia"]] = true,
		[L["Lady Deathwhisper"]] = true,
		[L["Sindragosa"]] = true,
		[L["Halion"]] = true,
		-- UNCONFIRMED BOSSES
		-- Suggested by shoggoth#9796
		[L["General Vezax"]] = true,
		[L["Gluth"]] = true,
		[L["Kel'Thuzad"]] = true,
		[L["Sapphiron"]] = true,
	}

	local function format_valuetext(d, columns, total, metadata, subview)
		d.valuetext = Skada:FormatValueCols(
			columns.Count and d.value,
			columns[subview and "sPercent" or "Percent"] and Skada:FormatPercent(d.value, total)
		)

		if metadata and d.value > metadata.maxvalue then
			metadata.maxvalue = d.value
		end
	end

	local data = {}
	local function log_parry(set)
		local actor = Skada:GetActor(set, data.actorid, data.actorname, data.actorflags)
		if not actor then return end

		actor.parry = (actor.parry or 0) + 1
		set.parry = (set.parry or 0) + 1

		-- saving this to total set may become a memory hog deluxe.
		if (set == Skada.total and not P.totalidc) or not data.dstName then return end

		actor.parrytargets = actor.parrytargets or {}
		actor.parrytargets[data.dstName] = (actor.parrytargets[data.dstName] or 0) + 1

		if M.parryannounce and set ~= Skada.total then
			Skada:SendChat(format(L["%s parried %s (%s)"], data.dstName, data.actorname, actor.parrytargets[data.dstName] or 1), M.parrychannel, "preset")
		end
	end

	local function spell_missed(t)
		if t.misstype == "PARRY" and t.dstName and parrybosses[t.dstName] then
			data.actorid, data.actorname, data.actorflags = Skada:FixMyPets(t.srcGUID, t.srcName, t.srcFlags)
			data.dstName = t.dstName

			Skada:DispatchSets(log_parry)
		end
	end

	function mode_target:Enter(win, id, label)
		win.actorid, win.actorname = id, label
		win.title = format(L["%s's parry targets"], label)
	end

	function mode_target:Update(win, set)
		win.title = uformat(L["%s's parry targets"], win.actorname)
		if not set or not win.actorname then return end

		local actor = set:GetActor(win.actorid, win.actorname)
		local total = (actor and not actor.enemy) and actor.parry
		local targets = (total and total > 0) and actor.parrytargets

		if not targets then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		for targetname, count in pairs(targets) do
			nr = nr + 1

			local d = win:actor(nr, targetname)
			d.class = "BOSS" -- what else can it be?
			d.value = count
			format_valuetext(d, mode_cols, total, win.metadata, true)
		end
	end

	function mode:Update(win, set)
		win.title = win.class and format("%s (%s)", L["Parry-Haste"], L[win.class]) or L["Parry-Haste"]

		local total = set and set:GetTotal(win.class, nil, "parry")
		if not total or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		local actors = set.actors

		for actorname, actor in pairs(actors) do
			if win:show_actor(actor, set, true) and actor.parry then
				nr = nr + 1

				local d = win:actor(nr, actor, actor.enemy, actorname)
				d.value = actor.parry
				format_valuetext(d, mode_cols, total, win.metadata)
			end
		end
	end

	function mode:GetSetSummary(set, win)
		if not set then return end
		return set:GetTotal(win and win.class, nil, "parry") or 0
	end

	function mode:OnEnable()
		self.metadata = {
			showspots = true,
			ordersort = true,
			click1 = mode_target,
			click4 = Skada.FilterClass,
			click4_label = L["Toggle Class Filter"],
			columns = {Count = true, Percent = false, sPercent = false},
			icon = [[Interface\Icons\ability_parry]]
		}

		mode_cols = self.metadata.columns

		-- no total click.
		mode_target.nototal = true

		Skada:RegisterForCL(
			spell_missed,
			{src_is_interesting = true, dst_is_not_interesting = true},
			"SPELL_MISSED",
			"SWING_MISSED"
		)

		Skada:AddMode(self)
	end

	function mode:OnDisable()
		Skada:RemoveMode(self)
	end

	function mode:OnInitialize()
		M.parrychannel = M.parrychannel or "AUTO"

		Skada.options.args.modules.args.Parry = {
			type = "group",
			name = self.localeName,
			desc = format(L["Options for %s."], self.localeName),
			args = {
				header = {
					type = "description",
					name = self.localeName,
					fontSize = "large",
					image = [[Interface\Icons\ability_parry]],
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
				parryannounce = {
					type = "toggle",
					name = format(L["Announce %s"], self.localeName),
					order = 10,
					width = "double"
				},
				parrychannel = {
					type = "select",
					name = L["Channel"],
					values = {AUTO = L["Instance"], SELF = L["Self"]},
					order = 20,
					width = "double"
				}
			}
		}
	end
end)
