--[[
     File Name           :     Friends.lua
     Created By          :     tubiakou
     Creation Date       :     [2019-01-07 01:28]
     Last Modified       :     [2019-02-11 10:55]
     Description         :     Friends class for the WoW addon AllFriends
--]]

--[[
This module of AllFriends implements a Friends class, responsible for all
functionality related to the Friends List.  This includes taking / restoring
snapshots, providing information, etc.
--]]


--local addonName, AF = ...
local addonName, AF_G = ...


-- Some local overloads to optimize performance (i.e. stop looking up these
-- standard functions every single time they are called, and instead refer to
-- them by local variables.
local string                = string
local strgsub               = string.gsub
local strlower              = string.lower


-- Class table
AF.Friends = {

    -- Class data prototypes (i.e. "default" values for new objects)
    ----------------------------------------------------------------------------
    class   =  "friends",   -- Class identifier
}
AF.Friends_mt = { __index = AF.Friends }    -- Class metatable


--- Class constructor "new"
-- Creates a new Friends object and sets initial state.
-- @return          The newly constructed and initialized Friends object
function AF.Friends:new( )

    local friendsObj = {}                       -- New object
    setmetatable( friendsObj, AF.Friends_mt )   -- Set up the object's metatable

    -- Per-object data initialization
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------

    return friendsObj
end


--- Class public method "getFriends"
-- Returns a table representing all the friends currently in the friend list.
-- The table is numerically indexed and takes the form:
--   tFriendList = {
--      playerObj1,     -- [1]
--      playerObj2,     -- [2]
--        ...
--      playerObjx      -- [x]
--   }
-- return   tFriendList  Table representing all friends currently in the friend list
function AF.Friends:getFriends( )
    local tFriendList = {}
    local numServerFriends = C_FriendList.GetNumFriends( )
    debug:debug( "Friend list contains %d friends", numServerFriends )
    local _, friendInfo, playerName, playerRealm
    for i = 1, numServerFriends do
        friendInfo = C_FriendList.GetFriendInfoByIndex( i )
        playerName = strlower( strgsub( friendInfo.name, "-.+$", "" ) )
        _, playerRealm = AF:getLocalizedRealm( friendInfo.name )
        debug:debug( "Retrieved %s-%s (%d of %d) from friend-list", playerName, playerRealm, i, numServerFriends )
        tFriendList[i] = AF.Player:new( playerName .. "-" .. playerRealm )
    end
    debug:debug( "Done retrieving friends - returning [%s]", AF._tostring( tFriendList ) )
    return tFriendList
end


--- Class public method "getFriendsAsNames"
-- Returns a table representing all the friends currently in the friend list.
-- The table takes the form:
--   tFriendList = {
--      [ "playername-playerrealm"]     = 1,
--      [ "anotherplayer-anotherrealm"] = 2,
--   }
-- return   tFriendList  Table representing all friends currently in the friend list
function AF.Friends:getFriendsAsNames( )
    local tFriendList = {}
    local numServerFriends = C_FriendList.GetNumFriends( )
    debug:debug( "Friend list contains %d friends", numServerFriends )
    local _, friendInfo, playerName, playerRealm
    for i = 1, numServerFriends do
        friendInfo = C_FriendList.GetFriendInfoByIndex( i )
        playerName = strlower( strgsub( friendInfo.name, "-.+$", "" ) )
        _, playerRealm = AF:getLocalizedRealm( friendInfo.name )
        debug:debug( "Retrieved %s-%s (%d of %d) from friend-list", playerName, playerRealm, i, numServerFriends )
        tFriendList[ playerName .. "-" .. playerRealm ] = i
    end
    debug:debug( "Done retrieving friends - returning [%s]", AF._tostring( tFriendList ) )
    return tFriendList
end


--- Class public method "countFriendList"
-- Returns the number of players in the current friend-list
-- @return          Number of players in the current friend-list
function AF.Friends:countFriendList( )
    local numFriends = C_FriendList.GetNumFriends( )
   debug:debug( "C_FriendsList.GetNumFriends() returned %d", numFriends )
    return numFriends
end


--- Class public method "isFriendListAvailable"
-- It appears that when starting the game, the Friend List may not yet be
-- available by the time events such as PLAYER_LOGIN and PLAYER_ENTERING_WORLD
-- fire.  This tests whether a friend-list is currently available.
--
-- NOTE: this method assumes that the friend-list contains at-least one player.
--
-- @return:  true    Friend-list is available.
-- @return:  false   Friend-list is unavailable.
function AF.Friends:isFriendListAvailable( )

    local friendInfo = C_FriendList.GetFriendInfoByIndex( 1 )
    if( friendInfo == nil ) then
        debug:debug( "GetFriendInfoByIndex() returned nil - server friend list unavailable." )
        return false
    elseif( friendInfo.name == nil ) then
        debug:debug( "friendInfo.name is nil - server friend list unavailable." )
        return false
    elseif( friendInfo.name == "" ) then
        debug:debug( "friendInfo.name is empty - server friend list unavailable." )
        return false
    else
        debug:debug( "Server friend-list available." )
        return true
    end
end


--- Class public method "findFriend"
-- Takes the specified player object and indicates whether or not they are
-- present in the current friend list.
-- @param   playerObj   Player object to be checked within friend list
-- @return  true        Specified player is in friend list
-- @return  false       Specified player not in friend list, or invalid object
function AF.Friends:findFriend( playerObj )

    -- Parameter validation
    if( not playerObj ) then
        debug:warn( "Invalid player object - can't search within friends." )
        return false
    end

    -- Identify player by name if on the local realm, or name-realm if on a
    -- connected realm, since this is what the WoW API current expects.
    local playerKey
    if( playerObj:isLocal( ) ) then
        playerKey = playerObj:getName( )
    else
        playerKey = playerObj:getKey( )
    end

    local friendReturn = C_FriendList.GetFriendInfo( playerKey )
    if( friendReturn ~= nil ) then
        debug:debug( "Player %s is in friend list.", playerKey )
        return true
    else
        debug:debug( "Player %s not in friend list.", playerKey )
        return false
    end
end


--- Class public method "addFriend"
-- Takes the specified player object and adds the player to the current friend
-- list.  The operation is idempotent - adding a friend that is already present
-- will return success.
-- @param   playerObj   Player object to be added to the friend list
-- @return  true        Added successfully (or was already present)
-- @return  false       Failure while adding friend
function AF.Friends:addFriend( playerObj )

    -- Parameter validation
    if( not playerObj ) then
        debug:warn( "Invalid player object - can't add to friend list." )
        return false
    end

    -- Qualify the player name with the player's realm if the realm is not
    -- local.  Otherwise use just the player's name.
    local playerKey
    if( playerObj:isLocal( ) ) then
        playerKey = playerObj:getName( )
    else
        playerKey = playerObj:getKey( )
    end

    if( not self:findFriend( playerObj ) ) then
        C_FriendList.AddFriend( playerKey )
        debug:info( "Added %s to friend list.", playerKey )
    end
    return true
end


--- Class public method "removeFriend"
-- Takes the specified player object and ensures the player is no longer in the
-- current friend list.  The operation is idempotent; Removing a non-existent
-- friend will return success.
-- @param   playerObj   Player object to be removed from the friend list
-- @return  true        Removed successfully (or was already not present)
-- @return  false       Failure while removing friend
function AF.Friends:removeFriend( playerObj )

    -- Parameter validation
    if( not playerObj ) then
        debug:warn( "Invalid player object - can't remove from friend list." )
        return false
    end

    -- Qualify the player name with the player's realm if the realm is not
    -- local.  Otherwise use just the player's name.
    local playerKey
    if( playerObj:isLocal( ) ) then
        playerKey = playerObj:getName( )
    else
        playerKey = playerObj:getKey( )
    end

    if( not self:findFriend( playerObj ) ) then
        debug:debug( "Player %s already absent from friend list.", playerKey )
    else
        C_FriendList.RemoveFriend( playerKey )
        debug:info( "Removed %s from friend list.", playerKey )
    end
    return true
end


--- Class public method "chkType"
-- Asserts whether the specified class ID matches the ID of this class
-- @param   wantedType  Class ID to assert against this class's ID
-- @return  true        Returned of the specified class ID matches this class's ID
-- @return <error raised by the assert() if the IDs don't match>
function AF.Friends:chkType( wantedType )
    return assert( self.class == wantedType )
end


-- vim: autoindent tabstop=4 shiftwidth=4 softtabstop=4 expandtab
