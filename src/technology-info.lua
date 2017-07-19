local technologies = {}
local parse_config = require('parse_config')

local function get_flat_bonus(self)
    local setting_name = ('qol-%s-flat-bonus'):format(self.name)
    return settings.global[setting_name].value
end
local function get_bonus_multiplier(self)
    local setting_name = ('qol-%s-multiplier'):format(self.name)
    return settings.global[setting_name].value
end
local function one_factory() return 1 end

for index, qol_type in ipairs(require('qol_types')()) do
    if qol_type.bonus_fields then
        local config = settings.startup[('qol-%s-research-config'):format(qol_type.name)].value
        if not config or #config == 0 then
            config = qol_type.default_technology_config
        end
        local tiers = parse_config(config, qol_type.allow_rational_bonus)

        local tier_info_functions = {}

        for tier_index, tier in ipairs(tiers) do
            if tier.is_split_technology then
                local tech_name1, tech_name2, count1, count2, per_level =
                    ('qol-%s-%d-1'):format(qol_type.name, tier_index),
                    ('qol-%s-%d-%d'):format(qol_type.name, tier_index, tiers[tier_index + 1].previous_tier_requirement + 1),
                    tiers[tier_index + 1].previous_tier_requirement,
                    tier.technology_count - tiers[tier_index + 1].previous_tier_requirement,
                    tier.bonus_per_technology
                tier_info_functions[tier_index] = function (force)
                    local tech1, tech2 = force.technologies[tech_name1], force.technologies[tech_name2]
                    local level1 = tech1.researched and count1 or (tech1.level - 1)
                    local level2 = tech2.researched and count2 or (tech2.level - 1 - count1)

                    return level1 + level2, count1 + count2, per_level
                end
            else
                local tech_name, count, per_level =
                    ('qol-%s-%d-1'):format(qol_type.name, tier_index),
                    tier.technology_count,
                    tier.bonus_per_technology
                tier_info_functions[tier_index] = function (force)
                    local tech = force.technologies[tech_name]
                    local level = tech.researched and count or (tech.level - 1)
                    return level, count, per_level
                end
            end
        end

        technologies[#technologies + 1] = {
            name = qol_type.name,
            fields = qol_type.bonus_fields,
            get_flat_bonus = get_flat_bonus,
            get_bonus_multiplier = qol_type.allow_rational_bonus and get_bonus_multiplier or one_factory,
            tier_count = #tiers,
            get_tier_info = function (self, tier_index, force)
                assert(type(self) == 'table' and self.name, 'use : to call get_tier_info', 2)
                assert(type(tier_index) == 'number' and tier_index >= 1 and tier_index <= #tier_info_functions, 'tier_index out of range', 2)
                assert(force and force.valid, 'invalid force in get_tier_info', 2)
                return tier_info_functions[tier_index](force)
            end
        }
    end
end
return technologies