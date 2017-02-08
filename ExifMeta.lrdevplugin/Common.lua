--[[
        Common.lua
        
        Namespace shared by more than one plugin module.
        
        This can be upgraded to be a class if you prefer methods to static functions.
        Its generally not necessary though unless you plan to extend it, or create more
        than one...
--]]

local Common, dbg, dbgf = Object.register( "Common" )



--- Determine if metadatabase item should be shown, given filter.
--
--  @param      t       (table, required) metadatabase item formed into a table.
--  @param      filter  (table, required) could easily have been optional, but is being checked externally.
-- 
function Common.isToShow( t, filter )
    if not filter.showHidden and t.hide then
        return false
    end
    if not filter.field then
        return true
    end
    local show
    if filter.field == 'ID' then
        show = ( t.id:find( filter.value, 1, not filter.regex ) ~= nil )
    elseif filter.field == 'Name' then
        show = ( t.name:find( filter.value, 1, not filter.regex ) ~= nil )
    elseif filter.field == 'Included' then
        show = t.include
    elseif filter.field == 'Interesting' then
        -- band-aid for string/num compare error.
        local fv
        local enc
        if type( filter.value ) == 'string' then
            fv = tonumber( filter.value )
        end
        if type( t.encounters ) == 'string' then
            enc = tonumber( t.encounters )
        end
        if enc ~= nil and fv ~= nil then
            show = ( enc > fv )
        else
            return false
        end
    elseif filter.field == 'New' then
        show = t.new
    else
        app:setPref( 'filterField', "No Filter" )
    end
    if filter.invert then
        return not show
    else
        return show
    end
end



--- Set the include flag for existing exif pref.
--
--  @param      id      (string, required) tag id
--  @param      value   (boolean, required) value to set.
--
--  @usage      presently just sets the global pref for include member, and clears the hide field in case it would otherwise be set too.
--  @usage      does not set property being displayed - that must be assured externally.
--
function Common.setInclude( id, value )
    Common.updateExifPrefField( id, 'include', value )
    if value then
        Common.updateExifPrefField( id, 'hide', false )
    end
end



--- Set the hide flag for existing exif pref.
--
--  @param      id      (string, required) tag id
--  @param      value   (boolean, required) value to set.
--
--  @usage      presently just sets the global pref for hide member, and clears the include field in case it would otherwise be set too.
--  @usage      does not set property being displayed - that must be assured externally.
--
function Common.setHide( id, value )
    Common.updateExifPrefField( id, 'hide', value )
    if value then
        Common.updateExifPrefField( id, 'include', false )
    end
end



--  Sort array of id keys by encounter count (most encounters first).
--
function Common._sortByEncounters( keys, tbl )
    local function sort( one, two )
        if tbl[one].encounters > tbl[two].encounters then
            return true
        else
            return false
        end    
    end
    table.sort( keys, sort )
end



--  Sort array of id keys by name (alphabetically ascending).
--
function Common._sortByName( keys, tbl )
    local function sort( one, two )
        if tbl[one].name < tbl[two].name then
            return true
        else
            return false
        end    
    end
    table.sort( keys, sort )
end



