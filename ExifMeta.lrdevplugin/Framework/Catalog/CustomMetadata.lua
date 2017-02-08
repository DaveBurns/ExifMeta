--[[
        CustomMetadata.lua
        
        By "custom metadata" I mean "plugin-defined" metadata.
--]]        


local CustomMetadata, dbg, dbgf = Object:newClass{ className = 'CustomMetadata', register = true }



--- Constructor for extending class.
--
function CustomMetadata:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function CustomMetadata:new( t )
    local o = Object.new( self, t )
    return o
end



--- Get set of plugin Ids (that are enabled and have custom metadata).
--
--  @usage for id, _ in pairs( custMeta:getPlugIds() ) do..
--
--  @return set of plugin IDs, may be empty, but will never be nil.
--
function CustomMetadata:getPluginIds()
    local photo = cat:getAnyPhoto()
    if not photo then
        return nil, "No photos"
    end
    local met = photo:getRawMetadata( 'customMetadata' ) -- @Lr4.4RC, this returns nil when "reload plugin..." box is checked.
    if met ~= nil then
        local pluginIds = {}
        for i, v in ipairs( met ) do
            pluginIds[v.sourcePlugin] = true
        end
        return pluginIds -- includes plugin Ids whether all custom metadata for random photo is blank or not.
    else
        -- added 20/Mar/2013 21:27
        local pluginIds = {}
        local cMeta = cat:getBatchRawMetadata( { photo }, { 'customMetadata' } ) -- works OK regardless of reload checkbox.
        local t = cMeta[photo].customMetadata -- throw error if custom-metadata not included.
        if tab:isNotEmpty( t ) then
            for k, v in pairs( t ) do
                local plugin = LrPathUtils.removeExtension( k ) -- id
                --local pluginName = LrPathUtils.extension( plugin )
                --Debug.pause( plugin, pluginName )
                pluginIds[plugin] = true -- assure ID is in set.
            end
        else
            Debug.pause( "no plugins with custom metadata are enabled" )
        end
        return pluginIds -- includes only those items for plugins whose custom metadata for random photo has at least one non-blank item.
    end    
end



--- Get specific plugin ID, given it's exact (albeit case insensitive) name suffix (must be enabled and have custom metadata).
--
--  @usage pluginId, errm = custMeta:getPluginId( "ChangeManager" ) -- for example.
--
--  @return plugin-id string, or nil
--  @return reason for nil plugin-id, or nil
--
function CustomMetadata:getPluginId( name, reverseDomain )
    app:callingAssert( str:is( name ), "no name" )
    local photo = cat:getAnyPhoto()
    if not photo then
        return nil, "No photos"
    end
    
    local met = photo:getRawMetadata( 'customMetadata' ) -- @20/Mar/2013 8:03, this is returning nil when "Reload plugin on each export" is checked.
    
    if met ~= nil then
        local pluginIds = {}
        local pluginId
        for i, v in ipairs( met ) do
            local plugin = v.sourcePlugin
            local pluginName = LrPathUtils.extension( plugin )
            if not str:is( pluginName ) then
                pluginName = plugin
            end
            if reverseDomain == nil or str:isStartingWith( plugin, reverseDomain, 1, true ) then
                if str:isEqualIgnoringCase( pluginName, name ) then
                    if pluginId and pluginId ~= plugin then
                        Debug.pause( pluginId, plugin )
                        return nil, "Plugin ID is ambiguous"
                    else
                        pluginId = plugin
                    end
                end
            -- else not starting with specified reverse-domain.
            end
        end
        return pluginId -- nil and not errm => just not installed or enabled - no error.
    else -- older version of Lr or "reload plugin..." is checked.   
        local pluginId
        local cMeta = cat:getBatchRawMetadata( { photo }, { 'customMetadata' } ) -- works OK regardless of reload checkbox.
        local t = cMeta[photo].customMetadata -- throw error if custom-metadata not included.
        if tab:isNotEmpty( t ) then
            for k, v in pairs( t ) do
                local plugin = LrPathUtils.removeExtension( k ) -- id
                if reverseDomain == nil or str:isBeginningWith( plugin, reverseDomain ) then -- up 'til 25/Apr/2014 2:54 reverse-domain was being interpreted as regex.
                    local pluginName = LrPathUtils.extension( plugin )
                    if str:isEqualIgnoringCase( pluginName, name ) then
                        if pluginId and pluginId ~= plugin then
                            Debug.pause( pluginId, plugin )
                            return nil, "plugin ID is ambiguous"
                        else
                            pluginId = plugin
                        end
                    end
                -- else not starting with specified reverse-domain.
                end
            end
        else
            Debug.pause( "no plugins with custom metadata are enabled" )
        end
        return pluginId -- note: plugin ID will be nil if none of the photos have data defined - usually that's fine, but consider yourself warned...
    end
end



