--[[
        SmartCollections.lua
        
        Interface to smart-collection utility class - no object to represent an individual (extended) smart collection...
        
        Has lotsa stuff for presening smart collection UI (e.g. for editing) which maybe should have stayed in SmartColluder - oh well..
        
        *** @30/May/2014 this class is not loaded by the framework initializer, so you must load in init.lua if desired.
--]]


local SmartCollections, dbg, dbgf = Object:newClass{ className = "SmartCollections", register = true }



--- Constructor for extending class.
--
function SmartCollections:newClass( t )
    return Object.newClass( self, t )
end


--- Constructor for new instance.
--
--  @param t pass noInit=true (boolean member) to suppress initialization of stuff you probably don't want initialized anyway..
--
function SmartCollections:new( t )
    local o = Object.new( self, t )
    if not o.noInit then
        o:init()
    end
    return o
end



local combineTable = { 
    { title="Any", value='union' },
    { title="All", value='intersect' },
    { title="None", value='exclude' },
}


local dateTimeUnitsTable = { -- popup-compatible
    { title="years", value='years' },
    { title="months", value='months' },
    { title="weeks", value='weeks' },
    { title="days", value='days' },
    { title="hours", value='hours' },
    { title="minutes", value='minutes' },
}


-- custom validators (UI to internal) and ToString functions (internal to string for UI).
local function dateValidate( vw, val )
    local d
    if type( val ) == 'string' then
        d = date:parseYyyyMmDdDate( val ) -- 4-char year, otherwise fairly flexible..
    end
    if d then
        return true, val
    else
        local now = LrDate.currentTime()
        local value= LrDate.timeToUserFormat( now, "%Y-%m-%d" ) -- now today
        return true, value
    end
end


-- ###3: could be incorporated in a reusable Math class, but so far this is the only method so..
local function logBase2( n )
    return ( math.log( n ) / math.log( 2 ) )
end


-- basically: ui-to-internal.
local function shutterSpeedValidate( vw, val )
    if type( val ) == 'string' then
        val = LrStringUtils.trimWhitespace( val )
        if val ~= "" then
            local sp = val:find( " " )    
            if sp then
                val = val:sub( 1, sp - 1 ) -- take front part.
            end
            local v = tonumber( val )
            if v ~= nil then
                local ov = v
                if v < 1 then
                    v = 1/v
                end
                local value = logBase2( v ) -- Lua 5.1's math lib does not support base param (Lua 5.2 does).
                if ov > 1 then
                    value = -value
                end
                return true, value
            else
                return false, val, "must be a number between .00001 and 10000 (optionally, followed by \" sec\")"
            end
        else -- blank field
            return true, 0 -- equivalent of 1 second, since 0 is exponent (log) of base 2.
        end
    else -- already numeric
        return true, val -- second
    end
end


-- note: this function is called when it's not a string, then again after conversion to string (ugh).
-- so just echo incoming if string, and format for display if number.
local function shutterSpeedToString( vw, valIn )
    if valIn == nil then
        Debug.pause() -- this hasn't happened yet.
        return "" -- if it did, presumably this would be the right response.
    end
    if type( valIn ) == 'string' then -- already converted to string, and being called again
        local n = tonumber( valIn ) -- see if it's a number
        if n then -- not already converted (with ' sec' suffix).
            Debug.pause( valIn, n ) -- this never happens, since if string, it's the value with _sec appended.
            valIn = n -- if it ever did happen, this may be right thing to do(?)
        else -- expected
            --Debug.pause( valIn, n )
        end
    end
    if type( valIn ) == 'string' then
        return valIn
    elseif type( valIn ) == 'number' then
        local valOut
        if valIn < 0 then
            valOut = -valIn
        else
            valOut = valIn
        end
        --Debug.pause( valIn, valOut )
        valOut = math.pow( 2, valOut )
        --Debug.pause( valIn, valOut )
        if valIn > 0 then -- corresponds to fractional shutter speeds.
            valOut = 1/valOut
        end
        if valOut >= 1 then
            return str:fmtx( "^1 sec", string.format( "%.1f", valOut ) )
        else
            return str:fmtx( "^1 sec", string.format( "%.5f", valOut ) )
        end
    else
        Debug.pause()
        return str:to( valIn )-- I guess..
    end
