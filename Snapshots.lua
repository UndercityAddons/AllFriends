--[[
     File Name           :     Snapshots.lua
     Created By          :     tubiakou
     Creation Date       :     [2019-01-07 01:28]
     Last Modified       :     [2019-02-11 11:55]
     Description         :     Snapshots class for the WoW addon AllFriends

This module of AllFriends implements a Snapshot class, responsible for all
functionality related to Snapshots (e.g. of the Friend List, the Ignore list,
etc.). These snapshots are what will be serialized and deserialized to/from
SavedVariables storage whenever the player logs off and back on.
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
local next                  = next
local string                = string
local strfind               = string.find
local strlower              = string.lower
local strupper              = string.upper
local table                 = table
local tblinsert             = table.insert
local pairs                 = pairs
local ipairs                = ipairs


--- Class table
AF.Snapshot = {

    -- Class data prototypes (i.e. "default" values for new objects)
    ----------------------------------------------------------------------------
    class             = "snapshot", -- Class identifier
    tFriends          = {},         -- Table of snapshotted friends
    numFriends        = 0,          -- Number of friends in snapshot
    tMasterFriends    = {},         -- Realm Group's master friends snapshot
    numMasterFriends  = 0,          -- Realm Group's master snapshot count
    Realm             = "",         -- Name of current realm
    tConnectedRealms  = {},         -- Tbl of connected or local realms
    snapshotRestored  = false,      -- Has a snapshot-restore completed
    doDeletions       = false,      -- Should the addon delete stale friends
    fullSync          = false,      -- Ignore doDeletions (turn TRUE for all currently connected realms)
}
AF.Snapshot_mt          = {}            -- Metatable
AF.Snapshot_mt.__index  = AF.Snapshot   -- Look in the class for undefined methods


--- Class private method "AF.wipeFriendsFromSnapshot"
-- Wipes all friends from a snapshot.  The snapshot can be the player's specific
-- snapshot, or the master snapshot for the realm-group.
-- @param   self        Object context
-- @param   whichSnap   "player" or "master" - which snapshot to work on
-- @return  true        Wipe successful
-- @return  nil         Error during wipe
function AF.wipeFriendsFromSnapshot( self, whichSnap )
    debug:trace( "entered" )
    if( whichSnap == nil ) then
        debug:warn( "No target snapshot specified - can't wipe the snapshot." )
        debug:trace( "exited" )
        return nil
    else
        whichSnap = strlower( whichSnap )
        if( whichSnap ~= "player" and whichSnap ~= "master" ) then
            debug:warn( "Target snapshot not player or master - can't wipe the snapshot." )
            debug:trace( "exited" )
            return nil
        end
    end
    if( whichSnap == "player" ) then
        wipe( self.tFriends )
        self.numFriends = 0
    else
        wipe( self.tMasterFriends )
        self.numMasterFriends = 0
    end
    return true
end


--- Class private method "AF.findFriendInSnapshot"
-- Takes a specified player object and indicates whether or not they are
-- present as a friend in the snapshot.
-- @param   self        Object context
-- @param   playerObj   Player object to be searched for as a friend
-- @param   whichSnap   "player" or "master" - which snapshot to work on
-- @return  "present"   Player present in snapshot as a friend
-- @return  "missing"   Player not in snapshot as a friend
-- @return  nil         Error (e.g. invalid player object)
function AF.findFriendInSnapshot( self, playerObj, whichSnap )
    debug:trace( "entered" )

    -- Parameter validation
    if( not pcall( function( ) return playerObj:chkType( AF.Player.class ) end ) ) then
        debug:warn( "Invalid player object - can't search within snapshot." )
        debug:trace( "exited" )
        return nil
    elseif( playerObj:getName( ) == "" or playerObj:getRealm( ) == "" ) then
        debug:warn( "Missing player name and/or realm - can't search within snapshot." )
        debug:trace( "exited" )
        return nil
    elseif( whichSnap == nil ) then
        debug:warn( "No target snapshot specified - can't search friend in snapshot." )
        debug:trace( "exited" )
        return nil
    else
        whichSnap = strlower( whichSnap )
        if( whichSnap ~= "player" and whichSnap ~= "master" ) then
            debug:warn( "Target snapshot not player or master - can't search friend in snapshot." )
            debug:trace( "exited" )
            return nil
        end
    end

    local playerKey = playerObj:getKey( )

    local target
    if( whichSnap == "player" ) then
        target = self.tFriends
    else
        target = self.tMasterFriends
    end

    if( target[playerKey] ~= nil ) then
        debug:info( "Friend %s present in %s snapshot.", playerKey, whichSnap )
        debug:trace( "exited" )
        return "present"
    else
        debug:info( "Friend %s not present in %s snapshot.", playerKey, whichSnap )
        debug:trace( "exited" )
        return "missing"
    end
end


--- Class private method "AF.addFriendToSnapshot"
-- Takes a specified player object and stashes them into a snapshot as a
-- friend.  The snapshot may either be the current player's personal snapshot,
-- or the master snapshot for the realm-group.  This is idempotent - multiple
-- attempts on the same player, or adding a player that is already present
-- will not cause duplicates.
-- @param   self        Object context
-- @param   playerObj   Player object to be stashed as a friend
-- @param   whichSnap   "player" or "master" - which snapshot to work on
-- @return  true        Player stashed successfully
-- @return  nil         Error stashing player
function AF.addFriendToSnapshot( self, playerObj, whichSnap )
    debug:trace( "entered" )

    -- Parameter validation
    if( not pcall( function( ) return playerObj:chkType( AF.Player.class ) end ) ) then
        debug:warn( "Invalid player object - can't add to snapshot." )
        debug:trace( "exited" )
        return nil
    elseif( playerObj:getName( ) == "" or playerObj:getRealm( ) == "" ) then
        debug:warn( "Missing player name and/or realm - can't add to snapshot." )
        debug:trace( "exited" )
        return nil
    elseif( whichSnap == nil ) then
        debug:warn( "No target snapshot specified - can't add to snapshot." )
        return nil
    else
        whichSnap = strlower( whichSnap )
        if( whichSnap ~= "player" and whichSnap ~= "master" ) then
            debug:warn( "Target snapshot not player or master - can't add to snapshot." )
            return nil
        end
    end

    if( AF.findFriendInSnapshot( self, playerObj, whichSnap ) == "present" ) then
        debug:info( "Friend %s already in snapshot.", playerObj:getKey( ) )
    else
        if( whichSnap == "player" ) then
            self.tFriends[ playerObj:getKey( ) ] = playerObj
            self.numFriends = self.numFriends + 1
            debug:info( "Stashed %s into player snapshot (friend #%d)", playerObj:getKey( ), self.numFriends )
        else
            self.tMasterFriends[ playerObj:getKey( ) ] = playerObj
            self.numMasterFriends = self.numMasterFriends + 1
            debug:info( "Stashed %s into master snapshot (friend #%d)", playerObj:getKey( ), self.numMasterFriends )
        end
    end
    debug:trace( "exited" )
    return true
end


--- Class private method "removeFriendFromSnapshot"
-- Takes a specified player object and removes them from a snapshot as a
-- friend.  The snapshot may either be the current player's personal snapshot,
-- or the master snapshot for the realm-group.  This is idempotent - multiple
-- attempts on the same player, or removing a player that is already absent
-- will not fail.
-- @param   self        Object context
-- @param   playerObj   Player object to be removed
-- @param   whichSnap   "player" or "master" - which snapshot to work on
-- @return  true        Player removed successfully
-- @return  nil         Error removing player
function AF.removeFriendFromSnapshot( self, playerObj, whichSnap )

    -- Parameter Validation
    if( not pcall( function( ) return playerObj:chkType( AF.Player.class ) end ) ) then
        debug:warn( "Invalid player object - can't remove from snapshot." )
        debug:trace( "exited" )
        return nil
    elseif( playerObj:getName( ) == "" or playerObj:getRealm( ) == "" ) then
        debug:warn( "Missing player name and/or realm - can't remove from snapshot." )
        debug:trace( "exited" )
        return nil
    elseif( whichSnap == nil ) then
        debug:warn( "No target snapshot specified - can't remove from snapshot." )
        return nil
    else
        whichSnap = strlower( whichSnap )
        if( whichSnap ~= "player" and whichSnap ~= "master" ) then
            debug:warn( "Invalid snapshot - can't remove from snapshot." )
            return nil
        end
    end

    if( AF.findFriendInSnapshot( self, playerObj, whichSnap ) ~= "present" ) then
        debug:info( "Friend %s already not in snapshot.", playerObj:getKey( ) )
    else
        if( whichSnap == "player" ) then
            self.tFriends[ playerObj:getKey( ) ] = nil
            self.numFriends = self.numFriends - 1
        else
            self.tMasterFriends[ playerObj:getKey( ) ] = nil
            self.numMasterFriends = self.numMasterFriends - 1
        end
        debug:info( "%s removed from %s snapshot", playerObj:getKey( ), whichSnap )
    end
    return true
end


--- Class private method "findGlobals"
-- Locates all data related to the specified player in the Addon's Globals that
-- were deserialized from the Addon's SavedVariables.  Returns references to
-- that data.  If any of the data locations are not present (e.g. the addons has
-- not run previously for this player), then empty placeholders will be created
-- and returned.  The references that are returned are:
--      - Table containing DoDeletions settings for all players
--      - The realm-group the player belongs to
--      - The realm-group's master snapshot
--
-- If an error occurs (e.g. invalid player key) then all returns will be nil.
--
-- @param   self            Object context
-- @param   playerKey       Player key (i.e. "name-realm")
-- @return  tDoDeletions    Table containing doDeletions flags for each player
-- @return  tMyRealmGroup   Table containing the player's realm-group
-- @return  tMasterSnapshot Table containing the realm-group's master snapshot
function AF.findGlobals( self, playerKey )

    -- Parameter Validation
    if( playerKey == nil or playerKey == "" or strfind( playerKey, "-" ) == nil ) then
        debug:warn( "Invalid player key - cannot find Player's globals." )
        return nil, nil, nil
    end

    local tMyRealmGroup = {}
    local tDoDeletions
    local tMasterSnapshot

    -- If the addon hasn't run before the the addon's SavedVariables file will
    -- not exist.  The corresponding global data structure will also not exist.
    -- Initialize everything non-specific to individual realm-groups or players
    -- that might be missing before we proceed.  (Data for initial realm-groups
    -- and players are initialized below, when doing per-group and per-player
    -- processing.)
    AllFriendsData = AllFriendsData or {}
    AllFriendsData.RealmGroups = AllFriendsData.RealmGroups or {}
    AllFriendsData.doDeletions = AllFriendsData.doDeletions or {}

    -- Locate the doDeletions table
    ---------------------------------------------------------------------------
    tDoDeletions = AllFriendsData.doDeletions
    ---------------------------------------------------------------------------

    -- Iterate all the realm-groups
    ---------------------------------------------------------------------------
    local gIndex = 1
    while( AllFriendsData.RealmGroups[gIndex] ~= nil ) do
        debug:debug( "gIndex loop at [%d]", gIndex )
        local curRealmGroup = AllFriendsData.RealmGroups[gIndex]
        curRealmGroup.realmList = curRealmGroup.realmList or {}

        -- Check if the current realm-group includes the current player's realm
        local rIndex = 1
        while( curRealmGroup.realmList[rIndex] ~= nil ) do
            debug:debug( "rIndex loop at [%d]", rIndex )
            debug:debug( "Testing realms %s against %s", curRealmGroup.realmList[rIndex], self.Realm )
            if( curRealmGroup.realmList[rIndex] == self.Realm ) then

                -- Found our realm-group.  Note its location and stop checking
                -- the current realm-group.
                debug:debug( "Found our realm group." )
                tMyRealmGroup = curRealmGroup
                break
            end
            rIndex = rIndex + 1
        end

        -- If we found our realm-group then stop iterating the remainder
        if( next( tMyRealmGroup ) ~= nil ) then
            break
        end
        gIndex = gIndex + 1
    end

    -- If we didn't find our realm-group then then create one.  gIndex now
    -- points to the first unused element within the table.
    if( next( tMyRealmGroup ) == nil ) then
        debug:debug( "No matching realm-group - Adding new one at gIndex %d", gIndex )
        AllFriendsData.RealmGroups[gIndex] = {}
        tMyRealmGroup = AllFriendsData.RealmGroups[gIndex]
    end
    ---------------------------------------------------------------------------

    -- Locate the realm-group's master snapshot, or create a new one
    ---------------------------------------------------------------------------
    tMyRealmGroup.tMasterSnapshot       = tMyRealmGroup.tMasterSnapshot or {}
    tMasterSnapshot                     = tMyRealmGroup.tMasterSnapshot
    ---------------------------------------------------------------------------

    return tDoDeletions, tMyRealmGroup, tMasterSnapshot
end


--- Class private method "diffSnapAndFriendList"
-- Takes a friendListObj and compares it against the specified snapshot
-- (player's or master) to see what has changed.  A diff-table is returned
-- listing the changes.  The table takes the following form:
--    tblDiffs = {
--      [playername-playerrealm"] = "added",   -- added to friend-list
--      ["anotherplayer-realm"]   = "removed", -- removed from friend-list
--    }
-- An empty diff- table indicates that there were no changes.
-- @param   self            Object context
-- @param   friendListObj   Friend List Object to compare.
-- @param   whichSnap       Which snapshot to compare ("player" or "master")
-- @return  tblDiffs        Diff-table of friend-list changes vs snapshot
-- @return  nil             Invalid parameters
function AF.diffSnapAndFriendList( self, friendListObj, whichSnap )

    -- Parameter validation
    if( not pcall( function( ) return friendListObj:chkType( AF.Friends.class ) end ) ) then
        debug:warn( "Invalid friends object - can't search complete diff." )
        return nil
    elseif( whichSnap == nil ) then
        debug:warn( "No snapshot specified - can't complete diff." )
        return nil
    elseif( whichSnap ~= "player" and whichSnap ~= "master" ) then
        debug:warn( "Invalid snapshot specified - can't complete diff." )
        return nil
    end

    local sourceSnap
    if( whichSnap == "player" ) then
        sourceSnap = self.tFriends
    else
        sourceSnap = self.tMasterFriends
    end
    local tFriendList = friendListObj:getFriendsAsNames( )

    local tblDiffs = {}

    -- Iterate the specified snapshot.  For every snapshot element that is not
    -- also in the friend-list, add it to the diff-table as a "removed" element.
    for playerKey, _ in pairs( sourceSnap ) do
        if( tFriendList[playerKey] == nil ) then
            tblDiffs[playerKey] = "removed"
            debug:debug( "Logging a 'removed %s' diff", playerKey )
        end
    end

    -- Iterate the friend list.  For every friend-list element that is not
    -- also in the snapshot, add it to the diff-table as an "added" element.
    for playerKey, _ in pairs( tFriendList ) do
        if( sourceSnap[playerKey] == nil ) then
            tblDiffs[playerKey] = "added"
            debug:debug( "Logging a 'added %s' diff", playerKey )
        end
    end

    return tblDiffs
end


--- Class public method "isFullSyncActive"
-- Indicates whether or not the addon will ignore the individual (by character)
-- delete flag and instead do stale friend-deletions on ALL characters on the
-- current realm and every connected realm.
-- @return  true    Full-Synchronization will be done.
-- @return  false   Full-Synchronization  will not be done.
function AF.Snapshot:isFullSyncActive( )
    debug:trace( "entered" )
    debug:trace( "exited" )
    return self.fullSync
end


---Class public method "setFullSync"
-- Turns FullSync true/false as specified for the local & all connected realms.
-- If the FullSync flag was already set to the new setting, then nothing further
-- is done.  If the setting has now changed, then a full friend snapshot-refresh
-- is performed immediately afterward to update any stale-deletion state that
-- might exist.
-- @param   fullSyncFlag    (true/false) Setting to change FullSync flag to.
-- @param   friendListObj   Friendlist to update the friend snapshot from.
-- @return  true            FullSync flag set.
-- @return  false           Error setting flag
function AF.Snapshot:setFullSync( fullSyncFlag, friendListObj )
    debug:trace( "entered" )

    -- Parameter validation
    if( not pcall( function( ) return friendListObj:chkType( AF.Friends.class ) end ) ) then
        debug:warn( "Invalid friends object - can't search within snapshot." )
        debug:trace( "exited" )
        return false
    elseif( fullSyncFlag == nil or type( fullSyncFlag ) ~= "boolean" ) then
        debug:warn( "Specified flag nil or empty - not setting FullSync flag." )
        debug:trace( "exited" )
        return false
    elseif( friendListObj == nil or type( friendListObj ) ~= "table" ) then
        debug:warn( "FriendList object nil or not table - not setting FullSync Flag." )
        debug:trace( "exited" )
        return false
    end

    -- If flag has changed, then immediately refresh the friend snapshot to
    -- properly rebase the per-player "overlay" and master snapshots, etc.
    if( self.FullSync ~= fullSyncFlag ) then
        self.fullSync = fullSyncFlag
        debug:info( "FullSync flag changed to %s", strupper( AF._tostring( self.fullSync ) ) )
        self:refreshFriendsSnapshot( friendListObj )
    else
        debug:info( "FullSync flag already %s.", AF._tostring( fullSyncFlag ) )
    end

    debug:trace( "exited" )
    return true
end


--- Class public-method "new"
--- Class constructor "new"
-- Creates a new Friends object and sets initial state.
-- @return          The newly constructed and initialized Friends object
function AF.Snapshot:new( )
    debug:trace( "entered" )

    local snapshotObj = {}                      -- New object
    setmetatable( snapshotObj, AF.Snapshot_mt ) -- Set up the object's metatable

    -- Per-object data initialization
    ----------------------------------------------------------------------------
    snapshotObj.tFriends            = {}
    snapshotObj.numFriends          = 0
    snapshotObj.tMasterFriends      = {}
    snapshotObj.numMasterFriends    = 0
    snapshotObj.Realm               = AF.getCurrentRealm( )
    snapshotObj.tConnectedRealms    = AF.getConnectedRealms( )
    snapshotObj.doDeletions         = false
    snapshotObj.fullSync            = false
    ----------------------------------------------------------------------------

    debug:trace( "exited" )
    return snapshotObj
end


--- class public method "isDeletionActive"
-- Indicates whether or not the addon will delete stale friends from the
-- friend list.
-- @return  true    Deletions will be done.
-- @return  false   Deletions will not be done.
function AF.Snapshot:isDeletionActive( )
    debug:trace( "entered" )
    debug:trace( "exited" )
    return self.doDeletions
end


--- class public method "setDeletion"
-- Sets the deletion flag for the current player in the snapshot to true / false
-- as specified.
-- @param   true / false    Set the deletion flag accordingly
-- @return  true            Deletion flag set
-- @return  false           Error setting flag
function AF.Snapshot:setDeletion( deleteFlag )
    debug:trace( "entered" )

    -- Parameter validation
    if( deleteFlag == nil or type( deleteFlag ) ~= "boolean" ) then
        debug:warn( "Specified parameter nil or not boolean - not setting Deletion flag." )
        debug:trace( "exited" )
        return false
    end
    self.doDeletions = deleteFlag
    debug:trace( "exited" )
    return true
end


--- Class public method "countFriends"
-- Returns the number of friends currently present in either the player's
-- snapshot individual snapshot, or the realm-group's master snapshot.
-- @param   whichSnap   "player" or "master" - which snapshot to work on
-- @return              The number of friends currently in the snapshot.
-- @return  nil         If there was an error processing the count
function AF.Snapshot:countFriends( whichSnap )
    debug:trace( "entered" )
    debug:trace( "exited" )

    -- Parameter validation
    if( whichSnap == nil ) then
        debug:warn( "No target snapshot specified - can't count friends." )
        return nil
    else
        whichSnap = strlower( whichSnap )
        if( whichSnap ~= "player" and whichSnap ~= "master" ) then
            debug:warn( "Target snapshot not player or master - can't count friends." )
            return nil
        end
    end

    if( whichSnap == "player" ) then
        return self.numFriends
    else
        return self.numMasterFriends
    end
end


--- Class public-method "refreshFriendsSnapshot"
-- (Re)builds the set of friends contained within the snapshot to reflect
-- the current state of the friend list.  Any prior friends in the snapshot
-- are first wiped.
-- @param   friendListObj   Friend-List object representing the current friend-list
-- @return  true            New set of friends built successfully within snapshot
-- @return  false           Error building new set of friends within snapshot
function AF.Snapshot:refreshFriendsSnapshot( friendListObj )
    debug:trace( "entered" )

    -- Parameter validation
    if( not pcall( function( ) return friendListObj:chkType( AF.Friends.class ) end ) ) then
        debug:warn( "Invalid friends object - can't rebuild snapshot." )
        debug:trace( "exited" )
        return false
    end

    -- Abort the snapshot rebuild if the addon hasn't finished initializing
    if( not self.snapshotRestored ) then
        debug:debug( "Addon init appears unfinished - skipping friend snapshot rebuild." )
        debug:trace( "exited" )
        return false
    end

    -- Identify what is different between the master snapshot and friend list.
    -- Handle differences as follows:
    --   1. Friends in the master snapshot but not the friend-list were just
    --      "newly-removed" by the player, so remove them from the master
    --       snapshot.
    --   2. friends in the friend-list but not the master snapshot are one of
    --      two things:  Newly-added, or stale.  Handle as follows:
    --        a. Friends not in the master snapshot and also not in the per-
    --           player "overlay" list are "newly-added", so add them to the
    --           master snapshot.
    --        b. Friends not in the master snapshot but in the player-specifc
    --           "overlay" list are stale.  Delete them from the friend-list
    --           and player-specific "overlay" snapshot if FullSync or
    --           DoDeletions are on, otherwise leave intact.
    debug:debug( "Starting to diff master vs friend list..." )
    local tDiffs = AF.diffSnapAndFriendList( self, friendListObj, "master" )
    for playerKey, whatHappened in pairs( tDiffs ) do
        debug:debug( "%s was %s from the snapshot.", playerKey, whatHappened )
        local tmpPlayerObj = AF.Player:new( playerKey )
        if( whatHappened == "removed" ) then
            AF.removeFriendFromSnapshot( self, tmpPlayerObj, "master" )
            debug:info( "Friend %s removed from master snapshot", playerKey )
        else
            if( AF.findFriendInSnapshot( self, tmpPlayerObj, "player" ) == "missing" ) then
                AF.addFriendToSnapshot( self, tmpPlayerObj, "master" )
            else
                if( self:isFullSyncActive( ) or self:isDeletionActive( ) ) then
                    friendListObj:removeFriend( playerKey )
                    AF.removeFriendFromSnapshot( self, tmpPlayerObj, "player" )
                end
            end
        end
    end
end


--- Class public-method "restoreFriendsSnapshot"
-- Syncs the in-game friend list to fully match the current friend snapshot:
--   1. Players in the snapshot that are missing from the friend list will be
--      added if they are on the same current (or any connected) realm.
--   2. Players in the friend list but not in the snapshot will be removed
--      according to the following conditions (otherwise stale friends will be
--      left alone):
--        - if fullSync is on (affects all characters in the current realm-group)
--        - if fullSync is off but doDeletions is on (current character only)
--
-- NOTE: This will temporarily unregister the FRIENDLIST_UPDATE event (if
--       previously registered) event in order to prevent triggering new
--       snapshot-refreshes whenever the friend list is altered.  The original
--       registration state of the event will be restored after the sync's done.
--
-- @param   friendListObj   Friend-List object representing the current friend-list
-- @return  true            New set of friends built successfully within snapshot
-- @return  false           Error building new set of friends within snapshot
function AF.Snapshot:restoreFriendsSnapshot( friendListObj )
    debug:trace( "entered" )

    -- Parameter validation
    if( not pcall( function( ) return friendListObj:chkType( AF.Friends.class ) end ) ) then
        debug:warn( "Invalid friend list object - can't restore snapshot." )
        debug:trace( "exited" )
        return false
    end

    -- Temporarily unregister FRIENDLIST_UPDATE event so that restores don't
    -- trigger new snapshots mid-way through.  Remember what the old register
    -- state was so it can be restored afterward.
    local oldRegisterState = frame:IsEventRegistered( "FRIENDLIST_UPDATE" ) == 1 or false
    if( oldRegisterState ) then
        frame:UnregisterEvent( "FRIENDLIST_UPDATE" )
        debug:debug( "Unregistering FRIENDLIST_UPDATE during restore" )
    else
        debug:debug( "FRIENDLIST_UPDATE already unregistered during restore" )
    end

    -- Iterate the snapshot and add all missing friends into the friend list.
    -- If a player-snapshot contains any friends, then use it; otherwise iterate
    -- through the master snapshot for that realm-group.
    local sourceSnap
    if( self:countFriends( "master" ) > 0 ) then
        sourceSnap = self.tMasterFriends
        debug:debug( "Master snapshot has friends, using it." )
    else
        sourceSnap = self.trFriends
        debug:debug( "Master snapshot is empty, using player snapshot instead." )
    end

    for _, playerObj in pairs( sourceSnap ) do
        friendListObj:addFriend( playerObj )
    end

    -- Once all players in the master snapshot are in the friend list, scan for
    -- stale friends (in the friend-list but not the master snapshot).  Handle
    -- all stale friends as follows:
    --   1. If fullSync or doDeletions are on, then delete stale friends from
    --      master snapshot.  Otherwise,
    --   2. if fullSync or doDeletions are off, then add the stale friends to
    --      the player-specific "overlay" snapshot to ensure preservation.
    local tDiffs = AF.diffSnapAndFriendList( self, friendListObj, "master" )
    AF.wipeFriendsFromSnapshot( self, "player" )
    for playerKey, action in pairs( tDiffs ) do
        if( action == "added" ) then
            if( self:isFullSyncActive( ) or self:isDeletionActive() ) then
                friendListObj:removeFriend( AF.Player:new( playerKey ) )
                debug:info( "%s stale - removed from friend list.", playerKey )
            else
                AF.addFriendToSnapshot( self, AF.Player:new( playerKey ), "player" )
                debug:info( "%s stale - added to player-specific overlay snapshot.", playerKey )
            end
        end
    end

    -- Once restore is completed, re-register this event (only if it previously
    -- was registered prior to starting the restore).  Instead of re-registering
    -- immediately, do so after a short delay to ensure all friend-list changes
    -- have been processesd by the server.  This should avoid unnecessary
    -- triggering of new snapshots for each change made.
    if( oldRegisterState ) then
        debug:debug( "Restore complete, re-registering FRIENDLIST_UPDATE" )
        C_Timer.After( 10, function() frame:RegisterEvent( "FRIENDLIST_UPDATE" ) end )
    else
        debug:debug( "Restore complete, not re-registering FRIENDLIST_UPDATE" )
    end

    self.snapshotRestored = true    -- Flag that a snapshot restoration has completed
    debug:always( "Friends List synchronized." )
    debug:trace( "exited" )
    return true
end


--- class public method "dumpFriendSnapshot"
-- Dumps the current Friend snapshot to debug-output.
-- @return                  <none>
function AF.Snapshot:dumpFriendSnapshot( whichSnap )
    debug:trace( "entered" )

    -- Parameter validation
    if( whichSnap == nil ) then
        debug:warn( "No target snapshot specified - can't dump friends." )
        return nil
    else
        whichSnap = strlower( whichSnap )
        if( whichSnap ~= "player" and whichSnap ~= "master" ) then
            debug:warn( "Target snapshot not player or master - can't dump friends." )
            return nil
        end
    end

    local count = 1
    local target
    if( whichSnap == "player" ) then
        target = self.tFriends
    else
        target = self.tMasterFriends
    end
    for _, playerObj in pairs( target ) do
        debug:always( "#%d %s%s-%s%s", count, CLR_VALUE, playerObj:getName( ), playerObj:getRealm( ), CLR_REG )
        count = count + 1
    end
    debug:trace( "exited" )
end


--- class public method "loadDataFromGlobal"
-- Intended to be called whenever the player logs in or reloads their UI (which
-- is when SavedVariable data is restored from the filesystem and placed into
-- the addon's globals.  This method takes that global data, searches it for
-- info related to the current realm, and and places it back into the class's
-- local data, overwriting whatever may have previously existed (e.g.
-- newly-initialized defaults).  Does nothing to previous data if no
-- SavedVariable data is available (i.e. first-time the Addon has ever been run)
-- or if no data related to the current realm can be found.
-- @return  true    Successfully loaded global data into class data
-- @return  false   Error during load
function AF.Snapshot:loadDataFromGlobal( )
    debug:trace( "entered" )
    debug:debug( "Loading snapshot from global SavedVariable" )

    local myName = strlower( UnitName( "player" ) ) .. "-" .. self.Realm

    -- Get the locations of the various global data related to this player
    local tDoDeletions, tMyRealmGroup, tMasterSnapshot = AF.findGlobals( self, myName )

    -- Load all the data from the Addon Globals related to this player into the snapshot
    if( tDoDeletions[myName] ~= nil ) then
        self:setDeletion( tDoDeletions[myName] )
    end
    if( tMyRealmGroup.fullSync ~= nil ) then
        self.fullSync = tMyRealmGroup.fullSync
    end
    for _, playerKey in ipairs( tMasterSnapshot ) do
        if( AF.addFriendToSnapshot( self, AF.Player:new( playerKey ), "master" ) ) then
            debug:debug( "Loaded master snapshot with %s from SavedVariables.", playerKey )
        else
            debug:warn( "Error loading master snapshot with %s from SavedVariables.", playerKey )
            debug:trace( "exited" )
            return false
        end
    end

    -- In-case this was a newly-created realm-group, save the list of connected
    -- realms so that this realm-group can be found the next time.
    tMyRealmGroup.realmList = self.tConnectedRealms

    debug:debug( "Finished loading SavedVariable data into snapshot." )
    debug:trace( "exited" )
    return true
end


--- Class public method "saveDataToGlobal"
-- Intended to be called whenever the player logs out or reloads their UI.
-- Player-Logout is when the game will serialize the addon's global data into
-- its SavedVariable filesystem store.  This method takes the class's local
-- data and places it into the addon's globals so it can be serialized.
function AF.Snapshot:saveDataToGlobal( )
    debug:trace( "entered" )
    debug:debug( "Saving snapshot to globals for serialization into SavedVariable")

    local myName = strlower( UnitName( "player" ) .. "-" .. self.Realm )

    -- Get the locations of the various global data related to this player
    local tDoDeletions, tMyRealmGroup, tMasterSnapshot = AF.findGlobals( self, myName )

    -- Save all the data related to this player into the Addon Globals
    tDoDeletions[myName]    = self:isDeletionActive( )
    tMyRealmGroup.fullSync  = self:isFullSyncActive( )
    tMyRealmGroup.realmList = self.tConnectedRealms

    wipe( tMasterSnapshot )
    for playerKey, _ in pairs( self.tMasterFriends ) do
        tblinsert( tMasterSnapshot, playerKey )
    end

    debug:debug( "Snapshot saved to global data." )
    debug:trace( "exited" )
end


--- Class public method "chkType"
-- Asserts whether the specified class ID matches the ID of this class
-- @param   wantedType  Class ID to assert against this class's ID
-- @return  true        Returned of the specified class ID matches this class's ID
-- @return <error raised by the assert() if the IDs don't match>
function AF.Snapshot:chkType( wantedType )
    return assert( self.class == wantedType )
end


-- vim: autoindent tabstop=4 shiftwidth=4 softtabstop=4 expandtab
