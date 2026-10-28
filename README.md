# Feather Doors

Authoritative RedM door domain for the Feather Framework. Version `0.1.0-dev`
contains the schema foundation and native proof adapter. It is not yet a working
door-lock service.

## Current behavior

Requires `feather-mysql` and Core Contract 1. Startup waits up to 30 seconds for
each provider, then creates the resource-owned migration journal and empty
group/leaf tables. No door records, player mutations, network routes, background
polling, prompts or state replication are enabled. Existing resource data is not
imported. Version remains `0.1.0-dev` during this foundation stage.

`feather_door_groups` stores stable UUID/key, manager, status, desired lock state,
revision, delegation epoch and startup-policy fields. `feather_door_leaves`
reserves a unique native door hash with model/position and one of two group
ordinals. Startup policy is stored only; no policy is applied to native doors.
Unsigned model hashes must eventually be normalized to uint32 at the API boundary.

`feather_door_schema_migrations` journals checksum and applying/applied state.
DDL auto-commits; interrupted same-checksum application can resume. Unknown or
changed migrations, unjournaled domain tables and missing/wrong column types
fail startup. Do not edit accepted migrations or manually mark failed rows applied.
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
and reports all operational features as `false`. `schema` becomes 1 only when
the foundation is ready. Health keeps `ready=false` and exposes
`stage='schema_foundation'`, `foundationReady`, `schemaVersion`,
`migrationsApplied`, `migrationsResumed`, and `status='foundation_ready'` on
successful schema startup. A required resource stop latches foundation readiness
off until Doors is restarted. These diagnostic shapes remain provisional.
No mutation exports or operational AwaitReady are provided.

Server-console command `DoorsSchemaSmokeTest` is read-only: it verifies migration
checksums/completion, three InnoDB tables and 22 expected column names/types.
It does not test SQL constraints, transactional CRUD, receipt recovery or native
behavior. Run it again after restarting Doors; first install should log
applied=1/resumed=0 and an ordinary second startup applied=0/resumed=0.
Refresh is required before restarting when installing this manifest change.

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
