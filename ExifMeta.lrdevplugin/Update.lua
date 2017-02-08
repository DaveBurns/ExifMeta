--[[
        Update.lua
        
        Handles "Update" file menu item.
--]]


local Update = {} -- register the name of this item in init.lua for conditional dbg support via plugin manager.


local dbg = Object.getDebugFunction( 'Update' )



--- Update target photos.
--
--  @usage      Menu handling function.
--
function Update.main()
    app:call( Service:new{ name="Update Photos", async=true, guard=App.guardVocal, main=function( call )
        local s, m = background:pause() -- must be called from async task.
        if s then
            app:log( "Background process paused." )
        else
            app:show{ warning="Unable to pause background task. Update will proceed despite this anomaly, but you should definitely report this problem!" }
        end
        local photos = catalog:getTargetPhotos() -- whole filmstrip if none selected - returns empty table not nil if no photos.
        local forceUpdate = false
        app:initPref( 'forceUpdate', false )
        if #photos == 0 then
            app:show{ warning="No photos to update." }
            return
        elseif #photos == 1 then
            local button = app:show { confirm="Update 1 selected photo?",
                buttons = { dia:btn( "Yes, if need be", 'ok' ), dia:btn( "Yes, force update", 'other' ) },
                actionPrefKey = "Update one photo",
            }
            if button == 'cancel' then
                call:cancel()
                return
            elseif button == 'other' then
                app:log( "Updating 1 selected photo, by force." )            
                forceUpdate = true
            else
                app:log( "Updating 1 selected photo, if need be..." )            
            end
            -- proceed w/ 1 selected photo.
        else
            local photo = catalog:getTargetPhoto()
            app:initPref( 'forceUpdate', false )
            if photo then -- at least one is selected
                local answer = app:show{ confirm="Update ^1, or just the one most selected?",
                    buttons={ dia:btn( "All Selected", 'ok' ), dia:btn( "Just One", 'other' ) },
                    subs = { str:plural( #photos, "selected photo", true ) },
                    viewItems = { vf:view {
                        bind_to_object = prefs,
                        vf:spacer{ height = 5 },
                        vf:checkbox {
                            title = "Force Update",
                            value = app:getPrefBinding( 'forceUpdate' ),
                        },
                    }},
                    actionPrefKey = "Confirm update of one versus all selected", -- I worry about the "don't ask" feature now that force-update has been added. Oh well, user has control..
                }
                forceUpdate = app:getPref( 'forceUpdate' )
                if answer == 'ok' then -- all selected
                    -- proceed with filmstrip photos.
                    app:log( "Updating filmstrip." )            
                elseif answer == 'other' then -- just one
                    photos = { photo }
                    app:log( "Updating most-selected photo." )            
                elseif answer == 'cancel' then -- cancel
                    call:cancel()
                    return
                else
                    error( "bad answer" )
                end
                if forceUpdate then
                    app:log( "Updating by force." )
                else
                    app:log( "Updating if need be..." )
                end
            else -- nothing is selected, so consider whole catalog, or filmstrip.
                local allPhotos = catalog:getAllPhotos()
                local title
                local answer = app:show{ confirm="Update ^1 in whole catalog, or ^2 in filmstrip?",
                    subs = { str:plural( #allPhotos, "photo", 1 ), str:plural( #photos, "photo", 1 ) },
                    buttons = { dia:btn( "Whole Catalog", 'other' ), dia:btn( "Filmstrip", 'ok' ) },
                    actionPrefKey = "Update whole catalog or filmstrip",
                }
                if answer == 'ok' then
                    -- photos = photos
                    app:log( "Updating filmstrip." )            
                else
                    photos = allPhotos
                    app:log( "Updating whole catalog." )            
                end
            end
        end
        call.photos = photos
        call.scope = LrProgressScope {
            title = str:fmt( "ExifMeta Update (^1)", str:plural( #call.photos, "target", true ) ),
            functionContext = call.context,        
        }
        local new = {}
        local nNew
        call.nChanged = 0
        call.nUnchanged = 0
        call.nAlreadyUpToDate = 0
        call.nMissing = 0
        call.totalNew = 0
        if #call.photos > 1 then
            app:log( "^1 to do.", str:plural( #call.photos, "photo" ) )
            Common.updatePhotos( call, new, forceUpdate )
            nNew = tab:countItems( new )
        else
            nNew = Common.updatePhoto( call.photos[1], call, new, forceUpdate )
        end
        Common.markNew( new ) -- or clear new.
        if nNew > 0 then
            app:logInfo( str:fmt( "There are ^1 new metadata items.", nNew ) )
            call.mandatoryMessage = str:fmt( "There are ^1 new metadata items.", nNew ) -- gets tacked on to final service dialog box, regardless of warnings or errors...
        end
        app:setGlobalPref( 'new', nNew )
    end, finale=function( call )
        background:continue()
        app:log( "^1 changed.", str:plural( call.nChanged, "photo", true ) )
        app:log( "^1 unchanged.", str:plural( call.nUnchanged, "photo", true ) )
        app:log( "^1 already up to date.", str:plural( call.nAlreadyUpToDate, "photo", true ) )
        app:log( "^1 missing.", str:plural( call.nMissing, "photo", true ) )
    end } )
end



Update.main()