end


-- 32 in UI yields value of 10
local function apertureValidate( vw, val )
    if type( val ) == 'string' then
        val = LrStringUtils.trimWhitespace( val )
        if val ~= "" then
            local sp, sq = val:find( "f ?/" )    
            if sp then
                val = val:sub( sq + 1 ) -- take rear part
            end
            local v = tonumber( val )
            if v ~= nil then
                val = logBase2( val ) -- Lua 5.1's math lib does not support base param (Lua 5.2 does).
                if val ~= nil then
                    return true, val * 2
                else
                    return false, val, "must be a number greater than or equal to 1 and (optionally, preceded by \"f / \")"
                end
            else
                return false, val, "must be a number greater than or equal to 1 and (optionally, preceded by \"f / \")"
            end
        else -- blank field
            return true, 0 -- equivalent of 1 second, since 0 is exponent (log) of base 2.
        end
    else -- already numeric
        return true, val
    end
end


local function apertureToString( vw, valIn )
    if valIn == nil then
        Debug.pause() -- this hasn't happened yet.
        return "" -- if it did, presumably this would be the right response.
    end
    if type( valIn ) == 'string' then -- already converted to string, and being called again
        local n = tonumber( valIn ) -- see if it's a number
        if n then -- not already converted (with ' sec' suffix).
            Debug.pause( valIn, n ) -- this never happens, since if string, it's the value with _sec appended.
            valIn = n -- if it ever did happen, this may be right thing to do(?)
        else -- expected
            --Debug.pause( valIn, n )
        end
    end
    if type( valIn ) == 'string' then
        return valIn
    elseif type( valIn ) == 'number' then
        --Debug.pause( valIn, valOut )
        if valIn < 0 then
            Debug.pause( "negative aperture?" )
            valIn = 0
        end
        local valOut = math.pow( 2, valIn / 2 )
        Debug.pause( valIn, valOut )
        return str:fmtx( "f / ^1", string.format( "%u", valOut ) )
    else
        Debug.pause()
        return str:to( valIn )-- I guess..
    end
end



-- Note: these tables are relying on the fact that Lr seems happy to ignore extraneous stuff in the items list.
-- if that changes, one would need to separate items from the other stuff (which is how it was originally).


local dateTimeOpTable = {
    { title="is", value='==', fieldType='date', validate=dateValidate }, -- field/value type is string, but maybe should have field-type of "date".
    { title="is not", value='~=', fieldType='date', validate=dateValidate }, -- ditto
    { title="is after", value='>', fieldType='date', validate=dateValidate },
    { title="is before", value='<', fieldType='date', validate=dateValidate },
    { title="is in the last", value='inLast', fieldType='number', constraints={ precision=1, min=1, max=100000 }, valUnitsTable=dateTimeUnitsTable },
    { title="is not in the last", value='notInLast', fieldType='number', constraints={ precision=1, min=1, max=100000 }, valUnitsTable=dateTimeUnitsTable },
    { title="is in the range", value='in', fieldType='date', validate=dateValidate, numValues=2 }, -- ditto
    { title="is today", value='today', numValues=0 },
    { title="is yesterday", value='yesterday', numValues=0 },
    { title="is in this week", value='thisWeek', numValues=0 },
    { title="is in this month", value='thisMonth', numValues=0 },
    { title="is in this year", value='thisYear', numValues=0 },
}

local textOpTable = {
    { title="contains", value='any' },
    { title="contains all", value='all' },
    { title="contains words", value='words' },
    { title="doesn't contain", value='noneOf' },
    { title="starts with", value='beginsWith' },
    { title="ends with", value='endsWith' },
}

local specificTextOpTable = {
    { title="is", value='==' },
    { title="is not", value='~=' },
    { title="contains", value='any' },
    { title="contains all", value='all' },
    { title="doesn't contain", value='noneOf' },
    { title="contains words", value='words' },
    { title="starts with", value='beginsWith' },
    { title="ends with", value='endsWith' },
}

local keywordsOpTable = {
    { title="contains", value='any' },
    { title="contains all", value='all' },
    { title="contains words", value='words' },
    { title="doesn't contain", value='noneOf' },
    { title="starts with", value='beginsWith' },
    { title="ends with", value='endsWith' },
    { title="are empty", value='empty', numValues=0 }, -- 'are' (not 'is').
    { title="aren't empty", value='notEmpty', numValues=0 },
}

