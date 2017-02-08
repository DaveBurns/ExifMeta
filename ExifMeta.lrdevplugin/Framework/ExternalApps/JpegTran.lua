--[[
        JpegTran.lua
        
        Represents jpegtran command-line utility.
--]]


local JpegTran, dbg, dbgf = ExternalApp:newClass{ className = 'JpegTran', register = true }



--- Constructor for extending class.
--
function JpegTran:newClass( t )
    return ExternalApp.newClass( self, t )
end



--- Constructor for new instance.
--
--  @usage pass pref-name, win-exe-name, or mac-pathed-name, if desired, else rely on defaults (but know what they are - see code).
--
function JpegTran:new( t )
    t = t or {}
    t.name = t.name or "JpegTran"
    t.prefName = t.prefName or 'jpegTranApp' -- same pref-name for win & mac.
    t.winExeName = t.winExeName or "jpegtran.exe" -- if included with plugin - may not be.
    t.macAppName = t.macAppName or "jpegtran" -- ###1 if included with plugin, also: pre-requisite condition for mac-default-app-path to be used instead of mac-pathed-name, if present on system.
    t.winDefaultExePath = nil -- is there a default path? (doesn't matter - it's always built in).
    t.macDefaultAppPath = "/usr/local/bin/jpegtran"
    t.winPathedName = nil -- pathed access to converter not supported on Windows.
    t.macPathedName = nil -- ditto
    local o = ExternalApp.new( self, t )
    return o
end



return JpegTran
