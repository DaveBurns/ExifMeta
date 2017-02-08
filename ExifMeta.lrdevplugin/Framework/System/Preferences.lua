--[[
        Preferences.lua
        
        Supports named preference sets that may or may not be supplemented by a preference config file.
--]]

local Preferences, dbg, dbgf = Object:newClass{ className = 'Preferences' }



--- Constructor for extending class.
--
function Preferences:newClass( t )
    return Object.newClass( self, t )
end



--- Constructs a new preference manager.
--      
--  <p>Installation procedure is going to have to be smart enough to deal with pre-existing directory upgrade.</p>
--
--  <p>This object manages named preference sets. Exclude and you just have the reglar set of unnamed (un-prefixed) prefs...</p>
--
--  <p>Param Table In:<blockquote>
--          - name(id): set name. if missing, then default set.<br>
--          - file-essential boolean.</blockquote></p>
--                          
--  <p>Object Table Out:<blockquote>
--          - friendlyName: same as name/id except for default.<br>
--          - file (path)<br>
--          - prefs (name-val table)</blockquote></p>
--      
--  @param      t       input parameter table.
--
--  @usage              Subdirectory for supplemental files is 'Preferences' in plugin directory.
--  @usage              See app class pref methods for more info.
--
--  @return             Preference manager object.
--
function Preferences:new( t )

    local o = Object.new( self, t )

    o.prefLoadingGate = Gate:new{ max=100 } -- e.g. max simultaneous async services trying to load/assure..      
    
    o.filePrefs = nil -- return table read from preference backing file.
    o.prefDir = LrPathUtils.child( _PLUGIN.path, 'Preferences' )
    o.backing = false
    o.loadDates = {}
    if LrFileUtils.exists( o.prefDir ) then
        o.dfltFile = LrPathUtils.child( o.prefDir, 'Default.lua' )
        o.backing = fso:existsAsFile( o.dfltFile ) -- deleting default file is disallowed.
        if not o.backing then
            o.dfltFile = LrPathUtils.replaceExtension( o.dfltFile, 'txt' )
            o.backing = fso:existsAsFile( o.dfltFile ) -- deleting default file is disallowed.
        end
        if o.backing then
            dbg( "prefs are backed in legacy fashion" )
        else
            dbg( "no legacy backing for prefs" )
        end
    end
    o.setsDir = LrPathUtils.child( _PLUGIN.path, 'Settings' )
    o.setsBacking = false
    if LrFileUtils.exists( o.setsDir ) then
        o.dfltSetsFile = LrPathUtils.child( o.setsDir, 'Default.lua' )
        o.setsBacking = fso:existsAsFile( o.dfltSetsFile ) -- deleting default file is disallowed.
        if not o.setsBacking then
            o.dfltSetsFile = LrPathUtils.replaceExtension( o.dfltSetsFile, 'txt' )
            o.setsBacking = fso:existsAsFile( o.dfltSetsFile ) -- deleting default file is disallowed.
        end
        if o.setsBacking then
            dbg( "additional settings (default) \"backing\" file has been discovered." )
        else
            dbg( "no default backing file for additional settings" )
        end
    elseif o.backing then
        dbgf( "prefs are not backed by new-style settings..." )
    else
        dbgf( "prefs are not backed no-how..." )
    end        
    o.dfltProps = {}
    o.glblDfltProps = {}
    o.presetCache = {}
    o:registerPreset( 'Default', 1 )
    return o
end        


-- Private Preset class for external use (via object methods):

local Preset = Object:newClass{ className="PreferencePreset", register=false }

-- no need for new class method, since no way to create preset objects externally.
function Preset:new( t )
    local o = Object.new( self, t )
    assert( str:is( o.name ), "new preset needs name" )
    return o
end


--function Preset:isBacked()
--    return preset.backingData
--end


function Preset:getPref( prefName )
    --assert( str:is( self.name ), "preset object needs name" )
    --Debug.pause( self.name )
    local prefValue = app.prefMgr:getPref( prefName, self.name ) -- a little round-a-bout.
    if prefValue ~= nil then
        return prefValue
    elseif self.backingData then
        return self.backingData[prefName]
    --elseif self.setsBackingData then - ###1
    --    return self.setsBackingData[prefName]
    else
        return nil
    end
end


--- Save pref in backing file.
--
--  @usage Note: this is different than the pref-mgr version, since it's intended to set persistent prefs in backing file.<br>
--         If that's not what you want, then use the preference manager version, which is intended to set prefs in lr-prefs, thus masking the value in the backing file.
--
--  @return status - t/f
--  @return message - errm.
--
function Preset:savePrefInBackingFile( prefName, prefValue )
    local temp = app.prefMgr:getPref( prefName, self.name )
    if self.backingData then
        if prefValue ~= self.backingData[prefName] then
            self.backingData[prefName] = prefValue
            local t = "return {\n" .. luaText:serialize( self.backingData ) .. "\n}\n" -- -- Note: this will cause loss of all comments.
            local s, m = fso:writeFile( self.backingFile, t ) 
            if s then
                -- golden
                app.prefMgr:setGlobalPref( 'prefSupportFileLoaded', not app.prefMgr:getGlobalPref( 'prefSupportFileLoaded' ) ) -- toggle.
                return true
            else
                -- app:logErr( "No could write pref file, so no persistence, errm: ^1", m )
                return false, m
            end    
        else
            -- value already set.
            return true -- from outside, already set is same as newly set.
        end
    else
        -- app:logErr( "No backing file for saving pref." )
        return false, "No backing file."
    end
end



--- Get "advanced settings" file path corresponding to specified preset, whether it exists (yet) or not.
--
--  @usage may have txt or lua extension - if txt file exists, path will be to it (even if lua file also exists), otherwise path will have lua extension.
--
--  @param presetName (string, default="current preset")
--
--  @return path
--  @return actualPresetName (non-nil, not empty).
--
function Preferences:getPresetBackingFile( presetName )
    presetName = presetName or self:getPresetName()
    local backingFile = LrPathUtils.child( self.prefDir, LrPathUtils.addExtension( presetName, "txt" ) )
    if not fso:existsAsFile( backingFile ) then
        backingFile = LrPathUtils.replaceExtension( backingFile, "lua" )
    end
    return backingFile, presetName
end



--- Get object that represents settings associated with specified preset.
--
--  @param presetName   preset name.
--  @param reload       reload backing file.
--
--  @usage will create preset if not already existing (registered), but note: the preset created is a special preset - really for behind the scene use (i.e. advanced settings only),<br>
--         it won't be registered - it's created without associated initialized props...
--
function Preferences:getPreset( presetName, reload )
    local preset = self.presetCache[presetName]
    if preset == nil then
        preset = Preset:new{ name=presetName }
        self.presetCache[presetName] = preset
        -- fall-through to load backing file.
    elseif not reload then
        return preset
    end
    preset.backingFile = LrPathUtils.child( self.prefDir, LrPathUtils.addExtension( presetName, "txt" ) )
    if not fso:existsAsFile( preset.backingFile ) then
        preset.backingFile = LrPathUtils.replaceExtension( preset.backingFile, "lua" )
    end
    if fso:existsAsFile( preset.backingFile ) then
        local status, other = pcall( dofile, preset.backingFile )
        if status then
            app:logVerbose( "Got preset '^1', backed by file: ^2", presetName, preset.backingFile )
            preset.backingData = other
            self:setGlobalPref( 'prefSupportFileLoaded', not self:getGlobalPref( 'prefSupportFileLoaded' ) ) -- toggle.
            return preset
        else
            app:logErr( "Preference preset ^1 backing file (^2) has an error, and so no values defined in backing file will be in effect, error message: ^3", presetName, preset.backingFile, str:to( other ) )
            return nil -- check for this.
        end
    end
    --[[ ###1
    preset.setsBackingFile = LrPathUtils.child( self.setsDir, LrPathUtils.addExtension( presetName, "txt" ) )
    if not fso:existsAsFile( preset.setsBackingFile ) then
        preset.setsBackingFile = LrPathUtils.replaceExtension( preset.setsBackingFile, "lua" )
    end
    if fso:existsAsFile( preset.setsBackingFile ) then
        local status, other = pcall( dofile, preset.setsBackingFile )
        if status then
            app:logVerbose( "Got preset '^1', backed by file: ^2", presetName, preset.setsBackingFile )
            preset.setsBackingData = other
            self:setGlobalPref( 'settingsSupportFileLoaded', not self:getGlobalPref( 'settingsSupportFileLoaded' ) ) -- toggle.
            --return preset
        else
            app:logErr( "Preference preset ^1 backing file (^2) has an error, and so no values defined in backing file will be in effect, error message: ^3", presetName, preset.setsBackingFile, str:to( other ) )
            return nil -- check for this.
        end
    end
    --]]
    return preset
end



--  determine if explicitly specified preset (non-defaulting) is in the preset cache.
function Preferences:_isCached( presetName )
    return self.presetCache[presetName]
end



