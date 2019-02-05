--[[
     File Name           :     Snapshots.lua
     Created By          :     tubiakou
     Creation Date       :     [2019-01-07 01:28]
     Last Modified       :     [2019-02-05 09:51]
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
local addonName, AF = ...


-- Some local overloads to optimize performance (i.e. stop looking up these
-- standard functions every single time they are called, and instead refer to
-- them by local variables.
local string                = string
local strlower              = string.lower
local getConnectedRealms    = AF.getConnectedRealms
local getCurrentRealm       = AF.getCurrentRealm
local pairs                 = pairs
local tostring              = AF._tostring


--- Tables for Class and metatable (stored within the addon's globals)
AF.Snapshot             = {}            -- Class
AF.Snapshot_mt          = {}            -- Metatable
AF.Snapshot_mt.__index  = AF.Snapshot   -- Look in the class for undefined methods


--- Class private method "wipeFriends"
-- Wipes all friends from the snapshot.
-- @param   self        Object context
local function wipeFriends( self )
    wipe( self.tFriends )
    self.numFriends = 0
    debug:debug( "Snapshot wiped of all friends." )
    return
end


--- class private method "setSkipDelete"
-- Takes the specified player object, treats them as a stale friend (i.e. in a
-- friend-list but not in the snapshot), and sets/clears their SkipDelete
-- status.  Having this status set causes the specified stale friend to not be
-- withheld from the friend list on subsequent snapshot restores.
-- @param   self        Object context
-- @param   playerObj   Player object to act on.
-- @param   status      (true/false) Sets/unsets the SkipDelete status
-- @return  true        Status successfully set/unset
-- @return  false       Error setting/unsetting status
local function setSkipDelete( self, playerObj, status )

    -- Parameter validation
    if( playerObj == nil or type( playerObj ~= "table" ) ) then
        debug:warn( "Player object nil or not table - not setting skip-delete status." )
        return false
    elseif( status == nil or type( status ) ~= "boolean" ) then
        debug:warn( "status flag nil or not-boolean - not setting skip-delete status." )
        return false
    end

    -- If provided status == true then add the player object to the SkipDelete
    -- table.  If status == false then remove the player object from the
    -- SkipDelete table if they exist (do nothing if they don't).
    if( status ) then
        self.tSkipDelete[ playerObj:getKey( ) ] = playerObj
        debug:debug( "Added %s to tSkipDelete table.", playerObj:getKey( ) )
    else
        if( self.tSkipDelete[ playerObj:getKey( ) ] ~= nil ) then
            self.tSkipDelete[ playerObj:getKey( ) ] = nil
        end
        debug:debug( "Removed %s from tSkipDelete table.", playerObj:getKey( ) )
    end
    return true
end


--- class private method "getSkipDelete"
-- Takes the specified player object, treats them as a stale friend (i.e. in a
-- a friend list but not in the snapshot), and returns their SkipDelete status.
-- @param   self        Object context
-- @param   playerObj   Player object to act on
-- @return  "set"       Player has its SkipDelete status set
-- @return  "unset"     Player's SkipDelete status is not set.
-- @return  ""          Error getting status
local function getSkipDelete( self, playerObj )

    -- Parameter validation
    if( playerObj == nil or type( playerObj ) ~= "table" ) then
        debug:warn( "Player object nil or not table - not getting skip-delete status." )
        return ""
    end

    if( self.tSkipDelete[ playerObj:getKey( ) ] ~= nil ) then
        debug:debug( "Player %s skip-delete status is set.", playerObj:getKey( ) )
        return "set"
    else
        debug:debug( "Player %s skip-delete status is not set.", playerObj:getKey( ) )
        return "unset"
    end
end


--- Class private method "findFriend"
-- Takes a specified player object and indicates whether or not they are
-- present as a friend in the snapshot.
-- @param   playerObj       Player object to be searched for as a friend
-- @return  "present"       Player present in snapshot as a friend
-- @return  "missing"       Player not in snapshot as a friend
-- @return  ""              Error (e.g. invalid player object)
local function findFriend( self, playerObj )

    -- Parameter validation
    if( not playerObj or type( playerObj ) ~= "table" ) then
        debug:warn( "Invalid player object - can't search within snapshot." )
        return ""
    end
    if( not playerObj:getKey( ) ) then
        debug:warn( "Missing player name and/or realm - can't search within snapshot." )
        return ""
    end
    if( self.tFriends[ playerObj:getKey( ) ] ) then
        debug:info( "Friend %s present in snapshot.", playerObj:getKey( ) )
        return "present"
    else
        debug:info( "Friend %s not present in snapshot.", playerObj:getKey( ) )
        return "missing"
    end
end


--- Class private method "addFriend"
-- Takes a specified player object and stashes them into the snapshot as a
-- friend.  This is idempotent - multiple attempts on the same player, or
-- adding a player that is already present will not cause duplicates.
-- @param   playerObj   Player object to be stashed as a friend
-- @return  true        Player stashed successfully
-- @return  false       Error stashing player
local function addFriend( self, playerObj )

    -- Parameter validation
    if( not playerObj or type( playerObj ) ~= "table" ) then
        debug:warn( "Invalid player object - can't add to snapshot." )
        return false
    end
    if( playerObj:getName( ) == "" or playerObj:getRealm( ) == "" ) then
        debug:warn( "Missing player name and/or realm - can't add to snapshot." )
        return false
    end

    -- If player already in snapshot then we're all done. Otherwise, go ahead
    -- and stash them.
    if( findFriend( self, playerObj ) == "present" ) then
        debug:info( "Friend %s already in snapshot.", playerObj:getKey( ) )
    else
        self.tFriends[ playerObj:getKey( )  ] = playerObj
        self.numFriends = self.numFriends + 1
        debug:info( "Stashed %s into snapshot (friend #%d)", playerObj:getKey( ), self.numFriends )
    end
    return true
end


--- class private method "isDeletionActive"
-- Indicates whether or not the addon will delete stale friends from the
-- friend list.
-- @return  true    Deletions will be done.
-- @return  false   Deletions will not be done.
local function isDeletionActive( self )
    return self.doDeletions
end


--- class private method "setDeletion"
-- Sets the deletion flag for the current player in the snapshot to true / false
-- as specified.
-- @param   true / false    Set the deletion flag accordingly
-- @return  true            Deletion flag set
-- @return  false           Error setting flag
local function setDeletion( self, deleteFlag )

    -- Parameter validation
    if( deleteFlag == nil or type( deleteFlag ) ~= "boolean" ) then
        debug:info( "Specified parameter nil or not boolean - not setting Deletion flag." )
        return false
    end
    self.doDeletions = deleteFlag
    return true
end


--- Class public-method "getNumFriends"
--- Class constructor "new"
-- Creates a new Friends object and sets initial state.
-- @return          The newly constructed and initialized Friends object
function AF.Snapshot:new( )
    local snapshotObj = {}                      -- New object
    setmetatable( snapshotObj, AF.Snapshot_mt ) -- Set up the object's metatable

    -- Per-object private Data
    ----------------------------------------------------------------------------
    snapshotObj.tFriends           = {}        -- Tbl of snapshotted player friends
    snapshotObj.numFriends         = 0         -- Number of friends in snapshot
    snapshotObj.Realm              = ""        -- Name of current realm
    snapshotObj.tConnectedRealms   = {}        -- Tbl of connected or local realms
    snapshotObj.snapshotRestored   = false     -- Has a snapshot-restore completed
    snapshotObj.doDeletions        = false     -- Should the addon delete stale friends
    snapshotObj.fullSync           = false     -- Ignore doDeletions (turn TRUE for all currently connected realms)
    snapshotObj.tSkipDelete        = {}        -- Table of stale friends to not delete
    ----------------------------------------------------------------------------

    -- Per-object initial settings
    ----------------------------------------------------------------------------
    snapshotObj.Realm              = getCurrentRealm( )
    snapshotObj.tConnectedRealms   = getConnectedRealms( )

    return snapshotObj
end


-- Returns the number of friends currently present in the snapshot.
-- @return          The number of friends currently in the snapshot.
function AF.Snapshot:getNumFriends( )
    return self.numFriends
end


--- Class public-method "refreshFriendsSnapshot"
-- (Re)builds the set of friends contained within the snapshot to reflect
-- the current state of the friend list.  Any prior friends in the snapshot
-- are first wiped.
-- @param   friendListObj   Friend-List object representing the current friend-list
-- @return  true            New set of friends built successfully within snapshot
-- @return  false           Error building new set of friends within snapshot
function AF.Snapshot:refreshFriendsSnapshot( friendListObj )

    -- Parameter validation
    if( not friendListObj ) then
        debug:warn( "Invalid friend list object - can't rebuild snapshot." )
        return false
    end

    -- Abort the snapshot rebuild if the addon hasn't finished initializing
    if( not self.snapshotRestored ) then
        debug:debug( "Addon init appears unfinished - skipping friend snapshot rebuild." )
        return false
    end

    -- Extract the full current friend-list.  Abort the rebuild if an error occurred.
    local tFriendsTmp = friendListObj:getFriends( )
    if( not tFriendsTmp ) then
        debug:warn( "Error pulling current friend list - aborting snapshot rebuild." )
        return false
    end

    wipeFriends( self )
    for i = 1, #tFriendsTmp do
        -- Stale friends will NOT be stashed in snapshots if any of the following
        -- are true:
        --  1. fullSync == true (for all characters in the current realm-group)
        --  2. DeletionActive == true for the current character, and the stale
        --     friend does NOT have its SkipDelete status set.
        -- In all other cases, stale friends will be stashed in snapshots, causing
        -- them to continue being propagated to other characters in the same realm-
        -- group.
        if( self:isFullSyncActive() ) then
            debug:debug( "FullSync active - stale friend %s not stashed into snapshot.", tFriendsTmp[i]:getKey( ) )
        elseif( isDeletionActive( self ) and not getSkipDelete( self, tFriendsTmp[i]:getKey( ) ) ) then
            debug:debug( "Deletions active and stale friend not flagged - not stashed into snapshot.",
                         tFriendsTmp[i]:getKey( ) )
        else
            debug:debug( ">>>   Adding #%d [%s] to snapshot.", i, tFriendsTmp[i]:getKey() )
            addFriend( self, tFriendsTmp[i] )
        end
    end
    return true
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

    -- Parameter validation
    if( not friendListObj ) then
        debug:warn( "Invalid friend list object - can't restore snapshot." )
        return false
    end

    debug:debug( "friendListObj: %s", tostring( friendListObj ) )

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

    -- Iterate through the snapshot and add all missing friends in it into the
    -- friend list.
    for playerKey, playerObj in pairs( self.tFriends ) do
        if( not friendListObj:findFriend( playerObj ) ) then
            friendListObj:addFriend( playerObj )
            debug:info( "Added %s to friend list.", playerKey )
        else
            debug:debug( "%s already in friend list.", playerKey )
        end
    end

    -- Iterate the friend-list, searching for stale friends (i.e. friends that
    -- aren't also in the snapshot).  If fullSync is on (all players on all
    -- realms in the connected group) then remove the stale player from the
    -- friend list.  Do the same if fullSync is off but doDeletions is on (for
    -- the current player on the current realm).  Otherwise, leave stale friends
    -- alone and flag for no-deletion the next time the addon is loaded and the
    -- snapshot is restored.
    local tFriendsTmp = friendListObj:getFriends()
    for playerKey, playerObj in pairs( tFriendsTmp ) do
        if( findFriend( self, playerObj ) ) then
            debug:debug( "Friend %s not stale - doing nothing.", playerKey )
        else
            if( not self:isFullSyncActive( ) and not isDeletionActive( self ) ) then
            debug:debug( "Friend %s stale but fullSync and doDeletions are off - doing nothing", playerKey )
            else
                debug:debug( "Friend %s stale and fullSync or doDeletions are on - removing.", playerKey )
                friendListObj:removeFriend( playerObj )
                setSkipDelete( self, playerObj, true )
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
    return true
end


--- class public method "dumpFriendSnapshot"
-- Dumps the current Friend snapshot to debug-output.
-- @return                  <none>
function AF.Snapshot:dumpFriendSnapshot( )
    local count = 1
    for _, playerObj in pairs( self.tFriends ) do
        debug:always( "#%d %s-%s", count, playerObj:getName( ), playerObj:getRealm( ) )
        count = count + 1
    end
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
-- @return  false   No SavedVariable data found - nothing done.
function AF.Snapshot:loadDataFromGlobal( )
    debug:debug( "Loading snapshot from global SavedVariable" )

    -- Done if no SavedVariable data exists
    if( AllFriendsData == nil ) then
        debug:debug( "No SavedVariable container table found - doing nothing." )
        return false
    end

    local myName = strlower( UnitName( "player" ) ) .. "-" .. self.Realm
    if( AllFriendsData.doDeletions ~= nil and AllFriendsData.doDeletions[ myName ] ~= nil ) then
        setDeletion( self, AllFriendsData.doDeletions[ myName ] )
    end

    -- Iterate through the various realm-groups (i.e. sets of connected realms)
    -- until a group containing the current realm is found.  Do nothing if no
    -- realm-group containing the current realm can be found.
    if( AllFriendsData.RealmGroups ) then
        local gIndex = 1
        while( AllFriendsData.RealmGroups[gIndex] ~= nil ) do
            local groupArray = AllFriendsData.RealmGroups[gIndex]
            local rIndex = 1
            while( groupArray.realmList[rIndex] ~= nil ) do
                if( groupArray.realmList[rIndex] == self.Realm ) then

                    -- This is our realm-group.  Validate integrity and then copy
                    -- its data into the class private storage.
                    if( groupArray.tFriends ~= nil and groupArray.numFriends ~= nil ) then
                        for playerKey, _ in pairs( groupArray.tFriends ) do
                            if( addFriend( self, AF.Player:new( playerKey ) ) ) then
                                debug:debug( "Loaded snapshot with friend %s from SavedVariables.", playerKey )
                            else
                                debug:warn( "Error loading friend %s from SavedVariables into snapshot.", playerKey )
                                return false
                            end
                        end
                        self.fullSync = groupArray.fullSync
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
    end
    debug:debug( "SavedVariable exists but no info on current realm [%s] found - doing nothing.", self.Realm )
    return false
end


--- Class public method "saveDataToGlobal"
-- Intended to be called whenever the player logs out or reloads their UI.
-- This is when the addon's SavedVariable data is pulled from the addon's
-- globals and serialized to the filesystem. This method takes the class's
-- local data and places it into the addon's globals so it can be serialized.
function AF.Snapshot:saveDataToGlobal( )
    debug:debug( "Saving snapshot to global SavedVariable" )
    local myName = strlower( UnitName( "player" ) .. "-" .. self.Realm )

    AllFriendsData = AllFriendsData or {}

    AllFriendsData.doDeletions = AllFriendsData.doDeletions or {}
    AllFriendsData.doDeletions[myName] = isDeletionActive( self )

    -- If the SavedVariable contains any pre-existing realm-groups (e.g. sets
    -- of connected realms) then iterate them to find one that contains the
    -- current realm.  Use that one if found, otherwise create a new gorup.
    local gIndex     = 1
    if( AllFriendsData.RealmGroups ~= nil ) then
        while( AllFriendsData.RealmGroups[gIndex] ~= nil ) do
            local groupArray = AllFriendsData.RealmGroups[gIndex]
            local rIndex = 1
            while( groupArray.realmList[rIndex] ~= nil ) do

                -- This is our realm-group.  Store our data in it.
                if( strlower( groupArray.realmList[rIndex] ) == self.Realm ) then
                    for playerKey, _ in pairs( self.tFriends ) do
                        groupArray.tFriends[playerKey] = "saved"
                        debug:debug( "Saved snapshot friend %s into SavedVariables.", playerKey )
                    end
                    groupArray.realmList  = self.tConnectedRealms
                    groupArray.numFriends = self.numFriends
                    groupArray.fullSync   = self.fullSync
                    debug:debug( "Realm-group existed in SavedVariables for current realm - updated." )
                    return true
                end
                rIndex = rIndex + 1
            end
            gIndex = gIndex + 1
        end
    else
        AllFriendsData.RealmGroups = {}
    end

    -- No existing realm group was found that contains the current realm.  At
    -- this point gIndex points to an empty slot in AllFriendsData.RealmGroups
    -- so just go ahead and populate it with current data.
    AllFriendsData.RealmGroups[gIndex] = {}
    local groupArray = AllFriendsData.RealmGroups[gIndex]
    for playerKey, _ in pairs( self.tFriends ) do
        groupArray.tFriends[playerKey] = "saved"
        debug:debug( "Saved snapshot friend %s into SavedVariables.", playerKey )
    end
    groupArray.realmList  = self.tConnectedRealms
    groupArray.numFriends = self.numFriends
    groupArray.fullSync   = self.fullSync
    debug:debug( "No snapshot found for current realm - creating new one." )
    return true
end



    -- CONTINUE HERE.  ALSO ENSURE THAT THE SKIPDELETE THING PER-PLAYER IS HANDLED.






--- class public method "isFullSyncActive"
-- Indicates whether or not the addon will ignore the individual (by character)
-- delete flag and instead do stale friend-deletions on ALL characters on the
-- current realm and every connected realm.
-- @return  true    Full-Synchronization will be done.
-- @return  false   Full-Synchronization  will not be done.
function AF.Snapshot:isFullSyncActive( )
    return self.fullSync
end


--- class public method "enableFullSync"
-- When enabled, the individual (by character) delete-flag will be ignored, and
-- instead stale friends will be deleted for ALL characters on the current realm
-- and every connected realm.
function AF.Snapshot:enableFullSync( )
    self.fullSync = true
    return
end


--- class public method "disableFullSync"
-- When disabled, stale-friend deletion will be done on a per-character basis
-- as per their individual deletion flags.
function AF.Snapshot:disableFullSync( )
    self.fullSync = false
    return
end


-- vim: autoindent tabstop=4 shiftwidth=4 softtabstop=4 expandtab
