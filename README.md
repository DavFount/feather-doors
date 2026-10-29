# Feather Doors

Authoritative RedM door domain for the Feather Framework. Version `0.1.0-dev`
contains a headless trusted server API and native proof adapter. Player
interaction and native replication are not enabled.

## Current behavior

Requires `feather-mysql` and Core Contract 1. Startup waits up to 30 seconds for
each provider, then applies the resource-owned schema journal. Trusted resources
can manage their own durable groups and operation receipts. No player mutations,
network routes, background polling, prompts or state replication are enabled. Existing resource data is not
imported. Version remains `0.1.0-dev` during this foundation stage.

`feather_door_groups` stores stable UUID/key, manager, status, desired lock state,
revision, delegation epoch and startup-policy fields. `feather_door_leaves`
reserves a unique native door hash with model/position and one of two group
ordinals. Startup policy is stored only; no policy is applied to native doors.
Unsigned model hashes must eventually be normalized to uint32 at the API boundary.

`feather_door_schema_migrations` journals checksum and applying/applied state.
DDL auto-commits; interrupted same-checksum application can resume. Unknown or
changed migrations, unjournaled domain tables and missing/wrong column types
fail startup. Migration 002 adds caller-scoped operation receipts; migration 003
adds the transactional change outbox. Accepted migration 001/002 SQL is unchanged.
Do not edit accepted migrations or manually mark failed rows applied.
There is no destructive rollback or automatic schema repair.

The internal `client/native.lua` adapter is now available for Phase 0 proof. It
performs no work when loaded and is not exported to consumers. Only the separate
operator-started `feather-doors-native-tests` fixture invokes it. It captures
existing native state/ratio, registers missing leaves, applies explicit lock
states and restores captured state on release. Existing registrations are never
removed; only fixture-created registrations are removed. Failed cleanup retains
its lease for retry. Removal confirmation can be pending across frames; repeated
confirmation does not reissue an already requested removal. Registration reads
accept only boolean values or numeric 0/1 and normalize them to booleans.
This is provisional native behavior, not a ready domain,
authorization API, persistence implementation or multiplayer synchronization.

Offline adapter checks: run `lua54.exe tests/native_spec.lua` from this directory
in PowerShell with Lua 5.4 installed. These checks mock natives and cannot prove
physical door behavior. Live proof instructions are in the sibling framework
documentation repository's `feather-doors/NATIVE_PROOF.md`.

## Diagnostic API

Server only:

```lua
local capabilities = exports['feather-doors']:GetCapabilities()
local health = exports['feather-doors']:GetHealth()
```

Both return fresh tables. Capabilities identifies the resource/version/stage
and reports physical/player features as `false`. `schema`, `trustedDefinitions`
and `durableReceipts`/`changeEvents` become 1 only when the foundation is ready. Health keeps
operational `ready=false` and exposes
`stage='access_target_foundation'`, `foundationReady`, `schemaVersion`,
`migrationsApplied`, `migrationsResumed`, and `status='foundation_ready'` on
successful schema startup. A required resource stop latches foundation readiness
off until Doors is restarted. These diagnostic shapes remain provisional.
No player routes or operational AwaitReady are provided. Consumer server APIs
must check foundationReady plus the relevant feature, not operational ready.

Server-console command `DoorsSchemaSmokeTest` is read-only: it verifies migration
checksums/completion, five InnoDB tables and 39 expected column names/types.
It does not test SQL constraints, transactional CRUD, receipt recovery or native
behavior. Run it again after restarting Doors; first install should log
applied=1/resumed=0 and an ordinary second startup applied=0/resumed=0.
Refresh is required before restarting when installing this manifest change.

## Trusted server API (contract under development)

Set exact caller resource names to true in `DoorsConfig.TrustedResources`.
The shipped map is empty. Caller identity comes from GetInvokingResource, never
from a request field. Each caller manages/reads only its own groups and receipts;
there is no cross-manager staff override. Calls fail unavailable on foundation
loss and revalidate before committing after yields. Configuration is a trusted
server boundary, not player authorization or a distributed revocation fence.
All calls return `{ok=true,value=...}` or `{ok=false,code,message}`.

| Export | Request |
| --- | --- |
| CreateDoorGroup | requestId, reasonCode, key, label, locked:boolean, startupPolicy? (default preserve), leaves (1–2) |
| UpdateDoorGroup | requestId, reasonCode, doorId, expectedRevision; at least one label/status/startupPolicy |
| SetLockState | requestId, reasonCode, doorId, expectedRevision, locked:boolean |
| DeleteDoorGroup | requestId, reasonCode, doorId, expectedRevision |
| GetDoorGroup | doorId |
| FindDoorByKey | key |
| ListDoorGroups | limit? (1–50, default 20), after? (UUID cursor) |
| FindOperation | requestId |
| GetOperationEvent | requestId |
| GetDoorTargetContext | doorId (caller-managed group; registered Access provider required) |
| GetControlledDoor | key (exact configured service-controller scope) |
| SetControlledLockState | key, expectedRevision, locked:boolean, requestId, reasonCode |
| FindControlledOperation | key, requestId (exact service scope and caller receipt) |

