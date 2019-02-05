--[[
     File Name           :     Debugging.lua
     Created By          :     tubiakou
     Creation Date       :     [2019-01-07 01:28]
     Last Modified       :     [2019-02-03 19:16]
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
local addonName, AF = ...


-- Some local overloads to optimize performance (i.e. stop looking up these
-- standard functions every single time they are called, and instead refer to
-- them by local variables.
local select        = select
local string        = string
local strformat     = string.format
local strupper      = string.upper
local tostring      = AF._tostring
local type          = type


-- Debugging levels (increasing severity)
DEBUG     = "DEBUG"   -- Highly detailed/verbose information
INFO      = "INFO"    -- Informative information
WARN      = "WARN"    -- Warnings about unexpected conditions/results
ERROR     = "ERROR"   -- Errors that will break things
ALWAYS    = "ALWAYS"  -- Output that should be shown unconditionally


-- COLOR CODES (can be used within debug messages)
AF.DBG_BLACK   = "\124cff000000"
AF.DBG_MAROON  = "\124cff800000"
AF.DBG_GREEN   = "\124cff008000"
AF.DBG_OLIVE   = "\124cff808000"
AF.DBG_NAVY    = "\124cff000080"
AF.DBG_PURPLE  = "\124cff800080"
AF.DBG_TEAL    = "\124cff008080"
AF.DBG_SILVER  = "\124cffc0c0c0"
AF.DBG_GRAY    = "\124cff808080"
AF.DBG_RED     = "\124cffff0000"
AF.DBG_LIME    = "\124cff00ff00"
AF.DBG_YELLOW  = "\124cffffff00"
AF.DBG_BLUE    = "\124cff0000ff"
AF.DBG_MAGENTA = "\124cffff00ff"
AF.DBG_CYAN    = "\124cff00ffff"
AF.DBG_WHITE   = "\124cffffffff"
AF.DBG_REGULAR = "\124r"


-- Create a table of debugging level names that are indexed by their increasing
-- severity.  Then add another set of elements to the same table that are the
-- severities (in increasing order) referring to the level names.  This way the
-- same table can be used to look up names (to get severities) or severities (to
-- get names).
local LEVELLIST     = { DEBUG, INFO, WARN, ERROR, ALWAYS }
local MAXLEVELS     = #LEVELLIST
for i = 1, MAXLEVELS do             -- Create an order to the debug levels
    LEVELLIST[LEVELLIST[i]] = i
end


--- Tables for Class and metatable (stored within the addon's globals)
AF.Debugging            = {}            -- Class
AF.Debugging_mt         = {}            -- Metatable
AF.Debugging_mt.__index = AF.Debugging  -- Look in the class for undefined methods


--- Class private method "logMsg"
-- Outputs a message to debug (currently the chat-frame)
-- @param   level   Debugging
-- @return
local function logMsg( level, format, ... )
    local formatType = type( format )

    local colourizedAddonName = strformat( "\124cffe900ff%s\124r", addonName )

    if( formatType == "string" ) then
        if( select( "#", ... ) > 0 ) then
            local status, msg = pcall( strformat, format, ... )
            if( status ) then
                DEFAULT_CHAT_FRAME:AddMessage( strformat( "%s: %s", colourizedAddonName, msg ) )
                return
            else
                DEFAULT_CHAT_FRAME:AddMessage( colourizedAddonName  .. ": Error formatting debug msg: " .. msg )
                return
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage( colourizedAddonName .. ": " .. format )
            return
        end
    elseif( formatType == 'function' ) then
        -- format should be a callable function which returns the message to be output
        DEFAULT_CHAT_FRAME:AddMessage( colourizedAddonName .. ": " .. format( ... ) )
        return
    end
    -- format is neither a string nor a function; Just call tostring() on it
    DEFAULT_CHAT_FRAME:AddMessage( colourizedAddonName .. ": " .. tostring( format) )
    return
end


--- Class private-methods "<various methods>"
-- Proxy functions for each debug level listed in LEVELLIST, all stored within a table
local levelFunctions = {}
for i = 1, MAXLEVELS  do
    local level = LEVELLIST[i]
    levelFunctions[i] = function( self, ... )
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
    local debugObj = {}                         -- New object
    setmetatable( debugObj, AF.Debugging_mt )   -- Set up the object's metatable

    -- Per-object private Data
    ----------------------------------------------------------------------------
    debugObj.order    = 0    -- gets initialized by call to self:setLevel() below
    debugObj.level    = 0    -- gets initialized by call to self:setLevel() below
    ----------------------------------------------------------------------------

    -- Per-object initial settings
    ----------------------------------------------------------------------------
    debugObj:setLevel( WARN )
    ----------------------------------------------------------------------------

    return debugObj     -- Pass object's reference back to caller
end


--- Class public-method "setLevel"
-- Sets the current debugging level
-- @param   level       = one of the debug levels listed in LEVELLIST
-- @return  true        = Debugging level changed successfully
-- @return  false       = Unable to change debug level
function AF.Debugging:setLevel( level )
    local order = LEVELLIST[strupper( level )]
    if( order == nil ) then
        debug:error( "Undefined debug level [%s]; ignoring.", tostring( level ) )
        return false
    else
        if( self.level ~= level ) then
            self:log( DEBUG, "Changing debugging verbosity from %s to %s", self.level, level )
        end
        self.level = level
        self.order = order
        for i = 1, MAXLEVELS do
            local name = LEVELLIST[i]:lower( )
            if( i >= order ) then
                self[name] = levelFunctions[i]
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
        debug:error( "log() failed - Undefined debug level [%s].", tostring( level ) )
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
    self:setLevel( AllFriendsData.DebugLevel )
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


-- vim: autoindent tabstop=4 shiftwidth=4 softtabstop=4 expandtab