local pluginTextOpTable = { -- mostly used just for plugin text, but also applies to caption...
    { title="contains", value='any' },
    { title="contains all", value='all' },
    { title="contains words", value='words' },
    { title="doesn't contain", value='noneOf' },
    { title="starts with", value='beginsWith' },
    { title="ends with", value='endsWith' },
    { title="is empty", value='empty', numValues=0 }, -- 'is' (keywords uses 'are')
    { title="isn't empty", value='notEmpty', numValues=0 },
}


local numOpTable = { -- general (or "generic" if you prefer) number operation table, i.e. no constraints supplied, so they'd better be supplied in criteria table.
    { title='is', value="==" },
    { title='is not', value="!=" },
    { title='is greater than', value=">" },
    { title='is less than', value="<" },
    { title='is greater than or equal to', value=">=" },
    { title='is less than or equal to', value="<=" },
    { title='is in range', value="in", numValues=2 },
}

local colorModeValueTable = {
    { title="Grayscale", value=1 },
    { title="RGB", value=2 },
    { title="RGB Palette", value=3 },
    { title="Transparency Mask", value=4 },
    { title="CMYK", value=5 },
    { title="YCbCr", value=6 },
    { title="CIELab", value=8 },
    { title="ICCLab", value=32803 },
    { title="Color Filter Array", value=9 },
    { title="Linear Raw", value=34892 },
    { title="Unknown", value=-1 },
}

local pickStatusValueTable = {
    { title="flagged", value=1 },
    { title="unflagged", value=0 },
    { title="rejected", value=-1 },
}

local ratingValueTable = {
    { title="unrated", value=0 }, -- could probably be nil instead.
    { title="1-star", value=1 },
    { title="2-star", value=2 },
    { title="3-star", value=3 },
    { title="4-star", value=4 },
    { title="5-star", value=5 },
}

local labelColorValueTable = {
    { title="red", value=1 },
    { title="yellow", value=2 },
    { title="green", value=3 },
    { title="blue", value=4 },
    { title="purple", value=5 },
    { title="custom", value='custom' }, -- hmm - mixed data types..
    { title="none", value='none' },
}

-- a unique combo for label text:
local labelTextOpTable = {
    { title='is', value="==" },
    { title='is not', value="!=" },
    { title='is empty', value="empty", numValues=0 },
    { title="isn't empty", value="notEmpty", numValues=0 },
}

local booleanOpTable = {
    { title='is true', value="isTrue", numValues=0 },
    { title='is false', value="isFalse", numValues=0 },
}


local flashFiredValueTable = {
    { title='did fire', value=true },
    { title='did not fire', value=false },
    { title='unknown', value=nil }, -- i.e. no value.
}

local gpsValueTable = {
    { title="Coordinates", value=true },
    { title="No Coordinates", value=false },
}

local copyrightStatusValueTable = {
    { title='copyrighted', value=true },
    { title='public domain', value=false },
    { title='unknown', value="unknown" },
}

local metadataStatusValueTable = {
    { title='Up to date', value='upToDate' },
    { title='Conflict detected', value='conflict' },
    { title='Has been changed', value='hasBeenChanged' },
    { title='Changed on disk', value='changedOnDisk' },
    { title='Unknown', value="unknown" },
}

local devPresetValueTable = {
    { title="default", value="default" },
    { title="specified", value="specified" },
    { title="custom", value="custom" },
}

local treatmentValueTable = {
    { title="black and white", value="grayscale" },
    { title="color", value="color" },
}


local matchOpTable = {
    { title="is", value="==" },
    { title="is not", value="!=" },
}


local fileFormatValueTable = {
    { title='Digital Negative (DNG)', value="DNG" },
    { title='Digital Negative / Lossless', value="DNG-LOSSLESS" },
    { title='Digital Negative / Lossy Compressed', value="DNG-LOSSY" },
    { title='Digital Negative / Reduced Resolution', value="DNG-REDUCED" },
    { title='Raw', value="RAW" },
    { title='JPEG', value="JPEG" },
    { title='TIFF', value="TIFF" },
    { title='PNG', value="PNG" },
    { title='Photoshop Document (PSD)', value="PSD" },
    { title='Video', value="VIDEO" },
}

