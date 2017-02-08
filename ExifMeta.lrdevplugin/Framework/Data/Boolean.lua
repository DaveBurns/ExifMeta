--[[================================================================================

        Boolean.lua
        
        Singleton supporting utility methods for dealing with boolean values.
        
        *** this class was done when I was first learning lua and many methods seem silly now
        (I was having problems occasionally which methods in here were supposed to help with, many are no longer used..).

================================================================================--]]


local Boolean, dbg, dbgf = Object:newClass{ className = 'Boolean', register = false }



--- Constructor for extending class.
--
function Boolean:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function Boolean:new( t )
    return Object.new( self, t )
end



--- Determine if the specified boolean is true.
--      
--  @usage      Returns the value as is if not nil, else the boolean 'false'.
--              Avoids problem of illegal comparison with nil.
--                      
function Boolean:isTrue( v )
    return v or false
end



--- Determine if value is non-nil, boolean, and true.
--
--  @usage      Convenience function for times when a value could be boolean true or something else...
--  @usage      this function will never throw an error.
--
--  @return     true iff "all of the above".
--
function Boolean:isBooleanTrue( v )
    return (v ~= nil) and type( v ) == 'boolean' and v == true
end



--- Determine if the specified boolean is false.
--
--  @usage  Same as 'not v' except it will throw an error if the value is not a boolean.
--
function Boolean:isFalse( v )
    return (v == nil) or (v == false)
end



--- Obtain boolean value from string representation.
--
--  @usage the inverse of 'tostring( booleanValue )'.
--
function Boolean:booleanFromString( s )
    if s == 'true' then
        return true
    elseif s == 'false' then
        return false
    else
        return nil
    end
end



--- Get a boolean from a variable whose type has not been pre-assured.
--
--  @usage If boolean, then returned verbatim, if string, then attempt to convert to boolean, otherwise returns nil.
--  @usage The intended use is for cases when a boolean is required, but user or legacy code may have left something else where a number is expected, in which case, the old value is to be ignored...
--  @usage never throws an error.
--  @usage myBool = bool:getAsBoolean( something ) or false -- assure boolean true or false from boolean or string, else convert nil to false.
--  @usage myBool = bool:getAsBoolean( something ); if myBool == nil then -- something is not gettable as boolean.
--
function Boolean:getAsBoolean( a ) -- perhaps should have been called "get if boolean or string equiv".
    if a ~= nil then
        if type( a ) == 'boolean' then
            return a
        elseif type( a ) == 'string' then
            return self:booleanFromString( a ) -- will be nil if string is not convertible to number.
        else
            return nil
        end
    else
        return nil
    end
end



--- Determine if a boolean, and if so, return it's value, otherwise return nil.
--
--  @usage throws error if not boolean type.
--
function Boolean:getBoolean( a, nameToThrow, default )
    if a ~= nil then
        if type( a ) == 'boolean' then
            return a
        elseif nameToThrow then
            app:error( "'^1' must be a boolean, not a '^2'", nameToThrow, type( a ) )
        else
            return nil
        end
    else
        return default
    end
end



--- Get boolean equivalent, or default.
--
--  @param v (any type, required) value to have returned boolean equivalent of.
--  @param dflt (boolean, optional) default in case value is nil.
--
--  @usage this works: mybool = avar or false -- return avar (presumed to be boolean or nil), or false as default.
--  @usage this does NOT work: mybool = avar or true -- always returns true!
--  @usage this function always returns boolean true or false (regardless of type of 'v' which is usually 'boolean'), never throws error.
--  @usage example: switch = bool:booleanValue( myVar, true ) -- return true or false if set, and if unset, return true.
--  @usage reminder: use instead of "local myBool = aBool or true" -- which will never be false!
--
function Boolean:booleanValue( v, dflt )
    if v then
        return true
    elseif v == nil then
        return dflt
    else -- boolean 'false'.
        return v
    end
end



return Boolean