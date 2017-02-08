--[[
        Number.lua
        
        Some of these methods are little wonky (and no longer used) - I realized some things after initial coding..
--]]

local Number, dbg, dbgf = Object:newClass{ className='Number', register=false }



--- Constructor for extending class.
--
function Number:newClass( t )
    return Object.newClass( self, t )
end




--- Constructor for new instance.
--
function Number:new( t )
    return Object.new( self, t )
end



--- Try to convert a string to a number, without croaking if the string is nil, null, or isn't a number...
--
--  @usage *** deprecated - this function is essentially the same as tonumber (which is more robust than I once thought, handling invalid types etc. by returning nil instead of throwing error, and handling numbers and numeric-strings in desired fashion.
--
function Number:numberFromString( s )
    if s == nil or s == '' then -- I thought this would throw an error if s not a string type, but @15/Dec/2012 (already) numeric type is surviving the test.
        return nil
    end
    local sts, num = pcall( tonumber, s )
    if sts and num then
        return num
    else
        return nil
    end
end
Number.getNumberFromString = Number.numberFromString -- function Number:getNumberFromString(...)
Number.to = Number.numberFromString -- function Number:to(...)




--- takes a number (or string representation of a number) and returns a string with sign prepended, whether positive or negative.
--
function Number:signedString( v )
    local number = tonumber( v )
    if number ~= nil then
        if number > 0 then -- should be ok to apply tonumber if v already number.
            return "+" .. v
        else
            return "" .. v
        end
    else
        app:callingError( "value does not represent a number: ^1", str:to( v ) )
    end
end



--- Get a number from a variable whose type has not been pre-assured.
--
--  @usage This function was invented when I thought the above would fail when 's' not string (e.g. number), but that seems OK now, so this function is may be completely redundent.
--  @usage If number, then returned verbatim, if string, then attempt to convert to number, otherwise returns nil.
--  @usage The intended use is for cases when a number is required, but user or legacy code may have left something else where a number is expected, in which case, the old value is to be ignored...
--  @usage never throws an error.
--
function Number:getAsNumber( a )
    if a ~= nil then
        if type( a ) == 'number' then
            return a
        elseif type( a ) == 'string' then
            return self:numberFromString( a ) -- will be nil if string is not convertible to number.
        else
            return nil
        end
    else
        return nil
    end
end



--- Determine if a number, and if so, return it's value, otherwise return nil.
--
--  @usage never throws error.
--
function Number:getNumber( a, nameToThrow )
    if a ~= nil then
        if type( a ) == 'number' then
            return a
        elseif nameToThrow then
            app:error( "'^1' must be a number, not a '^2'", nameToThrow, type( a ) )
        else
            return nil
        end
    else
        return nil
    end
end



--- Check if value is non-zero number.
--
--  @usage value can be nil, but if non-nil - must be number.
--
function Number:isNonZero( value )
    if value ~= nil and value ~= 0 then
        return true
    else
        return false
    end
end
Number.is = Number.isNonZero -- function Number:is(...)



--- Determine if number is integer.
--
--  @param nmbr number (not string, not nil..).
--
function Number:isInteger( nmbr )
    return (nmbr % 1) == 0
end



--- Determine if number is within a certain amount of another number +/-
--
--  @usage does not matter which number is first param and which is second.
--
--  @param num1 first number.
--  @param num2 second number.
--  @param amt maximum difference amount.
-- 
--  @return true of false if num1 is within amt of num2, or vice versa.
--
function Number:isWithin( num1, num2, amt )
    return ( num1 + amt ) >= num2 and ( num1 - amt ) <= num2
end



--- Format number to string with specified precision.
--
--  @usage num:fmtPrec( LrDate.currentTime() - initialTime, 3 ) -- replaces date-time--format-time-diff-msec method.
--
--  @param val number to be formatted.
--  @param prec (number, required) precision: number of digits after decimal place.
--
--  @return string e.g. '1.234' -- elapsed time to nearest millisecond.
-- 
function Number:fmtPrec( val, prec )
    if prec == 0 then
        return string.format( "%d", val )
    else
        return string.format( str:fmtx( "%.^1f", prec ), val )
    end
end



return Number