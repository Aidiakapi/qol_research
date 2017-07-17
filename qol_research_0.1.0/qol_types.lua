--[[

    You can configure multiple sets of research tiers, each set separated by a semi-colon (;).

    Each set has several fields defining amount of tiers, cost and ingredients, each field
    is separated by a comma.

    The fields are:

    1. [int]    Level of the previous tier required to start on this tier, or 0 to have no dependency.
    2. [int]    The amount of technologies in this tier, use 0 for infinite.
    3. [ratio]  The bonus per level of research.
    4. [int]    The duration of each cycle.
    5. [string] A math expression for the cycle cost of each technology. (See count_formula.)
    6. [string] Name of an item for each cycle.
    7. [int]    Amount of previous item.

    Repeat the last two to specify multiple ingredients.
    A ratio takes the format for x/y which is only supported for certain upgrades.

    Example:
    0,3,1/10,15,(L+1)*50,science-pack-1,1:2,4,3/20,20,50*2^(L-1),science-pack-1,1,science-pack-2,1

    This contains two tiers of research:
    0,3,1/10,15,(L+1)*50,science-pack-1,1
    and
    2,4,3/20,20,50*2^(L-1),science-pack-1,1,science-pack-2,1

    The first tier goes as follows:
    0                No tech in the previous (which doesn't exist anyways) tier is required.
    3                There's 3 tech in this tree.
    1/10             Each tech gives a 1/10 = 10% bonus.
    15               Each cycle takes 15 seconds.
    (L+1)*50         Cost of each tech, where L starts at 1.
    science-pack-1   It requires science pack 1
    1                Exactly 1 science pack 1 per cycle

    It creates 3 techs:
    Tech 1-1, 10% bonus, 15 seconds/cycle, 100 cycles of 1 x science-pack-1
    Tech 1-2, 10% bonus, 15 seconds/cycle, 150 cycles of 1 x science-pack-1
    Tech 1-3, 10% bonus, 15 seconds/cycle, 200 cycles of 1 x science-pack-1

    The second tier looks like
    2                It requires "Tech 1-2" to be unlocked before this tier becomes available.
    4                There's 4 tech in this tree.
    3/20             Each tech gives a 3/20 = 15% bonus.
    20               Each cycle takes 20 seconds.
    50*2^(L-1)       Cost of each tech, where L starts at 1.
    science-pack-1   It requires science pack 1
    1                x1
    science-pack-2   and science pack 2
    1                also x1

    This creates an additional 4 techs, which you can only start unlocking after you unlocked Tech 1-2:
    Tech 2-1, 15% bonus, 20 seconds/cycle, 50 * 2^0 = 50 cycles of 1 x science-pack-1 and 1 x science-pack-2
    Tech 2-2, 15% bonus, 20 seconds/cycle, 50 * 2^1 = 100 cycles of 1 x science-pack-1 and 1 x science-pack-2
    Tech 2-3, 15% bonus, 20 seconds/cycle, 50 * 2^2 = 200 cycles of 1 x science-pack-1 and 1 x science-pack-2
    Tech 2-4, 15% bonus, 20 seconds/cycle, 50 * 2^3 = 400 cycles of 1 x science-pack-1 and 1 x science-pack-2
]]

return function (unfiltered)
    -- Tier 1 (10%): 50, 100, 175, 300, 525
    -- Tier 2 (15%): 75, 150, 250, 400, 650
    -- Tier 3 (20%): 100, 200, 325, 500, 775
    -- Tier 4 (25%): 125, 250, 400, 600, 900
    -- Tier 5 (30%): 200, 400, 600, 800, 1000, 1200, 1400, ...
    local rational_default_config = '0,5,1/10,10,25*2^(L-1)+25*L,science-pack-1,1:3,5,3/20,15,25*2^(L-1)+50*L,science-pack-1,1,science-pack-2,1:3,5,2/10,20,25*2^(L-1)+75*L,science-pack-1,1,science-pack-2,1,science-pack-3,1:3,5,1/4,25,25*2^(L-1)+100*L,science-pack-1,1,science-pack-2,1,science-pack-3,1,high-tech-science-pack,1:3,0,3/10,30,200*L,science-pack-1,1,science-pack-2,1,science-pack-3,1,high-tech-science-pack,1,space-science-pack,1'
    local data = {
        {
            name = 'crafting-speed',
            allow_rational_bonus = true,
            default_technology_config = rational_default_config,
            bonus_fields = { 'manual_crafting_speed_modifier' }
        },
        {
            name = 'inventory-size',
            allow_rational_bonus = false,
            default_technology_config = '0,2,5,15,125*L,science-pack-1,1:1,2,5,20,175*L,science-pack-1,1,science-pack-2,1:1,2,5,25,225*L,science-pack-1,1,science-pack-2,1,science-pack-3,1:1,2,5,30,300*L,science-pack-1,1,science-pack-2,1,science-pack-3,1,high-tech-science-pack,1',
            bonus_fields = { 'character_inventory_slots_bonus' }
        },
        {
            name = 'mining-speed',
            allow_rational_bonus = true,
            default_technology_config = rational_default_config,
            bonus_fields = { 'manual_mining_speed_modifier' }
        },
        {
            name = 'movement-speed',
            allow_rational_bonus = true,
            default_technology_config = '0,5,1/20,10,25*2^(L-1)+25*L,science-pack-1,1:3,5,1/20,15,25*2^(L-1)+50*L,science-pack-1,1,science-pack-2,1:3,5,1/20,20,25*2^(L-1)+75*L,science-pack-1,1,science-pack-2,1,science-pack-3,1:3,5,1/20,25,25*2^(L-1)+100*L,science-pack-1,1,science-pack-2,1,science-pack-3,1,high-tech-science-pack,1:3,0,1/20,30,200*L,science-pack-1,1,science-pack-2,1,science-pack-3,1,high-tech-science-pack,1,space-science-pack,1',
            bonus_fields = { 'character_running_speed_modifier' }
        },
        {
            name = 'player-reach',
            allow_rational_bonus = false,
            default_technology_config = '0,5,1,10,25*2^(L-1)+25*L,science-pack-1,1:3,5,1,15,25*2^(L-1)+50*L,science-pack-1,1,science-pack-2,1:3,5,2,20,25*2^(L-1)+75*L,science-pack-1,1,science-pack-2,1,science-pack-3,1:3,5,2,25,25*2^(L-1)+100*L,science-pack-1,1,science-pack-2,1,science-pack-3,1,high-tech-science-pack,1:3,0,3,30,200*L,science-pack-1,1,science-pack-2,1,science-pack-3,1,high-tech-science-pack,1,space-science-pack,1',
            bonus_fields =
            {
                'character_build_distance_bonus',
                'character_item_drop_distance_bonus',
                'character_resource_reach_distance_bonus',
                'character_reach_distance_bonus',
            },
            field_settings =
            {
                { 'character_item_drop_distance_bonus', 'item-drop-distance' },
                { 'character_resource_reach_distance_bonus', 'resource-reach-distance' }
            }
        },
        {
            name = 'toolbelts',
            allow_rational_bonus = false,
            default_technology_config = '0,1,1,15,500,science-pack-1,1:1,1,1,30,500,science-pack-1,1,science-pack-2,1',
            effects_table_factory = function (amount)
                return { {
                    type = "num-quick-bars",
                    modifier = amount
                } }
            end
        }
    }

    if not unfiltered then
        local source = data
        data = {}
        for _, v in ipairs(source) do
            if settings.startup['qol-' .. v.name .. '-enabled'].value then
                data[#data + 1] = v
            end
        end
    end

    return data
end