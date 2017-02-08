--[[
        DateTime:lua
--]]

local DateTime, dbg, dbgf = Object:newClass{ className = 'DateTime', register = false }



--- Constructor for extending class.
--
function DateTime:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function DateTime:new( t )
    return Object.new( self, t )
end



local leapMonthSecs = nil
local normalMonthSecs = nil
local leapYearSecs = 0
local normalYearSecs = 0



--- Format date/time in default format.
--
function DateTime:formatDateTime( time )
    return LrDate.timeToUserFormat( time, "%Y-%m-%d %H:%M:%S" )
end



--- Format date in default format.
--
--  @param time date-time number (Lr SDK epoch)
--
--  @return string e.g. 2014-05-29
--
function DateTime:formatDate( time )
    return LrDate.timeToUserFormat( time, "%Y-%m-%d" )
end



--- Format time in default format.
--
--  @param time date-time number (Lr SDK epoch)
--
--  @return string e.g. 12:00:01
--
function DateTime:formatTime( time )
    return LrDate.timeToUserFormat( time, "%H:%M:%S" )
end



--- Format time difference as number.msec
--
--  @usage *** deprecated - use num--fmt-prec instead.
--
function DateTime:formatTimeDiffMsec( secs )
    local s = math.floor( secs )
    local r = ( secs - s ) * 1000
    local f = string.format( "%d.%03u", s, r )
    return f
end



--- Convert a number of seconds to hours:mm:ss format.
--      
--  @param      secs        time difference in seconds.
--
--  @usage      Takes a number, not a string.
--  @usage      Uses lr-path-utils-remove-extension (floor) instead of lr-string-utils-number-to-string (may round up).
--  @usage      Reminder: Very small time differences wreak havoc - round to zero for sanity.
--
--  @return string e.g. 12:00:01
--
function DateTime:formatTimeDiff( secs )
    assert( type( secs ) == 'number', "Bad argument type" )
    local sign
    if secs < 0 then
        secs = 0 - secs
        sign = '-'
    else
        sign = ''
    end
    if secs < 1 then
        secs = 0 -- nearest second.
    end
    local hourString = LrPathUtils.removeExtension( tostring( secs / 3600 ) ) -- truncated integer string
    local hours = tonumber( hourString ) -- back to number.
    local minuteString = LrPathUtils.removeExtension( tostring( ( secs - ( hours * 3600 ) ) / 60 ) )
    local minutes = tonumber( minuteString )
    local secondString = LrPathUtils.removeExtension( tostring( secs - ( hours * 3600 ) - ( minutes * 60 ) ) )
    -- local seconds = tonumber( secondString ) -- dont need seconds as number.
    -- no reason to pad hour string - calling context can pad the whole thing upon return if desired.
    minuteString = str:padLeft( minuteString, "0", 2 )
    secondString = str:padLeft( secondString, "0", 2 )
    if hours > 0 then
        return str:format( "^1^2:^3:^4", sign, hourString, minuteString, secondString )
    elseif minutes > 0 then
        return str:format( "^1^2:^3", sign, minuteString, secondString )
    else
        return str:format( "^1^2", sign, secondString )
    end
end
    
    
    
---  Parse date in MM-DD-YY format.
--
--	<p>Motivation for creation: Originally created to support windows directory entry parsing.</p>
--	<p>the unix version is in the ftp module for now (thats the only place its used).</p
--
--  @usage				Error handling is a bit weak. ###4
--  @usage              Will not work anymore after 1-1-2070.
--
--	@return			    4-digit year, month(1-12), day(1-31) numbers, else error message.
--
function DateTime:parseMmDdYyDate( dateStr )
	local chr = str:getChar( dateStr, 3 )
	local monthStr, dayStr, yearStr
	if chr == '-' then
		monthStr = string.sub( dateStr, 1, 2 )
	else
		return "no dash for month in mm-dd-yy date string"
	end
	chr = str:getChar( dateStr, 6 )
	if chr == '-' then
		dayStr = string.sub( dateStr, 4, 5 )
		yearStr = string.sub( dateStr, 7, 8 )
	else
		return "no dash for day in mm-dd-yy date string"
	end
	local year = tonumber( yearStr )		
	local month = tonumber( monthStr )		
	local day = tonumber( dayStr )		
	if year >= 70 then -- last century
		year = 1900 + year
	else
		year = 2000 + year
	end
	return year, month, day
