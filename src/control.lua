--[=[
    
    File containing the primary logic for the mod.

    Since v2.0.0 no more state is stored in the
    global table, and instead all information can
    be derived from the on_configuration_changed.

]=]

local flua = require('flua')
local config_ext = require('config_ext')
local setting_name_formats = require('defines.setting_name_formats')
local tech_format = 'qol-%s-%d-%d'

local suppress_research_unlocks = false

local function plog(str, ...)
    log(('[qol] ' .. str):format(...))
end

local function pprint(...)
    local message

    local n = select('#', ...)
    if n == 1 then
        message = '[qol] ' .. tostring(...)
    else
        local str = { '[qol] ' }
        for i = 1, n do
            local v = select(i, ...)
            str[i + 1] = tostring(v)
        end
        message = table.concat(str, '')
    end
    log(message)
    for _, player in pairs(game and game.players or {}) do
        player.print(message)
    end
end

--[=[
    Calculates the total bonus at a particular set of levels.

    Params:
      entry  ConfigExt
        The entry of research.
      levels  number[]
        The levels at which each tier is researched.
      multiplier number
        Optional. Override for the multiplier setting.
]=]
local function calculate_research_bonus_at(entry, levels, multiplier)
    if not entry.is_research_enabled then
        return 0
    end
    assert(#levels == #entry.config, 'levels size must be match tier count')
    if multiplier == nil then
        multiplier = entry.setting_multiplier
    end
    
    local value = flua.ipairs(entry.config)
        :map(function (index, tier)
            return tier.effect_value * levels[index]
        end, 1)
        :sum() * multiplier

    if entry.type == 'double' then
        return value
    else
        return math.ceil(value)
    end
end

--[=[
    Determines the current level at which a tier is researched at for a force.
    @param  force          LuaForce
    @param  entry          ConfigExt
    @param  research_tier  number     Tier index
    @return number  Index of the tier that was **finished** researching! 
--]=]
local function get_tier_research_level(force, entry, research_tier)
    if not entry.is_research_enabled then return end
    local tier_depth = entry.config[research_tier].tier_depth
    -- If infinite research
    if tier_depth == 0 then
        return force.technologies[('qol-%s-%d-1'):format(entry.name, research_tier)].level - 1
    end
    for i = tier_depth, 1, -1 do
        if force.technologies[('qol-%s-%d-%d'):format(entry.name, research_tier, i)].researched then
            return i
        end
    end
    return 0
end

--[=[
    Gets the level of each research tier.
    @param  force          LuaForce
    @param  entry          ConfigExt
    @return number[]  All research tier levels.
]=]
local function get_tier_research_levels(force, entry)
    return flua.range(#entry.config)
        :map(function (tier_index)
            return tier_index, get_tier_research_level(force, entry, tier_index)
        end, 2)
        :table()
end

--[=[
    Updates the field values for a specific force and entry.
    @param  force          LuaForce
    @param  entry          ConfigExt
    @param  all_fields     any bool
]=]
local function update_for_force_and_entry(force, entry, all_fields)
    local bonus = 0
    if entry.is_enabled then
        bonus = entry.setting_flat_bonus
        if entry.is_research_enabled then
            local levels = get_tier_research_levels(force, entry)
            bonus = bonus + calculate_research_bonus_at(entry, levels)
        end
    end
    
    if bonus < 0 then
        plog('detected negative bonus for %q of value %s, clamping', entry.name, bonus)
        bonus = 0
    end

    local fields = all_fields and entry.fields or entry.fields_filtered

    local enabled_fields = entry.fields_filtered
        :map(function (field) return field, true end, 2)
        :table()

    for field in fields:iter() do
        local old_value = force[field]
        local new_value
        if enabled_fields[field] then
            new_value = bonus
        else
            new_value = 0
        end
        if entry.field_defaults[field] ~= nil then
            new_value = new_value + entry.field_defaults[field](force)
        end

        if old_value ~= new_value then
            plog('force %q modifying %q: %s => %s', force.name, field, old_value, new_value)
            force[field] = new_value
        end
    end
end

--[=[
    Updates the field values for a specific force.
    @param  force          LuaForce
    @param  all_fields     any bool
]=]
local function update_for_force(force, all_fields)
    for _, entry in ipairs(config_ext) do
        if entry.is_enabled then
            update_for_force_and_entry(force, entry, all_fields)
        end
    end
end

--[=[
    Updates the field values for a all forces.
    @param  all_fields     any bool
]=]
local function update_for_all_forces(all_fields)
    for _, force in pairs(game.forces) do
        update_for_force(force, all_fields)
    end
end

--[=[
    Updates every possible field on every force.
]=]
local function update_all_including_disabled()
    for _, force in pairs(game.forces) do
        for _, entry in ipairs(config_ext) do
            update_for_force_and_entry(force, entry, true)
        end
    end
end

--[=[
    Parses the name of a technology
    @param  research_name  string
    @return nothing or
            entry           ConfigExt
            research_tier   number
            research_level  number
]=]
local function parse_research_name(research_name)
    local research_type, research_tier, research_level = research_name:match('^qol%-([a-z-]-)%-(%d+)%-(%d)$')
    if not research_type then return end

    local entry = flua.ivalues(config_ext):first(function (v) return v.name == research_type end)
    research_tier, research_level = tonumber(research_tier), tonumber(research_level)

    if not entry or
        not research_tier or
        not research_level or
        research_tier <= 0 or
        research_level <= 0 or
        research_tier > #entry.config
        then
        pprint('warning: unknown technology, bug or conflicting mod? ', research.name)
        return
    end

    return entry, research_tier, research_level
end

-- Handles adding bonuses for research 
script.on_event(defines.events.on_research_finished, function (event)
    if suppress_research_unlocks then return end
    local research = event.research
    local force = research.force

    local entry, research_tier, research_level = parse_research_name(research.name)
    if not entry then return end

    plog('research completed %q', research.name)
    update_for_force_and_entry(force, entry)
end)

-- Handles the modifications of the character bonus factors based on settings.
script.on_event(defines.events.on_runtime_mod_setting_changed, function (event)
    plog('runtime settings changed, performing a reset for enabled entries and all fields')
    update_for_all_forces(true)
end)

local function unlock_depended_upon_researches(force)
    suppress_research_unlocks = true
    local unlocked_total = 0
    local unlocked_previous = nil
    local techs = force.technologies

    -- Repeat the process until no more researches are unlocked
    while unlocked_total ~= unlocked_previous do
        unlocked_previous = unlocked_total
        local entries = flua.ivalues(config_ext)
            :filter(function (entry) return entry.is_research_enabled end)
        
        for entry in entries:iter() do
            -- Unlock researches that higher tiers depend on
            for tier_index, tier in flua.for_pairs(entry.config, #entry.config, 2, -1)
                :filter(function (_, tier) return tier.requirement ~= 0 end)
                :filter(function (index, tier)
                    local tech_name = tech_format:format(entry.name, index, 1)
                    return techs[tech_name].researched
                end)
                :iter() do
                local previous = techs[tech_format:format(entry.name, tier_index - 1, tier.requirement)]
                if not previous.researched then
                    plog('unlocked dependency \'%s\'', previous.name)
                    previous.researched = true
                    unlocked_total = unlocked_total + 1
                end
            end

            -- Unlock earlier entries in each tier
            for tier_index, tier in ipairs(entry.config) do
                local max_unlocked = flua.reverse_range(tier.tier_depth)
                    :first(function (index)
                        local tech_name = tech_format:format(entry.name, tier_index, index)
                        return techs[tech_name].researched
                    end)
                if max_unlocked ~= nil then
                    for tech in flua.reverse_range(max_unlocked - 1)
                        :filtermap(function (index)
                            local tech_name = tech_format:format(entry.name, tier_index, index)
                            local tech = techs[tech_name]
                            return (not tech.researched) and tech or nil
                        end):iter() do
                        plog('unlocked prior \'%s\'', tech.name)
                        tech.researched = true
                        unlocked_total = unlocked_total + 1
                    end
                end
            end
        end
    end
    
    suppress_research_unlocks = false
    return unlocked_total
end

script.on_configuration_changed(function (changes)
    plog('configuration change detected')

    -- Clear out the global table, it is no longer necessary
    for k, _ in pairs(global) do
        global[k] = nil
    end

    -- Transforming the old global table to the new global table
    local qol_research = changes.mod_changes.qol_research
    local upgrade_from_v01 = false
    if qol_research ~= nil then
        local old_version = qol_research.old_version
        if old_version ~= nil then
            local version_major, version_minor = old_version:match('^(%d+).(%d+).%d+$')
            version_major, version_minor = tonumber(version_major), tonumber(version_minor)
            plog('%s == %s.%s', old_version, version_major, version_minor)
            upgrade_from_v01 = version_major == 0 and version_minor == 1
            if version_major == 1 and version_minor == 1 then
                pprint('resetting all research bonus previously misapplied')
            end
        end
    end

    if upgrade_from_v01 then
        local restore_count = flua.wrap(2, pairs(game.forces))
            :map(function (_, force)
                return unlock_depended_upon_researches(force)
            end, 1)
            :sum()
        if restore_count == 0 then
            pprint('Upgraded from v0.1 to v2.0, you may have lost some researches.')
        elseif restore_count == 1 then
            pprint('Upgraded from v0.1 to v2.0, 1 research was restored, but some may be lost.')
        else
            pprint(('Upgraded from v0.1 to v2.0. %s researches were restored, but some may be lost.'):format(restore_count))
        end
        init_global_table()
    end

    -- If startup settings were changed, reset all entries' bonuses
    if changes.mod_startup_settings_changed then
        update_all_including_disabled()
    end
end)



commands.add_command('qol-reset', [[Sets all enabled Quality of Life based bonuses to the default values, and reapplying any bonuses from settings/research.
Execute this command to fix interoperability issues with other mods.]], function (event)
    if game.players[event.player_index].admin then
        pprint('resetting, check factorio-current.log if you want details')
        update_for_all_forces(true)
    else
        player.print('[qol] you must be an admin to run this command')
    end
end)
commands.add_command('qol-reset-all', [[Sets ALL Quality of Life based bonuses (including the ones disabled by settings) to the default values, and reapplying any bonuses from settings/research.
Execute this command to fix interoperability issues with other mods.]], function (event)
    if game.players[event.player_index].admin then
        pprint('resetting all, check factorio-current.log if you want details')
        update_all_including_disabled()
    else
        player.print('[qol] you must be an admin to run this command')
    end
end)