--  Sort metadatabase items according to prefs, filter while at it.
--
--  @return     iterator    (function) that returns pairs:
--              <br>id      (string) db id
--              <br>item    (table) metadatabase item table corresponding to id (constructed from pref elems).
--
function Common.sortedPairs( filter )

    local tbl = {}
    local t
    local seen = {}
    local keys = {}
    local sortField = app:getPref( 'sortField' )

    local p1, p2, id    

    for n, v in app:getGlobalPrefPairs() do
        repeat
            p1, p2 = n:find( "{emid}_", 1, true )
            if p1 == nil then
                break
            end
            id = n:sub( p2 + 1 )
            if seen[id] then
                break
            else
                seen[id] = true
            end
            local t = Common.getExifPrefTable( id )
            if not t then
                app:logWarning( "Can not find exif metadata table in preferences for id: " .. str:to ( id ) )
                break
            end
            
            if not filter or Common.isToShow( t, filter ) then
                if tbl[id] == nil then
                    -- dbg( #keys, "id", id )
                    keys[#keys + 1] = id
                    tbl[id] = t
                else
                    error( "cant be more than one table for same ID" )
                end
            -- else - no longer bothering to keep stuff not being shown.
            end
        until true
    end

    table.sort( keys ) -- always sorted first by ID
            
    if sortField == 'id' then
        -- done
    elseif sortField == 'encounters' then
        Common._sortByEncounters( keys, tbl )
    elseif sortField == 'name' then
        Common._sortByName( keys, tbl )
    elseif sortField == 'include' then
        local newKeys = {}
        for i, id in ipairs( keys ) do
            if tbl[id].include then
                newKeys[#newKeys + 1] = id
            end
        end
        for i, id in ipairs( keys ) do
            if not tbl[id].include then
                newKeys[#newKeys + 1] = id
            end
        end
        keys = newKeys
    elseif sortField == 'hide' then
        local newKeys = {}
        for i, id in ipairs( keys ) do
            if tbl[id].hide then
                newKeys[#newKeys + 1] = id
            end
        end
        for i, id in ipairs( keys ) do
            if not tbl[id].hide then
                newKeys[#newKeys + 1] = id
            end
        end
        keys = newKeys
    else
        error("sort order not implemented" )
    end
    
    
    local index = 0
    
    return function()
        index = index + 1
        local key = keys[index]
        if key ~= nil then
            --assert( tbl[key], "no tbl for key: " .. key )
            --assert( tbl[key].id, "no tbl id for key: " .. key )
            --assert( tbl[key].id == key, str:fmt( "key/id mismatch, index: ^1, key: ^2, tbl-id: ^3", index, key, tbl[key].id ) )
            return key, tbl[key]
        else
            return nil, nil
        end
    end

end



--- Saves new exif table in preferences.
--
--  @param      id      (string, required) item id.
--  @param      t       can be an entire table (in case of new metadata), or just selected fields for setting (make sure base table already exists).
--
--  @usage      presently only being used for initial storage of whole table (less the 'new' field which is set further down the road).
--
function Common.setExifPrefTable( id, t )

    app:setGlobalPref( "{emid}_" .. id, true )
    for k, v in pairs( t ) do
        app:setGlobalPref( "{em}_" .. id .. '_' .. k, v )
    end

end



--  *** save for posterity: not presently used - updates are field-wise.
--  Updates specified fields in existing pref table.
--
--  @param      id      (string, required) item id.
--  @param      t       can be an entire table (in case of new metadata), or just selected fields for setting (make sure base table already exists).
--
--  @usage      t can be an entire table, or just selected fields for updating (make sure base table already exists).
--
function Common.updateExifPrefTable( id, t )
    for k, v in pairs( t ) do
        Common.updateExifPrefField( id, k, v )
    end  
end



--- Gets entire exif table from preferences.
--
--  @param      id      (string, required) item id.
--
--  @usage      Presently only called by sorted-pairs iterator.
--
--  @return     t       whole metadata item table, or nil if none corresponds to specified id.
--
function Common.getExifPrefTable( id )

    local t = {}

    local exists = app:getGlobalPref( "{emid}_" .. id )
    if exists then
        t.id = id -- id in prefs is now boolean.
        t.include = app:getGlobalPref( "{em}_" .. id .. '_include' )
        t.encounters = app:getGlobalPref( "{em}_" .. id .. '_encounters' )
        t.prev = app:getGlobalPref( "{em}_" .. id .. '_prev' )
        t.name = app:getGlobalPref( "{em}_" .. id .. '_name' )
        t.hide = app:getGlobalPref( "{em}_" .. id .. '_hide' )
        t.new = app:getGlobalPref( "{em}_" .. id .. '_new' )
    else
        return nil
    end

    return t

end



--- Get one field of exif table from preferences.
--
--  @param      id      (string, required) item id.
--  @param      fld     (string, required) fld to get.
--
--  @usage      Its fast to get fields.
--
function Common.getExifPrefField( id, fld )
    return app:getGlobalPref( "{em}_" .. id .. '_' .. fld )
end



--- Uupdate one field of existing exif table in preferences.
--
--  @param      id      (string, required) item id.
--  @param      fld     (string, required) fld to set.
--  @param      val     (any, required) value to set - type preserved in prefs.
--
--  @usage      Use for setting one or two fields, otherwise prefer save-exif-pref-table - either can be used for updating pre-existing table.
--  @usage      Because setting is so much more time consuming than getting, it pays to get previous field value and make sure its changed.
--
function Common.updateExifPrefField( id, fld, val )
    local nm = "{em}_" .. id .. '_' .. fld
    local prev = app:getGlobalPref( nm )
    if prev ~= val then
        app:setGlobalPref( nm, val )
    end
end



--- Set one field of existing exif table in preferences.
--
--  @param      id      (string, required) item id.
--  @param      fld     (string, required) fld to set.
--  @param      val     (any, required) value to set - type preserved in prefs.
--
--  @usage      Previous value doesnt matter.
--  @usage      Because setting is so much more time consuming than getting, it pays to get previous field value and make sure its changed.
--              <br>this method for case when that has already been assured externally.
--
function Common.setExifPrefField( id, fld, val )
    local nm = "{em}_" .. id .. '_' .. fld
    app:setGlobalPref( nm, val )
end



--- Mark and/or clear new flag for all exif meta.
--
--  @usage      slowish at first, but will be fast after a while when no new items are being found.
--
function Common.markNew( new )

    for id, t in Common.sortedPairs() do
        assert( id == t.id, "id mismatch" )

        if new[id] then
            Common.updateExifPrefField( id, 'new', true )
        else
            Common.updateExifPrefField( id, 'new', false )
        end
        
    end
end



--- Default version of table-to-string func, which can be overridden by preference function.
--  @param params named parameter table, members include: xmlTbl (table of values in proprietary format) - required; delim (default = " | ").
--  @return string representation of values, typically comma-separated text values (return nil and no errm to skip without warning)..
--  @return errMsg if no can do..
local function tableToString_default( params )
    local delim = params.delim or error( "no delim" ) -- default before calling.
    local xmlTbl = params.xmlTbl or error( "no xml table" )
    local b = {} -- buf
    for i, v in ipairs( xmlTbl ) do
        local value = v[1]
        local typ = type( value )
        if typ == 'string' then
            b[#b + 1] = value
        elseif typ ~= 'table' then -- won't be a function.
            b[#b + 1] = tostring( value ) -- should be usable, e.g. number.
        else -- table
            return nil -- skip table of tables - not implemented, yet.
        end
    end
    return table.concat( b, delim )
end



---     Synopsis:           Parse exiftool -l -X output into a table.
--<br>      
--<br>      Notes:              to use:
--<br>                          if metadata-enabled then
--<br>                              get-metadata from photo
--<br>                              if metadata-from-photo not equal to metadata-from-file (same key) then
--<br>                                  save photo to-do item as update function.
--<br>      
--<br>      Returns:            meta-tbl, errm
--<br>      
--<br>                          table output format:
--<br>                              key:   GroupDerivation_NameDerivation
--<br>                              value(array): UI Name, value for photo
--<br>      
function Common._getFormattedExif( photo, exifPath, photoPath, tbl )

    local id, idpfx, nmpfx, errm
    
    local exeCmd
    local exeFile = app:getGlobalPref( 'exifToolExe' )
    local sep = app:getPref{ name='tableToStringDelimiter', default=" | " } -- string.
    local tableToString = app:getPref{ name='tableToString', default=tableToString_default } -- default is separated values.
    if str:is( exeFile ) then
        app:logVerbose( "Using custom configured exiftool: ^1", exeFile )
    else
        if WIN_ENV then
            exeFile = LrPathUtils.child( _PLUGIN.path, "exiftool.exe" )
        elseif MAC_ENV then
            exeFile = LrPathUtils.child( _PLUGIN.path, "exiftool" )
        else
            error( "invalid environment" ) -- never happens.
        end
        if fso:existsAsFile( exeFile ) then
            app:logVerbose( "Using built-in exiftool - if not working: try installing your own and browse to it in plugin manager." ) -- path comes in command below.
        else
            app:error( "Exiftool must either exist in .lrplugin folder (^1), or be configured with the absolute path to executable file in plugin manager.", exeFile )
        end
    end
    local sts, cmdOrMsg, data = app:executeCommand( exeFile, "-l -X", { photoPath }, exifPath, 'del' ) -- use 'get' to return response without deleting output file.
    if sts then
        app:logVerbose( "Exif obtained by command: " .. cmdOrMsg )
    else
        return nil, "Error executing command: " .. str:to( cmdOrMsg )
    end

    local xtbl = xml:parseXml( data )

    local goodStuff = xtbl[2][1]
    
    local getNameAndValue = app:getPref{ name='getNameAndValue', default=function( params ) -- expected-type now comes from default.
        return params.name, params.value
    end }

    local make = photo:getFormattedMetadata( 'cameraMake' ) or "unknown make"
    local model = photo:getFormattedMetadata( 'cameraModel' ) or "unknown model"
    local make5 = make:sub( 1, 5 ) -- no error if make is shorter than 5.
    local make5L = LrStringUtils.lower( make5 )
    
    for i = 1, #goodStuff do
    
        repeat
    
            local stuff = goodStuff[i]
            -- _debugTrace( "stf: ", stuff )
            
            local label = stuff.label -- for messages
            local group = stuff.ns
            local compName = stuff.name
            
            if not str:is( group ) or not str:is( compName ) then
                -- _debugTrace( "no group or compName, label: ", str:to( label ) )
                break
            end
            
            -- local text = stuff[1] or ''
            
            local child_1 = stuff[1]
            local child_2 = stuff[2]
            -- local child_3 = stuff[3]
    
            local friendlyName
            local text
            
            if child_1 and child_2 then
                friendlyName = child_1[1]
                text = child_2[1]
            else
                -- _debugTrace( "no child1 or child2, label: ", str:to( label ) )
                break
            end
            
            if friendlyName == nil or type (friendlyName ) ~= 'string' or #friendlyName == 0 then
                -- _debugTrace( "friendly name funky, label: ", str:to( label ) )
                break
            end
            
            if text == nil then
                -- _debugTrace( "text value nil, label: ", str:to( label ) )
                text = ''
            elseif type( text ) == 'string' then
                -- proceed
            elseif type( text ) == 'table' then
                -- _debugTrace( "text value not string, label: ", str:to( label ) )
                if tableToString then
                    text = tableToString {
                        xmlTbl = text, -- text is table of parsed xml (not ideal to pass to user func, but it's the best I got without massive rewriting).
                        delim = sep,
                    }
                    if text ~= nil then
                        if type( text ) == 'string' then
                            -- process it, even if empty.
                        else
                            app:logE( "bad table formatting, should be string not ^1", type( text ) )
                            break
                        end
                    else
                        break -- if nothing returned, nothing processed..
                    end
                else
                    break -- skip
                end
            else -- hmm..
                Debug.lognpp( "text value not string nor table, label: ", str:to( label ), text )
                Debug.pause( "see debug log file" )
            end
            
            local bin = text:find( '(Binary', 1, true )
            if bin and bin == 1 then
                -- _debugTrace( "binary, label: ", str:to( label ) )
                break -- ignore binary metadata
            end
            
            -- assure first char is a letter.
            local firstLetter = group:find( "%a" )
            if firstLetter == nil then
                app:logInfo( "Ignoring group with no letters: " .. group )
                break
            elseif firstLetter == 1 then
                -- ok as is
            else
                group = group:sub( firstLetter )
                if str:is( group ) then
                    -- ok now
                else
                    app:logInfo( "Ignoring strange group: " .. group )
                    break
                end
            end
                
            id = LOC( "$$$/X=^1_^2", string.gsub( group, "[^%w_]", "" ), string.gsub( compName, "[^%w_]", "" ) ) -- must be letters, numbers, & underscores only (starting with a letter),
                -- to be usable as a pref ID.
            local name, value = getNameAndValue {
                photo = photo,
                make = make,
                model = model,
                make5 = make5,
                make5L = make5L,
                id = id,
                name = friendlyName,
                value = text,
            }
            if str:is( name ) then
                tbl[id] = { name, value }
            else
                dbgf( "No name for ^1", friendlyName )
            end
        until true
    end
        
    return true
    
end



---     Synopsis:           Processes one metadata value read from exiftool output file.
--<br>      
--<br>      Notes:              - only called if preference set.
--<br>                          - important side-effect: adds a function to the "call.todo" list if photo metadata needs updating.
--<br>                          
--<br>      Returns:            nothing
--
function Common._processValue( photo, id, _value, call )

    assert( id ~= nil, "no id" )
    if _value == nil then return end

    local value, errMsg = photo:getPropertyForPlugin( _PLUGIN, id, nil, true ) -- nil => no version, true => dont throw error - chould catch error
    -- so I could distinquish between no value set and item does not exist - presently the course of action is the same so it does not matter.
    if not errMsg and (value ~= _value) then
        call.todo[#call.todo + 1] = function()
            --dbg( "call.todo - update, id: ", id .. ", from: " .. str:to( value ) .. ", to: " .. str:to( _value ) )
            photo:setPropertyForPlugin( _PLUGIN, id, _value ) -- shouldn't be an error since we just got the property, as long as we have catalog access.
        end
    elseif errMsg then
        app:logWarning( "Not updating due to error getting property, id: " .. id .. ", from: " .. str:to( value ) .. ", to: " .. str:to( _value ) .. ", err-msg: " .. str:to( errMsg ) .. " - generally this means you need to return to the plugin manager and commit inclusions." )
    else
        -- app:logVerbose( "Not updating since value has not changed, id: ", id .. ", from: " .. str:to( value ) .. ", to: " .. str:to( _value ) )
    end
    
end



---     Synopsis:           Adds exif-table to metadatabase.
--<br>      
--<br>      Notes:              saves corresponding database and metadata-definition in prefs.
--<br>      
--<br>      Returns:            nNew
--
function Common._processExifTable( photo, exifTbl, call, new ) -- ###3 raw-meta?

    local photoPath = photo:getRawMetadata( 'path' ) -- ###3 raw-meta?
    local nNew = 0

    for id, tbl in pairs( exifTbl ) do
    
        assert( id ~= nil, "no id" )
    
        local name = tbl[1] or "{NO NAME}" -- so far the "no-name" hasnt happened that I know of, it was because of some problem I put it in, but no reason to take it out, I dont think.
        local value = tbl[2] -- generally not nil, although theoretically it could be.
        
        local t_id = Common.getExifPrefField( id, "id" )
        
        if t_id == nil then -- first time
            app:logInfo( str:fmt( "New metadata found in ^1, id: ^2, name: ^3, value: ^4", photoPath, id, name, str:to( value ) ) )
            new[id] = true
            nNew = nNew + 1
            local t = {
                id = id,
                include = false,
                encounters = 1,
                name = name,
                hide = false,
                prev = value,
            }
            Debug.lognpp( "Setting new table to global prefs", t )
            Common.setExifPrefTable( id, t )
        else
            assert( id == t_id, "id mismatch" )
            local t_prev = Common.getExifPrefField( id, "prev" )
            if value ~= t_prev then
                local t_encounters = Common.getExifPrefField( id, 'encounters' )
                if t_encounters ~= nil then
                    t_encounters = t_encounters + 1
                    Common.setExifPrefField( id, 'encounters', t_encounters )
                    Common.setExifPrefField( id, 'prev', value )
                    Debug.lognpp( "Updating previously encountered value in global prefs", id, value, t_encounters )
                else
                    app:logWarning( "Previous value field exists, but encounters field is missing" )
                    Common.setExifPrefField( id, 'encounters', 1 )
                    Common.setExifPrefField( id, 'prev', value )
                end
            else
                Debug.lognpp( "Updating encountered table in global prefs (same value)", id, value )
            end
            local t_include = Common.getExifPrefField( id, 'include' )
            if t_include then
                Common._processValue( photo, id, value, call ) -- returns nothing: doesn't do anything except add a function to-do.
            else
                -- not being included, so...
            end
        end
    end
    return nNew
end




--- Update one photo's exif metadata.
--
--  @param      photo (lr-photo, required) the photo to update.
--  @param      call (call or service, required) the call object wrapper.
--  @param      new (array, required) for appending newly discovered metadata items.
--
--  @usage      throws error if problems
--
--  @return     nNew - number of new items discovered.
--
function Common.updatePhoto( photo, call, new, force, bg ) -- ###3 raw-meta? ets

    app:callingAssert( force ~= nil, "force-flag is mandatory boolean, not nil." )

    local photoPath = photo:getRawMetadata( 'path' ) -- ###3 raw-meta?
    local fmt = photo:getRawMetadata( 'fileFormat' ) -- ###3 raw-meta?
    if not LrFileUtils.exists( photoPath ) then
        call.nMissing = call.nMissing + 1
        return 0
    end
    if not force then
        local lastUpdate, msg = photo:getPropertyForPlugin( _PLUGIN, 'lastUpdate_', nil, true )
        if msg then
            error( str:fmt( "Unable to obtain last update time for ^1 (you may need to enable plugin), error message: ^2", photoPath, str:to( msg ) ) )
        end
        lastUpdate = tonumber( lastUpdate or 0 )
        local lastUpdateStr, msg = photo:getPropertyForPlugin( _PLUGIN, 'lastUpdate', nil, true )
        if msg then
            error( str:fmt( "Unable to obtain formatted update time for ^1, error message: ^2", photoPath, str:to( msg ) ) )
        end
        
        local metaDefTime = app:getGlobalPref( 'metaDefTime_' )
        assert( metaDefTime ~= nil, "meta-def-time not init" )
        
        if metaDefTime ~= 0 and metaDefTime < lastUpdate and str:is( lastUpdateStr ) then
            call.nAlreadyUpToDate = call.nAlreadyUpToDate + 1
            if not call.autoUpdate then
                app:logVerbose( "Metadata already up to date: ^1", photoPath ) -- too much when auto-update.
            end
            return 0
        end
    end
    -- Note: Update needs to run even if meta-def-time is nil, otherwise user has to commit nothing before database can be populated.
    
    call.todo = {} -- to-do functions for this photo.

    local exifFileName = str:getBaseName( photoPath ) .. ".exif-meta.xml" -- best if not same suffix as nx-tooey.
    local exifDir
    local exifTempDir = app:getPref( 'exifTempDir' )
    if str:is( exifTempDir ) then
        if LrPathUtils.isAbsolute( exifTempDir ) then
            if fso:existsAsDir( exifTempDir ) then
                app:logVerbose( "using custom temp dir for exiftool output" ) -- dir is evident by command executed
                exifDir = exifTempDir
            else
                app:logError( "temp dir specified absolutely does not exist (^1) - dir for exiftool output is defaulting to same as photo", exifDir )
            end
        else
            exifDir = LrPathUtils.getStandardFilePath( exifTempDir )
            if fso:existsAsDir( exifDir ) then
                app:logVerbose( "using custom temp dir specified as '^1' for exiftool output", exifTempDir ) -- dir is evident by command executed
            else
                app:logError( "temp dir specified as standard file path name does not exist (^1) - dir for exiftool output is defaulting to same as photo", exifTempDir )
            end
        end
    else
        app:logVerbose( "temp dir for exiftool output is defaulting to same as photo" )
    end
    if exifDir == nil then
        exifDir = LrPathUtils.parent( photoPath )
    end
    local exifPath = LrPathUtils.child( exifDir, exifFileName )
    if fso:existsAsFile( exifPath ) then -- this file is deleted when op completes, but if op hangs, it'll be locked - best to keep the ball rolling...
        LrFileUtils.delete( exifPath )
        LrTasks.yield()
        if fso:existsAsFile( exifPath ) then
            app:logW( "File is locked / cannot delete: '^1' - consider deleting manually after computer restarted or lock released.", exifPath )
            exifPath = LrFileUtils.chooseUniqueFileName( exifPath )
        end
    end
    local exifTbl = {}
    local targets = {}
    local xmpSpec = app:getPref( 'xmpHandling' ) or 'rawOnly'
    if fso:existsAsFile( photoPath ) then
        if fmt == 'RAW' then
            if xmpSpec == 'rawOnly' then
                targets = { photoPath }
            else
                local xmpPath = LrPathUtils.replaceExtension( photoPath, 'xmp' )            
                if fso:existsAsFile( xmpPath ) then
                    if xmpSpec == 'rawPri' then
                        targets = { xmpPath, photoPath }
                    elseif xmpSpec == 'xmpPri' then
                        targets = { photoPath, xmpPath }
                    elseif xmpSpec == 'xmpOnly' then
                        targets = { xmpPath }
                    else
                        app:error( "Invalid value for xmp handling" )
                    end
                else
                    -- Could make a fuss, or not...
                    targets = { photoPath }
                end
            end
        else
            targets = { photoPath }
        end
    else
        if fmt == 'RAW' then
            local xmpPath = LrPathUtils.replaceExtension( photoPath, 'xmp' )
            if fso:existsAsFile( xmpPath ) then
                app:logWarning( "Raw photo is missing (^1), but xmp sidecar is present: ^2", photoPath, LrPathUtils.leafName( xmpPath ) )
                return 0
            else
                app:logWarning( "Raw photo is missing (^1), no xmp sidecar either: ^2", photoPath, LrPathUtils.leafName( xmpPath ) )
                return 0
            end
        else
            app:logWarning( "Photo is missing (^1)", photoPath )
            return 0
        end
    end
    for i, path in ipairs( targets ) do
        app:log( path )
        local sts, errm = Common._getFormattedExif( photo, exifPath, path, exifTbl ) -- deletes temp files.
        if sts then
            Debug.lognpp( exifTbl )
        else
            -- app:logError( "no exif table, error message: " .. str:to( errm ) )
            app:error( "Unable to get formatted exif metadata from file (^1), error message: ^2", path, str:to( errm ) )
        end
    end
    local nNew = Common._processExifTable( photo, exifTbl, call, new )
    if nNew > 0 then
        app:logWarning( str:fmt( "^1 discovered in ^2. Return to plugin manager and select additional metadata for inclusion, if desired - you will need to reload the plugin afterward, and run update on this(these) photos again.", str:plural( nNew, "new metadata item" ), photoPath ) )
    else
        app:logVerbose( "No new metadata in " .. photoPath )
    end
    
    -- update at least the date, even if nothing else to-do.
    local updateCatalog = function() -- context & phase not used.
        if #call.todo then
            for i,v in ipairs( call.todo ) do
                v()
            end
        end
        local time = LrDate.currentTime()
        photo:setPropertyForPlugin( _PLUGIN, 'lastUpdate_', time )
        photo:setPropertyForPlugin( _PLUGIN, 'lastUpdate', date:formatDateTime( time ) )
        if app:getGlobalPref( 'bigBlock' ) then -- this means big-block "should" be there *after* a reload or restart...
            local buf = {}
            for k,v in tab:sortedPairs( exifTbl ) do -- sorted alphabetically by ID.
                buf[#buf + 1] = str:fmt( "^1:    ^2", v[1], v[2] )
            end
            if #buf > 0 then
                local bb = table.concat( buf, '\r\n' ) -- CR/LF is ignored in read-only fields and really makes Lightroom wonky when there are really long fields.
                local worked, orNot = custMeta:update( photo, 'bigBlock', bb, nil, true ) -- take any version, but dont throw error if problem. in: 24/Aug/2011 16:40
                -- note: this is the debue for this method (first use). Could be retrofitted elsewhere...
                if worked then
                    -- metadata updated.
                elseif orNot then -- error encountered attempting update.
                    app:logError( "Unable to update big-block of exif metadata, perhaps plugin needs to be reloaded (Windows), or Lightroom needs to be restarted (Mac), error message: " .. orNot )
                else
                    -- metadata unchanged.
                end
                -- photo:setPropertyForPlugin( _PLUGIN, 'bigBlock', bb ) - has potential for error if big-block pref set but plugin not reloaded. out: 24/Aug/2011 16:40
            end
        end
        if #call.todo > 0 then
            call.nChanged = call.nChanged + 1
            app:logInfo( str:fmt( "^1 metadata changes updated: ^2", #call.todo, photoPath ) )
        else
            call.nUnchanged = call.nUnchanged + 1
            app:logVerbose( "Metadata unchanged: " .. photoPath )
        end
        -- done.
    end
    if catalog.hasPrivateWriteAccess then -- multi-update.
        updateCatalog()
    else
        local tries
        if bg then
            tries = 1
        else
            tries = 20
        end
        local yes, no = cat:updatePrivate( tries, updateCatalog ) -- Changed to single try if bg task @16/Sep/2013 4:07 - hope it works.
        if yes then
            app:logInfo( "Updated photo: " .. photoPath )
        else
            -- app:logInfo( "Photo not updated, error message: " .. str:to( no ) )
            error( "Photo not updated, error message: " .. str:to( no ) )
        end
    end
    
    return nNew
    
end



---     Synopsis:           Updates exif metadata for selected photos.
--<br>      
--<br>      Notes:              Errors occuring in update-photo function are trapped and presented generally to the user, who can chooses to keep going or toss in the towel.
--<br>      
--<br>      Returns:            Nothing.
--
function Common.updatePhotos( call, new, force )

    local pcallStatus, nNewOrErrMsg
    local nNew
    local errm
    local enough
    local nToDo

    -- Note: update-func is called from Lightroom context, and critical variables must be in local function context.
    local photos = call.photos
    assert( photos and #photos > 1, "bad call" ) -- call single photo updater if only one photo.
    local limit = 1000
    local progressScope = call.scope
    nToDo = #photos
    
    local rawMeta = cat:getBatchRawMetadata( photos, { 'path' } )
    
    local updateFunc = function( context, phase )
        local i1 = ( phase - 1 ) * limit + 1
        local i2 = math.min( phase * limit, nToDo )
        app:logVerbose( "Updating photos from ^1 to ^2", i1, i2 )
        local yc = 0
        for i = i1, i2 do
            local photo = photos[i]
            local photoPath = rawMeta[photo].path
            pcallStatus, nNewOrErrMsg = LrTasks.pcall( Common.updatePhoto, photo, call, new, force )
            if pcallStatus then
                nNew = nNewOrErrMsg
                call.totalNew = call.totalNew + nNew
                app:setGlobalPref( 'new', call.totalNew )
                progressScope:setCaption( str:fmt( "^1 discovered...", str:plural( call.totalNew, "new item" ) ) )
            else
                errm = nNewOrErrMsg
                app:logError( "Unable to update metadata for " .. photoPath .. ", error message: " .. str:to( errm ) ) -- catalog read-access not required @3.0.
            end
            if call:isQuit( progressScope ) then
                return true -- done, no error.
            else
                progressScope:setPortionComplete( i, nToDo )
                yc = app:yield( yc ) -- yield every 20.
            end            
        end
        if i2 < nToDo then
            return false -- continue next phase.
        end
    end -- end-of-function-definition.

    local sts, msg = cat:updatePrivate( 50, updateFunc )
    if sts then
        app:log( "There were no catalog update errors." ) -- catalog may not have actually been updated, but presently the change count is not available in this context. logged stats should elaborate.
    else
        app:logError( "Catalog update error, message: " .. str:to( msg ) )
        call:abort( "Unable to update catalog." )
    end
    
end



return Common
