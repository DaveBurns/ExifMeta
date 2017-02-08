--[[
        Object.lua
        
        All plugin objects are derived from this common ancestor.
--]]


local Object = { classRegistry = {} } -- Object itself not registered for debug. Debug independently....



local LrPathUtils -- just in case needed before framework init.



--- Constructor for extending class.
--
function Object:newClass( t )

    if t == nil then
        error( "New class constructor requires initial table." )
    elseif not t.className then
        error( "New class constructor requires class-name." )
    end
    if (self.className or '') ~= '' then -- creating class derived from class derived from 'Object'.
        t.className = self.className .. '.' .. t.className -- class name is whole path in dot notation, excluding 'Object' base class.
    else
        -- t.className = 'Object' -- don't do this or 'Object' will appear as prefix for everything derived from object.
    end
    local class = Object.new( self, t )
    local name = class:getFullClassName()
    local dbg = function( ... )
        if gbl:getValue( 'app' ) then
            app:classDebugTrace( name, ... ) -- use to be OK (without checking for app), now not - dunno what happened.
        else
            Debug.logn( "class '"..name.."':", ... )
        end
    end
    local dbgf = function( fmt, ... )
        if gbl:getValue( 'app' ) then
            app:classDebugTraceFmt( name, fmt, ... ) -- use to be OK (without checking for app), now not - dunno what happened.
        else
            Debug.logn( "class '"..name.."':", str:fmt( fmt, ... ) )
        end
    end
    local reg = (t and t.register) or false
    if reg then
        Object.classRegistry[name] = { class = class, propKey = "classKey_" .. class:getPropertyKeyName() }
    end
    return class, dbg, dbgf
       
end



--- Creates an object.
--      
--  @param              t       Initialization table, for convenience - members could be assigned to table upon return for same effect.
--
--  @usage              Inheritable constructor method, for one-parent classes.
--  @usage              Called with class-name for creating classes derived from Object.
--  @usage              Called without class-name in derived class constructors for creating base Object functionality in derived instance.<br><blockquote>
--                            - Note: in this case, it must be called using dot notation (instead of colon notation), since function must be Object.new,<br>
--                              but self parameter must be derived class object.</blockquote>
--
--  @return             object - as table, with metatable index set to derived class object, throws error if trouble.
--
function Object:new( t )

    t = t or {} -- preserve presribed initial values, if specified, else create object from scratch.
    setmetatable(t, self) -- reminder: self may be Object class or may be class derived from Object, depending on context, but otherwise will never be an instance of the target object being created.
    self.__index = self -- Look up elements not found in instances of this class in the class object.
    return t -- return a "blessed" object - either class or instance of, depending on context.
    
end



--- Register non-class/plain-table object (a.k.a pseudo-class) for inclusion on class-enable form, and/or fetch a debug function.
--
--  @param      name        Registration and/or debug entity name.
--  @param      _reg        True or nil to register, false to forego registration, in which case this is really just a convenience function for defining a dbg function.
--
--  @usage      need to register objects during init for advanced debugging - NOT upon each invocation of a menu item...
--
--  @return     empty table     for syntactical convenience.
--  @return     debug function  (see app-debug-trace function for more info).
--
function Object.register( name, reg )
    local t = {}
    if reg == nil then
        reg = true
    end
    if reg then
        Object.classRegistry[name] = { class = Object, propKey = "tableKey_" .. name } -- pseudo-object/table.
    end
    return t, Object.getDebugFunction( name )    
end



--- Get debug function.
--
--  @usage - if object is registered, it will be tied to plugin manager enable/disable, otherwise always enabled.
--
function Object.getDebugFunction( name )
    if Object.classRegistry[name] then
        return function( ... )
            if app:isAdvDbgEna() then
                app:classDebugTrace( name, ... )
            end
        end, function( fmt, ... )
            if app:isAdvDbgEna() then
                app:classDebugTraceFmt( name, fmt, ... )
            end
        end
    else
        return function( ... )
            if app:isAdvDbgEna() then
                app:debugTrace( "'" .. name .. "':", ... )
            end
        end, function( fmt, ... )
            if app:isAdvDbgEna() then
                app:debugTrace( "'" .. name .. "':", str:fmtx( fmt, ... ) )
            end
        end
    end
end



