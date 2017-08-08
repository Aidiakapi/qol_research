--[[

    Small function programming library written by Aidiakapi.
    Version 0.1.0

    See the documentation in the code for specific usage of functions.

    Example:
    ```lua
    local flua = require('flua')
    local data = flua.range(5, 10):map(function (v) return v  * 2 end):concat(flua.range(4)):list()
    print(table.concat(data, ', '))
    -- prints: 10, 12, 14, 16, 18, 20, 1, 2, 3, 4
    ```

    Root functions:
        flua.index(table[, skip])     Creates an index-based iterator (similar to ipairs), optionally skipping initial indices.
        flua.keys(table)              Creates a key-based iterator (similar to pairs).
        flua.range([lower, ]upper)    Creates an iterator where both key and value are a sequence of numbers.
        flua.pattern(string, pattern) Creates an iterator that behaves like string:gsub.

    Iterator functions:
        [Meta]
        api:iter()            Returns the iterator that can be used in the `for ... in` loop.
        api:is_stateful()     Returns whether the iterator is stateful.
        
        [Transform]
        api:map(func)         Maps input values to output values.
        api:flatmap(func)     Maps an input to zero or more output values.
        api:filter(predicate) Removes elements from the iterator that do not satisfy the condition.
        api:filtermap(func)   Combines filtering with mapping, if the mapping function returns nil, it is filtered.
        api:take(n)           Takes the first n elements from the iterator.
        api:skip(n)           Skips the first n elements from the iterator.
        api:sequence()        Turns the iterator keys into sequential keys (1..n where n is the length).
        api:concat(iter)      Combines two iterators to create one where self is followed by iter.

        [Aggregation]
        api:reduce(func, initial_value)  Performs a left-fold on the iterator elements (aggregation).
        api:count()           Counts the number of elements in the iterator.
        api:sum()             Sums all values in the iterator.
        api:average()         Averages all values in the iterator.
        api:min()             Returns the minimum value in the iterator.
        api:max()             Returns the maximum value in the iterator.

        [Condition]
        api:all(predicate)    Checks if all values match a condition.
        api:any(predicate)    Checks if any value matches a condition.
        api:contains(object)  Checks if any value equals object.
        api:contains_key(object)  Checks if any key equals the object.

        [Search]
        api:first([predicate])   Finds the first item satisfying the predicate.
        api:single([predicate])  Returns the only item satisfying the predicate.

        [Collection]
        api:table()           Stores all keys and values of the iterator in a table.
        api:list()            Stores all values of the iterator in a list (sequential table).
        api:set()             Stores all keys with unique values of the iterator in a table.
        api:distinct()        Stores all unique values of the iterator in a list (sequential table).

    ISC License

]]
local metatable, api = {}, {}
metatable.__index = api

-- Meta
local function empty_next() -- Represents an empty iterator
    return
end
local empty_iter = setmetatable({ empty_next, false, false, false, 0 }, metatable)

local function iter_copy(variant)
    local copy = {}
    for k, v in pairs(variant) do
        if type(v) == 'table' then
            copy[k] = iter_copy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

--- Call to create an iterator for usage with the `for ... in` loop.
function api:iter()
    if self[4] then
        return self[1], iter_copy(self[2]), self[3]
    end
    return self[1], self[2], self[3]
end

--- Checks whether the iterator that would be returned by `:iter()` is stateful or not.
--- Stateful iterators may only be used once in a `for ... in` loop, whilst stateless
--- iterator can be reused.
function api:is_stateful()
    return self[4]
end

-- Transforms
local function map_next(invariant, control)
    local v1, v2 = invariant[2](invariant[3], control)
    if v1 == nil then return end
    return v1, invariant[1](v2, v1)
end
--- Maps values from a previous state to a new state.
--- @param  func  function(value, key) => new_value
---               Function that maps original values to new values.
function api:map(func)
    return setmetatable({ map_next, { func, self[1], self[2] }, self[3], self[4], self[5] }, metatable)
end

local function flatmap_next(variant, control)
    while true do
        -- Currently iterating a mapping
        if variant[5] then
            local k, v = variant[5](variant[6], variant[7])
            if k == nil then
                variant[5], variant[6], variant[7] = nil, nil, nil
            else
                variant[7] = k
                return variant[4], v
            end
        -- Advance the root iterator
        else
            local k, v = variant[2](variant[3], variant[4])
            -- End of iteration
            if k == nil then
                return nil
            end
            variant[4] = k

            -- Perform the mapping
            local result = variant[1](v, k)
            if type(result) == 'table' then
                if getmetatable(result) == metatable then
                    variant[5], variant[6], variant[7] = result:iter()
                else
                    variant[5], variant[6], variant[7] = ipairs(result)
                end
            elseif type(result) ~= 'nil' then
                error('flatmaps mapping function must return an iterator, a list or nil', 2)
            end
        end
    end
