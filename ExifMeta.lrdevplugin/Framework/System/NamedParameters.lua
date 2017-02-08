--[[
        NamedParameters.lua
        
        "Convenience" methods for accessing named function call parameters (assuring no calling mistakes..).
        
        Example:
        --------
        local np = NamedParameters:new( params ) -- throw error if params is nil. If nil is OK (all params are optional), then do: new( params or {} )
        local main = np:req( 'main' ) -- main parameter, required (must be non-nil).
        local pOne = np:get( 'pOne', "one", ) -- if no options, then just return params['pOne']
        local pTwo = np:get( 'pTwo', nil, 'function' ) -- options: default, type, constraints.., err-msg
        np:done( 'pThree' ) -- toss error if not all params gotten (optional include parameter names which are to be ignored).
--]]

local NamedParameters, dbg, dbgf = Object:newClass{ className="NamedParameters", register=false }


local types = { -- non-nil types.
    ['string'] = true,
    ['number'] = true,
    ['boolean'] = true,
    ['table'] = true,
    ['function'] = true,
}



--- Constructor for extending class.
--
function NamedParameters:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
--  @usage example: local np = NamedParameters:new( params or {} ) -- assure empty table if all named parameters are optional, otherwise error is thrown.
--
function NamedParameters:new( params )
    if params == nil then
        error( "named parameter table is required", 3 ) -- caller of caller.
    elseif type( params ) == 'table' then
        self.p = params -- named parameter table.
    else
        error( "params must be table", 3 ) -- assuming calling context passed whatever it received, so error is in caller's caller.
    end
    local this = Object.new( self ) -- new virginal but blessed object..
    this.got = {}
    return this
end



--- Get one (optional) parameter value.
--  
function NamedParameters:get( name, dflt, typ )
    local value = self.p[name]
    self.got[name] = true
    if value == nil then
        if typ ~= nil then -- typ also passed
            app:callingAssert( types[typ], "Invalid type specified: '^1' (for '^2' parameter)", typ, name ) -- this is more to make sure caller is getting the default param in correct position.
        else -- return whatever caller passed as default - hope it's good..
            return dflt -- may also be nil. note: dflt's type won't be compared to typ, so caller's responsibility to make sure type of default is as desired.
        end
    elseif typ ~= nil then
        if types[typ] then -- typ is a legal value.
            if type( value ) == typ then
                return value
            else
                error( str:fmtx( "Invalid type for '^1' parameter: should be '^2', was '^3' - value: ^4", name, typ, type( value ), tostring( value ) ), 3 )
            end
        else
            app:callingError( "Invalid type specified: '^1' (for '^2' parameter)", typ, name ) -- this is more to make sure caller is not trying to pass a default as typ param..
        end
    else
        return value
    end
end



--- Get one (required) parameter value.
--  
function NamedParameters:req( name, typ )
    local value = self.p[name]
    self.got[name] = true
    if value == nil then
        if typ ~= nil then -- typ also passed
            app:callingAssert( types[typ], "Invalid type specified: '^1' (for '^2' parameter)", typ, name ) -- this is more to make sure caller is not trying to pass a default as typ param..
        else -- return whatever caller passed as default - hope it's good..
            error( str:fmtx( "'^1' is required.", name ), 3 )
        end
    elseif typ ~= nil then
        if types[typ] then -- typ is a legal value.
            if type( value ) == typ then
                return value
            else
                error( str:fmtx( "Invalid type for '^1' parameter: should be '^2', was '^3' - value: ^4", name, typ, type( value ), tostring( value ) ), 3 )
            end
        else
            app:callingError( "Invalid type specified: '^1' (for '^2' parameter)", typ, name ) -- this is more to make sure caller is not trying to pass a default as typ param..
        end
    else
        return value
    end
end



--- Done getting parameter values, so make sure nothing was passed which can't be used.
--  @usage example #1: do v1 = np:get( 'v1' ); np:done() end -- get optional value from named parameter table, then assure no extras were passed.
--  @usage example #2: do v1 = np:req( 'v1' ); np:done( 'v2' ) end -- get required value from named parameter table, then assure nothing other than optional 'v2' was passed.
--  @param ... names of parameters to ignore (those for which it is acceptable if not gotten).
function NamedParameters:done( ... )
    local ignore = tab:createSet{...}
    for name, value in pairs( self.p ) do
        if not self.got[name] and not ignore[name] then
            -- used to throw error here, but that now seems too harsh (best not to have a function die of something insignificant, like an extra parameter got passed, which is no longer required/supported, but doesn't hurt..).
            local msg = str:fmtx( "'^1' is not a valid parameter (value='^2')", tostring( name ), tostring( value ) )
            if app:isAdvDbgEna() then -- e.g. during author development or user trouble-shooting.
                error( msg, 3 ) -- let's not gloss over the potential problem.
            else
                app:logV( "*** '^1' is not a valid parameter (value='^2')", tostring( name ), tostring( value ) ) -- often a non-issue, but in case user has verbose mode enabled..
            end
        end
    end
end


return NamedParameters