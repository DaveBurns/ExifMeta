--[[
        Keywords.lua
        
        'twas hoping this to be the be-all/end-ball of keyword modules, but not so easy: different apps need different keyword info..
        Might be so inefficient to try and compute everything for everybody that it defeats much of the purpose - hmm...
--]]

local Keywords, dbg, dbgf = Object:newClass{ className='Keywords', register=true }



local kwFromPath -- to support legacy methods.



--- Constructor for extending class.
--
function Keywords:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
--  @param t (table) object initialization table, options:
--      <br>    initInterval ( number, default: 1 ) set to zero to not re-initialized, else seconds for keyword re-init interval.
--
function Keywords:new( t )
    local o = Object.new( self, t )
    o.initInterval = o.initInterval or 1
    if o.initInterval >= 0 then
        o:startInit() -- once or until stop/shutdown.
    -- else init will be started/stopped externally.
    end
    return o
end



--- Init keyword cache.
--
--  @usage deprecated (I think) ###2 18/Dec/2013 9:54 (no longer sure why). - still being used in Ottomanic Importer, but maybe only until cut-over (?)
--
function Keywords:initCache()
    kwFromPath = {}
    local function initKeywords( path, keywords )
        for i, v in ipairs( keywords ) do
            local name = v:getName()
            kwFromPath[path .. name] = v
            initKeywords( path .. name .. "/", v:getChildren() )
        end
    end
    initKeywords( "/", catalog:getKeywords() )
end



--- Refresh display of recently changed photo (externally changed).
--
function Keywords:getKeywordFromPath( path, permitReinit )
    if not kwFromPath or ( permitReinit and not kwFromPath[path] ) then -- will be reinitialized upon first use, or if keyword expected but not found in cache.
        self:initCache()
    end
    --Debug.lognpp( kwFromPath )
    --Debug.showLogFile()
    return kwFromPath[ path ]
end