--- Set custom metadata property of photo to specified value, if not already set to it.
--
--  @param      photo (lr-photo, required) photo set metadata on.
--  @param      name (string, required) property name
--  @param      value (string | date | number | boolean, required) property value
--  @param      version (number, default nil) optional version number.
--  @param      noThrow (boolean, default false) optional no-throw, if omitted, errors are thrown.
--  @param      tries (number, default 10) number of tries - only applies if internal catalog wrapping required.
--
--  @usage      Will wrap with catalog access if need be.
--  @usage      Always throws errors for catastrophic failure, just not for undeclared metadata if no-throw.
--
--  @return     status (boolean or nil) true iff property set to different value, false iff property need not be set - already same value, nil => error setting property.
--  @return     error-message or previous value (string, nil, or any) nil if status false, error message if status nil, previous value if status true.
--
function CustomMetadata:update( photo, name, value, version, noThrow, tries )
    local _value, _errm = photo:getPropertyForPlugin( _PLUGIN, name, version, noThrow )
    if _errm then -- not doable & no-throw.
        return nil, _errm
    end
    if _value == value then -- whether one is nil or not.
        return false
    end
    -- fall-through => set
    if catalog.hasPrivateWriteAccess then -- has at least private write access, this should succeed since read succeeded.
        if noThrow then
            local s, m = LrTasks.pcall( photo.setPropertyForPlugin, photo, _PLUGIN, name, value, version )
            if s then
                return true, _value
            else
                -- return false, m - this until 31/Jan/2014 7:11
                return nil, m -- this after 31/Jan/2014 7:11, for consistency, e.g. with documentation. ###2 beware of potential for subtle bugs induced.
            end
        else
            photo:setPropertyForPlugin( _PLUGIN, name, value, version )
            return true, _value -- return old value for logging purposes or whatever.
        end
    else
        local status, message = cat:updatePrivate( tries or 10, function( context, phase )
            photo:setPropertyForPlugin( _PLUGIN, name, value, version ) -- @20/Jul/2012, no-throws for updating is only support for externally wrapped updates. ###3
        end )
        if status then
            return true, _value
        else
            return nil, message
        end
    end
end



