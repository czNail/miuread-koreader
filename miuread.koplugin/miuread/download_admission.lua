-- Admission for a NEW, forked book-download worker (including resume).
-- Memory thresholds are not applied to an already-running worker; its
-- separate runtime monitor decides whether to checkpoint/hibernate.
--
-- The minimum scales with MemTotal (see runtime_pressure.compute_thresholds):
-- the absolute config values are only the caps reached on large devices. A
-- 256 MiB device (KPW2 etc.) can never present 96 MiB free, so fixed
-- absolutes meant downloads were permanently unstartable there. A checkpoint
-- restart uses the slightly lower resume line because its worker has already
-- paid most of its setup cost. When the scaled profile cannot load (standalone
-- tests without /proc or its dependencies), fall back to the defensive
-- maximum of the absolute config values.
local thresholds_ok, RuntimePressure = pcall(require, "miuread.runtime_pressure")

local Admission = {}

function Admission.minimum(config, checkpoint)
    if thresholds_ok then
        local thresholds = RuntimePressure.thresholds()
        if checkpoint == true then
            return thresholds.resume_min
        end
        return thresholds.start_min
    end
    local fresh = tonumber(config and config.HEAVY_DOWNLOAD_START_MIN_KB) or 96*1024
    local resumed = tonumber(config and config.HEAVY_DOWNLOAD_RESUME_MIN_KB) or fresh
    return math.max(1, fresh, resumed)
end

function Admission.check(memory, config, checkpoint)
    local minimum = Admission.minimum(config, checkpoint)
    if type(memory) == "table" then
        local available = tonumber(memory.available_kb)
        if available and available < minimum then
            return false, "low_memory", minimum, available
        end
    end
    -- If the OS does not provide MemAvailable, preserve existing compatibility
    -- behaviour, rather than permanently preventing all downloads.
    return true, nil, minimum, memory and tonumber(memory.available_kb) or nil
end

return Admission
