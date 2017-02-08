--[[
        ExtendedManager.lua
        -------------------        
        
        todo:
        
        ###2:
        - FIXED: data not properly refreshed after opening plugin manager.
        - FIXED: metadeftime: need a way to force update, otherwise there's a catch-22: Cant commit when no data has changed, but cant change data because it seems up to date.
        - HAVENT SEEN since changed pref handling to non-table prefs. make sure there are no id mismatches. test-test-test.
        - FIXED: Use encounters threshold in interesting filter.
        On Mac:
        - Recursion guarding of pref handler seems broken.
        - Maybe both: initially, commiting and reloading causes database to become uninitialized again - maybe only if commit is attempted with zero data - no I think first time, data disappeared.
        - FIXED: Bottom two rows are too wide.
        
        ###2:
        - Presently, marking hide/include one at a time will not update data view (preferred behavior), but marking hide or include in bulk may cause them to disappear (not unreasonable, but would prefer consistence).
        - Use proper means for assuring numeric inputs are numeric.
--]]

local ExtendedManager, dbg, dbgf = Manager:newClass{ className='ExtendedManager' }



--- Constructor for new instance object.
--
function ExtendedManager:new( t )
    local o = Manager.new( self, t )
    o.page = 20 -- default, to be replaced by global pref.
    o.props = nil
    o.scrollView = ScrollView:new{ global = true } -- create new scroll view that uses global binding.
    o.it = {}
    return o
end



--- Initialize global prefs.
--
function ExtendedManager:_initGlobalPrefs()
    -- record previous value for migration to local pref.
    self.autoUpdateGlobalPref = app:getGlobalPref( 'autoUpdate' )
    -- now clear obsolete global pref:
    app:setGlobalPref( 'autoUpdate', nil )
    ----------------------------------
    app:initGlobalPref( 'metaDefTime', "Metadata database uninitialized" ) -- formatted
    app:initGlobalPref( 'metaDefTime_', 0 ) -- raw
    app:initGlobalPref( 'new', 0 )
    app:initGlobalPref( 'maxItems', 2000 )
    -- app:initGlobalPref( 'numRows', 20 ) - made local 19/Aug/2011 20:46
    app:initGlobalPref( 'included', 0 )
    app:initGlobalPref( 'bigBlock', true )
    app:initGlobalPref( 'exifToolExe', "" )
    app.prefMgr:registerPreset( "Nikon 51-pt Auto-focus", 2 )
    app.prefMgr:registerPreset( "GPS Lat-Long in Decimal", 3 )
    Manager._initGlobalPrefs( self )
end



--- Initialize plugin prefs.
--
function ExtendedManager:_initPrefs( presetName )
    -- migrate legacy global prefs to local
    if self.autoUpdateGlobalPref ~= nil then
        app:initPref( 'background', autoUpdate, presetName ) -- from global pref to local
    end
    -- migrate legacy local prefs to global
    local exiftool = app:getPref( 'exiftool', presetName )
    if str:is( exiftool ) then
        if str:is( app:getGlobalPref( 'exifToolExe' ) ) then
            app:logWarning( "Check exiftool setting in plugin manager." )
        else
            app:setGlobalPref( 'exifToolExe', exiftool )
        end
        app:setPref( 'exiftool', "", presetName ) -- will eclipse value read from backing file.
        app:show{ info="custom exiftool-executable configuration migrated from advanced settings to global preferences (plugin manager): ^1", exiftool }
    end
    -- local prefs
    app:initPref( 'numRows', 20, presetName )
    app:initPref( 'background', false, presetName ) -- not quite willing to have "auto-update" enabled by default for exif-meta (exifmeta only changes when edit using mfr software).
        -- no-op if already initialized based on previous auto-update setting.
    app:initPref( 'processTargetPhotosInBackground', false, presetName )
    app:initPref( 'processAllPhotosInBackground', false, presetName )
    app:initPref( 'xmpHandling', 'rawOnly', presetName )
    app:initPref( 'filterNot', false, presetName )
    app:initPref( 'filterField', "No Filter", presetName )
    app:initPref( 'filterValue', "", presetName )
    app:initPref( 'filterRegex', false, presetName )
    app:initPref( 'showHidden', true, presetName )
    app:initPref( 'scrollPos', 1, presetName )
    app:initPref( 'sortField', "id", presetName )
    Manager._initPrefs( self, presetName )
end



--- Preference change handler.
--
--  @usage      Handles preference changes.
--              <br>Preferences not handled are forwarded to base class handler.
--  @usage      Handles changes that occur for any reason, one of which is user entered value when property bound to preference,
--              <br>another is preference set programmatically - recursion guarding is essential.
--
function ExtendedManager:prefChangeHandlerMethod( _id, _prefs, key, value )

    --   N U M   R O W S  -- why global? - made local 24/Aug/2011 -ish.
    --[[if key == app:getGlobalPrefKey( 'numRows' ) then
        app:setPref( 'scrollPos', 1 ) -- Probably no longer necessary, since scroll pos will be bounded upon startup, but...
        app:show( "Reload plugin for changes to take effect." )
        
        -- change handled.        
        return
    end--]]

    -- fall-through => change not handled.
    Manager.prefChangeHandlerMethod( self, _id, _prefs, key, value )

end



