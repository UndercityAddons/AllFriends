--[[
     File Name           :     Friends.lua
     Created By          :     tubiakou
     Creation Date       :     [2019-01-07 01:28]
     Last Modified       :     [2019-01-15 10:21]
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
    self.tFriends           = {}
    self.numFriends         = 0
    self.Realm              = ""
    self.connectedRealms    = {}
    ----------------------------------------------------------------------------


    -- Per-object initial settings
    ----------------------------------------------------------------------------
    self.Realm              = string.lower( string.gsub( GetRealmName( ), "%s", "" ) )
    self.connectedRealms    = GetAutoCompleteRealms( self.ConnectedRealms ) -- This includes connected realms
    table.insert( self.connectedRealms, self.Realm )                        -- as well as the current realm

    return friendsObject
end


--- Class public-method "count"
-- Counts the current number of snapshot'ed friends
-- @return          The number of currently snapshot'ed friends
function AF.Friends_mt:count( )
    return self.numFriends
end


--- Class public-method "takeSnapshot"
-- Takes a snapshot of the current friend's list and saves it in an object
-- @return  true    Snapshot successfully taken/saved
-- @return  false   Error taking/saving snapshot
function AF.Friends_mt:takeSnapshot( )
    local numServerFriends = GetNumFriends( )
    debug:info( "Snapshotting %d server friends", numServerFriends )
    if( numServerFriends == 0 ) then
        return true
    end

    -- continue if one or more friends exist on the server
    self:wipeSnapshot( )
    local i, currentFriend, discard
    for i = 1, numServerFriends, 1 do
        local friendInfo = C_FriendList.GetFriendInfoByIndex( i )
        currentFriend = self:addRealmToName( friendInfo.name ); -- qualify name with current realm if not already qualified
        debug:debug( "friendInfo: %s", currentFriend )
        self:stashPlayerInSnapshot( currentFriend )
    end

    return true
end


--- Class public-method "restoreSnapshot"
-- Syncs the in-game friends list to fully match the current snapshot:
--    1. Players in the snapshot that are missing from the friends list will be
--       added if they are on the current or any connected realm.
--    2. Players in the friends list but not in the snapshot will be removed.
-- @return  true    Snapshot successfully taken/saved
-- @return  false   Error taking/saving snapshot
function AF.Friends_mt:restoreSnapshot( )
    local numServerFriends = GetNumFriends( )

    for currentFriend, v in pairs( self.tFriends ) do
        if( self:isPlayerInFriendsList( currentFriend ) ) then
            debug:info( "%s already in friend-list", currentFriend )
        else
            C_FriendList.AddFriend( currentFriend )
            debug:warn( "%s added to friend-list.", currentFriend )
        end
    end
end


--- Class public-method "stashPlayerInSnapshot"
-- Takes a specified player name and stashes them into the current snapshot.
-- This is idempotent, i.e. multiple stashes of the same player will not
-- cause duplicates.  Note that the specified name should already be realm-
-- qualified, e.g. "someplayer-moonguard".
-- @param   playerName  Realm-qualified player name to stash into snapshot
-- @return  true        Player stashed successfully
-- @return  false       Error stashing player
function AF.Friends_mt:stashPlayerInSnapshot( playerName )
    if( playerName == "" ) then                             -- Don't stash if name is empty
        debug:warn( "Can't stash an empty player name." )
        return false
    elseif( playerName == nil ) then                        -- Don't stash if name is nil
        debug:warn( "Can't stash a nil player name." )
        return false
    elseif ( string.match( playerName, "-" ) == nil ) then  -- don't stash if not realm-qualified
        debug:warn( "Can't stash player %s without a realm.", playerName )
        return false
    end

    if( self:isPlayerInSnapshot( playerName ) ) then    -- Do nothing if player already stashed
        debug:info( "Player %s already stashed - doing nothing.", playerName )
    else
        self.tFriends[playerName] = "stashed"           -- Go ahead and stash player
        self.numFriends = self.numFriends + 1
        debug:info( "Stashed %s info entry #%d.", playerName, self.numFriends )
    end

    return true
end


--- Class public-method "isPlayerInSnapshot"
-- Takes a specified friend and indicates whether or not they have been stashed
-- in the current snapshot.  Note that the specified name should already be
-- realm-qualified (e.g. "someplayer-moonguard".
-- @param   playerName  Realm-qualified player name to search for within snapshot
-- @return  true        Friend is currently stashed
-- @return  false       Friend not currently stashed
function AF.Friends_mt:isPlayerInSnapshot( playerName )
    if( playerName == "" ) then
        debug:warn( "Empty Player name - can't search within snapshot." )
        return false
    elseif( playerName == nil ) then
        debug:warn( "Nil player name - can't search within snapshot." )
        return false
    elseif ( string.match( playerName, "-" ) == nil ) then
        debug:warn( "Player %s not realm-qualified - can't search within snapshot.", playerName )
        return false
    end

    return self.tFriends[playerName] ~= nil
end


--- Class public-method "isPlayerInFriendsList"
-- Takes a specified player name and indicates whether or not they are present
-- in the current friends list. Player names without realm-qualifiers are local.
-- @param   friendName  Name of friend to search within the current snapshot.
-- @return  true        Friend is currently stashed
-- @return  false       Friend not currently stashed
function AF.Friends_mt:isPlayerInFriendsList( playerName )
    if( playerName == "" ) then
        debug:warn( "Empty Player name - can't search within friends." )
        return false
    elseif( playerName == nil ) then
        debug:warn( "Nil player name - can't search within friends." )
        return false
    end

    -- Strip the realm-qualifier if it exists and refers to the local realm.
    if( string.match( playerName, "-" ) ) then
        playerName = self:stripRealmFromNameIfLocal( playerName )
    end

    debug:debug( "Checking if %s is in your Friends List...", playerName )
    local friendReturn = C_FriendList.GetFriendInfo( playerName );
    if( friendReturn ~= nil ) then
        debug:debug( "%s found in friends-list.", playerName )
        return true
    else
        debug:debug( "%s not found in friends-list.", playerName )
        return false
    end
end


--- Class public-method "wipeSnapshot"
-- Wipes the current Friends snapshot clean.
-- in the current snapshot.
-- @return  true    always
function AF.Friends_mt:wipeSnapshot( )
    wipe( self.tFriends )
    self.numFriends = 0
    debug:debug( "Friend snapshot wiped." )
    return true
end


--- Class method "addRealmToName
-- Takes a Friend name and appends the current realm's name to it if a realm
-- is not already present.  If a realm is already present then validate that
-- it is either the current or a connected realm, and leave things as-is.
-- Fails if a realm is present but invalid (e.g. not local and not connected).
-- Also fails if the name is nil or empty.
-- @param   friendName  Name of friend to operate on
-- @return              Name with the realm appended (or already present and connected)
-- @return  nil         Name is nil or empty
-- @return  nil         Realm is present but is neither local nor connected.
function AF.Friends_mt:addRealmToName( friendName )
    if( friendName == nil or friendName == "" ) then
        debug:warn( "Friend empty or nil - unable to add realm." )
        return nil
    end

    local friendNameWithRealm
    if ( string.match( friendName, "-" ) == nil ) then
        friendNameWithRealm = friendName .. "-" .. self.Realm
        debug:debug( "%s lacked realm - now  %s.", friendName, friendNameWithRealm )
    else
        friendNameWithRealm = friendName
        debug:debug( "%s already contains realm.", friendName )
    end
    return friendNameWithRealm
end


--- Class Method "stripRealmFromNameIfLocal"
-- Takes a player name and if it contains a realm-qualifier, strips the
-- qualifier from the name if the realm is your current local realm.  Does
-- nothing if no realm is in the name, or if the realm is not the current one.
-- @param   playerName  Name of Player to operate on
-- @return              Player name w/o realm if realm is the current one
function AF.Friends_mt:stripRealmFromNameIfLocal( playerName )

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


--- Class method "isFriendRealmConnected"
-- Takes a friend name and checks the if realm it refers to is connected (or
-- not.  The current realm is considered to be connected.  Names not containing
-- a realm are treated as part of the current realm (i.e. connected).
-- @param  friendName   Name of the friend to check
-- @return true         Name contains connected, current, or no realm
-- @return false        Name contains a realm that is neither connected nor current
-- @return nil          Specified name is nil or empty
function AF.Friends_mt:isFriendRealmConnected( friendName )
    if( friendName == nil or friendName == "" ) then
        debug:warn( "Friend empty or nil - unable to check if connected." )
        return nil
    end

    if( string.match( friendName, "-" ) == nil ) then
        debug:info( "friend %s lacks realm - considered local and connected.", friendName )
        return true
    end

    local p = string.find( friendName, "-" )                            -- find position of name/realm delimiter
    local friendRealm = string.lower( string.sub( friendName, p+1 ) ) -- Extact everything after delimiter as the realm

    if( friendRealm == self.Realm ) then
        debug:info( "Friend %s's realm equals the current one - considered connected.", friendRealm )
        return true
    end

    local i = 1
    while( self.connectedRealms[i] ~= nil ) do
        if( string.lower( self.connectedRealms[i] ) == friendRealm  ) then
            debug:info( "Friend %s's realm is connected.", friendRealm )
            return true
        end
        i = i + 1
    end

    debug:info( "Friend %s's realm is not connected.", friendRealm )
    return false
end


--- class method "dumpFriendSnapshot"
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


--- class method 'loadDataFromGlobal'
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
    debug:info( "Loading snapshot from global SavedVariable" )

    -- Done if no SavedVariable data exists
    if( AllFriendsData == nil ) then
        debug:info( "No SavedVariable container table found - doing nothing." )
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
            if( groupArray.realmList[rIndex] == self.Realm ) then
                if( groupArray.tFriends ~= nil and groupArray.numFriends ~= nil ) then
                    self.tFriends   = groupArray.tFriends
                    self.numFriends = groupArray.tFriends
                    debug:info( "Snapshot loaded from realm group #%d", rIndex )
                    return true
                else
                    debug:info( "SavedVariable exists but missing mandatory data - doing nothing." )
                    return false
                end
            end
            rIndex = rIndex + 1
        end
        gIndex = gIndex + 1
    end
    debug:info( "SavedVariable exists but no info on current realm found - doing nothing." )
    return false
end


--- class method "saveDataToGlobal"
-- Intended to be called whenever the player logs out or reloads their UI.
-- This is when the addon's SavedVariable data is pulled from the addon's
-- globals and serialized to the filesystem. This method takes the class's
-- local data and places it into the addon's globals so it can be serialized.
-- @return  true    <always>
function AF.Friends_mt:saveDataToGlobal( )
    debug:info( "Saving snapshot to global SavedVariable" )
    local gIndex = 1
    local rIndex = 1
    local groupArray = {}

    AllFriendsData = AllFriendsData or {}

    if( AllFriendsData.RealmGroups ~= nil ) then
        -- Find an existing connected realm group containing the current realm if
        -- one already exists in SavedVariable.  If one is found then update it
        -- with current data.
        while( AllFriendsData.RealmGroups[gIndex] ~= nil ) do
            groupArray = AllFriendsData.RealmGroups[gIndex]
            rIndex = 1
            while( groupArray.realmList[rIndex] ~= nil ) do
                if( groupArray.realmList[rIndex] == self.Realm ) then
                    groupArray.realmList  = self.connectedRealms
                    groupArray.tFriends   = self.tFriends
                    groupArray.numFriends = self.numFriends
                    debug:info( "Snapshot saved into existing realm group #%d", rIndex )
                    return true
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
    groupArray.realmList  = self.connectedRealms
    groupArray.tFriends   = self.tFriends
    groupArray.numFriends = self.numFriends
    debug:info( "Snapshot saved into existing realm group #%d", rIndex )
    return true
end


-- vim: autoindent tabstop=4 shiftwidth=4 softtabstop=4 expandtab
