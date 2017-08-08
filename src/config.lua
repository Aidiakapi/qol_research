--[[

    You can configure multiple sets of research tiers, each set separated by a colon (:).

    Each set has several fields defining amount of levels, cost and ingredients, each field
    is separated by a comma.

    The fields are:

    1. [int]    Level of the previous tier required to start on this tier, or 0 to have no dependency on the previous tier.
    2. [int]    The amount of technologies (levels) in this tier, use 0 for infinite.
    3. [double] The bonus per level of research.
    4. [int]    The duration of each cycle.
    5. [string] A math expression for the cycle cost of each technology. (See count_formula.)
    6. [string] Name of an item for each cycle.
    7. [int]    Amount of previous item.

    Repeat the last two to specify multiple ingredients.

    Example:
    0,3,0.1,15,(L+1)*50,science-pack-1,1:2,4,0.15,20,50*2^(L-1),science-pack-1,1,science-pack-2,1

    This contains two tiers of research:
    0,3,0.1,15,(L+1)*50,science-pack-1,1
    and
    2,4,0.15,20,50*2^(L-1),science-pack-1,1,science-pack-2,1

    The first tier goes as follows:
    0                No tech in the previous (which doesn't exist anyways) tier is required.
    3                There's 3 tech in this tree.
    0.1             Each tech gives a 0.1 = 10% bonus.
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
    0.15             Each tech gives a 0.15 = 15% bonus.
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

-- Tier 1 (10%): 50, 100, 175, 300, 525
-- Tier 2 (15%): 75, 150, 250, 400, 650
-- Tier 3 (20%): 100, 200, 325, 500, 775
-- Tier 4 (25%): 125, 250, 400, 600, 900
-- Tier 5 (30%): 200, 400, 600, 800, 1000, 1200, 1400, ...
local rational_default_config = '0,5,0.1,10,25*2^(L-1)+25*L,science-pack-1,1:3,5,0.15,15,25*2^(L-1)+50*L,science-pack-1,1,science-pack-2,1:3,5,0.2,20,25*2^(L-1)+75*L,science-pack-1,1,science-pack-2,1,science-pack-3,1:3,5,0.25,25,25*2^(L-1)+100*L,science-pack-1,1,science-pack-2,1,science-pack-3,1,high-tech-science-pack,1:3,0,0.3,30,200*L,science-pack-1,1,science-pack-2,1,science-pack-3,1,high-tech-science-pack,1,space-science-pack,1'
local percentage_description = function (value) return ('%g%%'):format(value * 100) end
local pluralize_description = function (unit) return function (value) return ('%d %s%s'):format(value, unit, value == 1 and '' or 's') end end
local config = {
    {
        name = 'crafting-speed',
        type = 'double',
        default_config = rational_default_config,
        fields = { 'manual_crafting_speed_modifier' },
        description_factory = percentage_description
    },
    {
        name = 'inventory-size',
        type = 'int',
        default_config = '0,2,5,15,125*L,science-pack-1,1:1,2,5,20,175*L,science-pack-1,1,science-pack-2,1:1,2,5,25,225*L,science-pack-1,1,science-pack-2,1,science-pack-3,1:1,2,5,30,300*L,science-pack-1,1,science-pack-2,1,science-pack-3,1,high-tech-science-pack,1',
        fields = { 'character_inventory_slots_bonus' },
        description_factory = pluralize_description('slot')
    },
    {
        name = 'mining-speed',
        type = 'double',
        default_config = rational_default_config,
        fields = { 'manual_mining_speed_modifier' },
        description_factory = percentage_description
    },
    {
        name = 'movement-speed',
        type = 'double',
        default_config = '0,5,0.05,10,25*2^(L-1)+25*L,science-pack-1,1:3,5,0.05,15,25*2^(L-1)+50*L,science-pack-1,1,science-pack-2,1:3,5,0.05,20,25*2^(L-1)+75*L,science-pack-1,1,science-pack-2,1,science-pack-3,1:3,5,0.05,25,25*2^(L-1)+100*L,science-pack-1,1,science-pack-2,1,science-pack-3,1,high-tech-science-pack,1:3,0,0.05,30,200*L,science-pack-1,1,science-pack-2,1,science-pack-3,1,high-tech-science-pack,1,space-science-pack,1',
        fields = { 'character_running_speed_modifier' },
        description_factory = percentage_description
    },
    {
        name = 'player-reach',
        type = 'int',
        default_config = '0,5,1,10,25*2^(L-1)+25*L,science-pack-1,1:3,5,1,15,25*2^(L-1)+50*L,science-pack-1,1,science-pack-2,1:3,5,2,20,25*2^(L-1)+75*L,science-pack-1,1,science-pack-2,1,science-pack-3,1:3,5,2,25,25*2^(L-1)+100*L,science-pack-1,1,science-pack-2,1,science-pack-3,1,high-tech-science-pack,1:3,0,3,30,200*L,science-pack-1,1,science-pack-2,1,science-pack-3,1,high-tech-science-pack,1,space-science-pack,1',
        fields =
        {
            'character_build_distance_bonus',
            'character_item_drop_distance_bonus',
            'character_resource_reach_distance_bonus',
            'character_reach_distance_bonus',
        },
        field_toggles =
        {
            { 'character_item_drop_distance_bonus', 'item-drop-distance' },
            { 'character_resource_reach_distance_bonus', 'resource-reach-distance' }
        },
        description_factory = pluralize_description('tile')
    },
    {
        name = 'toolbelts',
        type = 'int',
        default_config = '0,1,1,15,500,science-pack-1,1:1,1,1,30,500,science-pack-1,1,science-pack-2,1',
        fields = {
            'quickbar_count'
        },
        --[[effects_table_factory = function (amount)
            return { {
                type = 'num-quick-bars',
                modifier = amount
            } }
        end,]]
        description_factory = pluralize_description('belt')
    }
}
return config