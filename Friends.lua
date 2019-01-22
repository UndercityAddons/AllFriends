--[[
     File Name           :     Friends.lua
     Created By          :     tubiakou
     Creation Date       :     [2019-01-07 01:28]
     Last Modified       :     [2019-01-22 01:30]
     Description         :     Friends class for the WoW addon AllFriends
--]]

--[[
This module of AllFriends implements a Friends class, responsible for all
functionality related to the Friends List.  This includes taking / restoring
snapshots, providing information, etc.
--]]


local addonName, AF = ...

--- Class metatable (stored within the Addon's globals)
AF.Friends_mt = {}
AF.Friends_mt.__index = AF.Friends_mt


--- Class constructor "new"
-- Creates a new Friends object and sets initial state.
-- @return          The newly constructed and initialized Friends object
function AF.Friends_mt:new( )
    local friendsObject = {}                    -- new object
    setmetatable( friendsObject, AF.Friends_mt )


    -- Per-object private Data
    ----------------------------------------------------------------------------
    self.tFriends           = {}        -- Tbl of snapshotted friends
    self.numFriends         = 0         -- Number of friends in snapshot
    self.Realm              = ""        -- Name of current realm
    self.tConnectedRealms   = {}        -- Tbl of connected or local realms
    self.snapshotRestored   = false     -- Has a snapshot-restore completed
    ----------------------------------------------------------------------------


    -- Per-object initial settings
    ----------------------------------------------------------------------------
    self.Realm              = string.lower( string.gsub( GetRealmName( ), "%s", "" ) )
    self.tConnectedRealms    = GetAutoCompleteRealms( self.ConnectedRealms ) -- All connected realms
    if( self.tConnectedRealms[1] == nil ) then                               -- or if unconnected, 
        table.insert( self.tConnectedRealms, self.Realm )                    -- then the local realm
    end

    return friendsObject
end


--- Class private method "isFriendInSnapshot"
-- Takes a specified friend and indicates whether or not they have been stashed
-- in the current snapshot.  Note that the specified name should already be
-- realm-qualified (e.g. "somefriend-moonguard".
-- @param   self        Object context
-- @param   friendName  Realm-qualified friend name to search for within snapshot
-- @return  true        Friend is currently stashed
-- @return  false       Friend not currently stashed
local function isFriendInSnapshot( self, friendName )
    if( friendName == "" ) then
        debug:warn( "Empty friend name - can't search within snapshot." )
        return false
    elseif( friendName == nil ) then
        debug:warn( "Nil friend name - can't search within snapshot." )
        return false
    elseif ( string.match( friendName, "-" ) == nil ) then
        debug:warn( "Friend %s not realm-qualified - can't search within snapshot.", friendName )
        return false
    end

    return self.tFriends[friendName] ~= nil
end


--- Class private method "stashFriendInSnapshot"
-- Takes a specified friend name and stashes them into the current snapshot.
-- This is idempotent, i.e. multiple stashes of the same friend will not
-- cause duplicates.  Note that the specified name should already be realm-
-- qualified, e.g. "somefriend-moonguard".
-- @param   self        Object context
-- @param   friendName  Realm-qualified friend name to stash into snapshot
-- @return  true        Friend stashed successfully
-- @return  false       Error stashing friend
local function stashFriendInSnapshot( self, friendName )
    if( friendName == "" ) then                             -- Don't stash if name is empty
        debug:warn( "Can't stash an empty friend name." )
        return false
    elseif( friendName == nil ) then                        -- Don't stash if name is nil
        debug:warn( "Can't stash a nil friend name." )
        return false
    elseif ( string.match( friendName, "-" ) == nil ) then  -- don't stash if not realm-qualified
        debug:warn( "Can't stash friend %s without a realm.", friendName )
        return false
    end

    if( isFriendInSnapshot( self, friendName ) ) then    -- Do nothing if friend already stashed
        debug:info( "Friend %s already stashed - doing nothing.", friendName )
    else
        self.tFriends[friendName] = "stashed"           -- Go ahead and stash friend
        self.numFriends = self.numFriends + 1
        debug:info( "Stashed %s info entry #%d.", friendName, self.numFriends )
    end

    return true
end


--- Class private method "stripRealmFromNameIfLocal"
-- Takes a player name and if it contains a realm-qualifier, strips the
-- qualifier from the name if the realm is your current local realm.  Does
-- nothing if no realm is in the name, or if the realm is not the current one.
-- @param   self        Object context
-- @param   playerName  Name of Player to operate on
-- @return              Player name w/o realm if realm is the current one
local function stripRealmFromNameIfLocal( self, playerName )

    -- Get position of name/realm delimiter in Player's name, if realm is present
    p = string.find( playerName, "-" )
    if( p ) then
        if( string.lower( string.sub( playerName, p+1 ) ) == self.Realm ) then
            debug:debug( "%s contains local realm - stripping.", playerName )
            return( string.sub( playerName, 1, p-1 ) )
        end
    end
    debug:debug( "%s contains no realm or realm is non-local - doing nothing.", playerName )
    return( playerName )
end


--- Class private method "isPlayerInFriendList"
-- Takes a specified player name and indicates whether or not they are present
-- in the current friends list. Player names without realm-qualifiers are local.
-- @param   self        Object context
-- @param   friendName  Name of friend to search within the current snapshot.
-- @return  true        Friend is in friends list
-- @return  false       Friend not in friends list
local function isPlayerInFriendList( self, playerName )
    if( playerName == "" ) then
        debug:warn( "Empty Player name - can't search within friends." )
        return false
    elseif( playerName == nil ) then
        debug:warn( "Nil player name - can't search within friends." )
        return false
    end

    -- Strip the realm-qualifier if it exists and refers to the local realm.
    playerName = stripRealmFromNameIfLocal( self, playerName )

    debug:debug( "Checking if %s is in your Friends List...", playerName )
    local friendReturn = C_FriendList.GetFriendInfo( playerName )
    if( friendReturn ~= nil ) then
        debug:debug( "%s found in friends-list.", playerName )
        return true
    else
        debug:debug( "%s not found in friends-list.", playerName )
        return false
    end
end


--- Class private method "removeFriendFromFriendList"
-- Removes the specified friend from the current friends list.  Nothing is
-- done if the friend is already not in the list.  Friend names can be in any
-- combination of upper/lower case, and may optionally be realm-qualified (
-- non realm-qualified names are considered on the local realm).
-- @param   self        Object context
-- @param   friendName  Name of friend to be removed from the friends list
-- @return  true        Friend removed from friends list, or already not present
-- @return  false       Problem with friend name (e.g. nil, empty)
local function removeFriendFromFriendList( self, friendName )
    if( friendName == nil or friendName == "" ) then
        debug:warn( "problem with friend name - not removing from friends-list." )
        return false
    end

    -- Strip local realm-qualifiers (friends list requires this), and then
    -- remove the friend from the friends list if present
    friendName = stripRealmFromNameIfLocal( self, friendName )
    if( isPlayerInFriendList( self, friendName ) ) then
        C_FriendList.RemoveFriend( friendName )
    end
    return true
end


--- Class private ethod "wipeSnapshot"
-- Wipes the current Friends snapshot clean.
-- in the current snapshot.
-- @param   self        Object context
local function wipeSnapshot( self )
    wipe( self.tFriends )
    self.numFriends = 0
    debug:debug( "Friend snapshot wiped." )
    return
end


--- Class private method "addRealmToName
-- Takes a player name and appends the current realm's name to it if a realm
-- is not already present.  If a realm is already present then validate that
-- it is either the current or a connected realm, and leave things as-is.
-- Fails if a realm is present but invalid (e.g. not local and not connected).
-- Also fails if the name is nil or empty.
-- @param   self        Object context
-- @param   playername  Name of player to operate on
-- @return              Name with the realm appended (or already present and connected)
-- @return  nil         Name is nil or empty
-- @return  nil         Realm is present but is neither local nor connected.
local function addRealmToName( self, playerName  )
    if( playerName == nil or playerName == "" ) then
        debug:warn( "playerName empty or nil - unable to add realm." )
        return nil
    end

    local playerNameWithRealm
    if ( string.match( playerName, "-" ) == nil ) then
        playerNameWithRealm = playerName .. "-" .. self.Realm
        debug:debug( "%s lacked realm - now  %s.", playerName, playerNameWithRealm )
    else
        playerNameWithRealm = playerName
        debug:debug( "%s already contains realm.", playerName )
    end
    return playerNameWithRealm
end


--- Class public-method "countFriendsInSnapshot"
-- Counts the current number of snapshot'ed friends
-- @return          The number of currently snapshot'ed friends
function AF.Friends_mt:countFriendsInSnapshot( )
    return self.numFriends
end


--- Class public method "countFriendList"
-- Returns the number of players in the current friend-list
-- @return          Number of players in the current friend-list
function AF.Friends_mt:countFriendList( )
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
function AF.Friends_mt:isFriendListAvailable( )

    local friendInfo = C_FriendList.GetFriendInfoByIndex( 1 )
    if( friendInfo == nil ) then
        debug:always( "GetFriendInfoByIndex() returned nil - server friend list unavailable." )
        return false
    elseif( friendInfo.name == nil ) then
        debug:always( "friendInfo.name is nil - server friend list unavailable." )
        return false
    elseif( friendInfo.name == "" ) then
        debug:always( "friendInfo.name is empty - server friend list unavailable." )
        return false
    else
        debug:always( "Server friend-list available." )
        return true
    end
end


--- Class public-method "takeSnapshot"
-- Takes a snapshot of the current friend's list and saves it in an object
function AF.Friends_mt:takeSnapshot( )
    local numServerFriends = C_FriendList.GetNumFriends( )

    if( self.snapshotRestored == false ) then
        debug:debug( "Skipping taking a snapshot - Addon initialization appears unfinished." )
    else
        debug:info( "Snapshotting %d server friends", numServerFriends )

        wipeSnapshot( self )

        local i, currentFriend, discard     -- For every current friend, stash into snapshot
        for i = 1, numServerFriends, 1 do
            local friendInfo = C_FriendList.GetFriendInfoByIndex( i )
            currentFriend = addRealmToName( self, friendInfo.name ); -- qualify name with current realm
            debug:debug( "friendInfo: %s", currentFriend )
            stashFriendInSnapshot( self, currentFriend )
        end
    end
    return
end


--- Class public-method "restoreSnapshot"
-- Syncs the in-game friends list to fully match the current snapshot:
--    1. Players in the snapshot that are missing from the friends list will be
--       added if they are on the current or any connected realm.
--    2. Players in the friends list but not in the snapshot will be removed.
-- NOTE: This will temporarily unregister the FRIENDLIST_UPDATE event in order
--       to prevent triggering new snapshots to be created whenever the friend-
--       list is altered.
function AF.Friends_mt:restoreSnapshot( )

    -- Go through snapshot and add all missing players within it into the friends list
    local numServerFriends = C_FriendList.GetNumFriends( )
    local currentFriend
    for currentFriend, v in pairs( self.tFriends ) do
        if( isPlayerInFriendList( self, currentFriend ) ) then
            debug:debug( "%s already in friend-list", currentFriend )
        else
            C_FriendList.AddFriend( currentFriend )
            debug:warn( "%s added to friend-list.", currentFriend )
        end
    end

    -- Go through friends list and remove all players that aren't also within the snapshot
    numServerFriends = C_FriendList.GetNumFriends( )
    local i
    for i = 1, numServerFriends, 1 do
        local friendInfo = C_FriendList.GetFriendInfoByIndex( i )
        currentFriend = addRealmToName( self, friendInfo.name ) -- qualify name with current realm
        if( isFriendInSnapshot( self, currentFriend )  ) then
            debug:debug( "%s already in both friends-list and snapshot.",currentFriend )
        else
            removeFriendFromFriendList( self, currentFriend )
            debug:info( "%s in friends-list but not snapshot - removed.", currentFriend )
        end
    end

    self.snapshotRestored = true    -- Flag that a snapshot restoration has completed
    return
end


--- class public method "dumpFriendSnapshot"
-- Dumps the current Friend snapshot to debug-output.
-- @return                  <none>
function AF.Friends_mt:dumpFriendSnapshot( )
    local i = 1, k, v
    debug:always( "%s: Dumping current friend snapshot:", addonName )
    for k, v in pairs( self.tFriends ) do
        debug:always( "%3d: %s", i, k )
        i = i + 1
    end
    debug:always( "Dump done." )
end


--- class public method 'loadDataFromGlobal'
-- Intended to be called whenever the player logs in or reloads their UI (which
-- is when SavedVariable data is restored from the filesystem and placed into
-- the addon's globals.  This method takes that global data, searches it for
-- info related to the current realm, and and places it back into the class's
-- local data, overwriting whatever may have previously existed (e.g.
-- newly-initialized defaults).  Does nothing to previous data if no
-- SavedVariable data is available (i.e. first-time the Addon has ever been run)
-- or if no data related to the current realm can be found.
-- @return  true    Successfully loaded global data into class data
-- @return  false   No SavedVariable data found - nothing done.
function AF.Friends_mt:loadDataFromGlobal( )
    debug:debug( "Loading snapshot from global SavedVariable" )

    -- Done if no SavedVariable data exists
    if( AllFriendsData == nil ) then
        debug:debug( "No SavedVariable container table found - doing nothing." )
        return false
    end

    -- Find the group of connected realms in SavedVariables that contains the
    -- current realm, and place related info into the class private data
    local gIndex = 1
    local rIndex = 1
    local groupArray = {}
    while( AllFriendsData.RealmGroups[gIndex] ~= nil ) do
        groupArray = AllFriendsData.RealmGroups[gIndex]
        rIndex = 1
        while( groupArray.realmList[rIndex] ~= nil ) do
            if( string.lower( groupArray.realmList[rIndex] ) == string.lower( self.Realm ) ) then
                if( groupArray.tFriends ~= nil and groupArray.numFriends ~= nil ) then
                    self.tFriends   = groupArray.tFriends
                    self.numFriends = groupArray.tFriends
                    debug:debug( "Snapshot loaded" )
                    return true
                else
                    debug:debug( "SavedVariable exists but missing mandatory data - doing nothing." )
                    return false
                end
            end
            rIndex = rIndex + 1
        end
        gIndex = gIndex + 1
    end
    debug:debug( "SavedVariable exists but no info on current realm [%s] found - doing nothing.", self.Realm )
    return false
end


--- class public method "saveDataToGlobal"
-- Intended to be called whenever the player logs out or reloads their UI.
-- This is when the addon's SavedVariable data is pulled from the addon's
-- globals and serialized to the filesystem. This method takes the class's
-- local data and places it into the addon's globals so it can be serialized.
function AF.Friends_mt:saveDataToGlobal( )
    debug:info( "Saving snapshot to global SavedVariable" )
    local gIndex = 1
    local rIndex = 1
    local groupArray = {}
    local curRealm = string.lower( self.Realm )

    AllFriendsData = AllFriendsData or {}

    if( AllFriendsData.RealmGroups ~= nil ) then
        -- Find an existing connected realm group containing the current realm if
        -- one already exists in SavedVariable.  If one is found then update it
        -- with current data.
        while( AllFriendsData.RealmGroups[gIndex] ~= nil ) do
            groupArray = AllFriendsData.RealmGroups[gIndex]
            rIndex = 1
            while( groupArray.realmList[rIndex] ~= nil ) do
                if( string.lower( groupArray.realmList[rIndex] ) == curRealm ) then
                    groupArray.realmList  = self.tConnectedRealms
                    groupArray.tFriends   = self.tFriends
                    groupArray.numFriends = self.numFriends
                    debug:info( "Snapshot saved into existing realm group #%d", rIndex )
                    return
                end
                rIndex = rIndex + 1
            end
            gIndex = gIndex + 1
        end
    else
        AllFriendsData.RealmGroups = {}
    end

    -- No existing realm group was found that contains the current realm.  AT
    -- this point gIndex points to an empty slot in AllFriendsData.RealmGroups
    -- so just go ahead and populate it with current data.
    AllFriendsData.RealmGroups[gIndex] = {}
    groupArray = AllFriendsData.RealmGroups[gIndex]
    groupArray.realmList  = self.tConnectedRealms
    groupArray.tFriends   = self.tFriends
    groupArray.numFriends = self.numFriends
    debug:info( "Snapshot saved into existing realm group #%d", rIndex )
    return
end


-- vim: autoindent tabstop=4 shiftwidth=4 softtabstop=4 expandtab
