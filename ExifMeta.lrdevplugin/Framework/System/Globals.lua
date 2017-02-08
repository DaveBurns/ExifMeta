--[[
        Globals.lua
--]]


-- Unlike most other framework modules, this one has no framework/Lr-import dependencies.
local LrPathUtils = import( 'LrPathUtils' )
local LrFileUtils = import( 'LrFileUtils' )
local LrErrors = import( 'LrErrors' )


local Globals = {}



function Globals:newClass( t )
    t = t or {} -- preserve presribed initial values, if specified, else create object from scratch.
    setmetatable(t, self) -- reminder: self may be Object class or may be class derived from Object, depending on context, but otherwise will never be an instance of the target object being created.
    self.__index = self -- Look up elements not found in instances of this class in the class object.
    return t -- return a "blessed" object - either class or instance of, depending on context.
end



--- Constructor for new global environment manager.
--
--  @param      t       initialization table, including:
--                      <br>strict (boolean, default true) - global access policy.
function Globals:new( t )
    local o = Globals.newClass( self, t )
    o:setStrict( o.strict )
    return o
end



--- Get global variable value, without throwing error if global policy is strict and variable is undefined.
--
--  @param name (string, required) any variable name.
--
--  @usage keeps from throwing an error when global policy is strict.
--
--  @return value iff in global table and value is not nil, else nil.
--
function Globals:getValue( name )
    if self.strict then
        return rawget( _G, name ) -- bypass metatable / __index function.
    else
        return _G[name] -- let this generate an error if some code has set strict access without going through this class.
    end
end



--- Declare a global variable with an initial (optional) value.
--
--  @param name (string, required) any variable name.
--  @param value (any lua value, required) variable's value.
--               <br>even if value is nil, this function still serves as a global variable definition
--               <br>such that subsequent access will not throw an error, even if policy is strict.
--  @paramOk overwriteOk (boolean, default false) true iff you want to redefine an existing variable.
--                       <br>generally false is best, since this assures you are not stomping on somebody elses variable.
--
--  @usage *** It is not recommended to use this function except during initialization.
--         its considered "best practice" when using the framework to define
--         all global variables in init.lua.
--
function Globals:initVar( name, value, overwriteOk )
    if self.strict then
        local v = rawget( _G, name )
        if v ~= nil and not overwriteOk then
            error( "Globals variable already exists and will not be overwritten: " .. name )
        end
        local mt = getmetatable( _G )
        if not mt then
            mt = { __declared = {} }
            setmetatable( _G, mt )
        elseif not mt.__declared then
            mt.__declared = {}
        end
        mt.__declared[name] = true
        rawset( _G, name, value ) -- bypass metatable / __newindex function.
    else
        _G[name] = value -- let there be an error if some rogue code has set strict policy not via this class.
    end
end



--- Determine if variable is declared globally, even if value is nil (applies to strict policy only).
--
function Globals:isDeclared( name )
    if self.strict then
        return getmetatable( _G )['__declared'][name]
    else
        return _G[name] ~= nil
    end
end



--- Glorified rawset.
--
function Globals:setValue( name, value )
    rawset( _G, name, value )
end



--- Set strict or lax global policy.
--
--  @param      t       (table, required) table to make strict access policy. In plugin's Init.lua, this is usually _G.
--  @param      strict (boolean, default false) true => make strict (undeclared var access generates error), false => make lax (undeclared access allowed).
--                     <br>setting strict to true will clear out all previous explicit declarations.
--
--  @usage      although lax sounds better, strict is better (Lr2 is strict by default, Lr3 is lax by default).
--  @usage      *** Note: this is not an object method.
--
function Globals:setStrict( strict )

    local mt = getmetatable( _G )
    if mt == nil then
        mt = {}
    end
    
    if strict then
    
        self.strict = true
        mt.__declared = {}
        
        -- *** blindly overwrites previous new-index function - this could be problem when mixing code that
        -- has different requirements for new-index function, and stomp on each other...
        mt.__newindex = function (t, n, v)
            if n == nil then return end
            if not mt.__declared[n] then
                local w = debug.getinfo(2, "S").what
                if w ~= "main" and w ~= "C" and n ~= 'trash' then
                    error("assign to undeclared variable '"..n.."'", 2)
                end
                mt.__declared[n] = true
            end
            rawset(t, n, v)
        end
          
        -- blindly overwrites previous index function.
        mt.__index = function (t, n)
            if n == nil then return nil end
            local w = debug.getinfo(2, "S").what
            if not mt.__declared[n] and w ~= "main" and w ~= "C" and n ~= 'trash' then
                error("variable '"..n.."' is not declared", 2)
            end
            return rawget(t, n)
        end
        
    else
        self.strict = false
        local mt = {
            __newIndex = function( t, n, v )
                rawset( t, n, v )
            end,
            __index = function( t, n )
                rawget( t, n )
            end,
        }
    end
    
    setmetatable( _G, mt )
end



return Globals
