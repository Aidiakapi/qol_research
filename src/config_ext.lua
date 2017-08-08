local flua = require('flua')
local config = require('config')

local setting_name_formats = require('defines.setting_name_formats')
local getters = {}

function getters:is_enabled()
    return true, settings.startup[setting_name_formats.enabled:format(self.name)].value
end

function getters:is_research_enabled()
    return true, self:is_enabled() and settings.startup[setting_name_formats.research_enabled:format(self.name)].value
end

function getters:setting_flat_bonus()
    return false, settings.global[setting_name_formats.flat_bonus:format(self.name)].value
end

function getters:setting_multiplier()
    return false, settings.global[setting_name_formats.multiplier:format(self.name)].value
end

function getters:config()
    local config_str = settings.startup[setting_name_formats.research_config:format(self.name)].value
    if not config_str or #config_str == 0 then
        config_str = config[self.index].default_config
    end

    local function parse_assert(condition, tier_index, message)
        if not condition then
            error(('[qol] config parse error in %s tier %s, %s'):format(self.name, tier_index, message), 2)
        end
    end

    -- Parse the config
    local config = flua.pattern(config_str, '[^:]+:?')
        :map(function (tier_str, index)
            local split = flua.pattern(tier_str, '[^:,]+,?')
                :map(function (v) return v:match('([^:,]+),?') end)

            local properties = split:list()
            parse_assert(#properties >= 7 and #properties % 2 == 1, index, 'incorrect number of properties')

            -- Generate ingredients table
            local ingredients = {}
            flua.index(properties, 5):reduce(function (accumulator, value)
                if #ingredients == accumulator then
                    ingredients[accumulator + 1] = { value }
                    return accumulator
                end
                local number = tonumber(value)
                parse_assert(number ~= nil, index, 'ingredient count must be a number')
                ingredients[accumulator + 1][2] = number
                return accumulator + 1
            end, 0)
            
            -- Parse all other properties
            local requirement = tonumber(properties[1])
            parse_assert(type(requirement) == 'number' and requirement >= 0, index, 'previous tier requirement must be a non-negative number')
            local tier_depth = tonumber(properties[2])
            parse_assert(type(tier_depth) == 'number' and tier_depth >= 0, index, 'tier depth must be a non-negative number')
            local effect_value = tonumber(properties[3])
            parse_assert(type(effect_value) == 'number' and effect_value >= 0, index, 'effect value must be a non-negative number')
            local cycle_duration = tonumber(properties[4])
            parse_assert(type(cycle_duration) == 'number' and cycle_duration >= 0, index, 'cycle duration must be a non-negative number')
            local cost_formula = properties[5]

            return {
                requirement = requirement,
                tier_depth = tier_depth,
                effect_value = effect_value,
                cycle_duration = cycle_duration,
                cost_formula = cost_formula,
                cycle_ingredients = ingredients
            }
        end)
        :table()

    parse_assert(#config >= 1, 0, 'at least one tier must be configured')
    parse_assert(config[1].requirement == 0, 1, 'the first tier cannot have requirements')
    for i = 1, #config - 1 do
        parse_assert(config[i].tier_depth >= config[i + 1].requirement, i + 1, 'tier requirement cannot be greater than previous tier depth')
    end

    return true, config
end

function getters:fields_filtered()
    return false, flua.index(self.fields):filter(function (v)
        local field_setting_name = self.field_toggles[v]
        if not field_setting_name then return true end
        return settings.global[setting_name_formats.field_toggle:format(self.name, field_setting_name)].value
    end)
end

local metatable = {}
function metatable.__index(self, key)
    local fn = getters[key]
    if fn then
        local cache, value = fn(self)
        if cache then rawset(self, key, value) end
        return value
    end
end
function metatable.__newindex(self, key, value)
    error('cannot add extra properties to config_ext')
end

return flua.index(config):map(function (entry, index)
    local field_toggles = {}
    if entry.field_toggles then
        for _, v in ipairs(entry.field_toggles) do
            field_toggles[v[1]] = v[2]
        end
    end
    return setmetatable({
        index = index,
        name = entry.name,
        type = entry.type,
        fields = entry.fields,
        description_factory = entry.description_factory,
        fields = entry.fields,
        field_toggles = field_toggles
    }, metatable)
end):list()
