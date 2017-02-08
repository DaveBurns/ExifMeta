--[[
        Ffmpeg.lua
        
        Initial motivation for this extended external-app class dedicated to exif-tool was
        the ability to support multiple simultaneous exif-tool sessions.
        
        Initial application was for preview-exporter which uses preview and image class objects.
        
        It is recommended to have one session per task / service, since if two async tasks
        shared the same session there would be interleaving of arguments...
        
        Examples:

            * local dc=Ffmpeg()
            * dc:convert{ photo=photo, ... }        
--]]


local Ffmpeg, dbg, dbgf = ExternalApp:newClass{ className = 'Ffmpeg', register = true }



--- Constructor for extending class.
--
function Ffmpeg:newClass( t )
    return ExternalApp.newClass( self, t )
end



--- Constructor for new instance.
--
--  @usage pass pref-name, win-exe-name, or mac-pathed-name, if desired, else rely on defaults (but know what they are - see code).
--
function Ffmpeg:new( t )
    t = t or {}
    t.name = t.name or "ffmpeg"
    t.prefName = t.prefName or 'ffmpegApp' -- same pref-name for win & mac.
    t.winExeName = t.winExeName or "ffmbc.exe" -- if included with plugin - probably will be.
    t.macAppName = t.macAppName or "ffmpeg" -- if included with plugin - ditto.
    t.winDefaultExePath = nil -- is there a default path? (doesn't matter - it's always built in).
    t.macDefaultAppPath = nil -- ditto
    t.winPathedName = nil -- pathed access to converter not supported on Windows.
    t.macPathedName = nil -- ditto
    local o = ExternalApp.new( self, t )
    return o
end



return Ffmpeg