Leaves contain `hash`, `model` (uint32 integers), `x`, `y`, `z` (bounded finite
numbers). They are copied on validation. Keys/leaf identity/geometry/manager are
immutable in this slice. Update status accepts active or suspended; deletion is
terminal retirement, not physical removal. Status transitions advance delegation
epoch; every successful mutation advances revision. Retired groups retain leaf
reservations; hash reuse/purge is not supported. Startup policy remains stored
only. SetLockState changes SQL desired state, not a physical/native door.

Snapshots contain doorId/key/label/status/locked/revision/delegationEpoch/
startupPolicy/leaves. List returns summary groups plus nextCursor (false at end);
cursor paging is not a frozen multi-request snapshot. FindOperation returns
`value.result`, the original mutation envelope. Replays return historical result
snapshots, not fresh group state. Use GetDoorGroup for current state.

Mutation receipts are keyed by actual caller plus requestId and bind a canonical
normalized request including operation/reason. Identical retries return the
original result; changed payload is request_conflict. Stale/retired/not-found
results are durable too; a corrected operation needs a new requestId. Unique
key/hash collision with confirmed rollback returns definition_conflict. Unknown
database/commit outcomes return pending_recovery: look up/retry the same request,
never issue a new mutation ID to guess whether it committed. No receipt pruning
or Audit integration is implemented. GetOperationEvent returns the caller's
eventId/eventType/payload/status/attempts for a successful mutation. Historical
operations from before migration003 have no fabricated events or backfill.

Server-console `DoorsApiFixture enable|disable` grants/revokes only the exact
disposable `feather-doors-api-tests` caller until the next Doors restart. It does
not alter config or enable any player routes. Run the protocol in framework docs
`feather-doors/TRUSTED_API_ACCEPTANCE.md`; leave the fixture disabled afterward.

## Committed change notifications

Successful mutations write one outbox row in the same transaction as group and
receipt. Replays and rejected mutations do not add events. Rows retain stable
event IDs, caller/request correlation, minimal status/revision/epoch/locked facts,
and publication status. Keys, labels, leaves, player identity and grant data are
not included. Core declares `doors.definition.changed.v1` for create/update/
retirement and `doors.state.changed.v1` for SetLockState. Payload contract is 1.

Subscribers use Core SubscribeEvent; only the declaring Doors resource may
publish. Treat events as invalidations, not authorization or physical state.
Reread the appropriate authority, deduplicate eventId and handle older revisions:
global/per-door delivery ordering is not promised. Manager-scoped reads remain
enforced; subscribing does not grant access to another manager's data.

Publisher acknowledges only Core ok with zero failed listeners. A listener error
retries the stable ID after five seconds, including to previously successful
listeners. Successful broker acceptance with zero subscribers also publishes the
row. This is at-least-once publication, not durable per-consumer delivery or Audit
ingestion. Listeners must handle duplicate IDs and persist their own workflow
receipts where needed. Offline subscribers have no automatic catch-up cursor.

`DoorsConfig.Outbox.Enabled` defaults false until acceptance. When enabled, one
serial worker polls each second in batches of at most 20. Acknowledgement loss
can republish after restart. Invalid JSON/identity/payload rows are quarantined,
not silently delivered or deleted. Published/quarantined rows are retained; no
automatic repair/purge is provided. This worker targets a single FXServer domain
instance; shared-database multi-host publication is not a supported contract.

Server-console `DoorsOutbox status|pause|resume|drain` reports aggregate state,
controls the runtime polling flag or processes one batch. Pause affects future
automatic batches; an in-flight batch can finish. Manual drain works while
paused. Runtime pause/resume resets to config on restart. Health includes outbox
enabled/busy/lastCode without doing SQL. Pending events survive ordinary restart;
consumer failure, database failure and Core failure never retroactively undo an
already committed mutation. Core/dependency loss latches the foundation off.

Server-console `DoorsEventFixture enable|disable` temporarily permits only the
separate `feather-doors-outbox-tests` caller, resetting on restart or fixture stop.
The normal API fixture is unchanged. Use the framework OUTBOX_ACCEPTANCE.md
protocol; the first listener failure is deliberate and expected.

