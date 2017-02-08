--[[================================================================================
        Lightroom/Lightroom
        
        Supplements LrApplication namespace (Lightroom from an app point of view, as opposed to a plugin point of view...).
================================================================================--]]


local Lightroom = Object:newClass{ className="Lightroom", register=false }



--- Constructor for extending class.
--
function Lightroom:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function Lightroom:new( t )
    local o = Object.new( self, t )
    return o
end



--- Get operating system user directory
function Lightroom:getOsUserDirAndName()
    local datDir = LrPathUtils.getStandardFilePath( 'appData' )
    if datDir then
        local isDir, isFile = fso:existsAs( datDir, 'directory' )
        if isDir then
            local index
            local name
            local comps = str:splitPath( datDir )
            for i = #comps, 1, -1 do
                local comp = comps[i]
                if comp == 'Users' then
                    break
                else
                    index = i -- username
                    name = comp
                end
            end
            if index then
                assert( str:is( name ), "no name" )
                comps[index + 1] = nil
                return str:componentsToPath( comps, app:pathSep() ), name
            else
                return nil, "no user name in app data dir path: "..datDir
            end
        else
            return nil, "app data dir does not exist: "..datDir
        end
    else
        return nil, "no app data dir"
    end
end



--- Get Windows "send-to" folder
function Lightroom:getWinSendToDir()
    app:callingAssert( WIN_ENV, "not applicable on Mac" )
    local d, e = self:getOsUserDirAndName()
    if d then
        d = d.."\\AppData\\Roaming\\Microsoft\\Windows\\SendTo"
        local isDir, isFile = fso:existsAs( d, 'directory' )
        if isDir then
            return d
        else
            return nil, "no send-to dir where expected: "..d
        end
    else
        return d, e
    end
end



--- Get filename preset dir.
--
--  @usage *** deprecated - not sure this is reliable @2/Dec/2013 10:31 (use v2 below instead).
--
function Lightroom:getFilenamePresetDir()
    local datDir = LrPathUtils.getStandardFilePath( 'appData' )
    for k, v in pairs( LrApplication.filenamePresets() ) do
        local exists = LrFileUtils.exists( v )
        if exists then
            --Debug.pause( "exists", v )
            return false, LrPathUtils.parent( v ) -- presets not stored with catalog
        end 
        --Debug.pause( v:sub( -60 ) )
    end
    local catDir = cat:getCatDir()
    local lrSets = LrPathUtils.child( catDir, "Lightroom Settings" )
    local fnTmpl = LrPathUtils.child( lrSets, "Filename Templates" )
    if fso:existsAsDir( fnTmpl ) then
        return true, fnTmpl -- presets *are* stored with catalog
    else
        return nil, LrPathUtils.child( datDir, "Filename Templates" ), fnTmpl -- not sure where they're stored: here's both locations.
    end
end



--- Get filename preset dir - 2nd version (recommended).
--
--  @usage *** deprecated - use general function instead.
--
--  @return dir (or nil)
--  @return reason for nil dir (or nil itself).
--
function Lightroom:getFilenamePresetDir2()
    local dir, err = self:computeActivePresetDir() -- leaf-name -- 'Lightroom' or 'Lightroom Settings'
    if dir then
        dir = LrPathUtils.child( dir, "Filename Templates" )
        if fso:existsAsDir( dir ) then
            return dir
        else
            return nil, "Unable to locate filename templates"
        end
    else
        return nil, err or "no additional information"
    end
end



