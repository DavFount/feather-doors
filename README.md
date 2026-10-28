# Feather Doors

Authoritative RedM door domain for the Feather Framework. Version `0.1.0-dev`
is an inert scaffold, not a working door-lock resource.

## Current behavior

Loads shared metadata and server diagnostics. It does not register or modify
doors, accept network requests, persist data, run background loops or display
player interactions. No runtime dependencies are required by this scaffold.
Future dependencies will be declared after their actual contracts are verified.

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
and reports all operational features as `false`. Health returns `ready = false`,
`status = 'not_implemented'` and `stage = 'scaffold'`. A started scaffold does
not establish domain readiness. These diagnostic shapes are provisional until
the first operational contract is defined. No mutation exports are provided.

## Resource ownership

Doors will own registered identities, grouped leaves, authoritative lock state,
authorization decisions, persistence, native synchronization and basic player
interaction. Consumers will use its server API; optional key, lockpick, property
and staff adapters retain their respective domain responsibilities.
`bcc-doorlocks` is reference material and is not a runtime dependency.

Architecture, implementation plans and acceptance evidence live in
`feather-framework-docs/feather-doors/FEATHER_DOORS_MASTER_PLAN.md` in the sibling
documentation repository. This resource has not been deployed or accepted live.

## License

GNU GPL v3; see LICENSE.
