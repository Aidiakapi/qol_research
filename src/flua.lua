--[=[

    Flua
    Library adds a functional iterator type.
    Version 0.1.0

    Types:
      flua
        Utilities to create source iterators.
      iterator
        The primary object to perform actions upon.
      list
        A sequential table (table where all keys of type number
        are consective in the range [1, n]).
      integer
        A whole number.
      any boolean
        Any value that will be tested for true-ness. Does not
        have to be of type 'boolean'.

    Terms:
      iterator
        A Flua iterator.
      native Lua iterator
        A stateful or stateless iterator for usage in the for-in loop.
      width
        Refers to the width of the n-tuple that is iterated over.
      element
        A single record in an iterator.
      value
        A single value inside an element.
      size
        Synonymous to count.
      invariant
        A value that does not change throughout iteration.
      control
        A value that is modified throughout iteration.

    Functions:
      flua.ipairs(list)
      flua.ivalues(list)
      flua.pairs(table)
      flua.values(table)
      flua.range([lower, ]upper)
      flua.infinite()
      flua.duplicate(n, value_1[, ..., value_n])

      iterator:iter()
      iterator:list()
      iterator:table()

      iterator:map(func[, new_width])
      iterator:flatmap(func[, new_width])
      iterator:filter(predicate)
      iterator:filtermap(func[, new_width])
      iterator:distinct()

      iterator:concat(iter)
      iterator:zip(iter)

      iterator:take(n)
      iterator:skip(n)

      iterator:reduce(aggregator, initial_value_1[, ..., initial_value_n])
      iterator:count()
      iterator:sum()
      iterator:average()
      iterator:min()
      iterator:max()

      iterator:all(predicate)
      iterator:any(predicate)
      iterator:contains(value_1[, ..., value_n])
    
    Detailed information about each function is found in the source code.
    All documentation is contained in comment blocks starting with --[=[

    ISC License

]=]

local flua, api = {}, {}
local iter_mt = { __index = api }
-- Use the maximum integer value of 32-bit float or 64-bit float
local MAXIMUM_INT_VALUE = ((16777216 + 1) == 16777216) and 16777216 or 9007199254740992
local lua_assert, assert = assert
if FLUA_DISABLE_ASSERT then
    assert = function () end
else
    assert = lua_assert
end


local function deep_copy(value)
    local copy = {}
    for key, subvalue in pairs(value) do
        if key == '_external' then
            copy._external = subvalue
        else
            if type(subvalue) == 'table' then
                copy[key] = deep_copy(subvalue)
            else
                copy[key] = subvalue
            end
        end
    end
    return copy
end

local function unpack_n(n, t, i)
    if n == 1 then return t[i] end
    return t[i], unpack_n(n - 1, t, i + 1)
end

local vs = setmetatable({}, {
    __index = function (self, index)
        assert(type(index) == 'number' and index >= 1)
        local vs = {}
        for i = 1, index do
            vs[i * 3 - 2] = 'v'
            vs[i * 3 - 1] = i
            vs[i * 3] = ', '
        end
        vs[#vs] = nil
        vs = table.concat(vs)
        rawset(self, index, vs)
        return vs
    end
})

local iter_return_n = setmetatable({}, {
    __index = function (self, index)
        assert(type(index) == 'number' and index >= 1)
        local vs = vs[index]
        local fn = load([[return function (invariant)
            local self, control = invariant._self, invariant._control
            local current_control = control[self._index]
            invariant._self = self._parent
            local new_control, ]] .. vs .. [[ = self._iterator(invariant, self._invariant, current_control)
            invariant._self = self
            control[self._index] = new_control
            return ]] .. vs .. [[
        end]], 'iter_return_n', 't')()
        rawset(self, index, fn)
        return fn
    end
})

local function iter_next(invariant)
    return iter_return_n[invariant._self._width](invariant)
end

local function mkiter(parent, width, size, iterator, invariant, control)
    local t = {
        _parent = parent,
        _index = parent and (parent._index + 1) or 1,
        _width = width,
        _size = size,
        _iterator = iterator,
        _invariant = invariant,
        _control = control
    }
    return setmetatable(t, iter_mt)
end

local function empty_next() end
local empty_iter = setmetatable({}, {
    __index = function (self, index)
        local iter = mkiter(nil, index, 0, empty_next, nil, nil)
        rawset(self, index, iter)
        return iter
    end
})

--[=[
    flua.ipairs(list) => iterator
    Creates an 2-wide iterator with indices and values similar to ipairs.

    Params:
      list  sequential table
        The list to iterate over.
    
    Returns:
      An iterator bound to the list.
    
    Remark:
      The list that is bound to must not be mutated.
]=]
local function ipairs_next(parent, invariant, control)
    control = control + 1
    if control > #invariant then return end
    return control, control, invariant[control]
end

function flua.ipairs(list)
    return mkiter(nil, 2, #list, ipairs_next, list, 0)
end

--[=[
    flua.ivalues(list) => iterator
    Creates a 1-wide iterator with solely the values from ipairs.

    Params:
      list  sequential table
        The list to iterate over.
    
    Returns:
      An iterator bound to the list.
    
    Remark:
      The list that is bound to must not be mutated.
]=]
local function ivalues_next(parent, invariant, control)
    control = control + 1
    if control > #invariant then return end
    return control, invariant[control]
end

function flua.ivalues(list)
    return mkiter(nil, 1, #list, ivalues_next, list, 0)
end

--[=[
    flua.pairs(table) => iterator
    Creates a 2-wide iterator with the keys and values from pairs.

    Params:
      table  any table
        The table to iterate.
    
    Returns:
      An iterator bound to the table.
    
    Remark:
      The table that is bound to must not be mutated.
]=]
local function pairs_next(parent, invariant, control)
    local k, v = next(invariant, control)
    return k, k, v
end
function flua.pairs(table)
    return mkiter(nil, 2, nil, pairs_next, table, nil)
end

--[=[
    flua.values(table) => iterator
    Creates a 1-wide iterator with solely the values from pairs.

    Params:
      table  any table
        The table to iterate.
    
    Returns:
      An iterator bound to the table.
    
    Remark:
      The table that is bound to must not be mutated.
]=]
local function values_next(parent, invariant, control)
    return next(invariant, control)
end
function flua.values(table)
    return mkiter(nil, 1, nil, values_next, table, nil)
end

--[=[
    flua.range([lower, ]upper) => iterator
    Creates a 1-wide iterator ranging from lower to upper.

    Params:
      lower  integer
        Optional. Specifies the lower bound. Default 1.
      upper  integer
        Specifies the inclusive upper bound.
    
    Returns:
      An iterator in range [lower, upper].
]=]
local function range_next(parent, invariant, control)
    if control > invariant then return end
    return control + 1, control
end
function flua.range(lower, upper)
    if not upper then
        lower, upper = 1, lower
    end
    if upper < lower then
        return empty_iter[1]
    end
    return mkiter(nil, 1, upper - lower + 1, range_next, upper, lower)
end

--[=[
    flua.infinite() => iterator
    Creates an indefinitely continuing iterator.

    Returns:
      A 1-wide iterator starting at 1 incrementing by 1 indefinitely.
]=]
local function infinite_next(parent, invariant, control)
    control = control + 1
    return control, control
end
local flua_infinite = mkiter(nil, 1, MAXIMUM_INT_VALUE, infinite_next, nil, 0)
function flua.infinite()
    return flua_infinite
end

--[=[
    flua.duplicate(n, value_1[, ..., value_w])
    Repeats an element with values [1..w] n times.

    Returns:
      An w-wide n-size iterator where each element is value_[1..w].
]=]
local function duplicate_next(parent, invariant, control)
    control = control + 1
    if control <= invariant.n then
        return control, unpack_n(invariant.w, invariant, 1)
    end
end
function flua.duplicate(n, ...)
    local w = select('#', ...)
    return mkiter(nil, w, n, duplicate_next, { n = n, w = w, ... }, 0)
end

--[=[
    iterator:iter() => native Lua iterator, invariant, control
    Creates an iterator for use with for-in loops.

    Returns:
      A native Lua iterator.
]=]
function api:iter()
    local control = {}
    for i = 1, self._index do control[i] = false end
    local current = self
    for i = self._index, 1, -1 do
        local current_control = current._control
        if type(current_control) == 'table' then
            control[i] = deep_copy(current_control)
        else
            control[i] = current_control
        end
        current = current._parent
    end

    return iter_next, { _control = control, _self = self }
end

--[=[
    iterator:list() => list
    Creates a list from a 1-wide iterator.

    Returns:
      The new list.
]=]
function api:list()
    assert(self._width == 1, 'list() can only be called on 1-wide iterators')
    local list = {}
    for v in self:iter() do
        list[#list + 1] = v
    end
    return list
end

--[=[
    iterator:table() => table
    Creates a table from a 2-wide iterator.

    Returns:
      A table where the keys are the first value in each element
      and the values are the second value in each element.

    Remark:
      If there are duplicate keys, the last value in the
      iterator is assigned.
]=]
function api:table()
    assert(self._width == 2, 'table() can only be called on 2-wide iterators')
    local table = {}
    for k, v in self:iter() do
        table[k] = v
    end
    return table
end

--[=[
    iterator:map(func[, new_width]) => iterator
    Maps all input values in an iterator to output values.

    Params:
      func  (in_1, ..., in_width) => out_1, ..., out_new_width
        Maps input values to output values.
        Remark, out_1 MUST NOT be nil, if it is, the behavior is undefined.
      new_width  integer
        Optional. The output width of the iterator. Default: input width.

    Returns:
      New iterator with the mapping applied.
]=]
local map_next_n = setmetatable({}, {
    __index = function (self, index)
        local vs = vs[index]
        local fn = load([[return function (parent, invariant)
            local ]] .. vs .. [[ = iter_next(parent)
            if v1 == nil then return end
            return nil, invariant(]] .. vs .. [[)
        end]], 'map_next_n', 't', { iter_next = iter_next })()
        rawset(self, index, fn)
        return fn
    end
})
function api:map(func, new_width)
    return mkiter(self, new_width or self._width, self._size, map_next_n[self._width], func, nil)
end

--[=[
    iterator:flatmap(func[, new_width]) => iterator
    Maps all input values to zero or more output values.
    
    Params:
      func  (in_1, ..., in_width) => iterator { width = new_width }
        Maps input values to zero or more output values.
        Remark, each returned iterator MUST BE new_width wide, otherwise
        the behavior is undefined.
      new_width  integer
        Optional. The output width of the iterator. Default: input width.
    
    Returns:
      New iterator with the mapping and flattening applied.
]=]
local flatmap_next_n = setmetatable({}, {
    __index = function (self, old_width)
        local tbl = setmetatable({}, {
            __index = function (self, new_width)
                local vs_old = vs[old_width]
                local vs_new = vs[new_width]
                local fn = load(([[return function (parent, invariant, control)
                    while true do
                        if control[1] == nil then
                            local %s = iter_next(parent)
                            -- End of parent iterator
                            if v1 == nil then return end
                            local iter = invariant(%s)
                            assert(iter._width == %d, 'flatmap: invalid iterator width, expected %d')
                            control[1], control[2], control[3] = iter:iter()
                        end
                        -- Iterate child
                        local %s = control[1](control[2], control[3])
                        control[3] = v1
                        if v1 ~= nil then
                            return control, %s
                        end
                        control[1], control[2], control[3] = nil, nil, nil
                    end
                end]]):format(vs_old, vs_old, new_width, new_width, vs_new, vs_new),
                'flatmap_next_n', 't', { assert = assert, iter_next = iter_next })()
                rawset(self, new_width, fn)
                return fn
            end
        })
        rawset(self, old_width, tbl)
        return tbl
    end
})
function api:flatmap(func, new_width)
    new_width = new_width or self._width
    return mkiter(self, new_width, nil, flatmap_next_n[self._width][new_width], func, {})
end

--[=[
    iterator:filter(predicate) => iterator
    Checks every value with a predicate to see if it should be preserved.

    Params:
      predicate  (in_1, ..., in_width) => any boolean
        A predicate determining whether the current value should be kept.
        
    Returns:
      New iterator with the filtering applied.
]=]
local filter_next_n = setmetatable({}, {
    __index = function (self, index)
        local vs = vs[index]
        local fn = load([[return function(parent, invariant)
            while true do
                local ]] .. vs .. [[ = iter_next(parent)
                if v1 == nil then return end
                if invariant(]] .. vs .. [[) then
                    return nil, ]] .. vs .. [[
                end
            end
        end]], 'filter_next_n', 't', { iter_next = iter_next })()
        rawset(self, index, fn)
        return fn
    end
})
function api:filter(predicate)
    return mkiter(self, self._width, nil, filter_next_n[self._width], predicate, nil)
end

--[=[
    iterator:filtermap(func[, new_width]) => iterator
    Performs mapping and filtering at the same. A value mapped to nil is filtered.

    Params:
      func  (in_1, ..., in_width) => out_1, ..., out_new_width
        Maps input values to output values.
        If out_1 is nil, the value is filtered.
      new_width  integer
        Optional. The output width of the iterator. Default: input width.

    Returns:
      New iterator with the mapping and filtering applied.
]=]
local filtermap_next_n = setmetatable({}, {
    __index = function (self, old_width)
        local tbl = setmetatable({}, {
            __index = function (self, new_width)
                local vs_old = vs[old_width]
                local vs_new = vs[new_width]
                local fn = load(([[return function (parent, invariant)
                    while true do
                        local %s = iter_next(parent)
                        if v1 == nil then return end
                        do
                            local %s = invariant(%s)
                            if v1 ~= nil then
                                return nil, %s
                            end
                        end
                    end
                end]]):format(vs_old, vs_new, vs_old, vs_new),
                'filtermap_next_n', 't', { iter_next = iter_next })()
                rawset(self, new_width, fn)
                return fn
            end
        })
        rawset(self, old_width, tbl)
        return tbl
    end
})
function api:filtermap(func, new_width)
    new_width = new_width or self._width
    return mkiter(self, new_width, nil, filtermap_next_n[self._width][new_width], func, nil)
end

--[=[
    iterator:distinct() => iterator
    Keeps unique elements from a 1-wide iterator.

    Returns:
      An iterator with only unique elements.
]=]
local function distinct_next_1(parent, invariant, control)
    while true do
        local v1 = iter_next(parent)
        if v1 == nil then return end
        if not control[v1] then
            control[v1] = true
            return control, v1
        end
    end
end
function api:distinct()
    assert(self._width == 1, 'wide iterators are not supported')
    return mkiter(self, self._width, nil, distinct_next_1, nil, {})
end

--[=[
    iterator:concat(iter) => iterator
    Combines the elements from two iterators.

    Params:
      iter  iterator
        The iterator whose elements follow the elements in
        the current iterator. Must be the same width.
    
    Returns:
      A new iterator combining the two iterators.
]=]
local concat_next_n = setmetatable({}, {
    __index = function (self, index)
        local vs = vs[index]
        local fn = load(([[return function (parent, invariant, control)
            -- Iterate self
            if not control then
                local %s = iter_next(parent)
                if v1 ~= nil then
                    return nil, %s
                end
                -- Move to second iterator
                control = { invariant:iter() }
            end
            local %s = control[1](control[2], control[3])
            control[3] = v1
            return control, %s
        end]]):format(vs, vs, vs, vs), 'concat_next_n', 't', { iter_next = iter_next })()
        rawset(self, index, fn)
        return fn
    end
})
function api:concat(iter)
    local new_size
    if self._size and iter._size then
        new_size = self._size + iter._size
    end
    if new_size == 0 then return empty_iter[self._width] end
    return mkiter(self, self._width, new_size, concat_next_n[self._width], iter, nil)
end

--[=[
    iterator:zip(iter) => iterator
    Combines the values in each element from two iterators.

    Params:
      iter  iterator
        The iterator whose values for each element are appended
        to the current iterator's element.
    
    Returns:
      A new iterator composing the two iterators.

    Remark:
      The returned iterator halts when the first of the two
      iterators halts.
]=]
local zip_next_n = setmetatable({}, {
    __index = function (self, index)
        local vs = vs[index]
        local fn = load(([[local function next_zip_store(control, %s, s1, ...)
            if s1 == nil then return end
            control[3] = s1
            return control, %s, s1, ...
        end
        
        return function (parent, invariant, control)
            local %s = iter_next(parent)
            if v1 == nil then return end
            return next_zip_store(control, %s, control[1](control[2], control[3]))
        end]]):format(vs, vs, vs, vs), 'zip_next_n', 't', { iter_next = iter_next })()
        rawset(self, index, fn)
        return fn
    end
})

function api:zip(iter)
    local new_size
    if self._size and iter._size then
        new_size = math.min(self._size, iter._size)
    end
    return mkiter(self, self._width + iter._width, new_size, zip_next_n[self._width], nil, { iter:iter() })
end

--[=[
    iterator:take(n) => iterator
    Takes the first n elements from the iterator.

    Params:
      n  integer
        The amount of elements to take. If the source
        iterator is shorter, it will stop early.
        When 0, an empty iterator is returned.
    
    Returns:
      New iterator that's limited to n elements.
]=]
local function take_next_n(parent, invariant, control)
    control = control + 1
    if control > invariant then return end
    return control, iter_next(parent)
end
function api:take(n)
    if n == 0 then return empty_iter[self._width] end
    local new_size
    if self._size then
        if self._size <= n then
            new_size = self._size
        else
            new_size = n
        end
    end
    return mkiter(self, self._width, new_size, take_next_n, n, 0)
end

--[=[
    iterator:skip(n) => iterator
    Skips the first n elements from the iterator.

    Params:
      n  integer
        The amount of elements to skip. If the source
        iterator is shorter, an empty iterator is returned.
    
    Returns:
      New iterator that skips the first n elements.
]=]
local function skip_next_n(parent, invariant, control)
    if not control then
        for i = 1, invariant do
            iter_next(parent)
        end
    end
    return true, iter_next(parent)
end
function api:skip(n)
    local new_size
    if self._size then
        new_size = self._size - n
        if new_size <= 0 then return empty_iter[self._width] end
    end
    return mkiter(self, self._width, new_size, skip_next_n, n, false)
end

--[=[
    iterator:reduce(aggregator, initial_value_1[, ..., initial_value_n])
        => result_1, ..., result_n
    Aggregates all data in the iterator into 1 or more result values.

    Params:
      aggregator  (accumulator_1, ..., accumulator_n, in_1, ..., in_width)
                  => new_accumulator_1, ..., new_accumulator_n
        A function that runs for each element in the iterator, the
        accumulator value(s) for the first element is initial_value_[1..n],
        for subsequent elements it is the result of the previous invocation
        of aggregator.
      initial_value_[1..n]  any
        The initial value(s) to use in the aggregation.

    Returns:
      The final value after the aggregation of all elements of each accumulator.
    
    Remark:
      Performs iteration.
]=]
local reduce_n = setmetatable({}, {
    __index = function (self, index)
        local vs = vs[index]
        local fn = load(([[return function (self, aggregator, %s)
            local iterator, invariant, control = self:iter()
            local function aggregator_wrapper(%s, c, ...)
                if c == nil then return false, %s end
                control = c
                return true, aggregator(%s, c, ...)
            end
            local not_done = true
            while not_done  do
                not_done, %s = aggregator_wrapper(%s, iterator(invariant, control))
            end
            return %s
        end]]):format(vs, vs, vs, vs, vs, vs, vs), 'reduce_n', 't')()
        rawset(self, index, fn)
        return fn
    end
})
function api:reduce(aggregator, ...)
    return reduce_n[select('#', ...)](self, aggregator, ...)
end

--[=[
    iterator:count() => integer
    Gets the element count in the iterator.

    Returns:
      The amount of elements in the iterator.

    Remark:
      May perform iteration.
]=]
function api:count()
    if self._size then return self._size end
    local count = 0
    for _ in self:iter() do
        count = count + 1
    end
    return count
end

--[=[
    iterator:sum() => number
    Sums the values in the 1-wide numeric iterator.

    Returns:
      The sum of the values.
    
    Remark:
      Performs iteration.
]=]
function api:sum()
    assert(self._width == 1, 'sum() can only be called on 1-wide iterators')
    local sum = 0
    for v in self:iter() do
        sum = sum + v
    end
    return sum
end

--[=[
    iterator:average() => number
    Averages the values in the 1-wide numeric iterator.

    Returns:
      The average of the values.
    
    Remark:
      Performs iteration.
]=]
function api:average()
    assert(self._width == 1, 'average() can only be called on 1-wide iterators')
    if self._size then
        return self:sum() / self._size
    end
    local count, sum = 0, 0
    for v in self:iter() do
        count, sum = count + 1, sum + v
    end
    return sum / count
end

--[=[
    iterator:min() => number
    Gets the smallest value from 1-wide numeric iterator.

    Returns:
      The smallest value or nil if the iterator is empty.
    
    Remark:
      Performs iteration.
]=]
function api:min()
    assert(self._width == 1, 'min() can only be called on 1-wide iterators')
    local iterator, invariant, control = self:iter()
    control = iterator(invariant, control)
    local min = control
    if control ~= nil then
        while true do
            control = iterator(invariant, control)
            if control == nil then break end
            if control < min then min = control end
        end
    end
    return min
end

--[=[
    iterator:max() => number
    Gets the largest value from 1-wide numeric iterator.

    Returns:
      The largest value or nil if the iterator is empty.
    
    Remark:
      Performs iteration.
]=]
function api:max()
    assert(self._width == 1, 'max() can only be called on 1-wide iterators')
    local iterator, invariant, control = self:iter()
    control = iterator(invariant, control)
    local max = control
    if control ~= nil then
        while true do
            control = iterator(invariant, control)
            if control == nil then break end
            if control > max then max = control end
        end
    end
    return max
end

local function invoke_predicate(predicate, v1, ...)
    if v1 == nil then return nil end
    return v1, predicate(v1, ...)
end

--[=[
    iterator:all(predicate) => boolean
    Checks if all elements in the iterator abide by the condition.

    Params:
      predicate  (value_1, ..., value_width) => any boolean
        A function that checks a provided condition.
    
    Returns:
      A boolean indicating if the condition was met on all elements.
]=]
function api:all(predicate)
    local iterator, invariant, control = self:iter()
    local result
    while true do
        control, result = invoke_predicate(predicate, iterator(invariant, control))
        if control == nil then return true end
        if not result then return false end
    end
end

--[=[
    iterator:all(predicate) => boolean
    Checks if any element in the iterator abide by the condition.

    Params:
      predicate  (value_1, ..., value_width) => any boolean
        A function that checks a provided condition.
    
    Returns:
      A boolean indicating if the condition was met on any element.
]=]
function api:any(predicate)
    local iterator, invariant, control = self:iter()
    local result
    while true do
        control, result = invoke_predicate(predicate, iterator(invariant, control))
        if control == nil then return false end
        if result then return true end
    end
end

local contains_n = setmetatable({}, {
    __index = function (self, index)
        local vs = vs[index]
        local es = vs:gsub('v', 'e')
        local condition = {}
        for i = 1, index do
            condition[#condition + 1] = 'e'
            condition[#condition + 1] = i
            condition[#condition + 1] = ' == '
            condition[#condition + 1] = 'v'
            condition[#condition + 1] = i
            condition[#condition + 1] = ' and '
        end
        condition[#condition] = nil
        condition = table.concat(condition)
        local fn = load(([[return function (self, %s)
            for %s in self:iter() do
                if %s then
                    return true
                end
            end
            return false
        end]]):format(vs, es, condition), 'contains_n', 't')()
        rawset(self, index, fn)
        return fn
    end
})
function api:contains(...)
    local n = select('#', ...)
    assert(self._width == n, 'wrong number of arguments to flua:contains')
    return contains_n[n](self, ...)
end

return flua
