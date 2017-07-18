--[[

Because the game doesn't fire events when you complete a level of research which has multiple levels, instead
every tick, one technology is checked for one force. If a change in that tech is detected, it'll update the
force.

All data is stored in the global object, with the exception of update_list, which is generated solely from
startup settings, and the qol_types source file. Unless these files change, no desync should be possible.

]]

local qol_types = require('qol_types')()
local parse_config = require('parse_config')
local api = {}

local function player_print(...)
    for _, player in pairs(game.players) do
        player.print(...)
    end
end

local update_list = {}
for _, qol_type in ipairs(qol_types) do
    if qol_type.bonus_fields then
        local config = settings.startup['qol-' .. qol_type.name .. '-research-config']
        if type(config) ~= 'string' or #config == 0 then
            config = qol_type.default_technology_config
        end
        local tiers = parse_config(config, qol_type.allow_rational_bonus)

        for tier_index, tier in ipairs(tiers) do
            local update_entry = 
            {
                qol_type = qol_type,
                bonus_per_technology = tier.bonus_per_technology,
                identifier = string.format('%s-%d', qol_type.name, tier_index),
                tech_name1 = string.format('qol-%s-%d-1', qol_type.name, tier_index),
                tech_name2 = tier.is_split_technology and string.format('qol-%s-%d-%d', qol_type.name, tier_index, tiers[tier_index + 1].previous_tier_requirement + 1) or nil,
                tech_levels1 = tier.is_split_technology and tiers[tier_index + 1].previous_tier_requirement or tier.technology_count,
                tech_levels2 = tier.is_split_technology and (tier.technology_count - tiers[tier_index + 1].previous_tier_requirement) or nil
            }

            update_list[#update_list + 1] = update_entry
        end
    end
end

function api.apply_stat_modifier(force, qol_type, modifier, use_multiplier)
    if qol_type.bonus_fields == nil then return end

    -- Apply optional modifier
    if use_multiplier and qol_type.allow_rational_bonus then
        modifier = modifier * settings.global[('qol-%s-multiplier'):format(qol_type.name)].value
    end
    local bonuses = global.bonuses[force.name]

    -- Apply the change to each field
    for _, field_name in ipairs(qol_type.bonus_fields) do
        local disabled = false
        if qol_type.field_settings then
            for _, field_setting in ipairs(qol_type.field_settings) do
                if field_name == field_setting[1] and not settings.global[('qol-%s-field-%s'):format(qol_type.name, field_setting[2])].value then
                    disabled = true
                    break
                end
            end
        end

        if not disabled then
            force[field_name] = force[field_name] + modifier
            if not bonuses[field_name] then
                bonuses[field_name] = modifier
            else
                bonuses[field_name] = bonuses[field_name] + modifier
            end
        end
    end
end

function api.apply_research_bonuses(force, update_entry)
    assert(force.valid, 'force must be valid')
    
    local tech1, tech2 = force.technologies[update_entry.tech_name1], update_entry.tech_name2 and force.technologies[update_entry.tech_name2] or nil
    
    local level
    if tech1.researched then
        level = update_entry.tech_levels1
    else
        level = tech1.level - 1
    end
    if tech2 and tech2.researched then
        level = level + update_entry.tech_levels2
    elseif tech2 then
        level = level +  (tech2.level - 1 - update_entry.tech_levels1)
    end

    local old_level = global.levels[force.name][update_entry.identifier] or 0
    if level == old_level then return end

    global.levels[force.name][update_entry.identifier] = level
    --player_print(string.format('%s updated from %d to %d for %s', update_entry.identifier, old_level, level, force.name))

    api.apply_stat_modifier(force, update_entry.qol_type, (level - old_level) * update_entry.bonus_per_technology, true)
end

-- ----------------
-- Force management
-- ----------------
function api.include_force(force)
    assert(force and force.valid, 'cannot include an invalid force')

    global.force_update_list[#global.force_update_list + 1] = force
    assert(not global.levels[force.name], 'duplicate force added')
    assert(not global.bonuses[force.name], 'duplicate force added')
    global.levels[force.name] = {}
    global.bonuses[force.name] = {}

    -- Apply flat bonuses
    for _, qol_type in ipairs(qol_types) do
        local flat_bonus = settings.global[('qol-%s-flat-bonus'):format(qol_type.name)].value
        api.apply_stat_modifier(force, qol_type, flat_bonus, false)
    end

    -- Apply research based bonuses
    for _, update_entry in ipairs(update_list) do
        api.apply_research_bonuses(force, update_entry)
    end
end
function api.prepare_forces()
    if global.force_update_list then return end
    global.force_update_list = {}
    if not global.levels then global.levels = {} end
    local levels = global.levels
    if not global.bonuses then global.bonuses = {} end

    for _, force in pairs(game.forces) do
        api.include_force(force)
    end
end
function api.reset_force_bonuses(delayed_reset_till)
    if delayed_reset_till then
        if not global.delayed_reset_till or global.delayed_reset_till < delayed_reset_till then
            global.delayed_reset_till = delayed_reset_till
        end
        return
    end
    if not global.levels then return end

    -- Store the previously applied bonuses
    local previous_bonuses = global.bonuses
    
    -- Remove all data
    global.levels = nil
    global.bonuses = nil
    global.force_update_list = nil

    -- Recreate the list to immediately reapply any bonuses
    api.prepare_forces()

    -- Remove the old bonuses
    for force_name, bonuses in pairs(previous_bonuses) do
        local force = game.forces[force_name]
        if force and force.valid then
            for field_name, modifier in pairs(bonuses) do
                force[field_name] = force[field_name] - modifier
            end
        end
    end
end

script.on_event(defines.events.on_force_created, function (event)
    -- If the list hasn't been created, ignore it
    if not global.force_update_list then return end
    api.include_force(event.force)
end)

script.on_event(defines.events.on_forces_merging, function (event)
    -- For some reason it takes a little bit to get forces properly updated
    -- although it sucks, we cannot just instantly reapply the bonuses, and
    -- instead have to wait.
    api.reset_force_bonuses(event.tick + 2)
end)
script.on_event(defines.events.on_runtime_mod_setting_changed, function (event)
    api.reset_force_bonuses()
end)

remote.add_interface('qol_research', {
    reset_force_bonuses = reset_force_bonuses
})

local function get_force_and_update_entry(tick)
    local force_index = tick % #global.force_update_list
    local update_index = ((tick - force_index) / #global.force_update_list) % #update_list
    return global.force_update_list[force_index + 1], update_list[update_index + 1]
end

-- script.on_event(defines.events.on_research_started, function (event)
--     event.research.force.research_progress = 1
-- end)

script.on_event(defines.events.on_tick, function (event)
    -- Special case for a delayed reset, no updates while a reset is scheduled
    if global.delayed_reset_till and event.tick < global.delayed_reset_till then
        global.delayed_reset_till = nil
        api.reset_force_bonuses()
        return
    end
    api.prepare_forces()
    local force, update_entry = get_force_and_update_entry(event.tick)
    -- There's an invalid force, just reset all bonuses and halt this frame's execution
    if not force or not force.valid then
        api.reset_force_bonuses()
    else
        api.apply_research_bonuses(force, update_entry)
    end
end)
