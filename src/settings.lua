local qol_types = require('qol_types')(true)
local order_lookup = { 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l' }

local extensions = {}
for i, v in ipairs(qol_types) do
    extensions[#extensions + 1] = {
        name = ('qol-%s-enabled'):format(v.name),
        type = 'bool-setting',
        setting_type = 'startup',
        order = 'a-a-' .. order_lookup[i] .. '-a',
        default_value = true
    }
    extensions[#extensions + 1] = {
        name = ('qol-%s-research-enabled'):format(v.name),
        type = 'bool-setting',
        setting_type = 'startup',
        order = 'a-a-' .. order_lookup[i] .. '-b',
        default_value = true
    }
end

for i, v in pairs(qol_types) do
    extensions[#extensions + 1] = {
        name = ('qol-%s-research-config'):format(v.name),
        type = 'string-setting',
        setting_type = 'startup',
        order = 'a-b-' .. order_lookup[i],
        default_value = '',
        allow_blank = true
    }
end

for i, v in pairs(qol_types) do
    extensions[#extensions + 1] = {
        name = ('qol-%s-flat-bonus'):format(v.name),
        type = v.allow_rational_bonus and 'double-setting' or 'int-setting',
        setting_type = 'runtime-global',
        order = ('a-c-%s-a'):format(order_lookup[i]),
        default_value = 0,
        minimum_value = -99999,
        maximum_value = 99999
    }

    if v.allow_rational_bonus then
        extensions[#extensions + 1] = {
            name = ('qol-%s-multiplier'):format(v.name),
            type = 'double-setting',
            setting_type = 'runtime-global',
            order = ('a-c-%s-b'):format(order_lookup[i]),
            default_value = 1,
            minimum_value = 0,
            maximum_value = 999
        }
    end

    if v.field_settings then
        for j, field in ipairs(v.field_settings) do
            extensions[#extensions + 1] = {
                name = ('qol-%s-field-%s'):format(v.name, field[2]),
                type = 'bool-setting',
                setting_type = 'runtime-global',
                order = ('a-c-%s-c-%s'):format(order_lookup[i], order_lookup[j]),
                default_value = true
            }
        end
    end
end

data:extend(extensions)