--- Property change handler.
--
--  @usage      Properties handled by this method, are either temporary, or
--              should be tied to named setting preferences.
--
function ExtendedManager:propChangeHandlerMethod( props, name, value, call )

    --[[ -- this is in some, but dunno if it works for exif-meta.
    if app.prefMgr and (app:getPref( name ) == value) then -- eliminate redundent calls.
        -- Note: in managed cased, raw-pref-key is always different than name.
        -- Note: if preferences are not managed, then depending on binding,
        -- app-get-pref may equal value immediately even before calling this method, in which case
        -- we must fall through to process changes.
        return
    end
    --]]
    
    --   N U M   R O W S
    if name == 'numRows' then
        app:setPref( 'numRows', value )
        --app:setPref( 'scrollPos', 1 ) -- Probably no longer necessary, since scroll pos will be bounded upon startup, but... commented out 24/Aug/2011 -ish.
        app:show( "Reload plugin for changes to take effect." )
        -- change handled.        
        return

    --   A U T O   U P D A T E
    elseif name == 'background' then
    
        if app:getPref( 'background' ) == value then
            Debug.pause( "Redundent background prop change." )
            return
        end
    
        app:setPref( 'background', value ) -- this is what base class change handler does if change passed through to it.
        if value then
            local started = background:start()
            if started then
                app:show( "Auto-update started." )
            else
                app:show( "Auto-update already started." )
            end
        elseif value ~= nil then
            app:call( Call:new{ name = 'Stop Background Task', async=true, guard=App.guardVocal, main=function( call )
                local stopped
                repeat
                    stopped = background:stop( 10 ) -- give it some seconds.
                    if stopped then
                        app:logVerbose( "Auto-update was stopped by user." )
                        app:show( "Auto-update is stopped." ) -- visible status wshould be sufficient.
                    else
                        if dialog:isOk( "Auto-update stoppage not confirmed - try again? (auto-update should have stopped - please report problem; if you cant get it to stop, try reloading plugin)" ) then
                            -- ok
                        else
                            break
                        end
                    end
                until stopped
            end } )
        end

    --   I N C L U D E   A L L
    elseif name == 'includeAll' then
        if value then
            if dialog:isOk( 'Mark all visible items for metadata inclusion?' ) then
                self:_mark( 'include', true )                --
            end
        elseif value ~= nil then
            if dialog:isOk( 'Clear metadata inclusion for all visible items?' ) then
                self:_mark( 'include', false )                --
            end
        end
        
    --   H I D E   A L L
    elseif name == 'hideAll' then
        if value then
            if dialog:isOk( 'Mark all visible items to be hidden?' ) then
                self:_mark( 'hide', true )                --
            end
        elseif value ~= nil then
            if dialog:isOk( 'Clear hiding for all visible metadata items?' ) then
                self:_mark( 'hide', false )                --
            end
        end            
        
    --   S C R O L L   P O S
    elseif name == 'scrollPos' then
        assert( type( value) == 'number', "scroll-pos not number" )
        app:setPref( 'scrollPos', value )
        self:_updateScrollView() -- note: if scroll position is only thing changing, then data view does not need to be updated.
    else
    
        -- note: presently not calling base class change handler,
        -- but beware this may need to be attended to in the future.
        
        --   P R O P   I N P U T S   ( I N C L U D E   &   H I D E )
        local p1, p2
        
        p1, p2 = name:find( 'include_' )
        if p1 then
            local propIndex = tonumber( name:sub( p2 + 1 ) )
            local propId = props['id_' .. propIndex]
            if propId == nil then
                return -- this happens as a transient - just ignore.
            end
            local prefIndex = self.scrollView:getPrefIndex( propIndex )
            local prefValue = self.data[prefIndex]
            if prefValue == nil then
                return
            end
            local prefId = prefValue.id
            if propId ~= prefId then
                return
            end
            assert( propId == prefId, "id mismatch" )
            Common.setInclude( prefId, value ) -- sets global prefs.
            prefValue.include = Common.getExifPrefField( prefId, 'include' )
            prefValue.hide = Common.getExifPrefField( prefId, 'hide' )
            self:_updateScrollView()
            return
        end
        
        p1, p2 = name:find( 'hide_' )
        if p1 then
            local propIndex = tonumber( name:sub( p2 + 1 ) )
            local propId = props['id_' .. propIndex]
            if propId == nil then
                --Debug.pause( "no prop id", propIndex )
                return -- this happens as a transient - just ignore.
            end
            local prefIndex = self.scrollView:getPrefIndex( propIndex )
            local prefValue = self.data[prefIndex]
            if prefValue == nil then
                --Debug.pause( "no pref value", propId, prefIndex )
                return
            end
            local prefId = prefValue.id
            if propId ~= prefId then
                --Debug.pause( "bad id", propId, prefId )
                return
            end
            assert( propId == prefId, "id mismatch" )
            Common.setHide( prefId, value ) -- will un-include if hiding.
            prefValue.include = Common.getExifPrefField( prefId, 'include' )
            prefValue.hide = Common.getExifPrefField( prefId, 'hide' )
            self:_updateScrollView()
            return
        end

        if name == 'significant' then
            return -- Probably should not be listened for, since really dont want to make it a saved / preset value.
        end
    
        dbg( "Misc property change - presumed to be a sort or filter...", name, value )
        --   S C R O L L   C O N T R O L
        dbgf( name, value )
        app:setPref( name, value ) -- save for next time - not done at end-of-dialog.
        self:_updateScrollView( true )

    end    
        
end



--- End of dialog method.
--
--  @param      props       same as was passed to start method.
--
function ExtendedManager:endDialogMethod( props )
    -- Manager.endDialogMethod( self, props ) - dont do this: I dont want to save all scroll properties
    -- with the preset. Nor do I want to save the temporary properties: include-all and hide-all.
    app:show( { info="You must commit changes to metadata to be included. If you did that already, or didn't change metadata to be included, then fine - otherwise, re-open plug-in manager and click the 'Commit' button.", actionPrefKey="Commit inclusion changes" } )
end



