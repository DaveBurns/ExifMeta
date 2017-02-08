--[[
        Init.lua (plugin initialization module)
--]]


-- Unstrictify _G (only required for reloading I think, but cheap insurance).
local mt = getmetatable( _G ) or {}
mt.__newIndex = function( t, n, v )
    rawset( t, n, v )
end
mt.__index = function( t, n )
    return rawget( t, n )
end
setmetatable( _G, mt )



--   I N I T I A L I Z E   L O A D E R
do
    local LrPathUtils = import 'LrPathUtils'
    local frameworkDir = LrPathUtils.child( _PLUGIN.path, "Framework" )
    local reqFile = frameworkDir .. "/System/Require.lua"
    local status, result1, result2 = pcall( dofile, reqFile ) -- gives good "file-not-found" error - no reason to check first (and is ok with forward slashes).
    if status then
        _G.Require = result1
        _G.Debug = result2
        assert( Require ~= nil, "no require" )
        assert( Debug ~= nil, "no debug" )
        assert( require == Require.require, "'require' is not what's expected" ) -- synonym: helps remind that its not vanilla 'require'.
    else
        error( result1 ) -- we can trust pcall+dofile to return a non-nil error message.
    end
    if _PLUGIN.path:sub( -12 ) == '.lrdevplugin' then
        Require.path( frameworkDir )
    else
        assert( _PLUGIN.path:sub( -9 ) == '.lrplugin', "Invalid plugin extension" )
        Require.path( 'Framework' ) -- relative to lrplugin dir.
    end
end



--   S E T   S T R I C T   G L O B A L   P O L I C Y
_G.Globals = require( 'System/Globals' )
_G.gbl = Globals:new{ strict = true }



--   I N I T I A L I Z E   F R A M E W O R K
_G.Object = require( 'System/Object' )                         -- base class of base object factory.
_G.ObjectFactory = require( 'System/ObjectFactory' )           -- base class of special object factory.
_G.InitFramework = require( 'System/InitFramework' )           -- class of object used for initialization.
_G.ExtendedObjectFactory = require( 'ExtendedObjectFactory' )    -- class of object used to create objects of classes not mandated by the framework.
_G.objectFactory = ExtendedObjectFactory:new()               -- object used to create objects of classes not mandated by the framework.
_G.init = InitFramework:new()                               -- create initializer object, of class specified here.
init:framework()                                            -- initialize framwork, relying on global object factory to create framework objects of proper class.
assert( custMeta ~= nil, "No custom metadata manager." )


--   P L U G I N   S P E C I F I C   I N I T
_G.LrXml = import 'LrXml'
_G.Xml = require( 'Data/Xml' )
_G.Background = require( 'System/Background' )
_G.Preferences = require( 'System/Preferences' )
_G.XmlRpc = require( 'Communication/XmlRpc' )
_G.Common = require( 'Common' )
_G.ExtendedManager = require( 'ExtendedManager' )
_G.ExtendedBackground = require( 'ExtendedBackground' )
_G.ExtendedUpdater = require( 'ExtendedUpdater' )
_G.ScrollView = require( 'Gui/ScrollView' )
_G.Reload = require( 'System/Reload' )
-- @9/Sep/2012 18:20 only used for new Write feature: ###3 - update all features to use exif-tool external-app object.
_G.ExifTool = require( "ExternalApps/ExifTool" )
_G.exifTool = ExifTool:new{ prefName = 'exifToolExe' } -- uses non-standard pref-name for backward compatibility.
_G.Xmp = require( "Image/Xmp" )
_G.xmp = Xmp:new()

_G.reload = Reload:new()
_G.xml = Xml:new()
_G.background = ExtendedBackground:new() -- name is fixed - this is how other things determine whether there is a potential for background activity.
_G.upd = ExtendedUpdater:new()



Object.register( 'Update' )
Object.register( 'Write' )



--   F I N I S H   S Y N C H R O N O U S   I N I T
ExtendedManager.initPrefs()
app:initDone()



--   I N I T I A T E   A S Y N C H R O N O U S   I N I T   A N D   B A C K G R O U N D   T A S K
if app:getGlobalPref( 'autoUpdate' ) or app:getPref( 'background' ) then -- check both legacy global pref and new local pref, so user does not notice a difference when upgrading.
    background:start()
end



-- the end.