--- Create a new named set, and load properties with initial values.
--
--  #param props (property table, required) properties to receive initial values for preset.
function Preferences:createPreset( props, presetName )
    presetName = presetName or self:getPresetName()
    if presetName == 'Default' then
        error( "Unable to create default preset - calling context should check for default preset name before calling create-preset." )
    end
    local function createBacker( soBacked, backingDir, dfltFile )
        if not soBacked then
            return
        end
        local file = LrPathUtils.child( backingDir, presetName .. ".lua" )
        if not fso:existsAsFile( file ) then
            file = LrPathUtils.replaceExtension( file, "txt" )
        end
        if not fso:existsAsFile( file ) then -- backing file is absent.
            if fso:existsAsFile( dfltFile ) then
                local s,m = fso:copyFile( dfltFile, file )
                if s then
                    self:loadPrefFile( file, presetName ) -- throws error if probs.
                    local answer = app:show{ confirm="Preference support file created for ^1 - edit now?",
                        subs = presetName,
                        buttons = { dia:btn( "Yes", 'ok' ), dia:btn( "No", 'cancel' ) },
                        -- presently no action-pref-key user must acknowlege / consider...
                    }
                        
                    if answer == 'ok' then
                        app:openFileInDefaultApp( file, true )
                    --else
                    end
                else
                    error( m )
                end
            else
                app:show{ error="Default preference file is missing: ^1", dfltFile }
            end
        else
            self:loadPrefFile( file, presetName ) -- throws error if probs.
            local answer = app:show{ info="^1 settings are backed by lua preference file: ^2 - edit now?",
                subs={ presetName, file },
                buttons={ dia:btn( "Edit Now", 'ok' ), dia:btn( "Not Now", 'cancel' ) },
                actionPrefKey="Edit advanced settings" }
            if answer == 'ok' then
                app:openFileInDefaultApp( file, true )
            elseif answer == 'cancel' then
                -- could conceivably make this memorable, but I think its good to have a reminder if backing is supported by this plugin - its not like
                -- the user will be creating presets every day...
            else
                error( "bad answer" )
            end
        end
    end
    -- typically a plugin should have one backer type or the other, and not both - but not expressly prohibited to have both.
    createBacker( self.backing, self.prefDir, self.dfltFile )
    createBacker( self.setsBacking, self.setsDir, self.dfltSetsFile )
    self:registerPreset( presetName )
    self:loadDefaults( props, presetName ) -- props ignored if nil, prefs still loaded.
    app:yieldIfPossible() -- allow change detector to run before next thing assumes...
end



function Preferences:renamePreset( _propsIgnored, oldName, newName )
    if oldName == 'Default' then
        error( "Unable to rename default preset - calling context should check for default preset name before calling rename-preset." )
    end
    local function renameBacker( soBacked, backingDir )
        if not soBacked then
            return
        end
        local oldFile = LrPathUtils.child( backingDir, oldName .. ".lua" )
        if not fso:existsAsFile( oldFile ) then
            oldFile = LrPathUtils.replaceExtension( oldFile, "txt" )
            if not fso:existsAsFile( oldFile ) then
                oldFile = LrPathUtils.child( backingDir, "Default.lua" )
                if not fso:existsAsFile( oldFile ) then
                    oldFile = LrPathUtils.child( backingDir, "Default.txt" )
                end
            end
        end
        local newFile = LrPathUtils.child( backingDir, newName .. ".lua" )
        if not fso:existsAsFile( newFile ) then
            newFile = LrPathUtils.replaceExtension( newFile, "txt" )
        end
        app:logv( "Considering renaming preset backing file from '^1' to '^2'", oldFile, newFile ) 
        if str:isEqualIgnoringCase( oldFile, newFile ) then
            app:logv( "backer has same name ignoring case, and shan't be renamed." )
            return
        end
        if fso:existsAsFile( oldFile ) then
            if fso:existsAsFile( newFile ) then
                local button = app:show{ confirm="OK to overwrite '^1'?", newFile }
                if button ~= 'ok' then
                    app:error( "Not OK to overwrite '^1'", newFile )
                end
                LrFileUtils.delete( newFile )
            end
            -- moveFile( sourcePath, destPath, createDestDirsIfNecessary, overwriteDestFileIfNecessary, avoidUnnecessaryUpdate, timeCheckIsEnough )
            local s,m = fso:moveFile( oldFile, newFile, false, true, false, nil )
            if s then
                self:loadPrefFile( newFile, newName ) -- throws error if probs.
                local answer = app:show{ confirm="Preference support file created for ^1 - edit now?",
                    subs = newName,
                    buttons = { dia:btn( "Yes", 'ok' ), dia:btn( "No", 'cancel' ) },
                    -- presently no action-pref-key user must acknowlege / consider...
                }
                if answer == 'ok' then
                    app:openFileInDefaultApp( newFile, true )
                --else
                end
            else
                error( m )
            end
        else
            app:error( "Unable to locate backing file for '^1' in '^2'", oldName, backingDir )
        end
    end
    -- typically a plugin should have one backer type or the other, and not both - but not expressly prohibited to have both.
    renameBacker( self.backing, self.prefDir, self.dfltFile )
    renameBacker( self.setsBacking, self.setsDir, self.dfltSetsFile )
    self:_movePrefs( oldName, newName )
    local oldIndex = self:_unregisterPreset( oldName )
    self:registerPreset( newName, oldIndex )
    -- self:loadDefaults( props, presetName )
    app:yieldIfPossible() -- allow change detector to run before next thing assumes...
end



function Preferences:duplicatePreset( _propsIgnored, oldName, newName )
    if newName == 'Default' then
        error( "Unable to duplicate to default preset - calling context should check for default preset name before calling duplicate-preset." )
    end
    if str:isEqualIgnoringCase( newName, oldName ) then
        error( "Unable to duplicate to same named preset - calling context should check preset names before calling duplicate-preset." )
    end
    local function duplicateBacker( soBacked, backingDir )
        if not soBacked then
            return true
        end
        local oldFile = LrPathUtils.child( backingDir, oldName .. ".lua" )
        if not fso:existsAsFile( oldFile ) then
            oldFile = LrPathUtils.replaceExtension( oldFile, "txt" )
            if not fso:existsAsFile( oldFile ) then
                oldFile = LrPathUtils.child( backingDir, "Default.lua" )
                if not fso:existsAsFile( oldFile ) then
                    oldFile = LrPathUtils.child( backingDir, "Default.txt" )
                end
            end
        end
        local newFile = LrPathUtils.child( backingDir, newName .. ".lua" )
        if not fso:existsAsFile( newFile ) then
            newFile = LrPathUtils.replaceExtension( newFile, "txt" )
        end
        app:logv( "Considering duplication of preset backing file from '^1' to '^2'", oldFile, newFile ) 
        assert( not str:isEqualIgnoringCase( oldFile, newFile ), "pgm fail" )
        if fso:existsAsFile( oldFile ) then
            local overwrite = false
            if fso:existsAsFile( newFile ) then
                local button = app:show{ confirm="OK to overwrite '^1'?",
                    subs = newFile,
                    buttons = { dia:btn( "Yes (do overwrite)", 'ok' ), dia:btn( "No (adopt existing)", 'other' ) },
                }
                if button == 'ok' then
                    overwrite = true
                elseif button == 'other' then
                    local button = app:show{ confirm="Are you sure file format and content is compatible?",
                        buttons = { dia:btn( "Yes", 'ok' ), dia:btn( "No", 'cancel' ) },
                    }
                    if button=='ok' then
                        app:log( "*** Adopting '^1' instead of overwriting - hopefully file format is compatible - consider checking if unsure.", newFile )
                        return true
                    else
                        app:error( "Unable to complete preset duplication due to unresolvable backing file conflict: ^1", newFile )
                    end
                else
                    app:error( "Preset duplication canceled due to backing file uncertainty: ^1", newFile )
                end
            -- else not already existing.
            end
            -- copyFile( sourcePath, destPath, createDestDirsIfNecessary, overwriteDestFileIfNecessary, avoidUnnecessaryUpdate, timeCheckIsEnough )
            local s, m = fso:copyFile( oldFile, newFile, false, overwrite, false, nil )
            if s then
                self:loadPrefFile( newFile, newName ) -- throws error if probs.
                local answer = app:show{ confirm="Preference support file created for ^1 - edit now?",
                    subs = newName,
                    buttons = { dia:btn( "Yes", 'ok' ), dia:btn( "No", 'cancel' ) },
                    -- presently no action-pref-key user must acknowlege / consider...
                }
                if answer == 'ok' then
                    app:openFileInDefaultApp( newFile, true )
                --else
                end
            else
                error( m )
            end
        else
            app:error( "Unable to locate backing file for '^1' in '^2'", oldName, backingDir )
        end
        return true
    end
    -- typically a plugin should have one backer type or the other, and not both - but not expressly prohibited to have both.
    local sts = duplicateBacker( self.backing, self.prefDir, self.dfltFile )
    sts = sts or duplicateBacker( self.setsBacking, self.setsDir, self.dfltSetsFile )
    if sts then
        self:_copyPrefs( oldName, newName )
        self:registerPreset( newName ) -- no index specified.
        -- self:loadDefaults( props, presetName )
        app:yieldIfPossible() -- allow change detector to run before next thing assumes...
    end
end