--- Start dialog method.
--
--  @usage      Called when plugin manager dialog box first opened.
--  @usage      Global prefs are initialized in init.lua, perhaps preset prefs should also be.
--
function ExtendedManager:startDialogMethod( props )

    self.props = props -- so props are available to all methods.
    --[[ *** moved to em-init-prefs: must be updated whenever pref preset changes anyway.
    app:initPref( 'filterNot', false ) -- probably should be in init.lua, but they're not used anywhere but the plugin manager so hardly matters.
    app:initPref( 'filterField', "No Filter" )
    app:initPref( 'filterValue', "" )
    app:initPref( 'filterRegex', false )
    app:initPref( 'showHidden', true )
    app:initPref( 'scrollPos', 1 )
    app:initPref( 'sortField', "id" )--]]
    props['includeAll'] = false -- need not be pref since temporary / not saved.
    props['hideAll'] = false -- ditto.
    self.page = tonumber( app:getPref( 'numRows' ) or 20 )
    if self.page > 200 then -- this would be one mondo sized monitor!
        self.page = 200
    elseif self.page < 5 then -- runnin' vga?
        self.page = 5
    end
    self.scrollView:setPageSize( self.page )
    view:setObserver( prefs, app:getGlobalPrefKey( 'autoUpdate' ), ExtendedManager, Manager.prefChangeHandler )
    
    if app:getPref( 'sortField' ) == 'hide' then
        app:setPref( 'showHidden', true ) -- this should already be the case, but cheap insurance...
    end
    
    -- If this is done synchronously upon start-dialog, the initial scroll view is not correct.
    app:call( Call:new{ name='Start Dialog', async=true, main=function( call )
        self:_updateScrollView( true ) -- sets scroll-view total size too, and assures scroll-pos is confined.
        -- *** Manager's start-dialog method is not picking these up: ###2 - why not?
        for i = 1, self.page do
            view:setObserver( props, 'include_' .. i, ExtendedManager, Manager.propChangeHandler )
            view:setObserver( props, 'hide_' .. i, ExtendedManager, Manager.propChangeHandler )
        end
    end } )

    Manager.startDialogMethod( self, props ) -- adds all properties as observers, so something will be done when they change - make sure its the right thing.
    -- (also adds base class managed pref observers).
end



--- Recomputes data to be viewed in the scroll view.
--
--  @usage      Call when anything changes that may alter the set of data to be viewed.
--              <br>Should be done when dialog box opened, as well as in response to sort and filter changes.
--
--  @usage      Could also be argued that it should be called whenever an update finds new data, in case the plugin manager
--              is open while data is being discovered, however I draw the line there, since it will be called normally when
--              plugin manager is opened, and if already open, there's always the refresh button.
--
function ExtendedManager:_updateDataView()
    local filter = { showHidden = self.props['showHidden'] }
    if app:getPref( 'filterField' ) ~= 'No Filter' then
        filter.invert = app:getPref( 'filterNot' )
        filter.field = app:getPref( 'filterField' )
        filter.value = app:getPref( 'filterValue' )
        if filter.field == 'Interesting' then
            local val = tonumber( filter.value or '1' )
            if type( val ) ~= 'number' then
                val = 1
            end
            filter.value = val
        end 
        filter.regex = app:getPref( 'filterRegex' )
    end
    self.data = {}
    local i = 1
    for id, t in Common.sortedPairs( filter ) do
        self.data[i] = t
        i = i + 1
    end
end



