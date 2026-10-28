# Feather Doors

Authoritative RedM door domain for the Feather Framework. Version `0.1.0-dev`
is an inert scaffold, not a working door-lock resource.

## Current behavior

Loads shared metadata and server diagnostics. It does not register or modify
doors, accept network requests, persist data, run background loops or display
player interactions. No runtime dependencies are required by this scaffold.
Future dependencies will be declared after their actual contracts are verified.

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