--- Migrate metadata from previous instance of plugin.
--
--  @param      photos (array) lr-photos
--  @param      matchFunc (function, optional) if not passed, will match first two parts of present plugin, and last part.
--    <br>          if passed, is function that takes a plugin ID and returns true if it matches such that metadata should be transferred.
--
--  @usage      Throws error if >1 matching plugin.
--
--  @returns    status (boolean or nil) true => success.
--  @returns    message (string or nil) if failed, reason.
--
function CustomMetadata:migrate( photos, matchFunc )
    app:call( Service:new{ name="Migrate Custom (Plugin) Metadata", async=true, progress=true, main=function( call )
        call.scope:setCaption( "Dialog box needs your attention..." )
        if not app:isPluginEnabled() then
            app:show{ warning="Plugin must be enabled." }
            call:cancel()
            return
        end
        photos = photos or catalog:getAllPhotos()
        if #photos == 0 then
            app:show{ warning="No photos - metadata not migrated." }
            app:cancel()
            return
        end
        local this = str:split( _PLUGIN.id, "." )
        matchFunc = matchFunc or function( pluginId )
            local comp = str:split( pluginId, "." )
            if #comp < 3 then
                return false
            else
                if comp[1] == this[1] and comp[2] == this[2] and comp[#comp] == this[#this] then
                    return true
                else
                    return false
                end
            end
        end
        local allCustMeta = cat:getBatchRawMetadata( photos, { 'customMetadata' } )
        local pluginIdSet = self:getPluginIds()
        if tab:isEmpty( pluginIdSet ) then
            app:show{ warning="No compatible source plugins with metadata are enabled." }
            call:cancel()
            return
        end
        local pluginId
        for id, _ in pairs( pluginIdSet ) do
            if id ~= _PLUGIN.id then
                if matchFunc( id ) then
                    if pluginId then
                        -- Debug.pause( "Duplicate Match", id )
                        app:show{ warning="Ambiguous plugin source for metadata migration, already have: ^1, but ^2 also matches - consider disabling one of them.", pluginId, id }
                        call:cancel()
                        return
                    else
                        pluginId = id
                    end 
                else
                    -- Debug.pause( "No match", id )
                end
            -- else don't match self.
            end
        end
        if str:is( pluginId ) then
            app:log( "Migrating custom metadata from ^1", pluginId )
        else
            app:show{ warning="No matching plugin for custom metadata migration - you may need to enable it, or re-install (Add) it." }
            call:cancel()
            return
        end
        local answer = app:show{ confirm="Migrate metadata from previous plugin (^1) to this plugin (^2)?\n \nThis will effect ^3",
            subs = { pluginId, _PLUGIN.id, str:plural( #photos, "photo", true ) },
            buttons = { dia:btn( "OK", 'ok' ) },
        }
        if answer ~= 'ok' then
            call:cancel()
            return
        end
        call.scope:setCaption( "Migrating metadata..." ) 
        local s, m = cat:updatePrivate( 30, function( context, phase )
            local i1, i2 = ( phase - 1 ) * 1000 + 1, math.min( phase * 1000, #photos )
            for i = i1, i2 do
                local photo = photos[i]
                local photoPath = photo:getRawMetadata( 'path' )
                app:log( photoPath )
                local cMeta = custMeta:getMetadata( photo, pluginId, allCustMeta )
                if cMeta then
                    --Debug.lognpp( cMeta )
                    for id, val in pairs( cMeta ) do
                        Debug.logn( "Meta found", id, val )
                        local s, m = custMeta:update( photo, id, val )
                        if s then
                            app:logVerbose( "Updated metadata ID '^1' from '^2' to '^3'", id, m, val )  
                        elseif s == false then
                            app:logVerbose( "Metadata ID '^1' already '^2'", id, val )  
                        else
                            app:logErr( "Unable to update metadata item: ^1", m )
                        end
                    end
                else
                    app:logVerbose( "No custom metadata." )
                end
                if call:isQuit() then
                    return true
                else
                    call.scope:setPortionComplete( i, #photos )
                end
            end
            if i2 < #photos then
                return false
            end
        end )
        if s then
            -- good
        else
            app:logErr( m )
            return
        end
    end } )
end



--- Clear custom metadata for specified photos.
--
function CustomMetadata:clear( photos, call, noThrow ) -- future improvement could include stats ###2

    call.scope:setCaption( "Dialog box needs your attention..." )
    if not app:isPluginEnabled() then
        app:show{ warning="Plugin must be enabled." }
        call:cancel()
        return
    end
    photos = photos or catalog:getAllPhotos()
    if #photos == 0 then
        app:show{ warning="No photos - metadata not cleared." }
        app:cancel()
        return
    end
    local answer = app:show{ confirm="Clear metadata from this plugin (^1)?\n \nDon't do this unless you're sure it's what you want.\n \nThis will effect ^2.",
        subs = { _PLUGIN.id, str:plural( #photos, "photo", true ) },
        buttons = { dia:btn( "OK", 'ok' ) },
    }
    if answer ~= 'ok' then
        return
    end
    call.scope:setCaption( "Assessing custom metadata..." ) 
    local allCustMeta = cat:getBatchRawMetadata( photos, { 'customMetadata' } )
    call.scope:setCaption( "Clearing custom metadata..." ) 
    app:log( "Clearing custom metadata from this plugin (^1)", _PLUGIN.id )
    local s, m = cat:updatePrivate( 30, function( context, phase )
        local i1, i2 = ( phase - 1 ) * 1000 + 1, math.min( phase * 1000, #photos )
        for i = i1, i2 do
            local photo = photos[i]
            local photoPath = photo:getRawMetadata( 'path' )
            app:log( photoPath )
            local cMeta = custMeta:getMetadata( photo, _PLUGIN.id, allCustMeta ) -- Just a cheap way to get the ID's I need, plus reports the previous value that got cleared.
            if cMeta then
                for id, val in pairs( cMeta ) do
                    Debug.pause( "Meta found", id, val )
                    --Debug.logn( "Meta found", id, val )
                    local s, m = custMeta:update( photo, id, nil, nil, noThrow ) -- nil value, unspecified version number.
                    if s then
                        app:logVerbose( "Cleared metadata ID '^1', was '^2'", id, m )  
                    elseif s == false then -- this may never happen, since metadata is not included when it's nil.
                        app:logVerbose( "Metadata ID '^1' was already clear.", id )  
                    elseif noThrow then
                        app:logWarning( "Unable to clear metadata item: ^1", m )
                    else
                        app:logErr( "Unable to clear metadata item: ^1", m )
                    end
                end
            else
                app:logVerbose( "No custom metadata." )
            end
            if call:isQuit() then
                return true
            else
                call.scope:setPortionComplete( i, #photos )
            end
        end
        if i2 < #photos then
            return false
        end
    end )
    if s then
        app:log( "Metadata cleared." )
        return true
    else
        app:logErr( m )
    end
end



-- private method to prompt user
function CustomMetadata:_promptForMetadataSaveOrRead( call, _SaveOrRead )

    local save = _SaveOrRead == 'Save'
    local read = _SaveOrRead == 'Read'
    local tidbit
    if save then
        tidbit = "in"
    elseif read then
        tidbit = "from"
    else
        app:callingError( "bad op" )
    end
    if not _PLUGIN.enabled then
        app:show{ warning="Plugin must be enabled in plugin manager (hint: 'Enable' button in 'Status' section)." }
        call:cancel()
        return nil
    end
        
    local photos = catalog:getTargetPhotos()
    local dir = LrPathUtils.child( LrPathUtils.parent( catalog:getPath() ), _PLUGIN.id )
    if photos == nil then
        app:show{ warning="No photos to " .. saveOrRead }
        call:cancel()
        return nil
    end
    if dia:isOk( "^1 custom metadata for ^2 ^3 ^4?", _SaveOrRead, str:plural( #photos, "photo", true ), tidbit, dir ) then
        return { photos=photos, dir=dir }
    else
        call:cancel()
        return nil
    end
        
end



--- Save (all) custom metadata for specified photos, to disk.
--
--  @usage includes user prompt and the whole nine yards.
--  @usage presently saves in sibling directory of catalog (named plugin-id), prefixed by photo path.
--
--  @return status (boolean) true if operation completed without uncaught error - there may have been individual file errors logged.
--  @return message (string) error message if status false.
--
function CustomMetadata:save()
    return app:call( Service:new{ name="Custom Metadata - Save", async=true, guard=App.guardVocal, main=function( call )
        local pluginId = _PLUGIN.id
        local response = self:_promptForMetadataSaveOrRead( call, "Save" )
        if response == nil then
            return
        end
        local photos = response.photos
        local dir = response.dir
        call.scope = LrProgressScope {
            title = str:fmt( "Saving custom metadata for ^1", str:plural( #photos, "photo", true ) ),
            caption = "Please wait...",
            functionContext = call.context,
        }
        app:log( "Saving custom metadata for plugin (^2): ^1", pluginId, str:plural( #photos, "photo" ) )
        local emptyXml = str:fmt( '<?xml version=1.0?>\n<custom-metadata pluginId="^1"></custom-metadata>', pluginId )
        local metaXml
        local rootElem
        local metaLookup
        local function populateMetaLookup()
            metaLookup = {}
            for i, v in ipairs( rootElem ) do
                metaLookup[v.xarg[1].text] = v
            end
        end
        local incl = app:getPref( 'metadataSaveInclusions' ) -- this is your "out" in case some metadata items are better left unsaved/restored.
        if incl ~= nil then
            assert( type( incl ) == 'table', "inclusions must be table" )
            for k, v in tab:sortedPairs( incl ) do
                if v then
                    app:log( "Including '^1'", k )
                end
            end
        else
            app:log( "Including all items, unless explicitly being excluded." )
        end
        local excl = app:getPref( 'metadataSaveExclusions' ) -- this is your "out" in case some metadata items are better left unsaved/restored.
        if excl == nil then
            app:log( "No exclusions.\n" )
            excl = {}
        elseif type( excl ) == 'table' then
            for k, v in tab:sortedPairs( excl ) do
                if v then
                    app:log( "Excluding '^1'", k )
                end
            end
            app:log( "\n" )
        else
            app:error( "exclusions should be table, typically defined in advanced settings" )
        end
        local function addMeta( meta ) -- to local meta-xml
            -- meta = id, value, sourcePlugin
            -- app:logVerbose( "Custom metadata being added: ^1=^2 (^3)", meta.id, meta.value, type( meta.value ) )
            if excl[meta.id] then
                return
            end
            if incl ~= nil and not incl[meta.id] then
                return
            end
            local typ
            if meta.value == nil then
                typ = 'nil'
            else
                typ = type( meta.value )
            end
            local xmlElem
            if metaLookup[meta.id] then
                xmlElem = metaLookup[meta.id]
                if xmlElem.xarg[3].text == 'nil' then
                    xmlElem.xarg[2].text = str:to( meta.value )
                    xmlElem.xarg[3].text = typ
                elseif xmlElem.xarg[3].text == typ then
                    xmlElem.xarg[2].text = str:to( meta.value )
                else
                    app:logWarning( "Metadata type for ^1 was ^2 (value='^4'), being overwritten with type ^3, value='^5'", meta.id, xmlElem.xarg[3].text, typ, xmlElem.xarg[2].text, meta.value )
                    xmlElem.xarg[2].text = str:to( meta.value )
                    xmlElem.xarg[3].text = typ
                end
            else
                xmlElem = { label="metadata-item", xarg={ { name="id", text=meta.id }, { name="value", text=str:to( meta.value ) }, { name="type", text=typ } } }
                rootElem[#rootElem + 1] = xmlElem
                metaLookup[meta.id] = xmlElem
            end
        end
        local rawMeta = cat:getBatchRawMetadata( photos, { 'path', 'isVirtualCopy' } )
        local fmtMeta = cat:getBatchFormattedMetadata( photos, { 'copyName' } )
        for i, photo in ipairs( photos ) do
            repeat
                local before
                local photoPath = rawMeta[photo].path
                local isVirtualCopy = rawMeta[photo].isVirtualCopy
                local copyName = ""
                local photoFilename = LrPathUtils.leafName( photoPath )
                local file
                if isVirtualCopy then
                    copyName = fmtMeta[photo].copyName
                    file = LrPathUtils.child( dir, LrPathUtils.addExtension( str:fmt( "^1 (^2)", photoFilename, copyName ), "vc_custom-metadata.xml" ) ) -- add-extension may take care of character encoding(?)
                else
                    file = LrPathUtils.child( dir, LrPathUtils.addExtension( photoFilename, "custom-metadata.xml" ) ) -- add-extension may take care of character encoding(?)                end
                end
                app:log( "Saving custom metadata of ^1 to ^2", photoPath, file )
                if fso:existsAsFile( file ) then
                    local c, m = fso:readFile( file ) -- c = content or error message
                    if c then
                        if str:is( c ) then
                            before = c
                            metaXml = xml:parseXml( c )
                            rootElem = metaXml[2]
                            if rootElem == nil then
                                app:logError( "Invalid xml file: ^1 - root element is nil - not saving custom metadata for ^2", file, photoPath )
                                break
                            elseif type( rootElem ) ~= 'table' then
                                app:logError( "Invalid xml file: ^1 - root element should be table - not saving custom metadata for ^2", file, photoPath )
                                break
                            elseif rootElem.label ~= 'custom-metadata' then
                                app:logError( "Invalid xml file: ^1 - root element should be named 'custom-metadata', not '^3' - not saving custom metadata for ^2", file, photoPath, ( rootElem.label or 'nil' ) )
                                break
                            else
                                if rootElem.xarg ~= nil then
                                    local arg
                                    for i, v in ipairs( rootElem.xarg ) do -- really should have method for reading attrs ###2
                                        if rootElem.xarg[i].name == 'pluginId' then
                                            arg = rootElem.xarg[i]
                                            break
                                        end
                                    end
                                    if arg then -- a bit presumptious to require it be first.
                                        if arg.text ~= pluginId then
                                            app:logError( "Invalid plugin id, found '^1' but expected '^2'", arg.text, pluginId )
                                            break
                                        else
                                            app:log( "Pre-existing custom metadata file appears to be valid: ^1", file )
                                            populateMetaLookup()
                                        end
                                    else
                                        app:logError( "First attribute of root element must be pluginId, file: ^1", file )
                                        break
                                    end
                                else
                                    app:logError( "Root element has no attributes, file: ^1", file )
                                    break
                                end
                            end
                        else
                            -- do not throw error since one file error should not the whole operation deny...
                            app:logError( "No content in '^1' - you may need to delete it before custom metadata will be saved for '^2'", file, photoPath )
                            break
                        end
                    else
                        -- do not throw error since one file error should not the whole operation deny...
                        app:logError( "Unable to read custom metadata file, error message: ^1 - custom metadata not saved for ^2", m, photoPath ) -- error message includes offending file-path.
                        break
                    end
                else
                    metaXml = xml:parseXml( emptyXml )
                    -- Debug.lognpp( metaXml )
                    rootElem = metaXml[2]
                    metaLookup = {}
                    -- Debug.lognpp( "Virginal root", rootElem )
                    app:log( "Pre-existing custom-metadata file does not exist: ^1", file )
                end
                local metadata = photo:getRawMetadata( 'customMetadata' ) -- all plugins
                for k, v in pairs( metadata ) do
                    if pluginId == nil then
                        addMeta( v )
                    elseif pluginId == v.sourcePlugin then
                        addMeta( v )
                    else
                        -- not saving...
                    end
                end
                local s, t = pcall( xml.serialize, xml, metaXml ) -- throws error if serialization failure
                if s then
                    --app:logVerbose( file )
                    local chg
                    if before then
                        --app:logVerbose( "Before" )
                        --app:logVerbose( before )
                        --app:logVerbose( "After" )
                        --app:logVerbose( t )
                        if before ~= t then
                            chg = true
                        -- else
                        end
                    else
                        --app:logVerbose( "New" )
                        --app:logVerbose( t )
                        chg = true
                    end
                    if chg then
                        local s, m = fso:assureAllDirectories( dir )
                        if s then
                            local s, m = fso:writeFile( file, t )
                            if s then
                                app:log( "Saved custom metadata for ^1 in ^2", photoPath, file )
                            else
                                app:logError( "Unable to save custom metadata for ^1, error message: ^2", photoPath, m ) -- error message contains offencting file path.
                            end
                        else
                            app:logError( "Unable to save custom metadata for ^1, error message: ^2", photoPath, m ) -- error message contains offencting file path.
                        end
                    else
                        app:log( "Custom metadata for ^1 has not changed, not writing ^2", photoPath, file )
                    end
                else
                    app:logError( "Unable to save custom metadata for ^1, error message: ^2", photoPath, t ) -- error message contains offencting file path.
                end
            until true
            if call.scope:isCanceled() then
                call:cancel()
                return
            else
                call.scope:setCaption( str:fmt( "^1 %", string.format( "%2u", ( i * 100 ) / #photos ) ) )
                call.scope:setPortionComplete( i, #photos )
            end
        end
    end } )
end



--- Read (all) custom metadata for specified photos, from disk.
--
--  @usage includes user prompt and the whole nine yards.
--  @usage presently expects files in sibling directory of catalog (named plugin-id), prefixed by photo path.
--  @usage *** there is a similar function for reading from xmp sidecar in custom metadata plugin manager.
--
--  @return status (boolean) true if operation completed without uncaught error - there may have been individual file errors logged.
--  @return message (string) error message if status false.
--
function CustomMetadata:read()
    return app:call( Service:new{ name="Custom Metadata - Read", async=true, guard=App.guardVocal, main=function( call )
        local pluginId = _PLUGIN.id
        local response = self:_promptForMetadataSaveOrRead( call, "Read" )
        if response == nil then
            return
        end
        local photos = response.photos
        local dir = response.dir
        call.scope = LrProgressScope {
            title = "Reading custom metadata",
            functionContext = call.context,
        }
        app:log( "Reading custom metadata for plugin (^2): ^1", pluginId, str:plural( #photos, "photo" ) )
        local metaXml
        local rootElem
        local rawMeta = cat:getBatchRawMetadata( photos, { 'path', 'isVirtualCopy' } )
        local fmtMeta = cat:getBatchFormattedMetadata( photos, { 'copyName' } )
        for i, photo in ipairs( photos ) do
            repeat
                local changes = 0
                local photoPath = rawMeta[photo].path
                local photoFilename = LrPathUtils.leafName( photoPath )
                local isVirtual = rawMeta[photo].isVirtualCopy
                local copyName
                local file
                if isVirtual then
                    copyName = fmtMeta[photo].copyName
                    file = LrPathUtils.child( dir, LrPathUtils.addExtension( str:fmt( "^1 (^2)", photoFilename, copyName ), "vc_custom-metadata.xml" ) ) -- add-extension may take care of character encoding(?)
                else
                    copyName = ""
                    file = LrPathUtils.child( dir, LrPathUtils.addExtension( photoFilename, "custom-metadata.xml" ) ) -- add-extension may take care of character encoding(?)
                end
                app:log( "Considering reading custom metadata for ^1", photoPath )
                if fso:existsAsFile( file ) then
                    local c, m = fso:readFile( file ) -- c = content or error message
                    if c then
                        if str:is( c ) then
                            metaXml = xml:parseXml( c )
                            rootElem = metaXml[2]
                            if rootElem == nil then
                                app:logError( "Invalid xml file: ^1 - root element is nil - not saving custom metadata for ^2", file, photoPath )
                                break
                            elseif type( rootElem ) ~= 'table' then
                                app:logError( "Invalid xml file: ^1 - root element should be table - not saving custom metadata for ^2", file, photoPath )
                                break
                            elseif rootElem.label ~= 'custom-metadata' then
                                app:logError( "Invalid xml file: ^1 - root element should be named 'custom-metadata', not '^3' - not saving custom metadata for ^2", file, photoPath, ( rootElem.label or 'nil' ) )
                                break
                            else
                                if rootElem.xarg ~= nil then
                                    local arg
                                    for i, v in ipairs( rootElem.xarg ) do -- really should have method for reading attrs ###2
                                        if rootElem.xarg[i].name == 'pluginId' then
                                            arg = rootElem.xarg[i]
                                            break
                                        end
                                    end
                                    if arg then -- a bit presumptious to require it be first.
                                        if arg.text ~= pluginId then
                                            app:logError( "Invalid plugin id, found '^1' but expected '^2'", arg.text, pluginId )
                                            break
                                        else
                                            app:logVerbose( "Custom metadata file appears to be valid: ^1", file )
                                        end
                                    else
                                        app:logError( "First attribute of root element must be pluginId, file: ^1", file )
                                        break
                                    end
                                else
                                    app:logError( "Root element has no plugin attribute, file: ^1", file )
                                    break
                                end
                            end
                        else
                            -- do not throw error since one file error should not the whole operation deny...
                            app:logError( "No content in '^1' - you may need to delete it before custom metadata will be saved for '^2'", file, photoPath )
                            break
                        end
                    else
                        -- do not throw error since one file error should not the whole operation deny...
                        app:logError( "Unable to read custom metadata file, error message: ^1 - custom metadata not saved for ^2", m, photoPath ) -- error message includes offending file-path.
                        break
                    end
                else
                    app:log( "Saved custom metadata file does not exist: ^1", file )
                    break
                end
                if #rootElem > 0 then
                    for i, elem in ipairs( rootElem ) do            
                        local id
                        local val
                        local typ
                        for i2, attr in ipairs( elem.xarg ) do
                            if attr.name == 'id' then
                                id = attr.text
                            elseif attr.name == 'value' then
                                val = attr.text
                            elseif attr.name == 'type' then
                                typ = attr.text
                            else
                                app:logVerbose( "Attr '^1' ignored, value: ^2", attr.name, attr.text )
                            end
                        end
                        if id ~= nil then
                            if val ~= nil then -- presently even "nil" values have non-nil value attribute written - type is used to distinquish.
                                if typ ~= nil then
                                    local upd
                                    local value
                                    if typ == 'nil' then
                                        assert( val == 'nil', "val not consistent with typ nil" )
                                        -- app:logVerbose( "Setting ^1 to nil", id )
                                        value = nil -- for emphasis
                                        upd = true
                                    elseif typ == 'string' then
                                        value = val
                                        -- app:logVerbose( "Setting ^1 to string: ^2", id, value )
                                        upd = true
                                    elseif typ == 'number' then
                                        value = num:numberFromString( val )
                                        if value ~= nil then
                                            -- app:logVerbose( "Setting ^1 to number: ^2", id, val )
                                            upd = true
                                        else
                                            app:logWarning( "Can't set ^1 - type is 'number' but value isn't: ^2", id, val )
                                            upd = false
                                        end
                                    elseif typ == 'boolean' then
                                        value = bool:booleanFromString( val )
                                        if value ~= nil then
                                            upd = true
                                            -- app:logVerbose( "Setting ^1 to boolean: ^2", id, val )
                                        else
                                            upd = false
                                            app:logWarning( "Can't set ^1 - type is 'boolean' but value isn't: ^2", id, val )
                                        end
                                    end
                                    assert( upd ~= nil, "upd must be set" )
                                    if upd then
                                        local s, m = self:update( photo, id, value, nil, true, 20 ) -- version=nil, no-throw=true, 20 tries.
                                        if s ~= nil then -- definitive
                                            if s then
                                                app:logVerbose( "'^1' changed from '^2' to '^3'", id, str:to( m ), str:to( value ) )
                                                changes = changes + 1
                                            else
                                                -- not changed.
                                            end
                                        else
                                            app:logError( m )
                                        end
                                    -- else warning logged
                                    end
                                else
                                    app:logWarning( "No type for ^1, value is '^2'", id, val )
                                end
                            else
                                app:logWarning( "No value for '^1'", id )
                            end
                        else
                            app:logWarning( "No id attr" )
                        end
                    end
                    app:log( "^1 changed.", str:plural( changes, "metadata item", true ) )
                else
                    app:logWarning( "No custom metadata items for '^1' are present in '^2'", photoPath, file )
                end
            until true
        end
    end } )
end



--- Consolidate custom metadata for specified plugin into a lookup table (dictionary) form.
--
--  @param photo (LrPhoto, required) photo
--  @param pluginId (string, required) plugin id.
--  @param cMeta - (table, optional) batch of raw metadata including custom metadata for all plugins.
--
--  @return table - id/value members, or empty - never nil.
--
function CustomMetadata:getMetadata( photo, pluginId, cMeta )
    local r = {}
    if cMeta then
        local meta = cMeta[photo]
        if meta then -- custom metadata is available for specified photo - all plugins, 
            local t = meta.customMetadata or error( "No custom metadata for photo." )
            for k, v in pairs( t ) do
                local plugin = LrPathUtils.removeExtension( k )
                if plugin == pluginId then
                    local id = LrPathUtils.extension( k )
                    r[id] = v -- skip over plugin id and '.'
                end
            end
            return r
        -- else fall-through
        end
    end
    if not cMeta then
        cMeta = photo:getRawMetadata( 'customMetadata' ) -- note: different format than above-mentioned c-meta.
    end
    if cMeta then
        for i, t in ipairs( cMeta ) do
            if t.sourcePlugin == pluginId then
                r[t.id] = t.value
            end
        end
    -- else - it's possible a photo has no custom metadata, in which case nil may be returned instead of empty table.
    end
    return r
end



--- Gets an array of custom metadata specs, from Metadata.lua
--
--  @param      reread      (boolean, default=false) force re-read.
--
--  @usage      Initialized upon first use, or a forced re-read..<br>
--              (maybe should have made whole provider return-table available, oh well - not needed yet.
--
--  @return     array of metadata fields for photos, or nil. For format of reply, see Metadata.lua.
--  @return     excuse string (if first return value is nil).
--
function CustomMetadata:getMetadataSpecs( reread )
    if reread or not self.metadataFieldsForPhotos then
        local metaFilename = app:getInfo( 'LrMetadataProvider' )
        if metaFilename == nil then
            return nil
        end
        local metaFile = LrPathUtils.child( _PLUGIN.path, metaFilename )
        if not fso:existsAsFile( metaFile ) then
            return nil, "Metadata file missing: " .. metaFile
        end
        local s, d = pcall( dofile, metaFile )
        if s then
            app:logV( "re-read ^1 to get metadata specs.", metaFile )
        else
            return nil, d
        end
        self.metadataFieldsForPhotos = d.metadataFieldsForPhotos -- this member name is fixed by Lightroom proper.
    end
    return self.metadataFieldsForPhotos
end



--- Copy selected metadata values from most selected photo to the other selected photos.
--
function CustomMetadata:manualSync()
    app:call( Service:new{ name="Custom Metadata Manual Sync", async=true, guard=App.guardVocal, main=function( call )
    
        call.nUpdated = 0
        call.nAlreadyUpToDate = 0
    
        local pluginId = _PLUGIN.id
    
        if not _PLUGIN.enabled then
            app:show{ warning="Plugin must be enabled in plugin manager (hint: 'Enable' button in 'Status' section)." }
            call:cancel()
            return nil
        end
            
        local photos = cat:getSelectedPhotos()
        local dir = LrPathUtils.child( LrPathUtils.parent( catalog:getPath() ), _PLUGIN.id )
        if photos == nil or #photos < 2 then
            app:show{ warning="Select two or more photos first." }
            call:cancel()
            return nil
        end
        local mostSelPhoto = catalog:getTargetPhoto()
        local mo = self:getMetadata( mostSelPhoto, _PLUGIN.id )
        local errm
        if self.specs == nil then
            self.specs, errm = self:getMetadataSpecs()
        end
        local me = self.specs
        
        if me == nil then
            if errm then
                app:show{ error="Error reading metadata spec file: ^1", errm }
            else
                app:show{ warning="No metadata specified." }
            end
            call:cancel()
            return
        end
                
        local props = LrBinding.makePropertyTable( call.context )
        
        
        local viewItems = {}
        
        viewItems[#viewItems + 1] =
            vf:static_text {
                title = str:fmt( "Copy custom metadata from ^1 to the other ^2?", mostSelPhoto:getFormattedMetadata( 'fileName' ), str:plural( #photos - 1, "selected photo", true ) ),
            }
        viewItems[#viewItems + 1] = vf:spacer { height = 20 }

        local c = 0        
        for i, v in ipairs( me ) do
            c = c + 1
            props[v.id] = false
            viewItems[#viewItems + 1] = vf:checkbox {
                bind_to_object = props,
                title = v.title,
                value = bind( v.id ),
            }
        end
        if c == 0 then
            app:show{ warning="No metadata" }
            call:cancel()
            return
        end
        
        local accItems = {}
        accItems[#accItems + 1] =
            vf:row {
                vf:push_button {
                    title = 'Check All',
                    action = function()
                        for i, v in ipairs( me ) do
                            props[v.id] = true
                        end
                    end,
                },
                vf:push_button {
                    title = 'Check None',
                    action = function()
                        for i, v in ipairs( me ) do
                            props[v.id] = false
                        end
                    end,
                },
            }
                    
        
        local args = { title=app:getAppName() .. " - manual sync" }
        args.contents = vf:view( viewItems )
        args.accessoryView = vf:row( accItems )
        local answer = LrDialogs.presentModalDialog( args )
        
        if answer == 'cancel' then
            call:cancel()
            return
        end
        
        call.scope = LrProgressScope {
            title = "Syncing custom metadata",
            functionContext = call.context,
        }
        app:log( "Copying custom metadata ^1", pluginId, str:plural( #photos, "photo" ) )
        
        local s, m = cat:updatePrivate( 20, function( context, phase )
            local i1 = ( phase - 1 ) * 1000 + 1
            local i2 = math.min( phase * 1000, #photos )
            for i = i1, i2 do
                repeat
                    local photo = photos[i]
                    if photo == mostSelPhoto then -- doesn't hurt to update most-sel photo too, but it bothers me.
                        break
                    end
                    for k, v in props:pairs() do
                        if v then
                            local chg, errm = custMeta:update( photo, k, mo[k], nil, true )
                            if chg == nil then
                                app:logErr( errm or "unknown error occurred" )
                            elseif chg then
                                call.nUpdated = call.nUpdated + 1
                            else
                                call.nAlreadyUpToDate = call.nAlreadyUpToDate + 1
                            end
                        end
                    end
                until true
            end
            if i2 < #photos then
                return false -- continue to next phase, not done yet.
            end
        end )
        
        if not s then
            app:error( m )
        end
    
    end, finale=function( service, status, message )
        if status and not service:isCanceled() then
            app:show{ info="^1 updated, ^2 already up to date.", subs = { str:plural( service.nUpdated, "field", true ), service.nAlreadyUpToDate }, actionPrefKey = 'Stats for manual sync' }
        end
    end } )
end



return CustomMetadata