end


--- Parse date from string, when expressed year first, 4 digits followed by separator (default separator is dash, slash (forward or back), or underscore) and 1-2 char mo. then 1-2 char day.
--
--  @usage Examples:
--      <br>    2013-12-31  (valid)
--      <br>    2014/1/1    (valid)
--      <br>    2014_01_01  (valid)
--      <br>    14/01/01    (NOT valid)
--
function DateTime:parseYyyyMmDdDate( a, sep )
    sep = sep or "[-/\\_]"
    local b = { a:match( str:fmtx( "(%d%d%d%d)^1(%d%d?)^1(%d%d?)", sep ) ) } -- full-year required, but months and/or days can be partially qualified (need not be 0 padded).
    if #b == 3 then
        local y = tonumber( b[1] )
        local m = tonumber( b[2] )
        local d = tonumber( b[3] )
        local t = LrDate.timeFromComponents( y, m, d )
        return t
    else
        return nil
    end
end



--- Parse time in HH:MM{AM/PM} format.
--
--	<p>Motivation for creation: Originally created to support windows directory entry parsing.</p>
--	<p>the unix version is in the ftp module for now (thats the only place its used).</p
--
--	@usage          Error handling is a bit weak. ###4
--  @usage          Will not work after 1-1-2070.
--
--	@return         hour (0-23), minute (0-59), else error message.
--
function DateTime:parseHhMmAmPmTime( timeStr )
	local chr = str:getChar( timeStr, 3 )
	local hourStr, minuteStr
	if chr == ':' then
		hourStr = string.sub( timeStr, 1, 2 )
		minuteStr = string.sub( timeStr, 4, 5 )
	else
		return "no colon for hour/minute in hh:mm{am/pm} string: " .. timeStr
	end
	local amPmStr = string.sub( timeStr, 6, 7 )
	local hour = tonumber( hourStr )		
	local minute = tonumber( minuteStr )		
	local offset
	if amPmStr == 'AM' then
		offset = 0
	elseif amPmStr == 'PM' then
		offset = 12
	else
		return "expected time in 12-hour format: " .. timeStr
	end
	return hour + offset, minute
end



--- Format time in UTC standard notation, with ms.
--
--  @param time from arbitrary time zone.
--  @param offset seconds from utc.
--  @param dls flag for dls adjustment.
--
function DateTime:timeToUtcFormat( time, offset, dls )

    local dlsAdj = 0
    local _offset, dlsFlg = LrDate.timeZone()
    
    if dls and dlsFlg then
        dlsAdj = 3600
    end
    
    if offset == nil then
        offset = _offset
    end
    
    --local subs = time - math.floor( time )
    --local ms = subs * 1000
    --local msFmt = string.format( "%u", ms )
    time = time + offset + dlsAdj
    local fmt = LrDate.timeToW3CDate( time, 0 ):sub( 1, -7 ) .. 'Z' -- offset already folded in.
    return fmt

end



--- Format time as structure with named members (numerical values).
--
--  @param  dt      Date-time number
--  @param  ofs     optional utc offset in seconds.
--  @param  includeJulianDay (boolean, default=false) set true to have julian day included in time struct.
--
--  @return table with members: year, month, day, hour, minute, second, dayOfWeek, and optionally: julianDay.
--
function DateTime:timeStruct( dt, ofs, includeJulianDay )
    local timeNumArray = { LrDate.timestampToComponents( dt, ofs ) } -- nil => local time-zone, 0 => utc/gmt.
    local timeNumStruct = {
        year = timeNumArray[1],
        month = timeNumArray[2],
        day = timeNumArray[3],
        hour = timeNumArray[4],
        minute = timeNumArray[5],
        second = timeNumArray[6],
        dayOfWeek = timeNumArray[7],
    }
    if includeJulianDay then
        local js = LrDate.timeToUserFormat( dt, "%j", ofs ~= nil ) -- is-gmt.
        timeNumStruct.julianDay = num:numberFromString( js )
    end
    return timeNumStruct
