--[[
        ObjectFactory.lua
        
        Creates objects used in the guts of the framework.
        Serves as a hook for apps to be able to control the classes of objects that get created,
        without having to override gobs of stuff to get to them.
        
        Generally, this is edited when new objects are created in the framework that are not 
        globally accessible. Plugin authors making plugins out of the new framework will generally
        edit the derived type: special-object-factory, if they've extended said classes.
--]]

local ObjectFactory, dbg, dbgf = Object:newClass{ className = 'ObjectFactory', register = false }



--- Constructor for extending class.
--
function ObjectFactory:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function ObjectFactory:new( t )
    local o = Object.new( self, t )
    return o
end



--- Load a framework module.
--
--  @usage     Called by init-framework method - extended object factory can return nil for unsupported classes,
--             <br>or load a custom framework module for some class.
--
function ObjectFactory:frameworkModule( spec )
    return Require.require( spec )
end



--- "Manufacture" a new instance object of specified class.
--
--  @param      class       (string or class, required) partial class name if unique, otherwise full-class-name, or class table proper.
--  @param      ...         passed to object constructor.
--
function ObjectFactory:newObject( class, ... )
    if type( class ) == 'table' then
        if class.new then
            return class:new( ... )
        else
            error( "Unable to create object of this class object: " .. tostring( class or 'nil' ) )
        end
    elseif type( class ) == 'string' then
        if class == 'InitFramework' then
            return InitFramework:new()
        elseif class == 'OperatingSystem' then
            if WIN_ENV then
                return Windows:new()
            else
                return Mac:new()
            end
        elseif class == 'ExportDialog' then
            return Export:newDialog( ... )
        elseif class == 'Export' then
            return Export:newExport( ... )
        elseif class == 'PublishDialog' then
            return Publish:newDialog( ... )
        elseif class == 'Publish' then
            return Publish:newExport( ... )
        else
            error( "Unable to create object with this class name (string): " .. tostring( class or 'nil' ) )
        end
    else
        error( "Class must be object or class name string" )
    end
end



return ObjectFactory