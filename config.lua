DoorsConfig = {
    -- Exact server resource names. Each caller manages/reads only its own groups.
    TrustedResources = {},
    -- Acceptance starts with manual server-console drain; resume enables a
    -- bounded 20-row poll each second until pause or Doors restart.
    Outbox = { Enabled=false },
}
