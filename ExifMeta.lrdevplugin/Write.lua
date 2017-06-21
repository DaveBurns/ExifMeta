--[[
        Write.lua
        
        Handles "Write" file menu item.
--]]


local Write = {} -- register the name of this item in init.lua for conditional dbg support via plugin manager.


local dbg, dbgf = Object.getDebugFunction( 'Write' )
assert( dbgf ~= nil, "no dbgf" )



--- Write target photos.
--
--  @usage      Menu handling function.
--
function Write.main()
    app:call( Call:new{ name="Write Photos", async=true, progress=nil, guard=App.guardVocal, main=function( call )
        call.dng = {}
        call.raw = {}
        call.rgb = {}
        call.all = {}
        local s, m = background:pause() -- must be called from async task.
        if s then
            app:log( "Background process paused." )
        else
            app:show{ warning="Unable to pause background task. Write will proceed despite this anomaly, but you should definitely report this problem!" }
        end
        local selPhotos = cat:getSelectedPhotos()
        if #selPhotos == 0 then
            app:show{ warning="Select photo(s) first." }
            call:cancel()
            return
        end
        local cache = lrMeta:createCache{ photos=selPhotos, rawIds={ 'fileFormat', 'path', 'isVirtualCopy' }, fmtIds={ 'copyName' } }
        for i, photo in ipairs( selPhotos ) do
            repeat
                local path = cache:getRawMetadata( photo, 'path' )
                local photoName = cat:getPhotoNameDisp( photo, true, cache )
                app:log( "Considering ^1", photoName )
                local format = cache:getRawMetadata( photo, 'fileFormat' )
                local virt = cache:getRawMetadata( photo, 'isVirtualCopy' )
                if virt then
                    --app:log( "Virtual copy ignored." )
                    break
                end
                if format == 'RAW' then
                    --app:log( "Raw" )
                    call.raw[#call.raw + 1] = photo
                    call.all[#call.all + 1] = photo
                elseif format == 'DNG' then
                    --app:log( "DNG" )
                    call.dng[#call.dng + 1] = photo
                    call.all[#call.all + 1] = photo
                elseif format == 'VIDEO' then
                    --app:log( "Video ignored." )
                    break
                else
                    call.rgb[#call.rgb + 1] = photo
                    call.all[#call.all + 1] = photo
                end
            until true
        end
        local nSubject = #call.raw + #call.dng + #call.rgb
        local props = LrBinding.makePropertyTable( call.context )
        app:initGlobalPref( 'autoXmp', false )
        app:initGlobalPref( 'doCaptureTime', false )
        local _incrSeconds = app:getGlobalPref( 'incrSeconds' )
        if _incrSeconds then -- was checked in legacy version.
            app:setGlobalPref( 'incrInSeconds', 1 ) -- set it to equivalent value in new version: one.
            app:setGlobalPref( 'incrSeconds', nil ) -- clear remnant from legacy version. 
        else -- wasn't checked, or never initialized
            app:initGlobalPref( 'incrInSeconds', 0 ) -- assure init as number, default to zero.
        end
        app:initGlobalPref( 'year', 2012 )
        app:initGlobalPref( 'month', 1 )
        app:initGlobalPref( 'day', 1 )
        app:initGlobalPref( 'hour', 0 )
        app:initGlobalPref( 'minute', 0 )
        app:initGlobalPref( 'second', 0 )
        app:initGlobalPref( 'doRaws', false )
        app:initGlobalPref( 'doDngs', false )
        app:initGlobalPref( 'doAddl', false )
        app:initGlobalPref( 'saveOrig', false )
        local presets2 = app:getPref( 'addlTagPresets' )
        local presetLookup = {}
        if presets2 == nil then
            app:logVerbose( "*** No presets defined." )
            presets2 = {}
        end
        -- Note: storing structured preset item in global prefs is causing spinning donut for a few seconds when selecting new preset.
        local presetItems = {{ title='Custom', value = "" }}
        -- not need to set global preset pref since value will be explicitly set below.
        local maxTags = app:getPref( "maxTags" ) or 7 -- user's responsibility for assuring max-tags will fit largest preset defined.
        for i, v in ipairs( presets2 ) do
            if str:is( v.title ) then
                if #v.value > maxTags then
                    maxTags = #v.value
                end
            -- else condition dealt with in second pass of presets below.
            end
        end
        local tempv = {}
        for i = 1, maxTags do
            local tagName = "tagName_" .. i
            local tagValue = "tagValue_" .. i
            app:initGlobalPref( tagName, "" )
            app:initGlobalPref( tagValue, "" )
            if str:is( app:getGlobalPref( tagName ) ) then
                tempv[#tempv + 1] = { tag=app:getGlobalPref( tagName ), value=app:getGlobalPref( tagValue ) }
            end
        end
        local found = false
        for i, v in ipairs( presets2 ) do
            if tab:isEquivalent( tempv, v.value ) then
                app:setGlobalPref( 'preset', v.title )
                found = true
            end
            if str:is( v.title ) then
                presetItems[#presetItems + 1] = { title=v.title, value=v.title }
                presetLookup[v.title] = v
            else
                app:logWarning( "presets should include title" )
            end
        end
        if not found then
            app:setGlobalPref( 'preset', "" ) -- custom
        end
        local presets = nil
        local function getStampNum()
            return LrDate.timeFromComponents( app:getGlobalPref( 'year' ), app:getGlobalPref( 'month' ), app:getGlobalPref( 'day' ), app:getGlobalPref( 'hour' ), app:getGlobalPref( 'minute' ), app:getGlobalPref( 'second' ), 'local' )
        end
        local function getStampStr( timeNum )
            assert( type( timeNum) == 'number', "?" )
            return LrDate.timeToUserFormat( timeNum, "%Y:%m:%d %H:%M:%S" ) -- local timezone implied, exiftool compatible format.
        end
        local function updateEgCapTime()
            props.egCapTime = getStampStr( getStampNum() )
        end
        updateEgCapTime()
        local function chgHdlr( id, props, key, value )
            app:call( Call:new{ name="Change Handler", async=true, guard=App.guardSilent, main=function( call )
                -- async allows do-raws to use a modal dialog with impunity, but runs the risk that changes made simultaneously are missed.
                -- note: user can't make changes simultaneously, but program can - so beware. The other option is to spin a separate thread for prompts.
                -- guarding allows changes to be made to mutually dependent values without triggering an infinite recursion.
                local name = app:getGlobalPrefName( key )
                if name == 'preset' then
                    --Debug.lognpp( value )
                    local n = 1
                    if presetLookup[value] then
                        local val = presetLookup[value].value
                        for i, v in ipairs( val ) do
                            local tagName = "tagName_" .. i
                            local tagValue = "tagValue_" .. i
                            local tag = v.tag
                            local value = v.value
                            app:setGlobalPref( tagName, tag )
                            app:setGlobalPref( tagValue, value )
                            n = n + 1
                        end
                    else
                        --
                    end
                    for i = n, maxTags do
                        local tagName = "tagName_" .. i
                        local tagValue = "tagValue_" .. i
                        app:setGlobalPref( tagName, "" )
                        app:setGlobalPref( tagValue, "" )
                    end
                    
                elseif name == '______addl' then
                    app:setGlobalPref( 'preset', "" ) -- custom.
                elseif name:find( 'tagName' ) then
                    app:setGlobalPref( name, value:gsub( '"', '' ) )
                    app:setGlobalPref( 'preset', "" ) -- custom.
                elseif name:find( 'tagValue' ) then
                    app:setGlobalPref( name, value:gsub( '"', '' ) )
                    app:setGlobalPref( 'preset', "" ) -- custom.
                elseif name == 'doRaws' then
                    if value then
                        local button = app:show{ confirm="Are you sure you want to modify proprietary raw files? (not recommended unless necessary)",
                            buttons = { dia:btn( "Yes", 'ok' ), dia:btn( "No", 'cancel' ) },
                        }
                        if button == 'cancel' then
                            app:setGlobalPref( 'doRaws', false )
                        end
                    end
                elseif name == 'doCaptureTime' then
                    if not value then
                        if not app:getGlobalPref( 'doAddl' ) then
                            app:setGlobalPref( 'doAddl', true )
                        end
                    end
                elseif name == 'doAddl' then
                    if not value then
                        if not app:getGlobalPref( 'doCaptureTime' ) then
                            app:setGlobalPref( 'doCaptureTime', true )
                        end
                    end
                else
                    updateEgCapTime()
                end
            end } )
        end
        view:setObserver( prefs, app:getGlobalPrefKey( "preset" ), Write, chgHdlr ) -- so change will set associated addl text.

        if presets ~= nil then
            if type( presets ) == 'table' then
                for i, v in ipairs( presets ) do
                    if v.title ~= nil then
                        if type( v.title ) == 'string' then
                            if v.value ~= nil then
                                if type( v.value ) == 'string' then
                                    app:initGlobalPref( 'preset', v.value ) -- first time will set addl too, no-op after first time.
                                else
                                    error( "bad value type" )
                                end
                            else
                                error( "value missing" )
                            end
                        else
                            error( "bad title type" )
                        end
                    else
                        error( "missing title" )
                    end
                end -- for
            else
                error( "bad write-presets type - must be table" )
            end
        else
            --app:logWarning( "No write presets - using default preset." )
            --presets = {
            --    { title="Default (write presets are missing)", value='-tag="value"' },
            --}
        end

        view:setObserver( prefs, app:getGlobalPrefKey( "doCaptureTime" ), Write, chgHdlr )
        view:setObserver( prefs, app:getGlobalPrefKey( "doAddl" ), Write, chgHdlr )
        view:setObserver( prefs, app:getGlobalPrefKey( "doRaws" ), Write, chgHdlr )
        view:setObserver( prefs, app:getGlobalPrefKey( "year" ), Write, chgHdlr )
        view:setObserver( prefs, app:getGlobalPrefKey( "month" ), Write, chgHdlr )
        view:setObserver( prefs, app:getGlobalPrefKey( "day" ), Write, chgHdlr )
        view:setObserver( prefs, app:getGlobalPrefKey( "hour" ), Write, chgHdlr )
        view:setObserver( prefs, app:getGlobalPrefKey( "minute" ), Write, chgHdlr )
        view:setObserver( prefs, app:getGlobalPrefKey( "second" ), Write, chgHdlr )
        view:setObserver( prefs, app:getGlobalPrefKey( "addl" ), Write, chgHdlr )
        call.testMode = true -- cheap insurance - not necessary.
        
        local function maintOrig( del )
            local serviceName = del and "Delete _original files" or "Restore originals"
            app:call( Service:new{ name=serviceName, async=true, main=function( maintCall )
                assert( del ~= nil, "pass del" )
                maintCall.stats = {
                    nMaint = 0
                } 
                local todo = {}
                local function rec( targ, orig )
                    if fso:existsAsFile( orig ) then
                        if fso:existsAsFile( targ ) then
                            todo[#todo + 1] = { orig=orig, targ=targ }
                        elseif del then
                            -- todo[#todo + 1] = { orig=orig, targ=targ }
                            -- don't delete original unless targ exists.
                            app:logWarning( "Not deleting _original file, since correponding target does not exist: '^1' - consider deleting manually if desired.", targ )
                            -- ###3 - consider a univeral cleanup option (one that assumes nothing, and deletes _original files whether source still exists or not).
                        end
                    else
                        app:logVerbose( "No _original file exists corresponding to: ^1", targ )
                    end
                end
                for i, photo in ipairs( call.all ) do
                    local photoPath = cache:getRawMetadata( photo, 'path' )
                    local targ = xmp:getXmpFile( photo, cache )
                    local orig = photoPath .. '_original'
                    rec( photoPath, orig )
                    if targ == photoPath then
                        -- done
                    else
                        local targOrig = targ .. '_original'
                        rec( targ, targOrig )
                    end
                end
                if #todo == 0 then
                    if del then
                        app:show{ info="There are no originals corresponding to selected photos to delete." }
                        maintCall:cancel()
                        return
                    else
                        app:show{ info="There are no originals to restore corresponding to selected photos." }
                        maintCall:cancel()
                        return
                    end
                end
                local button
                local buttons = { dia:btn( "OK", 'ok' ) }
                if del then
                    button = app:show{ confirm="Delete (move to recycle bin if possible) ^1",
                        subs = { str:nItems( #todo, "_original files" ) },
                        buttons = buttons,
                    }
                else
                    button = app:show{ confirm="Restore ^1 (previous target will be moved to recycle bin if possible)",
                        subs = { str:nItems( #todo, "_original files" ) },
                        buttons = buttons,
                    }
                end
                if button == 'cancel' then
                    return
                elseif button == 'ok' then
                
                else
                    error( "bad button" )
                end
                
                -- fall-through => do it: delete or restore.
                if del then
                    for i, item in ipairs( todo ) do
                        local toDel = item.orig
                        local targ = item.targ
                        local s, qual = fso:moveToTrash( toDel )
                        if s then
                            maintCall.stats.nMaint = maintCall.stats.nMaint + 1
                            if qual then
                                app:log( "^1 was deleted or moved to trash: ^2", toDel, qual )
                            else
                                app:log( "^1 was deleted or moved to trash.", toDel )
                            end
                        else
                            app:logErr( "Unable to move '^1' to trash.", toDel )
                        end
                    end
                else -- restore (reminder: both files exist)
                    for i, item in ipairs( todo ) do
                        local orig = item.orig
                        local targ = item.targ
                        local s, qual = fso:moveToTrash( targ )
                        if s then
                            if qual then
                                app:logVerbose( "^1 was deleted or moved to trash so ^2 could take it's place: ^3", targ, orig, qual )
                            else
                                app:logVerbose( "^1 was deleted or moved to trash so ^2 could take it's place.", targ, orig )
                            end
                            local renamed, m = fso:moveFolderOrFile( orig, targ ) -- rename
                            if renamed then
                                maintCall.stats.nMaint = maintCall.stats.nMaint + 1
                                app:log( "^1 was restored from ^2", targ, orig )
                            else
                                app:logErr( "Unable to restore ^1 from ^2: ^3", targ, orig, m )
                            end
                            
                        else
                            app:logErr( "Unable to remove '^1' so '^2' could take it's place: ^3", targ, orig, qual )
                        end
                    end
                end
            end, finale=function( maintCall )
                app:log()
                if del == true then
                    app:log( "^1 deletes.", maintCall.stats.nMaint )
                elseif del == false then -- restore.
                    app:log( "^1 restorals.", maintCall.stats.nMaint )
                    app:log( "*** Reminder: you may need to read metadata in Lightroom for info in restored files to propagate from xmp to catalog." )
                else
                    error( "program failure" )
                end
            end } )
        end
        
        local a = {}
        a.title = "ExifMeta - Modify Exif in Photo File(s)"
        local vi = { spacing=vf:dialog_spacing() }
        
        -- header
        local tb = ""
        if #call.rgb then
            if #call.raw > 0 or #call.dng > 0 then
                if #call.rgb == 1 then
                    tb = str:fmtx( " (1 of which is an RGB file)" )
                else
                    tb = str:fmtx( " (^1 of which are RGB files)", #call.rgb )
                end
            end
        end
        vi[#vi + 1] = vf:row {
            vf:static_text {
                title = str:fmtx( "^1 subject to modification ^2", str:nItems( nSubject, "source files" ), tb )
            },
        }
        local tv = {}
        if #call.raw > 0 then
            tv[#tv + 1] = vf:row {
                vf:static_text {
                    title = str:fmtx( "How to treat ^1:", str:nItems( #call.raw, "raw photos" ) ),
                },
                vf:checkbox {
                    title = "modify raw files too",
                    bind_to_object = prefs,
                    value = app:getGlobalPrefBinding ('doRaws' ),
                    tooltip = "if checked, proprietary raw file will be modified as well as xmp sidecar file (if it exists); if unchecked, only the xmp sidecar will be modified (it must exist)."
                    --checked_value = true,
                },
                --[[ *** always do sidecars too, otherwise Lr will not consolidate changed date from raw without deleteing/renameing the xmp.
                vf:radio_button {
                    title = "modify XMP sidecars",
                    bind_to_object = prefs,
                    value = app:getGlobalPrefBinding ('doRaws' ),
                    checked_value = false,
                },
                --]]
            }
        end
        if #call.dng > 0 then
            tv[#tv + 1] = vf:row {
                vf:spacer {
                    width = 10,
                },
                vf:checkbox {
                    title = str:fmtx( "modify ^1", str:nItems( #call.dng, "DNG Files" ) ),
                    tooltip = "@9/Sep/2012, ExifTool does not support v1.4 DNGs. This plugin can not tell which version of DNGs are subject to modification.",
                    bind_to_object = prefs,
                    value = app:getGlobalPrefBinding ('doDngs' ),
                },
            }                
        end
        if #tv > 0 then
            vi[#vi + 1] = vf:row( tv )
        end
        
        -- capture time
        vi[#vi + 1] = vf:separator{ fill_horizontal = 1 }
        
        vi[#vi + 1] =
            vf:row {
                vf:checkbox {
                    title = "Save metadata before, and read after",
                    bind_to_object = prefs,
                    value = app:getGlobalPrefBinding ('autoXmp' ),
                    tooltip = "If checked, Exif Meta (Exif Write) will assure changes take effect in Lightroom; If un-checked, you will need to take manual action: save metadata before running, and read metadata afterward.\n \nI recommend checking this to start with, and if you have problems with it, then either tweak advanced settings 'til it works, or uncheck it and handle manually.",
                },
            }
        vi[#vi + 1] =
            vf:row {
                vf:checkbox {
                    title = "Modify capture time",
                    bind_to_object = prefs,
                    value = app:getGlobalPrefBinding ('doCaptureTime' ),
                },
                vf:spacer{ width=1 },
                vf:edit_field {
                    tooltip = "Inter-photo time increment, in seconds - zero => all photos set to same time; 1 => each photo one second after the previous; 86400 => each photo one day after the previous..",
                    bind_to_object = prefs,
                    precision = 0,
                    width_in_digits = 5, -- generally this will be zero or one, but why not support display of up to ~86400 (seconds per day).
                    min = 0,
                    max = math.huge, -- no reason to impose arbitrary limitation
                    value = app:getGlobalPrefBinding ('incrInSeconds' ),
                },
                vf:static_text {
                    title=bind {
                        key = app:getGlobalPrefKey( 'incrInSeconds' ),
                        bind_to_object = prefs,
                        transform = function()
                            return str:phrase( app:getGlobalPref( 'incrInSeconds' ), "second between photos", "seconds between photos" )
                        end
                    },
                },
                vf:spacer{ width=1 },
                vf:static_text {
                    bind_to_object = props,
                    title = bind 'egCapTime',
                },
            }
        vi[#vi + 1] =    
            vf:row {
                vf:static_text {
                    title = "Date:",
                },
                vf:column {
                    vf:static_text {
                        title = "Year",
                    },
                    vf:edit_field {
                        bind_to_object = prefs,
                        value = app:getGlobalPrefBinding ('year' ),
                        tooltip = "4-digit year",
                        width_in_digits = 4,
                        min = 1000,            
                        max = 9999,
                        precision = 0,
                        enabled = app:getGlobalPrefBinding ('doCaptureTime' ),
                    },
                },
                vf:column {
                    vf:static_text {
                        title = "Month",
                    },
                    vf:popup_menu {
                        bind_to_object = prefs,
                        value = app:getGlobalPrefBinding ('month' ),
                        items = {
                            { title = "January", value = 1 },
                            { title = "February", value = 2 },
                            { title = "March", value = 3 },
                            { title = "April", value = 4 },
                            { title = "May", value = 5 },
                            { title = "June", value = 6 },
                            { title = "July", value = 7 },
                            { title = "August", value = 8 },
                            { title = "September", value = 9 },
                            { title = "October", value = 10 },
                            { title = "November", value = 11 },
                            { title = "December", value = 12 },
                        },
                        enabled = app:getGlobalPrefBinding ('doCaptureTime' ),
                    },
                },
                vf:column {
                    vf:static_text {
                        title = "Day",
                    },
                    vf:edit_field {
                        bind_to_object = prefs,
                        value = app:getGlobalPrefBinding ('day' ),
                        tooltip = "month-day, typically 1-31",
                        width_in_digits = 2,
                        min = 1,            
                        max = 31,
                        precision = 0,
                        enabled = app:getGlobalPrefBinding ('doCaptureTime' ),
                    },
                },
                vf:spacer {
                    width = 10,
                },
                vf:static_text {
                    title = "Time:",
                },
                vf:column {
                    vf:static_text {
                        title = "Hour",
                    },
                    vf:edit_field {
                        bind_to_object = prefs,
                        value = app:getGlobalPrefBinding ('hour' ),
                        tooltip = "2-digit hour, 0-23",
                        width_in_digits = 2,
                        min = 0,            
                        max = 23,
                        precision = 0,
                        enabled = app:getGlobalPrefBinding ('doCaptureTime' ),
                    },
                },
                vf:column {
                    vf:static_text {
                        title = "Minute",
                    },
                    vf:edit_field {
                        bind_to_object = prefs,
                        value = app:getGlobalPrefBinding ('minute' ),
                        tooltip = "2-digit minute, 0-59",
                        width_in_digits = 2,
                        min = 0,            
                        max = 59,
                        precision = 0,
                        enabled = app:getGlobalPrefBinding ('doCaptureTime' ),
                    },
                },
                vf:column {
                    vf:static_text {
                        title = "Second",
                    },
                    vf:edit_field {
                        bind_to_object = prefs,
                        value = app:getGlobalPrefBinding ('second' ),
                        tooltip = "2-digit second to start with, 0-59",
                        width_in_digits = 2,
                        min = 0,            
                        max = 59,
                        precision = 0,
                        enabled = app:getGlobalPrefBinding ('doCaptureTime' ),
                    },
                },
            }        
        
        -- save originals
        vi[#vi + 1] = vf:separator { fill_horizontal = 1 }
        
        vi[#vi + 1] = 
            vf:row {
                vf:checkbox {
                    title = "Save copy of originals",
                    bind_to_object = prefs,
                    value = app:getGlobalPrefBinding( 'saveOrig' ),
                },
                vf:push_button {
                    title = "Restore copy of originals",
                    action = function( button )
                        maintOrig( false ) -- restore
                    end,
                },
                vf:push_button {
                    title = "Delete copy of originals",
                    action = function( button )
                        maintOrig( true ) -- delete
                    end, 
                },
            }
            
        -- additional tooling
        vi[#vi + 1] = vf:separator { fill_horizontal = 1 }
        
        vi[#vi + 1] = 
            vf:row {
                vf:checkbox {
                    title = "Additional tags",
                    bind_to_object = prefs,
                    value = app:getGlobalPrefBinding ('doAddl' ),
                },
                vf:popup_menu {
                    bind_to_object = prefs,
                    value = app:getGlobalPrefBinding ('preset' ),
                    --items = presets2,
                    items = presetItems,
                    _value_equal = function( v1, v2 )
                        return true
                    end,
                    ___value_equal = function( v1, v2 )
                        --Debug.lognpp( "v1", v1 )
                        --Debug.lognpp( "v2", v2 )
                        if tab:isEquivalent( v1, v2 ) then
                            return true
                        else
                            return false
                        end
                    end,
                    enabled = app:getGlobalPrefBinding ('doAddl' ),
                },
                vf:spacer{ width=10 },
                vf:static_text {
                    title = "exif tag doc (web)",
                    text_color = LrColor( 'blue' ),
                    mouse_down = function()
                        LrHttp.openUrlInBrowser( "http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/EXIF.html" )
                    end,
                },                    
            }
        -- tag/value matrix:
        local col = { spacing = 1 }
        col[#col + 1] =
            vf:row { 
                vf:static_text {
                    title = "Tag",
                    width = share 'tag_name',
                },
                vf:static_text {
                    title = "Value",
                    width = share 'tag_value',
                },
            }
        
        for i = 1, maxTags do
            local tagName = 'tagName_' .. i
            local tagValue = 'tagValue_' .. i
            col[#col + 1] =
                vf:row {
                    vf:edit_field {
                        bind_to_object = prefs,
                        value = app:getGlobalPrefBinding( tagName ),
                        width_in_chars = 15,
                        width = share 'tag_name',
                        enabled = app:getGlobalPrefBinding( 'doAddl' ),
                    },
                    vf:edit_field {
                        bind_to_object = prefs,
                        value = app:getGlobalPrefBinding( tagValue ),
                        width_in_chars = 25,
                        width = share 'tag_value',
                        enabled = app:getGlobalPrefBinding( 'doAddl' ),
                    },
                }
            view:setObserver( prefs, app:getGlobalPrefKey( tagName ), Write, chgHdlr )
            view:setObserver( prefs, app:getGlobalPrefKey( tagValue ), Write, chgHdlr )
        end
        vi[#vi + 1] = vf:column( col )
            
        local ai = {}
        ai[#ai + 1] = vf:row {
            vf:push_button {
                title = "Test Run (files not modified)",
                props = props,
                action = function( button )
                    LrDialogs.stopModalWithResult( button, 'testRun' )
                end
            },
            vf:push_button {
                title = "Help",
                action = function( button )
                    local m = {}
                    m[#m + 1] = "Visit plugin manager to define presets: preset manager section - edit advanced settings: addlTagPresets."
                    dia:quickTips( m )
                end
            },
        }
        a.actionVerb = "Modify Photo Files"
        a.cancelVerb = "Done"
        a.contents = vf:view( vi )
        a.accessoryView = vf:view( ai )
        
        -- note: doit is called *after* dismissal of dialog box.
        local function doit()
            app:call( Service:new{ name="Exif Write", async=false, progress={ caption="Working - please wait..." }, main=function( srvc )
                srvc.stats = {
                    nFilesWritten = 0,
                    nPhotosUpdated = 0,
                }
                assert( call.testRun ~= nil, "program failure" )
                if not app:getGlobalPref( 'doCaptureTime' ) and not app:getGlobalPref( 'doAddl' ) then
                    app:show{ warning="Enable capture time modification or additional tooling." }
                    return -- should "never" happen.
                end
                if not call.testRun then
                    app:log()
                    app:log( "*** Modifying photo files (this is not a test run)" )
                    app:log( "*** Modifying photo files (this is not a test run)" )
                    app:log( "*** Modifying photo files (this is not a test run)" )
                    app:log()
                else
                    app:log()
                    app:log( "*** This is a test run (no photo files will be modified)." )
                    app:log( "*** This is a test run (no photo files will be modified)." )
                    app:log( "*** This is a test run (no photo files will be modified)." )
                    app:log()
                end
                local exe = exifTool:getExe()
                if str:is( exe ) then
                    app:log( "exiftool executable: ^1", exe )
                else
                    app:show{ warning="Unable to proceed - exiftool executable has not been specified." }
                    srvc:cancel()
                    return
                end
                if #call.all == 0 then -- dunno if possible here, but just in case..
                    app:logW( "No photos" ) 
                    return
                end
                if #call.all > 1 then
                    srvc.ets = exifTool:openSession( srvc.name ) -- open a real session for multiple photos.
                else
                    srvc.ets = exifTool -- emulates a session.
                end
                local ver, errm = srvc.ets:getVersionString()
                if ver then
                    app:log( "exiftool version: ^1", ver )
                    app:log()
                else
                    app:show{ warning="Unable to obtain exiftool version number: ^1", errm }
                    return
                end

                local autoXmp = app:getGlobalPref( 'autoXmp' )
                assert( autoXmp ~= nil, "bad pref" )
                
                if autoXmp then
                    local s, m
                    if #call.all == 1 then
                        -- Catalo g : s avePhotoMetadata( photo, photoPath, targ, call, noVal )
                        local photo = call.all[1]
                        s, m = cat:savePhotoMetadata( photo, photo:getRawMetadata( 'path' ), nil, call )
                    else
                        -- Catalo g : s aveMetadata( photos, preSelect, restoreSelect, alreadyInGridMode, service )
                        s, m = cat:saveMetadata( call.all, true, false, false, call )
                    end
                    if s then
                        app:log( "Metadata saved - ^1", str:nItems( #call.all, "photos" ) )
                    else
                        app:logE( m )
                        return
                    end
                else
                    app:log( "Not saving metadata automatically before-hand - hopefully you've done it manually." )
                end
                call.read = {} -- metadata
                local readSet = {}

                local capTimeNum = getStampNum()
                assert( type( capTimeNum ) == 'number', "?" )                
                
                for i, photo in ipairs( call.all ) do
                
                    repeat -- once
                        local photoPath = cache:getRawMetadata( photo, 'path' )
                        local fmt = cache:getRawMetadata( photo, 'fileFormat' )
                        local xmpPath = xmp:getXmpFile( photo, cache ) -- does not check existence.
                        local targetPaths = {}
                        if fso:existsAsFile( xmpPath ) then
                            targetPaths[#targetPaths + 1] = xmpPath -- maybe same as photo path.
                            if fmt == 'RAW' then
                                if app:getGlobalPref( 'doRaws' ) then
                                    if photoPath ~= xmpPath then
                                        if fso:existsAsFile( photoPath ) then
                                            targetPaths[#targetPaths + 1] = photoPath
                                            app:log( "Processing raw photo '^1', and xmp: ^2", photoPath, LrPathUtils.leafName( xmpPath ) )
                                        else
                                            app:logWarning( "File is missing: '^1' - this photo will not be processed.", photoPath )
                                            break
                                        end
                                    else
                                        app:error( "program failure" )
                                    end
                                else
                                    app:log( "Processing xmp sidecar file only: '^1', not raw: ^2", xmpPath, LrPathUtils.leafName( photoPath ) )
                                end
                            else
                                app:log( "Processing '^1'", xmpPath )
                            end
                        elseif fmt == 'RAW' then
                            if app:getGlobalPref( 'doRaws' ) then
                                app:log( "No xmp for '^1' - doing raw only.", photoPath )
                                targetPaths[#targetPaths + 1] = photoPath
                            else
                                app:logWarning( "No xmp for '^1' - skipping it." )
                                break
                            end
                        else
                            app:logWarning( "File is missing: '^1' - this photo is being skipped.", xmpPath ) -- same as photo path.
                            break
                        end

                        -- Do exiftooleanization to one file (photo or xmp sidecar).    
                        local function doIt( selector, file )
                            if app:getGlobalPref( 'saveOrig' ) then
                                -- no arg
                            else
                                srvc.ets:addArg( "-overwrite_original" )
                            end
                            if app:getGlobalPref( 'doCaptureTime' ) then
                                local stamp = getStampStr( capTimeNum )
                                local exifTag = str:fmtx( "-exifIFD:DateTimeOriginal=^1", stamp )
                                local xmpTag = str:fmtx( "-xmp:DateTimeOriginal=^1", stamp )
                                if selector == 1 then -- exif
                                    srvc.ets:addArg( exifTag )
                                elseif selector == 2 then -- xmp
                                    srvc.ets:addArg( xmpTag )
                                else -- both
                                    assert( selector == 3, "?" )
                                    srvc.ets:addArg( exifTag )
                                    srvc.ets:addArg( xmpTag )
                                end
                            -- else don't do capture time.
                            end
                            if app:getGlobalPref( 'doAddl' ) then
                                for i = 1, maxTags do
                                    local tagName = 'tagName_' .. i
                                    local tagValue = 'tagValue_' .. i
                                    local tag = app:getGlobalPref( tagName )
                                    if str:is( tag ) then
                                        local value = app:getGlobalPref( tagValue )
                                        local arg
                                        if str:is( value ) then
                                            arg = str:fmtx( "-^1=^2", tag, value ) -- no need to wrap value since tag will also be wrapped in quotes.
                                        else
                                            arg = str:fmtx( "-^1", tag ) -- no need to wrap value since tag will also be wrapped in quotes.
                                        end
                                        srvc.ets:addArg( arg )
                                    end
                                end
                            end
                            local p = srvc.ets:getArgumentString()
                            if not call.testRun then
                                if srvc.ets:isSession() then
                                    app:log( "Invoking exiftool upon target (^1) in session mode (arguments do not need quotes), with arguments: ^2", file, p )
                                else
                                    app:log( "Invoking exiftool upon target (^1) in one-shot mode (quotes around entire -tag=value parameter obviates need for quotes around value), with arguments: ^2", file, p )
                                end
                                
                                -- pre 15/Jan/2015 20:49
                                srvc.ets:setTarget( file ) -- after this, files *will* be modified upon execute *or* closing, and session must be closed so exiftool will exit.
                                srvc.ets:execute() -- this is now hot.
                                
                                srvc.stats.nFilesWritten = srvc.stats.nFilesWritten + 1
                            else
                                if srvc.ets:isSession() then
                                    app:log( "Would invoke exiftool upon target (^1) in session mode (arguments do not need quotes), with arguments: ^2", file, p )
                                else
                                    app:log( "Would invoke exiftool upon target (^1) in one-shot mode (quotes around entire -tag=value parameter obviates need for quotes around value), with arguments: ^2", file, p )
                                end
                                
                                -- reminder: do not set targets.
                                srvc.ets:clearArgumentString()
                                
                                srvc.stats.nFilesWritten = srvc.stats.nFilesWritten + 1
                            end
                            if not readSet[photo] then
                                call.read[#call.read + 1] = photo
                                srvc.stats.nPhotosUpdated = srvc.stats.nPhotosUpdated + 1
                                readSet[photo] = true
                            end
                        
                        end
                        
                        if xmpPath == photoPath then -- all in one.
                            doIt( 3, photoPath ) -- do both tags (exif+xmp) to one common file.
                        else -- separate - do raw then xmp sidecar.
                            doIt( 1, photoPath ) -- exif tag
                            doIt( 2, xmpPath ) -- xmp tag.
                        end
                        local incr = app:getGlobalPref( 'incrInSeconds' ) -- numeric (should never be nil, but won't hurt to check..).
                        if incr and ( incr > 0 ) then -- user entered non-zero value.
                            capTimeNum = capTimeNum + incr -- change cap-time-num for next time
                        -- else leave cap-time-num as set for next time.
                        end

                    until true                
                end -- for photo

                if autoXmp then
                    local s, m                
                    if #call.read > 0 then
                        if #call.read == 1 then
                            local photo = call.read[1]
                            s, m = cat:readPhotoMetadata( photo, nil, false, call, "Reading metadata after writing" ) -- readPhotoMetadata( photo, photoPath, alreadyInLibraryModule, service, manualSubtitle )
                        else
                            s, m = cat:readMetadata( call.read, true, false, true, call ) -- readMetadata( photos, preSelect, restoreSelect, alreadyInGridMode, service )
                        end
                    end                
                    if s then
                        app:log( "Metadata read - ^1", str:nItems( #call.read, "photos" ) )
                    else
                        app:logE( m )
                        return
                    end
                else
                    app:log( "Not reading metadata automatically - you may have to read manually for changes to take effect." )
                end
            end, finale=function( srvc )
                exifTool:closeSession( srvc.ets ) -- @10/Sep/2012 4:46 - handles nil OK. Warning: closing a true exiftool session will execute open session if pending.
                app:log()
                if not call.testRun then
                    if srvc.stats.nFilesWritten == srvc.stats.nPhotosUpdated then
                        app:log( "^1 modified.", str:nItems( srvc.stats.nFilesWritten, "photo files" ) )
                    else
                        app:log( "^1 (^2) modified.", str:nItems( srvc.stats.nFilesWritten, "files" ), str:nItems( srvc.stats.nPhotosUpdated, "photos" ) )
                    end
                    if srvc.stats.nFilesWritten > 0 then
                        app:log( "You may need to read metadata for changes to be incorporated in Lightroom." )
                    end
                else
                    if srvc.stats.nFilesWritten == srvc.stats.nPhotosUpdated then
                        app:log( "^1 would have been modified.", str:nItems( srvc.stats.nFilesWritten, "photo files" ) )
                    else
                        app:log( "^1 (^2) would have been modified.", str:nItems( srvc.stats.nFilesWritten, "files" ), str:nItems( srvc.stats.nPhotosUpdated, "photos" ) )
                    end
                end
            end } )
        end
        repeat
            local button = LrDialogs.presentModalDialog( a )
            if button == 'ok' then
                call.testRun = false
                doit()
            elseif button == 'testRun' then
                call.testRun = true
                doit()
            elseif button == 'cancel' then
                return
            else
                error( "bad button" )
            end
        until false
        
    end, finale=function( call )
        background:continue()
        -- Debug.showLogFile()
    end } )
end



Write.main()