--- Get preference preset name.
--
--  @param friendly (return "Un-named" instead of 'Default')
--
--  @return name if not nil, else 'Default'.
--
function Preferences:getPresetName()
    local presetName
    if prefs._global_presetName ~= nil then
        if type( prefs._global_presetName ) == 'string' then
            presetName = LrStringUtils.trimWhitespace( prefs._global_presetName ) -- I would have expected UI to trim but it does not.
        else
            Debug.pause( prefs._global_presetName )
        end
    end
    if not str:is( presetName ) then
        prefs._global_presetName = 'Default' -- a little side effect, he-he: initializing global preset name when getting, if not init.
        return 'Default'
    else
        return presetName
    end
end



--- Switch to named or unamed preference set.
--
--  @usage @13/Nov/2013 6:14 this is not (always) called from async task (but probably should be ###2). 
--
function Preferences:switchPreset( props, presetName )
    presetName = presetName or self:getPresetName()
    local function switchBacker( soBacked, backingDir, dfltFile )
        if not soBacked then
            return
        end
        local file
        file = LrPathUtils.child( backingDir, presetName .. ".lua" )
        if not fso:existsAsFile( file ) then
            file = LrPathUtils.replaceExtension( file, "txt" )
        end
        if not fso:existsAsFile( file ) then -- backing file is absent - note: we are switching to an already existing set,
            -- so if backing is supported, the file should be there.
            if presetName == 'Default' then
                error( 'Default preference support file has disappeared: ' .. str:to( dfltFile ) )
            end
            if dia:isYes( str:format( "Preference file supporting '^1' settings does not exist:\n \n^2\n \nCreate a new one? (will be a copy of the default)", presetName, file ) ) then
                if fso:existsAsFile( dfltFile ) then
                    local s,m = fso:copyFile( dfltFile, file )
                    if s then
                        local status, message = pcall( self.loadPrefFile, self, file, presetName ) -- added preset name 13/Nov/2013 5:51 ###4
                        if status then
                            if dia:isYes( "Preferences support file created anew - edit now?" ) then
                                app:openFileInDefaultApp( file, true )
                            --else its user's responsibility to edit later, or not.
                            end
                        else
                            dialog:messageWithOptions( { error="Unable to load advanced settings from preference backing file, error message: ^1" }, message )
                        end
                    else
                        error( m ) -- not sure how this is being handled. ###4
                    end
                else
                    app:show{ error="Default preference file is missing: ^1", dfltFile }
                end
            else
                app:logWarning( "Best find that file (" .. file .. "), since preference support file is required for this plugin." )
            end
        else
            local status, message = pcall( self.loadPrefFile, self, file, presetName ) -- load props used to do this | added preset name 13/Nov/2013 5:51 ###4
            if status then
                app:logInfo( str:format( "Switched to pref set ^1 backed by ^2", presetName, file ) )
            else
                dialog:messageWithOptions( { error="Unable to load advanced settings from preference backing file, error message: ^1" }, message )
            end
        end
    end
    switchBacker( self.backing, self.prefDir, self.dfltFile )
    switchBacker( self.setsBacking, self.setsDir, self.dfltSetsFile )
    if props then
        dbg("loading props for", presetName )
        self:loadProps( props )
    end
end



--- Determine if preference or settings file backing is supported by this plugin.
--
function Preferences:isBackedByFile()
    return self.backing or self.setsBacking
end



-- Determine if preference file backing is supported by this plugin.
--[[ *** not required, yet.
function Preferences:isPrefBackedByFile()
    return self.backing
end
--]]



--- Gets path to existing preference support file.
--
--  @usage if not existing, returns nil & errm.
--
--  @return full path (or nil if not existing).
--  @return filename (or errm if not existing).
--
function Preferences:getPrefSupportFile( presetName, backingDir )
    presetName = presetName or self:getPresetName()
    backingDir = backingDir or self.prefDir
    local name = presetName .. ".lua"
    local file = LrPathUtils.child( backingDir, name )
    local name2 = presetName .. ".txt"
    local file2 = LrPathUtils.child( backingDir, name2 )
    local fileExists = fso:existsAsFile( file )
    local file2Exists = fso:existsAsFile( file2 )
    if fileExists and file2Exists then
        error( "backer exists with multiple extensions - ambiguous..." )
    end
    if fileExists then
        return file, name
    elseif file2Exists then
        return file2, name2
    else
        return nil, str:fmtx( "file does not exist corresponding to '^1'", presetName )
    end
end



--- Gets path to preference support file.
--
--  @usage the only difference between this and get-pref-support-file is the default backing dir ('Settings' instead of 'Preferences')
--
--  @return full path
--  @return filename
--
function Preferences:getSettingsSupportFile( presetName, backingDir )
    presetName = presetName or self:getPresetName()
    backingDir = backingDir or self.setsDir
    local name = presetName .. ".lua"
    local file = LrPathUtils.child( backingDir, name )
    local name2 = presetName .. ".txt"
    local file2 = LrPathUtils.child( backingDir, name2 )
    local fileExists = fso:existsAsFile( file )
    local file2Exists = fso:existsAsFile( file2 )
    if fileExists and file2Exists then
        error( "backer exists with multiple extensions - ambiguous..." )
    end
    if fileExists then
        return file, name
    elseif file2Exists then
        return file2, name2
    else
        return nil, str:fmtx( "file does not exist corresponding to '^1'", presetName )
    end
end



--- Unconditionally loads ONE preference "backing" file (either legacy or new settings), and saves load-date for conditional loading support.
--
--  <p>Preferences not in lr-pref table, are looked for in preference backing file, if available.</p>
--
--  @param file     The path to the file.
--
--  @usage          Auto-detects (based on parent folder of file) whether loading legacy pref backer or new sets backer and handles appropriately.
--  @usage          Up until 5/Aug/2011 this used to log errors instead of throwing them - not good enough (errors in backers not being detected).<br>
--                  Now calling context must take care to handle thrown errors to handle more gracefully if necessary.
--
function Preferences:loadPrefFile( file, presetName )

    -- Note: @13/Nov/2013 6:07, this function is NOT always called from task, so can't be gated.. - ###2 probably should be.

    local dir = LrPathUtils.parent( file )
    local filePrefs = ( dir == self.prefDir )
        
    if filePrefs then
        self.filePrefs = nil
    else
        app:assert( dir == self.setsDir, "bad dir: ^1, self.setsDir: ^2, file: ^3, presetName: ^4", dir, self.setsDir, file, presetName )
    end
    
    local status, prefTbl = pcall( dofile, file )
    if status then
        if prefTbl then
            if type( prefTbl ) == 'table' then
                if filePrefs then
                    -- @13/Nov/2013 3:26, I'm wondering why not load the file time here, instead of in calling contexts. ###2
                    -- the thing is, I'm pretty sure I thought about it before, and rejected the idea, although now I can't imagine/remember why.
                    app:logv( "Loaded preference backing file: " .. file )
                    self.filePrefs = prefTbl
                    -- added 20/May/2013 6:48: (fixes problem with cached presets not seeing backing file changes, even if explicitly reloaded (plugin reload required).
                    local preset = self.presetCache[presetName]
                    if preset then
                        preset.backingData = prefTbl
                    end
                    if presetName ~= nil then
                        local baseName = LrPathUtils.removeExtension( LrPathUtils.leafName( file ) )
                        if baseName == presetName then -- if both are same, then safe bet to record loaded file date for preset.
                            self.loadDates[presetName] = LrFileUtils.fileAttributes( file ).fileModificationDate
                        else
                            Debug.pause( "preset name is not base name", baseName, presetName )
                        end
                    else
                        Debug.pause( "No preset name" )
                    end
                    self:setGlobalPref( 'prefSupportFileLoaded', not self:getGlobalPref( 'prefSupportFileLoaded' ) ) -- toggle.
                    -------------------------
                else
                    app:logv( "Loaded settings backer file: " .. file )
                    local name = LrPathUtils.removeExtension( LrPathUtils.leafName( file ) ) -- could be more optimized ###2.
                    local key = app:getSettingsKey ( name )
                    systemSettings:initAndRegister( key, prefTbl )
                    self.loadDates[key] = LrFileUtils.fileAttributes( file ).fileModificationDate
                    self:setGlobalPref( 'settingsSupportFileLoaded', not self:getGlobalPref( 'settingsSupportFileLoaded' ) ) -- toggle.
                    -------------------------
                end
            else
                error( "Preference backing file must return a table, not a " .. type( prefTbl ) ) -- error log changed to error thrown 5/Aug/2011 2:47
            end
        else
            error( "Preference backing file must return a table" ) -- -- error log changed to error thrown 5/Aug/2011 2:47
        end        
    else
        error( "Unable to load pref support file from '" .. file .. "', more: " .. str:to( prefTbl ) ) -- error log changed to error thrown 5/Aug/2011 2:47
    end
end



--- Load or re-load preference support file (returns nothing - throws error if problems).
--
function Preferences:loadPrefSupportFile( presetName )
    local s, m = app:pcall{ name="Load Pref Support File", main=function( call )
        self.prefLoadingGate:enter()
        presetName = presetName or self:getPresetName()
        local function loadBacker( dir, getter, expected )
            local file, name = getter( self, presetName, dir ) -- name is filename.
            if file then
                if fso:existsAsFile( file ) then
                    Debug.pauseIf( LrPathUtils.removeExtension( name ) ~= presetName, "names not same", presetName, name )
                    self:loadPrefFile( file, presetName ) -- load legacy pref backer, or init-n-reg settings; throws error if problems.
                else
                    app:error( "pref support file missing: ^1", file )
                end
            elseif expected then
                app:error( "no pref support file for ^1", name )
            end
        end
        loadBacker( self.prefDir, self.getPrefSupportFile, self.backing )
        loadBacker( self.setsDir, self.getSettingsSupportFile, self.setsBacking )
    end, finale=function( call )
        self.prefLoadingGate:exit()
    end }
    if not s then
        error( m )
    end
end



--- Load or re-load preference support file, if it's changed since last loaded (returns nothing - throws error if problems).
--
function Preferences:assurePrefSupportFile( presetName )
    if not self.backing and not self.setsBacking then return end -- without one or the other, 'tain't much point..
    local s, m = app:pcall{ name="Assure Pref Support File", async=false, guard=App.guardNot, main=function( call ) -- Note: calling context must be async, and guarded using wait-gate instead of rejection.
        app:callingAssert( LrTasks.canYield(), "call from (async) task" )
        self.prefLoadingGate:enter()
        presetName = presetName or self:getPresetName()
        local function assureBacker( dir, getter, expect )
            local file, name = getter( self, presetName, dir ) -- name is filename here, with extension, or errm.
            if file then
                Debug.pauseIf( LrPathUtils.removeExtension( name ) ~= presetName, str:fmtx( "names not same, preset-name: ^1, reglar name: ^2", presetName, name ) )
                if fso:existsAsFile( file ) then -- file existence must be pre-checked.
                    local prev
                    local tidbit
                    if dir == self.prefDir then
                        prev = self.loadDates[presetName]
                        tidbit = "(legacy) pref"
                    else
                        local key = app:getSettingsKey( presetName )
                        prev = self.loadDates[key]
                        tidbit = "settings"
                    end
                    local changed, when = fso:isChangedSince( file, prev ) -- date can be nil.
                    if changed then
                        self:loadPrefFile( file, presetName ) -- throws error if problems - logs verbosely about loaded file.
                        if prev ~= nil then
                            local diff = ( when - prev )
                            -- app:logV( "^1 backing file changed, was '^2', now '^3'.", presetName, LrDate.timeToUserFormat( prev, "%Y-%m-%d %H:%M:%S" ), LrDate.timeToUserFormat( when, "%Y-%m-%d %H:%M:%S" ) )
                            app:logV( "^1 ^5 backing file changed, was '^2', now '^3', diff: ^4.", presetName, prev, when, diff, tidbit ) -- ###4 could format times I spose - this not happening so much since tweak to record load date in load-pref-file method.
                        else
                            app:logV( "^1 ^3 backing file changed, not recorded before, now '^2'.", presetName, when, tidbit )
                        end
                    else -- not changed
                        if prev then -- should always be prev if hasn't changed
                            local diff = when - prev
                            if diff == 0 then
                                app:logV( "No ^3 backing file change '^1', file-time: ^2.", presetName, prev, tidbit )
                            else
                                app:logV( "No ^5 backing file change '^1', recorded: ^2, new file date: ^3, diff: ^4.", presetName, prev, when, diff, tidbit )
                            end
                        else
                            Debug.pause( "no prev" )
                        end
                    end
                else
                    app:error( "pref support file missing: ^1", file )
                end
            elseif expect then
                app:error( "no pref support file for ^1 - ^2", presetName, name )
            end
        end
        assureBacker( self.prefDir, self.getPrefSupportFile, self.backing ) -- will assure it, even if not expected, but only an error doing so if expected.
        assureBacker( self.setsDir, self.getSettingsSupportFile, self.setsBacking ) -- ditto.
    end, finale=function( call )
        self.prefLoadingGate:exit()
    end }
    if not s then
        error( m )
    end
end



--  Translates a simple property name to its equivalent name-prefixed pref key,
--      
--  <p>If active name is null, then prop-name is pref-key - assures compatibility with no-preference module configuration.</p>
--
--  @param propName (string, required) name of preference.
--  @param presetName (string, default = current preset) name of preset.
--
--  @usage      Reminder: not public.
--
--  @return     key for pref index.
--
function Preferences:_getPrefKey( propName, presetName )
    presetName = presetName or self:getPresetName()
    return presetName .. '__' .. propName
end



--- Get global preference value.
--
--  @usage key is name prefixed by _global_ in the interest of keeping a clear separation,
--  <br>between managed preference globals and unmanaged, and also preset preferences.
--
--  @return the value - may be nil.
--
function Preferences:getGlobalPref( name )
    return prefs['_global_'..name]
end



--- Get actual preference key corresponding to managed global preference name.
--
--  @return key suitable for binding.
--
function Preferences:getGlobalKey( name )
    return '_global_' .. name
end



--- Set global preference value.
--
--  @param name (string, required) name of pref (actual key is a derivation).
--  @param val (any non-table value, default nil) simple value for pref, nil to clear.
--
--  @usage key is name prefixed by _global_ in the interest of keeping a clear separation,
--  <br>between managed preference globals and unmanaged, and also preset preferences.
--
function Preferences:setGlobalPref( name, val )
    if name == nil then
        return -- hopefully only happens when *all* prefs have been cleared.
    end
    prefs['_global_'..name] = val
end



--- Sets global preference based on property name.
--      
--  <p>Named or unamed.</p>
--
--  @param name (string, required) preference name.
--  @param value (any simple type, required) preference value.
--  @param presetName (string, default = current preset) preset name.
--
--  @usage      like all preference methods, this method is wrapped by app object - see App class for more info.
--
function Preferences:setPref( name, value, presetName )
    presetName = presetName or self:getPresetName()
    local key = self:_getPrefKey( name, presetName )
    if prefs[name] then
        dbg( "property being set to prefs already exists without prefix: ", name )
    end
    prefs[key] = value
end



--- Sets preference based on property name.
--      
--  <p>Named or unamed.</p>
--  <p>Is should not be necessary to init props to match here, provided props are loaded from prefs afterward.</p>
--      
--  @param name (string, required) preference name.
--  @param dflt (any simple type, required) preference default value.
--  @param presetName (string, default = current preset) preset name.
--  @param values (array, optional) initial "pointer" values for table prefs, in case not only value is important, but pointer to value is too (e.g. popup).
--
--  @usage      Like all preference methods, this method is wrapped by app object - see App class for more info.
--
function Preferences:initPref( name, dflt, presetName, values )
    local key = self:_getPrefKey( name, presetName )
    if prefs[key] == nil then
        prefs[key] = dflt -- so pref is not nil.
    elseif values then -- value saved needs to be linked to pointer to equivalent value in context env.
        local v = prefs[key]
        for i, v2 in ipairs( values ) do
            local value
            if v2.value then
                value = v2.value
            else
                value = v2
            end
            if tab:isEquivalent( v, value ) then
                prefs[key] = value
                v = nil
                break
            end
        end
        if v ~= nil then -- value not found
            prefs[key] = dflt
        end
    end
    if presetName == 'Default' then
        self.dfltProps[name] = dflt
    end
    if presetName == nil then
        self:initPref( name, dflt, 'Default', values ) -- and vice versa.
    end
end



--- Initialize global preference value.
--      
--  @usage      Like all preference methods, this method is wrapped by app object - see App class for more info.
--
function Preferences:initGlobalPref( name, dflt )
    local key = self:getGlobalKey( name )
    if prefs[key] == nil then
        prefs[key] = dflt
    end
    self.glblDfltProps[key] = dflt
end



--- Gets pref value corresponding to prop name.
--      
--  <p>Named or unamed.</p>
--
--  @param name (string, required) preference name.
--  @param presetName (string, default = current preset) preset name.
--
--  @usage      Like all preference methods, this method is wrapped by app object - see App class for more info.
--
function Preferences:getPref( propName, presetName )
    local prefKey = self:_getPrefKey( propName, presetName )
    local value = prefs[prefKey]
    if value ~= nil then
        --dbg( "got value from prefs for prop named", propName, "value", value )
        return value
    end
    if not str:is( presetName ) or presetName == 'Default' then
        if self.filePrefs then -- file backed value.
            value = self.filePrefs[propName]
            --dbg( "value from backer for prop named", propName, "is", value )
        else
            --dbg( "no backer for prop named", propName )
        end
    else
        local preset = self:getPreset( presetName ) -- @9/Oct/2012 22:19, this will create an uninitialized preset and put it in the cache,
        -- but not register it. I guess the purpose of such is for the case when preset is specified for which there is backing file, but preset
        -- may not exist/be-registered-in plugin manager. I don't remember at the moment, the motivation/details but it seems like it was done to
        -- support Photooey's need for preset in export settings / preset, when such official preset may not exist. Bottom line, it's a sorta
        -- iffy proposition, IMO - but working...
        if preset then -- no error in backing file
            if self.backing and not preset.backingData then -- ###2 this added to work around bug discovered 9/Nov/2013 21:35 - not sure how preset with backing file is in cache without backing data, but until remedied:
                preset = self:getPreset( presetName, true ) -- force reload, if applicable.
            end
            if preset.backingData then
                value = preset.backingData[propName]
            else
                --Debug.pause( "no backing data" )
            end
        else
            app:error( "Unable to get preset - presumably there was a syntax error in the backing file of '^1'", presetName )
        end
    end
    if value == nil then
        app:callingAssert( gbl:getValue( 'systemSettings' ), "No system settings" )
        local rootKey = app:getSettingsKey( presetName ) -- get root settings key for preset.
        local propKey = systemSettings:getKey( rootKey, propName ) -- get child key corresponding to property name
        value = systemSettings:getValue( propKey ) -- get settings value corresponding to absolute key, from prefs (no options).
        if value == nil then value = systemSettings:getRootValue( rootKey, propName ) end -- support prefs in root of settings file if not exposed via UI (like advanced settings).
    end
    return value
end



--- Get global preference pair iterator.
--
--  @param      sortFunc (boolean or function, default false) pass true for default name sort, or function for custom name sort.
--
--  @usage      for iterating global preferences, without having to wade through non-globals.
--
--  @return     iterator function that returns name, value pairs, in preferred name sort order.
--              <br>Note: the name returned is not a key. to translate to a key, call get-global-pref-key and pass the name.
-- 
function Preferences:getGlobalPrefPairs( sortFunc )

    local names = {}
    local values = {}
    assert( prefs.pairs ~= nil, "no pref pairs" )
    for k, v in prefs:pairs() do
        if k:sub( 1, 8 ) == '_global_' then
            local name = k:sub( 9 )
            names[#names+1] = name
            values[name] = v
        end
    end
    
    if sortFunc ~= nil then
        if type( sortFunc ) == 'function' then
            table.sort( names, sortFunc )
        elseif sortFunc then
            table.sort( names )
        -- else dont sort
        end
    -- else dont sort
    end
    
    local index = 0
    return function()
        index = index + 1
        local name = names[index]
        return name, values[name]
    end
    
end



--- Get non-global preference pair iterator.
--
--  @param      sortFunc (boolean or function, default false) pass true for default name sort, or function for custom name sort.
--
--  @usage      for iterating non-global preferences, without having to wade through globals.
--
--  @return     iterator function that returns name, value pairs, in preferred name sort order.
--              <br>Note: the name returned is not a key. to translate to a key, call get-pref-key and pass the name.
-- 
function Preferences:getPrefPairs( sortFunc, presetName )

    presetName = presetName or self:getPresetName()

    local names = {}
    local values = {}
    
    if prefs['preset__' .. presetName] == nil then
        Debug.pause( "unregistered preset:", presetName )
        return function() return nil end
    end
    local prefix = presetName .. '__' -- must match get-pref-key.
    local pos = prefix:len() + 1
    assert( prefs.pairs ~= nil, "no pref pairs" )
    for k,v in prefs:pairs() do
        if str:isBeginningWith( k, prefix ) then -- up 'til 25/Apr/2014 prefix (i.e. preset-name) was being interpreted as regex.
            local name = k:sub( pos )
            names[#names+1] = name
            values[name] = v
        else
            -- dbg( "skip load prop: ", k )
        end
    end
    
    if sortFunc ~= nil then
        if type( sortFunc ) == 'function' then
            table.sort( names, sortFunc )
        elseif sortFunc then
            table.sort( names )
        -- else dont sort
        end
    -- else dont sort
    end
    
    local index = 0
    return function()
        index = index + 1
        local name = names[index]
        return name, values[name]
    end
    
end



--- Load properties from preset.
--
--  <p>Default set is handled like any other: properties are loaded whether set is registered or not.</p>
--
--  @usage      Like all preference methods, this method is wrapped by app object - see App class for more info.
--
function Preferences:loadProps( props, presetName )
    app:callingAssert( props ~= nil, "no props to load" )
    dbgf( "Loading props" )
    presetName = presetName or self:getPresetName()
    if prefs['preset__' .. presetName] == nil then
        dbgf( "Loading properties from preset ^1", presetName )
    end
    local prefix = presetName .. '__' -- must match get-pref-key.
    local pos = prefix:len() + 1
    assert( prefs.pairs ~= nil, "no pref pairs" )
    for k,v in prefs:pairs() do
        if str:isBeginningWith( k, prefix ) then -- until 25/Apr/2014 2:36 this was is-starting-with, so interpretation was regex, which meant no presets with '-' or '+'...
            local propName = k:sub( pos )
            dbg( "load prop: ", str:format( "prop-name: ^1, val: ^2, from pref-key: ^3", propName, str:to( v ), k ) )
            props[propName] = v
            --app:yieldIfPossible() -- assures change handler has a chance to run (often times, they are silently guarded).
            -- Not sure if we really want the change handler running with settings in a potentially half-baked state.
        else
            -- dbg( "skip load prop: ", k )
        end
    end
end



--- Register a preset.
--
--  <p>Typically called in init-prefs to register a preset to be subsequently initialized,
--  for when plugin is including built-in presets, in which case backing file if any,
--  is explicitly provided in 'Preferences' folder.</p>
--
--  @param presetName - Any name that can be used as part of a pref key.
--  @param presetNumber - Ordinal number defining sequence in plugin manager.
--
--  @usage Un-registering presets is done in the course of deleting a preset - no need for independent unreg method.
--
function Preferences:registerPreset( presetName, presetNumber )
    if presetNumber == nil and str:is( prefs['preset__' .. presetName] ) then
        return -- already registered.
    end
    if presetNumber == nil then
        if self.presetIndex == nil then
            self.presetIndex = 1
        else
            self.presetIndex = self.presetIndex + 1
        end
    else
        self.presetIndex = presetNumber
    end
    prefs["presetIndex__" .. presetName] = self.presetIndex
    prefs["preset__" .. presetName] = true
end



function Preferences:_isRegistered( presetName )
    return prefs["preset__" .. presetName]
end



--- Save propertiesavings into named or unamed set.
--      
--  <p>If named, sets 'name-existing' indicator into prefs.</p>
--
--  @usage      Like all preference methods, this method is wrapped by app object - see App class for more info.
--
function Preferences:saveProps( props, presetName )
    assert( props ~= prefs, "props are prefs" )
    presetName = presetName or self:getPresetName()
    if props and props.pairs then
        for k,v in props:pairs() do
            if k:find( '_global_' ) then
                dbg( 'global prop should not be saved' )
            else
                self:setPref( k, v )
            end
        end
    else
        app:logWarning( "Registering preset with no props, pairs: " .. (props.pairs or "nil") )
    end
    dbg( "registering saved preset: ", "preset__" .. presetName )
    self:registerPreset( presetName ) -- if not already registered.
    -- prefs["preset__" .. presetName] = true
end



--- Checks if specified named set exists - case insensitive: for checking if duplicate before adding.
--
--  @usage      @2010-11-22 - only called within pref mngr proper.
--
function Preferences:isPresetExisting( _setName )
    dbg( "checking if set exists: ", str:format( "nm: ^1, val: ^2", "preset__" .. _setName, str:to( prefs["preset__" .. _setName] ) ) )
    -- return prefs["preset__" .. setName] - this is case sensitive: especially not good if prefs are backed by case-insensitive file.
    local setName = LrStringUtils.lower( _setName )
    for k, v in prefs:pairs() do
        if str:isStartingWith( k, "preset__" ) then -- its a preset registration - regex is ok.
            local name = k:sub( 9 )
            if str:is( name ) then
                name = LrStringUtils.lower( name )
                if name == setName then -- dup
                    return true
                end
            else
                app:logVerbose( "*** Shouldn't be blank prefs registered." )
            end
        end
    end
    return false
end



--- Delete active named set.
--      
--  @param      props       Properties to load from some other set (presently the default/un-named set) once present set is deleted.
--
--  @usage      Throws error if active set is unamed, so check first.
--
function Preferences:deletePreset( props, presetName )
    presetName = presetName or self:getPresetName()
    local ok
    if presetName == 'Default' then
        ok = dialog:isOk( str:fmt( "Reset 'Default' settings to factory defaults?" ) )
    else
        if self:isBackedByFile() then
            ok = dialog:isOk( str:format( "Delete '^1' preset and all associated settings including the preset support file (plugin configuration file that contains advanced settings)?", presetName ) )
        else
            ok = dialog:isOk( str:format( "Delete '^1' preset and associated settings ?", presetName ) )
        end
    end
    if ok then
        self:_deletePreset( props, presetName ) -- name implied.
        app:yieldIfPossible() -- allow change detector to run before next thing assumes...
    end
    return ok
end



--- Load defaults into properties.
--
--  @usage defaults come from init-pref calls.
--
function Preferences:loadDefaults( props, presetName )
    presetName = presetName or self:getPresetName()
    local prefix = presetName .. '__'
    local pos = prefix:len() + 1
    -- @9/Oct/2012 20:15 (preset may not need to be registered, but should be...):
    for k, v in pairs( self.dfltProps ) do
        self:setPref( k, v, presetName )
        if props then
            props[k] = v
        end
        --app:yieldIfPossible() -- assures change handler has a chance to run (often times, they are silently guarded).
        -- Not sure if we really want the change handler running with settings in a potentially half-baked state.
    end
    --[[ *** save for a while (this is how it used to work, up 'til 9/Oct/2012 20:15):
    for k,v in prefs:pairs() do
        if str:isStartingWith( k, prefix ) then -- regex probably NOT ok here!?
            local propName = k:sub( pos )
            local value = self.dfltProps[propName]
            dbg( "loading default: ", str:format( "prop-name: ^1, val: ^2, pref-key: ^3", propName, str:to( value ), k ) )
            prefs[k] = value
            props[propName] = value -- could just load-props afterward, but might as well get it while I'm here...
            app:yieldIfPossible() -- assures change handler has a chance to run (often times, they are silently guarded).
        elseif app:isVerbose() then
            dbg( "not loading default: ", k )
        end
    end
    --]]
end



--- Load defaults into properties.
--
--  @usage defaults come from init-pref calls.
--
function Preferences:loadGlobalDefaults()
    local prefix = '_global_'
    local pos = prefix:len() + 1
    assert( prefs.pairs ~= nil, "no pref pairs" )
    for k,v in prefs:pairs() do
        if str:isStartingWith( k, prefix ) then -- regex ok since prefix is just _ global _ .
            -- local propName = k:sub( pos )
            local value = self.glblDfltProps[k]
            -- dbg( "loading global default: ", str:format( "key: ^1, val: ^2", k, str:to( value ) ) )
            prefs[k] = value
            --app:yieldIfPossible() -- assures change handler has a chance to run (often times, they are silently guarded).
            -- Not sure if we really want the change handler running with settings in a potentially half-baked state.
        elseif app:isVerbose() then
            dbg( "not loading global default: ", k )
        end
    end
end


function Preferences:_moveOrCopyPrefs( oldPrefix, newPrefix, delSrcPrefs )
    local pos = oldPrefix:len() + 1
    for k, v in prefs:pairs() do
        if str:isBeginningWith( k, oldPrefix ) then -- up 'til 25/Apr/2014 2:52 old-prefix was being interpreted as regex.
            local propName = k:sub( pos )
            local newPropKey = newPrefix .. propName
            if delSrcPrefs then
                dbg( "moving pref: ", str:format( "prop-name: ^1, val: ^2, new prop-key: ^3", propName, str:to( v ), newPropKey ) )
                prefs[newPropKey] = v
                prefs[k] = nil
            else
                dbg( "copying pref: ", str:format( "prop-name: ^1, val: ^2, new prop-key: ^3", propName, str:to( v ), newPropKey ) )
                prefs[newPropKey] = v
            end
        else
            dbg( "not moving: ", k )
        end
    end
end


-- Note: supports preset renaming.
function Preferences:_movePrefs( oldName, newName )
    if oldName == 'Default' then
        app:callingError( "can't move default prefs - check before calling." )
    end
    if newName == 'Default' then
        app:callingError( "can't move prefs to default - check new-name before calling." )
    end
    local oldPrefix = oldName .. "__"
    local pos = oldPrefix:len() + 1
    local newPrefix = newName .. "__"
    self:_moveOrCopyPrefs( oldPrefix, newPrefix, true ) -- move exposed prefs.
    if self.setsBacking then
        local oldRootKey, _oldName = app:getSettingsKey( oldName )
        local oldPrefix = oldRootKey .. "__"
        local newRootKey, _newName = app:getSettingsKey( newName )
        local newPrefix = newRootKey .. "__"
        Debug.pause( oldPrefix, newPrefix )
        self:_moveOrCopyPrefs( oldPrefix, newPrefix, true ) -- move exposed prefs.
    end
end



-- Note: supports preset duplication.
function Preferences:_copyPrefs( oldName, newName )
    if newName == 'Default' then
        app:callingError( "can't move prefs to default - check new-name before calling." )
    end
    local oldPrefix = oldName .. "__"
    local pos = oldPrefix:len() + 1
    local newPrefix = newName .. "__"
    self:_moveOrCopyPrefs( oldPrefix, newPrefix, false ) -- copy exposed prefs.
    if self.setsBacking then
        local oldRootKey, _oldName = app:getSettingsKey( oldName )
        local oldPrefix = oldRootKey .. "__"
        local newRootKey, _newName = app:getSettingsKey( newName )
        local newPrefix = newRootKey .. "__"
        Debug.pause( oldPrefix, newPrefix )
        self:_moveOrCopyPrefs( oldPrefix, newPrefix, true ) -- move exposed prefs.
    end
end



function Preferences:_unregisterPreset( presetName )
    if presetName ~= 'Default' then
        dbg( "Unregistering preset: ", presetName )
        prefs["preset__" .. presetName] = nil
        local index = prefs["presetIndex__" .. presetName]
        prefs["presetIndex__" .. presetName] = nil
        return index
    else
        app:error( "Can't unregister default preset" )
    end
end


--  Delete active named set.
--      
--  @param      props       Properties to load from some other set (presently the default/un-named set) once present set is deleted.
--
--  @usage      Throws error if active set is unamed, so check first.
--
function Preferences:_deletePreset( props, presetName )
    presetName = presetName or self:getPresetName()
    local prefix = presetName .. '__'
    local pos = prefix:len() + 1
    assert( prefs.pairs ~= nil, "no pref pairs" )
    local function deleteBacker( soBacked, backingDir )
        if not soBacked then
            return
        end
        local file, name = self:getPrefSupportFile( presetName, backingDir )
        if file then
            if fso:existsAsFile( file ) then
                local answer
                if app:isRelease() then
                    answer = 'ok' -- approval was given previously.
                else -- in develop mode, best not to delete what may be the only copy of built-in preset support files.
                    answer = app:show{ confirm="Are you sure you want to delete the preset support text file?: ^1",
                        subs = file,
                        buttons = { dia:btn( "Yes", 'ok' ), dia:btn( "No", 'cancel' ) },
                    }
                end
                if answer == 'ok' then
                    local s,m = fso:moveToTrash( file )
                    if s then
                        app:show{ info="Moved to trash or deleted: ^1", file }
                    else
                        app:show{ error="Unable to delete file: ^1", file }
                    end
                end
            end
        else
            app:show{ error="can't delete backing file - ^1", name }
        end
    end
    for k,v in prefs:pairs() do
        if str:isBeginningWith( k, prefix ) then -- up 'til 25/Apr/2014 2:52 prefix was being interpreted as regex.
            local propName = k:sub( pos )
            dbg( "del: ", str:format( "prop-name: ^1, val: ^2", propName, str:to( v ) ) )
            if presetName == 'Default' then
                prefs[k] = self.dfltProps[propName]
            else
                prefs[k] = nil
            end
        else
            dbg( "not deleting: ", k )
        end
    end
    if presetName ~= 'Default' then
        deleteBacker( self.backing, self.prefDir )
        deleteBacker( self.setsBacking, self.setsDir )
        self:_unregisterPreset( presetName )
    end
    prefs._global_presetName = 'Default'
    if props then
        self:loadProps( props ) -- requires props.
    end
    if presetName == 'Default' then
        app:show{ info="Default settings have been reset." }
    end
end



--  Return iterator that feeds k,v pairs back to the calling context sorted according to the specified sort function.
--      
--  @param           sortFunc       May be nil, in which case default sort order is employed (alphabetical).
--      
--  @return          Iterator function.
--
function Preferences:___________sortedPairs( sortFunc )
    local a = {}
    assert( prefs.pairs ~= nil, "no pref pairs" )
    for k in prefs:pairs() do
        a[#a + 1] = k
    end
    table.sort( a, sortFunc )
    local i = 0
    return function()
        i = i + 1
        return a[i], prefs[a[i]]
    end
end



--- Gets list of saved (registered) presets.
--      
--  @return    Array of strings suitable for combo box.
--
function Preferences:getPresetNames()
    --[[ *** save as reminder:
    local ordered = false
    local sortFunc = function( p2, p1 )
        local reverse = false
        if p1 ~= nil and p2 ~= nil then
            local one = prefs['presetIndex__' .. p1]
            if one ~= nil then
                local two = prefs['presetIndex__' .. p2]
                if two ~= nil then
                    reverse = one < two
                    ordered = true
                else
                    reverse = false -- sort function prefers a false if there is anything iffy...
                end
            else
                reverse = false -- sort function prefers a false if there is anything iffy...
            end
        else
            reverse = false -- sort function prefers a false if there is anything iffy...
        end
        return reverse
    end
    --]]
    local items = {}
    for k,v in prefs:pairs() do -- all prefs - unsorted.
        if str:isStartingWith( k, "preset__" ) then -- regex ok
            local set = k:sub( 9 )
            if set ~= 'Default' then
                items[#items + 1] = set
            end
        end
    end
    --local newItems = tab:sortReverseCopy( items, sortFunc )
    --if ordered then
    --    Debug.pause( "ordered" )
    --    return newItems
    --else
        table.sort( items ) -- sort original items alphabetically.
        --Debug.pause( "sorted" )
        table.insert( items, 1, 'Default' )
        for i, v in ipairs( items ) do
            prefs['presetIndex__' .. v] = i -- lock in the order for next time - new presets will have index assigned too.
        end
        return items
    --end
end



function Preferences:refreshPresetMenu( props )
    props.items = {} -- keeps menu from blinking when switching presets.
    local items = {}
    local names = self:getPresetNames() -- string array, sorted - 'Default' is always first.
    for i, name in ipairs( names ) do
        items[#items + 1] = { title=name, value=name }
    end
    if #items > 1 then
        table.insert( items, 2, { separator=true } ) -- separate 'Default' preset.
    end
    items[#items + 1] = { separator=true }
    items[#items + 1] = { title="New Preset", value="__new__" }
    items[#items + 1] = { title="Duplicate Preset", value="__dup__" }
    items[#items + 1] = { title="Rename Preset", value="__ren__" }
    items[#items + 1] = { title="Delete Preset", value="__del__" }
    if self:isBackedByFile() then
        items[#items + 1] = { title="Edit Advanced Settings", value="__edit__" }
        items[#items + 1] = { title="Reload Advanced Settings", value="__reload__" }
    end
    if true then -- ###1 params.props or params.loadDefaults then
        items[#items + 1] = { title="Load Factory Defaults", value="__defaults__" }
    end
    items[#items + 1] = { title="Help", value="__help__" }
    props.items = items
    local sel
    local currPresetName = self:getPresetName()
    for i, name in ipairs( names ) do
        if name == currPresetName then -- valueBindTo[valueKey] then
            sel = name
            break
        end
    end
    if str:is( sel ) then
        props.sel = sel
    else
        props.sel = 'Default'
    end
    --return items -- ?###1
end


--- Make plugin-manager preset popup.
--
--  @params (table) name/value parameter pairs:<br>
--              * call (optional: used for context to create local props if not passed)
--              * sort (boolean true to sort alphabetically, or sort function).
--              * props (props in calling context to contain preset target values)
--              * valueBindTo - e.g. prefs or props (can be same or different from props).
--              * valueKey ( default = 'presetValue' )
--              * viewOptions ( default = {} ) -- table of view options for starters: e.g. width_in_chars, or fill_horizontal.
--
--  @usage modeled after LrFtp.makeFtpPresetPopup
--  @usage uses global view factory (vf).
--
--  @return view
--
function Preferences:makePresetPopup( params )

    if params.props == nil then
        app:callingAssert( params.call, "need props or call w/context" )
    end
    
    local props = params.props or LrBinding.makePropertyTable( params.call.context )
    
    local helpMsg
    if params.helpMsg == nil then
        local p = {} -- paragraphs
        p[#p + 1] = "The preset popup allows you to choose a different (named) set of options, or manage these sets of options:"
        p[#p + 1] = "The upper choices are for the former (choose preset name), the lower choices are for the latter (preset management):"
        p[#p + 1] = "* New Preset: Create a new preset - initial values will be the factory defaults."
        p[#p + 1] = "* Duplicate Preset: Same as 'New Preset', except initial values will be same as selected (duplicated) preset."
        p[#p + 1] = "* Rename Preset: Rename preset - values will be preserved, but you may need to re-choose the new name in some places..."
        if self:isBackedByFile() then
            p[#p + 1] = "* Delete Preset: Delete the presently selected preset; includes deletion of \"backing file\" containing advanced settings."
            p[#p + 1] = "* Edit Advanced Settings: Opens a lua text \"configuration\" file containing \"advanced\" settings in your default text editor. Note: some plugins require you to select 'Reload Advanced Settings' after editing advanced settings, or reload plugin, for changes to take effect."
            p[#p + 1] = "* Reload Advanced Settings: Reloads edited settings from \"configuration\" file. Reminder: some plugins require you to select 'Reload Advanced Settings' after editing advanced settings, or reload plugin, for changes to take effect."
        else
            p[#p + 1] = "* Delete Preset: Delete the presently selected preset."
        end
        if params.props or params.loadDefaults then
            p[#p + 1] = "* Load Factory Defaults: Loads factory default values into presently selected preset."
        end
        
        helpMsg = table.concat( p, "\n\n" ) -- paragraph separator.
    else
        helpMsg = params.helpMsg
    end
    local valueBindTo = params.valueBindTo or prefs
    local valueKey = params.valueKey or app:getGlobalPrefKey( 'presetName' )
    local items = {}
    local names
    local function updItems()
        props.items = {} -- keeps menu from blinking when switching presets.
        items = {}
        names = self:getPresetNames() -- string array, sorted - 'Default' is always first.
        for i, name in ipairs( names ) do
            items[#items + 1] = { title=name, value=name }
        end
        if #items > 1 then
            table.insert( items, 2, { separator=true } ) -- separate 'Default' preset.
        end
        items[#items + 1] = { separator=true }
        items[#items + 1] = { title="New Preset", value="__new__" }
        items[#items + 1] = { title="Duplicate Preset", value="__dup__" }
        items[#items + 1] = { title="Rename Preset", value="__ren__" }
        items[#items + 1] = { title="Delete Preset", value="__del__" }
        if self:isBackedByFile() then
            items[#items + 1] = { title="Edit Advanced Settings", value="__edit__" }
            items[#items + 1] = { title="Reload Advanced Settings", value="__reload__" }
        end
        if params.props or params.loadDefaults then
            items[#items + 1] = { title="Load Factory Defaults", value="__defaults__" }
        end
        items[#items + 1] = { title="Help", value="__help__" }
        props.items = items
        local sel
        for i, name in ipairs( names ) do
            if name == valueBindTo[valueKey] then
                sel = name
                break
            end
        end
        if str:is( sel ) then
            props.sel = sel
        else
            props.sel = 'Default'
        end
    end
    local function isDup( name, caseSensitive )
        if names == nil or #names == 0 then
            app:error( "What happened to the default preferences?" )
        end
        if str:isEqualIgnoringCase( name, 'Default' ) then -- not OK to have distinct 'default' preset - any case.
            return true
        end
        for i, v in ipairs( items ) do -- items includes separators which have no value.
            if v.value ~= nil and str:isEqual( v.value, name, not caseSensitive ) then -- assures user can't create preset named '__new__' and such, too.
                return true
            end
        end
        return false    
    end
    
    updItems() -- create items and assign to props.
    
    local args = tab:copy( params.viewOptions or {} )
    args.bind_to_object = props
    args.value = bind 'sel'
    args.items = bind 'items'
    
    local vw = vf:popup_menu( args )
    
    -- note: @20/Jan/2013 4:59, record() *must* be followed by updItems(), otherwise weird menu race / items phenomenon.
    local function record( v )
    
        --props.value = v             -- what was this for?, not sure @20/Jan/2013 5:24 ###2 - doesn't seem to hurt anything, so leaving in (cant tell benefit either in present situation testing). - leftover from days before value was bound to sel?
        -- trying without (oh boy) @20/Jan/2013 5:34 - maybe not a good idea... - watch it...
        
        --vw.value = v                -- what was this for? @20/Jan/2013 5:02 - not sure ###2. removed 20/Jan/2013 5:30, since it makes the menu shaky, hopefully no longer needed!?
        
        --props.sel = v - don't do this: call updItems() upon return instead, which will keep from having wonky items.
        
        valueBindTo[valueKey] = v -- will trigger a change in external observer, which may be problematic, if external observer makes change that triggers ch below.
        if params.callback then -- callback avoids having 2 listeners vying, which was causing contention / infinite change ping-ponging.
            params.callback( v )
        end
    end
    local function ch( id, props, name, value )
    
        app:call( Call:new{ name="presetPopupChangeHandler", async=true, guard=App.guardSilent, main=function( call ) -- was released up to 17/Nov/2012 21:51 in most plugins as synchronous,
            -- but editing a new preset backing file isn't working unless async is true.
        
            if name == 'sel' then
                if value == "__new__" then
                    local oldName = valueBindTo[valueKey]
                    local newName = dia:getSimpleTextInput {
                        title="New Preset",
                        subtitle = "Enter new preset name:",
                        editFieldOptions = {
                            width_in_chars = 20,
                            immediate = true,
                            validate = function( view, value )
                                local newValue = value:gsub( "%.", "." )
                                if newValue ~= value then
                                    return false, newValue, "Dot ('.' character) has been removed from preset name - dots are not allowed in preset names."
                                else
                                    return true, value -- 'sit..
                                end
                            end,
                        },
                    }
                    --newName = newName:gsub( "%.", "" ) - works, but need comprehensive solution.
                    if str:is( newName ) then
                        if not isDup( newName ) then
                            self:createPreset( params.props, newName ) -- always created with default values now.
                            --valueBindTo[valueKey] = newName
                            record( newName )
                            updItems() -- sets props.sel. props.value only needs to be set when change to preset selection is asynchronous/external.
                        else
                            app:show{ warning="There is already a preset named '^1' - consider a different name.", newName }
                            props.sel = oldName
                        end
                    else
                        props.sel = oldName
                    end
                    
                elseif value == "__dup__" then
                    local oldName = valueBindTo[valueKey]
                    local names = self:getPresetNames()
                    if names ~= nil and #names > 0 then
                        local newName = dia:getSimpleTextInput{
                            title="Duplicate Preset",
                            subtitle = str:fmtx( "Enter new preset name for duplicate of ^1:", oldName ),
                            init = oldName .. " 2",
                            editFieldOptions = {
                                width_in_chars = 20,
                                immediate = true,
                                validate = function( view, value )
                                    local newValue = value:gsub( "%.", "." )
                                    if newValue ~= value then
                                        return false, newValue, "Dot ('.' character) has been removed from preset name - dots are not allowed in preset names."
                                    else
                                        return true, value -- 'sit..
                                    end
                                end,
                            },
                        }
                        if str:is( newName ) then
                            if not isDup( newName ) then -- if new-name is 'Default' (ignoring case), it will be considered a dup.
                                
                                local index
                                for i, v in ipairs( names ) do
                                    if oldName == v then
                                        index = i
                                        break
                                    end
                                end
                                
                                if index then
    
                                    self:duplicatePreset( params.props, oldName, newName )
    
                                    record( newName )
                                    updItems()
                                else
                                    Debug.pause( "no preset to duplicate" )
                                    props.sel = oldName
                                end
                                
                                app:show{ info="'^1' duplicated to '^2'", oldName, newName }
                                
                            else
                                app:show{ warning="There is already a preset named '^1' - consider a different name.", newName }
                                props.sel = oldName
                            end
                        else
                            props.sel = oldName
                        end
                    else
                        app:show{ warning="No presets to duplicate" }
                        props.sel = oldName
                    end
                    
                elseif value == "__ren__" then
                    local oldName = valueBindTo[valueKey]
                    if oldName ~= 'Default' then
                        local names = self:getPresetNames()
                        if names ~= nil and #names > 0 then
                            local newName = dia:getSimpleTextInput{
                                title="Rename Preset",
                                subtitle = str:fmtx( "Enter new preset name for ^1:", oldName ),
                                init = oldName .. " 2",
                                editFieldOptions = {
                                    width_in_chars = 20,
                                    immediate = true,
                                    validate = function( view, value )
                                        local newValue = value:gsub( "%.", "" )
                                        if newValue ~= value then
                                            return false, newValue, "Dot ('.' character) has been removed from preset name - dots are not allowed in preset names."
                                        else
                                            return true, newValue -- even if returning true status (indicating value is/was OK), the new value still needs to be returned too.
                                        end
                                    end,
                                },
                            }
                            if str:is( newName ) then
                                if not isDup( newName, true ) then -- true => see case difference as distinct name (not duplicate).
                                    
                                    local index
                                    for i, v in ipairs( names ) do
                                        if oldName == v then
                                            index = i
                                            break
                                        end
                                    end
                                    
                                    if index then
        
                                        self:renamePreset( params.props, oldName, newName )
        
                                        record( newName )
                                        updItems()
                                    else
                                        Debug.pause( "no preset to rename" )
                                        props.sel = oldName
                                    end
                                    
                                    app:show{ info="'^1' renamed to '^2'", oldName, newName,
                                        actionPrefKey = "Preference renamed",
                                    }
                                    
                                else
                                    app:show{ warning="There is already a preset named '^1' - consider a different name.", newName }
                                    props.sel = oldName
                                end
                            else
                                props.sel = oldName
                            end
                        else
                            app:show{ warning="No presets to rename" }
                            props.sel = oldName
                        end
                    else
                        app:show{ warning="You can't rename the default preset." }
                        props.sel = oldName
                    end
                    
                elseif value == "__del__" then
                    local oldName = valueBindTo[valueKey]
                    if oldName ~= 'Default' then
                        local ok = self:deletePreset( params.props, oldName ) -- props ignored if nil; yields before return.
                        if ok then
                            --valueBindTo[valueKey] = 'Default'
                            record( 'Default' )
                            updItems() -- will set props.sel to 'Default'.
                        else
                            Debug.pause( "notok" )
                            props.sel = oldName
                        end
                    else
                        app:show{ warning="You can't delete the default preset." }
                        props.sel = oldName
                    end
                elseif value == "__edit__" then
                    local presetName = valueBindTo[valueKey]
                    local function editBacker( soBacked, backingDir )
                        assert( soBacked ~= nil, "backing failure" )
                        if not soBacked then
                            return
                        end
                        assert( str:is( backingDir ), "backing failure #2" )
                        local file, name = self:getPrefSupportFile( presetName, backingDir ) -- possible for file to be nil, if file missing or whatever
                        if file ~= nil then
                            if fso:existsAsFile( file ) then
                                local button = app:show{ info="In a moment, '^1' will open in the default app for you to edit. After editing, be sure to click the 'Reload Advanced Settings' button (or reload plugin).",
                                    subs = { file },
                                    actionPrefKey = "Reminder to reload after editing advanced settings" }
                                if button ~= 'cancel' then
                                    app:openFileInDefaultApp( file, true ) -- true => prompt before and after opening.
                                end
                            else
                                app:show{ error="Not existing: ^1", file } -- Its created when the set is created, and each time when switching sets - so simple error here OK.
                            end
                        else
                            app:show{ error="No preference support file - ^1", name } -- Its created when the set is created, and each time when switching sets - so simple error here OK.
                        end
                    end
                    if presetName ~= 'Default' or ( app:getUserName() == '_RobCole_' and app:isAdvDbgEna() ) then
                        editBacker( self.backing, self.prefDir )
                        editBacker( self.setsBacking, self.setsDir )
                    else
                        app:show{ warning="You can not edit advanced settings of the default preset (since it may be overwritten upon next plugin update). Create a new preset and edit it's advanced settings instead (or select a different preset)." }
                    end
                    props.sel = presetName
                elseif value == "__reload__" then
                    local presetName = valueBindTo[valueKey]
                    local function loadBacker( soBacked, backingDir, dfltFile )
                        if not soBacked then
                            return
                        end
                        local file, name = self:getPrefSupportFile( presetName, backingDir )
                        if file then
                            if fso:existsAsFile( file ) then
                                self:loadPrefFile( file, presetName ) -- load props used to do this (throws error if probs).
                                assert( name == LrPathUtils.leafName( file ), "Preset file naming anomaly" )
                                app:logV( "Reloaded advanced settings for ^1 preset, by re-reading preset backing file: ^2", presetName, file ) -- long version.
                                app:showBezel( { holdoff=0 }, "'^1' reloaded.", presetName ) -- added 27/Nov/2013 2:59. Reminder: the difference between this and display method is display prepends app-name.
                                -- in this case, app-name is overkill since display is the direct result of user action within known plugin..
                            else
                                app:show{ error="Unable to reload advanced settings for ^1, preset backing file not found:\n^2", presetName, file } -- Its created when the set is created, and each time when switching sets - so simple error here OK.
                            end
                        else
                            app:show{ error="can't reload backing file - ^1", name }
                        end
                    end
                    loadBacker( self.backing, self.prefDir, self.dfltFile )
                    loadBacker( self.setsBacking, self.setsDir, self.dfltSetsFile )
                    props.sel = presetName
                elseif value == "__defaults__" then
                    local presetName = valueBindTo[valueKey]
                    if dialog:isOk( str:fmt( "Overwrite ^1 settings with factory defaults?", presetName ) ) then
        	            if self.setsBacking then
        	                local key = app:getSettingsKey( presetName )
        	                local dataDescr, errm = systemSettings:getDataDescr( key )
        	                if dataDescr then
                                systemSettings:init{ key=key, items=dataDescr, bindTo=prefs, forceInit=true } -- throws err? ###2
                                if params.props then
        	                        self:loadDefaults( params.props, presetName ) -- props ignored if nil. ###2 callback if no props?
        	                    elseif params.loadDefaults then
        	                        params.loadDefaults( presetName )
        	                    else
        	                        app:show{ warning="Defaults can't be loaded.", actionPrefKey="Default preferences not loaded" }
        	                        return
        	                    end
        	                    app:logv( "Prefs reset to factory defaults, and additional settings forcefully re-initialized too." )
        	                    app:show{ info="Defaults were successfully loaded...", actionPrefKey="Default preferences and settings loaded" }
        	                else
        	                    Debug.pause( "no data descr" )
                            end
                        else
                            if params.props then
    	                        self:loadDefaults( params.props, presetName ) -- props ignored if nil. ###2 callback if no props?
    	                    elseif params.loadDefaults then
    	                        params.loadDefaults( presetName )
    	                    else
        	                    app:show{ warning="Defaults can't be loaded.", actionPrefKey="Default preferences not loaded" }
        	                    return
    	                    end
      	                    app:logv( "Prefs reset to factory defaults." )
        	                app:show{ info="Defaults were successfully loaded.", actionPrefKey="Default preferences loaded" }
                        end
        	        end
                    props.sel = presetName
                elseif value == "__help__" then
                    local presetName = valueBindTo[valueKey]
                    app:show{ info=helpMsg }
                    props.sel = presetName
                else -- existing preset selected from menu.
                    record( value )
                    
                    -- props.sel = value - not enough
                    updItems() -- needs this for some reason, else items are *sometimes* wonky. ###2
                end
            elseif name == valueKey then -- bound value has changed, usually (always?) externally.
                record( value )
                updItems()
            else
                Debug.pause( name, value )
            end
        end } )
    end
    view:setObserver( props, 'sel', Preferences, ch ) -- assure selection changes propagate to targets.
    view:setObserver( valueBindTo, valueKey, Preferences, ch ) -- target preset name change propagates to selection.
    return vw
end



return Preferences