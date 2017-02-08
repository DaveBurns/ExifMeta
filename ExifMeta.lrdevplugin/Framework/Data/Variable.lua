--[[================================================================================

        Variable.lua
        
        *** deprecated - I think this class was never used, but can't be sure..
        
================================================================================--]]


local Variable, dbg, dbgf = Object:newClass{ className='Variable', register=false }



--- Constructor for extending class.
--
function Variable:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function Variable:new( t )
    return Object.new( self, t )
end



--  @24/Nov/2013 21:44, can't see anywhere this is used, but maybe I missed something.
--
function Variable:get( a, ... )
    if a ~= nil then
        return a
    end
    for i, v in ipairs{ ... } do
        if v ~= nil then
            return v
        end            
    end
end



-- ditto
function Variable:coerceType( v, t )
    if v ~= nil then
        if t == 'number' then
            return tonumber( v )
        elseif t == 'string' then
            return tostring( v )
        --[[
        elseif t == 'boolean' then
            local ts = tostring( v )
            if ts == 'true' then
                return true
            else
                return false
            end
        --]]
        else
            app:callingError( "Unable to coerce type to ^1", t )
        end
    else
        return nil
    end
end



function Variable:is( v )
    if v == nil then return false end
    local typ = type( v )
    if typ == 'string' then
        return #v > 0
    elseif typ == 'table' then
        for k in pairs( v ) do
            return true
        end
        return false
    elseif typ == 'number' then
        return v ~= 0
    elseif typ == 'boolean' then
        return v
    else -- function
        return true
    end
end


return Variable