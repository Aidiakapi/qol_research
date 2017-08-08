local flua = require('flua')
local config = flua.index(require('config'))
local data_utils = require('data_utils')
local setting_name_formats = require('defines.setting_name_formats')

local ordering_table = data_utils.create_ordering_table(config:count() * 3)
local flag_ordering_table = data_utils.create_ordering_table(
    config:filtermap(function (v)
        return v.field_toggles and #v.field_toggles
    end):max() or 0
)

local function create_enabled_setting(entry, index)
    return {
        name = setting_name_formats.enabled:format(entry.name),
        type = 'bool-setting',
        setting_type = 'startup',
        order = 'a-' .. ordering_table[index * 2 - 1],
        default_value = true
    }
end
local function create_research_enabled_setting(entry, index)
    return {
        name = setting_name_formats.research_enabled:format(entry.name),
        type = 'bool-setting',
        setting_type = 'startup',
        order = 'a-' .. ordering_table[index * 2],
        default_value = true
    }
end
local function create_research_config_setting(entry, index)
    return {
        name = setting_name_formats.research_config:format(entry.name),
        type = 'string-setting',
        setting_type = 'startup',
        order = 'b-' .. ordering_table[index],
        default_value = '',
        allow_blank = true
    }
end
local function create_flat_bonus_setting(entry, index)
    return {
        name = setting_name_formats.flat_bonus:format(entry.name),
        type = entry.type .. '-setting',
        setting_type = 'runtime-global',
        order = 'c-' .. ordering_table[index * 3 - 2],
        default_value = 0,
        minimum_value = -99999,
        maximum_value = 99999
    }
end
local function create_multiplier_setting(entry, index)
    return {
        name = setting_name_formats.multiplier:format(entry.name),
        type = 'double-setting',
        setting_type = 'runtime-global',
        order = 'c-' .. ordering_table[index * 3 - 1],
        default_value = 1,
        minimum_value = 0,
        maximum_value = 999
    }
end
local function create_field_toggle_settings(entry, index)
    return flua.index(entry.field_toggles):map(function (field_toggle, field_index)
        return {
            name = setting_name_formats.field_toggle:format(entry.name, field_toggle[2]),
            type = 'bool-setting',
            setting_type = 'runtime-global',
            order = ('c-%s-%s'):format(ordering_table[index * 3], flag_ordering_table[field_index]),
            default_value = true
        }
    end)
end

data:extend(config:map(create_enabled_setting)
    :concat(config:map(create_research_enabled_setting))
    :concat(config:map(create_research_config_setting))
    :concat(config:map(create_flat_bonus_setting))
    :concat(config:map(create_multiplier_setting))
    :concat(config:flatmap(create_field_toggle_settings))
    :list()
)