local aspectRatioValueTable = {
    { title='portrait', value="portrait" },
    { title='landscape', value="landscape" },
    { title='square', value="square" },
}


local criteriaTable = { -- popup-compatible
    -- top items
    { title="Rating", value='rating', opTable=numOpTable, valueItems=ratingValueTable },
    -- note: it would then need overlay UI, to support both edit-field and popup in same UI space.
    { title="Pick Flag", value='pick', opTable=matchOpTable, valueItems=pickStatusValueTable }, --pickStatusOpTable },
    { title="Label Color", value='labelColor', opTable=matchOpTable, valueItems=labelColorValueTable },
    { title="Label Text", value='labelText', opTable=labelTextOpTable },
    { title="Has Smart Preview", value='proxyStatus', opTable=booleanOpTable },
    { separator=true },
   
    -- Source
    { title="Folder", value='folder', opTable=textOpTable },
    { title="Collection", value='collection', opTable=textOpTable },
    { title="Publish Collection", value='publishCollection', opTable=textOpTable },
    { title="Published Via", value='publishedVia', opTable=textOpTable },
    { separator=true },

    -- File Name / Type
    { title="Filename", value='filename', opTable=textOpTable },
    { title="Copy Name", value='copyname', opTable=pluginTextOpTable }, -- not plugin, but same text options
    { title="File Type", value='fileFormat', opTable=matchOpTable, valueItems=fileFormatValueTable },--fileFormatOpTable },
    { title="Is DNG With Fast Load Data", value='fastLoadDNG', opTable=booleanOpTable },
    { separator=true },

    -- Dates
    { title="Capture Date", value='captureTime', opTable=dateTimeOpTable }, -- op-table includes field-type specific op-items
    { title="Edit Date", value='touchTime', opTable=dateTimeOpTable },
    { separator=true },

    -- Camera Info
    { title="Camera", value='camera', opTable=specificTextOpTable },
    { title="Camera Serial Number", value='cameraSN', opTable=specificTextOpTable },
    { title="Lens", value='lens', opTable=specificTextOpTable },
    { title="Focal Length", value='focalLength', opTable=numOpTable, constraints={ precision=0, min=0, max=65535 } },
    { title="Shutter Speed", value='shutterSpeed', opTable=numOpTable, validate=shutterSpeedValidate, value_to_string=shutterSpeedToString },
    { title="Aperture", value='aperture', opTable=numOpTable, validate=apertureValidate, value_to_string=apertureToString },
        -- note: dunno about the max value, Lr's is bigger, but seems arbitrary, however if ya use math.huge, it puts funny symbols instead of a real max num.
    { title="ISO Speed Rating", value='isoSpeedRating', opTable=numOpTable, constraints={ precision=0, min=0, max=100000 } }, -- max I know if is 12.8k, so max is 8x, which seems under-oomph'd - still: it matches Lr UI.
        -- Lr's using tenths decimal place, but, fractional ISOs??
    { title="Flash", value='flashFired', opTable=matchOpTable, valueItems=flashFiredValueTable },
    { separator=true },

    -- Location
    { title="Country", value='country', opTable=specificTextOpTable },
    { title="State / Province", value='state', opTable=specificTextOpTable },
    { title="City", value='city', opTable=specificTextOpTable },
    { title="Sublocation", value='location', opTable=specificTextOpTable },
    { separator=true },
    { title="GPS Data", value='hasGPSData', opTable=matchOpTable, valueItems=gpsValueTable },
    { separator=true },

    -- Other Metadata
    { title="Title", value='title', opTable=textOpTable },
    { title="Caption", value='caption', opTable=pluginTextOpTable }, -- not plugin text, but same ops.
    { title="Keywords", value='keywords', opTable=keywordsOpTable },
    { title="Creator", value='creator', opTable=specificTextOpTable },
    { title="Job", value='jobIdentifier', opTable=specificTextOpTable },
    { title="Copyright Status", value='copyrightState', opTable=matchOpTable, valueItems=copyrightStatusValueTable },
    { separator=true },

    { title="Any Searchable Metadata", value='metadata', opTable=textOpTable },
    { title="Searchable IPTC", value='iptc', opTable=textOpTable },
    { title="Searchable EXIF", value='exif', opTable=textOpTable },
    { title="Any Searchable Plugin Metadata", value='allPluginMetadata', opTable=textOpTable },
    { title="Metadata Status", value='metadataStatus', opTable=matchOpTable, valueItems=metadataStatusValueTable },
    { separator=true },

    -- Develop    
    { title="Has Adjustments", value='hasAdjustments', opTable=booleanOpTable },
    { title="Is Proof", value='isProofCopy', opTable=booleanOpTable },
    { title="Develop Preset", value='developPreset', opTable=matchOpTable, valueItems=devPresetValueTable },
    { title="Treatment", value='treatment', opTable=matchOpTable, valueItems=treatmentValueTable },
    { title="Cropped", value='cropped', opTable=booleanOpTable },
    { separator=true },

    -- Size
    { title="Long Edge", value='longEdge', opTable=numOpTable, constraints={ precision=0, min=0, max=100000 } },
    { title="Short Edge", value='shortEdge', opTable=numOpTable, constraints={ precision=0, min=0, max=100000 } },
    { title="Width", value='width', opTable=numOpTable, constraints={ precision=0, min=0, max=100000 } },
    { title="Height", value='height', opTable=numOpTable, constraints={ precision=0, min=0, max=100000 } },
    { title="Megapixels", value='megapixels', opTable=numOpTable, constraints={ precision=1, min=0, max=100000 } },
    { separator=true },
    
    { title="Long Edge Cropped", value='longEdgeCropped', opTable=numOpTable, constraints={ precision=0, min=0, max=100000 } },
    { title="Short Edge Cropped", value='shortEdgeCropped', opTable=numOpTable, constraints={ precision=0, min=0, max=100000 } },
    { title="Width Cropped", value='widthCropped', opTable=numOpTable, constraints={ precision=0, min=0, max=100000 } },
    { title="Height Cropped", value='heightCropped', opTable=numOpTable, constraints={ precision=0, min=0, max=100000 } },
    { title="Megapixels Cropped", value='megapixelsCropped', opTable=numOpTable, constraints={ precision=1, min=0, max=100000 } },
    
    { separator=true },
    { title="Aspect Ratio", value='aspectRatio', opTable=numOpTable, valueItems=aspectRatioValueTable },
    --{ title="Aspect Ratio Cropped", value='aspectRatioCropped', opTable=numOpTable, valueItems=aspectRatioValueTable }, - no cropped version for some reason.
    { separator=true },
    
    -- Color
    { title="Bits Per Channel", value='bitDepth', opTable=numOpTable, constraints={ precision=0, min=1, max=32 } }, -- defaults would be a nice touch ###2
    { title="Source Color Mode", value='colorMode', opTable=matchOpTable, valueItems=colorModeValueTable },
    { title="Source Color Profile", value='colorProfile', opTable=textOpTable },
    { separator=true },

    -- Plugin metadata
    --{ title="Plugin Metadata", value='pluginMeta', opTable=textOpTable },
    
    
    { title="Any Searchable Text", value='all', opTable=textOpTable },
}


