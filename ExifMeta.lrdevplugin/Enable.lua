--[[
        Enable.lua
--]]

if app then
    app:call( Call:new{ name='Enable', async=false, guard=App.guardSilent, main=function( call )
        -- _G.enabled = true - obsolete.
        app:logInfo( app:getAppName() .. " is enabled - exif metadata should be available (if included metadata has been commited), along with file menu items." )
    end } )
end
