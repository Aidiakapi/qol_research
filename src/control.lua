--[=[
    
    File containing the primary logic for the mod.

    Description of the global table:
    global:
        previous_settings:
            $-flat-bonus: number
            $-multiplier: number
            $-flag-$: boolean
        startup_settings:
            $: any

    The $ sign is a placeholder for dynamic values
    startup_settings will hold all known startup settings
    this is used to detect whether any of this mod's values
    have changed in on_configuration_changed.

    Because the mod does not store per-force or per-player
    information, and because when merging forces, all the
    technologies of the source force are just destroyed,
    there is no need to handle those events.

    There are a few edge cases that are particularly hard
    to deal with. Notably, any mod calling the LuaForce
    reset_technology_effects function, and modifications
    to startup settings. I describe below how I deal with
    both of them.

    reset_technology_effects()
    Assuming this is solely called in migration scripts,
    which solely run when a change in mods is detected, it
    uses a heuristic to determine if it were called. This
    heuristic will compute the mimimum possible value that
    each field should have (based on the flat_bonus setting
    and technology levels). If it finds any field that has
    a current value lower than what would be permissable by
    the settings, it will add all bonuses. Since any mod
    could add larger bonuses that push it over this minimum,
    qol_research may be broken by other mods.

    Modification of startup settings
    Because the mod allows for any arbitrary tech tree to be
    created through startup settings, it'd require parsing
    and storing the previous tech tree, and then calculating
    bonus field diffs based on that. This is not impossible,
    and requires only minor refactoring. It is however such
    a niche scenario, that I do not consider it worth the time
    right now, and instead it's a feature I consider I may
    consider in the future. For now it performs a reset, which
    then triggers the same code as reset_technology_effects().

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

local function add_relative_bonus(force, entry, value)
    assert(entry.is_enabled, '[qol] add_relative_bonus called whilst entry is disabled');
    if value == 0 then return end
    for field in entry.fields_filtered:iter() do
        plog('%s.%s: %s => %s', force.name, field, force[field], force[field] + value)
        force[field] = force[field] + value
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
    @return number[]  All research tier levels.
]=]
local function get_tier_research_levels(force, entry)
    return flua.range(#entry.config)
        :map(function (tier_index)
            return get_tier_research_level(force, entry, tier_index)
        end)
        :list()
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

local function update_global_startup_settings()
    global.startup_settings = flua.ivalues(config_ext)
        :flatmap(function (entry)
            return flua.ivalues({
                setting_name_formats.enabled:format(entry.name),
                setting_name_formats.research_enabled:format(entry.name),
                setting_name_formats.research_config:format(entry.name)
            })
        end)
        :map(function (setting_name)
            return setting_name, settings.startup[setting_name].value
        end, 2)
        :table()
end

local function init_global_table()
    for k, _ in pairs(global) do
        global[k] = nil
    end

    global.previous_settings =
        flua.ivalues(config_ext)
        :flatmap(function (entry)
            return flua.ivalues({
                entry.setting_names.flat_bonus,
                entry.setting_names.multiplier
            }):concat(entry.field_setting_names)
        end)
        :map(function (setting)
            return setting, settings.global[setting].value
        end, 2)
        :table()
    
    update_global_startup_settings()
end

script.on_init(function ()
    init_global_table()

    -- Add all flat bonuses for all enabled tiers
    for entry in flua.ivalues(config_ext)
        :filter(function (entry) return entry.is_enabled end)
        :iter()
        do
        local flat_bonus = entry.setting_flat_bonus
        for _, force in pairs(game.forces) do
            add_relative_bonus(force, entry, flat_bonus)
        end
    end
end)

-- Handles adding bonuses for research 
script.on_event(defines.events.on_research_finished, function (event)
    if suppress_research_unlocks then return end
    local research = event.research
    local force = research.force

    local entry, research_tier, research_level = parse_research_name(research.name)
    if not entry then return end

    plog('research completed \'%s\'', research.name)

    local levels = get_tier_research_levels(force, entry)
    
    local new_bonus = calculate_research_bonus_at(entry, levels)
    levels[research_tier] = levels[research_tier] - 1
    local old_bonus = calculate_research_bonus_at(entry, levels)

    local extra = new_bonus - old_bonus
    add_relative_bonus(force, entry, extra)
end)

-- Handles the modifications of the character bonus factors based on settings.
script.on_event(defines.events.on_runtime_mod_setting_changed, function (event)
    local setting = event.setting
    local old_value = global.previous_settings[setting]
    if old_value == nil then return end
    
    local new_value = settings.global[setting].value
    global.previous_settings[setting] = new_value

    plog('setting changed \'%s\': %s => %s', setting, old_value, new_value)

    -- Flat bonus settings
    local entry = flua.ivalues(config_ext):first(function (v)
        return setting == v.setting_names.flat_bonus
    end)
    if entry then
        if not entry.is_enabled then
            pprint('warning: ', entry.name, ' upgrades are not enabled')
            return
        end
        local delta_value = new_value - old_value
        for _, force in pairs(game.forces) do
            add_relative_bonus(force, entry, delta_value)
        end
        return
    end

    -- Modifier bonus settings
    entry = flua.ivalues(config_ext):first(function (v)
        return setting == v.setting_names.multiplier
    end)
    if entry then
        if not entry.is_enabled then
            pprint('warning: ', entry.name, ' upgrades are not enabled')
            return
        end
        for _, force in pairs(game.forces) do
            local levels = get_tier_research_levels(force, entry)
            local old_bonus = calculate_research_bonus_at(entry, levels, old_value)
            local new_bonus = calculate_research_bonus_at(entry, levels, new_value)
            local delta_bonus = new_bonus - old_bonus
            add_relative_bonus(force, entry, delta_bonus)
        end
        return
    end

    -- Field flag settings
    entry = flua.ivalues(config_ext):first(function (v)
        return v.field_setting_map[setting] ~= nil
    end)
    if not entry then
        return
    end
    if not entry.is_enabled then
        pprint('warning: ', entry.name, ' upgrades are not enabled')
        return
    end

    local field = entry.field_setting_map[setting]
    for _, force in pairs(game.forces) do
        local bonus = calculate_research_bonus_at(entry, get_tier_research_levels(force, entry))
                    + entry.setting_flat_bonus
        if old_value then
            bonus = bonus * -1
        end
        plog('%s.%s: %s => %s', force.name, field, force[field], force[field] + bonus)
        force[field] = force[field] + bonus
    end
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

    -- Transforming the old global table to the new global table
    local qol_research = changes.mod_changes.qol_research
    local upgrade_from_v01 = false
    if qol_research ~= nil then
        local old_version = qol_research.old_version
        if old_version ~= nil then
            local version_major, version_minor = old_version:match('^(%d+).(%d+).%d+$')
            plog('%s == %s.%s', old_version, version_major, version_minor)
            upgrade_from_v01 = tonumber(version_major) == 0 and tonumber(version_minor) == 1
        end
    end
    local startup_changed = changes.mod_startup_settings_changed
        and (global.startup_settings
            and flua.pairs(global.startup_settings)
            :any(function (setting_name, old_value)
                local new_value = settings.startup[setting_name].value
                return new_value ~= old_value
            end))

    if upgrade_from_v01 then
        local restore_count = flua.wrap(2, pairs(game.forces))
            :map(function (_, force)
                return unlock_depended_upon_researches(force)
            end, 1)
            :sum()
        if restore_count == 0 then
            pprint('Upgraded from v0.1 to v1.0, you may have lost some researches.')
        elseif restore_count == 1 then
            pprint('Upgraded from v0.1 to v1.0, 1 research was restored, but some may be lost.')
        else
            pprint(('Upgraded from v0.1 to v1.0. %s researches were restored, but some may be lost.'):format(restore_count))
        end
        init_global_table()
    elseif startup_changed then
        pprint('warning: changing mod startup settings overwrites bonus values on force')
        pprint('warning: this may conflict with other mods that provide bonuses through script')
        update_global_startup_settings()
    end

    -- When the startup configuration changes or it's an upgrade
    -- from version 0.1.x, it'll reset all values, triggering the
    -- reset below (provided that there are any bonuses).
    local pending_reset_actions
    if upgrade_from_v01 or startup_changed then
        pending_reset_actions = {}
        for force_name in pairs(game.forces) do
            pending_reset_actions[force_name] = {}
        end
        for field, default_value in flua.ivalues(config_ext)
            :flatmap(function (entry)
                return flua.ivalues(entry.fields)
                    :map(function (field)
                        return field,
                            entry.field_default_values
                            and entry.field_default_values[field]
                            or 0
                    end, 2)
            end, 2)
            :iter()
            do
            for _, force in pairs(game.forces) do
                pending_reset_actions[force.name][field] = default_value - force[field]
            end
        end
    end

    -- Use a heuristic to determine if the technology effects
    -- were actually reset. If so, restore those effects.
    local enabled_config = flua.ivalues(config_ext)
        :filter(function (entry) return entry.is_enabled end)
        :list();
    for _, force in pairs(game.forces) do
        local bonus_values = flua.ivalues(enabled_config)
            :flatmap(function (entry)
                local levels = get_tier_research_levels(force, entry)
                local bonus = calculate_research_bonus_at(entry, levels) 
                            + entry.setting_flat_bonus
                return entry.fields_filtered
                    :map(function (field_name)
                        return field_name, bonus,
                            entry.field_default_values
                            and entry.field_default_values[field_name]
                            or 0
                    end, 3)
            end, 3)

        local is_reset = pending_reset_actions
            or bonus_values
            :any(function (field_name, bonus, default)
                return force[field_name] < bonus + default
            end)
        
        if is_reset then
            plog('\'%s\' effect reset detected, attempting to restore', force.name)
            for field, value in bonus_values:iter() do
                if value ~= 0 then
                    plog('restore %s.%s: %s => %s', force.name, field, force[field], force[field] + value)
                    force[field] = force[field] + value
                end
            end
        end
    end

    if pending_reset_actions then
        for force_name, fields in pairs(pending_reset_actions) do
            local force = game.forces[force_name]
            for field, value in pairs(fields) do
                if value ~= 0 then
                    plog('reset %s.%s: %s => %s', force.name, field, force[field], force[field] + value)
                    force[field] = force[field] + value
                end
            end
        end
    end
end)