function SmartCollections:init()
    if self.combineLookup then return end
    dbgf( "smart-coll i/f initializing." )
    self.combineLookup = {}
    for i, v in ipairs( combineTable ) do
        self.combineLookup[v.value] = v
    end
    self.criteriaLookup = {}
    --self.valUnitsLookup = {}
    for i, critItem in ipairs( criteriaTable ) do
        repeat
            if critItem.separator then break end
            app:assert( critItem.opTable, "no op-table for ^1", critItem.title or "no title" )
            self.criteriaLookup[critItem.value] = critItem
            local opLookup
            if critItem.opLookups == nil then
                critItem.opLookups = {}
            end
            if critItem.opLookups[critItem.opTable] == nil then
                critItem.opLookups[critItem.opTable] = {}
            else
                break
            end
            opLookup = critItem.opLookups[critItem.opTable]
            for j, u in ipairs( critItem.opTable ) do
                opLookup[u.value] = u
            end
            Debug.lognpp( critItem.value, opLookup )
        until true                
        -- criteria table is already in popup-compatible format.
    end
    -- handle plugin text op lookup as special case.
    self.pluginOpLookup = {}
    for i, v in ipairs( pluginTextOpTable ) do
        self.pluginOpLookup[v.value] = v
    end
    -- handle plugin enum op lookup as special case.
    --self.pluginOpLookup = {}
    for i, v in ipairs( matchOpTable ) do
        self.pluginOpLookup[v.value] = v
    end