--- This is generally called once upon init, then continues to re-init forever, or until stopped or shutdown.
--
--  @usage another option is to start initialization task, and stop it, as desired.
--
function Keywords:startInit( ival )
    app:pcall{ name="Ongoing keyword init", async=true, guard=app:isAdvDbgEna() and app:getUserName() == '_RobCole_' and App.guardVocal or App.guardSilent, main=function( call )
        -- note: these are intialized only once. Ongoing loops only add / overwrite - callers have the responsibility to cull obsolete entries.
        Debug.pauseIf( self.stop, "expected stop to be nil or false when starting init task." )
        app:logV( "Initializing keyword data." )
        self.stop = false -- false, but not nil.
        if ival ~= nil then
            self.initInterval = ival
        end
        local kwFromPath
        local kwsFromName
        local kwArray
        local kwSet
        local yc = 0
        local function initKeywords( path, keywords )
            for i, v in ipairs( keywords ) do
                kwArray[#kwArray + 1] = v
                kwSet[v] = true
                local name = v:getName()
                dbgf( name )
                kwFromPath[path .. name] = v
                if kwsFromName[name] == nil then
                    kwsFromName[name] = { v }
                else
                    local dat = kwsFromName[name]
                    dat[#dat + 1] = v
                end
                initKeywords( path .. name .. "/", v:getChildren() )
            end
            if self.stop or shutdown then return end
            yc = app:yield( yc )
        end
        repeat
            kwFromPath = {}
            kwsFromName = {}
            kwArray = {}
            kwSet = {}
            initKeywords( "/", catalog:getKeywords() )
            self.kwFromPath = kwFromPath
            self.kwsFromName = kwsFromName
            self.kwArray = kwArray
            self.kwSet = kwSet
            dbgf( "keyword init completed" )
            if self.initInterval > 0 then
                app:sleep( self.initInterval, .1, function( et )
                    return self.stop
                end )
            else
                Debug.pause( "Not using continuous init keyword data?" )
                app:logV( "Keywords init once." )
                call:cancel'' -- call is quit.
                break
            end
        until shutdown or self.stop
    end, finale=function( call )
        if not shutdown then
            if call.status then
                if not self.stop and not call:isQuit() then
                    app:displayError( "Keyword init task terminated unexpectedly." )
                elseif self.stop then
                    app:logV( "Keyword init task stopped." )
                -- else nuthin'
                end
            else
                app:displayError( app:parseErrorMessage( call.message ) )
            end
        end
        self.stop = nil -- idle..
    end }
    if LrTasks.canYield() then
        LrTasks.yield() -- give init task a chance to run.
    end
end



--- Call this when exiting dialog box that uses initializing keyword object.
--
function Keywords:stopInit()
    if self.stop ~= nil then
        self.stop = true
        if LrTasks.canYield() then
            app:sleep( 5, .1, function( et )
                return self.stop == nil
            end )
            if self.stop ~= nil then
                app:displayError( "Unable to stop keyword init task." )
            end        
        else
            app:logV( "Stop request issued to keyword init task, but can't wait for task stop confirmation." )
        end
    else
        app:logV( "Keyword init not running (already stopped), so can't stop it." )
    end
end



-- private method - called all over the place to assure initialization prior to access.
-- options can include 'call' and/or 'maxWait'.
function Keywords:_assureInit( options )
    options = options or {}
    if not self.kwsFromName then -- init not complete, yet.
        if self.stop == nil then
            app:logV( "*** Keyword data initialization was not started prior to getting keyword info - initializing once to honor request." )
            self:startInit{ initInterval = -1 } -- default if not init is to init once: if you want more, then start init externally.
        end
        local cap
        if options.call then
            cap = options.call:setCaption( "Waiting for keyword initialization to complete" ) -- no-op if no scope attached to call.
        end
        app:sleep( options.maxWait or 30, .2, function( et )
            return self.kwsFromName
        end )
        if shutdown then return end
        if options.call then
            options.call:setCaption( cap ) -- no-op if no scope attached to call.
        end
        if not self.kwsFromName then
            app:error( "Keyword data initialization failure - timeout." )
        end
    end
    return options
end



-- presumably private method..
function Keywords:getKeywordForPathTable( options )
    self:_assureInit( options )
    return self.kwFromPath
end



-- ditto
function Keywords:getKeywordsForNameTable( options )
    self:_assureInit( options )
    return self.kwsFromName
end



-- ###1 make sure ottomanic importer is working and enhanced before releasing.
--- Refresh display of recently changed photo (externally changed).
--
--  @usage as of 30/May/2014 18:45, not used in any live plugins of mine, but passed preliminary tests.
--
function Keywords:getKeywordForPath( path, options )
    return self:getKeywordForPathTable( options )[ path ]
end



-- wait for first init, but never waits otherwise.
function Keywords:getKeywordsForName( name, options )
    local kws = self:getKeywordsForNameTable( options )[name]
    if #kws > 1 then
        return kws
    elseif #kws == 1 then
        return kws, kws[1]
    elseif #kws == 0 then
        return nil -- check for this.
    end
end



--- Get all keywords array.
--
--  @param options reserved for future.
--
--  @return keyword array - values are lr-keyword objects.
--
function Keywords:getAllKeywords( options )
    self:_assureInit()
    return self.kwArray
end



--- Get set of all keywords.
--
--  @param options reserved for future.
--
--  @return keyword set - keys are lr-keyword objects (values are 'true').
--
function Keywords:getAllKeywordSet( options )
    self:_assureInit()
    return self.kwSet
end



--- Get component array given leaf keyword.
--
--  @usage it is expected that leaf keyword will be pure/true leaf, but such is not required - it could also be parental keyword.
--
--  @param keyword (LrKeyword, required) the keyword to be expressed as component array.
--  @param reverse (boolean, default: false) whether components should be reversed so root is first.
--
--  @return comp (array) will always have at least one keyword - never empty, never nil. leaf will be first component, root will be last - reverse order if desired.
--
function Keywords:getKeywordComponents( keyword, reverse )
    local comp = { keyword }
    local parent = keyword
    repeat 
        parent = parent:getParent()
        if parent == nil then
            break
        end
        comp[#comp + 1] = parent
    until false
    if reverse then
        tab:reverseInPlace( comp )
        return comp
    end
    return comp
end



--- Get keyword as path.
--
--  @usage it is expected that leaf keyword will be pure/true leaf, but such is not required - it could also be parental keyword.
--
--  @param keyword (LrKeyword, required) the keyword to be expressed as path.
--  @param options (table, optional) include format = 'slash', 'Lr5', or 'legacy', as desired - default is 'slash' notation.
--
--  @return path string and comp (array).
--
function Keywords:getKeywordPath( keyword, options )
    options = options or {}
    local format = options.format or 'slash'
    local names = {}
    local comps
    if format == 'slash' then
        comps = self:getKeywordComponents( keyword, true ) -- most significant at front of string
    else -- least significant at front of string
        comps = self:getKeywordComponents( keyword, false )
    end
    for i, v in ipairs( comps ) do
        names[#names + 1] = v:getName()
    end
    if format == 'slash' then
        return "/"..table.concat( names, "/" )
    elseif format=='Lr5' then
        return table.concat( names, " < " )
    elseif format == 'legacy' then
        return table.concat( names, " > " )
    else
        app:callingError( "Invalid format: ^1", format or 'nil' )
    end
end



--- Get array of keyword paths (includes synonyms).
--
--  @param keyword lr-keword object.
--  @param options may include 'format' ('slash' or 'Lr5' or 'legacy') - default is 'slash'.
--
--  @return array of strings
--
function Keywords:getKeywordPaths( keyword, options )
    options = options or {}
    local format = options.format or 'slash'
    local names = {}
    local comps
    if format == 'slash' then
        comps = self:getKeywordComponents( keyword, true ) -- most significant at front of string
    else -- least significant at front of string
        comps = self:getKeywordComponents( keyword, false )
    end
    local parentPath
    for i = 1, #comps - 1 do
        names[#names + 1] = comps[i]:getName()
    end
    local paths = {}
    if #names > 0 then
        if format == 'slash' then
            parentPath = "/"..table.concat( names, "/" )
        elseif format=='Lr5' then
            parentPath = table.concat( names, " < " )
        elseif format == 'legacy' then
            parentPath = table.concat( names, " > " )
        else
            app:callingError( "Invalid format: ^1", format or 'nil' )
        end
    else
        parentPath = ""
    end
    local function putPath( name )
        local path
        if format == 'slash' then
            path = parentPath.."/"..name
        elseif format=='Lr5' then
            path = name.." < "..parentPath
        elseif format == 'legacy' then
            path = name.." > "..parentPath
        else
            app:callingError( "Invalid format: ^1", format or 'nil' )
        end
        paths[#paths + 1] = path
    end
    putPath( comps[#comps]:getName() )
    local synArr = keyword:getSynonyms()
    for i, name in ipairs( synArr ) do
        putPath( name )
    end
    return paths
end



--- Parse keyword string info into parallel arrays of resolved keywords and corresponding names/subpaths (having unique counterpart existing in catalog).
--
--  @usage implementation @19/Dec/2013 6:47 does not return parsed keywords which aren't in the catalog, but maybe should, so they can be created, at least as on option.
--
--  @param kwString keywords as read from get-formatted-metadata method.
--  @param options may include 'delim' or 'sep'.
--
--  @return keywords (array of LrKeyword objects) - resolved.
--  @return names (parallael array of strings) - resolved.
--  @return message (qualifying message) - will accompany partially keywords/names, but won't accompany if all are resolved.
--  @return other ( table, only if qualifying message ) - members: 'missing', 'ambiguous' (arrays of strings).
--
function Keywords:parseKeywordString( kwString, options )
    options = self:_assureInit( options )
    local delim = options.delim or options.sep or ","
    local kwStrings = str:split( kwString, delim )
    local rec = self:getKeywordsForNameTable()
    local kws = {} -- keywords array.
    local names = {} -- parallel array of resolved names.
    local trbl = {}
    local ambg = {}
    local function checkHierKw( kwPqNames )
        local r = rec[kwPqNames[1]] or error( "no r" )
        for i, lrKw in ipairs( r ) do
            local p = lrKw
            for j, name in ipairs( kwPqNames ) do
                if p:getName() ~= name then
                    return nil
                else
                    p = p:getParent()
                    if p == nil then
                        if i == #r then -- it's the last component, nil is expected if partially qualified hierarchical spec does fully qualify
                            break
                        else -- we ran out of components on record to cover those being entered - no good.
                            return nil
                        end
                    else
                        Debug.pause( p:getName() )
                    end
                end
            end
            return lrKw -- this is not 100% robust ###1
        end
    end
    local function checkAbs( path, comps )
        local name = comps[1]
        assert( LrPathUtils.leafName( path ) == comps[1], "?" ) -- ls-name first.
        local kws = rec[name]
        if not kws then return false end
        Debug.pause( kws, name, path, comps )
        for i, kw in ipairs( kws ) do
            local p = self:getKeywordPath( kw )
            if p == path then
                Debug.pause( p )
                return kw
            else
                Debug.pause( p, path )
            end
        end
        return false
    end
    for i, kwNameOrSubpath in ipairs( kwStrings ) do
        -- consider parsing leaf
        repeat -- messy, but working AFAICT @19/Dec/2013 4:26.
            local kwPqNames = str:split( kwNameOrSubpath, "<" ) -- array of fully or partially qualifying (hopefully sufficiently qualifying for uniqueness) keyword names. Lr5 syntax ###1 - support variable syntax.
            if #kwPqNames < 2 then
                kwPqNames = str:split( kwNameOrSubpath, ">" ) -- try legacy format.
            end
            local abs
            local trail
            if #kwPqNames < 2 then -- try "slash" format.
                local _kwPqNames = str:split( kwNameOrSubpath, "/" )
                if #_kwPqNames > 1 then
                    if not str:is( _kwPqNames[1] ) then
                        table.remove( _kwPqNames, 1 )
                        abs = true
                    end
                    if not str:is( _kwPqNames[#_kwPqNames] ) then
                        trail = true
                        _kwPqNames[#_kwPqNames] = nil
                    end
                    kwPqNames = tab:reverseArray( _kwPqNames ) -- not in place.
                end
            end
            Debug.pause( kwPqNames, abs )
            if #kwPqNames == 1 then
                kwNameOrSubpath = kwPqNames[1] -- may have been slightly reformatted for compatibility.
            end
            if rec[kwNameOrSubpath] then
                if #rec[kwNameOrSubpath] == 1 then
                    app:logV( "Resolved: ^1", kwNameOrSubpath )
                    kws[#kws + 1] = rec[kwNameOrSubpath][1] -- keyword object
                    names[#names + 1] = kwNameOrSubpath -- name which begat said keyword object.
                    break
                -- else
                end
            -- else
            end
            if #kwPqNames > 1 or abs then -- multi-comp kw-subpath
                local kw
                if abs then
                    if trail then -- name/subpath has a trailing slash, which needs to be removed for present purposes..
                        kwNameOrSubpath = kwNameOrSubpath:sub( 1, -2 )
                    end
                    -- similarly, if abs, there was a leading slash which needs to be put back on now (to the path).
                    kw = checkAbs( (#kwPqNames==1 and "/" or "" ).. kwNameOrSubpath, kwPqNames ) -- abs handled by comparing paths.
                else
                    kw = checkHierKw( kwPqNames ) -- relative handled by comparing components.
                end
                if kw then -- matching keyword found.
                    kws[#kws + 1] = kw -- add it to list.
                    names[#names + 1] = kwNameOrSubpath
                else -- missing
                    trbl[#trbl + 1] = kwNameOrSubpath
                end
            else -- only one path component specified
                if rec[kwNameOrSubpath] then
                    assert( #rec[kwNameOrSubpath] > 1, "hmm...(rec for kw <=1)" )
                    ambg[#ambg + 1] = kwNameOrSubpath
                else -- missing
                    trbl[#trbl + 1] = kwNameOrSubpath
                end
            end
        until true
    end
    if #kws > 0 then
        assert( #kws == #names, "parallel arrays are skewed" )
        app:logV( "^1 resolved.", #kws )
    else
        app:log( "No keywords were resolved." )
    end
    local buf = {}
    if #trbl > 0 then
        buf[#buf + 1] = "Keywords missing: " .. table.concat( trbl, ", " )
    end
    if #ambg > 0 then
        buf[#buf + 1] = "Ambiguous keywords: " .. table.concat( ambg, ", " )
    end
    local msg
    if #buf > 0 then
        msg=table.concat( buf, "\n" )
        return kws, names, msg, { missing=trbl, ambiguous=ambg }
    else
        assert( #kwStrings == #kws, "kw rslv discrep." )
        return kws, names -- none are ambig or missing.
    end
    
end



return Keywords

