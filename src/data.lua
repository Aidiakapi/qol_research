local qol_types = require('qol_types')()
local parse_config = require('parse_config')
local order_lookup = { 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l' }

local extensions = {}

-- Creates the configuration for all researches based on the config provided by the user, or the default config.
for i, v in ipairs(qol_types) do
    if settings.startup['qol-' .. v.name .. '-research-enabled'].value and v.default_technology_config then
        local config = settings.startup['qol-' .. v.name .. '-research-config']
        if type(config) ~= 'string' or #config == 0 then
            config = v.default_technology_config
        end
        local tiers = parse_config(config, v.allow_rational_bonus)

        for tier_index, tier in ipairs(tiers) do
            local effects_table = v.effects_table_factory and v.effects_table_factory(tier.bonus_per_technology) or nil

            local localised_description = { ('technology-description.qol-%s'):format(v.name), v.description_factory(tier.bonus_per_technology) }
            if tier.is_split_technology then
                extensions[#extensions + 1] = {
                    type = 'technology',
                    name = ('qol-%s-%d-1'):format(v.name, tier_index),
                    localised_description = localised_description,
                    icon = '__qol_research__/graphics/' .. v.name .. '.png',
                    icon_size = 128,
                    effects = effects_table,
                    prerequisites = tier.previous_tier_requirement > 0
                        and { 'qol-' .. v.name .. '-' .. tostring(tier_index - 1) .. '-1' }
                        or nil,
                    unit =
                    {
                        count_formula = tier.count_formula,
                        ingredients = tier.ingredients,
                        time = tier.cycle_duration
                    },
                    max_level = tostring(tiers[tier_index + 1].previous_tier_requirement),
                    upgrade = true,
                    order = 'qol-research-' .. tostring(order_lookup[i]) .. '-' .. tostring(order_lookup[tier_index]) .. '-a'
                }
                extensions[#extensions + 1] = {
                    type = 'technology',
                    name = ('qol-%s-%d-%d'):format(v.name, tier_index, tiers[tier_index + 1].previous_tier_requirement + 1),
                    localised_description = localised_description,
                    icon = '__qol_research__/graphics/' .. v.name .. '.png',
                    icon_size = 128,
                    effects = effects_table,
                    prerequisites = { 'qol-' .. v.name .. '-' .. tostring(tier_index) .. '-1' },
                    unit =
                    {
                        count_formula = tier.count_formula,
                        ingredients = tier.ingredients,
                        time = tier.cycle_duration
                    },
                    max_level = tier.technology_count == 0 and 'infinite' or tostring(tier.technology_count),
                    upgrade = true,
                    order = 'qol-research-' .. tostring(order_lookup[i]) .. '-' .. tostring(order_lookup[tier_index]) .. '-b'
                }
            else
                extensions[#extensions + 1] = {
                    type = 'technology',
                    name = ('qol-%s-%d-1'):format(v.name, tier_index),
                    localised_description = localised_description,
                    icon = '__qol_research__/graphics/' .. v.name .. '.png',
                    icon_size = 128,
                    effects = effects_table,
                    prerequisites = tier.previous_tier_requirement > 0
                        and { 'qol-' .. v.name .. '-' .. tostring(tier_index - 1) .. '-1' }
                        or  nil,
                    unit =
                    {
                        count_formula = tier.count_formula,
                        ingredients = tier.ingredients,
                        time = tier.cycle_duration
                    },
                    max_level = tier.technology_count == 0 and 'infinite' or tostring(tier.technology_count),
                    upgrade = true,
                    order = 'qol-research-' .. tostring(order_lookup[i]) .. '-' .. tostring(order_lookup[tier_index])
                }
            end
        end
    end
end

if #extensions >= 1 then
    data:extend(extensions)
end
