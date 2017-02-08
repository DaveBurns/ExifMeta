--[[
        Synopsis:           Opens one file in its O.S.-registered default app.
        
        Notes:              - I assume this is non-blocking.
                            - Good choice for opening local help files, since lr-http-open-url-in-browser does not work
                              properly on Mac in that case.
        
        Returns:            X
--]]        


local Mac = OperatingSystem:newClass{ className = 'Mac' }



--- Constructor for extending class.
--
function Mac:newClass( t )
    return OperatingSystem.newClass( self, t )
end



--- Constructor for new instance.
--
function Mac:new( t )
    return OperatingSystem.new( self, t )
end



--- Return OS shell name (e.g. Explorer or Finder)
--
function Mac:getShellName()
    return "Finder"
end



--- Open file in default app.
--
--  @param      file        path
--
function Mac:openFileInDefaultApp( file )
    LrShell.openFilesInApp( { file }, "open") -- macs like to feed the file to the "open" command.
end



--[[
        May not work in Lion, may need: ###1 test on Mac
        
finder_pid=$(ps -xawwo pid,command | grep
"/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder$" | awk
'{print $1}')

/bin/launchctl bsexec $finder_pid /usr/bin/osascript -e 'tell application
"System Events" to log out' 

ref: http://groups.google.com/group/macenterprise/browse_thread/thread/bf3120cf188f04e5/6206a68d204c10b4?show_docid=6206a68d204c10b4


Another example:
set app_name to "Finder"
set the_pid to (do shell script "ps ax | grep " & (quoted form of app_name) & " | grep -v grep | awk '{print $1}'")
if the_pid is not "" then do shell script ("kill -9 " & the_pid)
from: http://macstuff.beachdogs.org/blog/?p=31

Another app note: http://developer.apple.com/library/mac/#technotes/tn2065/_index.html

--]]
--- Send key string verbatim to Lightroom.
--      
--  <p>Uses applescript string passed to osascript.</p>
--
function Mac:sendUnmodifiedKeys( keyStr, keyDowns, keyUps )

    if app:getPref( 'testSendKeysFailure' ) then
        return false, "*** Mac send-keys *TEST* failure"
    end

    local scriptTbl = {}

    --###1scriptTbl[#scriptTbl + 1] = "-e 'tell application \"Lightroom\" to activate'"
    scriptTbl[#scriptTbl + 1] = "-e 'tell application \"System Events\"'"

    if keyDowns then
        tab:appendArray( scriptTbl, keyDowns )
    end

    if str:is( keyStr ) then
        scriptTbl[#scriptTbl + 1] = "-e 'keystroke \"" .. keyStr .. "\"'"
    -- else maybe just keydowns...
    end

    if keyUps then
        tab:appendArray( scriptTbl, keyUps )
    end

    scriptTbl[#scriptTbl + 1] = "-e 'end tell'"

    local scriptStr = table.concat( scriptTbl, ' ' )
    local command = 'osascript'
    local params = scriptStr

    return self:executeCommand( command, params ) -- no targets, no output.
end



-- save for posterity...
--[[function Mac:_sendUnmodifiedKeys( keyStr )
    local command = 'osascript'
    local dir = Load.getFrameworkDir()
    dir = LrPathUtils.child( dir, 'System/Support' )
    local file = LrPathUtils.child( dir, 'SendKeys.ascript' )
    assert( fso:existsAsFile( file ), "no script" ) -- redundant since execute-command will also check it.
    local params = '"' .. file .. '" ' .. keyStr  
    return self:executeCommand( command, params ) -- no targets, no output.
end--]]



--- Send mac-modified keystroke sequence to mac os / lightroom.
--      
--  <p>Format examples:</p><blockquote>
--      
--          Ctrl-S<br>
--          Cmd-FS<br>
--          ShiftCtrl-S</blockquote></p>
--
--  @param     modKeys     Mash the modifiers together (in any order), follow with a dash, then mash the keystrokes together (order matters).
--
function Mac:sendModifiedKeys( modKeys )
    local k1, k2 = modKeys:find( '-' )
    local keyMods
    local keyStr
    if k1 then
        keyStr = modKeys:sub( k2 + 1 )
        keyMods = modKeys:sub( 1, k1 - 1 )
    else
        error( "No keystroke" )
    end
    local keyDownTbl = {}
    local keyUpTbl = {}
    if keyMods:find( 'Shift' ) then
        keyDownTbl[#keyDownTbl + 1] = "-e 'key down shift'"
        keyUpTbl[#keyUpTbl + 1] = "-e 'key up shift'"
    end
    if keyMods:find( 'Option' ) or keyMods:find( 'Opt' ) then -- added short form 23/Nov/2013 18:13.
        keyDownTbl[#keyDownTbl + 1] = "-e 'key down option'"
        keyUpTbl[#keyUpTbl + 1] = "-e 'key up option'"
    end
    if keyMods:find( 'Cmd' ) or keyMods:find( 'Command' ) then -- added long form 23/Nov/2013 18:12
        keyDownTbl[#keyDownTbl + 1] = "-e 'key down command'"
        keyUpTbl[#keyUpTbl + 1] = "-e 'key up command'"
    end
    if keyMods:find( 'Ctrl' ) or keyMods:find( 'Control' ) then -- added long form 23/Nov/2013 18:12 (fixed bug in long form 8/Feb/2014 (said 'keysMod' instead of 'keyMods') - I don't see how this could have worked since long form enhancement.
        keyDownTbl[#keyDownTbl + 1] = "-e 'key down control'"
        keyUpTbl[#keyUpTbl + 1] = "-e 'key up control'"
    end
    return self:sendUnmodifiedKeys( keyStr, keyDownTbl, keyUpTbl )
end



--- mac implementation of operating-system--make-folder-link.
--
function Mac:makeFolderLink( linkPath, folderPath )
    local cmd = "ln"
    local parms = str:fmtx( '/s "^1"', folderPath ) -- ###1 test on Mac - this does not look right - should be '-s' I would think..
    local targs = { linkPath }
    return app:executeCommand( cmd, parms, targs, nil, 'del', true )
end



--- mac implementation of operating-system--make-folder-link. ###1 test on Mac
--
function Mac:makeFileLink( linkPath, filePath )
    local cmd = "ln"
    local parms = str:fmtx( '"^1"', filePath )
    local targs = { linkPath }
    return app:executeCommand( cmd, parms, targs, nil, 'del', true )
end



return Mac
