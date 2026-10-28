local foundation={ready=false,status='starting',schemaVersion=0,applied=0,resumed=0}
local stopped=false
local function dependencies()
    return GetResourceState('feather-mysql')=='started' and GetResourceState('feather-core')=='started'
end
local function health()
    local ready=foundation.ready and not stopped and dependencies()
    return {
        resource=FeatherDoors.Name,ready=false,status=ready and 'foundation_ready'
            or (foundation.ready and 'dependency_unavailable' or foundation.status),
        stage='schema_foundation',foundationReady=ready,schemaVersion=foundation.schemaVersion,
        migrationsApplied=foundation.applied,migrationsResumed=foundation.resumed
    }
end
exports('GetCapabilities',function()
    return {resource=FeatherDoors.Name,version=FeatherDoors.Version,stage='schema_foundation',
        doorRegistration=false,lockState=false,persistence=false,synchronization=false,playerInteraction=false,
        schema=health().foundationReady and 1 or 0}
end)
exports('GetHealth',health)
local function fail(code)
    foundation.ready=false; foundation.status=code
    print('[feather-doors] startup unavailable: '..code)
end
CreateThread(function()
    local ok,result=pcall(function()
        foundation.status='waiting_for_core'
        local core=exports['feather-core']:AwaitReady(30000)
        local caps=exports['feather-core']:GetCapabilities()
        if type(core)~='table' or core.ok~=true or type(caps)~='table' or caps.ok~=true
            or type(caps.value)~='table' or caps.value.contract~=1 then return {ok=false,code='core_unavailable'} end
        foundation.status='waiting_for_database'
        if DB.awaitReady(30000)~=true then return {ok=false,code='database_unavailable'} end
        if stopped or not dependencies() then return {ok=false,code='dependency_stopped'} end
        foundation.status='migrating'
        local migrated=DoorsSchema.Run(DB)
        if not migrated.ok then return migrated end
        local checked=DoorsSchema.Check(DB)
        if not checked.ok then return checked end
        if stopped or not dependencies() then return {ok=false,code='dependency_stopped'} end
        foundation.schemaVersion=migrated.value.version
        foundation.applied=migrated.value.applied; foundation.resumed=migrated.value.resumed
        foundation.status='foundation_ready'; foundation.ready=true
        print(('[feather-doors] foundation ready schema=%d applied=%d resumed=%d; door operations disabled'):format(
            foundation.schemaVersion,foundation.applied,foundation.resumed))
        return {ok=true}
    end)
    if not ok then fail('startup_exception'); print('[feather-doors] '..tostring(result))
    elseif not result.ok then fail(result.code) end
end)
AddEventHandler('onResourceStop',function(resource)
    if resource=='feather-core' or resource=='feather-mysql' or resource==GetCurrentResourceName() then
        stopped=true; foundation.ready=false; foundation.status='dependency_stopped'
    end
end)
RegisterCommand('DoorsSchemaSmokeTest',function(player,args)
    if player~=0 then return end
    if #args~=0 then print('[feather-doors] Usage: DoorsSchemaSmokeTest (server console)'); return end
    if not health().foundationReady then print('[feather-doors] schema smoke unavailable: '..foundation.status); return end
    local ok,result=pcall(DoorsSchema.Check,DB)
    if not ok then print('[feather-doors] schema smoke failed: database_exception'); return end
    print('[feather-doors] schema smoke '..(result.ok and ('PASS schema=1 tables=3 columns=22; operational ready=false') or ('FAIL '..result.code)))
end,true)
