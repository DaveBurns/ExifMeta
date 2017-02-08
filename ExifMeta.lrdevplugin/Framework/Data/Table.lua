--[[
        Table.lua
        
        Class of singleton object with utiility methods for "helping" with tables..
--]]

local Table, dbg, dbgf = Object:newClass{ className='Table', register=false }



--- Constructor for extending class.
--
function Table:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function Table:new( t )
    return Object.new( self, t )
end



--  Compute md5 over table elements.
--
function Table:_md5( t )

    if t == nil then return end
    
    if self.visited [t] then return end
    self.visited [t] = true
    
    if type( t ) ~= 'table' then
        local val = str:to( t )
        -- app:logInfo( "val-t: " .. val )
        self.md5str[#self.md5str + 1] = val
    else
        for k,v in pairs( t ) do
            if type( v ) == 'table' then
                self:_md5( v )
            else
                local val = str:to( v )
                -- app:logInfo( "val-tv, key: " .. str:to( k ) .. ", val: " .. val )
                self.md5str[#self.md5str + 1] = val
            end
        end 
    end
end



--- Compute md5 over table elements.
--
function Table:md5( t )
    self.md5str = {}
    self.visited = {}
    self:_md5( t )
    local str = table.concat( self.md5str, '' )
    local md5 = LrMD5.digest( str )
    return md5
end



--- Get array of sorted keys.
--
--  @usage used by sorted-pairs iterator function, dunno if anywhere else..
--
function Table:arrayOfSortedKeys( t, sortFunc, reverse )
    local a = {}
    for k in pairs( t ) do
        a[#a + 1] = k
    end
    if reverse then
        self:sortReverse( a, sortFunc )
    else
        table.sort( a, sortFunc )
    end
    return a
end



--- Return iterator that feeds k,v pairs back to the calling context, keys sorted according to the specified sort function.
--      
--  @usage      sort-func may be nil, in which case default sort order is employed.
--      
--  @return     iterator function
--
function Table:sortedPairs( t, sortFunc, reverse )
    local a = self:arrayOfSortedKeys( t, sortFunc, reverse )
    local i = 0
    return function()
        i = i + 1
        return a[i], t[a[i]]
    end
end



--- Sort a homogeneous table in reverse of what you can do with the normal table-sort function, including the stubborn last element.
--
--  @usage *** deprecated -- use proper sort function instead, then reverse the result - use table__sort-reverse instead.
-- 
--  @param t the table
--  @param reverseSortFunc -- a "reversed sense" sort function.
--  @param dummy (same type as a array elements, optional if string or number type elements)
--
--  @usage My experience is that sometimes you want the exact opposite order than what a normal sort is capable of yielding.<br>
--         in this case, simply having a unique dummy element (that is guaranteed to be "less" than any of the others) to push through solves the problem.
--  @usage Returns nothing - sorts in place, like reglar table.sort function.
--  @usage throws error if unable to sort properly.
--         
function Table:reverseSort( t, reverseSortFunc, dummy )
    if t == nil or #t == 1 then
        return -- won't get any more sorted...
    end
    local tc = self:copy( t ) -- make shallow copy
    if dummy == nil then
        if type( t[1] ) == 'string' then
            dummy = string.rep( string.char( 0 ), 15 ) .. "___dUmMy___" -- 3 underscores on each side. - must be less than any other string in the list (and unique).
        elseif type( t[1] ) == 'number' then
            dummy = 0 - math.huge -- negative infinity.
        else
            error( "dummy must be supplied if not string or number elements" )
        end
    end
    tc[#tc + 1] = dummy
    table.sort( tc, reverseSortFunc )
    local index = 1
    for i = 1, #tc do
        if tc[i] ~= dummy then
            t[index] = tc[i]
            index = index + 1
        else
            -- skip it.        
        end
    end
    if index == #tc then -- exactly one dummy found, meaning the dummy was unique.
        -- good
    else
        error( str:fmt( "invalid dummy (^1 duplicates) - sort reverseSortFunction failed", #tc - index ) )
    end
end



--- Creates a table sorted in reverse of what you can do with the normal table-sort function, including the stubborn last element.
--
--  @usage *** deprecated -- use proper sort function instead, then reverse the result - use table__sort-reverse-copy instead.
-- 
--  @param t the table
--  @param reverseSortFunc -- a "reversed sense" sort function.
--  @param dummy (same type as a array elements, optional if string or number type elements)
--
--  @usage My experience is that sometimes you want the exact opposite order than what a normal sort is capable of yielding.<br>
--         in this case, simply having a unique dummy element (that is guaranteed to be "less" than any of the others) to push through solves the problem.
--         
--  @return  "Reverse" sorted copy, if possible, otherwise original is returned - original array is always unmodified.
--  @return  Error message string if unable to sort properly.
--         
function Table:reverseSortCopy( t, reverseSortFunc, dummy )
    if t == nil or #t == 1 then
        return -- won't get any more sorted...
    end
    local tc = self:copy( t ) -- make shallow copy
    if dummy == nil then
        if type( t[1] ) == 'string' then
            dummy = string.rep( string.char( 0 ), 15 ) .. "___dUmMy___" -- 3 underscores on each side. - must be less than any other string in the list (and unique).
        elseif type( t[1] ) == 'number' then
            dummy = 0 - math.huge -- negative infinity.
        else
            error( "dummy must be supplied if not string or number elements" )
        end
    end
    tc[#tc + 1] = dummy
    table.sort( tc, reverseSortFunc )
    local t2 = {}
    local index = 1
    for i = 1, #tc do
        if tc[i] ~= dummy then
            t2[index] = tc[i]
            index = index + 1
        else
            -- skip it.        
        end
    end
    if index == #tc then -- exactly one dummy found, meaning the dummy was unique.
        return t2
    else
        return t, str:fmt( "invalid dummy (^1 duplicates) - sort reverseSortFunction failed", #tc - index )
    end
end



--- Sort table without altering it, and return a sorted copy, reversed.
--
--  @param t - the table
--  @param func - a proper sort function.
--
function Table:sortReverseCopy( t, func )
    local t = self:copy( t )
    table.sort( t, func )
    return self:reverseArray( t )
end



--- Sort table in place, reversed.
--
--  @param t - the table
--  @param func - a proper sort function.
--
function Table:sortReverse( t, func )
    table.sort( t, func )
    self:reverseInPlace( t )
end



--- Reverse an array in place.
--
function Table:reverseInPlace( t )
    if t == nil or #t == 1 then
        return
    end
    local function swap( j, k )
        local temp = t[j]
        t[j] = t[k]
        t[k] = temp
    end
    for i = 1, math.floor( #t / 2 ) do
        swap( i, #t - i + 1 )
    end
    return t
end



--- Reverse table array order.
--
--  @usage another way to achieve correct order when the sort function won't give it -<br>
--         sort the opposite of what you want, then reverse.
--
--  @return reversed array - the input table remains unaltered.
--
function Table:reverseArray( t )
    local t2 = {}
    local index = 1
    for i = #t, 1, -1 do
        t2[index] = t[i]
        index = index + 1
    end
    return t2
end



--- Determine if table has no elements.
--      
--  @usage      Determine if specified variable includes at least one item in the table, either at a numeric index or as key/value pair.
--      
--  @return     boolean
--
function Table:isEmpty( t )
    if t == nil then return true end
    if #t > 0 then return false end
    for _,__ in pairs( t ) do
        return false
    end
    return true
end



--- Determine if table has any elements.
--      
--  @usage      Determine if specified variable includes at least one item in the table, either at a numeric index or as key/value pair.
--      
--  @return     boolean
--
function Table:isNotEmpty( t )
    if t == nil then return false end
    if type( t ) ~= 'table' then error( "t must be table, not "..type( t ), 2 ) end
    if #t > 0 then return true end
    for _,__ in pairs( t ) do
        return true
    end
    return false
end
Table.hasItems = Table.isNotEmpty -- function Table:hasItems( t ) - synonym.



--- Determine if passed parameter is a table with at least one non-nil element (whether array or set/struct or hybrid..).
--
--  @usage Note: like str-is method, this function will throw error if non-nil argument isn't a table (e.g. is a string or boolean).
--
function Table:is( t, valueTitle )
    if t ~= nil then
        if type( t ) == 'table' then
            return not self:isEmpty( t ) -- this method assumes table type.
        else
            app:callingError( "expected \"^1\" value to be table, not ^2", valueTitle or "unnamed", type( t ) )
        end
    else -- nil is simply considered not a table.
        return false
    end
end



--- Determine if passed parameter represents a table containing values at numeric indexes.
--
function Table:isArray( t, valueTitle )
    if t ~= nil then
        if type( t ) == 'table' then
            return #t > 0
        else
            app:callingError( "expected \"^1\" value to be table, not ^2", valueTitle or "unnamed", type( t ) )
        end
    else -- nil is simply considered not an array.
        return false
    end
end



--- Count non-nil items in table.
--      
--  @usage     includes items at all indexes, be they numeric array indexes or others.
--
function Table:countItems( t, excl )
    local count = 0
    for k, v in pairs( t ) do -- look at all items (up through last non-nil item).
        if v ~= excl then -- if not excluded (e.g. 'false'),
            count = count + 1 -- count it.
        end
    end
    return count
end



--- Appends one array to another.
--
--  @usage      the first array is added to directly, and then returned.
--
function Table:appendArray( t1, t2 )
    for i = 1, #t2 do
        t1[#t1 + 1] = t2[i]
    end
    return t1
end



--- Appends one or more arrays to another.
--
--  @usage      the first array is added to directly, and then returned.
--
function Table:appendArrays( t1, ... )
    for i, a in ipairs{ ... } do
        self:appendArray( t1, a )
    end
    return t1
end



--- Removes duplicates from an array.
--  @return a *new* array without the duplicates.
function Table:removeDuplicates( a1 )
    local a = {}
    local s = {}
    for i, v in ipairs( a1 ) do
        if not s[v] then
            s[v] = true
            a[#a + 1] = v
        -- else dup: ignore.
        end
    end
    return a
end
Table.removeDups = Table.removeDuplicates -- function Table:removeDups( ... ) -- compact synonym..



--- Searches for an item in an array (starting at index 1).
--
--  @usage             very inefficient to call this repeatedly in a loop.
--
--  @return            index where found, or 0 if not found.
--
function Table:findInArray( t1, item )

    if tab:is( t1 ) then -- table type, and non-empty.
        for i = 1, #t1 do
            if t1[i] == item then
                return i
            end
        end
    end
    return 0

end



--- Searches for an item in an array.
--
--  @usage             very inefficient to call this repeatedly in a loop.
--
--  @return            boolean
--
function Table:isFoundInArray( t1, item )
    return ( self:findInArray() > 0 )
end



--- Like "append", except creates a new array.
--      
--  @usage             Does not check for item duplication.
--      
--  @return            new array = combination of two passed arrays.
--
function Table:combineArrays( t1, t2 )
    local t = {}
    if t1 ~= nil then
        for k,v1 in ipairs( t1 ) do
            t[#t + 1] = v1
        end
    end
    if t2 ~= nil then
        for i,v2 in ipairs( t2 ) do
            t[#t + 1] = v2
        end
    end
    return t
end




--- Like "combine", except DOES check for item duplication.
--      
--  @usage      good for coming up with a new array that includes all items from the passed arrays.
--      
--  @return     new array.
--
function Table:mergeArrays( t1, t2 )
    local t = {}
    local lookup = {}
    if t1 then
        for k,v1 in ipairs( t1 ) do
            t[#t + 1] = v1
            lookup[v1] = true
        end
    end
    if t2 then
        for i,v2 in ipairs( t2 ) do
            if not lookup[v2] then
                t[#t + 1] = v2
            end
        end
    end
    return t
end



--- Adds items in one table to another.
--
--  @usage      adds all t2 items to t - nothing is returned.
--  @usage      Note: values of t2 will overwrite same-key values of t, so make sure thats what you want...
--      
--  @param      t      a table of key-value pairs to be added to.
--  @param      t2     a table of key-value pairs to add.
--
--  @return     t       - the original table with additions..
--      
function Table:addItems( t, t2 )
    if t2 ~= nil then
        for k, v in pairs( t2 ) do
            t[k] = v
        end
    end
    return t
end



--- Remove items from one table specified by another.
--
--  @usage useful instead of removing items from table in pairs loop, for example.
--
function Table:removeItems( t, t2 )
    for k, v in pairs( t2 ) do
        t[k] = nil
    end
end



--  Replaced the above on 9/Apr/2014 22:32 (seems to work just fine) - delete above-mentioned fn and remove this comment if no troubles by 2015.
--
--- Merge two or more sets.
--
--  @usage creates a new set by combining one or more sets.
--
--  @param ... zero or more sets actually - if zero: empty set will be returned, if one, a shallow copy of it will be returned,
--      <br>if two then the first with common keyed elements overwritten by the second... 
--
--  @return new set - values can be whatever (e.g. can be used for lookup too, not just a "pure" set..).
--
function Table:mergeSets( ... )
    local t = {}
    for i, v in ipairs{ ... } do
        --Debug.lognpp( v )
        self:addItems( t, v )
    end
    return t
end



--- Make a shallow copy of a table.
--
--  @usage Useful for when you have a table and need to make a mod, but don't want to modify the original.
--  @usage Shallow is OK when it doesn't matter if copy values point to same tables/functions as source (or all elements are non-table/non-function values).
--
function Table:copy( t )
    return self:addItems( {}, t )
end



--- Make a deep copy of a table.
--
--  @usage All table members will be new copied versions, *except* (@13/Dec/2013 6:22) for functions, which will still be references.
--
function Table:deepCopy( t )
    local _cnt = 0 -- sanity counter
    local c = {}
    local v = {}
    local function addItems( _c, _t )
        if v[_t] then return end -- prevent circular references
        v[_t] = true -- been here, done that...
        _cnt = _cnt + 1
        Debug.pauseIf( _cnt == 100000 ) -- insane? (stop debug if infinite loop).
        for k, val in pairs( _t ) do
            if type( val ) == 'table' then
                _c[k] = {}
                addItems( _c[k], val )
            else
                _c[k] = val
            end
        end
    end
    addItems( c, t )
    --[[ *** seems to be working - uncomment if suspicious..
    if app:isAdvDbgEna() then
        if not tab:isEquiv( c, t ) then
            Debug.lognpp( t )
            Debug.lognpp( c )
            Debug.showLogFile()
            Debug.pause()
        end
    end
    --]]
    return c
end



--- Set table member access strictness policy.
--
--  @param t (table, required) the table to make strict access policy.
--  @param write (boolean, default false) true => strict write access, false => lax.
--  @param read (boolean, default false) true => strict read access, false => lax.
--
--  @usage Do not use for _G - use global-specific set-strict method instead.
--  @usage Useful for closing a table (strict) so accidental assignment or access is caught immediately.
--  @usage Note: one can always use rawset and rawget directly to bypass strictness completely.
--
function Table:setStrict( t, write, read )
    local mt = getmetatable(t)
    if mt == nil then
        mt = { __declared = {} }
        setmetatable( t, mt )
    elseif not mt.__declared then
        mt.__declared = {}
    end
    if write then
        -- *** blindly overwrites previous new-index function.
        mt.__newindex = function (t, n, v)
            if n == nil then return end
            if not mt.__declared[n] then
                local w = debug.getinfo(2, "S").what
                if w ~= 'C' then
                    error("assign to undeclared lua table member '"..n.."'", 2)
                end
                mt.__declared[n] = true
            end
            rawset(t, n, v)
        end
    else
        mt.__newindex = function( t, n, v )
            rawset( t, n, v )
        end
    end
    if read then    
        -- *** blindly overwrites previous index function.
        mt.__index = function (t, n)
            if n == nil then return nil end
            if not mt.__declared[n] then
                local w = debug.getinfo(2, "S").what
                if w ~= 'C' then
                    error("lua table member '"..n.."' is not declared", 2)
                end
            end
            return rawget(t, n)
        end
    else
        mt.__index = function( t, n )
            return rawget( t, n )
        end
    end
end



--- Failsafe way to add a member to a table that may already be closed for write access (strict write-access policy has been set).
--
--  @usage Subsequent accesses may be direct without error, even on closed table.
--
--  @param t the table
--  @param n variable name
--  @param v initial value
--  @param overwriteOk (boolean) set true if variable may already be initialized, and if so, passed value should supercede.
--
function Table:initVar( t, n, v, overwriteOk )
    if t == nil then error( "no table" ) end
    if n == nil then return end
    local mt = getmetatable( t )
    if not mt then
        mt = {}
        setmetatable( t, mt )
    end
    if not mt.__declared then
        mt.__declared = {}
    end
    if not overwriteOk then
        local value = rawget( t, n )
        if value then
            error( "Already declared: " .. str:to( n ) )
        end
    end
    -- note: its ok to overwrite nil value whether already declared or not.
    mt.__declared[n] = v
    rawset( t, n, v )        
end



--- Determines if two tables (or non-table values) are equivalent.
--
--  @usage adequate (and slightly more efficient) if elemental equality dictates table equivalence, otherwise, consider version with eq-func.
--
--  @param t1 (any, required) elemental or table value.
--  @param t2 (any, required) elemental or table value.
--
--  @return true iff equivalent members at same indexes, even if order returned by pairs is different.
--
function Table:isEquivalent( t1, t2 )
    if ( t1 == nil ) and ( t2 == nil ) then
        return true
    elseif t1 == nil then
        return false
    elseif t2 == nil then
        return false
    end
    if type( t1 ) ~= type( t2 ) then
        return false
    end
    if type( t1 ) == 'table' then -- t2 is also a table
        local t1Count = 0
        for k, v in pairs( t1 ) do
            t1Count = t1Count + 1
            if not self:isEquivalent( v, t2[k] ) then
                return false
            end
        end
        local t2Count = tab:countItems( t2 )
        if t1Count == t2Count then
            return true
        else
            return false
        end
    else
        return t1 == t2
    end
    app:error( "how here?" )
end



--- Determines if two tables (or non-table values) are equivalent.
--
--  @usage same as version without eq-func if elemental equality dictates table equivalence, otherwise you'll need to pass an equivalence function.
--
--  @param t1 (any, required) elemental or table value.
--  @param t2 (any, required) elemental or table value.
--  @param eqFunc (function, optional) compares elemental (not table) values for equivalence.
--
--  @return true iff equivalent members at same indexes, even if order returned by pairs is different.
--
function Table:isEquiv( t1, t2, eqFunc )
    if ( t1 == nil ) and ( t2 == nil ) then
        return true
    elseif t1 == nil then
        return false
    elseif t2 == nil then
        return false
    end
    if type( t1 ) ~= type( t2 ) then
        return false
    end
    eqFunc = eqFunc or function( v1, v2 )
        if v1 == v2 then
            return true
        else
            --Debug.pause( v1, v2 )
            return false
        end
    end
    if type( t1 ) == 'table' then -- t2 is also a table
        local t1Count = 0
        for k, v in pairs( t1 ) do
            t1Count = t1Count + 1
            if type( v ) == 'table' then
                return self:isEquiv( v, t2[k] ) -- note absence of eq-func (dunno if good or bad, but notable..).
            elseif not eqFunc( v, t2[k] ) then
                --Debug.lognpp( v )
                --Debug.lognpp( t2[k] )
                --Debug.pause()
                return false
            end
        end
        local t2Count = tab:countItems( t2 )
        if t1Count == t2Count then
            return true
        else
            Debug.pause( t1Count, t2Count )
            return false
        end
    else
        return eqFunc( t1, t2 )
    end
    app:error( "how here?" )
end



--- Create a set from an array
--
--  @param array (table) array
--  @param b value for items in set to have - defaults to true.
--
--  @return set
--
function Table:createSet( array, b )
    if array == nil then
        app:callingError( "array is nil" )
    end
    local set = {}
    if b == nil then
        b = true
    end
    for i, v in ipairs( array ) do
        set[v] = b
    end
    return set
end



--- Creates a set whose contained elements have index instead of true as their value.
--
function Table:createSetI( array )
    if array == nil then
        app:callingError( "array is nil" )
    end
    local set = {}
    for i, v in ipairs( array ) do
        set[v] = i
    end
    return set
end



--- Convert table to array - probably should be deprecated: has never been used, that I know of.
--
function Table:convertToArray( tbl, keyName, valueName, sorter )
    keyName = keyName or "key"
    valueName = valueName or "value"
    local a = {}
    if sorter then
        for k, v in self:sortedPairs( tbl, sorter ) do
            a[#a + 1] = { [keyName] = k, [valueName]=v }
        end
    else
        for k, v in pairs( tbl ) do
            a[#a + 1] = { [keyName] = k, [valueName]=v }
        end
    end
    return a
end



--- Create an array from a set.
--
--  @param set (table, required) the set.
--  @param sort (boolean true, or function, default=don't sort) true for default sort (keys must be sortable, i.e. withstand lua comparison operator), or function for custom sort.
--
--  @usage for when you got a set, but you *need* an array.
--  @usage synonym: 'createArray' (set implied).
--
function Table:createArrayFromSet( set, sort )
    if set == nil then
        app:callingError( "set is nil" )
    end
    local array = {}
    if sort then
        if type( sort ) ~= 'function' then -- it's boolean true, probably, in any case: default sort.
            sort = nil -- set sort "function" to nil.
        end
        --[[ I'm afraid of the potential impact of the robustened checking below which I almost added - just be mindful of caveat when calling..
        if type( sort ) ~= 'function' then -- default sort
            local anyKey
            for k, v in pairs( set ) do
                anyKey = k
            end
            if anyKey ~= nil then
                local s, m = pcall( function() return anyKey > anyKey end )
                if not s then -- comparison operation failed - standard sort function will fail.
                    app:callingError( "Keys must be comparable by lua (consider custom sort function if necessary) - ^1", m )
                end
                sort = nil -- ok to use default sorting
            -- else -- the "set" (table) is empty - probably could just return {}, but to be like before the any-key check - fall through..
            end
        end
        --]]
        for k, v in tab:sortedPairs( set, sort ) do
            if v then
                array[#array + 1] = k
            end
        end
    else
        for k, v in pairs( set ) do
            if v then
                array[#array + 1] = k
            end
        end
    end
    return array
end
Table.createArray = Table.createArrayFromSet -- function Table:createArray( ... )



--- Concatenate keys.
--
function Table:concatKeys( set, sep )
    local array = self:createArray( set )
    return table.concat( array, sep )
end



--- Determine if item is in array, if so return index (does not check for redundent items).
--
--  @usage *** deprecated - use findInArray or isFoundInArray instead.
--
function Table:isInArray( array, item )
    for i, v in ipairs( array ) do
        if v == item then
            return i
        end
    end
    -- return nil
end



--- Get any key and value.
--
function Table:getAnyKeyAndValue( t )
    for k, v in pairs( t ) do
        return k, v
    end
end



--- Add from set to set, or names array to set.
--
function Table:addToSet( toSet, fromSet )
    app:callingAssert( toSet ~= nil, "no to-set" )
    app:callingAssert( fromSet ~= nil, "no from-set" )
    if #fromSet == 0 then -- a set
        for k, v in pairs( fromSet ) do
            toSet[k] = v
        end
    else
        for i, name in ipairs( fromSet ) do -- names array
            toSet[name] = true
        end
    end
end



--- Add from set to set, or names array to set.
--
--  @usage dont use - unless I'm missing something, this method is bugged and hasn't been tested(?)
--
function Table:removeFromSet( set, remove )
    app:callingAssert( set ~= nil, "no to-set" )
    app:callingAssert( remove ~= nil, "no from-set" )
    if #set == 0 then -- a set
        return
    elseif #remove == 0 then
        return
    else
        for k, v in pairs( remove ) do
            set[k] = nil
        end
    end
end



--[[ *** not sufficiently thought through...
function Table:addUniqueValueToArray( array, key, value )
    if array[0] == nil then
        array[0] = { index=0, lookup={} }
    end
    if lookup[key] then
        return
    end
    array[0].index = array[0].index + 1
    array[array[0].index] = value
    array[0].lookup[key] = true
end
--]]



--- Return a value which must be a table or nil.
--
--  @usage will not throw an error (unless name-to-throw is provided) - use when nil is better than a variable of the wrong type.
--
function Table:getTable( a, nameToThrow )
    if a ~= nil then
        if type( a ) == 'table' then
            return a
        elseif nameToThrow then
            app:error( "'^1' must be a table, not a '^2'", nameToThrow, type( a ) )
        else
            return nil
        end
    else
        return nil
    end
end



--- Get (potentially nested) table value given specified key in dot-notation format.
--
function Table:getValue( t, dotKeys )
    if t == nil then return nil end
    local keys = str:split( dotKeys, "." ) -- plain text by default.
    local t2 = t
    for i, v in ipairs( keys ) do
        t2 = t2[v] -- if t2 not table, this will throw indexing error.
        if t2 == nil then
            return nil
        end
    end
    return t2
end



--- Extract a table slice.
--
function Table:slice( t, i1, i2 )
    if self:isEmpty( t ) then return {} end
    local t2 = {}
    for i=i1, ( i2 or #t ) do
        t2[#t2 + 1] = t[i]
    end
    return t2
end



--- Create a table by replicating item, count times.
--
function Table:replicate( item, count )
    local t = {}
    for i = 1, count do
        t[i] = item
    end
    return t
end



--- Fetch specified slice of table treated as array (indexes are analogous to string.sub).
--
function Table:arraySlice( array, i1, i2 )
    local res = {}
    local n = #array
    -- default array for range
    i1 = i1 or 1
    i2 = i2 or n
    if i2 < 0 then
        i2 = n + i2 + 1
    elseif i2 > n then
        i2 = n
    end
    if i1 < 1 or i1 > n then
        return {}
    end
    local k = 1
    for i = i1, i2 do
        res[k] = array[i]
        k = k + 1
    end
    return res
end



--- Array value iterator "convenience" function.
--
function Table:arrayValues( t )
    local i = 0
    return function()
        i = i + 1
        return t[i]
    end
end



return Table