end


function SmartCollections:getCombinePopupItems()
    return combineTable -- already in popup-compatible format.
end

function SmartCollections:getCriteriaPopupItems()
    --Debug.pause()
    return criteriaTable
end

-- return nil if no op-table, in which case resort to raw edit-field.
function SmartCollections:getOperationPopupItems( critId )
    local critItem = self.criteriaLookup[critId]
    if critItem then
        if critItem.opTable then
            return critItem.opTable -- , critItem.opLookups[critItem.opTable]
        else
            Debug.pause( "no op table" ) -- technically, this is a programming error, but best to keep the wheel turning..
            return nil
            -- return {{title="[no op tbl]",value=nil}}
        end
    else -- this is what happens if user has plugin-metadata in smart collection, which is supported by presenting 
        --Debug.pause( "no lookup for", critId )
        return nil
        --return {{title=str:fmtx( "[no op for ^1]", critId ),value=nil}}
    end    
end

function SmartCollections:getValUnitPopupItems( critId, opId )
    local critItem = self.criteriaLookup[critId]
    if critItem then
        -- check critItem/valUnitsTable?
        local lookup = critItem.opLookups[critItem.opTable]
        Debug.pauseIf( lookup==nil, critId, opId, critItem, critItem.opLookups )
        if lookup then
            local opItem = lookup[opId]
            if opItem then
                if opItem.valUnitsTable then
                    --Debug.pause( opItem.valUnitsTable )
                    return opItem.valUnitsTable, opItem
                else
                    --Debug.pause( critId, opId, opItem )
                    return nil, opItem
                end
            else
                --Debug.pause( critId, opId )
                return nil
            end
        else
            --Debug.pause( critId, opId )
            return nil
        end
    else
        --Debug.pause( critId, opId )
        return nil
    end
end

function SmartCollections:getFriendlyCriteria( critId )
    local critItem = self.criteriaLookup[critId]
    if critItem then
        return critItem.title
    else
        --Debug.pause( critId )
        return str:fmtx( "[^1]", critId )
    end
end 


--  returns string which represents operation, and corresponding op-item, if operation in lookup. If operation not in lookup, and non-registered crit, then returns a the ID bracketed to represent operation, and nil for op-item.
function SmartCollections:getFriendlyOperation( critId, opId )
    local critItem = self.criteriaLookup[critId]
    if critItem then
        local lookup = critItem.opLookups[critItem.opTable]
        Debug.pauseIf( lookup==nil, critId, opId, critItem, critItem.opLookups )
        if lookup then
            local opItem = lookup[opId]
            if opItem then
                return opItem.title, opItem
            else
                --Debug.pause( critId, opId )
                return str:fmtx( "[^1]", opId )
            end
        else
            Debug.pause( critId, opId )
            return str:fmtx( "[^1]", opId )
        end
    else
        critId = LrStringUtils.trimWhitespace( critId )
        if str:isBeginningWith( critId, "sdk" ) then -- sdktext: standard prefix for plugin textual metadata. sdk: for enums.
            local opItem = self.pluginOpLookup[opId]
            if opItem then
                return opItem.title, opItem
            else
                return str:fmtx( "[^1]", opId )
            end
        else -- not plugin-metadata
            return str:fmtx( "[^1]", opId )
        end
    end
end


