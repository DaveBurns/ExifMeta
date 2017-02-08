--[[
        Disable.lua
--]]

if app then
    app:call( Call:new{ name='Disable', async=false, guard=App.guardSilent, main=function( call )
        -- _G.enabled = false - obsolete.
        app:logInfo( app:getAppName() .. " is disabled - it must be enabled for updating and metadata functionality..." )
    end } )
end
