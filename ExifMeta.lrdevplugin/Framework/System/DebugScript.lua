--[[----------------------------------------------------------------------------
12345678901234567890123456789012345678901234567890123456789012345678901234567890

Debug Script

Copyright 2010, John R. Ellis -- You may use this script for any purpose, as
long as you include this notice in any versions derived in whole or part from
this file.

This file implements the Debug Script menu command.  For a description, see the
accompanying "Debugging Toolkit.htm".
------------------------------------------------------------------------------]]


-- RDC
--[[local Require = require 'Require'.path ("../common")
local Debug = require 'Debug'
require 'strict'


local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils = import 'LrPathUtils'
local LrPrefs = import 'LrPrefs'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local bind = LrView.bind--]]
local f = vf 
-- local prefs = LrPrefs.prefsForPlugin ()

local Newline = WIN_ENV and "\r\n" or "\n"
    --[[ A platform-indepent newline. Unfortunately, some controls (e.g.
    edit_field) need to have the old-fashioned \r\n supplied in strings to
    display newlines properly on Windows. ]]

-- Forward references
local browsePush, debugRequire, formatFilenameGlobals, invokeEditor,
    lineCount, loadFile, optionsPush, showErrors, showWindow

--[[----------------------------------------------------------------------------
private void 
showWindow ()

Shows the main window of the script.
------------------------------------------------------------------------------]]

local prop
    --[[ The properties table for the main window. ]]

local TopText = [[Enter a .lua script file to run:]]

local GlobalText = [[The following globals were defined while running the
script, indicating possible mistakes:]]
GlobalText = GlobalText:gsub ("%c", " ")

function showWindow ()

LrTasks.startAsyncTask( function()
LrFunctionContext.callWithContext ("", function (context)

    prop = LrBinding.makePropertyTable (context)
    
    local resultLabel, resultStr, globalStr = "", "", ""
    
    while true do
        prop.openDebugWindow = (prefs.debugScriptOpenDebugWindow == nil) and 
            true or prefs.debugScriptOpenDebugWindow
        prop.showNewGlobals = (prefs.debugScriptShowNewGlobals == nil) and 
            true or prefs.debugScriptShowNewGlobals
        prop.reloadScripts = (prefs.debugReloadScripts == nil) and 
            true or prefs.debugReloadScripts
        if prefs.debugClearPrefs == nil then
            prop.clearPrefs = false -- RDC
        else
            prop.clearPrefs = prefs.debugClearPrefs
        end
        prop.filename = prefs.debugScriptFilename or ""

        local verb = LrDialogs.presentModalDialog {title = "Debug Script", 
            actionVerb = "Run", cancelVerb = "Close", save_frame = "debugScriptPosition",
            accessoryView = vf:push_button {
                title = "Close Momentarily",
                tooltip = "so you can close plugin manager or other underlying dialog boxes, or twiddle with Lightroom for a second...",
                action = function( button )
                    LrDialogs.stopModalWithResult( button, 'closeDialogs' )
                end
            },
            contents = f:column {
            bind_to_object = prop, spacing = f:control_spacing (),
            f:static_text {title = TopText},
            f:row {
                f:edit_field {value = bind ("filename"), width_in_chars = 30,
                    immediate = true},
                f:push_button {title = "Browse...", 
                    action = showErrors (browsePush)}},
            f:checkbox {title = "Show new globals (likely mistakes)",
                value = bind ("showNewGlobals")},
            f:checkbox {title = "Reload all 'require'd scripts",
                value = bind ("reloadScripts")},
            f:checkbox {title = "Clear LrPrefs.prefsForPlugin",
                value = bind ("clearPrefs")},
            f:row {
                f:push_button {title = "Reload Plugin", width=share('button'), tooltip = "shutdown & reinitialize plugin...",
                    action = function() reload:now() end },
                f:push_button {title = "Show Log", width=share('button'), tooltip = "open debug log file in default app",
                    action = function() app:showDebugLog() end },
                f:push_button {title = "Clear Log", width=share('button'), tooltip = "clear debug log by moving log file to trash",
                    action = function() app:clearDebugLog() end }},
            resultStr == "" and LrView.kIgnoredView or f:column {
                f:static_text {title = resultLabel},
                f:edit_field {value = resultStr, width_in_chars = 40, 
                    immediate = true, 
                    height_in_lines = math.min (10, 
                                        math.max (3, lineCount (resultStr)))}},
            globalStr == "" and LrView.kIgnoredView or f:column {
                f:static_text {title = GlobalText, width_in_chars = 40, height_in_lines = 2,
                    wrap = true},
                f:edit_field {value = globalStr, width_in_chars = 40, 
                     immediate = true, 
                     height_in_lines = math.min (25, lineCount (globalStr))}}}}
        prefs.debugScriptOpenDebugWindow = prop.openDebugWindow 
        prefs.debugScriptShowNewGlobals = prop.showNewGlobals 
        prefs.debugReloadScripts = prop.reloadScripts 
        prefs.debugClearPrefs = prop.clearPrefs 
        prefs.debugScriptFilename = prop.filename
        
        if verb == "cancel" then break end
        if verb == "closeDialogs" then
            LrTasks.sleep( 3 )
        elseif verb == "ok" then
            if prop.filename == "" then
                LrDialogs.message ("Enter a file to be loaded")
            else
                service = 'done'
                local success, result, filenameGlobals = loadFile (prop.filename)
                globalStr = formatFilenameGlobals (filenameGlobals)
                if success then 
                    resultLabel = "Returned:"
                    resultStr = Debug.pp (result)
                    
                    local times = 5
                    repeat
                        LrTasks.sleep( .1 )
                        times = times - 1
                    until times == 0 or service == 'started'
                    if service == 'started' then
                        repeat
                            LrTasks.sleep( .2 )
                        until service == 'done'
                    end
                    
                else
                    resultLabel = "Failed:"
                    resultStr = result
                    invokeEditor (result)
                    end
                resultStr = resultStr:gsub ("\n", Newline)
            end
        else
            error( "bad verb" )
        end
        end
    end)
end)
end 
 

