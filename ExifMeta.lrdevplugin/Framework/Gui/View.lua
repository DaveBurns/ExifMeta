--[[
        View.lua
--]]

local View, dbg, dbgf = Object:newClass{ className = 'View' }



--- Constructor for extending class.
--
function View:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function View:new( t )
    local o = Object.new( self, t )
    return o
end



--- Observe ftp setting property changes. ### deprecated.
--
--  @usage *** deprecated
--
--  @param object (table, required) must include 'observeFtpPropertyChanges' table with a named member set to boolean 'true' for each property to be observed.
--  @param props (property-table, required) ftp-settings.
--  @param ftpSettingsName (string, required) name of ftp-settings property.
--  @param checkSetting (function( ftpProps, name, prev, value ), optional) can be used to check the values being set, and return true for 'OK' or false and a warning message if not.
--
--  @usage Call when starting dialog box containing ftp settings.
--  @usage This function was designed to be used in conjunction with<br>
--         the framework object's version of ftp-query-for-password-if-needed, since it will look<br>
--         in the encrypted store for the password saved by this function.
--
function View:observeFtpPropertyChanges( object, props, ftpSettingsName, checkSetting )
    app:call( Call:new{ name="handle password storage", async=true, guard=App.guardSilent, main=function( call )
   
--[[ Typical FTP Settings:
    path = "/testfolder", 
    protocol = "ftp", 
    storePassword = true, 
    password = "dsf", 
    passive = "normal", 
    title = "Untitled FTP", 
    username = "fb159e0f", 
    port = 21, 
    server = "ftp.imemine.com"}
--]]    
        assert( object ~= nil, "no object" )
        if object.observeFtpPropertyChanges == nil then
            -- this case provided so caller can have benefit of password encryption without necessarily observing/checking for legal values.
            object.observeFtpPropertyChanges = { password=true }
        else
            assert( type( object.observeFtpPropertyChanges ) == 'table', "property specs should be table" )
        end
        assert( props[ftpSettingsName] ~= nil, "no ftp settings in props" )
        assert( props[ftpSettingsName].server ~= nil, "no server specified in ftp settings" )
        assert( props[ftpSettingsName].username ~= nil, "username must be specified in ftp settings." )
        assert( props[ftpSettingsName].storePassword ~= nil, "bad props for password storage" )
        
        local saved = tab:copy( props[ftpSettingsName] ) -- make a shallow copy of ftp properties.
        
        -- note password property is cleared when first editing via popup.
        repeat
            if object.observeFtpPropertyChanges['path'] ~= nil then break end
            if object.observeFtpPropertyChanges['protocol'] ~= nil then break end
            if object.observeFtpPropertyChanges['storePassword'] ~= nil then break end
            if object.observeFtpPropertyChanges['password'] ~= nil then break end
            if object.observeFtpPropertyChanges['passive'] ~= nil then break end
            if object.observeFtpPropertyChanges['title'] ~= nil then break end
            if object.observeFtpPropertyChanges['username'] ~= nil then break end
            if object.observeFtpPropertyChanges['port'] ~= nil then break end
            if object.observeFtpPropertyChanges['server'] ~= nil then break end
            if object.observeFtpPropertyChanges['remoteDirPathForFtpUploadTest'] ~= nil then break end
            app:callingError( "No ftp properties to observe" )
        until true

        if checkSetting == nil then
            checkSetting = function( ftpProps, name, prev, value )
                return true -- , value - second return obsolete.
            end
        end
        
        local function processChange( name, prevValue, newValue )
        
            local sts, msg = checkSetting( props[ftpSettingsName], name, prevValue, newValue )
            if sts then
                -- setting approved.
            else
                -- props[ftpSettingsName] = prevValue - this does not do any good, since its after the fact -
                    -- lightroom zeros everything out upon entry, then re-populates upon 'OK' button, at which time,
                    -- the ftp properties are locked in.
                if str:is( msg ) then
                    app:show{ warning=msg }
                -- else ignore setting change without complaint.
                end
                return
            end

            if name == 'password' then            

                local pswd = newValue -- convenience var
                -- Note: unlike the other properties, password property is cleared when ftp settings dialog box is opened, and
                -- then set when user closes the form.
                if prevValue ~= nil and pswd == nil then
                    return
                end
                if pswd == nil then
                    pswd = ""
                end
                
                local chars = pswd:len()
                local charsUi
                if app:isVerbose() then
                    charsUi = str:fmt( " (^1 character) ", chars )
                else
                    charsUi = " "
                end
                local key = str:fmt( "^1_^2_ftp", props[ftpSettingsName].server, props[ftpSettingsName].username ) -- update for sftp support. ###3 must match ftp module.
                local unc = LrPasswords.retrieve( key )

                if unc ~= pswd then
                    local answer
                    if chars > 0 then
                        if str:is( unc ) then
                            answer = app:show{ info="Overwrite password in encrypted store with newly entered^3value (for future ftp to '^1' as '^2')? It is recommended to do so, instead of saving a preset with ftp password in plain text.",
                                subs = { props[ftpSettingsName].server, props[ftpSettingsName].username, charsUi },
                                buttons = { dia:btn( "Yes - use encrypted store", 'ok' ), dia:btn( "No - use preset instead", 'other', false ), }, --  dia:btn( "No", 'cancel' ) },
                                actionPrefKey = "Save password in encrypted store",
                            }
                        elseif props[ftpSettingsName].storePassword then
                            answer = 'ok' -- taking the liberty here - if never been stored in encrypted store, and user is entering a password and is presently willing to store unencrypted...
                        else
                            answer = app:show{ info="Save^3password in encrypted store (for future ftp to '^1' as '^2')? It is recommended to do so, instead of saving a preset with ftp password in plain text.",
                                subs = { props[ftpSettingsName].server, props[ftpSettingsName].username, charsUi },
                                buttons = { dia:btn( "Yes", 'ok' ), dia:btn( "No", 'cancel', false ) },
                                actionPrefKey = "Save password in encrypted store",
                            }
                        end
                    else
                        if str:is( unc ) then
                            local ans = app:show{ info="Clear encrypted password too? - not recommended, unless it is your intention to eliminate all password storage and enter the password each time.",
                                buttons = { dia:btn( "Yes", 'ok' ), dia:btn( "No", 'cancel', false ) },
                                actionPrefKey = "Clear blankened password in encrypted store",
                            }
                            if ans == 'ok' then
                                answer = 'other'
                            else
                                app:logVerbose( "User elected not to clear blankened password in encrypted store." )
                                return
                            end
                        else
                            app:logVerbose( "Don't trip - user will be prompted for password on demand and have option to save encrypted or not." )
                            app:show{ info="No passwords will be stored - you will be prompted each time.",
                                actionPrefKey = "No password stored - prompt instead",
                            }
                            return
                        end
                    end
                    if answer == 'ok' then
                        assert( pswd:len() > 0, "unexpected blank password" )
                        LrPasswords.store( key, pswd )
                        assert( LrPasswords.retrieve( key ) == pswd, "no crypt upd" ) -- will not work if pswd is nil.
                        app:logVerbose( "Entered password saved in encrypted storage." )
                        app:show{ info="Entered password^1has been saved in encrypted storage. If password has already been saved as plain text in a preset, now would be a good time to go blanken it (or uncheck 'Store password in preset') and then update the preset.",
                            subs = charsUi,
                            actionPrefKey = "Entered password saved in encrypted storage",
                        }
                    elseif answer == 'other' then
                        LrPasswords.store( key, "" )
                        assert( not str:is( LrPasswords.retrieve( key ) ), "no crypt clr" )
                        app:logVerbose( "Password that was in encrypted storage has been removed." )
                        app:show{ info="Password that was in encrypted storage has been removed.",
                            actionPrefKey = "Password that was in encrypted storage has been removed",
                        }
                    elseif answer == 'cancel' then
                        app:logVerbose( "User elected not to store password in encrypted store." )
                    else
                        app:error( "bad answer" )
                    end                        
                else
                    app:logVerbose( "Password is already in encrypted store." )
                end    

            end -- password
            
            -- protocol is handled via check function.
            
        end
        
        while not shutdown and object.observeFtpPropertyChanges do

            LrTasks.sleep( .1 ) -- its possible (has happened) that watcher gets cleared while sleeping
            
            if object.observeFtpPropertyChanges ~= nil then
                for k, v in pairs( object.observeFtpPropertyChanges ) do
                    local newValue = props[ftpSettingsName][k]
                    if newValue ~= saved[k] then
                        processChange( k, saved[k], newValue )
                        saved[k] = newValue
                    end
                end
            end
            
        end -- while
        
    end, finale=function( call, status, message )
        if not status then
            app:show{ error=message }
        end
    end } )
end



--- Discontinue observation of ftp setting changes. deprecated.
--
--  @usage *** deprecated
--
--  @usage This must be called when dialog box is ended.
--
function View:unobserveFtpPropertyChanges( object )
    object.observeFtpPropertyChanges = nil
end



--- Get view items for ftp settings as an array of two arrays containing view items, suitable for a two-row display.
--
--  @param object (table, required) Serves as ID for set-observer. May contain ftpPropertyMap member table with elements:<br>
--         * server = { propName='ftpServer', validationMethodName='checkFtpSetting' },<br>
--         * ... ditto for other ftp-settings, and<br>
--         * remoteDirPathForFtpUploadTest = { propName='customUploadDir', validationMethodName='checkUploadDir' },<br>
--         Note: validation method(s) of object take name, value as param and return sts, msg.
--  @param props (LrObservableTable, required) properties passed to start-dialog box...
--  @param enabledBinding (binding table, optional) if passed, all fields enabling will be contingent upon specified binding.
--  @param retItems (boolean, optional) if passed, return items.
--  @param labelOptions (table, optional) if passed, options for labels.
--  @param dataOptions (table, optional) if passed, options for labels.
--
--  @usage once upon a time, it started a task to watch for property changes, so you must call end-ftp-settings-view in end-dialog method - those days are gone..
--  @usage So far, it only works for display directly in plugin manager dialog or export/publish dialog.
--  @usage If you want a different physical arrangement..., you can massage the returned items and re-package...
--  @usage To use:<br>
--         local vi = view:getFtpSettingsViewItems( ftpSettings, props, "getPrefBinding" ) -- bind using app--get-pref-binding method.<br>
--         local view = vf:view{ vf:row( vi[1] ), vf:row( vi[2] ) } -- or<br>
--         <br>
--         local vi = view:getFtpSettingsViewItems( ftpSettings, props ) -- default props binding<br>
--         local view = vf:view{ vf:row( vi[1] ), vf:row( vi[2] ) }
--
--  @return defaultView (LrView) default ftp view.
--  @return viewItems (2-D array of view-items, 1st-D is "row", 2nd-D has 3 view items for the "row") in case you want to massage before creating custom view.
--
function View:startFtpSettingsView( object, props, enabledBinding, retItems, labelOptions, dataOptions )

