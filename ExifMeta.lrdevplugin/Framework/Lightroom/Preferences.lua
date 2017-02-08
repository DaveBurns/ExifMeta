--[[================================================================================
        Lightroom/Preferences
================================================================================--]]


local LightroomPreferences = Object:newClass{ className="LightroomPreferences", register=false }



--- Constructor for extending class.
--
function LightroomPreferences:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function LightroomPreferences:new( t )
    local o = Object.new( self, t )
    return o
end



-- see Pretend plugin for a better load function
-- note: this is currently only being used by LrFourB, I think.
function LightroomPreferences:load()
    local s, m = app:call( Call:new{ name="Loading Lightroom Preferences", async=false, main=function( call ) -- no guarding "should" be necessary.
        local dir = LrPathUtils.getStandardFilePath( 'appData' ) -- lr app data
        dir = LrPathUtils.child( dir, 'Preferences' )
        local filename = "Lightroom 3 Preferences.agprefs" -- ###1 it had better not being used ;-}
        local file = LrPathUtils.child( dir, filename )
        if fso:existsAsFile( file ) then
            --Debug.logn( "got it", file )
        else
            --Debug.logn( "file not found", file )
            file = dia:selectFile {
                title = "Choose Lightroom preferences file",
                canCreateDirectories = false,
            }
            if file then
                -- good
            else
                call:cancel()
                return
            end
        end
        call.prefs = _G.prefs
        _G.prefs = nil
        call.AgRect = rawget( _G, 'AgRect' )
        rawset( _G, 'AgRect', function( a, b, c, d )
            return { a, b, c, d }
        end )
        local s, m = pcall( dofile, file )
        if s then
            -- good
            if _G.prefs then
                self.prefs = prefs
                prefs = call.prefs
                call.prefs = nil
            else
                error( "No prefs" )
            end
        else
            app:show{ warning="Lightroom preferences file may be corrupt - ^1", m }
            return
        end
        
        -- additional pref testing
        --local prefText = luaText:serialize( lrPrefs ) -- either this
        --app:log()
        --app:log( "Lightroom preferences:" )
        --app:log( prefText ) -- or this are causing an infinite loop.
        --app:log()
        --app:log()
        app:logVerbose( "Lightroom preferences have been loaded." )
        
        
    end, finale=function( call, status, message )
        if call.prefs ~= nil then
            _G.prefs = call.prefs
        end
        if call.AgRect ~= nil then
            _G.AgRect = call.AgRect
        end
        --Debug.showLogFile()
    end } )
    if s then
        return self.prefs
    else
        return false, m
    end
end
   
   
   
return LightroomPreferences 