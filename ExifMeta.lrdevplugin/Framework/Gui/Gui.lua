--[[
        Gui.lua
--]]

local Gui, dbg, dbgf = Object:newClass{ className = 'Gui' }


Gui.moduleNames = { "Library", "Develop" } -- these are the only ones used.



--- Constructor for extending class.
--
function Gui:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function Gui:new( t )
    local o = Object.new( self, t )
    return o
end



--- Switch to specified module.
--
--  @param moduleNumber -- 1=library, 2=develop (other modules not supported). May also be module name string: anything starting with 'L' or 'D', not case sensitive.
--
--  @usage No guarantees - involve user with a prompt if absolute assurance required.
--
function Gui:switchModule( moduleNumber, mandatory )
    if moduleNumber == nil then
        error( 'Module number must not be nil' )
    end
    if type( moduleNumber ) == 'string' then
        if LrStringUtils.lower( moduleNumber:sub( 1, 1 ) ) == "l" then -- first char is 'L' or 'l'
            moduleNumber = 1
        elseif LrStringUtils.lower( moduleNumber:sub( 1, 1 ) ) == "d" then -- first char is 'D' or 'd'
            moduleNumber = 2
        else
            moduleNumber = tonumber( moduleNumber ) -- try to make it a number.
        end
    elseif type( moduleNumber ) == 'number' then
        -- good to go.
    else
        return false, "Invalid module number: " .. str:to( moduleNumber )
    end
    if moduleNumber >= 1 and moduleNumber <= 2 then
        local s, m 
        if WIN_ENV then
            s, m = app:sendWinAhkKeys( "{Ctrl Down}{Alt Down}" .. moduleNumber .. "{Ctrl Up}{Alt Up}" )
        else
            s, m = app:sendMacEncKeys( "CmdOption-" .. moduleNumber )
        end
        if s then
            -- log verbose externally if desired.
            return true
        elseif not mandatory then
            return s, m -- let failure be dealt with externally, or not.
        else
            repeat
                local btn = app:show{ info="Unable to switch automatically to ^1 module, which is mandatory for operation to succeed. If already in that module, just click 'Already in ^1 Module', otherwise click 'Dismiss dialog for 3 seconds' button, and switch module manually.",
                    subs = { Gui.moduleNames[moduleNumber] },
                    buttons = { dia:btn( str:fmtx( "Already in ^1 Module", Gui.moduleNames[moduleNumber] ), 'ok' ), dia:btn( "Dismiss dialog for 3 seconds", 'other' ) },
                }
                if btn == 'other' then
                    app:sleep( 3 )
                    if shutdown then return false, "shutdown" end
                elseif btn == 'cancel' then
                    return false, "Unable to switch modules."
                else
                    return true
                end
            until false
        end
    else
        return false, "Invalid module number: " .. str:to( moduleNumber )
    end
end



--- Go to grid mode in library module.
--
--  @usage No guarantees - involve user with a prompt if absolute assurance required.
--
--  @param mandatory (boolean, default=true) Specifies whether grid-mode is essential.
--
function Gui:gridMode( mandatory )

    local keyChar = app:getPref{ name='gridModeChar', expectedType='string' } or 'g'
    local timebase = app:getPref{ name='timebase', expectedType='number' } or .1
    -- ###2 it's dangerous having misc prefs strewn: one app reuses this pref name for something else and there's a conflict.

    if mandatory == nil then
        mandatory = true
    end
    
    local s, m = app:sendKeys( keyChar, timebase * 2 ) -- OS agnostic.
    if s then
        -- log verbose externally if desired.
        return true
    elseif not mandatory then
        return s, m -- let failure be dealt with externally, or not.
    else
        repeat
            local btn = app:show{ info="Unable to switch automatically to grid mode of library module, which is mandatory for operation to succeed. If already in grid mode, just click 'Already in Grid Mode', otherwise click 'Dismiss dialog for 3 seconds' button, and switch to grid mode manually.",
                buttons = { dia:btn( "Already in Grid Mode", 'ok' ), dia:btn( "Dismiss dialog for 3 seconds", 'other' ) },
            }
            if btn == 'other' then
                app:sleep( 3 )
                if shutdown then return false, "shutdown" end
            elseif btn == 'cancel' then
                return false, "Unable to assure grid mode."
            else
                return true
            end
        until false
    end
end
Gui.gridView = Gui.gridMode -- function Gui:gridView( mandatory )



--  assure lib module, in grid-mode, or not.
--[[ *** save for potential future resurrection: need to have some way to invoke and detect something only doable in librar. Unfortunately lib menu item is not it: keystroke may be consumed by a different plugin.
function Gui:isLibModule()
    local pre = gbl:getValue( '_libModuleFlag' )
    if pre == nil then
        app:error( "unable to locate _libModuleFlag in global environment" )
    end
    _G._libModuleFlag = false
    local s, m
    if WIN_ENV then
        s, m = app:sendWinAhkKeys( '{Alt down}l{Alt up}u
    else
        s, m = self:gridMode( true ) -- mandatory
    end
    -- check for global anyway - may have worked...
    if _libModuleFlag then
        return true
    else
        return false, m
    end
end
--]]
    


return Gui
