--[[
     File Name           :     Debugging.lua
     Created By          :     tubiakou
     Creation Date       :     [2019-01-07 01:28]
     Last Modified       :     [2019-02-10 20:28]
     Description         :     Debugging facility for the WoW addon AllFriends
--]]

--[[
This module of AllFriends implements a simple debugging facility, enabling the
addon to output severity-filtered messages to the debug system (currently the
chat-frame).  The following is a simplified example illustrating usage:

debug = AF.Debugging:new( )
debug:setLevel( ERROR )  -- may be DEBUG, INFO, WARN, ERROR, ALWAYS (increasing severity)

debug:warn( "This message will not be output - WARN is lower severity than ERROR." )
debug:error( "This message will be output - equal-to or greater than ERROR" )
debug:always( "This message will always be output" )
debug:info( "The messages can be in strformat() form, player %s.", UnitName( "player" ) )
debug:debug( "You may pass tables, strings, numbers, etc., like this:")
debug:debug( C_FriendList.GetFriendInfoByName( "somefriend" ) )

debug:log( ERROR, You can also use debug:log() to specify the msg severity manually." )
]]--

-- WoW API treats LUA modules as "functions", and passes them two arguments:
--  1. The name of the addon, and
--  2. A table containing the globals for that addon.
-- Using these lets all modules within an addon share the addon's global information.
--local addonName, AF = ...
local addonName, AF_G = ...


-- Some local overloads to optimize performance (i.e. stop looking up these
-- standard functions every single time they are called, and instead refer to
-- them by local variables.
local select        = select
local string        = string
local strfind       = string.find
local strformat     = string.format
local strmatch      = string.match
local strupper      = string.upper
local type          = type



-- Debugging levels (increasing severity)
TRACE   = "TRACE"   -- Flow tracing (function entry/exit, etc)
DEBUG   = "DEBUG"   -- Highly detailed/verbose information
INFO    = "INFO"    -- Informative information
WARN    = "WARN"    -- Warnings about unexpected conditions/results
ERROR   = "ERROR"   -- Errors that will break things
ALWAYS  = "ALWAYS"  -- Output that should be shown unconditionally


-- Standardized colour codes
AF.CLR_BLACK   = "\124cff000000"
AF.CLR_MAROON  = "\124cff800000"
AF.CLR_GREEN   = "\124cff008000"
AF.CLR_OLIVE   = "\124cff808000"
AF.CLR_NAVY    = "\124cff000080"
AF.CLR_PURPLE  = "\124cff800080"
AF.CLR_TEAL    = "\124cff008080"
AF.CLR_SILVER  = "\124cffc0c0c0"
AF.CLR_GRAY    = "\124cff808080"
AF.CLR_RED     = "\124cffff0000"
AF.CLR_LIME    = "\124cff00ff00"
AF.CLR_YELLOW  = "\124cffffff00"
AF.CLR_BLUE    = "\124cff0000ff"
AF.CLR_MAGENTA = "\124cffff00ff"
AF.CLR_CYAN    = "\124cff00ffff"
AF.CLR_WHITE   = "\124cffffffff"
AF.CLR_REGULAR = "\124r"

-- Non-standard colour codes
AF.CLR_MUDDY_RED     = "\124cffcd5554"
AF.CLR_ALGAE_GREEN   = "\124cff00c07f"
AF.CLR_HONEY         = "\124cffcdae1d"
AF.CLR_DEEP_ORANGE   = "\124cffbe4f0c"
AF.CLR_ORANGE_YELLOW = "\124cffff5a09"
AF.CLR_MISTY_GRAPE   = "\124cffaa80ff"

-- Some frequently used colours (usable debug msgs and chat output)
CLR_PREFIX   = AF.CLR_MISTY_GRAPE
CLR_REG      = AF.CLR_REGULAR
CLR_FUNCNAME = AF.CLR_ALGAE_GREEN
CLR_ARG      = AF.CLR_YELLOW
CLR_CMD      = AF.CLR_LIME
CLR_OPT      = AF.CLR_CYAN
CLR_OPT_OFF  = AF.CLR_MAGENTA
CLR_OPT_ON   = AF.CLR_LIME
CLR_VALUE    = AF.CLR_YELLOW



-- Class table
AF.Debugging = {

    -- Class data prototypes (i.e. "default" values for new objects)
    ----------------------------------------------------------------------------
    class   = "debugging",  -- Class identifier
    order   = 0,            -- Initialized by debugObj:setLevel() below
    level   = 0,            -- Initialized by debugObj:setLevel() below
}
AF.Debugging_mt = { __index = AF.Debugging }    -- Class metatable

-- Create a table of debugging level names that are indexed by their increasing
-- severity.  Then add another set of elements to the same table that are the
-- severities (in increasing order) referring to the level names.  This way the
-- same table can be used to look up names (to get severities) or severities (to
-- get names).
local LEVELLIST     = { TRACE, DEBUG, INFO, WARN, ERROR, ALWAYS }
local MAXLEVELS     = #LEVELLIST
for i = 1, MAXLEVELS do             -- Create an order to the debug levels
    LEVELLIST[LEVELLIST[i]] = i
end


--- Class private method "logMsg"
-- Outputs a message to debug (currently the chat-frame)
-- @param   level   Debugging
-- @return
local function logMsg( level, format, ... )
    local formatType = type( format )

--    DEFAULT_CHAT_FRAME:AddMessage( AF._tostring( debugstack( 0, 10, 10 ) ) )

    local prefix
    if( level ~= TRACE and level ~= DEBUG and level ~= INFO ) then
        prefix = strformat( "%s%s%s", CLR_PREFIX, addonName, CLR_REG )
    else
        prefix = strformat( "%s%s.lua%s", CLR_PREFIX, addonName, CLR_REG )
        local fileName = ""
        local funcName = ""
            if( strfind( debugstack( 3, 2, 0 ), "`.+'" ) ~= nil ) then

                local fileFilter = strformat( "^.-%s\\(.-):.-:", addonName )
                fileName = strmatch( debugstack( 3, 2, 0 ), fileFilter )
                funcName = strmatch( debugstack( 3, 2, 0 ), "^.-`(.-)'" )
            end
        if( funcName ~= "" ) then
            prefix = strformat( "%s%s%s\\%s%s()%s",
                                CLR_PREFIX, fileName, CLR_REG, CLR_FUNCNAME, funcName, CLR_REG )
        else
            prefix = strformat( "%s%s\\<%smain code%s>", prefix, CLR_REG, CLR_FUNCNAME, CLR_REG )
        end
    end


    if( formatType == "string" ) then
        if( select( "#", ... ) > 0 ) then
            local status, msg = pcall( strformat, format, ... )
            if( status ) then
                DEFAULT_CHAT_FRAME:AddMessage( strformat( "%s: %s", prefix, msg ) )
                return
            else
                DEFAULT_CHAT_FRAME:AddMessage( prefix .. ": Error formatting debug msg: " .. msg )
                return
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage( prefix .. ": " .. format )
            return
        end
    elseif( formatType == 'function' ) then
        -- format should be a callable function which returns the message to be output
        DEFAULT_CHAT_FRAME:AddMessage( prefix .. ": " .. format( ... ) )
        return
    end
    -- format is neither a string nor a function; Just call tostring() on it
    DEFAULT_CHAT_FRAME:AddMessage( prefix .. ": " .. AF._tostring( format) )
    return
end


--- Class public-methods "<various methods>"
-- Proxy functions for each debug level listed in LEVELLIST, all stored within a table
--local levelFunctions = {}
AF.Debugging.levelFunctions = {}
for i = 1, MAXLEVELS  do
    local level = LEVELLIST[i]
    AF.Debugging.levelFunctions[i] = function( self, ... )
        return logMsg( level, ... )
    end
end


--- Class private method "disableLevel"
--  Stub function that does nothing for disabled debug levels
local function disableLevel( )
end


--- Class constructor "new"
-- Creates a new debugging object and sets initial debugging state
-- @return          The newly constructed and initialized debugging object
function AF.Debugging:new( )

    local debugObj = {}                         -- Create object
    setmetatable( debugObj, AF.Debugging_mt )   -- Set the class to be the object's MT

    -- Per-object data initialization
    ----------------------------------------------------------------------------
    debugObj:setLevel( WARN )
    ----------------------------------------------------------------------------

    return debugObj

end


--- Class public-method "setLevel"
-- Sets the current debugging level
-- @param   level       = one of the debug levels listed in LEVELLIST
-- @return  true        = Debugging level changed successfully
-- @return  false       = Unable to change debug level
function AF.Debugging:setLevel( level )
    local order = LEVELLIST[strupper( level )]
    if( order == nil ) then
        debug:error( "Undefined debug level [%s]; ignoring.", AF._tostring( level ) )
        return false
    else
        if( self.level ~= level ) then
            self:log( DEBUG, "Changing debugging verbosity from %s to %s", self.level, strupper( level ) )
        end
        self.level = level
        self.order = order
        for i = 1, MAXLEVELS do
            local name = LEVELLIST[i]:lower( )
            if( i >= order ) then
                self[name] = AF.Debugging.levelFunctions[i]
            else
                self[name] = disableLevel
            end
        end
    end
    return true
end


--- Class public-method "getLevel"
-- Gets the current debugging level
-- @return              = one of the debug levels listed in LEVELLIST
function AF.Debugging:getLevel( )
    return self.level
end


--- Class public-method "log"
-- Provides a way to log the specified message at the specified severity
-- @param   level   Level of severity to log at
-- @return  ...     Msg component(s) to log
function AF.Debugging:log( level, ... )
    local order = LEVELLIST[level]
    if( order == nil ) then
        debug:error( "log() failed - Undefined debug level [%s].", AF._tostring( level ) )
    else
        if( order < self.order ) then
            return
        end
        return logMsg( level, ... )
    end
end


--- class public method 'loadDataFromGlobal'
-- Intended to be called whenever the player logs in or reloads their UI (which
-- is when SavedVariable data is restored from the filesystem and placed into
-- the addon's globals.  This method takes persistent debuggging state from the
-- global data and reinjects it into the current debugging object.  Does nothing
-- if no SavedVariable data is available (i.e. first-time the Addon has ever
-- been run).
-- @return  true    Successfully loaded global data into class data
-- @return  false   No SavedVariable data found - nothing done.
function AF.Debugging:loadDataFromGlobal( )
    debug:debug( "Loading persistent debug state from global SavedVariable" )
    if( AllFriendsData == nil ) then
        debug:debug( "No SavedVariable container table found - doing nothing." )
        return false
    end
    if( AllFriendsData.DebugLevel ) then
        self:setLevel( AllFriendsData.DebugLevel )
    end
    return true
end


--- class public method "saveDataToGlobal"
-- Intended to be called whenever the player logs out or reloads their UI.
-- This is when the addon's SavedVariable data is pulled from the addon's
-- globals and serialized to the filesystem. This method takes the class's
-- local data and places it into the addon's globals so it can be serialized.
function AF.Debugging:saveDataToGlobal( )
    debug:info( "Saving debug state to global SavedVariable" )

    AllFriendsData = AllFriendsData or {}
    AllFriendsData.DebugLevel = self:getLevel( )
    return
end


--- Class public method "chkType"
-- Asserts whether the specified class ID matches the ID of this class
-- @param   wantedType  Class ID to assert against this class's ID
-- @return  true        Returned of the specified class ID matches this class's ID
-- @return <error raised by the assert() if the IDs don't match>
function AF.Debugging:chkType( wantedType )
    return assert( self.class == wantedType )
end


-- vim: autoindent tabstop=4 shiftwidth=4 softtabstop=4 expandtab
