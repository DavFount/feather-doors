-- Diagnostic exports only. No operational door API is available yet.
exports('GetCapabilities', function()
    return {
        resource = FeatherDoors.Name,
        version = FeatherDoors.Version,
        stage = FeatherDoors.Stage,
        doorRegistration = false,
        lockState = false,
        persistence = false,
        synchronization = false,
        playerInteraction = false
    }
end)

exports('GetHealth', function()
    return {
        resource = FeatherDoors.Name,
        ready = false,
        status = 'not_implemented',
        stage = FeatherDoors.Stage
    }
end)