end
--- Maps a single value to zero or more output values.
--- @param  func  function(value, key) => nil|iterator|{ new_values... }
---               Function that maps a single value to zero or more outputs.
--- @remark This creates a stateful iterator.
function api:flatmap(func)
    if self[5] == 0 then return empty_iter end
    return setmetatable({ flatmap_next, { func, self[1], self[2], self[3] }, false, true }, metatable)
end

local function filter_next(invariant, control)
    while true do
        local v1, v2 = invariant[2](invariant[3], control)
        if v1 == nil then return end
        if invariant[1](v2, v1) then
            return v1, v2
        end
        control = v1
    end
end
--- Filters an iterator so it only contains elements matching a condition.
--- @param  predicate  function(value, key) => boolean  Used to test each element.
function api:filter(predicate)
    return setmetatable({ filter_next, { predicate, self[1], self[2] }, self[3], self[4] }, metatable)
end

local function filtermap_next(invariant, control)
    while true do
        local v1, v2 = invariant[2](invariant[3], control)
        if v1 == nil then return end
        v2 = invariant[1](v2, v1)
        if v2 ~= nil then
            return v1, v2
        end
        control = v1
    end
end
--- Combines filter and map, returning a nil from the mapping function will filter it.
--- @param  func  function(value, key) => nil|new_value  Used to test each element.
function api:filtermap(func)
    return setmetatable({ filtermap_next, { func, self[1], self[2] }, self[3], self[4] }, metatable)
end

local function take_next(variant, control)
    if variant[1] >= variant[2] then return end
    variant[1] = variant[1] + 1
    return variant[3](variant[4], control)
end
--- Takes the first n elements from the iterator.
--- @param  n  number  The maximum amount of elements to take.
--- @remark This creates a stateful iterator.
function api:take(n)
    local new_length
    if self[5] then
        new_length = self[5] < n and self[5] or n
    end
    if new_length == 0 then
        return empty_iter
    end
    return setmetatable({ take_next, { 0, n, self[1], self[2] }, self[3], true, new_length }, metatable)
end

local function skip_next(invariant, control)
    -- If we're at the start
    if control == invariant[1] then
        -- Skip n elements
        for i = 1, invariant[2] do
            control = invariant[3](invariant[4], control)
            if control == nil then return end
        end
    end
    return invariant[3](invariant[4], control)
end
--- Skips the first n elements from the iterator.
--- @param  n  number The maximum amount of elements to skip.
function api:skip(n)
    local new_length
    if self[5] then
        if self[5] <= n then
            return empty_iter
        end
        new_length = self[5] - n
    end
    return setmetatable({ skip_next, { self[3], n, self[1], self[2] }, self[3], self[4], new_length }, metatable)
end

local function sequence_next(variant, control)
    control = control + 1
    local k, v = variant[1](variant[2], variant[3])
    variant[3] = k
    if k == nil then return end
    return control, v
end
--- Changes all keys to become a sequence (1..n).
--- @remark This creates a stateful iterator.
function api:sequence()
    if self[5] == 0 then return empty_iter end
    return setmetatable({ sequence_next, { self[1], self[2], self[3] }, 0, true, self[5] }, metatable)
end

local function concat_next(variant)
    if not variant[1] then
        local k, v = variant[2](variant[3], variant[4])
        if k ~= nil then
            variant[4] = k
            return k, v
        end
        variant[1] = true
    end
    local k, v = variant[5](variant[6], variant[7])
    if k == nil then return end
    variant[7] = k
    return k, v
end
--- Concatenates an iterator to the current iterator
--- @param  iter  Iterator returned by calling `flua`, `flua.index` or `flua.keys`.
--- @remark This creates a stateful iterator.
function api:concat(iter)
    local new_length
    if self[5] and iter[5] then
        new_length = self[5] + iter[5]
    end
    return setmetatable({ concat_next, { false, self[1], self[2], self[3], iter[1], iter[2], iter[3] }, nil, true, new_length }, metatable)
end

-- Aggregations
--- Performs left-folding on the iterator.
--- @param  func  function(accumulator, value, key) => new_accumulator
---               Executed for every element in the iterator. For the first element
---               the value of accumulator is set to initial_value, for subsequent
---               elements it is the result of calling func on the preceding element.
--- @param  initial_value  any  The initial value of the accumulator

function api:reduce(func, initial_value)
    for v1, v2 in self:iter() do
        initial_value = func(initial_value, v2, v1)
    end
    return initial_value
end

--- Counts the amount of items in the iterator.
function api:count()
    -- self:reduce(function (acc) return acc + 1 end, 0)
    if self[5] then return self[5] end
    local c = 0
    for _ in self:iter() do
        c = c + 1
    end
    return c
end

--- Computes the sum of all values in the iterator. The iterator must have numerical values.
function api:sum()
    -- self:reduce(function (acc, value) return acc + value end, 0)
    local s = 0
    for _, v in self:iter() do
        s = s + v
    end
    return s
end

--- Computes the average of values in the iterator. The iterator must have numerical values.
function api:average()
    if self[5] then return self:sum() / self[5] end
    local sum, count = 0, 0
    for _, v in self:iter() do
        sum, count = sum + v, count + 1
    end
    return sum / count
end