function SmartCollections:getFriendlyValues( v, opItem, smartCollName )
    --Debug.pause( v )
    local value, value2, vunits = v.value, v.value2, v.value_units -- raw convenience.
    local v1, v2, value_units -- friendly
    local critItem = self.criteriaLookup[v.criteria]
    if critItem then
        if opItem then
            local nv = opItem.numValues == nil and 1 or opItem.numValues
            if nv > 0 then
                local fieldType
                if critItem.valueItems then
                    fieldType = 'popup'
                elseif critItem.constraints then
                    fieldType = 'number'
                else
                    fieldType = opItem.fieldType -- a few ops have different field types depending on which op-item is selected.
                    -- reminder: absent field-type will be treated as string.
                end
                if fieldType == 'popup' then
                    local valueItems = opItem.valueItems or critItem.valueItems or error( "no value items for popup" ) -- if in op-table for item, it takes precedence, else had better be in crit-tbl.
                    for i, tv in ipairs( valueItems ) do
                        local fv
                        if type( value ) ~= type( tv.value ) then
                            fv = var:coerceType( value, type( tv.value ) )
                        else
                            fv = value
                        end
                        if fv == tv.value then
                            v1 = tv.title
                            if nv == 1 or v2 ~= nil then
                                break
                            end
                        end
                        if nv > 1 and v2 == nil then
                            local fv2
                            if type( value2 ) ~= type( tv.value ) then
                                fv2 = var:coerceType( value2, type( tv.value ) )
                            else
                                fv2 = value2
                            end
                            if fv2 == tv.value then
                                v2 = tv.title
                                if nv > 1 and v1 ~= nil then
                                    break
                                end
                            end
                        end
                    end
                    if v1 == nil then
                        v1 = str:to( value )
                    end
                    if nv > 1 and v2 == nil then
                        v2 = str:to( value2 )
                    end
                else
                
                    local tostr = critItem.value_to_string or opItem.value_to_string
                    if tostr then
                        if value ~= nil then
                            value = tostr( nil, value )
                        end
                        if value2 ~= nil then
                            value2 = tostr( nil, value2 )
                        end
                    end
                
                    if nv == 1 then
                        v1 = str:to( value )
                        v2 = nil
                    else
                        v1 = str:to( value )
                        v2 = str:to( value2 )
                    end
                end
                value_units = opItem.valUnitsTable and vunits or ""
                --Debug.pause( opItem.valUnitsTable, vunits, value_units )
            else
                v1 = nil
                v2 = nil
                value_units = ""
            end
        else
            v1 = value
            v2 = value2
            value_units = vunits or ""
        end
    else -- no crit item (presumably plugin metadata)
        if opItem then -- confirmed plugin metadata
            if opItem.numValues == 0 then
                v1 = nil
                v2 = nil
            elseif opItem.numValues == 2 then
                v1 = value
                v2 = value2
            else
                v1 = value
                v2 = nil
            end
        else -- basically, a bogus entry (e.g. user mis-edited the criteria field).
            --Debug.pause( "no crit-item, no op-item" )
            app:show{ warning="The smart collection '^1' contains a rule which appears to be bogus/wonked. Consider double-checking it and re-editing...", smartCollName }
            v1 = value
            v2 = value
            -- I guess
        end
        value_units = ""
    end
    return v1, v2, value_units
end


function SmartCollections:lookupCombine( combine )
    return self.combineLookup[combine]
end
function SmartCollections:lookupCriteria( criteria )
    return self.criteriaLookup[criteria]
end
function SmartCollections:lookupPluginOp( operation )
    return self.pluginOpLookup[operation]
end
function SmartCollections:getMatchOpTable()
    return matchOpTable
end
function SmartCollections:getPluginTextOpTable()
    return pluginTextOpTable
end



--- Get photos defined by rules of specified smart collection - Lr5+ only.
--
--  @usage throws error if Lr4-, so check before calling, be prepared for error..
--  @usage *** See source code for other (undocumented) methods which may be of interest.
--
--  @param smartColl (LrCollection, required) must be smart.
--  @param options (table, optional) members: sort, & ascending. Defaults are 'captureTime' and true, respectively.
--
--  @return array of lr-photos - empty if none, never nil.
--
function SmartCollections:getPhotos( smartColl, options )
    if app:lrVersion() >= 5 then
        local args = tab:mergeSets( {
            sort = 'captureTime',
            ascending = true,
        }, options ) -- overwrite defaults with specified options, if applicable.
        args.searchDesc = smartColl:getSearchDescription()
        --Debug.lognpp( args.searchDescr )
        --local photos = catalog:findPhotos( args )
        --Debug.lognpp( smartColl:getName(), photos )
        --return photos
        return catalog:findPhotos( args ) -- tail call performance advantage in Lua.
    else
        app:callingError( "Requires Lr5+" )
    end
end



return SmartCollections