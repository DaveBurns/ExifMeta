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


local Java, dbg, dbgf = ExternalApp:newClass{ className = 'Java', register = true }



--- Constructor for extending class.
--
function Java:newClass( t )
    return ExternalApp.newClass( self, t )
end



--- Constructor for new instance.
--
--  @usage pass pref-name, win-exe-name, or mac-pathed-name, if desired, else rely on defaults (but know what they are - see code).
--
function Java:new( t )
    t = t or {}
    t.name = t.name or "java"
    t.prefName = t.prefName or 'javaApp' -- same pref-name for win & mac.
    t.winExeName = nil -- if included with plugin - probably will NOT be.
    t.macAppName = nil -- if included with plugin - ditto.
    t.winDefaultExePath = nil -- is there a default path? (doesn't matter - it's always built in).
    t.macDefaultAppPath = nil -- ditto
    t.winPathedName = nil -- pathed access to converter not supported on Windows.
    t.macPathedName = nil -- ditto
    if not str:is( t.exe ) then
        t.exe = "java" -- relative
    end
    -- will overwrite exe with preferred java (as governed by pref), if set.
    local o = ExternalApp.new( self, t ) -- calls process-exe-change which needs exe set to something..
    return o
end



function Java:isUsable()
    if not str:is( self.exe ) then -- if not set to something.
        self.exe = "java" -- set relatively to most likely candidate.
    end
    local usable, qualified = ExternalApp.isUsable( self, true ) -- no-log
    if usable then -- either absolute file exists, or relative given benefit of doubt
--  @param params (string, default="") command-line parameters, if any.
--  @param targets (table(array), default={}) list of command-line targets, usually paths.
--  @param outPipe (outPipe, default=nil) optional output file (piped via '>'), if nil temp file will be used for output filename if warranted by out-handling.
--  @param outHandling (string, default=nil) optional output handling, 'del' or 'get' are popular choices - see app-execute-command for details.
--  @param noQuotes (boolean, default=false) optional in case quotes are problem (@8/Mar/2014, don't remember when they are).
--  @param expectedReturnCode (number, default=0) optional return code expected.
--
--functio n E xternalAp p : e xecuteCommand( params, targets, outPipe, outHandling, noQuotes, expectedReturnCode )
        local target
        if app:isRelease() then
            target = LrPathUtils.child( _PLUGIN.path, "JavaSirve.jar" )
        else
            target = "X:\\Dev\\AppsJava\\JavaSirve\\dist\\JavaSirve.jar"
        end
        if fso:existsAsFile( target ) then
            local status, cmdOrMsg, content = self:executeCommand( "-jar", target, nil, 'del', nil, 999 ) -- return value is hard-coded: 999.
            if status then
                if content:find( "Java sirve...", 1, true ) then -- usually this exactly followed by \r\n or \n.
                    return true
                else
                    Debug.pause( content )
                    return false, "Invalid response from java test execution: "..content
                end
            else
                return false, cmdOrMsg
            end
        else
            return false, "Java sirve test jar not with plugin, expected "..target
        end
    else
        return false, qualified
    end
end



return Java