end



--[==[      *** SAVE FOR FUTURE REFERENCE: these methods work, but lr-date has equivalent functions.
            
            function DateTime:getYearSecs( year )
                local secs = 0
                year = year - 1 -- dont count this year's seconds.
                while ( year >= 2001 ) do
                    if DateTime:isLeapYear( year ) then
                        secs = secs + leapYearSecs
                    else
                        secs = secs + normalYearSecs
                    end
                    year = year - 1
                end
                return secs
            end
            --[[
                    Works for years 2001 to 2099.
            --]]
            function DateTime:isLeapYear( year )
                return math.mod( year, 4 ) == 0
            end
            --[[
                    - these must be confined as follows or it will blow up:
                    year:   2001+
                    month:  1-12
                    day:    1-31
                    - these can sometimes be a bit bigger (or even a tiny bit smaller) if some adjustment has been made but not normalized:
                    hour:   0-23
                    minute: 0-59
                    second: 0-59
            --]]
            function DateTime:getTime( year, month, day, hour, minute, second )
                if leapMonthSecs == nil then
                    leapMonthSecs = {}
                    leapMonthSecs[1] = 0
                    leapMonthSecs[2] = 31 * 86400
                    leapMonthSecs[3] = leapMonthSecs[2] + (29 * 86400)
                    leapMonthSecs[4] = leapMonthSecs[3] + (31 * 86400)
                    leapMonthSecs[5] = leapMonthSecs[4] + (30 * 86400)
                    leapMonthSecs[6] = leapMonthSecs[5] + (31 * 86400)
                    leapMonthSecs[7] = leapMonthSecs[6] + (30 * 86400)
                    leapMonthSecs[8] = leapMonthSecs[7] + (31 * 86400)
                    leapMonthSecs[9] = leapMonthSecs[8] + (31 * 86400)
                    leapMonthSecs[10] = leapMonthSecs[9] + (30 * 86400)
                    leapMonthSecs[11] = leapMonthSecs[10] + (31 * 86400)
                    leapMonthSecs[12] = leapMonthSecs[11] + (30 * 86400)
                    normalMonthSecs = {}
                    normalMonthSecs[1] = 0
                    normalMonthSecs[2] = 31 * 86400
                    normalMonthSecs[3] = normalMonthSecs[2] + (28 * 86400)
                    normalMonthSecs[4] = normalMonthSecs[3] + (31 * 86400)
                    normalMonthSecs[5] = normalMonthSecs[4] + (30 * 86400)
                    normalMonthSecs[6] = normalMonthSecs[5] + (31 * 86400)
                    normalMonthSecs[7] = normalMonthSecs[6] + (30 * 86400)
                    normalMonthSecs[8] = normalMonthSecs[7] + (31 * 86400)
                    normalMonthSecs[9] = normalMonthSecs[8] + (31 * 86400)
                    normalMonthSecs[10] = normalMonthSecs[9] + (30 * 86400)
                    normalMonthSecs[11] = normalMonthSecs[10] + (31 * 86400)
                    normalMonthSecs[12] = normalMonthSecs[11] + (30 * 86400)
                    leapYearSecs = leapMonthSecs[12] + (31 * 86400) -- add in december
                    normalYearSecs = normalMonthSecs[12] + (31 * 86400) -- add in december
                end
                local secs = DateTime:getYearSecs( year )
                if DateTime:isLeapYear( year ) then
                    secs = secs + leapMonthSecs[ month ]
                else
                    secs = secs + normalMonthSecs[ month ]
                end
                secs = secs + ( ( day - 1 ) * 86400 )
                secs = secs + hour * 3600
                secs = secs + minute * 60
                secs = secs + second
                assert (secs == LrDate.timeFromComponents( year, month, day, hour, minute, second, 0 ), "Lightroom time does not agree." ) -- This function returns
                    -- exact same value as Lightroom's.
                return secs
            end
--]==]



return DateTime