--- Get registered classes/tables as item array suitable for combo box.
--
--  @return     array of strings with full-name of all registered classes or pseudo-classes.
--
function Object.getClassItems()
    return tab:arrayOfSortedKeys( Object.classRegistry )
end



--- Get full class name suitable for indexing property table, which must not include dots.
--
function Object:getPropertyKeyName()
    if self.className then
        return string.gsub( self.className, "%.", "_x_" ) --  property table keys must not contain dots.
    else
        return "Object"
    end
end    



--- Get unique full class name in dot notation (excludes 'Object' ancestry in inheritance path).
--      
--  @usage              Most useful for debugging...
--  @usage              Guaranteed to be unique.
--      
--  @return             string: e.g. 'Export.SpecialExport'
--
function Object:getFullClassName()
    if self.className then
        return self.className
    else
        return "Object"
    end
end



--- Get "leaf" class name.
--      
--  @usage              Most useful for debugging...
--  @usage              Short & informal..., but not necessarily unique.
--      
--  @return             string: e.g. 'SpecialExport'
--
function Object:getClassName()
    if self.className then
        if LrPathUtils == nil then -- added 23/Nov/2013 4:42 because it was needed for a short time. Not needed anymore, but seems like cheap insurance, so it stays.
            LrPathUtils = import 'LrPathUtils'
        end
        local ext = LrPathUtils.extension( self.className )
        if (ext or '') ~= '' then -- creating class derived from class derived from 'Object'.
            return ext
        else
            return self.className
        end
    else
        return "Object"
    end
end



--- Method for getting short synopsis-style display string for debugging/logging.
--      
--  @usage      Default is full class name - override for something better.
--
function Object:toString()
    return self:getFullClassName()
end



--- Create a class from two or more parents.
--      
--  @param          register        boolean true iff hybrid class should be registered for advanced debug support.
--  @param          ...             base classes.
--
--  @usage          If only one parent, just use the 'new' method.
--  @usage          See in book "Programming in Lua: Multiple Inheritance".
--  @usage          @2011-01-19: Integrated properly into framework, including advanced debug support.
--      
--  @return         Class object with multiple inheritance, plus debug function.
--
function Object.createClass( register, ... )
    local function search( k, plist )
        for i = 1, #plist do
            local v = plist[i][k]
            if v then
                return v
            end
        end
        -- return nil implicit: just like any other class when referencing member not present.
    end
    local class = {}
    local parents = { ... }
    
    setmetatable( class, { __index = function( t, k )
        return search( k, parents )
    end } )
    
    class.__index = class
    
    function class:getClassName()
        local name = ''
        for i = 1, #parents do
            repeat
                name = name .. '_' .. parents[i]:getClassName()
            until true
        end
        return name
    end
    
    function class:getFullClassName()
        local name = self:getClassName()
        return 'Hybrid.' .. name -- punt: a more robust implementation might try to merge heritages.
        -- note: since hybrid objects are only ones to include the object prefix, its provides a clue...
    end
    
    function class:getPropertyKeyName()
        local name = ''
        for i = 1, #parents do
            name = name .. parents[i]:getPropertyKeyName() -- underscore provide another clue that its a hybrid.
        end
        return name
    end
    
    function class:toString()
        return self:getFullClassName()
    end
    
    function class:new( o )
        o = o or {}
        setmetatable( o, class )
        return o
    end
    
    if register then
        local name = class:getFullClassName()
        Object.classRegistry[name] = { class = class, propKey = "classKey_" .. class:getPropertyKeyName() }
        return class, function( a, b )
            app:classDebugTrace( name, a, b )
        end
    else
        return class, function( a, b )
            app:debugTrace( name, a, b )
        end
    end
    
    return class 
end



--- Inherit base class members directly (via class object) instead of indirectly (via metatable) if need be.
--
--  @usage this is useful for classes like Export/Publish - Lightroom won't consult metatable for static member functions...
--
function Object:inherit( BaseClass )
    for k, v in pairs( BaseClass ) do -- consider base class members.
        if self[k] then -- member also supported by derived class.
            if not rawget( self, k ) then -- but not directly accessible
                self[k] = v -- assign base class member directly to class.
                --Debug.logn( "Inherited", k, str:to( v ) )
            else
                --Debug.logn( "NOT inherited", k, str:to( v ) )
            end
        end
        --Debug.showLogFile()
    end
end
    


return Object