--[[
        Manager.lua
        
        Plugin manager UI support.
--]]

local Manager, dbg, dbgf = Object:newClass{ className = 'Manager' }



--- Constructor for extending class.
--
function Manager:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function Manager:new( t )
    local o = Object.new( self, t )
    o.basePrefChgGate = Gate:new{ max = 50 } -- reminder: extended class needs
        -- Note: it is recommended to also (independently) gate extended classes pref change handlers.
    o.propChgGate = Gate:new{ max = 50 } -- it is recommended to use this in property change handling method of extended class, so calls don't recurse but no changes get lost (i.e. call is gated).
        -- remember: it's possible for multiple gated calls to be executed back-to-back, so use prompt-once parameter of app-show method to eliminate redundent prompts.
        -- I assume 50 will be enough, if not this gate can be overridden in "derived" (extension) class.
    return o
end



--- Initialize global preferences.
--
function Manager:_initGlobalPrefs()
    app:initGlobalPref( 'runCount', 0 ) -- consider building this into base class.
    app:setGlobalPref( 'runCount', app:getRunCount() + 1 ) -- app gets global run-count pref as a number, no errors thrown.
    if app:isVerbose() then
        app:setGlobalPref( 'infoSynopsis', "Logging verbosely" )
    else
        app:setGlobalPref( 'infoSynopsis', "Logging is limited" )
    end
    app:initGlobalPref( 'infoSynopsis', "" )
    app:initGlobalPref( 'username', "" ) -- works out same as -Anonymous-, but without showing as that.
    app:initGlobalPref( 'globalTestData', "initial global test data" )
end



--- Initialize local preferences for specified preset.
--
function Manager:_initPrefs( presetName )
    -- note: verbose-logging pref is initialized as part of framework proper.
    if presetName and presetName:find( "%." ) then -- dump responsibility for existing dot-named presets onto the user. Could auto-migrate, but since prefs are no doubt wonky in such presets anyway, there wouldn't be much point.
        app:logW( "Presets with '.' in their names don't work correctly - please rename '^1' and get rid of the dot(s), or delete it..", presetName )
        app:show{ warning="Presets with '.' in their names don't work correctly - please rename '^1' and get rid of the dot(s), or delete it..", presetName }
    end
    app:initPref( 'testData', "initial test data", presetName )
    app:initPref( 'promptToSaveMetadata', 0, presetName )
end