--[[----------------------------------------------------------------------------
private void
invokeEditor (string errorStr)

Given "errorStr", an error string thrown by error(), parses the filename
and line number and invokes the editor.  If the string doesn't contain
a file/line or the launch of the editor fails, returns silently.
------------------------------------------------------------------------------]]

function invokeEditor (errorStr)
    local file, line1 = errorStr:match ('%[string "([^"]+)"%]:(%d+):')
    if file then 
        local line2 = errorStr:match ("at line (%d+)%)") 
        Debug.invokeEditor (file, line2 or line1) 
        end
    end
    

--[[----------------------------------------------------------------------------
private void
browsePush (LrView button)

Implements the Browse button of the main window, by opening the standard
file-open dialog and setting "prop.filename" to the result.
------------------------------------------------------------------------------]]

function browsePush (button)
    local dir 
    if prop.filename then dir = LrPathUtils.parent (prop.filename) end
    if not dir then dir = LrPathUtils.parent (_PLUGIN.path) end
    local paths = LrDialogs.runOpenPanel {title = "Debug Script > Open",
        canChooseFiles = true, canChooseDirectores = false, 
        canCreateDirectories = false, fileTypes = "lua", 
        initialDirectory = dir}
    if paths then prop.filename = paths [1] end 
    end

--[[----------------------------------------------------------------------------
private boolean success, result, table resultGlobals
loadFile (string filename)

Compiles and executes the file "filename", which is assumed to be in the plugin
directory if the name doesn't include a directory.  Any nested 'require's will
be loaded from the same directory.

Returns success = true if the execution succeeds, in which case "result" is the
value returned by the file.  Returns success = false if an error is thrown, in
which case "result" is the error string. The table "resultGlobals" maps a
filename that was loaded directly or indirectly via "require" to a table of
globals that were defined by loading that file.  That table maps a global
variable name that was defined by the file to its value.

If prop.reloadScripts is true, then the script and its nested 'require's will be
reloaded; otherwise, they will only be loaded if they're not already loaded.

If prop.clearPrefs is true, then the plugin preferences are deleted.

The file is always run with Debug enabled.

Before executing the file, any global names that had been defined by previous
calls to loadFile() are deleted.
------------------------------------------------------------------------------]]

local originalG

function loadFile (filename)
    local loadDirectory = LrPathUtils.parent (filename)
    if not loadDirectory then loadDirectory = _PLUGIN.path end
    filename = LrPathUtils.leafName (filename)

    if not originalG then
        originalG = table.shallowcopy (_G)
        setmetatable (originalG, nil)
    else
        for k, v in pairs (_G) do 
            if originalG [k] == nil then rawset (_G, k, nil) end
            end
        end

    if prop.clearPrefs then 
        for k, v in prefs:pairs () do
            if k:sub (1, 5) ~= "debug" then prefs [k] = nil end
            end
        end

    assert( Debug.enabled, "Debug not enabled" )
    -- Debug.init (true) - RDC: handled externally.
    Debug.setLogFilename (LrPathUtils.child (loadDirectory, "_debug.log")) -- RDC
    Require.reload (prop.reloadScripts)  
    Require.loadDirectory (loadDirectory)


    -- local success, result = LrTasks.pcall (Require.require, 'Init.lua', true)
    local success, result = LrTasks.pcall (Require.require, filename, true)
    
    return success, result, Require.newGlobals ()
    end    
            
        
    

--[[----------------------------------------------------------------------------
private string
formatFilenameGlobals (table filenameNewGlobals)

Given the table "filenameNewGlobals" (returned by loadFile()), which maps a
filename to the globals defined by loading that file, formats a nice report
showing file-by-file the globals defined by the file.
------------------------------------------------------------------------------]]

function formatFilenameGlobals (filenameNewGlobals)
    local s = ""
    for filename, newGlobals in pairs (filenameNewGlobals) do
        local s1 = ""
        for k, v in pairs (newGlobals) do
            if s1 ~= "" then s1 = s1 .. Newline end
            s1 = s1 .. k .. " = " .. Debug.pp (v, 0, 35)
            end

        if s1 ~= "" then
            if s ~= "" then s = s .. Newline .. Newline end 
            s = s .. filename .. ":" .. Newline .. s1
            end
        end
    return s
    end
    
        
--[[----------------------------------------------------------------------------
private int
lineCount (string s)

Counts the number of lines in "s".  The last line may or may not end
with a newline, but it counts as a line.
------------------------------------------------------------------------------]]

function lineCount (s)
    local l = 0
    for i = 1, #s do if s:sub (i, i) == "\n" then l = l + 1 end end
    if #s > 0 and s:sub (-1, -1) ~= "\n" then l = l + 1 end
    return l
    end

--[[----------------------------------------------------------------------------
func showErrors (func)

Returns a function wrapped around "func" such that if any errors occur from
calling "func", the standard Lightroom error dialog is displayed.  By default,
Lightroom doesn't show an error dialog for callbacks from LrView controls or for
tasks created by LrTasks.  We don't call Debug.showErrors here to avoid
nasty recursions.
------------------------------------------------------------------------------]]

function showErrors (func)
    return function (...)
        return LrFunctionContext.callWithContext("wrapped", 
            function (context)
                LrDialogs.attachErrorDialogToFunctionContext (context)
                return func (unpack (arg))
                end)
        end 
    end


-- RDC
-- showWindow ()
return { showWindow = showWindow }
        