--- Updates the view of the current data set.
--
--  @usage      Call in response to anything that changes the view of the data, most notably scrolling, and when data-set changes.
--
function ExtendedManager:_updateScrollView( updateDataView )

    if updateDataView then
        self:_updateDataView()
    end

    local props = self.props
    local data = self.data
    
    self.scrollView:setDataSize( #data )
    props['significant'] = #data
    local pos = app:getPref( 'scrollPos' )
    if pos == nil then
        app:logError( "scroll-pos should never be nil" )
        pos = 1
    end
    assert( type( pos ) == 'number', "scroll-pos should be number" )
    local pos2 = self.scrollView:setScrollPos( pos ) -- may confine pos, based on data-size.
    if pos2 ~= pos then
        props['scrollPos'] = pos2 -- make sure property reflects confined pos
        app:setPref( 'scrollPos', pos2 ) -- make sure pref reflects prop.
    end

    for propIndex, dataIndex in self.scrollView:dataIndices() do
    
        props['include_' .. propIndex] = data[dataIndex].include
        props['interest_' .. propIndex] = (data[dataIndex].encounters > 1)
        props['name_' .. propIndex] = data[dataIndex].name
        props['id_' .. propIndex] = data[dataIndex].id
        props['hide_' .. propIndex] = data[dataIndex].hide
    
    end
    
    for propIndex in self.scrollView:fillIndices() do
    
        props['include_' .. propIndex] = nil
        props['interest_' .. propIndex] = false
        props['name_' .. propIndex] = nil
        props['id_' .. propIndex] = nil
        props['hide_' .. propIndex] = nil
    
    end
    
end



--  Mark visibles as hidden or included.
--
--  @usage      Typically called upon initialization, and in response to filter or sort changes.
--
function ExtendedManager:_mark( spec, check )

    app:call( Call:new{ name="Mark", async=true, guard=App.guardVocal, main=function( call )

        local ttl
        if check then
            ttl = 'Marking ' .. spec .. ' boxes'
        else
            ttl = 'Clearing ' .. spec .. ' boxes'
        end
    
        local scope = DelayedProgressScope:new {
            title = ttl,
            caption = "Please wait...",
            functionContext = call.context,
            modal = true,
            indeterminate = true,
            cannotCancel = true,
            delaySecs = 1, -- 1 is default
            updateSecs = .25, -- .25 is default
        }
    
        local id, fld, p1, p2
        local filter = { showHidden = self.props['showHidden'] }
        if app:getPref( 'filterField' ) ~= 'No Filter' then
            filter.invert = app:getPref( 'filterNot' )
            filter.field = app:getPref( 'filterField' )
            filter.value = app:getPref( 'filterValue' )
            filter.regex = app:getPref( 'filterRegex' )
        end
        
        for id, t in Common.sortedPairs( filter ) do -- sorted by preferred order.
            assert( id == t.id, "id mismatch" )
            if spec == 'include' then
                if t.include ~= check then
                    --Debug.lognpp( "Marking included", id )
                    Common.setInclude( id, check )
                end
            elseif spec == 'hide' then
                if t.hide ~= check then
                    --Debug.lognpp( "Marking hidden", id )
                    Common.setHide( id, check )
                end
            end
            scope:setIndeterminateProgress( true ) -- otherwise it never gets displayed.
        end
        
        self:_updateScrollView( true )
    
        scope:done()
        -- wouldnt hurt to have some stats and a prompt ###2
    end } )    
end



--- Hide tags with few distinct value encounters.
--
function ExtendedManager:_hideBoringTags( button )
    app:call( Call:new{ name=button.title, async=true, guard=App.guardVocal, main=function( call )
    
        local num, msg
        repeat
	        num, msg = dialog:getNumericInput {
                subtitle = "Mark all tags for hiding that have never seen \"this many\" distinct values.\n \nNote: values >= 2 hide boring data (larger values hide more, enter '2' to be conservative).\nA value of '1' won't hide anything, but gives you the chance to check distinct value counts in the log.\n \n(Hint: Only do this after you've updated a large sample of photos)\n \nHow many?",
	        }
	        if not num or msg then
	            return
	        end
	        if num < 1 then
	            app:show( { warning="Number should be greater or equal to 1" } )
	        end
	    until num >= 1
	    
        local scope = DelayedProgressScope:new {
            title = "Hiding Boring Tags",
            caption = "Please wait...",
            functionContext = call.context,
            modal = true,
            indeterminate = true,
            cannotCancel = true,
            delaySecs = 1, -- 1 is default
            updateSecs = .25, -- .25 is default
        }
	    
        local p1, p2, id
        local nHidden = 0
        local nAlready = 0
        local nSkipped = 0
        local seen = {}
        local t
        for id, t in Common.sortedPairs() do
            repeat
                assert( id == t.id, "id mismatch" )
                if t.encounters < num then
                    if t.new then
                        app:logWarning( "New metadata cant be considered boring - not hidden, ID: " .. id )
                        nSkipped = nSkipped + 1
                    else
                        app:logInfo( "Hiding " .. id .. ", encounters: " .. t.encounters )
                        if t.hide then
                            nAlready = nAlready + 1
                        else
                            Common.setHide( id, true ) -- clears include flag.
                            nHidden = nHidden + 1
                        end
                    end
                else
                    app:logInfo( str:fmt( "^1 has seen ^2", id, str:plural( t.encounters, "distinct value", true ) ) )
                end
            until true
            scope:setIndeterminateProgress( true )
		end
		if nHidden > 0 then
		    self:_updateScrollView( true )
		end
        scope:done() -- doesnt do much, since modal box hangs around until context destroyed - oh well...
	    app:show( { info="^1 freshly marked for hiding\n^2 were already marked hidden\n^3 skipped because they're too new" }, nHidden, nAlready, nSkipped )
    end } )
end



---     Synopsis:           Saves auto-gen metadata-provider lua plugin file.
--<br>      
--<br>      Notes:              Module content depends on metadb tables from prefs.
--<br>      
--<br>      Returns:            true        -- chg
--<br>                          false       -- no chg
--<br>                          nil, errm   -- chg? - error.
--
function ExtendedManager:_updateLrMetadataProvider( meta )

    local chg = false
    
    --   P L U G I N   M E T A D A T A   P R O V I D E R
    local mpPath = LrPathUtils.child( _PLUGIN.path, "ExifMeta_MetadataDefinition_AutoGenerated(DoNotEdit).lua" )
    
    local mpOut = {}
    mpOut[#mpOut + 1] = "local metaDefs = {}"
    mpOut[#mpOut + 1] = "metaDefs[#metaDefs + 1] = { id='lastUpdate', title='ExifMeta Updated', version=1, dataType='string', searchable=true, browsable=true }"
    mpOut[#mpOut + 1] = "metaDefs[#metaDefs + 1] = { id='lastUpdate_' }\n"
    if app:getGlobalPref( 'bigBlock' ) then -- must not be read-only or Lightroom chokes (too long for comfort I guess).
        mpOut[#mpOut + 1] = "metaDefs[#metaDefs + 1] = { id='bigBlock', title='Exif Metadata', version=2, dataType='string', readOnly=false, searchable=false, browsable=false }" -- 512 byte limit for searchable strings (could split it...)
    end
    for k,v in tab:sortedPairs( meta ) do
        local outLine
        -- outLine = LOC( "$$$/X=metaDefs[#metaDefs + 1] = { id='^1', title='^2', version=1, dataType='string', readOnly=true, searchable=true, browsable=true }", k, v )
        outLine = LOC( "$$$/X=metaDefs[#metaDefs + 1] = { id='^1', title='^2', version=2, dataType='string', readOnly=true, searchable=true, browsable=true }", k, v ) -- 25/Aug/2011 22:04
            -- version number changed because I couldn't re-install released version of plugin (with released toolkitID) due to a data-type change.
            -- although not necessary for other users, hopefully it won't hurt either (except commiting even an unchaged db will result in a need to update catalog).
        mpOut[#mpOut + 1] = outLine
    end
    mpOut[#mpOut + 1] = "\nreturn {"
    mpOut[#mpOut + 1] = "  metadataFieldsForPhotos = metaDefs,"
    mpOut[#mpOut + 1] = "  schemaVersion = 1,"
    mpOut[#mpOut + 1] = "}"

    local prev = fso:readFile( mpPath )
    local now = table.concat( mpOut, '\n' )
    if (prev == nil) or (prev ~= now) then
        local sts, qual = fso:writeFile( mpPath, now )
        if sts then
            app:logInfo( "Wrote metadata provider lua file: " .. mpPath )
            chg = true
            local time = LrDate.currentTime()
            app:setGlobalPref( 'metaDefTime_', time ) -- raw
            app:setGlobalPref( 'metaDefTime', date:formatDateTime( time ) )
            -- Common.updateSettingsSynopsis()
        else
            return nil, "Unable to update metadata provider lua file, error message: " .. str:to( qual )
        end
    else
        -- no prev, or prev same as before - in either case - still need to update info.lua if changed.
    end

    return chg
    
end



---     Synopsis:           Re-writes Tagsets...lua
--<br>      
--<br>      Notes:              Includes baseline tagset items from configuration, with exif data appended with separators and section headers.
--<br>      
--<br>      Returns:            chg - or throws an error.
--        
function ExtendedManager:_updateLrMetadataTagsetFactory( meta )

    local tagsetBaselines = app:getPref( "tagsetBaselines" )
    
    if tagsetBaselines == nil then
        app:logWarning( "Tagset baseline table (defined in user configuration file) is nil - plugin tagset file will not be updated." )
        return
    end
    
    if tab:isEmpty( tagsetBaselines ) then
        app:logInfo( "Tagset baseline table (defined in user configuration file) is empty - no custom metadata tagsets will be available." )
    end
    

    local path = LrPathUtils.child( _PLUGIN.path, "MetadataTagsets_AutoGenerated(DoNotEdit).lua" )
    local compareTo, orNot = fso:readFile( path )
    if compareTo then
        -- go on
    else
        app:logInfo( "*** Tagset file not found (expected when updating plugin to 2.2.2+ from 2.2.1-, otherwise this may be a problem), error message: " .. str:to( orNot ) )
    end
    
    local tbl = {}
    local index = 1
    
    --   O P E N   R E T U R N   T A B L E
    tbl[index] = 'return {'
    index = index + 1
    
    for id, baseline in pairs( tagsetBaselines ) do
    
        --   H E A D E R   A N D   B A S E L I N E   I T E M S
        tbl[index] = '{'
        index = index + 1
        tbl[index] = 'title = "' .. baseline.title .. '",'
        index = index + 1
        tbl[index] = "id = '" .. id .. "',"
        index = index + 1
        tbl[index] = "items = {"
        index = index + 1
        for i,v in ipairs( baseline.items ) do
            tbl[index] = v .. ","
            index = index + 1
        end
        
        -- E X I F   M E T A
        
        tbl[index] = "'com.adobe.separator',"
        index = index + 1
        tbl[index] = '{"com.adobe.label", label="RC Exif Meta" },'
        index = index + 1
        tbl[index] = "'com.adobe.separator',"
        index = index + 1
        tbl[index] = "'" .. app:getInfo( 'LrToolkitIdentifier' ) .. ".lastUpdate" .. "',"
        index = index + 1
        tbl[index] = "'com.adobe.separator',"
        index = index + 1


        local prefix = ''
        local saveIndex = index
        local prefixCount = 0
        for k,v in tab:sortedPairs( meta ) do
            -- dbg( k, v )
            local prefixPos = k:find( '_' )
            if prefixPos then
                local _prefixPos = k:find( '_', prefixPos + 1 )
                if _prefixPos then
                    prefixPos = _prefixPos
                end
                if prefixPos > 1 then
                    local _prefix = k:sub( 1, prefixPos - 1 )
                    if _prefix ~= prefix then
                        if prefixCount < 1 then
                            index = saveIndex
                        else
                            -- index = 1
                        end
                        prefix = _prefix
                        saveIndex = index
                        prefixCount = 0
                        tbl[index] = "{ 'com.adobe.label', label = '" .. prefix .. "' },"
                        index = index + 1
                    end
                else
                    tbl[index] = "{ 'com.adobe.separator' },"
                    index = index + 1
                end
            else
                tbl[index] = "{ 'com.adobe.separator' },"
                index = index + 1
            end
            
            tbl[index] = "'" .. app:getInfo( 'LrToolkitIdentifier' ) .. "." .. k .. "',"
            index = index + 1
            prefixCount = prefixCount + 1
                        
        end

        if app:getGlobalPref( 'bigBlock' ) then
            tbl[index] = "'com.adobe.separator',"
            index = index + 1
            tbl[index] = "{ formatter = '" .. app:getInfo( 'LrToolkitIdentifier' ) .. ".bigBlock', topLabel=true },"
            index = index + 1
        end

        --   C L O S E   I T E M S   A N D   T A G S E T   T A B L E
        if prefixCount < 1 then
            index = saveIndex
        end
        tbl[index] = '},'
        index = index + 1
        tbl[index] = '},'
        index = index + 1
        
    end

    --   C L O S E   R E T U R N   T A B L E        
    tbl[index] = '}'
    index = index + 1
    
    --   C O N V E R T   T O   W R I T A B L E   S T R I N G
    local tstr = table.concat( tbl, "\n" )
    
    --   W R I T E   T O   F I L E
    local chg
    if compareTo then
        if compareTo ~= tstr then
            app:logInfo( "Updating changed tagset file: " .. path )
            local sts, msg = fso:writeFile( path, tstr )
            if sts then
                chg = true
            else
                error( "Unable to update tagset file: " .. str:to( msg ) )
            end
        else
            app:logVerbose( "Tagset file same: " .. path )
            chg = false
        end
    else
        app:logInfo( "Writing new tagset file same: " .. path ) -- no-tagset error already logged above.
        local sts, msg = fso:writeFile( path, tstr )
        if sts then
            chg = true
        else
            error( "Unable to write new tagset file: " .. str:to( msg ) )
        end
    end
    
    --   R E T U R N   C H A N G E   F L A G
    return chg
    
end



--  Commits included items whether visible or not to database definition, and tagsets.
--
function ExtendedManager:_commit()
    app:call( Call:new{ name="Commit Metadata Definition", async=true, guard=App.guardVocal, main=function( call )
        local s, m = background:pause()
        if not s then
            app:show( { error="Unable to commit, error message: ^1" }, m )
            return
        end
        assert( background.state ~= 'running', "how running?" )
        local nIncluded = 0
        local meta = {}
        for id, t in Common.sortedPairs() do -- prefs sorted by preferred order.
            assert( t ~= nil, "no t" )
            assert( t.id, "no t-id" )
            assert( t.id == id, "t-id mismatch, key: " .. id .. ", t.id: " .. t.id )
            assert( t.include ~= nil, "no t-incl" )
            assert( t.encounters ~= nil, "no t-enc" )
            assert( t.name ~= nil, "no t-name" )
            assert( t.hide ~= nil, "no t-hide, name: " .. t.name )
            if t.include then
                meta[t.id] = t.name
                nIncluded = nIncluded + 1
            end
        end
        app:setGlobalPref( 'included', nIncluded )
        app:logInfo( str:fmt( "^1 configured for inclusion.", str:plural( nIncluded, "metadata item" ) ) )
        if not app:isPluginEnabled() then
            app:show( { warning="You need to enable plugin for exif metadata and update to work." } )
        end
        local chg = self:_updateLrMetadataProvider( meta )
        -- note: its possible for tagset to change due to a config change
        local chg2 = self:_updateLrMetadataTagsetFactory( meta )
        local pfx
        if chg and chg2 then
            pfx = "Metadata definitions and tagsets have changed"
        elseif chg then
            pfx = "Metadata definitions have changed"
        elseif chg2 then
            pfx = "Metadata tagsets have changed"
        end
        if pfx then
            background:quit()
            app:show( pfx .. " - your catalog must be updated. You must reload plugin (which may take several seconds or more) for changes to take effect (hint: Expand Plug-in Author Tools section, and click the 'Reload Plug-in' button, then wait until the blue donut or beach ball stops spinning and/or the reload button pops back out)." )
        else
            if dialog:isOk( "No metadata definitions nor tagsets changed.\n \nDo you want to update database definition time anyway to force metadata updates?\n(not necessary under normal circumstances)" ) then
                local time = LrDate.currentTime()
                app:setGlobalPref( 'metaDefTime_', time ) -- raw
                app:setGlobalPref( 'metaDefTime', date:formatDateTime( time ) )
            end
            background:continue()
        end
    end } )
end



--- Sections for bottom dialog method.
--
function ExtendedManager:sectionsForBottomOfDialogMethod( vf, props )

    assert( props == self.props, "props changed" )	
    
    local ctrlSection = { bind_to_object = prefs } -- assumes pref-mgr.
	ctrlSection.title = app:getAppName() .. " General Settings"
	-- ctrlSection.synopsis = bind { key=app:getGlobalPrefKey( 'settingsSynopsis' ), object=prefs }
	ctrlSection.synopsis = bind {
	    object = prefs,
	    keys = { app:getGlobalPrefKey( 'metaDefTime_' ), app:getGlobalPrefKey( 'included' ), app:getGlobalPrefKey( 'new' ) },
	    transform = function( value, toUi )
	        if app:getGlobalPref( 'metaDefTime_' ) == 0 then
	            return "Metadata Database Uninitialized"
	        else
                return str:fmt( "Database definition: ^1   ^2 included   ^3", app:getGlobalPref( 'metaDefTime' ), app:getGlobalPref( 'included' ), str:plural( app:getGlobalPref( 'new' ), "new item" ) )
	        end
	    end
	}

    ctrlSection[#ctrlSection + 1] =
        vf:row {
            vf:static_text {
                title = "Database definitions updated",
                width = share 'label_width',
            },
            vf:edit_field {
                value = app:getGlobalPrefBinding( 'metaDefTime' ),
                tooltip = "Date/time of last commit that resulted in a database change.",
                width_in_chars = 15,
                width = share 'data_width',
                enabled = false,
            },
        }

    ctrlSection[#ctrlSection + 1] =
        vf:row {
            vf:static_text {
                title = "Number of metadata item rows",
                width = share 'label_width',
            },
            vf:edit_field {
                bind_to_object = props,
                value = bind 'numRows',
                tooltip = "Number of items to present on a page - bigger is better, as long as its still fitting on your monitor.",
                width_in_chars = 6,
                width = share 'data_width',
                precision = 0, -- integer
            },
        }

    ctrlSection[#ctrlSection + 1] =
        vf:row {
            vf:static_text {
                title = "New metadata items last update",
                width = share 'label_width',
            },
            vf:edit_field {
                value = app:getGlobalPrefBinding( 'new' ),
                tooltip = "Number of new items found during the last manual update.",
                width_in_chars = 6,
                width = share 'data_width',
                enabled = false,
                precision = 0, -- integer
            },
        }

    ctrlSection[#ctrlSection + 1] =
        vf:row {
            bind_to_object = props,
            vf:static_text {
                title = "Auto-update control",
                width = share 'label_width',
            },
            vf:checkbox {
                title = "Automatically check most selected photo.",
                value = bind( 'background' ),
                title = "Enable auto-update of most selected photo.",
                tooltip = "If checked, most selected photo will automatically be updated, if need be; if unchecked, manual update may be necessary to assure freshness.",
                width = share 'data_width',
            },
        }
    ctrlSection[#ctrlSection + 1] =
        vf:row {
            bind_to_object = props,
            vf:static_text {
                title = "Auto-update selected photos",
                width = share 'label_width',
            },
            vf:checkbox {
                title = "Automatically update selected photos.",
                value = bind( 'processTargetPhotosInBackground' ),
                enabled = bind( 'background' ),
				-- tooltip = "",
                width = share 'data_width',
            },
        }
    ctrlSection[#ctrlSection + 1] =
        vf:row {
            bind_to_object = props,
            vf:static_text {
                title = "Auto-update whole catalog",
                width = share 'label_width',
            },
            vf:checkbox {
                title = "Automatically update all photos in catalog.",
                value = bind( 'processAllPhotosInBackground' ),
                enabled = bind( 'background' ),
				-- tooltip = "",
                width = share 'data_width',
            },
        }
    ctrlSection[#ctrlSection + 1] =
        vf:row {
            vf:static_text {
                title = "Auto-update status",
                width = share 'label_width',
            },
            vf:edit_field {
                value = app:getGlobalPrefBinding( 'backgroundState' ),
                tooltip = "Status of background task responsible for updating most selected photo.",
                width = share 'data_width',
                enabled = false,
            },
        }
    ctrlSection[#ctrlSection + 1] =
        vf:row {
            vf:static_text {
                title = "ExifTool executable",
                width = share 'label_width',
            },
            vf:edit_field {
                value = app:getGlobalPrefBinding( 'exifToolExe' ),
                tooltip = "Path to exiftool executable file",
                width_in_chars = 36,
            },
            vf:push_button {
                title='Browse',
                action = function( button )
                    local ft
                    local id
                    if WIN_ENV then
                        ft = 'exe'
                    else
                        ft = '*'
                    end
                    local f = app:getGlobalPref( 'exifToolExe' )
                    if str:is( f ) then
                        id = LrPathUtils.parent( f )
                        if not fso:existsAsDirectory( id ) then
                            id = nil
                        end
                    end
                    local file = dia:selectFile( {
                        title = "Select exiftool executable",
                        fileTypes = ft,
                        initialDirectory = id } )
                    if file then -- not canceled.
                        app:setGlobalPref( 'exifToolExe', file ) -- two way binding will set ui field.
                    end
                end
            },
        }
    ctrlSection[#ctrlSection + 1] =
        vf:row {
            vf:static_text {
                title = "XMP Sidecar Handling",
                width = share 'label_width',
            },
            vf:radio_button {
                title = "Raw Only",
                bind_to_object = props,
                value = bind( 'xmpHandling' ),
                checked_value = 'rawOnly',
                tooltip = "Harvest metadata from raw files only - ignore xmp sidecars.",
            },
            vf:radio_button {
                title = "Xmp Priority",
                bind_to_object = props,
                value = bind( 'xmpHandling' ),
                checked_value = 'xmpPri',
                tooltip = "Harvest metadata from raw files and xmp sidecars - duplicate tags in raw are overwritten by xmp value.",
            },
            vf:radio_button {
                title = "Raw Priority",
                bind_to_object = props,
                value = bind( 'xmpHandling' ),
                checked_value = 'rawPri',
                tooltip = "Harvest metadata from raw files and xmp sidecars - duplicate tags in xmp are overwritten by value from raw file.",
            },
            vf:radio_button {
                title = "Xmp Only",
                bind_to_object = props,
                value = bind( 'xmpHandling' ),
                checked_value = 'xmpOnly',
                tooltip = "Harvest metadata from xmp sidecar files only - metadata in raw files will be ignored.",
            },
        }

    
    local appSection = { bind_to_object = prefs } -- assumes pref-mgr.
    
	appSection.title = app:getAppName() .. " Metadata Selection"
	appSection.synopsis = "Click triangle to the left to expand section..." -- bind{ key = 'included', object = props }

	appSection.spacing = 0 -- vf:label_spacing()

	appSection[#appSection + 1] = 
		vf:row {
			vf:push_button {
			    title = "^",
                tooltip = "Sort by inclusion status - included items first, followed by non-included items.",
    	        width = 20, -- share 'col_1',
    	        action = function( button )
    	            app:call( Call:new{ name="Sort by Include", async=false, guard=App.guardSilent, main=function( call )
    	                app:setPref( 'sortField', 'include' )
    	                self:_updateScrollView( true )
    	            end } )
    	        end
			},
			vf:push_button {
			    title = "^",
                tooltip = "Sort by number of unique values items have seen. Thos with the most different values are first...",
    	        width = 20, -- share 'col_2',
    	        action = function( button )
    	            app:call( Call:new{ name="Sort by Encounters", async=false, guard=App.guardSilent, main=function( call )
    	                app:setPref( 'sortField', 'encounters' )
    	                self:_updateScrollView( true )
    	            end } )
    	        end
			},
			vf:push_button {
			    title = "Sort by Name",
                tooltip = "Sort by exif name field",
    	        width = 230, -- share 'col_3',
    	        action = function( button )
    	            app:call( Call:new{ name=button.title, async=false, guard=App.guardSilent, main=function( call )
    	                app:setPref( 'sortField', 'name' )
    	                self:_updateScrollView( true )
    	            end } )
    	        end
			},
			vf:push_button {
			    title = "Sort by ID",
                tooltip = "Sort by exif ID field",
    	        width = 230, -- share 'col_4',
    	        action = function( button )
    	            app:call( Call:new{ name=button.title, async=false, guard=App.guardSilent, main=function( call )
    	                app:setPref( 'sortField', 'id' )
    	                self:_updateScrollView( true )
    	            end } )
    	        end
			},
			vf:push_button {
			    title = "^",
                tooltip = "Sort by 'hidden' field - hidden fields first, followed by unhidden fields.",
    	        width = 20, -- share 'col_last',
    	        action = function( button )
    	            app:call( Call:new{ name="Sort by Hide", async=false, guard=App.guardSilent, main=function( call )
    	                app:setPref( 'sortField', 'hide' )
    	                if app:getPref( 'showHidden' ) then
    	                    self:_updateScrollView( true )
    	                else
    	                    props['showHidden'] = true -- change triggers prefs-to-props call.
    	                end
    	            end } )
    	        end
			},
		}
		
	appSection[#appSection + 1] = 
		vf:spacer {
		    height = 5,
		}
		
    for i = 1, self.page do
    	appSection[#appSection + 1] = 
    		vf:row {
    		    bind_to_object = props,
    			vf:checkbox {
    				value = bind( 'include_' .. i ),
    			    width = 20,
    			},
    			vf:radio_button {
    				value = bind( 'interest_' .. i ),
    			    checked_value = true,
    			    enabled = false, -- program controlled.
    			    width = 20,
    			},
    			vf:edit_field {
    				value = bind( 'name_' .. i ),
    			    font = '<system/small>',
    			    width = 230,
    			},
    			vf:edit_field {
    				value = bind( 'id_' .. i ),
    			    font = '<system/small>',
    			    width = 230,
    			},
    			vf:checkbox {
    				value = bind( 'hide_' .. i ),
    			    width = 20,
    			},
    		}
    end
    
	appSection[#appSection + 1] = 
		vf:spacer {
		    height = 5,
		}
		
	appSection[#appSection + 1] = 
		vf:row {
  		    bind_to_object = props,
  		    spacing = 3,
  		    vf:checkbox {
  		        value = bind 'includeAll',
                tooltip = "If checked, will mark all items in scroll list for inclusion; uncheck to unmark...",
  		    },
			vf:push_button {
				title = "Up",
                tooltip = 'Scroll one row "up" (virtual window goes up, items go down)',
				action = function( button )
				    app:call( Call:new{ name=button.title, main = function( call )
                        local pos = self.scrollView:computeScrollPos( ScrollView.up, 1 )
                        props['scrollPos'] = pos -- triggers prop change that sets scroll pos.
                    end } )
				end
			},
			vf:push_button {
				title = "Down",
                tooltip = 'Scroll one row "down" (virtual window goes down, items go up)',
				action = function( button )
				    app:call( Call:new{ name=button.title, main = function( call )
                        local pos = self.scrollView:computeScrollPos( ScrollView.down, 1 )
                        props['scrollPos'] = pos -- triggers prop change that sets scroll pos.
                    end } )
				end
			},
			vf:push_button {
				title = "Page Up",
                tooltip = 'Scroll one page "up" (virtual window goes up, items go down)',
				action = function( button )
				    app:call( Call:new{ name=button.title, main = function( call )
                        local pos = self.scrollView:computeScrollPos( ScrollView.up )
                        props['scrollPos'] = pos -- triggers prop change that sets scroll pos.
                    end } )
				end
			},
			vf:push_button {
				title = "Page Down",
                tooltip = 'Scroll one page "down" (virtual window goes down, items go up)',
				action = function( button )
				    app:call( Call:new{ name=button.title, main = function( call )
                        local pos = self.scrollView:computeScrollPos( ScrollView.down )
                        props['scrollPos'] = pos -- triggers prop change that sets scroll pos.
                    end } )
				end
			},
			vf:push_button {
				title = WIN_ENV and "Hide Boring Tags" or "Hide Boring", -- shorten row if Mac.
				tooltip = "Display prompt to allow opportunity to mark tags for hiding that are not seeing much action",
				action = function( button )
				    self:_hideBoringTags( button )
				end
			},
			vf:static_text {
			    title = "Scroll-Pos",
			},
			vf:edit_field {
			    value = bind 'scrollPos',
                tooltip = 'Scroll position as row number: 1 is at the "top"...',
			    width_in_chars = 4,
			    min=1,
			    max=10000, -- code will self limit, otherwise Lr like to limit to 100 for some reason.
			    precision = 0, -- zero is the default on Windows, but defaults to 2 on Mac.
			},
			vf:static_text {
			    title = "/",
			},
			vf:edit_field {
			    value = bind 'significant',
			    width_in_chars = 4,
			    enabled = false,
			    precision = 0,
			},
    		vf:spacer {
    		    width = 1,
    		},
  		    vf:checkbox {
  		        value = bind 'hideAll',
  		        tooltip = "Check to mark all items in scroll list to be hidden; uncheck to unmark..."
  		    },
		}
		
	appSection[#appSection + 1] = 
		vf:spacer {
		    height = 5,
		}
		
	appSection[#appSection + 1] = 
		vf:row {
  		    bind_to_object = props,
			vf:checkbox {
			    value = bind 'filterNot',
			    title = "Not",
			    tooltip = "Invert the sense of the filter.",
			    enabled = bind {
			        key = 'filterField',
			        transform = function( value, toUi )
			            if value == 'No Filter' then
			                return false
			            else
			                return true
			            end
			        end
			    }
			},
			vf:combo_box {
			    value = bind 'filterField',
			    tooltip = "Specify which aspect dictates the things to present in the scroll list.",
				items = { "Included", "New", "Interesting", "Name", "ID", "No Filter" },
				width_in_chars = 10,
			},
			vf:edit_field {
			    value = bind 'filterValue',
			    tooltip = "Show only names or IDs containing this substring - case sensitive.",
			    width_in_chars = 20,
			    enabled = bind {
			        key = 'filterField',
			        transform = function( value, toUi )
			            if value == 'Name' or value == 'ID' then
			                return true
			            elseif value == 'Interesting' then -- cheating: using enable transform method to bind interesting filter value.
			                local sts, num = pcall( tonumber, props['filterValue'] )
			                if sts and type( num ) == 'number' then
			                    props['filterValue'] = '' .. num
			                else
			                    props['filterValue'] = '1'
			                end
			                return true
                        else
			                return false
			            end
			        end
			    }
			},
			vf:checkbox {
			    value = bind 'filterRegex',
			    title = "Regex",
			    tooltip = "Treat filter substring text as a lua pattern - for users with a Lua manual only.",
			    enabled = bind {
			        key = 'filterField',
			        transform = function( value, toUi )
			            if value == 'Name' or value == 'ID' then
			                return true
			            else
			                return false
			            end
			        end
			    }
			},
			vf:checkbox {
			    value = bind 'showHidden',
			    title = "Show Hidden",
			    tooltip = "If checked, even hidden fields are shown; if unchecked hidden fields are not shown.",
			},
        }		

    -- Hard to get stuff to keep from spilling off right edge on Mac - resort to new row.
	appSection[#appSection + 1] = 
		vf:spacer {
		    height = 3,
		}
		
	appSection[#appSection + 1] = 
		vf:row {
  		    bind_to_object = prefs,
			vf:push_button {
				title = "Refresh",
				tooltip = "Refresh the items on the scroll list - not necessary unless auto-update has found new stuff while you're viewing the list.",
				width = share 'tailButtons',
				action = function( button )
                   self:_updateScrollView( true )
				end
			},
			vf:push_button {
				title = "Commit",
				tooltip = "Commit to changed inclusion settings and/or changed tagset definitions - if database or tagset definitions have changed, you will need to reload the plugin.",
				width = share 'tailButtons',
				action = function( button )
                   self:_commit() -- wrapped internally.
				end
			},
			vf:checkbox {
				title = "Include exif metadata as one big text block",
				tooltip = "If checked, then *all* exif metadata will appear in the right-hand metadata panel (not usable in library filters or smart collections)",
				value = app:getGlobalPrefBinding( 'bigBlock' ),
			},
        }		
    if not app:isRelease() then
        appSection[#appSection + 1] = vf:spacer{ height=50 }
        appSection[#appSection + 1] = vf:row {
            vf:push_button {
                title = '_test',
                action = function( button )
                    local st5
                    app:call( Call:new{ name=button.title, async=true, main=function( call )
                        local strng = "123"
                        st5 = strng:sub( 1, 5 )
                    end, finale=function( call )
                        Debug.pause( call.status, call.message, st5 )
                    end } )
                end
            },
        }
    end
        
    local sections = Manager.sectionsForBottomOfDialogMethod ( self, vf, props ) -- fetch base manager sections.
    tab:appendArray( sections, { ctrlSection, appSection } ) -- put app-specific prefs after.
    return sections
end



return ExtendedManager
-- the end.