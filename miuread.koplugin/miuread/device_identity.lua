-- Persistent installation identity for WeRead's ordinary Web QR sessions.
-- Not the Native shelf-management deviceId and not the local login_session_id.
-- Generate only from OS entropy; never use math.random or shared identifiers.
local Identity = {}
local KEY = "device_fingerprint"

function Identity.valid(value)
    return type(value) == "string" and #value >= 1 and #value <= 10
        and value:match("^%d+$") ~= nil and tonumber(value) <= 4294967295
end

function Identity.get(store)
    if not store or type(store.get) ~= "function" or type(store.set) ~= "function" then
        return nil, "device settings unavailable"
    end
    local existing = store:get(KEY, "")
    if Identity.valid(existing) then
        if type(store.read_persisted) == "function" then
            local persisted = store:read_persisted(KEY)
            if persisted ~= existing then
                return nil, "existing device identity is not safely persisted"
            end
        end
        return existing
    end

    local source = io.open("/dev/urandom", "rb")
    if not source then return nil, "secure device randomness unavailable" end
    local ok, bytes = pcall(source.read, source, 4)
    source:close()
    if not ok or type(bytes) ~= "string" or #bytes ~= 4 then
        return nil, "secure device randomness read failed"
    end
    local a, b, c, d = bytes:byte(1, 4)
    local fingerprint = string.format("%.0f", ((a * 256 + b) * 256 + c) * 256 + d)
    local saved, err = store:set(KEY, fingerprint)
    if saved ~= true then
        return nil, "device identity save failed: " .. tostring(err or "unknown")
    end
    -- QR credentials must never be issued under an identity that only existed
    -- in memory. Store's disk validation catches interrupted writes.
    if type(store.read_persisted) == "function" then
        local persisted, read_err = store:read_persisted(KEY)
        if persisted ~= fingerprint then
            return nil, "device identity verification failed: " .. tostring(read_err or "not persisted")
        end
    end
    return fingerprint
end

return Identity
