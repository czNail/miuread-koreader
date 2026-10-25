-- Admission for a NEW, forked book-download worker (including resume).
-- Memory thresholds are not applied to an already-running worker; its
-- separate runtime monitor decides whether to checkpoint/hibernate.
local Admission = {}

function Admission.minimum(config)
    local fresh=tonumber(config and config.HEAVY_DOWNLOAD_START_MIN_KB) or 96*1024
    local resumed=tonumber(config and config.HEAVY_DOWNLOAD_RESUME_MIN_KB) or fresh
    return math.max(1,fresh,resumed)
end

function Admission.check(memory,config)
    local minimum=Admission.minimum(config)
    if type(memory)=="table" then
        local available=tonumber(memory.available_kb)
        if available and available<minimum then
            return false,"low_memory",minimum,available
        end
    end
    -- If the OS does not provide MemAvailable, preserve existing compatibility
    -- behaviour, rather than permanently preventing all downloads.
    return true,nil,minimum,memory and tonumber(memory.available_kb) or nil
end

return Admission
