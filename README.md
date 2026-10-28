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
fail startup. Migration 002 adds caller-scoped operation receipts; accepted
migration 001 SQL is unchanged. Do not edit accepted migrations or manually mark failed rows applied.
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
and `durableReceipts` become 1 only when the foundation is ready. Health keeps
operational `ready=false` and exposes
`stage='trusted_api_foundation'`, `foundationReady`, `schemaVersion`,
`migrationsApplied`, `migrationsResumed`, and `status='foundation_ready'` on
successful schema startup. A required resource stop latches foundation readiness
off until Doors is restarted. These diagnostic shapes remain provisional.
No player routes or operational AwaitReady are provided. Consumer server APIs
must check foundationReady plus the relevant feature, not operational ready.

Server-console command `DoorsSchemaSmokeTest` is read-only: it verifies migration
checksums/completion, four InnoDB tables and 27 expected column names/types.
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
never issue a new mutation ID to guess whether it committed. No receipt pruning,
Audit integration or outbox delivery is implemented in this slice.

Server-console `DoorsApiFixture enable|disable` grants/revokes only the exact
disposable `feather-doors-api-tests` caller until the next Doors restart. It does
not alter config or enable any player routes. Run the protocol in framework docs
`feather-doors/TRUSTED_API_ACCEPTANCE.md`; leave the fixture disabled afterward.

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
