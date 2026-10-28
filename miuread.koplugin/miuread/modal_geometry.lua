-- Geometry helpers for ink-screen transient windows.  Pure Lua; no KOReader UI dependencies.
local M = {}
local function finite(v)
    v = tonumber(v)
    return v and v == v and v ~= math.huge and v ~= -math.huge and v or nil
end
function M.rect(r, margin, screen_w, screen_h)
    if not r then return nil end
    local x, y, w, h = finite(r.x), finite(r.y), finite(r.w), finite(r.h)
    if not x or not y or not w or not h or w <= 0 or h <= 0 then return nil end
    margin = math.max(0, finite(margin) or 0)
    local l, t, right, bottom = math.floor(x - margin), math.floor(y - margin),
        math.ceil(x + w + margin), math.ceil(y + h + margin)
    if screen_w then l, right = math.max(0, l), math.min(screen_w, right) end
    if screen_h then t, bottom = math.max(0, t), math.min(screen_h, bottom) end
    if right <= l or bottom <= t then return nil end
    return {x=l, y=t, w=right-l, h=bottom-t}
end
function M.union(a, b)
    if not a then return b end
    if not b then return a end
    local l, t = math.min(a.x,b.x), math.min(a.y,b.y)
    return {x=l, y=t, w=math.max(a.x+a.w,b.x+b.w)-l,
        h=math.max(a.y+a.h,b.y+b.h)-t}
end
-- Reduce only the genuinely scalable metrics.  Never claim a clipped frame is valid.
function M.scale_to_fit(available, values, floor_value)
    local sum = 0
    for _, v in ipairs(values) do sum = sum + math.max(0, tonumber(v) or 0) end
    if sum <= available then return values, true end
    local ratio = available / math.max(1, sum)
    local result, used = {}, 0
    for i, v in ipairs(values) do
        result[i] = math.max(floor_value or 1, math.floor(v * ratio))
        used = used + result[i]
    end
    return result, used <= available
end
return M