--- Get preferences directory.
--
--  @usage *** deprecated - this function only works in Windows. (I think @13/Apr/2014 3:22, Pretend is only function using this).
--  @usage since filename is different too (in different OS's), consider using getPrefsFile instead (parent is prefs dir).
--
--  @return dir (or nil)
--  @return reason for nil dir (or nil itself).
--
function Lightroom:getPrefsDir()
    return self:getPresetDir( 'Preferences' )
end



--- Get preferences file.
--
--  @usage filename and location is different on each system, as is data-format, on Windows, format is Lua, on Mac it's plist/partly-binary.
--
--  @return prefs file path or nil if none.
--  @return error message if no prefs file.
--
function Lightroom:getPrefsFile()
    local lrPrefsDir = LrPathUtils.getStandardFilePath( 'appPrefs' ) -- reported dir, will also be computed for comparison..
    if not lrPrefsDir then
        return nil, "no prefs dir"
    end
    local lrPrefsDirExists = fso:existsAsDir( lrPrefsDir )
    if WIN_ENV then
        local fn = str:fmtx( "Lightroom ^1 Preferences.agprefs", app:lrVersion() )
        local dir, err = lightroom:getPresetDir( 'Preferences' )
        if dir then -- it exists
            if dir ~= lrPrefsDir then
                if lrPrefsDirExists then -- differ
                    app:log( "*** Lr reported preference dir exists (^1) but differs from computed path: '^2', which also exists - assuming computed value is correct.", lrPrefsDir, dir )
                else
                    app:log( "*** Lr reported preference dir does not exist (^1), but computed dir does exist and is assumed to be correct: ^2", lrPrefsDir, dir )
                end
            else -- same
                app:log( "Lr reported preference dir same as computed dir: '^1' (which exists).", dir )
            end
            local pf = LrPathUtils.child( dir, fn )
            if fso:existsAsFile( pf ) then
                return pf
            else
                return nil, "Lightroom preferences file does not exist as: "..pf
            end
        elseif lrPrefsDirExists then
            Debug.pause( lrPrefsDir, err )
            local pf = LrPathUtils.child( lrPrefsDir, fn )
            if fso:existsAsFile( pf ) then
                app:log( "*** Unable to compute Lr preferences dir - ^1, relying on Lr reported dir, since it exists and so does file '^2' - I hope that's the correct preference file." )
                return pf
            else
                return nil, err
            end
        else
            app:log( "*** Unable to compute Lr preferences dir - ^1, and Lr reported dir (^2) does not exist.", err, lrPrefsDir )
            return nil, err
        end
    else -- Mac
        if lrPrefsDirExists then
            local fn = str:fmtx( "com.adobe.Lightroom^1.plist", app:lrVersion() )
            local pf = LrPathUtils.child( lrPrefsDir, fn )
            if fso:existsAsFile( pf ) then
                Debug.pause( pf )
                app:log( "*** Mac preference file is in different format than expected." ) -- ###2: remove this pseudo-warning log if implementation supports Mac format.
                return pf
            else
                return nil, "Prefs file not existing: "..pf
            end
        else
            return nil, "Prefs dir not existing: "..lrPrefsDir
        end 
    end
    error( "how here?" )
end




--- Generic function for getting Lightroom settings dir - either root or subdir.
--
--  @usage: lightroo m : g etPresetDir() same as lightroom:computeActivePresetDir()
--  @usage: lightroo m : g etPresetDir( 'Preferences' ) to get prefs dir..
--  @usage: lightroo m : g etPresetDir( 'Filename Templates' ) to get fn tmpl dir..
--  @usage: lightroo m : g etPresetDir( 'Export Presets' ) to get export preset dir..
--
--  @return path
--  @return orMsg
--
function Lightroom:getPresetDir( subdir, create )
    local dir, err = self:computeActivePresetDir() -- leaf-name -- 'Lightroom' or 'Lightroom Settings'
    if dir then
        if str:is( subdir ) then
            dir = LrPathUtils.child( dir, subdir )
            if fso:existsAsDir( dir ) then
                return dir
            elseif create then
                local s, m, c = fso:assureDir( dir )
                Debug.pauseIf( s and not c, "dir not created?" )
                --return s, m - until 19/May/2014 4:32 (bug if needed to be created)
                -- after 19/May/2014 4:35:
                if s then
                    return dir
                elseif m then
                    return nil, m
                else
                    Debug.pause( "?" )
                    return nil, "no additional info"
                end
            else
                return nil, str:fmtx( "Unable to locate '^1' folder - expected to be subdirectory of '^2'", subdir, dir )
            end
        else
            return dir
        end
    else
        return nil, err or "no additional information"
    end
end



--- Evaluate conditions necessary for successfully restarting Lightroom. *** saves prefs?
--
--  @usage *** deprecated unless follow-up restart method saves prefs (or you/user does not care about it).
--
--  @return restart function appropriate for OS, or nil.
--  @return status message to explain no restart function.
--
function Lightroom:prepareForRestart( catPath )
    local f, qual
    local s, m = app:call( Call:new{ name="Preparing to Restart Lightroom", async=false, main=function( call ) -- no guarding "should" be necessary.
        local exe
        local opts
        if not str:is( catPath ) then
            catPath = catalog:getPath()
        end
        local targets = { catPath }
        local doPrompt
        if WIN_ENV then
            exe = app:getPref( "lrApp" ) or app:getGlobalPref( "lrApp" ) -- set one of these in plugin manager or the like, to avoid prompt each time.
            opts = "-restart"
            if str:is( exe ) then
                if fso:existsAsFile( exe ) then
                    f = function()
                        return app:executeCommand( exe, opts, targets )
                    end -- no qualifications: if config'd should be good to go.
                else
                    qual = str:fmtx( "Lightroom app does not exist here: '^1' - consider changing pref...", exe )
                end
            else -- no exe config'd
                -- local sts, othr, x  = app:executeCommand( "ftype", nil, "Adobe.AdobeLightroom" )
                local sts, cmdOrMsg, resp  = app:executeCommand( "ftype Adobe.AdobeLightroom", nil, nil, nil, 'del', true )
                if sts then
                    app:logv( cmdOrMsg )
                    local q1, q2 = resp:find( "=", 1, true )
                    if q1 then
                        local p1, p2 = resp:find( ".exe", q2 + 1, true )
                        if p1 then
                            exe = resp:sub( q2 + 1, p2 )
                            if str:is( exe ) then
                                if fso:existsAsFile( exe ) then
                                    f = function()
                                        return app:executeCommand( exe, opts, targets )
                                    end
                                    qual = str:fmtx( "Lightroom executable (obtained by asking Windows): ^1", exe )
                                else
                                    qual = str:fmtx( "Lightroom app should exist here, but doesn't: '^1' - consider setting explicit pref...", exe )
                                end
                            else
                                qual = str:fmtx( "Exe file as parsed from ftype command does not exist: ^1", exe )
                            end
                        else
                            qual = str:fmtx( "Unable to parse exe file from ftype command, which returned: ^1", resp )
                        end
                    else
                        qual = str:fmtx( "Unable to parse exe file from ftype command, which returned '^1'", resp )
                    end
                else
                    qual = str:fmtx( "Unable to obtain lr executable from ftype command - ^1", cmdOrMsg )
                end
            end
        else -- Mac
            f = nil
            qual = "Auto-restart not supported on Mac yet."
            --[[ best not to try programmatic restart on Mac, until tested.
            f = function()
                return app:executeCommand( "open", nil, targets ) -- ###1 test on Mac - @10/May/2013 17:20 - not validated on Mac.
            end -- no qual
            --]]
        end
    end } )
    if s then
        return f, qual
    else
        return nil, m
    end
end



--- Restarts lightroom with current or specified catalog.
--
--  @usage *** deprecated, since does not save prefs - use other method, unless you want to subvert prefs.
--  @usage *** Does NOT save preferences on the way out (@25/Nov/2013, there is no way I know to restart and save prefs).
--  @usage depends on 'lrApp' pref or global-pref for exe-path in windows environment - if not there, user will be prompted for exe file.
--
--  @param catPath (string, default = current catalog) path to catalog to restart with.
--  @param noPrompt (boolean, default = false) set true for no prompting, otherwise user will be prompted prior to restart, if prompt not permanently dismissed that is.
--
function Lightroom:restart( catPath, noPrompt )
    local s, m = app:call( Call:new{ name="Restarting Lightroom", async=false, main=function( call ) -- no guarding "should" be necessary.
        local exe
        local opts
        if not str:is( catPath ) then
            catPath = catalog:getPath()
        end
        local targets = { catPath }
        local doPrompt
        if WIN_ENV then
            exe = app:getPref( "lrApp" ) or app:getGlobalPref( "lrApp" ) -- set one of these in plugin manager or the like, to avoid prompt each time.
            opts = "-restart"
            if not str:is( exe ) or not fso:existsAsFile( exe ) then
                if not str:is( exe ) then
                    app:logVerbose( "Consider setting 'lrApp' in plugin manager or the like." )
                    Debug.pause( "Consider setting 'lrApp' in plugin manager or the like." )
                else
                    app:logWarning( "Lightroom app does not exist here: '^1' - consider changing pref...", exe )
                end
                repeat
                    exe = dia:selectFile{ -- this serves as the "prompt".
                        title = "Select lightroom.exe file for restart.",
                        fileTypes = { "exe" },
                    }
                    if exe ~= nil then
                        if fso:existsAsFile( exe ) then
                            break
                        else
                            app:show{ warning="Nope - try again." }                            
                        end
                    else
                        return false, "user cancelled"
                    end
                until false
            elseif not noPrompt then
                doPrompt = true
            -- else just do it.
            end
            --app:setGlobalPref( "lrApp", exe ) -- not working: seems pref is not commited, even if long sleep.
            --app:sleep( .1 ) -- superstition, probably does not help to persist prefs..
            --[[ *** save for possible future resurrection: can't get restart to happen following task-kill.
            local s, m = app:executeCommand( "taskkill", "/im lightroom.exe", nil ) -- no targets. ###2 if this works, port to exit method as well.
            if s then 
                app:log( "Issued taskkill..." )
            else
                return false, m
            end
            --]]
            --assert( app:getGlobalPref( "lrApp" ) == exe, "no" )
        else
            exe = "open"
            doPrompt = true
        end
        if doPrompt then
            -- osascript -e 'tell application "Adobe Photoshop Lightroom 5" to quit' -- ###2
            local btn = app:show{ confirm="Lightroom will restart now, if it's OK with you.",
                actionPrefKey = "Restart Lightroom",
            }
            if btn ~= 'ok' then
                return false, "user cancelled"
            end
        -- else don't prompt
        end
        app:executeCommand( exe, opts, targets )
        app:error( "Lightroom should have restarted." ) -- since it never get's here, I question if preferences were actually saved - hmm...
    end } )
end



--- Exit Lightroom
--
function Lightroom:exit()
    local keys = app:getPref( 'keysToExitLightroom' )
    if not str:is( keys ) then
        keys = ( WIN_ENV and "{Alt Down}f{Alt Up}x" ) or "Cmd-fx"
    end
    local s, m
    if WIN_ENV then
        s, m = app:sendWinAhkKeys( keys ) -- until 25/Nov/2013 23:00
        -- I tried this once and it seemed prefs were saved, now it seems they're not.. - I'm sticking with the keystroke injection, which either works
        -- exactly as expected or not at all.
        --s, m = app:executeCommand( "taskkill", "/im lightroom.exe", nil ) - no targets. ###2 theoretically, this should be more reliable, but so far: it's not.
    else
        s, m = app:sendMacEncKeys( keys ) -- ###1 test on Mac.
    end
    return s, m
end



--- Get active dir for lightroom settings, e.g. presets n' preferences.
--
--  @usage re-worked 6/Dec/2014 22:48 to (hopefully) solve problem with wrong computation on Mac/Yosemite.
--
function Lightroom:computeActivePresetDir()
    local presetFolders = LrApplication.developPresetFolders()
    for i, v in ipairs( presetFolders ) do
        if not v:getPath():find( "[/\\]Adobe Photoshop Lightroom" ) then -- presumably an Lr built-in preset.
            local candidate = LrPathUtils.parent( v:getPath() )
            repeat
                local leafName = LrPathUtils.leafName( candidate )
                if leafName == "Lightroom" or leafName == 'Lightroom Settings' then -- bingo
                    return candidate
                else -- not it (never is on the first try) but in Windows, it is on the second try, and on Mac/Yosemite, it may be the third try.
                    candidate = LrPathUtils.parent( candidate )
                end
            until candidate == nil
            Debug.pause( "?" )
        -- else probably a built-in dev preset.
        end
    end
    return nil, "Active preset directory is unobtainable using develop preset folder path parsing"
end



--- Determine Lr app/exe file path based on develop preset folders, or whatever means possible.
--
--  @return exe file path or nil if none
--  @return Lr program folder path or error message.
-- 
function Lightroom:computeLrAppPath()
    local presetFolders = LrApplication.developPresetFolders()
    for i, v in ipairs( presetFolders ) do
        if v:getPath():find( "Adobe Photoshop Lightroom" ) then
            local presetFolderPath = LrPathUtils.parent( v:getPath() )
            local presetFolderDirName = LrPathUtils.leafName( presetFolderPath )
            Debug.pauseIf( presetFolderDirName ~= 'TEMPLATES', "not templates" )
            local devModulePath = LrPathUtils.parent( presetFolderPath )
            local devModuleDirName = LrPathUtils.leafName( devModulePath )
            Debug.pauseIf( devModuleDirName ~= 'Develop.lrmodule', "not dev module" )
            local lrAppFolderPath = LrPathUtils.parent( devModulePath )
            local lrAppPath = LrPathUtils.child( lrAppFolderPath, WIN_ENV and 'lightroom.exe' or 'lightroom' ) -- ###1 test on Mac.
            if fso:existsAsFile( lrAppPath ) then
                return lrAppPath, lrAppFolderPath -- got it.
            else
                Debug.pause( "Hmm... - no Lr executable here:", lrAppPath )
            end
        end
    end
    Debug.pause( "No Lr app/exe via dev-presets." )
    if WIN_ENV then    
        app:logV( "Unable to compute Lr app path based on preset folders - trying another approach..." )
        local sts, cmdOrMsg, resp  = app:executeCommand( "ftype Adobe.AdobeLightroom", nil, nil, nil, 'del', true )
        if sts then
            app:logv( cmdOrMsg )
            local q1, q2 = resp:find( "=", 1, true )
            if q1 then
                local p1, p2 = resp:find( ".exe", q2 + 1, true )
                if p1 then
                    exe = resp:sub( q2 + 1, p2 )
                    if str:is( exe ) then
                        if fso:existsAsFile( exe ) then
                            app:logV( "Lightroom executable (obtained by asking Windows): ^1", exe )
                            return exe, LrPathUtils.parent( exe ) -- eureka!
                        else
                            qual = str:fmtx( "Lightroom app should exist here, but doesn't: '^1' - consider setting explicit pref...", exe )
                        end
                    else
                        qual = str:fmtx( "exe file as parsed from ftype command does not exist: ^1", exe )
                    end
                else
                    qual = str:fmtx( "unable to parse exe file from ftype command, which returned: ^1", resp )
                end
            else
                qual = str:fmtx( "unable to parse exe file from ftype command, which returned '^1'", resp )
            end
        else
            qual = str:fmtx( "unable to obtain lr executable from ftype command - ^1", cmdOrMsg )
        end
    else
        qual = "unable to compute Lr app path based on preset folders (only method used so far on Mac)."
    end    
    return nil, "Unable to compute Lr app path - "..qual
end

   

--- Get (combo-box compatible) array of develop preset names.
--  ###3 consider a develop-presets module.
function Lightroom:getDevelopPresetNames()
    local names = {}
    local folders = LrApplication.developPresetFolders()
    for i, folder in ipairs( folders ) do
        local presets = folder:getDevelopPresets()
        for i,v in ipairs( presets ) do
            names[#names + 1] = v:getName()
        end
    end
    return names
end
Lightroom.getDevPresetNames = Lightroom.getDevelopPresetNames -- function Lightroom:getDevPresetNames(...)



--- Get (popup compatible) array of develop preset items - value is UUID.
--
--  @param params optional table of parameters (all members are optional):
--      <br>    folderIncl
--      <br>    folderExcl
--      <br>    nameIncl
--      <br>    nameExcl
--
function Lightroom:getDevelopPresetItems( params )
    params = params or {}
    local items = {}
    local folders = LrApplication.developPresetFolders()
    for i, folder in ipairs( folders ) do
        repeat
            local folderName = folder:getName()
            if str:includedAndNotExcluded( folderName, params.folderIncl, params.folderExcl ) then
                local folderIndex = #items + 1
                local presets = folder:getDevelopPresets()
                for i, v in ipairs( presets ) do
                    local name = v:getName()
                    if str:includedAndNotExcluded( name, params.nameIncl, params.nameExcl ) then
                        items[#items + 1] = { title=name, value=v:getUuid() }
                    else
                        --Debug.pause( "Excluded preset name:", name, params.nameIncl, params.nameExcl )
                    end
                end
                if #items >= folderIndex then -- some items from folder included.
                    table.insert( items, folderIndex, { separator=true } )
                    table.insert( items, folderIndex, { title=folderName, value=nil } )
                    table.insert( items, folderIndex, { separator=true } )
                end
            else
                --Debug.pause( "Excluded preset folder:", folderName, params.folderIncl, params.folderExcl )
            end
        until true
    end
    return items
end
Lightroom.getDevPresetItems = Lightroom.getDevelopPresetItems -- function Lightroom:getDevPresetItems(...)



--- Get (popup compatible) array of metadata preset items - value is UUID.
--
function Lightroom:getMetadataPresetItems( substr ) -- no equiv to get plain names just yet.
    local items = {}
    local metaPresets = LrApplication.metadataPresets()
    for name, id in pairs( metaPresets ) do
        if not substr or name:find( substr, 1, true ) then
            items[#items + 1] = { title=name, value=id }
        end
    end
    return items
end
Lightroom.getMetaPresetItems = Lightroom.getMetadataPresetItems -- function Lightroom:getMetadataPresetItems(...)



--- Get camera calibration profile items corresponding to specified model.
--
function Lightroom:getCameraProfiles( model )
    local profiles = { "Adobe Standard" }
    local function getSome( dir, rmv )
        local c = 0
        for file in LrFileUtils.files( dir ) do
            repeat
                if LrFileUtils.exists( file ) == 'directory' then break end -- ignore directories
                if LrPathUtils.extension( file ) ~= 'dcp' then break end  -- ignore recipes etc.
                local filename = LrPathUtils.leafName( file )
                if str:isBeginningWith( filename, '_' ) then break end -- ignore "temp" files..
                if not str:isBeginningWith( filename, model ) then
                    --Debug.pause( not rmv, model, filename )
                    break
                end -- ignore special-purpose profiles for individual photos.
                -- take the rest:
                local profileName = LrPathUtils.removeExtension( filename ) -- assumes profile name is same as filename - for me (Rob): it is. If not - there will be bogus entries: user beware..
                if rmv then
                    if str:isBeginningWith( profileName, model ) then
                        profileName = LrStringUtils.trimWhitespace( profileName:sub( #model + 1 ) )
                    end
                else
                    --Debug.pause( model, profileName )
                end
                profiles[#profiles + 1] = profileName
                c = c + 1
            until true
        end
        if c > 0 then
            app:logV( "Found ^1 for ^2 in ^3.", str:nItems( c, "camera profiles" ), model, dir )
        else
            app:logV( "No camera profiles for ^1 in ^2.", model, dir )
        end
    end
    local pgmData    
    if WIN_ENV then
        pgmData = "C:\\ProgramData\\Adobe\\CameraRaw\\CameraProfiles\\Camera"
    else
        pgmData = "/Library/Application Support/Adobe/CameraRaw/CameraProfiles/Camera"
    end
    if fso:existsAsDir( pgmData ) then
        local dir = LrPathUtils.child( pgmData, model )
        if fso:existsAsDir( dir ) then
            getSome( dir, true )
        else
            Debug.pause( dir )
            app:logW( "Unable to obtain standard camera profiles for '^1' - '^2' does not exist.", model, dir )
        end        
    else
        Debug.pause( pgmData )
        app:logW( "Unable to obtain standard camera profiles for '^1' - '^2' does not exist.", model, pgmData )
    end
    local dir = LrPathUtils.getStandardFilePath( 'appData' ) or error( "no app-data dir" ) -- Lr app-data that is.
    dir = LrPathUtils.parent( dir ) -- Adobe app data.
    if fso:existsAsDir( dir ) then
        dir = LrPathUtils.child( dir, "CameraRaw" )
        if fso:existsAsDir( dir ) then
            dir = LrPathUtils.child( dir, "CameraProfiles" )
            if fso:existsAsDir( dir ) then
                dir = LrPathUtils.child( dir, model )
                if fso:existsAsDir( dir ) then
                    getSome( dir )
                else
                    app:logV( "Camera profiles do not exist for '^1' - '^2' does not exist.", model, dir )
                end
            else
                app:error( "Camera profiles dir does not exist: ^1", dir )
            end
        else
            app:error( "Camera raw dir does not exist: ^1", dir )
        end
    else
        app:error( "Adobe app-data dir does not exist: ^1", dir )
    end
    return profiles
end



--- Save preset, in both dirs if possible - w/catalog and common/shared.
--
--  @param presetSubdir (string, required) e.g. 'Export Actions'
--  @param presetName (string, required) base name, will have .lrtemplate appended.
--  @param textValue (string, required) preset value in text form.
--  @param suppressExtension (boolean, default=false) set true to not append .lrtemplate.
--  @param forceUpdate (boolean, default=false) set true to to force update (copy even if already existing).
--
--  @return comStatus - true iff saved in common location.
--  @return catStatus - true iff saved with catalog.
--  @return message - qualifying message, will be non-empty string unless both statuses are true.
--
function Lightroom:assurePreset( presetSubdir, presetName, textValue, suppressExtension, forceUpdate )
    local catStatus, comStatus, catMessage, comMessage
    local comDir = LrPathUtils.child( LrPathUtils.getStandardFilePath( 'appData' ), presetSubdir ) -- common/shared "Lightroom" (Settings) folder.
    local filename
    if suppressExtension then
        filename = presetName
    else
        filename = LrPathUtils.addExtension( presetName, "lrtemplate" )
    end
    if fso:existsAsDir( comDir ) then -- should always be there I think.
        local file = LrPathUtils.child( comDir, filename )
        local fileExists = fso:existsAsFile( file )
        if fileExists then
            app:logV( "Already exists: ^1", file )
        else
            app:logV( "Does not already exist: ^1", file )
        end
        if fileExists and not forceUpdate then
            comStatus = true
        else
            comStatus, comMessage = fso:writeFile( file, textValue ) 
            if comStatus then
                app:logV( "Wrote: ^1", file )
            end
        end
    else
        comStatus, comMessage = false, str:fmtx( "Where's the common/shared presets sub-directory? - not here: '^1' - unable to create preset: '^2'", comDir, presetName )
    end
    local catDir = cat:getCatDir() -- ignore 2nd return value.
    catDir = LrPathUtils.child( catDir, "Lightroom Settings" ) -- w/catalog.
    catDir = LrPathUtils.child( catDir, presetSubdir ) -- w/catalog.
    if fso:existsAsDir( catDir ) then
        local file = LrPathUtils.child( catDir, filename )
        local fileExists = fso:existsAsFile( file )
        if fileExists then
            app:logV( "Already exists: ^1", file )
        else
            app:logV( "Does not already exist: ^1", file )
        end
        if fileExists and not forceUpdate then
            catStatus = true
        else
            catStatus, catMessage = fso:writeFile( file, textValue ) 
            if comStatus then
                app:logV( "Wrote: ^1", file )
            end
        end
    else
        catStatus, catMessage = false, str:fmtx( "There were no presets found with catalog here: '^1' - unable to create preset: '^2'", catDir, presetName )
    end
    local message = comMessage or catMessage or nil
    return comStatus, catStatus, message
end


   
return Lightroom 