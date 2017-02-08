--[[
        Reload.lua
--]]

local Reload, dbg = Object:newClass { className='Reload', register = false }



--- Constructor for extending class.
--
function Reload:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function Reload:new( t )
    local o = Object.new( self, t )
    return o
end



--- Reload function - no prompting if dev mode.
--
function Reload:now( bypassPrompt )

    app:call( Call:new{ name='Reload', async=true, guard=App.guardVocal, main=function(call)
        if app:isRelease() and not bypassPrompt then
            if not dialog:isOk( str:fmt( "The 'Reload' function should be reserved for when you are having problems with a plugin (or think you might be...), and in general, its best to reload plugins via the plugin manager.\n \nThe reload menu function is convenient for debugging though.\n \nAre you sure you want to reload ^1?", app:getPluginName() ) ) then
                return
            end
        end
        app:logInfo( "Reloading..." )
        local shutdownFilename = app:getInfo( 'LrShutdownPlugin' )
        if shutdownFilename then
            local shutdownPath = LrPathUtils.child( _PLUGIN.path, shutdownFilename )
            dofile( shutdownPath ) -- file presence tested by lightroom when loading plugin.
            if gbl:getValue( 'background' ) then
                background:waitForIdle()
            end
        end
        local initFilename = app:getInfo( 'LrInitPlugin' )
        assert( initFilename, "Reload requires init-plugin module." )
        local initPath = LrPathUtils.child( _PLUGIN.path, initFilename )
        _G.reloading = true -- init module is the only only one that looks at this flag.
        dofile( initPath ) -- file presence tested by lightroom when loading plugin.
    end, finale=function( call, status, message )
        _G.reloading = false
    end } )

end



return Reload