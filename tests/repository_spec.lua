local function copy(t)
    if type(t)~='table' then return t end
    local out={}; for k,v in pairs(t) do out[k]=copy(v) end; return out
end
-- Test codec: deterministic scalar encoding for request canonicalization and
-- defensive receipt snapshots. Live fixture separately exercises Cfx JSON/SQL.
local encoded,counter={},0
json={encode=function(value)
    if type(value)~='table' then return string.format('%q',tostring(value)) end
    counter=counter+1; local token='receipt:'..counter; encoded[token]=copy(value); return token
end,decode=function(token) return copy(assert(encoded[token])),#token+1 end}
dofile('server/contract.lua'); dofile('server/events.lua'); dofile('server/repository.lua')
local C=DoorsContract
local passed=0
local function check(ok,label) assert(ok,label); passed=passed+1 end
local id='11111111-1111-1111-1111-111111111111'
local data={groups={},leaves={},receipts={},outbox={}}
local nextEvent=0
local enabled,unknown,loseAfterCommit,duplicate,revokeDuringWrite=true,false,false,false,false
local failOutbox=false
local db={}
local function receiptKey(a,b) return a..'/'..b end
function db.transaction(callback)
    local before=copy(data)
    local tx={}
    function tx.value(sql)
        if sql:find('event_id',1,true) then nextEvent=nextEvent+1; return ('22222222-2222-2222-2222-%012d'):format(nextEvent) end
        return id
    end
    function tx.one(sql,a,b)
        if sql:find('feather_door_outbox',1,true) then return copy(data.outbox[receiptKey(a,b)]) end
        if sql:find('feather_door_operations',1,true) then return copy(data.receipts[receiptKey(a,b)]) end
        local row
        if sql:find('`door_key`=?',1,true) then
            for _,candidate in pairs(data.groups) do if candidate.door_key==a then row=candidate end end
        else row=data.groups[a] end
        if row and b and row.manager_resource~=b then return nil end
        return copy(row)
    end
    function tx.query(sql,a,b,limit)
        if sql:find('feather_door_outbox',1,true) then
            local rows={}
            for key,row in pairs(data.outbox) do
                local joined=copy(row); joined.receipt_result_json=data.receipts[key].result_json; rows[#rows+1]=joined
            end
            return rows
        end
        if sql:find('feather_door_leaves',1,true) then return copy(data.leaves[a] or {}) end
        local rows={}; for _,row in pairs(data.groups) do
            if row.manager_resource==a and row.door_id>b then rows[#rows+1]=copy(row) end
        end
        table.sort(rows,function(x,y) return x.door_id<y.door_id end)
        while #rows>limit do table.remove(rows) end
        return rows
    end
    function tx.exec(sql,...)
        local p={...}
        if sql:find('INSERT INTO `feather_door_operations`',1,true) then
            local key=receiptKey(p[1],p[2]); data.receipts[key]=data.receipts[key] or {request_json=p[3]}
        elseif sql:find('UPDATE `feather_door_operations`',1,true) then
            data.receipts[receiptKey(p[2],p[3])].result_json=p[1]
        elseif sql:find('INSERT INTO `feather_door_groups`',1,true) then
            if duplicate then error({driverCode=1062,rollbackConfirmed=true}) end
            data.groups[p[1]]={door_id=p[1],door_key=p[2],label=p[3],manager_resource=p[4],locked=p[5],
                startup_policy=p[6],revision=1,delegation_epoch=1,status='active'}
        elseif sql:find('INSERT INTO `feather_door_leaves`',1,true) then
            data.leaves[p[2]]=data.leaves[p[2]] or {}
            table.insert(data.leaves[p[2]],{door_hash=p[1],door_id=p[2],model_hash=p[3],x=p[4],y=p[5],z=p[6],ordinal=p[7]})
        elseif sql:find('UPDATE `feather_door_groups`',1,true) then
            local row=assert(data.groups[p[6]])
            assert(row.revision==p[7],'expected SQL revision predicate')
            row.label=p[1]; row.status=p[2]; row.locked=p[3]; row.startup_policy=p[4]
            row.revision=row.revision+1; row.delegation_epoch=p[5]
        elseif sql:find('INSERT INTO `feather_door_outbox`',1,true) then
            local key=receiptKey(p[3],p[4]); assert(not data.outbox[key],'duplicate event')
            data.outbox[key]={event_id=p[1],door_id=p[2],source_resource=p[3],request_id=p[4],event_type=p[5],revision=p[6],payload_json=p[7],status='pending',attempts=0}
            if failOutbox then error('outbox insertion failed') end
        elseif sql:find('UPDATE `feather_door_outbox`',1,true) then
            for _,row in pairs(data.outbox) do if row.event_id==p[1] then row.status='pending' end end
        else error('unhandled SQL') end
        if unknown then error('unknown DB outcome') end
        if revokeDuringWrite then enabled=false end
    end
    local ok,result=pcall(callback,tx)
    if not ok or result~=true then data=before end
    if not ok then error(result) end
    if loseAfterCommit and result then loseAfterCommit=false; error('commit reply lost') end
    return result
end
local api=DoorsRepository.New(db,function() return enabled end)
local create={requestId='create',reasonCode='test',key='test.door',label='Test',locked=true,
    leaves={{hash=123,model=456,x=0,y=0,z=0}}}
check(not C.Validate('create',{}),'reject empty request')
for _,change in ipairs({{locked=1},{startupPolicy=false},{label='bad\nlabel'},{key=''},{actorSource=7},{leaves={{hash=1,model=-1,x=0,y=0,z=0}}},
    {leaves={{hash=1,model=1,x=math.huge,y=0,z=0}}},{leaves={{hash=1,model=1,x=0,y=0,z=-2001}}}}) do
    local bad=copy(create); for k,v in pairs(change) do bad[k]=v end
    check(not C.Validate('create',bad),'malformed definition rejected')
end
check(C.Canonical({a=1,b=2})==C.Canonical({b=2,a=1}),'canonical keys sorted')
local result=api:Mutate('owner','create',create)
check(result.ok and result.value.revision==1,'create definition')
check(result.value.leaves[1].hash==123,'create leaf projection')
check(api:Event('owner',{requestId='create'}).value.payload.operation=='create','committed event visible')
check(api:Event('other',{requestId='create'}).code=='not_found','event reads caller scoped')
local replay=api:Mutate('owner','create',copy(create))
check(replay.ok and replay.value.doorId==id and data.groups[id].revision==1,'create replay no duplicate')
check(nextEvent==1,'receipt replay does not generate another event')
local changed=copy(create); changed.label='Different'
check(api:Mutate('owner','create',changed).code=='request_conflict','immutable request ID')
check(api:Get('other',{doorId=id}).code=='not_found','another trusted caller cannot read group')
check(api:Find('other',{requestId='create'}).code=='not_found','another trusted caller cannot read receipt')
check(api:Get('owner',{key='test.door'},true).ok,'key lookup')
check(#api:List('other',{}).value.groups==0,'list scoped to manager')
check(#api:List('owner',{limit=1}).value.groups==1,'bounded list')
check(api:List('owner',{limit=51}).code=='invalid_request','oversized list refused')
check(api:List('owner',{limit=false}).code=='invalid_request','false list limit refused')
local update={requestId='update',reasonCode='test',doorId=id,expectedRevision=1,label='Updated'}
result=api:Mutate('owner','update',update)
check(result.ok and result.value.revision==2 and result.value.label=='Updated','update revision')
check(result.value.delegationEpoch==1,'label does not invalidate epoch')
check(api:Mutate('owner','state',{requestId='stale',reasonCode='test',doorId=id,expectedRevision=1,locked=false}).code=='revision_conflict','stale writer refused')
check(not data.outbox['owner/stale'],'rejected operation emits no event')
result=api:Mutate('owner','state',{requestId='state',reasonCode='test',doorId=id,expectedRevision=2,locked=false})
check(result.ok and result.value.revision==3 and not result.value.locked,'desired state committed')
check(api:Find('owner',{requestId='state'}).value.result.value.revision==3,'durable result lookup')
check(api:Mutate('other','retire',{requestId='foreign',reasonCode='test',doorId=id,expectedRevision=3}).code=='not_found','foreign mutation refused')
result=api:Mutate('owner','update',{requestId='suspend',reasonCode='test',doorId=id,expectedRevision=3,status='suspended'})
check(result.ok and result.value.delegationEpoch==2,'suspension invalidates epoch')
check(api:Mutate('owner','state',{requestId='blocked',reasonCode='test',doorId=id,expectedRevision=4,locked=true}).code=='suspended','suspended group cannot change lock')
result=api:Mutate('owner','retire',{requestId='retire',reasonCode='test',doorId=id,expectedRevision=4})
check(result.ok and result.value.status=='retired' and result.value.revision==5 and result.value.delegationEpoch==3,'terminal retirement')
check(api:Mutate('owner','update',{requestId='revive',reasonCode='test',doorId=id,expectedRevision=5,status='active'}).code=='retired','cannot resurrect retired group')
check(api:Mutate('owner','create',create).value.revision==1,'historical receipt remains original snapshot')
enabled=false
check(api:Get('owner',{doorId=id}).code=='unavailable','readiness loss denies reads')
check(api:Mutate('owner','create',create).code=='unavailable','readiness loss denies receipt replay')
enabled=true; duplicate=true
changed=copy(create); changed.requestId='duplicate'
check(api:Mutate('owner','create',changed).code=='definition_conflict','confirmed unique conflict reported')
check(not data.receipts['owner/duplicate'],'conflict transaction rolled back receipt')
duplicate=false; unknown=true; changed.requestId='unknown'
check(api:Mutate('owner','create',changed).code=='pending_recovery','unknown transaction result not assumed rollback')
unknown=false
check(not data.receipts['owner/unknown'],'mock exception rolled back')
revokeDuringWrite=true; data.groups[id].status='active'
check(api:Mutate('owner','state',{requestId='revoked',reasonCode='test',doorId=id,expectedRevision=5,locked=true}).code=='unavailable',
    'authority revalidated before transaction commit')
check(not data.receipts['owner/revoked'] and data.groups[id].revision==5,'revocation rolls back all writes')
check(not data.outbox['owner/revoked'],'event rolls back with revoked mutation')
revokeDuringWrite=false; enabled=true
-- A committed result with a lost reply must be recoverable without new writes.
data.groups[id].status='active'
loseAfterCommit=true
local lost=api:Mutate('owner','state',{requestId='lost',reasonCode='test',doorId=id,expectedRevision=5,locked=true})
check(lost.code=='pending_recovery','lost commit reply remains unknown')
check(api:Find('owner',{requestId='lost'}).value.result.value.revision==6,'committed mutation recovered')
check(api:Mutate('owner','state',{requestId='lost',reasonCode='test',doorId=id,expectedRevision=5,locked=true}).value.revision==6
    and data.groups[id].revision==6,'lost reply retry does not repeat state mutation')
failOutbox=true
check(api:Mutate('owner','state',{requestId='outbox-fail',reasonCode='test',doorId=id,expectedRevision=6,locked=false}).code=='pending_recovery','outbox failure never reports mutation success')
check(data.groups[id].revision==6 and not data.receipts['owner/outbox-fail'] and not data.outbox['owner/outbox-fail'],
    'outbox failure rolls back group, receipt and event')
failOutbox=false
data.outbox['owner/create']=nil
check(api:Mutate('owner','create',create).value.revision==1 and not data.outbox['owner/create'],'old receipt replay does not fabricate event backfill')
-- Exercise the real operator fixture through mocked Cfx exports. Worker calls
-- run sequentially here; only MariaDB live acceptance establishes row contention.
data={groups={},leaves={},receipts={},outbox={}}
local fixtureCommands,messages={},{}
local methods={CreateDoorGroup='create',UpdateDoorGroup='update',DeleteDoorGroup='retire',SetLockState='state'}
local fixtureAllowed=false
local fixtureCaller='feather-doors-api-tests'
local targetAdapter
exports={['feather-doors']=setmetatable({},{__index=function(_,name)
    return function(_,spec)
        if not fixtureAllowed then return C.Err('forbidden') end
        local caller=fixtureCaller
        if methods[name] then return api:Mutate(caller,methods[name],spec) end
        if name=='FindDoorByKey' then return api:Get(caller,spec,true) end
        if name=='GetDoorGroup' then return api:Get(caller,spec) end
        if name=='ListDoorGroups' then return api:List(caller,spec) end
        if name=='FindOperation' then return api:Find(caller,spec) end
        if name=='GetOperationEvent' then return api:Event(caller,spec) end
        if name=='GetDoorTargetContext' then return targetAdapter:Context(caller,spec) end
        error('unknown export')
    end
end})}
RegisterCommand=function(name,handler) fixtureCommands[name]=handler end
CreateThread=function(handler) handler() end
GetGameTimer=function() return 1000 end
Wait=function() error('unexpected fixture wait') end
local actualPrint=print
print=function(message) messages[#messages+1]=message end
dofile('../feather-doors-api-tests/server.lua')
fixtureCommands.DoorsApiSmokeTest(0,{'denied'})
fixtureAllowed=true
fixtureCommands.DoorsApiSmokeTest(0,{'run'})
fixtureCommands.DoorsApiSmokeTest(0,{'verify'})
print=actualPrint
for _,message in ipairs(messages) do check(not message:find('FAIL',1,true),'fixture scenario no failures') end
check(messages[#messages]:find('3/3 passed',1,true)~=nil,'fixture restart verification scenario completes')
-- Execute the real outbox fixture against the repository and publisher, using
-- in-memory SQL/JSON and a broker callback boundary. Real Core is tested in
-- events_spec; only the live gate proves MariaDB and Cfx integration together.
data={groups={},leaves={},receipts={},outbox={}}
fixtureCaller='feather-doors-outbox-tests'
local subscriptions={}
exports['feather-core']={SubscribeEvent=function(_,name,callback)
    subscriptions[name]=subscriptions[name] or {}; table.insert(subscriptions[name],callback)
    return C.Ok({token=name..':'..#subscriptions[name]})
end}
function db.query()
    local rows={}; for _,row in pairs(data.outbox) do if row.status=='pending' then rows[#rows+1]=copy(row) end end
    return rows
end
function db.exec(sql,eventId)
    for _,row in pairs(data.outbox) do
        if row.event_id==eventId then
            row.attempts=row.attempts+1
            if sql:find("'published'",1,true) then row.status='published' end
        end
    end
end
local publisher=DoorsEvents.New(db,function(name,payload)
    local delivered,failed=0,0
    for _,callback in ipairs(subscriptions[name] or {}) do
        if pcall(callback,copy(payload),{publisher='feather-doors'}) then delivered=delivered+1 else failed=failed+1 end
    end
    return C.Ok({delivered=delivered,failed=failed})
end,function() return true end)
messages={}; print=function(message) messages[#messages+1]=message end
dofile('../feather-doors-outbox-tests/server.lua')
fixtureCommands.DoorsEventSmokeTest(0,{'seed'})
local drained=publisher:Drain()
fixtureCommands.DoorsEventSmokeTest(0,{'retry'})
subscriptions={}; dofile('../feather-doors-outbox-tests/server.lua')
fixtureCommands.DoorsEventSmokeTest(0,{'watch'})
local retried=publisher:Drain()
fixtureCommands.DoorsEventSmokeTest(0,{'verify'})
fixtureAllowed=false; fixtureCommands.DoorsEventSmokeTest(0,{'denied'})
print=actualPrint
check(drained.ok and drained.value.published==3 and drained.value.retried==1,'outbox fixture controlled listener failure')
check(retried.ok and retried.value.published==1,'outbox fixture pending replay')
for _,message in ipairs(messages) do check(not message:find('FAIL',1,true),'actual outbox fixture no assertion failure') end
check(messages[#messages]=='[doors-outbox-tests] completed denied','outbox fixture final denial completes')
-- Preserve the same four facts and recover the exact live quarantine history.
for _,row in pairs(data.outbox) do row.status='quarantined'; row.attempts=1 end
check(DoorsEvents.RecoverFixture(db).value.requeued==4,'existing fixture quarantine requeued transactionally')
fixtureAllowed=true; subscriptions={}; messages={}
print=function(message) messages[#messages+1]=message end
dofile('../feather-doors-outbox-tests/server.lua')
fixtureCommands.DoorsEventSmokeTest(0,{'recover'})
drained=publisher:Drain(); fixtureCommands.DoorsEventSmokeTest(0,{'retry'})
subscriptions={}; dofile('../feather-doors-outbox-tests/server.lua')
fixtureCommands.DoorsEventSmokeTest(0,{'watch'})
retried=publisher:Drain(); fixtureCommands.DoorsEventSmokeTest(0,{'verify'})
print=actualPrint
check(drained.value.published==3 and drained.value.retried==1 and retried.value.published==1,'recovered fixture failure/restart/retry scenario')
for _,message in ipairs(messages) do check(not message:find('FAIL',1,true),'actual recovered fixture no assertion failure') end
check(messages[#messages]=='[doors-outbox-tests] completed verify','recovered fixture verification completes')
-- Real lifecycle fixture through real repository/adapter, mocked Access transport.
dofile('server/access.lua')
data={groups={},leaves={},receipts={},outbox={}}
fixtureCaller='feather-doors-access-tests'
local provider,providerGeneration=nil,0
function db.one(_,targetId) return data.groups[targetId] and copy(data.groups[targetId]) end
targetAdapter=DoorsAccess.New(db,{available=function() return true end,call=function(name,request)
    if name=='AwaitReady' then return C.Ok(true) end
    if name=='GetCapabilities' then return C.Ok({contract=1}) end
    if name=='RegisterTargetProvider' then provider=request;providerGeneration=providerGeneration+1;return C.Ok(true) end
    if name=='UnregisterTargetProvider' then provider=nil;return C.Ok(true) end
    if name=='ResolveTargetContext' then
        local result=provider.resolve(request)
        if result.ok then result.value.provider={resource='feather-doors',contract=1,generation=providerGeneration} end
        return result
    end
end},function() return true end)
exports['feather-access']={ResolveTargetContext=function() return C.Err('authorization_denied') end,
    GrantCapability=function() return C.Err('authorization_denied') end}
fixtureAllowed=false;messages={};print=function(message) messages[#messages+1]=message end
dofile('../feather-doors-access-tests/server.lua')
fixtureCommands.DoorsAccessSmokeTest(0,{'denied'})
fixtureAllowed=true;targetAdapter:Register()
fixtureCommands.DoorsAccessSmokeTest(0,{'run'})
targetAdapter:Unregister();fixtureCommands.DoorsAccessSmokeTest(0,{'unregistered'})
targetAdapter:Register();fixtureCommands.DoorsAccessSmokeTest(0,{'verify'})
fixtureAllowed=false;fixtureCommands.DoorsAccessSmokeTest(0,{'denied'})
print=actualPrint
for _,message in ipairs(messages) do check(not message:find('FAIL',1,true),'actual Access lifecycle fixture no assertion failure') end
check(messages[#messages]:find('3/3 passed',1,true)~=nil,'actual Access fixture completes final denial')
print(('PASS %d repository/contract checks'):format(passed))
