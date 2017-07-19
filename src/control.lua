local qol = {}

local print, assert = (function ()
    local global_print = print
    return function (...)
        local first = select(1, ...)
        global_print(('[qol] %s'):format(first), select(2, ...))
    end, function (condition, message, level)
        if not condition then
            error('[qol] ' .. tostring(message), (level or 1) + 1)
        end
    end
end)()

local function player_print(...)
    print(...)
    if game and game.players then
        for _, player in pairs(game.players) do
            player.print(...)
        end
    end
end

local technologies = require('technology-info')

function qol:add_modifier(force, fields, modifier)
    assert(force and force.valid, 'force be modified must be valid', 2)
    local data = self.forces[force.name]
    assert(data, 'cannot add modifier to unknown force', 2)
    assert(type(fields) == 'table', 'fields must be a table', 2)
    assert(type(modifier) == 'number', 'modifier must be a number', 2)

    for _, field in ipairs(fields) do
        if data[field] then
            data[field] = data[field] + modifier
        else
            data[field] = modifier
        end
        force[field] = force[field] + modifier
    end
end

function qol:recalculate_all_bonuses()
    if not global.qol_data then
        print('warning: recalculate_all_bonuses was called but no state is available')
        return
    end
    assert(game, 'recalculate_all_bonuses requires game to be available', 2)
    print('recalculating all bonuses')

    -- Store the old modifiers and clean the data
    local old_modifiers = self.forces
    self.forces = {}

    -- Add all forces
    for _, force in pairs(game.forces) do
        if force.valid then
            self.forces[force.name] = {}
            for _, tech in ipairs(technologies) do
                -- Add flat bonus
                qol:add_modifier(force, tech.fields, tech:get_flat_bonus())

                -- Add research based bonus
                for tier_index = 1, tech.tier_count do
                    local level, _, modifier_per_level = tech:get_tier_info(tier_index, force)
                    local modifier = (level * modifier_per_level) * tech:get_bonus_multiplier()
                    qol:add_modifier(force, tech.fields, modifier)
                end
            end
        end
    end

    -- Remove old modifiers
    for force_name, modifiers in pairs(old_modifiers) do
        local force = game.forces[force_name]
        if force and force.valid then
            for field, modifier in pairs(modifiers) do
                force[field] = force[field] - modifier
            end
        end
    end
end

script.on_event(defines.events.on_research_finished, function (event)
    if not event.research.name:find('^qol-') then return end
    print(('research %s completed'):format(event.research.name))

    qol:recalculate_all_bonuses()
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function ()
    qol:recalculate_all_bonuses()
end)

script.on_event(defines.events.on_force_created, function ()
    qol:recalculate_all_bonuses()
end)

script.on_event(defines.events.on_forces_merging, function (event)
    qol.recalculate_on_tick = event.tick + 1
end)

do
    local function create_qol_data()
        global.qol_data = {
            forces = {}
        }
        for force_name in pairs(game.forces) do
            global.qol_data.forces[force_name] = {}
        end
    end
    local function create_metatable()
        assert(global.qol_data, 'qol_data must be created before metatable can be set up')
        local data = global.qol_data
        setmetatable(qol, {
            __index = function (self, key)
                local fn = rawget(qol, key)
                if fn then return fn end
                return data[key]
            end,
            __newindex = function (self, key, value)
                local fn = rawget(qol, key)
                if fn then error(('[qol] cannot assign to field %q'):format(key), 2) end
                data[key] = value
            end
        })
    end

    script.on_init(function ()
        create_qol_data()
        create_metatable()
    end)
    script.on_load(function ()
        if global.qol_data then
            create_metatable()
        else
            print('warning: global.qol_data nonexistent')
        end
    end)

    script.on_event(defines.events.on_tick, function (event)
        if not global.qol_data then
            create_qol_data()
            create_metatable()
            for key in pairs(global) do
                if key ~= 'qol_data' then
                    global[key] = nil
                end
            end
            qol:recalculate_all_bonuses()
            qol.recalculate_on_tick = nil
            return
        end
        if qol.recalculate_on_tick and qol.recalculate_on_tick <= event.tick then
            qol.recalculate_on_tick = nil
            qol:recalculate_all_bonuses()
        end
    end)
end