--- Static method for initializing preferences: both global and non-global.
--
--  @usage      Global preferences used by framework are initialized in init-framework.<br>
--              (I don't think framework is using any non-global preferences at the moment).
--              This function is for initializing preferencea used by application.
--  @usage      Must be called from init module, so preferences are initialized without having to visit plugin manager.
--  @usage      Extended classes should always call this after initializing extended preferences.
--
function Manager.initPrefs()
    if Manager.manager == nil then
        Manager.manager = objectFactory:newObject( 'Manager' )
    end
    Manager.manager:_initGlobalPrefs()
    if app.prefMgr then
        local presetNames = app.prefMgr:getPresetNames() -- including 'Default'.
        for i, presetName in ipairs( presetNames ) do
            --Debug.logn( presetName )
            Manager.manager:_initPrefs( presetName )
        end
    else
        Manager.manager:_initPrefs( nil )
    end
end



--- Static method for updating display property corresponding to pref.
--
function Manager.setProp( name, value )
    if Manager.manager and Manager.manager.props then
        Manager.manager.props[name] = value
    -- else ignore request (plugin manager not displaying the prop anyway).
    end
end



function Manager:presetChangeCallback( v )
    app.prefMgr:switchPreset( self.props )
end



--- Preference change handler.
--
--  <p>Handles change to preferences that are associated with a property table in the plugin manager UI.<br>
--  Examples: adv-dbg-ena, pref-set-name.</p>
--
--  @param      _prefs      Preferences associated with value change.
--  @param      key         raw preference key - not suitable for direct comparison to global pref names.
--  @param      value       New preference value.
--  @param      call        
--
--  @usage      this method is limited to global prefs. prefs tied to preset go through prop-change-handler-method instead.
--  @usage      *** IMPORTANT: The base class method is critical and must be called by derived class.
--  @usage      Changed items are typically changed via the UI and are bound directly to lr-prefs.
--              <br>props are not bound to prefs explicitly/directly, but need to be reloaded if the pref set name changes.
--
function Manager:prefChangeHandlerMethod( _id, _prefs, key, value, call )

    local gate
    local guard
    local async
    if app:isAdvDbgEna() then
        gate = self.basePrefChgGate
    else
        async=true
        guard=App.guardSilent
    end
    --app:pcall{ name="prefChangeHandlerMethod", async=true, guard=App.guardSilent, main=function( call ) -- ###4 changed to async fairly recently (presumably 2012 or 2013) - delete comment if no issues come 2015.
    app:pcall{ name="baseManagerPrefChangeHandlerMethod", gate=gate, guard=guard, async=async, function( call ) -- ###1 changed to gated 27/Sep/2014 17:43 on a trial basis (adv-dbg-only). If all goes well, make it permanent come 2016.

        assert( prefs == _prefs, "pref change handler method is for prefs only" )
        
        local name = app:getGlobalPrefName( key ) 
    
        -- dbg( "Pref Changed: ", str:format( "^1: ^2", key, str:to( value ) ) )
        if name == 'advDbgEna' then
            if value then
                if app:getGlobalPref( 'classDebugEnable' )  then
                    app:setGlobalPref( "classDebugSynopsis", "Active" )
                else
                    app:setGlobalPref( "classDebugSynopsis", "Inactive" )
                end    
                if app:isRelease() then
                    app:show{ info="Advanced debugging is normally done by plugin author, or under plugin author's direction." }
                end
                Debug.init( true )
            elseif value ~= nil then
                app:setGlobalPref( "classDebugSynopsis", "" )
                Debug.init( false )
            end
            
        elseif name == 'classDebugEnable' then
            if value then
                if app:getGlobalPref( 'advDbgEna' ) then
                    app:setGlobalPref( "classDebugSynopsis", "Active" )
                else
                    app:setGlobalPref( "classDebugSynopsis", "" )
                end            
            else
                if app:getGlobalPref( 'advDbgEna' ) then
                    app:setGlobalPref( "classDebugSynopsis", "Inactive" )
                else
                    app:setGlobalPref( "classDebugSynopsis", "" )
                end            
            end    
            
        --[[ *** save for reference:        
        elseif name == 'presetName' then
            assert( self.props, "no props to load preset into" )
            --app:presetNameChange( self.props, key, value ) -
        --]]
        
        elseif name == 'logVerbose' then
            -- this is the same code as app--set-log-verbose
            app.logr:enable{ verbose = value }
            if value then
                app:setGlobalPref( 'infoSynopsis', "Logging verbosely" )
                app:logv( "Logging is now verbose." )
            else
                app:setGlobalPref( 'infoSynopsis', "Logging is limited" )
                app:log( "Logging is now limited." )
            end
        else
            -- ?
        end
    end, finale=function( call )
        --
    end }
end



--- Plugin manager property change handler.
--
--  @usage          Handles changes to property table for UI elements that are NOT specifically/directly bound to a lr-preference.
--  @usage          By default, this method simply sets the corresponding preference which may be from a named set, or the unnamed (default) set.
--  @usage          *** IMPORTANT: Derived class may need to call base class method, or at a minimum, make sure changed prefs are set.
--
function Manager:propChangeHandlerMethod( props, name, value )
    app:setPref( name, value )
end



--- Start dialog method.
--
--  @usage      *** IMPORTANT: The base class method is critical and must be called by derived class,
--              <br>AFTER initializing all the pref values, so they get loaded into props.
--
function Manager:startDialogMethod( props )

    self.props = props
    dia:clearPromptOnce()
    
    -- dbg("loading props corresponding to set ", app:getGlobalPref( 'presetName' ) )
    app:switchPreset( props )
    
    view:setObserver( prefs, app:getGlobalPrefKey( 'advDbgEna' ), Manager, Manager.prefChangeHandler )
    view:setObserver( prefs, app:getGlobalPrefKey( 'classDebugEnable' ), Manager, Manager.prefChangeHandler )
    --view:setObserver( prefs, app:getGlobalPrefKey( 'presetName' ), Manager, Manager.prefChangeHandler ) - *** save for reference.
    view:setObserver( prefs, app:getGlobalPrefKey( 'logVerbose' ), Manager, Manager.prefChangeHandler )
   
    if props ~= prefs then
        for k in props:pairs() do
            dbg( "Manager registering property observer for:", k )
            -- *** Save for a while: props:addObserver( k, Manager.propChangeLegacyHandler ) -- the old way - possible to get redundent change handling, or worse
                -- if user clicks another plugin, then back to this one, it will add another observer.
            view:setObserver( props, k, Manager, Manager.propChangeHandler ) -- the new way - only one call to change handler per change.
        end
    end

    self.dialogEnded = false
    LrTasks.startAsyncTask( function()
        app:sleep( math.huge, 1, function() -- ###1 really, this should be a property, not a global preference - Lr is now saving changed prefs dynamically!
            app:setGlobalPref( 'managerPeriodicUpdate', not app:getGlobalPref( 'managerPeriodicUpdate' ) ) -- a simple 1-sec toggle, in case
            props.managerPeriodicUpdate = not props.managerPeriodicUpdate
                -- extended class has something to check/update periodically.
            return self.dialogEnded
        end )
    end )
    
end



--- Sections for top of dialog method.
--
--  @usage      Derived class is free to call to include standard sections, or override completely...
--
function Manager:sectionsForTopOfDialogMethod( vf, props )

    self.props = props

    local infoSection = { bind_to_object = prefs }
    
    local compatStr = app:getCompatibilityString()
    
    infoSection.title = app:getPluginName()
    -- infoSection.synopsis = compatStr
    infoSection.synopsis = 	bind{ key=app:getGlobalPrefKey( 'infoSynopsis' ), object=prefs }
	infoSection.spacing = vf:label_spacing()

    infoSection[#infoSection + 1] = 
		vf:row {
			vf:static_text {
				title = compatStr,
			},
			vf:static_text {
				title = 'Author: ' .. app:getAuthor(),
			},
			vf:static_text {
				title = "Author's Website: " .. app:getAuthorsWebsite(),
			},
		}
		
	infoSection[#infoSection + 1] = vf:spacer{ height=5 }
	
-- BEGIN CONDITIONAL buyPlugin

    local buyUrl = app:getInfo( "buyUrl" ) or false
    
    -- get rid of button if copy is licensed?
    
    if buyUrl then
    
    	infoSection[#infoSection + 1] = 
    		vf:row {
    			vf:push_button {
    				title = "Buy " .. app:getPluginName(),
    				font = "<system/bold>",
    				width = share( "button_width" ),
    				action = function( button )
    				    app:call( Call:new{ name = "Buy", main=function()
                            LrHttp.openUrlInBrowser( buyUrl )
                        end } )
    				end
    			},
    			vf:static_text {
    				title = str:format( "Go to website with purchasing info..." ),
    			},
    		}
    end

-- END CONDITIONAL buyPlugin

-- BEGIN CONDITIONAL donate

    local donateUrl = app:getInfo( "donateUrl" ) or false
    
    if donateUrl then
    	infoSection[#infoSection + 1] = 
    		vf:row {
    			vf:push_button {
    				title = "Donate",
    				font = "<system/bold>",
    				width = share( "button_width" ),
    				action = function( button )
    				    app:call( Call:new{ name = "Buy", main=function()
    	                    LrHttp.openUrlInBrowser( donateUrl )
                        end } )
    				end
    			},
    			vf:static_text {
    				title = str:format( "Go to website with donation information and donation link.\nTo donate more than $1 - use the 'Quantity' field - thank you!\nDonations assure continued support for the plugins you use, and more plugins...\n(not to mention being a great way to simply express your appreciation)" ),
    			},
    		}
    end

-- END CONDITIONAL donate

    if buyUrl or donateUrl then
    	infoSection[#infoSection + 1] = vf:spacer{ height=5 }
    	infoSection[#infoSection + 1] = vf:separator{ fill_horizontal = 1 }
    end
	infoSection[#infoSection + 1] = vf:spacer{ height=5 }
	
	infoSection[#infoSection + 1] = 
		vf:row {
			vf:push_button {
				title = "Reset Prompt Dialogs",
				width = share( "button_width" ),
				action = function( button )
				    app:resetWarningDialogs()
                    app:show{ info="Prompt dialogs have been reset." }
				end
			},
			vf:static_text {
				title = LOC( '$$$/X=Show ^1 dialog boxes previously marked "Do Not Show".', app:getAppName() ),
			},
		}

    local cbRow = {}		
		
-- BEGIN CONDITIONAL updateOption

    if app:getInfo( "xmlRpcUrl" ) then
    	infoSection[#infoSection + 1] = 
    		vf:row {
    			vf:push_button {
    				title = "Check for Update",
    				width = share( "button_width" ),
    				action = function( button )
                        app:checkForUpdate()
    				end
    			},
    			vf:static_text {
    				title = str:format( "Check for newer version of ^1 via the internet.", app:getPluginName() ),
    			},
    		}
        infoSection[#infoSection + 1] =
    		vf:row {
    			vf:push_button {
    				title = "Update Plugin",
    				width = share( "button_width" ),
    				action = function( button )
                        app:updatePlugin()
    				end
    			},
    			vf:static_text {
    				title = str:fmtAmp( "Update plugin to newer version (must be downloaded && unzipped already).", app:getPluginName() ),
    			},
    		}
    end


-- END CONDITIONAL updateOption

	infoSection[#infoSection + 1] = 
		vf:row {
			vf:push_button {
				title = "View Logs",
				width = share( "button_width" ),
				action = function( button )
                    app:showLogFile()
				end
			},
			vf:static_text {
				title = str:format( "Show log file using default app." ),
			},
		}
	
	infoSection[#infoSection + 1] = 
		vf:row {
			vf:push_button {
				title = "Clear Logs",
				width = share( "button_width" ),
				action = function( button )
				    app:call( Call:new{ name=button.title, async=true, guard=App.guardSilent, main=function( call )
                        app:clearLogFile()
                    end } )
				end
			},
			vf:static_text {
				title = str:format( "Clear log file by moving it to trash." ),
			},
		}
	
-- BEGIN CONDITIONAL problemReportOption

    local problemReportOption = app:getInfo( 'problemReportOption' )
    if problemReportOption == nil then
        problemReportOption = true
    end
    if problemReportOption then	
    	infoSection[#infoSection + 1] = 
    		vf:row {
    		    vf:push_button {
        			title = "Report Problem", -- "Send Logs to " .. app:getAuthor(),
        			width = share( "button_width" ),
        			action = function( button )
        			    app:call( Call:new{ name = "Send log file", guard = App.guardVocal, main = function( context , ... )
        			        local contents, message = app:getLogFileContents()
        			        if contents then
        			            local ok = dialog:putTextOnClipboard{ title="Copy Log Contents To Clipboard", contents=contents }
        			            if ok then
        			                LrHttp.openUrlInBrowser( "mailto:rob@robcole.com?subject=" .. app:getPluginName() .. " - Problem Report" .. "&body=Replace this text with the contents of the log file, which should still be on the clipboard, which you can paste by clicking anywhere in the body of the email, then pressing " .. app:getCtrlKeySeq( 'V' ) .. ". Then, make sure you include a detailed explanation of the problem you've encountered, and if possible - the steps that will be required for me to reproduce the problem. There should be a dialog box open in Lightroom with more instructions..." ) -- Drive-by (does not wait).
                                    app:show{ info="Your browser should have opened your mailer with a new email message to send.\n\nIf you haven't already done so, please paste the log contents from the clipboard into the body of the email (first click anywhere in the body of the email, then press ^1), then send.", app:getCtrlKeySeq( 'V' ) }
        			            else
        			                --
        			            end
        			        else
        			            app:show{ error="Unable to get log contents, error message: ^1", message }
        			        end
        			     
        			    end, finale = function( call, status, message )
        			        if status then
                            else
                                app:show{ error="Unable to send logs, error message: ^1", message }
                            end
                        end } )
        			end
       			},
    			vf:static_text {
    				title = str:fmt( "Report problem with ^1 to ^2.", app:getPluginName(), app:getAuthor() ),
    			},
    		}
    end

-- END CONDITIONAL problemReportOption

-- BEGIN CONDITIONAL updateOption

    if app:getInfo( "xmlRpcUrl" ) then
        if gbl:getValue( "xmlRpc" ) then
            if xmlRpc.url then
            	cbRow[#cbRow + 1] = 
            		vf:checkbox {
            			title = "Check for updates upon startup.",
            			value = app:getGlobalPrefBinding( 'autoUpdateCheck' ),
            		}
            else
                error( "xml-rpc url must be specified in init.lua" )
            end
        else
            error( "xml-rpc object must be instantiated to support update-option - hint: define url in config file." )
        end
    end
		
-- END CONDITIONAL updateOption


	infoSection[#infoSection + 1] = vf:spacer{ height=5 }
		
	
    cbRow[#cbRow + 1] = 
		vf:checkbox {
			title = "Verbose Logging",
			value = app:getGlobalPrefBinding( 'logVerbose' ),
		}
		
-- BEGIN CONDITIONAL updateOption
    if app:getInfo( "xmlRpcUrl" ) then
        cbRow[#cbRow + 1] = vf:spacer{ fill_horizontal = 1 }
        cbRow[#cbRow + 1] = 
    		vf:push_button {
    			title = "Uninstall",
    			width = share 'width_button_2',
    			tooltip = "Uninstall " .. app:getPluginName(),
    			action = function( button )
                    app:uninstallPlugin()
    			end
    		}
    end
-- END CONDITIONAL updateOption

    
	infoSection[#infoSection + 1] = vf:row( cbRow )
	
	
	infoSection[#infoSection + 1] = vf:row {
	    vf:static_text {
	        --width = share 'button_width',
	        title = "Log Folder",
	    },
	    vf:edit_field {
	        -- bind_to_object is prefs
	        value = app:getGlobalPrefBinding( 'logDir' ),
	        width_in_chars = 45,
	        tooltip = "Enter path or browse for directory in which to store log file; leave blank and Lightroom will choose for you (documents folder).",
	    },
	    vf:spacer {
	        -- bind_to_object is prefs
	        width = 1,
	        fill_horizontal= 1,
	    },
	    vf:push_button {
	        title = "Browse",
 			width = share 'width_button_2',
	        action = function( button )
	            app:call( Call:new{ name=button.title, async=true, guard=App.guardVocal, main=function( call )
	                call.dfltDir = LrPathUtils.child( cat:getDir(), "Logs" )
	                if not LrFileUtils.exists( call.dfltDir ) then
	                    LrFileUtils.createAllDirectories( call.dfltDir )
	                    call.okToDelete = true -- wasn't existing - just created (must check other things too though, since user could populate and/or choose while dialog open).
	                end
    	            local logDir = dia:selectFolder(
    	                { title = "Choose 'Logs' folder in catalog directory (recommended), or choose preferred location for plugin log files.",
    	                  canCreateDirectories = true, -- this is for a button to create dir - not seen on Windows, maybe Mac.
    	                  initialDirectory = call.dfltDir,
    	                  -- prompt = "Choose", - not supported by folder chooser.
    	                } )
    	            if logDir and logDir ~= app:getGlobalPref( 'logDir' ) then
    	                app:show{ info="^1 will store log files in '^2' directory once plugin is reloaded or Lightroom is restarted.",
    	                    app:getAppName(),
    	                    logDir,
    	                }
    	                app:setGlobalPref( 'logDir', logDir )
    	            end
    	        end, finale=function( call )
    	            if call.okToDelete and app:getGlobalPref( 'logDir' ) ~= call.dfltDir and LrFileUtils.isEmptyDirectory( call.dfltDir ) then
    	                LrFileUtils.delete( call.dfltDir )
    	            end
    	        end } )
	        end,
	    },
	}
	
		
		
	--   C L A S S    D E B U G 

    local advDbgSection
	
	--if not app:isRelease() then
	if true then -- I suppose it cant hurt anything too much(?)
	
        advDbgSection = { bind_to_object = prefs }
        
    	advDbgSection.title = "Debug"
    	advDbgSection.synopsis = bind {
    	    keys = { app:getGlobalPrefKey( 'advDbgEna' ), app:getGlobalPrefKey( 'classDebugEnable' ) },
    	    bind_to_object=prefs,
    	    transform = function()
	            if app:getGlobalPref( 'advDbgEna' ) then
	                if app:getGlobalPref( 'classDebugEnable' ) then
	                    return "Restricted"
	                else
	                    return "Enabled"
	                end
	            else
	                return "Disabled"
	            end
    	    end
    	}
    	    
    	advDbgSection.spacing = vf:label_spacing()
    	
    	advDbgSection[#advDbgSection + 1] = 
    	    vf:row {
    	        vf:push_button {
    	            title = "Reset Selected Prompts",
    	            action = function( button )
    	                app:call( Call:new{ name=button.title, async=true, guard=App.guardSilent, main=function( call )
    	                    local items = {}
    	                    local lookup = {}
    	                    local enaPfx = "actionPrefKey_enabled_"
    	                    local answerPfx = "actionPrefKey_answer_"
    	                    local friendlyPfx = "actionPrefKey_friendly_"
    	                    local enaPfxLen = enaPfx:len()
                            for k, v in app:getGlobalPrefPairs() do -- works with pref-mgr or none
                                if str:isBeginningWith( k, enaPfx ) and v then -- apk enabled.  up 'til 25/Apr/2014 2:52 ena-pfx was being interpreted as regex.
                                    local friendlySfx = k:sub( enaPfxLen + 1 )
                                    local enaName = enaPfx .. friendlySfx
                                    local ansName = answerPfx .. friendlySfx
                                    local friendlyName = friendlyPfx .. friendlySfx
                                    local friendly = app:getGlobalPref( friendlyName )
                                    items[#items + 1] = friendly
                                    lookup[friendly] = { enaName, ansName, friendlyName } 
                                end
                            end
                            if #items > 0 then
                                local item = dia:getComboBoxSelection{
                                    title = "Reset Selected Prompts",
                                    subtitle = 'Select prompt to be reset...',
                                    items = items,
                                }
                                if item then
                                    local t = lookup[item]
                                    if t then
                                        app:setGlobalPref( t[1], false ) -- disable
                                        app:setGlobalPref( t[2], "" ) -- kill answer.
                                        app:setGlobalPref( t[3], "" ) -- kill friendly string.
                                        app:show{ info="'^1' prompt has been reset.", item }
                                    else
                                        error( "no item lookup" )
                                    end
                                -- else canceled.
                                end
                            else
                                app:show{ info="No prompts to reset." }
                            end
                                
    	                end } )
    	            end,
    	        },
    	        vf:static_text {
    	            title = "Reset selected prompt, if you can figure out which one - hint: rollover 'Do Not Show' boxes for prompt ID."
    	        },
    	    }
    	advDbgSection[#advDbgSection + 1] = vf:spacer{ height=5 }
    	
    	advDbgSection[#advDbgSection + 1] = 
    		vf:row {
        		vf:checkbox {
        			title = "Enable Advanced Debug",
        			value = app:getGlobalPrefBinding( 'advDbgEna' ),
        		},
        		vf:push_button {
        			title = "Clear Log",
        			enabled = app:getGlobalPrefBinding( 'advDbgEna' ),
        			action = function( button )
        			    app:clearDebugLog() -- wrapped internally
                    end,
        		},
        		vf:push_button {
        			title = "Show Log",
        			enabled = app:getGlobalPrefBinding( 'advDbgEna' ),
        			action = function( button )
        			    app:showDebugLog() -- wrapped internally.
                    end,
        		},
        		vf:push_button {
        			title = "Debug Script",
        			enabled = app:getGlobalPrefBinding( 'advDbgEna' ),
        			action = function( button )
        			    app:call( Call:new { name='Debug Script', async=true, guard=App.guardVocal, main=function( call )
                            if gbl:getValue( "DebugScript" ) then
                                DebugScript.showWindow()
                            else
                                app:show{ error="DebugScript.lua has not been loaded." }
                            end
                        end } )
                    end,
        		},
                vf:push_button {
                    title = "Debug Options",
        			enabled = app:getGlobalPrefBinding( 'advDbgEna' ),
                    tooltip = "set an editor for displaying files...",
                    action = function( button )
        			    app:call( Call:new { name='Debug Script', async=true, guard=App.guardVocal, main=function( call )
                            Debug.showOptionsWindow()
                        end } )
                    end
                },           
        		vf:checkbox {
        			title = "Go Until Error",
        			bind_to_object = LrPrefs.prefsForPlugin( _PLUGIN.id..".Debug" ), -- ###3
        			value = bind( 'goUntilError' ),
        		},
    		}

    	advDbgSection[#advDbgSection + 1] = vf:spacer { height = 5 }
    	advDbgSection[#advDbgSection + 1] = vf:row {
		    vf:checkbox {
			    value = app:getGlobalPrefBinding( 'classDebugEnable' ),
			    enabled = app:getGlobalPrefBinding( 'advDbgEna' ),
				title = "Restrict debugging to selected classes only:",
			},
			vf:spacer{ fill_horizontal = .4 }, -- right-justify run-count.
			vf:static_text {
			    title = "Run Count: "..app:getRunCount(),
			},
			vf:spacer{ fill_horizontal = .2 }, -- keep run-count somewhat away from right wall.
		}
    	advDbgSection[#advDbgSection + 1] = vf:separator { fill_horizontal = 1 }

    	local items = Object.getClassItems()
    	local columns = 3
        local rowItems = {}
    	for i = 1, #items do
    	
            repeat
    	
                local fullClassName = items[i]
                
                -- dbg( "Item: ", fullClassName )
    
                local propKey = Object.classRegistry[fullClassName].propKey
                local pqClassName
                local subd, count = fullClassName:gsub( "%.", "." ) -- count dots.
                if count == 0 then
                    pqClassName = fullClassName -- extension would be "".
                else
                    pqClassName = string.rep( ".", count ) .. LrPathUtils.extension( fullClassName ) -- replace base classes with dots.
                end
                
                app:initGlobalPref( propKey, false )
                
        	    rowItems[#rowItems + 1] = vf:checkbox {
        		    title =  pqClassName,
        		    value = app:getGlobalPrefBinding( propKey ),
        		    enabled = LrBinding.andAllKeys( app:getGlobalPrefKey( 'classDebugEnable' ), app:getGlobalPrefKey( 'advDbgEna' ) ),
        		    width = share( "col_width" ),
        		}
        		if #rowItems == columns then
                    advDbgSection[#advDbgSection + 1] = vf:row( rowItems )
                    rowItems = {}
                end
        		
        	until true
        	
        end
        if #rowItems > 0 then
            advDbgSection[#advDbgSection + 1] = vf:row( rowItems )
        end
        
    	advDbgSection[#advDbgSection + 1] = vf:spacer{ height = 10 }
    	advDbgSection[#advDbgSection + 1] = 
    		vf:row {
        		vf:static_text {
        		    title = "User:",
        		    width = share 'short_label_width',
        		},
        		vf:edit_field {
        		    value = app:getGlobalPrefBinding( 'username' ), -- plugin user name.
        		    width_in_chars = 10,
        		    tooltip = "In case plugin has user-specific programming - leave blank if you don't know what to enter.",
        		},
        		vf:spacer{ width = 5 },
        		vf:static_text {
        		    title = "Lightroom Toolkit ID: ",
        		},
        		vf:static_text {
        		    title = app:getInfo( "LrToolkitIdentifier" )
        		},
       		}
    end

    if advDbgSection and #advDbgSection then		
        return { infoSection, advDbgSection }
    else
        return { infoSection }
    end
end



--- Sections for bottom of dialog method.
--
--  @usage      *** Required for named preference set support - must be called in derived class if named preferences are to be supported and this method is overridden.
--
function Manager:sectionsForBottomOfDialogMethod( vf, props )

    self.props = props -- property table changes when switching plugins in plugin manager.
    
    local sections = {}

    if gbl:getValue( 'metadataManager' ) then
        if app:getInfo( 'LrMetadataProvider' ) and gbl:getValue( 'CustomMetadata' ) ~= nil and gbl:getValue( 'custMeta' ) ~= nil then
            -- good
        else
            app:error( "metadata manager not configured properly" )
        end
        local metaSection = { bind_to_object = props }
        sections[#sections + 1] = metaSection
    
    	metaSection.title = "Metadata Manager"
    	-- metaSection.synopsis = "Controls (no settings)"  -- bind{ key=app:getGlobalPrefKey( 'blahBlah' ), object=prefs }
    
    	metaSection.spacing = vf:label_spacing()
    	
        metaSection[#metaSection + 1] =
            vf:row {
                vf:push_button {
                    title = "Save Custom Metadata",
                    width = share 'button_width',
                    action = function( button )
                        custMeta:save()
                    end,
                },
                vf:static_text {
                    title = "Saves custom metadata from catalog to individual files.",
                },
            }
        metaSection[#metaSection + 1] =
            vf:row {
                vf:push_button {
                    title = "Read Custom Metadata",
                    width = share 'button_width',
                    action = function( button )
                        custMeta:read()
                    end,
                },
                vf:static_text {
                    title = "Reads custom metadata from saved files to catalog.",
                },
            }
        --[[ *** doesn't see right to be in plugin manager.
        metaSection[#metaSection + 1] =
            vf:row {
                vf:push_button {
                    title = "Sync Custom Metadata",
                    width = share 'button_width',
                    action = function( button )
                        custMeta:manualSync()
                    end,
                },
                vf:static_text {
                    title = "Copies custom metadata from most selected photo to other selected photos.",
                },
            }
        --]]
    end
    
    
    if Preferences ~= nil then

        local appSection = { bind_to_object = props }
        sections[#sections + 1] = appSection
    
    	appSection.title = "Preset Manager"
    	appSection.synopsis = bind{ key=app:getGlobalPrefKey( 'presetName' ), object=prefs }
    
    	appSection.spacing = vf:label_spacing()
    
        if app:isAdvDbgEna() then
        	appSection[#appSection + 1] = 
        		vf:row {
        			vf:push_button {
        				title = "Clear All Settings",
        				props = props,
        				action = function( button )
        				    app:call( Call:new{ name=button.title, async = false, main = function()
        				        local info = "*** Click 'Clear All' to thoroughly wipe all settings associated with this plugin, or click 'Reset Globals' to just reset global preferences to factory default values.\n \nNote: No preference support files will be deleted, and only in the case of 'Reset Globals' - no preset settings will be affected."
        				        local answer = app:show{ info=info, buttons={ dia:btn( "Clear All", 'ok' ), dia:btn( "Reset Globals", 'other' ) } }
        				        if answer == 'ok' then
                                    app:clearAllPrefs( button.props ) -- and load properties with default set.
                                    app:show{ info="All settings have been cleared - *** IMPORTANT: you must reload plugin now to avoid problems (consider re-enabling advanced debug first)." }
        				        elseif answer == 'other' then
                                    app.prefMgr:loadGlobalDefaults()
                                    app:show{ info="Global preference settings have been reset to factory defaults - named and un-named preset settings were unaffected, however you may have to re-select." }
                                elseif answer == 'cancel' then
                                    -- dbg( "Canceled" )
                                else
                                    error( "whats the answer?" )
                                end
                            end } )
        				end
        			},
        			vf:static_text {
        				title = str:format( 'Clear All ^1 settings (or just reset globals to factory defaults).', app:getAppName() ),
        			},
        		}
        end
    		
    	appSection[#appSection + 1] = vf:spacer{ height = 3 }
    	
    	local presetTb
    	if app.prefMgr:isBackedByFile() then
    	    presetTb = "Preset selection defines basic settings, as visible in 'Plug-in Manager',\nas well as advanced settings in \"backing file\"."
    	else
    	    presetTb = "Preset selection defines settings as seen in other sections\nof 'Plug-in Manager'"
    	end 
    	
    	if true then -- new way
    	
    	    appSection[#appSection + 1] = vf:row {
    	    
    	        vf:static_text {
    	            title = "Preset: ",
    	        },
    	        app.prefMgr:makePresetPopup {
                    props = props,
                    valueBindTo = prefs,
                    valueKey = app:getGlobalPrefKey( 'presetName' ),
                    callback = function( v )
                        -- popup assures preset name change  triggers the callback.
                        self:presetChangeCallback( v )
                    end
    	        },
    	        vf:static_text {
    	            title = presetTb,
    	        },
    	    }

        else -- save for a while    	
        	appSection[#appSection + 1] =
        	    vf:row {
            	    vf:edit_field {
            	        bind_to_object = prefs,
            	        value = app:getGlobalPrefBinding( 'presetName' ),
               	        width = share( 'pref_set_button_width' ),
            	    },
            		vf:static_text {
            			title = str:format( 'Enter preset name - to be created if not already existing, else loaded.\n(You must enter something other than \'Default\' to edit advanced settings)' ),
            		},
            	}
        	appSection[#appSection + 1] =
        	    vf:row {
            	    vf:push_button {
            	        title = 'Select Preset',
            	        width = share( 'pref_set_button_width' ),
            	        props = props,
            	        action = function( button )
            	            app:call( Call:new{ name = button.title, async=true, guard = App.guardSilent, main=function( call )
                	            local items = app.prefMgr:getPresetNames() -- *** Gui-mngr and the pref-mgr are friends.
                	            if #items > 1 then
                    	            local param = {}
                    	            param.title = 'Choose Preset'
                    	            param.subtitle = 'Choose a preset to load settings'
                    	            param.items = items
                    	            local sel,msg = dialog:getComboBoxSelection( param )
                    	            -- dbg( "sel", sel )
                    	            if sel then
                    	                local presetName = app.prefMgr:getPresetName()
                    	                if presetName == sel then
                    	                    local presetKey = app:getGlobalPrefKey( 'presetName' )
                    	                    --Debug.pause( presetKey )
                           	                app:presetNameChange( button.props, presetKey, sel ) -- force a change to be processed, so config file is reloaded.
                                        else            	                
                    	                    --Debug.pause( sel )
                    	                    app:setGlobalPref( 'presetName', sel ) -- change handler takes it from here.
                    	                end
                        	        end
                    	        else
                    	            app:show{ warning="There are no presets other than 'Default' - try entering a name in the preset name box..." }
                    	        end
                    	    end } )
            	        end
            	    },
            		vf:static_text {
            			title = str:format( 'Choose preset by name and load corresponding settings.' ),
            		},
            	}
        	appSection[#appSection + 1] =
        	    vf:row {
            	    vf:push_button {
            	        title = 'Delete Preset',
            	        enabled = bind{ key=app:getGlobalPrefKey( 'presetName' ), bind_to_object=prefs, transform=function( value, fromModel )
            	            if str:is( value ) and value ~= 'Default' then
            	                return true
            	            else
            	                return false
            	            end
            	        end },
            	        width = share( 'pref_set_button_width' ),
            	        props = props,
            	        action = function( button )
                            app:call( Call:new{ name='Delete Pref Preset', main = function()
                	            app:deletePrefPreset( button.props )
                            end } )
            	        end
            	    },
            		vf:static_text {
            			title = str:format( 'Delete this preset and all settings associated with it.\n(the \'Default\' preset can not be deleted)' ),
            		},
            	}
            	
        	appSection[#appSection + 1] =
        	    vf:row {
            	    vf:push_button {
            	        title = 'Load Factory Defaults',
            	        width = share( 'pref_set_button_width' ),
            	        props = props,
            	        action = function( button )
                            app:call( Call:new{ name='Delete Pref Preset', main = function()
                                local presetName = app.prefMgr:getPresetName()
                                if dialog:isOk( str:fmt( "Overwrite ^1 settings with factory defaults?", presetName ) ) then
                    	            app.prefMgr:loadDefaults( button.props ) -- nothing returned.
                    	            app:show{ info="Defaults were successfully loaded.", actionPrefKey="Default preferences loaded" }
                    	        end
                            end } )
            	        end
            	    },
            		vf:static_text {
            			title = str:format( 'Reset settings for this preset to factory default values.' ),
            		},
            	}
            	
            if app.prefMgr and app.prefMgr:isBackedByFile() then -- use app method?
            	appSection[#appSection + 1] =
            	    vf:row {
                	    vf:push_button {
                	        title = 'Edit Advanced Settings',
                	        width = share( 'pref_set_button_width' ),
                	        props = props,
                	        enabled = LrView.bind {
                	            key = app:getGlobalPrefKey( 'presetName' ),
                	            bind_to_object = prefs,
                	            transform = function( val, toUi )
                	                if app.prefMgr:getPresetName() == 'Default' then
                	                    return false
                	                else
                	                    return true
                	                end
                	            end,
                	        },
                	        action = function( button )
                	            app:call( Call:new{ name=button.title, async=true, main = function()
                	                assert( app.prefMgr:getPresetName() ~= 'Default', "config file edit button shouldn't be enabled for default preset" )
              	                    local file, name = app.prefMgr:getPrefSupportFile()
              	                    if fso:existsAsFile( file ) then
              	                        app:show{ info="In a moment, '^1' will open in the default app for you to edit. After editing, be sure to click the 'Reload Advanced Settings' button (or reload plugin).",
              	                            subs = { file },
              	                            actionPrefKey = "Reminder to reload after editing advanced settings" }
               	                        app:openFileInDefaultApp( file, true ) -- true => prompt before and after opening.
                  	                else
                  	                    app:show{ error="Not existing: ^1", file } -- Its created when the set is created, and each time when switching sets - so simple error here OK.
                  	                end
                	            end } )
                	        end
                	    },
                		vf:static_text {
                			title = str:format( 'Edit plugin configuration file corresponding to this preset.\n(if this is disabled/greyed-out, then you need to enter a preset name above)' ),
                		},
                	}
            	appSection[#appSection + 1] =
            	    vf:row {
                	    vf:push_button {
                	        title = 'Reload Advanced Settings',
                	        width = share( 'pref_set_button_width' ),
                	        props = props,
                	        action = function( button )
                	            app:call( Call:new{ name=button.title, main = function()
                	                -- make this single method: ###2
              	                    local file, name = app.prefMgr:getPrefSupportFile()
           	                        local presetName = app.prefMgr:getPresetName()
              	                    if fso:existsAsFile( file ) then
                                        app.prefMgr:loadPrefFile( file, presetName ) -- load props used to do this (throws error if probs).
                                        assert( name == LrPathUtils.leafName( file ), "Preset file naming anomaly" )
                                        local dir = LrPathUtils.parent( file )
                                        app:show{ info="Reloaded advanced settings for ^1 preset, by re-reading preset backing file: ^2", presetName, file }
                  	                else
                  	                    app:show{ error="Unable to reload advanced settings for ^1, preset backing file not found:\n^2", presetName, file } -- Its created when the set is created, and each time when switching sets - so simple error here OK.
                  	                end
                	            end } )
                	        end
                	    },
                		vf:static_text {
                			title = str:format( 'Reload recently edited plugin configuration file.\n(be sure to click this after editing advanced settings)' ),
                		},
                	}
                end
            end
            
        appSection[#appSection + 1] = vf:spacer{ height = 5 }
        appSection[#appSection + 1] =
            vf:row {
                vf:push_button {
                    title = "|<",
                    action = function( button )
                        app:call( Call:new{ name="First preset", async=false, guard=App.guardSilent, main=function( call )
                            -- Note: handling @10/Oct/2012 4:32 assures default preset is always first, and other preset-names are sorted alphabetically: ascending.
  	                        app:setGlobalPref( 'presetName', 'Default' )
  	                    end } )
                    end
                },
                vf:push_button {
                    title = "<",
                    action = function( button )
                        app:call( Call:new{ name="Previous preset", async=false, guard=App.guardSilent, main=function( call )
                            local presetName = app.prefMgr:getPresetName()
                            local presetNames = app.prefMgr:getPresetNames()
                            local targetIndex
                            for i, name in ipairs( presetNames ) do
                                if name == presetName then
                                    targetIndex = i - 1
                                    break
                                end
                            end
                            if targetIndex then
                                if targetIndex > 0 then
                                    app:setGlobalPref( 'presetName', presetNames[targetIndex] )
                                end
                            end
                        end } )
                    end
                },
                vf:push_button {
                    title = ">",
                    action = function( button )
                        app:call( Call:new{ name="Next preset", async=false, guard=App.guardSilent, main=function( call )
                            local presetName = app.prefMgr:getPresetName()
                            local presetNames = app.prefMgr:getPresetNames()
                            local targetIndex
                            for i, name in ipairs( presetNames ) do
                                if name == presetName then
                                    targetIndex = i + 1
                                    break
                                end
                            end
                            if targetIndex then
                                if targetIndex <= #presetNames then
                                    app:setGlobalPref( 'presetName', presetNames[targetIndex] )
                                --else
                                --    app:setGlobalPref( 'presetName', 'Default' )
                                end
                            --else
                            --    app:setGlobalPref( 'presetName', 'Default' )
                            end
                        end } )
                    end
                },
                vf:push_button {
                    title = ">|",
                    action = function( button )
                        app:call( Call:new{ name="Last preset", async=false, guard=App.guardSilent, main=function( call )
                            local presetNames = app.prefMgr:getPresetNames()
                            local index = #presetNames
                            while not str:is( presetNames[index] ) and ( index > 1 ) do
                                Debug.pause( "No preset at " .. str:to( index ) )
                                index = index - 1
                            end
                            if str:is( presetNames[index] ) then
                                app:setGlobalPref( 'presetName', presetNames[index] )
                            else
                                Debug.logn( "No last preset found" )                            
                            end
                        end } )
                    end
                },
                vf:static_text {
                    title = "First, Previous, Next, Last preset..."
                },
            }
        
    end
    
    return sections
end



--- Called when dialog box is being exited for whatever reason.
--      
--  <p>Typically a good place to make sure settings have been saved.</p>
--
--  @usage      *** MUST be called by derived type too (as well as the start method).
--  @usage      The base method just saves everything - override to descriminate.
--
function Manager:endDialogMethod( props )

    -- dbg( "End-of-dialog, saving properties..." )
    local count = 0
    
    self.props = props
    
    assert( props ~= prefs, "how can prefs be props?" )

    for k,v in props:pairs() do
        if app:isVerbose() then
            -- dbg( "Saving: ", str:format( "^1 ^2: ^3", app:getGlobalPref( 'presetName' ), str:to( k ), str:to( v ) ) )
        end
        if str:isStartingWith( k, '_global_' ) then -- why would properties have -global- in them? - isn't that just for prefs???  regex ok.
            dbg( "What's this globally prefixed key doing in the manager properties?:", k ) -- this isn't happening - perhaps it was before the -global- handling was debugged.
        else
            count = count + 1
            dbg( "Saving manager property as pref, name: ", k, " value: ", str:to( v ) )
            app:setPref( k, v )
        end
    end

    -- dbg( "End-of-dialog, properties saved: ", str:to( count ) )
    self.dialogEnded = true
end



-- *** Save as reminder (the concept is used elsewhere, but not the method).
-- Set property and yield, so change handler can run.
--
--function Manager:setPropAndYield( name, value )
--    self.props[name] = value
--    LrTasks.yield()
--end



---------------------------------------------------------------------------------



--- Preference change handler.
--
--  Static function required by Lightroom.
--  Derived classes should override method instead.
--
function Manager.prefChangeHandler( _id, _prefs, name, value )
    assert( Manager.manager ~= nil, "Manager nil" )
    app:call( Call:new{ name="mgrPrefChgHdlr", async = true, guard = App.guardSilent, main = function( call ) -- Made async 28/Nov/2011 9:57 ###4 - delete this comment if no problems by 2015
    
        -- @13/May/2012 3:15 I had a problem, but maybe had to do with multiple instances of plugin running - prompt to switch to created preset was preceding the prompt to create the preset!
        -- switching back to synchronous caused a different problem - preferences support file seemed to have disappeared (probably before it was created..
        
        Manager.manager:prefChangeHandlerMethod( _id, _prefs, name, value, call )
    end } )
end    



--- Property change handler.
--
--  Static function required by Lightroom.
--  Derived classes should override method instead.
--
function Manager.propChangeHandler( id, props, name, value )

    assert( Manager.manager ~= nil, "Manager nil" )
    -- Debug.pause( id, props, name, value )
    app:call( Call:new{ name="mgrPropChgHdlr", async = true, guard = App.guardSilent, main = function( call ) -- ditto ###4
        --[[ *** save for posterity: its really not the default prefs that need to be protected, its the default backing file that must remain virginal (so plugin update does not overwrite).
        if app.prefMgr then
            local presetName = app.prefMgr:getPresetName()
            if presetName == 'Default' then
                local r = app:getPref( name ) -- restore previous value.
                if r ~= value then
                    app:show{ warning="A recent code change no longer permits changing the default (un-named) preferences. Please use a named preset for all customized preferences (hint: enter a name in Preset Manager section).\n \nPrevious value will be restored: '^1'.", str:to( r ) }
                    props[name] = r -- restore previous value.
                    return
                end
            end
            
        end--]]
        -- fall-through => either preferences are un-managed, or property represents a named preset preference.
        Manager.manager:propChangeHandlerMethod( props, name, value, call ) -- ID is not passed through, for backward compatibility.
            -- only value I can think of in having the id would be to remove the listener, and so far that hasn't been needed.
            -- Anyway, the 'id' is 'Manager'.
    end, finale=function( call )
        if call.status then
            -- Debug.pause()
        else 
            app:logE( "Error processing property change: ^1", call.message )
        end
    end } )
end
    


--- Called when dialog box is being initialized for plugin.
--
--  Static function simply creates an appropriate manager instance
--  and dispatches its start-dialog method.
--
--  Derived classes should override methods, not static functions.
--
function Manager.startDialog( props )
    if Manager.manager == nil then
        Manager.manager = objectFactory:newObject( 'Manager', { props=props } )
    end
    Manager.manager:startDialogMethod( props )
end



--- Called when dialog box is being exited for whatever reason.
--      
--  Static function required by Lightroom.
--  Derived classes should override method instead.
--
function Manager.endDialog( props )
    -- assert( Manager.manager ~= nil, "Manager nil" )
    if Manager.manager then
        Manager.manager:endDialogMethod( props )
    -- else let it go - usually means there was an error loading it upon init or start-dialog.
    end
end



--- Create top section of dialog.
--
--  Static function required by Lightroom.
--  Derived classes should override method instead.
--
function Manager.sectionsForTopOfDialog( vf, props )
    if Manager.manager == nil then -- this is never necessary when everything is in straight, but allows for a much more intelligible error message.
        Manager.manager = objectFactory:newObject( 'Manager', { props=props } )
    end
    assert( Manager.manager ~= nil, "Manager nil" )
    return Manager.manager:sectionsForTopOfDialogMethod( vf, props )
end



--- Create bottom section with settings.
--
--  Static function required by Lightroom.
--  Derived classes should override method instead.
--
function Manager.sectionsForBottomOfDialog( vf, props )
    if Manager.manager == nil then -- this is never necessary when everything is in straight, but allows for a much more intelligible error message.
        Manager.manager = objectFactory:newObject( 'Manager', { props=props } )
    end
    assert( Manager.manager ~= nil, "Manager nil" )
    return Manager.manager:sectionsForBottomOfDialogMethod( vf, props )
end



return Manager