--[[
    Example FTP Settings:
    ---------------------
        path = "/testfolder", 
        protocol = "ftp", 
        storePassword = true, -- don't care
        password = "dsf", 
        passive = "normal", 
        title = "Untitled FTP", -- don't care.
        username = "fb159e0f", 
        port = 21, 
        server = "ftp.imemine.com"

    Example FTP Property Map Setup:
    -------------------------------
    self.ftpPropertyMap = {
        server = { propName='ftpServer', validationMethodName='checkFtpSetting' },
        ...
    }
--]]    

    if object == nil then
        app:callingError( "Need object." )
    end
    if type( object  ) ~= 'table' then
        app:callingError( "Object must be table." )
    end
    -- property name map ( defaults to same name as ftp-settings table ).
    local map = {
        server = object.ftpPropertyMap and object.ftpPropertyMap.server and object.ftpPropertyMap.server.propName or 'server',
        username = object.ftpPropertyMap and object.ftpPropertyMap.username and object.ftpPropertyMap.username.propName or 'username',
        password = object.ftpPropertyMap and object.ftpPropertyMap.password and object.ftpPropertyMap.password.propName or 'password',
        protocol = object.ftpPropertyMap and object.ftpPropertyMap.protocol and object.ftpPropertyMap.protocol.propName or 'protocol',
        port = object.ftpPropertyMap and object.ftpPropertyMap.port and object.ftpPropertyMap.port.propName or 'port',
        passive = object.ftpPropertyMap and object.ftpPropertyMap.passive and object.ftpPropertyMap.passive.propName or 'passive',
        path = object.ftpPropertyMap and object.ftpPropertyMap.path and object.ftpPropertyMap.path.propName or 'path',
        remoteDirPathForFtpUploadTest = object.ftpPropertyMap and object.ftpPropertyMap.remoteDirPathForFtpUploadTest and object.ftpPropertyMap.remoteDirPathForFtpUploadTest.propName or 'remoteDirPathForFtpUploadTest',
    }
    -- setting validation methods ( may be nil )
    local validationMethodNames = {
        [map.server] = object.ftpPropertyMap and object.ftpPropertyMap.server and object.ftpPropertyMap.server.validationMethodName,
        [map.username] = object.ftpPropertyMap and object.ftpPropertyMap.username and object.ftpPropertyMap.username.validationMethodName,
        [map.password] = object.ftpPropertyMap and object.ftpPropertyMap.password and object.ftpPropertyMap.password.validationMethodName,
        [map.protocol] = object.ftpPropertyMap and object.ftpPropertyMap.protocol and object.ftpPropertyMap.protocol.validationMethodName,
        [map.port] = object.ftpPropertyMap and object.ftpPropertyMap.port and object.ftpPropertyMap.port.validationMethodName,
        [map.passive] = object.ftpPropertyMap and object.ftpPropertyMap.passive and object.ftpPropertyMap.passive.validationMethodName,
        [map.path] = object.ftpPropertyMap and object.ftpPropertyMap.path and object.ftpPropertyMap.path.validationMethodName,
        [map.remoteDirPathForFtpUploadTest] = object.ftpPropertyMap and object.ftpPropertyMap.remoteDirPathForFtpUploadTest and object.ftpPropertyMap.remoteDirPathForFtpUploadTest.validationMethodName,
    }
    
    labelOptions = labelOptions or {}	
    dataOptions = dataOptions or {}	
    
    -- reminder: so far, this only works on export/plugin-manager dialog boxes.
	local ftpPresetPopup = LrFtp.makeFtpPresetPopup( tab:mergeSets( { 
		factory = vf,
	    properties = props,
	    bind_to_object = props,
	    valueBinding = 'ftpSettingsBuf', -- for internal use only - hardcoding should be fine.
	    itemsBinding = 'ftpItems',       -- not sure how this works anyway... ###4
	    width_in_chars = 25; -- determines data-1 width.
	    width = share '_data_1',
	    tooltip = "FTP Presets - select or edit..., but remember to click 'Load FTP Settings From Preset' afterward.",
	    enabled = enabledBinding,
	}, dataOptions ) )
	
	-- compute password-encrypted property:
    local key = str:fmt( "^1_^2_ftp", props[map.server], props[map.username] ) -- , props[map.protocol] ) - I assume the same password would be used whether ftp or sftp.
    local unc = LrPasswords.retrieve( key ) -- encrypted password, unencoded.
    if str:is( unc ) then
  	    props.passwordEncrypted = true
  	else
  	    props.passwordEncrypted = false
  	end
	
	-- encrypt FTP password
	local function encryptPassword()

        local key = str:fmt( "^1_^2_ftp", props[map.server], props[map.username] ) -- , props[map.protocol] ) - I assume the same password would be used whether ftp or sftp.
        local unc = LrPasswords.retrieve( key ) -- encrypted password, unencoded.
        local note = "Note: A chain is only as strong as it's weakest link - consider blankening the password in your FTP preset(s) too..."
        
        local pswd = props[map.password]
        if not str:is( pswd ) then
            if str:is( unc ) then
                local answer = app:show{ confirm="Password to be encrypted is blank, but already encrypted password is not.\n\nDo you want to clear encrypted password?",
                    buttons = { dia:btn( "Yes", 'ok' ) },
                }
                if answer == 'ok' then
                    LrPasswords.store( key, "" ) -- perhaps should store nil, but dunno if that actually clears it ###3. Could test this explicitly, then remove this comment, although it's a very small deal, since it's likely there are very few different server/user passwords being cleared.
                else
                    --return
                end
            else
                app:show{ warning="Can't encrypt a blank password." }
                --return
            end
        elseif unc == pswd then
            props[map.password] = ""
            app:show{ warning="That password was already in encrypted storage - still is: no problem...\n\n^1", note }
        else
            repeat
                if not str:is( props[map.server] ) then
                    app:show{ warning="Passwords are associated with specific servers, therefore 'Server' must not be blank." }
                    break -- return -- Probably OK to fall-through and update password-encrypted property - I don't think it hurts.
                end
                if not str:is( props[map.username] ) then
                    app:show{ warning="Passwords are associated with specific users, therefore 'Username' must not be blank." }
                    break -- return -- Probably OK to fall-through and update password-encrypted property - I don't think it hurts.
                end
                local encrypt = false
                if str:is( unc ) and unc ~= pswd then
                    local answer = app:show{ confirm="Overwrite password in encrypted store (for logging in to ^1 as ^2)?",
                        subs = { props[map.server], props[map.username] },
                        buttons = { dia:btn( "Yes", 'ok' ) },
                    }
                    if answer == 'ok' then
                        encrypt = true
                    end
                else
                    encrypt = true
                end
                if encrypt then
                    LrPasswords.store( key, pswd ) -- note: the scope of this is current plugin only.
                    props[map.password] = ""
                    app:show{ info="Password moved to encrypted store - it will be used for logging in to ^1 as ^2, unless a non-blank password is entered to override it.\n\n^3",
                        subs = { props[map.server], props[map.username], note },
                    }
                -- else nuthin'
                end
            until true
        end
        
        local unc2 = LrPasswords.retrieve( key ) -- encrypted password, unencoded.
        if str:is( unc2 ) then
      	    props.passwordEncrypted = true
      	else
      	    props.passwordEncrypted = false
      	end

	end -- end of password encryption function.

    local r = {}
    local tb = WIN_ENV and "FTP Settings" or "..." -- Mac probably would be too wide with full text width.
    r[#r + 1] =
        {
            vf:static_text( tab:mergeSets( {
                title = "FTP Settings:",
                width = share '_label_1',
                enabled = enabledBinding,
            }, labelOptions ) ),
            vf:static_text( tab:mergeSets( {
                title = str:fmtx( "Select Preset, then click 'Load ^1 From Preset',\nor enter info directly in the fields below.", tb ),
                height_in_lines = 2,
                width = share '_data_1',
	            enabled = enabledBinding,
            }, dataOptions ) ),
            vf:spacer{ width=1 },
        }
    r[#r + 1] =
        {
            vf:static_text( tab:mergeSets( {
                title = "Presets",
                width = share '_label_1',
                enabled = enabledBinding,
            }, labelOptions ) ),
            ftpPresetPopup,
            vf:push_button {
                title = 'Load FTP Settings From Preset',
                tooltip = "Copy settings from FTP preset to fields below.",
	            enabled = enabledBinding,
                action = function( button )
                    app:call( Call:new{ name=button.title, async=true, main=function( call )
                        -- Debug.pause( props.ftpSettingsBuf.passive )
                        if str:is( props[map.server] ) or str:is( props[map.path] ) or str:is( props[map.username] ) then -- check if anything there to worry about...
                            local answer = app:show{ confirm="Overwrite FTP settings with those of selected preset?",
                                buttons = { dia:btn( "OK", 'ok' ) },
                                actionPrefKey = call.name,
                            }
                            if answer ~= 'ok' then
                                return
                            end
                        end
                        -- Note: without the yield, the changed property handler only runs for the first assignment.
                        -- I'm guessing that's because of the silent recursion guarding, but that's not been verified.
                        -- The silent recursion guarding was added, I *think*, so that changes to properties/prefs made within
                        -- the change handler itself would not result in infinite recursion, or at least not result in double (immediate) recursion interference.
                        -- This may be the source of other bugs in this or other plugins. ###2
                        -- Another solution I've employed elsewhere is just to set the property and the preference both, but that assumes nothing else should
                        -- be done by an observer, which may very well not be true in this case (it's been designed with change-callback handler for values validation...).
                        -- Now that I think about it, the check for get-pref in the change handlers could also be the source of a bug or two - hmmmmm... - not sure what to do about it at the moment.
                        props[map.server] = props.ftpSettingsBuf.server
                        LrTasks.yield()
                        props[map.username] = props.ftpSettingsBuf.username
                        LrTasks.yield()
                        props[map.password] = props.ftpSettingsBuf.password -- may be blanked out, so be sure to query...
                        LrTasks.yield()
                        props[map.protocol] = props.ftpSettingsBuf.protocol
                        LrTasks.yield()
                        props[map.port] = props.ftpSettingsBuf.port
                        LrTasks.yield()
                        props[map.path] = props.ftpSettingsBuf.path
                        LrTasks.yield()
                        props[map.passive] = props.ftpSettingsBuf.passive
                        LrTasks.yield()
                        -- Do not do this: - there is a race condition between the following code and the asynchronous change handler.
                        -- -assert( app:getPref( map.server ) == props[map.server], "Server change not propagated to pref" )
                        -- -assert( app:getPref( map.username ) == props[map.username], "Username change not propagated to pref" ) -- fails here without the yield in between server and username prop set.
                        -- -assert( app:getPref( map.path ) == props[map.path], "Server Path change not propagated to pref" )
                        -- etc.
                        app:show{ info="Values from FTP preset have been copied to this form for use. You can use as is, or edit values in this form.",
                            actionPrefKey = str:fmtx( "^1 confirmation", call.name ),
                        }
                    end } )
                end,
            }
        }
    r[#r + 1] =
        {
            vf:static_text( tab:mergeSets( {
                title = "Server",
                width = share '_label_1',
                enabled = enabledBinding,
            }, labelOptions ) ),
            vf:edit_field( tab:mergeSets( {
                bind_to_object = props,
                width = share '_data_1',
                value = bind( map.server ),
                tooltip = "Often something like: ftp.myserver.com or may be same as web server (www.myserver.com). IP address instead of name OK too.",
	            enabled = enabledBinding,
            }, dataOptions ) ),
            vf:static_text {
                title = "FTP server host name, or IP",
                enabled = enabledBinding,
            },
        }
    r[#r + 1] =
        {
            vf:static_text( tab:mergeSets( {
                title = "Server Path",
                width = share '_label_1',
                enabled = enabledBinding,
            }, labelOptions ) ),
            vf:edit_field( tab:mergeSets( {
                bind_to_object = props,
                width = share '_data_1',
                value = bind( map.path ),
                tooltip = "If this starts with a slash, it will be \"absolute\" (root) path. Otherwise, it is relative to server default directory. Trailing slash is a \"don't care\".",
	            enabled = enabledBinding,
            }, dataOptions ) ),
            vf:static_text {
                title = "Base directory for file transfers.",
                enabled = enabledBinding,
            },
        }
    r[#r + 1] =
        {
            vf:static_text( tab:mergeSets( {
                title = "Username",
                width = share '_label_1',
                enabled = enabledBinding,
            }, labelOptions ) ),
            vf:edit_field( tab:mergeSets( {
                bind_to_object = props,
                width = share '_data_1',
                value = bind( map.username ),
                tooltip = "Username for FTP login as provided to you by your FTP service provider.",
	            enabled = enabledBinding,
            }, dataOptions ) ),
            vf:static_text {
                title = "Username for FTP login",
                enabled = enabledBinding,
            },
        }
    r[#r + 1] =
        {
            vf:static_text( tab:mergeSets( {
                title = "Password",
                width = share '_label_1',
                enabled = enabledBinding,
            }, labelOptions ) ),
            vf:password_field( tab:mergeSets( {
                bind_to_object = props,
                width = share '_data_1',
                value = bind( map.password ),            
                tooltip = "Password associated with username for FTP login, as provided to you by your FTP service provider, unless you've changed it. If blank, password will come from encrypted store, or you will be prompted.",
	            enabled = enabledBinding,
            }, dataOptions ) ),
            vf:push_button {
                title = "Encrypt",
                tooltip = "Encrypt and store password associated with this server & user, in a safe place, and blanken here.",
                action = function( button )
                    app:call( Call:new{ name=button.title, async=true, guard=App.guardVocal, main=function( call )
                        encryptPassword()                
                    end } )
                end,                
	            enabled = enabledBinding,
            },
            vf:static_text {
                title = "Password is encrypted",
                visible = bind( 'passwordEncrypted' ),
                enabled = enabledBinding,
            },
        }
    r[#r + 1] =
        {
            vf:static_text( tab:mergeSets( {
                title = "Protocol",
                width = share '_label_1',
                enabled = enabledBinding,
            }, labelOptions ) ),
            vf:popup_menu( tab:mergeSets( {
                bind_to_object = props,
                width = share '_data_1',
                value = bind( map.protocol ),            
                items = { { title='FTP', value='ftp'}, {title='SFTP',value='sftp'} },
                tooltip = "Try FTP if you don't know any better, SFTP if offered by your service provider and/or required.",
	            enabled = enabledBinding,
            }, dataOptions ) ),
            vf:static_text {
                title = "FTP is the norm, SFTP if required.",
                enabled = enabledBinding,
            },
        }
    r[#r + 1] =
        {
            vf:static_text( tab:mergeSets( {
                title = "Port",
                width = share '_label_1',
                enabled = enabledBinding,
            }, labelOptions ) ),
            vf:edit_field( tab:mergeSets( {
                bind_to_object = props,
                width = share '_data_1',
                value = bind( map.port ),            
                min = 0,
                max = 65535,
                precision = 0,
                tooltip = "FTP service providers rarely use non-standard ports, but double-check port number if you can't transfer files.",
	            enabled = enabledBinding,
            }, dataOptions ) ),
            vf:static_text {
                title = "Usually 21 for FTP, 22 for SFTP.",
                enabled = enabledBinding,
            },
        }
    r[#r + 1] =
        {
            vf:static_text( tab:mergeSets( {
                title = "Passive",
                width = share '_label_1',
                enabled = enabledBinding,
            }, labelOptions ) ),
            vf:popup_menu( tab:mergeSets( {
                bind_to_object = props,
                width = share '_data_1',
                value = bind( map.passive ),            
                items = { { title='Normal', value='normal'}, {title='Not Passive',value='none'}, {title="Enhanced",value="enhanced"} },
                tooltip = "Leave at 'Normal' unless not working, or as instructed by your FTP service provider.",
	            enabled = enabledBinding,
            }, dataOptions ) ),
            vf:static_text {
                title = "Connection/transfer mode.",
                enabled = enabledBinding,
            },
        }
    local omitFileUploadTest = app:getPref( 'omitFileUploadTest' )
    local remoteDirTitle = "Remote Dir Path:\n(for Upload Test)"
    local testButtonTooltip
    if not omitFileUploadTest then
        testButtonTooltip = "'Test FTP Settings' tests basic internet connectivity and FTP login, plus a temp-file upload test too - to be sure everything is OK."
        r[#r + 1] =
            {
                vf:static_text( tab:mergeSets( {
                    title = remoteDirTitle,
                    height_in_lines = 2,
                    width = share '_label_1',
                    enabled = enabledBinding,
                    tooltip = "Remote directory sub-path. Target remote directory will be 'Server Path' / 'Remote Dir'. Leading and/or trailing slashes are optional and don't change semantics.",
                }, labelOptions ) ),
                vf:edit_field( tab:mergeSets( {
                    bind_to_object = props,
                    value = bind( map.remoteDirPathForFtpUploadTest ),
                    width = share '_data_1',
                    tooltip = "Leave this field blank to test upload to base directory on server, or enter directory sub-path (relative to base directory). Note: trailing slash is a \"don't care\", but this should *not* include a filename!",
	                enabled = enabledBinding,
                }, dataOptions ) ),
            }
    else
        testButtonTooltip = "'Test FTP Settings' tests basic internet connectivity and FTP login."
        r[#r + 1] =
            {
                vf:spacer( tab:mergeSets( {
                    width = share '_label_1',
                    enabled = enabledBinding,
                }, labelOptions ) ),
                vf:spacer( tab:mergeSets( {
                    width = share '_data_1',
                }, dataOptions ) ),
            }
    end
    local a = r[#r]
    a[#a + 1] =
        vf:push_button {
            title = "Test FTP Settings",
            tooltip = testButtonTooltip,
	        enabled = enabledBinding,
            action = function( button )
                app:call( Call:new{ name=button.title, async=true, guard=App.guardVocal, main=function( call )
                    local answer
                    if omitFileUploadTest then
                        answer = app:show{ confirm="Proceed to test basic internet connectivity and FTP login?",
                            buttons = { dia:btn( "OK", 'ok' ) },
                            actionPrefKey = "FTP test confirmation",
                        }
                    else
                        answer = app:show{ confirm="Proceed to test basic internet connectivity, FTP login, and uploading?\n \n*** NOTE: A temp file will be uploaded to '^1' (relative to '^2') for the purpose of remote clock calibration *and* so you can assure files are uploading to the directory you expect.",
                            subs = { props[map.remoteDirPathForFtpUploadTest], props[map.path] },
                            buttons = { dia:btn( "OK", 'ok' ) },
                            actionPrefKey = "FTP test (including upload) confirmation",
                        }
                    end
                    if answer ~= 'ok' then return end
                    local settings = {
                        server = props[map.server],
                        username = props[map.username],
                        password = props[map.password],
                        path = props[map.path],
                        protocol = props[map.protocol],
                        port = props[map.port],
                        passive = props[map.passive],
                    }
                    if not str:is( settings.server ) then
                        app:show{ warning="'Server' can not be blank." }
                        --call:cancel()
                        return
                    end
                    if not str:is( settings.username ) then
                        app:show{ warning="'Username' can not be blank." }
                        --call:cancel()
                        return
                    end
                    if not str:is( settings.path ) then
                        local answer = app:show{ confirm="'Server Path' is blank - not technically forbidden, but rarely correct - continue?",
                            buttons = { dia:btn( "Continue", 'ok' ) },
                            actionPrefKey = "Server path is blank warning.",
                        }
                        if answer ~= 'ok' then
                            --call:cancel()
                            return
                        end
                    end
                    if not str:is( settings.protocol ) then
                        app:show{ warning="'Server Protocol' can not be blank." }
                        --call:cancel()
                        return
                    end
                    if settings.port == nil then
                        app:show{ warning="'Port' can not be blank." }
                        --call:cancel()
                        return
                    end
                    
                    local ftpSubPath = props[map.remoteDirPathForFtpUploadTest] or ""
                    --Debug.pause( map.remoteDirPathForFtpUploadTest, ftpSubPath )
                    
                    call.scope = LrDialogs.showModalProgressDialog {
                        title = str:fmt( "^1 - ^2", app:getAppName(), call.name ),
                        caption = "Please wait...",
                        cannotCancel = true,
                        functionContext = call.context,
                    }
                    
                    -- ###2 add support for ftp-agg app to test settings.
                    local ftp = Ftp:new{ ftpSettings=settings, autoNegotiate=true }
                    local ok = ftp:queryForPasswordIfNeeded()
                    if not ok then
                        app:logError( "No password." )
                        --call:cancel()
                        return
                    end
                    if str:is( settings.password ) then
                        --Debug.pause() - interferes with modal progress dialog, dang it.
                    else
                        app:error( "'Password' can not be blank." )
                    end

                    app:logV( "Connecting.." )
                    local s, m = ftp:connect() -- Checks for dir existence at root.
                    if s then
                        app:log( "Connected to '^1' as '^2'.", settings.server, settings.username )
                    else
                        app:show{ warning="Unable to connect to '^1' as '^2' - ^3.\n\nCould mean server, username, or password is bad, but could also mean server path is bad: '^4' - consider browsing for the server path (start by selecting 'Edit' on 'Presets' \"drop-down\" menu), but remember to click 'Load FTP Settings From Preset' afterward. Note: if server path starts with '/' it's absolute, otherwise it's relative to server default dir.\n\nIf you can't get this right, contact your FTP service provider. If still no go - consult plugin provider.", settings.server, settings.username, str:to( m ), settings.path }
                        --call:cancel()
                        return
                    end
                    if not omitFileUploadTest then
                        local rfp
                        s, m, rfp = ftp:calibrateClock( LrPathUtils.getStandardFilePath( 'temp' ), ftpSubPath, true ) -- clock calibration is required for getting directory contents which is required for validating upload.
                        local fn = LrPathUtils.leafName( rfp )
                        if s then
                            local tidbit
                            if str:is( props[map.password] ) then
                                tidbit = " - consider encrypting password now"
                            else
                                tidbit = ""
                            end
                            call.scope:done()
                            LrTasks.yield() -- not sure if this is useful.
                            app:show{ info = "Test file uploaded and remote clock calibrated - FTP settings are OK^4.\n \n*** NOTE: A temp file named '^1' remains for now in remote dir '^2' (relative to '^3') but will be deleted as soon as you dismiss this dialog box - consider inspecting with independent FTP client to make sure temp file was uploaded to the directory you expect.\n \nIf files are not uploading to expected location, you need to change server path or remote directory (or both).",
                                subs = { fn, ftpSubPath, settings.path, tidbit },
                            }
                            local s, m = ftp:_pRemoveFile( rfp ) -- remove remote cal file.
                            if s then
                                app:logV( "Removed temp file used for remote calibration: ^1", rfp )
                            else
                                app:logWarning( "Unable to remove remote calibration file: ^1, error message: ^2", rfp, str:to( m ) )
                            end
                        else
                            app:show{ warning="Basic connectivity is OK, but unable to upload test file for remote clock calibration (which is required for validating uploads) - ^1. Server: '^2', Username: '^3'. Server Path '^4' or Remote Dir Path '^5' may not be valid.",
                                subs = { str:to( m ), settings.server, settings.username, settings.path, ftpSubPath or "" },
                            }
                        end
                    else
                        call.scope:done()
                        LrTasks.yield() -- not sure if this is useful.
                        app:show{ info="Basic internet connectivity and FTP login are OK. Note: this does not necessarily mean file transfers will succeed, since they also depend on server path and other settings." }
                    end
                    
                end } )
            end
        }


        --   P R O P E R T Y   W A T C H I N G 

        assert( object ~= nil, "no object" )
        if object.ftpPropertiesToObserve == nil then
            -- this case provided so caller can have benefit of password encryption without necessarily observing/checking for legal values.
            -- object.ftpPropertiesToObserve = { password = true }
            object.ftpPropertiesToObserve = {} -- no longer need to observe password changes.
        else
            assert( type( object.ftpPropertiesToObserve ) == 'table', "property specs should be table (a 'set')" )
        end
        
        local saved = {
            [map.server] = props[map.server],
            [map.username] = props[map.username],
            [map.password] = props[map.password], -- may be blanked out, so be sure to query...
            [map.protocol] = props[map.protocol],
            [map.port] = props[map.port],
            [map.path] = props[map.path],
            [map.passive] = props[map.passive],
            [map.remoteDirPathForFtpUploadTest] = props[map.remoteDirPathForFtpUploadTest]
        }
        
        local function processChange( id, props, name, value )
            app:call( Call:new{ name="Process Change", async=false, guard=App.guardSilent, main=function( call )
        
                if name == map.remoteDirPathForFtpUploadTest then
                    props[name] = Ftp.formatSubPath( value, true ) -- true => trailing slash OK.
                    value = props[name]
                end
            
                local validationMethodName = validationMethodNames[name]
                
                local sts, msg
                if validationMethodName then
                    sts, msg = object[validationMethodName]( object, name, value )
                else
                    sts = true
                end
            
                if sts then
                    -- setting approved - good: all done.
                    saved[name] = props[name]
                else
                    props[name] = saved[name] -- won't trigger a change, due to recustion guard, which is OK, because in essence, it hasn't "changed", so much as it's being put back to where it was.
                    if str:is( msg ) then
                        app:show{ warning=msg }
                    -- else nuthin;
                    end
                end
            end } )
        end
        
        view:setObserver( props, map.remoteDirPathForFtpUploadTest, object, processChange )
        for propName, methodName in pairs( validationMethodNames ) do
            if methodName then
                if object[methodName] ~= nil then
                    if type( object[methodName] ) == 'function' then
                        view:setObserver( props, propName, object, processChange )
                    else
                        app:callingError( "Bad validation method: ^1 - type: ^2", k, type( object[methodName] ) )
                    end
                else
                    app:callingError( "Bad validation method name: ^1", methodName )
                end
            else
                assert( methodName == false, "invalid method name" )
            end
        end

    if retItems then
        return r
    end

    -- create default view        
    local ftpViewItems = {}
    for i, v in ipairs( r ) do
        ftpViewItems[#ftpViewItems + 1] = vf:row( v )
    end
    local ftpView = vf:view( ftpViewItems )
    -- note: r is not what it was at this point.

    return ftpView
end
View.getFtpSettingsView = View.startFtpSettingsView -- function View:getFtpSettingsView(...) -- no longer needing a corresponding "finish" call.



--- Get catalog-photo view in a scroller.
--
--  @param args (table) containing:<br>
--             - photos (array, required) photos to view. <br>
--             - fmtMetaSpecs (array, optional) formatted metadata keys to accompany thumbnails. <br>
--             - fmtMeta (array, optional) formatted metadata to accompany thumbnails. <br>
--             - clickBack (function, optional) callback function for clickage. <br>
--             - viewWidth <br>
--             - viewHeight <br>
--             - thumbWidth <br>
--             - thumbHeight <br>
--
function View:getThumbnailsView( args )
    if app:lrVersion() < 4 then app:callingError( "thumbnails view requires Lr4+" ) end
    local photos = args.photos -- may be nil
    local props = args.props -- may be nil
    local maxThumbs = args.maxThumbs or 100
    app:callingAssert( props or photos, "need static photos or dynamic properties" )
    app:callingAssert( not ( props and photos ), "need static photos or dynamic properties - not both" )
    local fmtMetaSpecs = args.fmtMetaSpecs or { 'fileName' }
    local fmtMeta
    local frame_width
    if #fmtMetaSpecs > 0 and photos then
        fmtMeta = args.fmtMeta or cat:getBatchFormattedMetadata( photos, fmtMetaSpecs )
        frame_width = args.frame_width or 1
    else
        frame_width = args.frame_width -- or 0, the default.
    end
    local frame_width = args.frame_width or ( #fmtMetaSpecs > 0 ) and 1 or 0
    local lookup = {}
    local clickBack = function( viewObject )
        app:call( Call:new{ name="Clickback", async=true, guard=App.guardSilent, main=function( call )
            if args.clickBack then
                args.clickBack( viewObject.photo, viewObject ) -- 2nd param usually ignored, but just in case...
            else
                local photo = viewObject.photo
                if photo then
                    Debug.pause( "You clicked", photo:getFormattedMetadata( 'fileName' ) )
                else
                    Debug.pause( "?" )
                end
            end
        end } )
    end
    assert( args.binding or photos, "need photos or binding" )
    local getPhotoBinding = args.binding and args.binding.getPhotoBinding or function( index ) return photos[index] end
    local getThumbTextBinding = args.binding and args.binding.getThumbTextBinding or function( index ) return photos[index]:getFormattedMetadata( 'fileName' ) end
    local getThumbTextColorBinding = args.binding and args.binding.getThumbTextColorBinding or function( index ) return nil end -- nil => default (black).
    local thumbTextHeight = args.thumbTextHeight or ((fmtMetaSpecs and #fmtMetaSpecs > 0) and #fmtMetaSpecs) or 0
    local vw = args.viewWidth or 800
    local vh = args.viewHeight or 400
    local iw = args.thumbWidth or 200 -- happens to match Adobe default, but it seems like a good number to me too...
    local ih = args.thumbHeight or iw
    local nColumns = args.nColumns or math.max( math.floor( vw / ( iw + 3 ) ), 1 )
    local vi = tab:copy ( args.viewOptions or {} ) 
    vi.width = vw
    vi.height = vh
    vi.bind_to_object = props -- may be nil
    local index = 1
    --[[
    local binding
    if props then -- dynamic
        binding = {}
        for i = 1, maxThumbs do
            binding[#binding + 1] = bind( 'photo_' .. i )
        end
    else -- static photos
        binding = photos        
    end
    --]]
    local nBindings
    if props then
        nBindings = maxThumbs
    else
        nBindings = #photos
    end
    while index <= nBindings do
        local col = {}
        for ci = 1, nColumns do
            if index > nBindings then
                break
            end
            col[#col + 1] =
                vf:catalog_photo {
                    photo = getPhotoBinding( index ),
                    width = iw,
                    height = ih,
                    frame_width = frame_width,
                    frame_color = args.frame_color, -- LrColor( 50, 50, 50 ),
                    background_color = args.background_color, -- LrColor( 100, 100, 100 ),
                    mouse_down = clickBack,
                }
            -- note: formatted metadata to be applied as footnote - header text not supported.
            if fmtMetaSpecs and #fmtMetaSpecs > 0 then
                if photos and fmtMeta then
                    local photo = photos[index]
                    if fmtMeta[photo] then
                        local text = {}
                        for _, spec in ipairs( fmtMetaSpecs ) do
                            if str:is( fmtMeta[photo][spec] ) then
                                text[#text + 1] = fmtMeta[photo][spec]
                            end
                        end
                        local nLines = #text
                        col[#col] = vf:view {
                            col[#col],
                            vf:static_text {
                                title = table.concat( text, "\n" ),
                                height_in_lines = nLines,
                            }
                        }
                    -- else no foot.
                    end
                elseif props then -- contents is a don't care, think of it as a contract...
                    col[#col] = vf:view {
                        col[#col],
                        vf:static_text {
                            title = getThumbTextBinding( index ),
                            width = iw,
                            height_in_lines = thumbTextHeight,
                            text_color = getThumbTextColorBinding( index ),
                            font = args.thumbTextFont, -- seems not dynamically bindable - hmm...
                        },
                    }
                -- else no footnote.
                end
            -- else no footnote text.
            end
            index = index + 1
        end
        if #col > 0 then
            vi[#vi + 1] = vf:spacer{ height = args.spacerHeight or 10 }
            vi[#vi + 1] = vf:row( col )
        end
    end
    local v = vf:scrolled_view( vi )
    return v, vi
end



--- Gets collection browser in the form of a push-button view item.
--
function View:getCollectionBrowser( params )
    local tooltip = params.tooltip or "Browse to collection..."
    --local props = params.bindTo or app:callingError( "need bind-to" )
    --local key = params.bindKey or app:callingError( "need bind-key" )
    local viewOptions = tab:copy( params.viewOptions ) or {}
    viewOptions.title = viewOptions.title or 'Browse'
    local coll -- chosen collection, or nil if none chosen.
    local function chooseCollection( parent )
        local parentName
        if parent == nil then
            parent = catalog
            parentName = "Catalog"
        else
            parentName = parent:getName()
        end
        local sets = parent:getChildCollectionSets()
        local colls = parent:getChildCollections()
        local items = {}
        for i, set in ipairs( sets ) do
            if #set:getChildCollectionSets() > 0 or #set:getChildCollections() > 0 then -- set not empty.
                items[#items + 1] = { title = set:getName(), value=set }
            end
        end
        local nSets = #items
        if #items > 0 then
            items[#items + 1] = { separator = true }
        end
        local nColls = 0
        for i, coll in ipairs( colls ) do
            items[#items + 1] = { title = coll:getName(), value=coll }
            nColls = nColls + 1
        end
        local title
        local subtitle
        if nSets > 0 and nColls > 0 then
            title = "Choose collection or set"
            subtitle = "Collection sets are at top, collections are underneath, with a line separating them."
        elseif nSets > 0 then
            title = "Choose collection set"
            subtitle = "There are no collections in set."            
        elseif nColls > 0 then
            title = "Choose collection"
            subtitle = "There are no collection sets to choose."            
        else
            app:show{ warning="No collections or sets in ^1", parentName }
            return
        end
        title = title .. " from " .. parentName .. " then click 'OK', or click 'Cancel' to abort..."
        local sel = dia:getPopupMenuSelection {
            title = title,
            subtitle = subtitle,
            items = items,
        }
        if sel ~= nil then
            assert( sel.type ~= nil, "no sel type" )
            if sel:type() == 'LrCollection' then
                coll = sel
            elseif sel:type() == 'LrCollectionSet' then
                if #sel:getChildCollectionSets() > 0 or #sel:getChildCollections() > 0 then
                    chooseCollection( sel )
                else
                    app:show{ info="Collection set is empty" } -- no longer happens, right?
                end
            else
                error( "bad sel" )
            end        
        else
            -- don't trip..
        end
    end
    viewOptions.action = function( button )
        app:call( Call:new{ name="Collection Chooser", async=true, main=function( call )
            chooseCollection()
            if coll then
                if params.assign then
                    params.assign( coll )
                else
                    local props = app:callingAssert( params.bindTo, "no assign nor bind-to" )
                    local key = app:callingAssert( params.bindKey, "no assign nor bind-key" )
                    props[key] = coll
                end
            end
        end } )
    end
    viewOptions.tooltip = tooltip
    local browser = vf:push_button( viewOptions )
    return browser
end



--- Get a view item capable of representing the thumbnail of a catalog photo.
--
function View:getThumbnailViewItem( params )
    --local viewOptions = tab:copy( params.viewOptions ) -- in case things get added, it won't keep growing.
    if app:lrVersion() >= 4 then
        return vf:catalog_photo( params.viewOptions )
    else
        local vo = tab:copy( params.viewOptions )
        vo.photo = nil
        vo.height = nil
        vo.width = nil
        vo.height_in_lines = 5
        vo.width_in_chars = 15
        vo.title = " \n    (Thumbnail display\n    requires Lr4+)\n \n" -- leading space is required.
        local vi = vf:static_text( vo )
        return vi
    end
end



--- Add observer, without having duplicate.
--
function View:setObserver( props, name, id, handler )
    props:removeObserver( name, id )
    props:addObserver( name, id, handler )
end



function View:_getPresetPrefNames( presetId )
    return presetId .. "__selNames__", presetId .. "__selName__"
end



function View:getPresetKey( presetId, presetName )
    return presetId .. "_" .. str:makeLuaVariableNameCompliant( presetName )
end


--- Makes a preset popup menu which utilizes callbacks to handle associated preset data, whilst encapsulating preset selection/new/delete.
--
--  @param params (table) with members:
--      <br>presetId (string, required) uniquely identifies this preset popup and it's preference settings.
--      <br>props (propertyTable, required) property table created in calling context. note: initialized afresh from persistent prefs, so no need for it to also be persistent.
--      <br>callback (table, required) members are callback functions:
--          <br>getPresetNames ( function( presetId, app:getPref( presetNamesPref ), app:getPref( selectedPresetNamePref ) ) - returns presetNames, presetName; required ) sort names, or generate default list, ... ).
--          <br>initNewPreset ( function( presetId, presetName, presetKey ) - returns name, m; required ) initialize data associated with specified preset.
--          <br>deletePreset ( function( presetId, presetName, presetKey ) - returns s, m; required ) scrub settings associated with specified preset.
--          <br>selectPreset ( function( presetId, presetName, presetKey ) - returns s, m; required ) function to select preset.
--          <br>isEqual ( function( presetId, presetName, presetKey ) - returns s, m; optional ) function to determine equality - if not passed, then auto-save is assumed.
--      <br>viewOptions (table, optional) view options.
--
function View:makePresetPopup( params )
    local presetPopup
    local s, m = app:call( Call:new{ name="View - Make Preset Popup", async=false, guard=App.guardNot, main=function( icall )
    
        local presetId = params.presetId or app:callingError( "need (unique) preset id" )
        local props = params.props or app:callingError( "need props" )
        local callback = params.callback or app:callingError( "need callback" ) -- could support callback as object with methods. ###2 - wait for demand.
        app:callingAssert( callback.getPresetNames, "callback needs get-names" ) -- filter/sort...
        app:callingAssert( callback.initNewPreset, "callback needs init-new-preset" )
        app:callingAssert( callback.deletePreset, "callback needs delete-preset" )
        app:callingAssert( callback.selectPreset, "callback needs select-preset" )
        local autoSave
        if callback.isEqual == nil then
            dbgf( "no is-equal callback, so auto-save is assumed." )
            autoSave = true
        end
        local presetNamesPref, selectedPresetNamePref = self:_getPresetPrefNames( presetId )
        
        -- *** no need to init preset-names or selected-preset-name prefs, since callback will provide initial value(s).
        
        -- Computes (or recomputes) popup menu items, based on passed names/name or from prefs.
        local function computePopupItems( presetNames, presetName )
        
            local items = {}
            
            local init
            
            if presetNames == nil then
                init = true
                presetNames, presetName = callback.getPresetNames( presetId, app:getPref( presetNamesPref ), app:getPref( selectedPresetNamePref ) ) -- array of names, optionally pre-checked filtered by callback object.
                -- note: if pref indicates empty table, defaults could be initialized..
            end
            if presetName == nil then -- either no names/name, or selection no longer legal within names.
                if str:is( props.popupSel ) and props.popupSel == "__save_as__" or props.popupSel == "__save__" or props.popupSel == "__delete__" then -- this happens when deleting a preset, for example.
                    presetName = nil
                else
                    presetName = props.popupSel
                end
            end
            if type( presetNames ) ~= 'table' then
                --Debug.pause( "setting", presetNamesPref, "to empty table" )
                app:setPref( presetNamesPref, {} )
                presetNames = app:getPref( presetNamesPref ) -- array of preset names.
            elseif tab:isEmpty( app:getPref( presetNamesPref ) ) then
                --Debug.pause( "init..." )
                app:setPref( presetNamesPref, presetNames )
            end
            if not str:is( presetName, 'presetName' ) then
                presetName = ""
                app:setPref( selectedPresetNamePref, presetName )
            elseif app:getPref( selectedPresetNamePref ) == nil then
                local s, m = callback.selectPreset( presetId, presetName, self:getPresetKey( presetId, presetName ) ) -- callback to load data for specified preset.
                if s then
                    app:setPref( selectedPresetNamePref, presetName ) -- save preset selection.
                else -- theoretically this won't happen, since bad presets shouldn't be on the list, but just in case.
                    app:show{ warning="Unable to select preset named '^1' - ^2", presetName, m or "no error message returned" }
                    app:setPref( selectedPresetNamePref, nil )
                    props.popupSel = nil
                end
            end
            
            -- add (ordered) preset names to item list, *and* detect whether preset-name is in preset-names.
            local found
            if not tab:isEmpty( presetNames ) then
                for i, v in ipairs( presetNames ) do
                    items[#items + 1] = { title=v, value=v }
                    if presetName == v then
                        --props.popupSel = v
                        found = v
                    end
                end
            end
            -- initialize popup selection property based on found preset-name, or default to nil.
            if found then
                if str:isStartingWith( found, "__" ) then -- regex ok.
                    Debug.pause() -- @20/Jun/2013 22:07, I don't think this has happened(?).
                    props.popupSel = nil
                else
                    if init then
                        local s, m = callback.selectPreset( presetId, found, self:getPresetKey( presetId, found ) ) -- callback to load data for specified preset.
                        if s then
                            app:setPref( selectedPresetNamePref, found ) -- save preset selection.
                            props.popupSel = found
                        else -- theoretically this won't happen, since bad presets shouldn't be on the list, but just in case.
                            app:show{ warning="Unable to select preset named '^1' - ^2", found, m or "no error message returned" }
                            app:setPref( selectedPresetNamePref, nil )
                            props.popupSel = nil
                        end
                    else
                        props.popupSel = found
                    end
                end
            else
                props.popupSel = nil
            end

            if #items > 0 then
                items[#items + 1] = { separator=true }
            end
            if not autoSave then
                items[#items + 1] = { title="Save", value = "__save__" }
            end
            items[#items + 1] = { title="Save As", value = "__save_as__" }
            items[#items + 1] = { title="Rename", value = "__rename__" }
            items[#items + 1] = { title="Delete", value = "__delete__" }
            items[#items + 1] = { separator=true }
            items[#items + 1] = { title="Reset", value = "__reset__" }
            
            -- finally, save popup items as bound property.
            props.popupItems = items
            
        end

        -- clear all edits.
        local function unedit( reload )
            if autoSave then return end
            local items = {}
            for i, v in ipairs( props.popupItems ) do
                if v.value then
                    if str:isEndingWith( v.value, " - edited..." ) then
                        local uneditName = v.value:sub( 1, #v.value - 12 )
                        if reload then
                            callback.selectPreset( presetId, uneditName, view:getPresetKey( presetId, uneditName ) ) -- load unedited values.
                        end
                        items[#items + 1] = { title=uneditName, value=uneditName }
                    else
                        items[#items + 1] = v
                    end
                else
                    items[#items + 1] = v -- separator
                end
            end
            props.popupItems = items
            props.edited = false
        end
        
        -- called in response to edit change.
        local function editChgHdlr( one, two, key, val )
            if val then -- edited
                if not str:isEndingWith( props.popupSel, '- edited...' ) then
                    local presetName = app:getPref( selectedPresetNamePref ) -- persistently remembered preset name (sans - edited...).
                    assert( not str:isEndingWith( presetName, "- edited..." ), "is ending with - edited, hmm...." )
                    local editedName = presetName .. " - edited..."
                    Debug.pause( editedName )
                    local item = { title=editedName, value=editedName }
                    local items = {}
                    for i, v in ipairs( props.popupItems ) do
                        if v.value == presetName then
                            items[#items + 1] = item
                        else
                            items[#items + 1] = v
                        end
                    end
                    props.popupItems = items
                    props.popupSel = editedName
                -- else already "editing".
                end
            else
                local presetName = app:getPref( selectedPresetNamePref )
                if callback.isEqual and callback.isEqual( presetId, presetName, view:getPresetKey( presetId, presetName ) ) then
                    unedit()
                    props.popupSel = presetName
                else
                    Debug.pause( callback.isEqual )
                end
            end
        end
        
        -- popup *selection* change handler.
        -- *** note: could be selection of command item, or data item.
        local function popupChgHdlr( one, two, id, value )
        
            -- not sure why async, but no problems so far (that I know of) as a result.
            -- not sure why guarded, but probably not a bad idea, since we don't want ganged up commands, nor do we need to double-select a preset..
            app:call( Call:new{ name="Popup Change Handler", async=true, guard=App.guardSilent, main=function( icall )
            
                local prevPresetName = app:getPref( selectedPresetNamePref ) -- save current preset name selection, in case restoral is necessary.
                if prevPresetName == nil then
                    Debug.pause( "no prev preset" )
                    prevPresetName = ""
                end
                
                local prevPopupSel = app:getGlobalPref( 'prevPopupSel' )
                if prevPopupSel == nil then
                    prevPopupSel = prevPresetName
                    app:setGlobalPref( 'prevPopupSel', prevPopupSel )
                end
                if not str:isBeginningWith( value, "__" ) then
                    app:setGlobalPref( 'prevPopupSel', value )
                end
            
                -- pre-condition check
                if value == '__rename__' then -- beware of elseifs.
                    repeat
                        local presetNames = app:getPref( presetNamesPref ) or {} -- currently existing preset names, if there are any.
                        local newPresetName
                        if not str:is( prevPresetName ) then
                            value = '__save_as__' -- if no preset name yet, treat as save-as.
                            break
                        end
                        repeat
                            newPresetName = dia:getSimpleTextInput { -- get potential new name.
                                title = str:fmtx( "^1 - Save As", app:getAppName() ),
                                subtitle="Set name",
                                width_in_chars = 30,
                                init = newPresetName,
                            }
                            if not str:is( newPresetName ) then
                                props.popupSel = prevPresetName
                                return
                            end
    
                            local dup                        
                            for i, nm in ipairs( presetNames ) do
                                if str:isEqualIgnoringCase( nm, newPresetName ) then
                                    app:show{ warning="That name (^1) is already taken - note: to rename, just delete then save as again: nothing will be lost.", nm }
                                    dup = true
                                    break
                                end
                            end
                            
                            if not dup then
                                break
                            end
                            
                        until false
                        
                        assert( str:is( newPresetName ), "pgm fail - no preset name" )
                        
                        local presetKey = self:getPresetKey( presetId, prevPresetName ) -- key for prev name.
                        local s, m = callback.deletePreset( presetId, prevPresetName, presetKey )
                        if s then
                            presetKey = self:getPresetKey( presetId, newPresetName ) -- new key.
                            
                            local s, m = callback.initNewPreset( presetId, newPresetName, presetKey ) -- sel-names probably doesn't matter, but since it's available..
                            -- app:setPref( newPresetName, presetValue ) - this is what init-new-preset does (selName is preset-name).
                            
                            if s then
                                --Debug.pause( "renamed" )
                                local set = tab:createSet( presetNames )
                                set[prevPresetName] = nil
                                set[newPresetName] = true
                                presetNames = tab:createArrayFromSet( set )
                                local newNames = callback.getPresetNames( presetId, presetNames, newPresetName ) or error( "no names" )
                                -- Debug.pause( "setting", presetNamesPref, #newNames, "names for save-as" )
                                app:setPref( presetNamesPref, newNames ) -- save preset names.
                                app:setPref( selectedPresetNamePref, newPresetName ) -- save preset name selected.
                                computePopupItems( newNames, newPresetName ) -- will set popup-sel to match preset-name.
                            else
                                app:show{ warning="Unable to create a new preset named '^1' (in the interest of renaming) - ^2", newPresetName, m or "no error message returned" }
                                props.popupSel = prevPresetName -- perhaps theoretically an attempt should be made to reload, as is done in case of preset-name selection.
                            end
                        else
                            app:show{ warning="Unable to delete preset named '^1' (in the interest of renaming) - ^2", newPresetName, m or "no error message returned" }
                            props.popupSel = prevPresetName -- perhaps theoretically an attemp should be made to reload, as is done in case of preset-name selection.
                        end
                        return
                    until true
                    -- break means no name for rename, thus save-as.
                end
                
                -- note: rename may have been changed to save-as
                
                if value == '__save_as__' or value == '__save__' then
                    local presetNames = app:getPref( presetNamesPref ) or {} -- currently existing preset names, if there are any.
                    local presetName
                    if not str:is( prevPresetName ) or ( str:isBeginningWith( prevPresetName, "__" ) and str:isEndingWith( prevPresetName, "__" ) ) then -- bogus
                        value = '__save_as__' -- if no preset name yet, or current preset name is bogus (yeah, due to a bug no doubt..), treat as save-as.
                    end
                    if value == '__save_as__' then
                        repeat
                            presetName = dia:getSimpleTextInput { -- get potential new name.
                                title = str:fmtx( "^1 - Save As", app:getAppName() ),
                                subtitle="Set name",
                                width_in_chars = 30,
                                init = presetName,
                            }
                            if not str:is( presetName ) then
                                props.popupSel = prevPresetName
                                return
                            end
    
                            local dup                        
                            for i, nm in ipairs( presetNames ) do
                                if str:isEqualIgnoringCase( nm, presetName ) then
                                    app:show{ warning="That name (^1) is already taken - note: to rename, just delete then save as again: nothing will be lost.", nm }
                                    dup = true
                                    break
                                end
                            end
                            
                            if not dup then
                                break
                            end
                            
                        until false
                    else -- prev is legal preset name.
                        presetName = prevPresetName
                    end
                    
                    assert( str:is( presetName ), "pgm fail - no preset name" )
                    
                    local presetKey = self:getPresetKey( presetId, presetName )
                    
                    local s, m = callback.initNewPreset( presetId, presetName, presetKey ) -- sel-names probably doesn't matter, but since it's available..
                    -- app:setPref( presetName, presetValue ) - this is what init-new-preset does (selName is preset-name).
                    
                    if s then
                        if value == '__save_as__' then
                            presetNames[#presetNames + 1] = presetName
                            local newNames = callback.getPresetNames( presetId, presetNames, presetName ) or error( "no names" )
                            --Debug.pause( "setting", presetNamesPref, #newNames, "names for save-as" )
                            app:setPref( presetNamesPref, newNames ) -- save preset names.
                            app:setPref( selectedPresetNamePref, presetName ) -- save preset name selected.
                            computePopupItems( newNames, presetName ) -- will set popup-sel to match preset-name.
                            props.edited = false
                        else -- this clause used to rely on aName returned from init-new-preset, but such is not returned anymore, ###1
                            -- so @25/Mar/2014 19:49, it's same as save-as. Could be consolidated, but presently serving as reminder..
                            Debug.pause( presetName ) -- leave this in until plugins that rely on "Save" feature are validated. ###2
                            local newNames = callback.getPresetNames( presetId, presetNames, presetName ) or error( "no names" )
                            --Debug.pause( "setting", presetNamesPref, #newNames, "names for save-as" )
                            app:setPref( presetNamesPref, newNames ) -- save preset names.
                            app:setPref( selectedPresetNamePref, presetName ) -- save preset name selected.
                            computePopupItems( newNames, presetName ) -- will set popup-sel to match preset-name.
                            props.edited = false
                            app:show{ info="Saved edited '^1'", presetName, actionPrefKey = "Saved preset" }
                        end
                    else
                        app:show{ warning="Unable to create a new preset named '^1' - ^2", presetName, m or "no error message returned" }
                        props.popupSel = prevPresetName -- perhaps theoretically an attempt should be made to reload, as is done in case of preset-name selection.
                    end
                    
                elseif value == '__delete__' then
                    --Debug.pause( presetNamesPref )
                    local presetNames = app:getPref( presetNamesPref ) -- current preset names.
                    if presetNames == nil then
                        Debug.pause( "no names" )
                        return
                    end                    
                    
                    local newNames = {}
                    local found = {}
                    for i, v in ipairs( presetNames ) do
                        if v ~= prevPresetName then
                            newNames[#newNames + 1] = v
                        else
                            found[#found + 1] = v
                        end
                    end
                    if #found > 0 then
                        if #found == 1 then
                            local presetName = found[1]
                            local presetKey = self:getPresetKey( presetId, presetName )
                            local s, m = callback.deletePreset( presetId, presetName, presetKey )
                            if s then
                                --Debug.pause( "setting", presetNamesPref, #newNames, "names after del" )
                                app:setPref( presetNamesPref, newNames )
                                app:setPref( selectedPresetNamePref, nil )
                                app:setGlobalPref( 'prevPopupSel', nil )
                                computePopupItems() -- invokes callback's get-preset-names function (albeit usually overkill, since they don't need sorting), and sets popup-sel to nil.
                                return
                            else
                                app:show{ warning="Unable to delete preset named '^1' - ^2", presetName, m or "no error message returned" }
                            end
                        else
                            app:show{ warning="Unable to delete preset named '^1' - there is more than one preset with that name.", prevPresetName }
                        end
                    elseif str:is( prevPresetName ) then
                        Debug.pause( newNames )
                        app:show{ warning="Unable to delete preset named '^1' - preset not found.", prevPresetName }
                    else
                        app:show{ warning="Unable to delete preset, since no preset is selected." }
                    end
                    props.popupSel = prevPresetName -- restore popup selection to previous.
                    
                elseif value == '__reset__' then
                    local b
                    if callback.isFactoryDefault and callback.isFactoryDefault( presetId, prevPresetName, view:getPresetKey( presetId, prevPresetName ) ) and callback.resetPreset then
                        b = app:show{ confirm="* Reload - reload values previously saved as '^1' (i.e. undo editing...).\n* Reset - revert '^1' to factory default values.\n* Reset All - reset presets to factory default configuration. To be clear: this will remove all user-saved presets.",
                            buttons = { dia:btn( "Reload", 'ok' ), dia:btn( "Reset All", 'resetAll' ), dia:btn( "Reset", 'reset' ) },
                            subs = prevPresetName,
                        }
                    elseif autoSave then
                        b = app:show{ confirm="Are you sure you want to reset all presets to factory default configuration?\n \n*** WARNING: all presets may be deleted.",
                            buttons = { dia:btn( "Yes", 'ok' ) }, -- one button must have verb 'ok'.
                            subs = prevPresetName,
                        }
                        if b == 'ok' then
                            b = 'resetAll' -- translate
                        end
                    else
                        b = app:show{ confirm="* Reload - reload values previously saved as '^1' (i.e. undo editing...).\n* Reset All - reset presets to factory default configuration.",
                            buttons = { dia:btn( "Reload", 'ok' ), dia:btn( "Reset All", 'resetAll' ) },
                            subs = prevPresetName,
                        }
                    end
                    if b == 'ok' then -- reload
                        callback.selectPreset( presetId, prevPresetName, view:getPresetKey( presetId, prevPresetName ) )
                        unedit( false )
                        props.popupSel = prevPresetName -- won't trigger change due to guarding.
                    elseif b == 'reset' then
                        callback.resetPreset( presetId, prevPresetName, view:getPresetKey( presetId, prevPresetName ) )
                        unedit( false )
                        props.popupSel = prevPresetName -- won't trigger change due to guarding.
                    elseif b == 'resetAll' then
                        local newNames, name = callback.getPresetNames( presetId, nil, nil )
                        app:setPref( presetNamesPref, newNames ) -- save preset names.
                        app:setPref( selectedPresetNamePref, name ) -- save preset name selected.
                        computePopupItems( newNames, name ) -- will set popup-sel to match preset-name, if possible.
                        if str:is( name ) then
                            callback.selectPreset( presetId, name, view:getPresetKey( presetId, name ) )
                        end
                        --app:show{ info="Re-initialized presets to factory defaults.", actionPrefKey=str:fmtx( "Re-initialized (^1) presets.", presetId ) }
                        app:show{ info="Presets were re-initialized to factory default configuration." }
                    elseif b == 'cancel' then
                        props.popupSel = prevPopupSel
                    else
                        error( "bad b" )
                    end
                elseif not str:isBeginningWith( value, "__" ) then -- preset name selection
                
                    -- Note: perhaps an easier way to deal with this is to have items where value includes prefix, but title doesn't.

                    local newIsEdited
                    local newPresetName = value
                    if str:isEndingWith( newPresetName, '- edited...' ) then
                        newPresetName = newPresetName:sub( 1, #newPresetName - 12 )
                        newIsEdited = true
                    -- else it is what it is..
                    end
                    
                    local presetKey = self:getPresetKey( presetId, newPresetName )

                    if newPresetName ~= prevPresetName then
                        unedit( true ) -- reload if need be.
                        local s, m = callback.selectPreset( presetId, newPresetName, presetKey ) -- callback to load data for specified preset.
                        if s then
                            app:setPref( selectedPresetNamePref, value ) -- save preset selection.
                            props.popupSel = newPresetName -- not sure why/if this is necessary.
                        else -- theoretically this won't happen, since bad presets shouldn't be on the list, but just in case.
                            app:show{ warning="Unable to select preset named '^1' - ^2", value, m or "no error message returned" }
                            
                            local s, m = callback.selectPreset( presetId, prevPresetName, self:getPresetKey( presetId, prevPresetName ) )
                            if s then
                                props.popupSel = app:getPref( selectedPresetNamePref ) -- worth noting: this would generate a selection change, except it won't (really) since change handler is guarded.
                            else
                                app:show{ warning="Unable to revert to previous preset named '^1' - ^2", prevPresetName, m or "no error message returned" }
                                props.popupSel = nil
                            end
                        end
                    else
                        -- Debug.pause( "same preset - consider better handling of edit flags.", newPresetName, newIsEdited )
                    end
                    
                else
                    app:error( "Unimplemented control value: ^1", value )
                end
            end } )
            
        end -- end of popup change handler.
        
        local args = tab:copy( params.viewOptions or {} )
        args.bind_to_object = props 
        args.value = bind 'popupSel'
        args.items = bind 'popupItems'
        args.width_in_chars = args.width_in_chars or 40 -- maybe a little big, but precedent set by initial motivating application.
        args.tooltip = args.tooltip or "Feel free to name the current dataset, for future reference, by choosing 'Save As'."
        presetPopup = vf:popup_menu( args )
        computePopupItems() -- do everything that needs to be done now.
        view:setObserver( props, 'popupSel', View, popupChgHdlr ) -- maintain when changes occur.
        view:setObserver( props, 'edited', View, editChgHdlr )
        
    end, finale=function( call )
        if not call.status then
            Debug.pause( call.message )
        end
    end } )
    if s then
        assert( presetPopup ~= nil, "no preset popup" )
        return presetPopup
    else
        return nil, str:fmtx( "Unable to make preset popup menu - ^1", m )
    end
end



--- Get preset name and associated data value(s) key, given ID and props - nil => in transition, blank => no preset selected.
--
function View:getPresetName( presetId, props )
    app:callingAssert( props ~= nil, "no props" )
    local presetNamesPref, selectedPresetNamePref = self:_getPresetPrefNames( presetId )
    local presetName = app:getPref( selectedPresetNamePref )
    local popupName = props.popupSel
    
    --[[ it's *probably* important for some (all?) existing plugins that preset name NOT be returned if edited, but this stays
         as a reminder... (the plugin where I almost needed it, dev-preset-lab was the impetus for "auto-save" feature, in which case preset is never "edited").
    if popupName and str:isEndingWith( popupName, " - edited..." ) then
        popupName = popupName:sub( 1, -13 )
    end        
    if presetName and str:isEndingWith( presetName, " - edited..." ) then
        presetName = presetName:sub( 1, -13 )
    end
    --]]
    
    if app:isAdvDbgEna() and str:is( presetName ) then
        local presetNames = app:getPref( presetNamesPref )
        local selSet = tab:createSet( presetNames )
        if not selSet[presetName] then -- there is a preset defined & selected, and therefore it needs to be updated.
            Debug.pause( presetName, #presetNames, presetNames )
        end
    end
    if str:is( presetName ) then
        if popupName == presetName then -- steady state
            return presetName, self:getPresetKey( presetId, presetName )
        else
            --Debug.pause( props.popupSel, presetName ) - generally (always probably), preset-name is the incoming, and popup-sel is the outgoing, thus
            -- it may make more sense to simply return the incoming. As long as callers know to deal with nil, should be OK.
            return nil -- in transition.
        end
    else
        if not str:is( popupName ) then
            return "" -- no preset, but not in transition.
        else
            return nil -- in transition.
        end
    end
end



--- Create items for view of log-file controls (verbose, show, clear).
--
--  @usage assign named items to create view of your choice.
--
--  @param params (table/structure, optional) with named members:
--      <br>    verboseCheckboxViewOptions
--      <br>    showLogsButtonViewOptions
--      <br>    clearLogsButtonViewOptions
--
--  @return table of named items: verboseCheckbox, showLogsButton, clearLogsButton.
--
function View:getLogControls( params )
    local controls = {}
    local cb = tab:mergeSets( {
        title = "Log Verbose",
        bind_to_object = prefs,
        value = app:getGlobalPrefBinding( 'logVerbose' ),
        tooltip = "Check to have extra information logged which might be helpful trouble-shooting. After trouble-shooting, be sure to return to normal mode (uncheck), to avoid excessive logging.",
    }, params.verboseCheckboxViewOptions )
    local show = tab:mergeSets( {
        title = "Show Logs",
        action = function()
            app:showLogFile() -- async.
        end,
        tooltip = "Open log file in default app for .log files.",
    }, params.showLogsButtonViewOptions )
    local clear = tab:mergeSets( {
        title = "Clear Logs",
        action = function()
            app:clearLogFile()
        end,
        tooltip = "Clear logs by deleting log file - it will get recreated if additional info is logged.",
    }, params.clearLogsButtonViewOptions )
    self:setObserver( prefs, app:getGlobalPrefKey( 'logVerbose' ), Manager, Manager.prefChangeHandler )
    controls.verboseCheckbox = vf:checkbox( cb )
    controls.showLogsButton = vf:push_button( show )
    controls.clearLogsButton = vf:push_button( clear )
    return controls
end



--- Create items for view of plugin manager preset (label, preset-dropdown).
--
--  @usage assign named items to create view of your choice.
--  @usage By default, target value is bound to 'pluginManagerPreset' in global prefs, and is NOT initialized by this method.
--  @usage target value is NOT initialized by this method, so initialize externally before presenting dialog box.
--
--  @param params (table/structure, required) with named members:
--      <br>    call (Call class, required) not sure what this is used for, but never tried NOT passing it.
--      <br>    labelViewOptions (table/structure, optional) view options for static-text label control.
--      <br>    presetPopupOptions (table/structure, optional) options for argument to pref-mgr's make-preset-popup method, most notably:
--              <br>    call            - defaults to call passed as top-level param.
--              <br>    valueBindTo     - defaults to prefs
--              <br>    valueKey        - defaults to global pref key whose name is 'pluginManagerPreset'.
--              <br>    callback        - defaults to integrity-checking no-op.
--      <br>    popupViewOptions (table/structure, optional) these can be included as part of the former, or as this var instead.
--
--  @return table of named view items: label, popup.
--
function View:getPluginManagerPresetControls( params )
    app:callingTypeAssert( params, "params", 'table' )
    local call = params.call or app:callingError( "no call" )
    local controls = {}
    local label = tab:mergeSets( {
        title = "Plugin Manager Preset",
    }, params.labelViewOptions )
    local popup = tab:mergeSets( {
        call = call,
        valueBindTo = prefs,
        valueKey = app:getGlobalPrefKey( 'pluginManagerPreset' ),
        callback = function( presetName )
            assert( app:getGlobalPref( 'pluginManagerPreset' ) == presetName, "bad preset name" )
        end,
    }, params.presetPopupOptions )
    popup.viewOptions = tab:mergeSets( {
        width_in_chars = 35,
        tooltip = "Plugin manager preset defines input options in plugin manager, and/or options in \"advanced\" settings (preference backing file), and whichever other plugin preferences (e.g. persistent editable fields in dialog boxes) are tied to plugin manager preset.",
    }, params.popupViewOptions )
    controls.label = vf:static_text( label )
    controls.popup = app.prefMgr:makePresetPopup( popup )
    Debug.pauseIf( popup.valueBindTo[popup.valueKey] == nil, "Plugin manager preset preference/property is not initialized." )
    return controls
end



--- Get (encrypted) password view items.
--
--  @return array with:
--      <br>    editable password field
--      <br>    encryption button.
--      <br>    show password button.
--  
function View:getEncryptedPasswordViewItems( passwordFieldName, props, pwDescr, viewOptions )
    -- app:callingAssert( gbl:getValue( 'LrPasswords' ), "requires lr-passwords" ) - built into framework now.
    app:callingAssert( str:is( pwDescr ), "need pw-descr" )
    local field, button, button2
    field = vf:password_field( tab:mergeSets( {
        value = bind{ key=passwordFieldName, bind_to_object=props },
        width_in_chars = 20,
    }, viewOptions or {} ) )
    button = vf:push_button {
        title = "Encrypt",
        action = function()
            local pwToEncrypt = props[passwordFieldName]
            if not str:is( pwToEncrypt ) then
                app:show{ warning="Enter a password to encrypt." }
                return
            end
            local pwEncrypted = LrPasswords.retrieve( passwordFieldName )
            if str:is( pwEncrypted ) then
                if pwToEncrypt == pwEncrypted then
                    app:show{ info="That password is already encrypted." }
                else
                    repeat
                        local prev = dia:getSimpleTextInput{ title="Encrypting a new password for "..pwDescr, subtitle="Enter previous password for "..pwDescr }
                        if str:is( prev ) then
                            if prev == pwEncrypted then
                                LrPasswords.store( passwordFieldName, pwToEncrypt )
                                app:show{ info="New password is encrypted." }
                                props[passwordFieldName] = ""
                                return
                            else
                                app:show{ warning="Nope - try again." }
                            end
                        else
                            app:show{ warning="Encrypted password has not been changed." }
                            return
                        end
                    until false
                end
            else
                repeat
                    local same = dia:getSimpleTextInput{ title="Encrypting password for "..pwDescr, subtitle="Enter password for "..pwDescr.." again to be sure." }
                    if str:is( same ) then
                        if same == pwToEncrypt then
                            LrPasswords.store( passwordFieldName, pwToEncrypt )
                            app:show{ info="Password is encrypted." }
                            props[passwordFieldName] = ""
                            return
                        else
                            app:show{ warning="Nope - try again." }
                        end
                    else
                        app:show{ warning="Encrypted password has not been changed." }
                        return
                    end
                until false
            end
        end,
    }
    button2 = vf:push_button {
        title = "Info",
        action = function()
            local pwEnt = props[passwordFieldName]
            local pwEnc = LrPasswords.retrieve( passwordFieldName )
            if str:is( pwEnt ) and str:is( pwEnc ) then
                if pwEnt == pwEnc then
                    app:show{ info="Password entered in field is same as password in encrypted storage: '^1' (without the apostrophes) - consider blankening the entry field so others can't access your password.", pwEnt }
                else
                    app:show{ warning="Password entered does not match that in encrypted storage." }
                end 
            elseif str:is( pwEnt ) then
                app:show{ info="Password is not-encrypted - I recommend encrypting it for added security." }
            elseif str:is( pwEnc ) then
                app:show{ info="Password is encrypted." }
            end
        end,
    }
    return { field, button, button2 }
end



--- Determines whether password entered (in props) is same as corresponding value in encrypted store.
--
function View:verifyPassword( passwordFieldName, props )
    local pw = props[passwordFieldName]
    if str:is( pw ) then
        local pwEncrypted = LrPasswords.retrieve( passwordFieldName )
        if pw == pwEncrypted then
            return true
        else
            return false
        end
    else
        return nil
    end
end



--- get (dimiss-for) fiddle view items as members of returned table: fiddle-button, time-field, and units-text.
--  @param params fiddleButtonViewOptions; timeFieldViewOptions; unitsTextViewOptions; props; timePropName;
function View:getFiddleViewItems( params )
    local np = NamedParameters:new( params )
    local call = np:req( 'call' ) -- call is only required parameter.
    local props = np:get( 'props', prefs ) -- pass favored property table, else it will be prefs.
    local timePropName = np:get( 'timePropName', app:getPrefKey( "fiddleTimeInSeconds" ) ) -- key, not name.
    local button = np:get( 'button', 'fiddle' ) -- "result" (button) returned by modal dialog box.
    local fiddleButtonViewOptions = np:get( 'fiddleButtonViewOptions', {} )
    local timeFieldViewOptions = np:get( 'timeFieldViewOptions', {} )
    local unitsTextViewOptions = np:get( 'unitsTextViewOptions', {} )
    np:done() -- that should be all - if others were passed, log a user warning or toss developer an error.
    if props[timePropName] == nil then props[timePropName] = 3 end
    local v = {}
    local valueBinding = bind{ bind_to_object=props, key=timePropName, transform=function(v,toUi) if not toUi then props[timePropName]=v end return v end }
    v.fiddleButton = vf:push_button( tab:addItems( { title="Dismiss for", tooltip="Close this dialog box for a few seconds, so you can fiddle in Lightroom, then resume..", action=function(b) LrDialogs.stopModalWithResult( b, button ) end }, fiddleButtonViewOptions ) )
    v.timeField = vf:edit_field( tab:addItems( { width_in_digits=1, precision=0, min=1, max=9, bind_to_object=props, value=valueBinding }, timeFieldViewOptions ) )
    v.unitsText = vf:static_text( tab:addItems( { title="seconds", }, unitsTextViewOptions ) )
    return v
end



return View
