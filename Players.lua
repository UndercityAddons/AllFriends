--[[
     File Name           :     Players.lua
     Created By          :     tubiakou
     Creation Date       :     [2019-01-07 01:28]
     Last Modified       :     [2019-02-11 13:51]
     Description         :     PLayer class for the WoW addon AllFriends

This module of AllFriends implements a Player class, representing a Player
and all the things you can do with/to them.
--]]


-- WoW API treats LUA modules as "functions", and passes them two arguments:
--  1. The name of the addon, and
--  2. A table containing the globals for that addon.
-- Using these lets all modules within an addon share the addon's global information.
--local addonName, AF = ...
local addonName, AF_G = ...


-- Some local overloads to optimize performance (i.e. stop looking up these
-- standard functions every single time they are called, and instead refer to
-- them by local variables.
local string            = string
local strlower          = string.lower
local strsplit          = strsplit
local type              = type

--- Class table
AF.Player = {

    -- Class data prototypes (i.e. "default" values for new objects
    ----------------------------------------------------------------------------
    class       = "player", -- Class identifier
    isLocalFlg  = true,     -- Is player on the local (i.e. current) realm
    name        = "",       -- Player's name (lowercase)
    realm       = "",       -- Player's realm (lowercase)
}
AF.Player_mt            = {}
AF.Player_mt.__index    = AF.Player


--- Class constructor "new"
-- Creates a new PLayer object, setting initial state for the player as follows:
--  1. If a name is provided then the object will be initialized with that
--     player name.
--  2. If a realm is also provided (anything after 1st '-' character), then that
--     realm will be set.  Otherwise the name of the local realm will be set.
--  3. If a realm is provided but not a name, then nothing will be set.
-- @param   name    (Optional) Player's name, possibly with realm
-- @return          The newly constructed and initialized Player object
-- @return  nil     Error, e.g. realm provided but not local and not connected
function AF.Player:new( name )
    local playerObj = {}                        -- New object
    setmetatable( playerObj, AF.Player_mt )     -- Set up the object's metatable

    -- Per-object data initialization
    ----------------------------------------------------------------------------
    if( name ~= nil and name ~= "" ) then
        playerObj.name, playerObj.realm = strsplit( "-", name, 2 )
        if( playerObj.name == "" ) then  -- Realm provide but missing name - don't do anything
            debug:debug( "Realm %s provided but missing name - not creating new player object.", playerObj.realm )
            return nil
        else
            playerObj.name = strlower( playerObj.name )
            playerObj.realm = strlower( playerObj.realm )
            playerObj.isLocalFlg, playerObj.realm = AF:getLocalizedRealm( playerObj.name .. "-" .. playerObj.realm )
            if( playerObj.realm == "unknown" ) then
                debug:debug( "No new player object created - specified realm not connected." )
                return nil
            end
        end
    end
    ----------------------------------------------------------------------------

    debug:debug( "New player object:  %s", AF._tostring( playerObj ) )
    return playerObj
end


--- class public method "getName"
-- Returns a player object's name
-- @return          The player object's name (all lowercase)
function AF.Player:getName( )
    return self.name
end


--- class public method "getRealm"
-- Returns a player object's realm
-- @return          The player object's realm (all lowercase, no spaces)
function AF.Player:getRealm( )
    return self.realm
end


--- class public method "getKey"
-- Returns a player object's key (i.e. player name and realm separated by a "-".
-- @return  playerKey   Player key in the form "playername-playerrealm"
function AF.Player:getKey()
    return self.name .. "-" .. self.realm
end


--- class public method "isLocal"
-- Indiates whether the player object is on the local (i.e. current) realm
-- @return  true        Player object is on the local realm
-- @return  false       Player object not on the local realm
function AF.Player:isLocal( )
    return self.isLocalFlg
end


--- Class public method "chkType"
-- Asserts whether the specified class ID matches the ID of this class
-- @param   wantedType  Class ID to assert against this class's ID
-- @return  true        Returned of the specified class ID matches this class's ID
-- @return <error raised by the assert() if the IDs don't match>
function AF.Player:chkType( wantedType )
    return assert( self.class == wantedType )
end


-- vim: autoindent tabstop=4 shiftwidth=4 softtabstop=4 expandtab