Persisted JSON is decoded and copied through bounded raw iteration into plain
tables before strict validation. The running lua-rapidjson decoder retains object
metadata despite dkjson-style nil metadata arguments; the installed legacy
json.lua file alone does not identify the active codec. Ordinary API requests
still reject metatables. Trailing garbage, scalar and
oversized stored JSON are refused. The installed runtime decoder is exercised
by tests/runtime_json_spec.lua (supply its json.lua path as argument1).

Server-console `DoorsOutbox recover-fixture` is a narrowly scoped repair for the
four existing doors-outbox-v1 acceptance facts. It requires paused/idle publishing,
validates every payload/row against its original successful receipt under row
locks, then requeues only quarantined rows. Pending/published rows are unchanged;
IDs, payloads, receipts, group data and attempts are never rewritten. It is not
a generic quarantine replay or payload repair API. Do not reseed the used fixture.

## Optional Access target provider

Access config must declare doors.group owner feather-doors, vocabulary door.lock/
door.unlock and Providers.TrustedReaders['feather-doors']=true. No grant reader,
manager or Core service policy is added. Access is optional; base Doors still
starts without it. This provider enables target facts, not player authorization.

Server-console DoorsAccess register|unregister|status controls explicit provider
registration. It starts unregistered. Duplicate registration refuses replacement;
Access stop invalidates local state. Use explicit re-registration after recovery,
not broad sibling restarts. Health exposes access registered/lastCode and
capabilities exposes accessTargetProvider. None is a permission token.

GetDoorTargetContext returns Access's targetType/targetId/epoch/status/
capabilities/provider envelope, checking current manager and facts before/after
yields. Suspension/resumption/retirement advance epoch; metadata does not.
CheckDoorAccess is not implemented; grantManagement/playerAuthorization stay
false. Grant-management callback denies all requests until a separate actor/
Property/staff contract is proven. Managing a definition confers no grant rights.

Server-console DoorsAccessFixture enable|disable permits only the isolated
feather-doors-access-tests caller until restart/fixture stop. That fixture has no
direct Access reader/manager trust. Framework ACCESS_TARGET_ACCEPTANCE.md owns
the coordinated Access/Doors activation and headless test protocol.

## Global service control

Configure DoorsConfig.ServiceControllers as exact resource -> exact key -> true.
For example, bcc-banks could be allowed only global.valentine.bank.entry. The map
ships empty. This policy is for trusted server-service state control; it is not
a second player grant ledger. No wildcard, actor spoofing or client registration.

GetControlledDoor returns only doorId/key/status/locked/revision/delegationEpoch.
SetControlledLockState changes desired SQL state through the normal receipt and
revision pipeline, even for a definition managed by a different resource. It
does not edit identity/metadata, retire a definition or issue access. Public owner
APIs remain manager-only. FindControlledOperation returns the original result
only if it is tagged with that exact controlKey and caller. Check current state
separately; historical replays are not fresh state. Configuration revocation is
rechecked after yields before commit, not advertised as a distributed fence.

The banking service chooses its approved clock and public hours. Doors supplies
no scheduler or implicit job permission. Use desired states, expected revisions
and stable IDs per immutable request. Do not blindly overwrite stale revisions or
repeat unknown outcomes under new IDs. Successful service mutations emit the
existing state event with operation=control; payload consumers must accept this
additional contract1 operation. No SQL schema change is required.

Native replication remains disabled: these APIs do not physically open the bank
yet. Global native door state is shared; permitted unlock is not per-player
passage isolation. Employee access will require explicitly issued Access grants,
not job membership alone. Property/staff grant-management implementation remains
disabled, as designed in framework GRANT_AUTHORITY_DESIGN.md.

Console-only DoorsControllerFixture enable|disable temporarily permits separate
owner/controller test resources for one synthetic key, resetting on restart or
either fixture stop. See framework SERVICE_CONTROL_ACCEPTANCE.md. No real bank
resource is enabled by this fixture or the default config.

## Resource ownership

Doors will own registered identities, grouped leaves, authoritative lock state,
authorization decisions, persistence, native synchronization and basic player
interaction. Consumers will use its server API; optional key, lockpick, property
and staff adapters retain their respective domain responsibilities.
`bcc-doorlocks` is reference material and is not a runtime dependency.

Architecture, implementation plans and acceptance evidence live in
`feather-framework-docs/feather-doors/FEATHER_DOORS_MASTER_PLAN.md` in the sibling
documentation repository. Native bank cleanup and physical lock/unlock have
operator acceptance; schema startup/SQL and full domain behavior remain separate
acceptance gates. Follow the current checkpoint rather than historical tests.

## License

GNU GPL v3; see LICENSE.
