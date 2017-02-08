--[[
        Windows.lua
        
        Extends operating system functionality for Windows specific behavior.
--]]

local Windows, dbg, dbgf = OperatingSystem:newClass{ className = 'Windows' }


--- Constructor for extending class.
--
function Windows:newClass( t )
    return OperatingSystem.newClass( self, t )
end



--- Constructor for new instance.
--
function Windows:new( t )
    local o = OperatingSystem.new( self, t )
    o.sendKeys = Require.findFile( 'System/Support/SendKeysAHK.exe' )
    -- Don't want to wait until first use to find out its not going to work:
    assert( o.sendKeys ~= nil, "Unable to obtain path to send-keys-ahk resource file." )
    return o
end



--- Return OS shell name (e.g. Explorer or Finder)
--
function Windows:getShellName()
    return "Explorer"
end



--- Opens one file in its O.S.-registered default app.
--      
--  @usage      Non-blocking - nothing returned.
--  @usage      Good choice for opening local help files, since lr-http-open-url-in-browser does not work properly on Mac in that case.
--  @usage      Not called directly - see operating system parent class for more info
--      
function Windows:openFileInDefaultApp( file )
    if LrFileUtils.exists( file ) then
        LrShell.openFilesInApp( { "" }, file) -- open file like an app, windows knows what to do.
    else
        error( "Unable to open file in default app, file does not exist: " .. str:to( file ) )
    end
end



--- Send key string verbatim using AHK compiled script, which just directs parameter string verbatim
--  to Lightroom, and must therefore be in AHK compatible format if it contains any special keystroke modifiers.
--      
--  @usage       Ctrl sequence format is: {Ctrl Down}key(s){Ctrl Up}
--  @usage       Not called directly - see operating system parent class for more info
--      
function Windows:sendUnmodifiedKeys( keyStr )
    -- local file2 = LrPathUtils.child( dir, 'SendKeysToLightroom.ps1' )
    if app:getPref( 'testSendKeysFailure' ) then
        return false, "*** Windows send-keys *TEST* failure"
    end
    local param = '"' .. keyStr .. '"'
    return app:executeCommand( self.sendKeys, param )
end



--[[ *** SAVE FOR POSTERITY
        Send key string verbatim using powershell called by bat.
        
        Note: Like the vbs version, this works for everything EXCEPT control-key modified sequences, like Ctrl-s.
        
        Pros: It has extra logic to assure keystrokes are directed at Lightroom, instead of whatever.
        Cons: Powershell scripts are disabled by default. Strangely enough, a script can change script execution policy!
--] ]
function Windows:_sendUnmodifiedKeys( keyStr )

    local dir = Load.getFrameworkDir()
    dir = LrPathUtils.child( dir, 'System' )
    dir = LrPathUtils.child( dir, 'Support' )
    local file1 = LrPathUtils.child( dir, 'SendKeysPS1.bat' )
    local file2 = LrPathUtils.child( dir, 'SendKeysToLightroom.ps1' )
    local param = '"' .. file2 .. '" ' .. keyStr
    return app:executeCommand( file1, param )
end--]]



--[[ *** SAVE FOR POSTERITY
        Send key string verbatim using vbs.
        
        Note: this works for everything EXCEPT control-key modified sequences, like Ctrl-s.
--] ]
function Windows:_sendUnmodifiedKeys( keyStr )
    local frameworkDir = Load.getFrameworkDir()
    local system = LrPathUtils.child( frameworkDir, "System" )
    local support = LrPathUtils.child( system, "Support" )
    local command = LrPathUtils.child( support, "SendKeys.vbs" )
    assert( fso:existsAsFile( command ), "command no file" )
    return self:executeCommand( command, keyStr )
end--]]



--[[ *** SAVE FOR POSTERITY
        Send windows-specific keystroke sequence.
        
        Note:       - With the exception of Ctrl, Alt, & Shift,
                      it is up to plugin author to encode special keystrokes in vbs compatible format.
                      
                      See http://msdn.microsoft.com/en-us/library/8c6yea83%28VS.85%29.aspx for more info.
--] ]
function Windows:sendModifiedKeys( modKeys )
    local k1, k2 = modKeys:find( '-' )
    local keyMods
    local keyStr
    if k1 then
        keyStr = modKeys:sub( k2 + 1 )
        keyMods = modKeys:sub( 1, k1 - 1 )
    else
        error( "No keystroke" )
    end
    if keyMods:find( 'Ctrl' ) then
        keyStr = '^' .. keyStr
    end
    if keyMods:find( 'Alt' ) then
        keyStr = '%' .. keyStr
    end
    if keyMods:find( 'Shift' ) then
        keyStr = '+' .. keyStr
    end
    dbg( "winkeystr: ", keyStr )
    return self:sendUnmodifiedKeys( keyStr )
end--]]



--- windows implementation of operating-system--make-folder-link.
--
function Windows:makeFolderLink( linkPath, folderPath )
    local cmd = "mklink"
    local parms = str:fmtx( '/j "^1"', linkPath )
    local targs = { folderPath }
    return app:executeCommand( cmd, parms, targs, nil, 'del', true )
end



--- windows implementation of operating-system--make-folder-link.
--
function Windows:makeFileLink( linkPath, filePath )
    local cmd = "mklink"
    local parms = str:fmtx( '/h "^1"', linkPath )
    local targs = { filePath }
--function Ap p : e xecuteCommand( command, parameters, targets, output, handling, noQuotes, expectedReturnCode )
    return app:executeCommand( cmd, parms, targs, nil, 'del', true )
end



return Windows

