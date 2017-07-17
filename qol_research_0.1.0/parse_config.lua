local function string_split(self, sep)
   local fields = {}
   self:gsub('([^' .. sep .. ']+)', function(c) fields[#fields+1] = c end)
   return fields
end

local function parse_int(str)
    local nr = tonumber(str)
    if nr == nil then error('invalid int parameter', 2) end
    return nr
end

local function parse_rational(str, allow_rational_bonus)
    local numerator, denominator
    for s in string.gmatch(str, '([^/]+)/?') do
        local nr = tonumber(s)
        assert(nr ~= nil, 'invalid number in rational')
        if numerator == nil then
            numerator = nr
        elseif denominator == nil then
            denominator = nr
        else
            error('invalid rational')
        end
    end
    if numerator == nil then error('no increase supplied', 2) end
    if denominator ~= nil and not allow_rational_bonus then
        error('rational bonuses is not allowed', 2)
    end
    if denominator == 0 then
        error('rational number with 0 in the denominator is not allowed', 2)
    end
    denominator = denominator or 1
    return numerator / denominator
end

return function (config, allow_rational_bonus)
    -- Split up the config and tiers
    local tiers = string_split(config, ':')
    for tier_index, tier in ipairs(tiers) do
        local tier = string_split(tier, ',')
        assert(#tier >= 7, 'too few parameters in tier')

        local tier_obj =
        {
            previous_tier_requirement = parse_int(tier[1]),
            technology_count          = parse_int(tier[2]),
            bonus_per_technology      = parse_rational(tier[3], allow_rational_bonus),
            cycle_duration            = parse_int(tier[4]),
            count_formula             = tier[5],
            ingredients               = {}
        }

        for i = 6, #tier, 2 do
            if i + 1 > #tier then
                error('expected ingredient names and quantities in pairs.')
            end
            tier_obj.ingredients[#tier_obj.ingredients + 1] =
            {
                tier[i],
                parse_int(tier[i + 1])
            }
        end

        tiers[tier_index] = tier_obj
    end

    -- Determine whether the tier is split into two technologies
    for i = 1, #tiers - 1 do
        -- A tier has to be split if the next tier depends on the current
        -- one, AND the tier it depends on isn't the last tier (taking into
        -- account the special case when there's an infinite amount of tiers).
        local tier, next = tiers[i], tiers[i + 1]
        tier.is_split_technology = next.previous_tier_requirement > 0
            and (next.previous_tier_requirement < tier.technology_count
            or tier.technology_count == 0)
    end
    -- The last tier can never be a split technology
    tiers[#tiers].is_split_technology = false

    return tiers
end