--- Computes the minimum of values in the iterator. The iterator must have numerical values.
--- @remark Returns nil when the iterator is empty.
function api:min()
    local m
    for _, v in self:iter() do
        if m == nil or v < m then m = v end
    end
    return m
end

--- Computes the maximum of values in the iterator. The iterator must have numerical values.
--- @remark Returns nil when the iterator is empty.
function api:max()
    local m
    for _, v in self:iter() do
        if m == nil or v > m then m = v end
    end
    return m
end

-- Conditions
--- Checks if all of the elements in the collection passes a condition.
--- @param  predicate  function(value, key) => boolean  Used to test each element.
function api:all(predicate)
    for v1, v2 in self:iter() do
        if not predicate(v2, v1) then
            return false
        end
    end
    return true
end

--- Checks if any of the elements in the collection passes a condition.
--- @param  predicate  function(value, key) => boolean  Used to test each element.
function api:any(predicate)
    for v1, v2 in self:iter() do
        if predicate(v2, v1) then
            return true
        end
    end
    return false
end

--- Checks if any of the values equals object.
--- @param  object  any  The object to check for.
function api:contains(object)
    for _, v in self:iter() do
        if v == object then
            return true
        end
    end
    return false
end

--- Checks if any of the keys equals object.
--- @param  object  any  The object to check for.
function api:contains_key(object)
    for v in self:iter() do
        if v == object then
            return true
        end
    end
    return false
end

-- Search
function api:first(predicate)
    if not predicate then
        for k, v in self:iter() do return k, v end
        return
    end
    for k, v in self:iter() do
        if predicate(v, k) then
            return k, v
        end
    end
end

function api:single(predicate)
    local fk, fv
    if not predicate then
        for k, v in self:iter() do
            if fk then return end
            fk, fv = k, v
        end
        if fk then
            return fk, fv
        end
        return
    end
    for k, v in self:iter() do
        if predicate(v, k) then
            if fk then return end
            fk, fv = k, v
        end
    end
    if fk then
        return fk, fv
    end
end

-- Collections

--- Creates a table based on the keys and values in the iterator.
--- @remark When there are duplicate keys, the latest value will be used.
function api:table()
    local tbl = {}
    for v1, v2 in self:iter() do
        tbl[v1] = v2
    end
    return tbl
end
--- Creates a list (sequential table) of the values in the iterator.
function api:list()
    local tbl = {}
    for _, v in self:iter() do
        tbl[#tbl + 1] = v
    end
    return tbl
end
--- Creates a unique set of values. If multiple keys map to the same value, the first key is used.
--- @remark When there are duplicate keys, the latest key will be used.
function api:set()
    local unique, tbl = {}, {}
    for v1, v2 in self:iter() do
        if not unique[v2] then
            unique[v2] = true
            tbl[v1] = v2
        end
    end
    return tbl
end
--- Creates a unique list (sequential table) of values in the iterator.
function api:distinct()
    local unique, tbl = {}, {}
    for _, v in self:iter() do
        if not unique[v] then
            unique[v] = true
            tbl[#tbl + 1] = v
        end
    end
    return tbl
end

local flua = {}

function flua.index(table, skip)
    if table == nil then return empty_iter end
    local iterator, invariant, control = ipairs(table)
    if skip ~= nil then
        assert(type(skip) == 'number' and skip >= 0)
        return flua(iterator, invariant, control + skip, #table - skip)
    end
    return flua(iterator, invariant, control, #table)
end
function flua.keys(table)
    if table == nil then return empty_iter end
    return flua(pairs(table))
end

local function range_next(invariant, control)
    control = control + 1
    if control <= invariant then
        return control, control
    end
end
--- Generates a range between lower and upper
--- @param [lower] number  The optional lower bound of the range.
--- @param  upper  number  The upper bound of the range.
--- @remark Both lower and upper are inclusive. Lower is optional.
function flua.range(lower, upper)
    if not upper then
        upper = lower
        lower = 1
    elseif lower > upper then
        return empty_iter
    end

    return flua(range_next, upper, lower - 1, upper - lower + 1)
end

local function pattern_next(variant, control)
    variant[1] = variant[1] + 1
    control = control + 1
    local s, e = string.find(variant[2], variant[3], variant[1])
    if not s then return end
    variant[1] = e
    return control, string.sub(variant[2], s, e)
end
--- Creates an iterator that matches a pattern in a string.
--- The returned iterator contains has index as key and the
--- match as value.
--- @param  string  string   The string to perform matching on.
--- @param  string  pattern  The pattern to match on the string.
--- @remark Does NOT support captures in the pattern.
--- Example:
--- print(table.concat(flua.pattern('hello world this is a string', '%a+ +%a+'):table(), ', '))
--- prints: 'hello world, this is, a string'
function flua.pattern(string, pattern)
    return flua(pattern_next, { 0, string, pattern }, 0, nil, true)
end

return setmetatable(flua, {
    __call = function (self, iterator, invariant, control, initial_size, stateful)
        return setmetatable({ iterator, invariant, control, not not stateful, initial_size }, metatable)
    end
})
