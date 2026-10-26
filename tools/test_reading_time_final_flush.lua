-- Run on KOReader from its directory:
--   ./luajit <repo>/tools/test_reading_time_final_flush.lua <repo>/miuread.koplugin
-- The reading-end progress preempt must let an already requested final
-- reading-time flush settle (bounded) before stopping the time service.
require('setupkoenv')
local plugin=assert(arg[1],'plugin path required')
package.path=plugin..'/?.lua;'..package.path
-- Device modules loaded by sync.lua expect KOReader's global settings.
local settings_tmp=os.tmpname()
G_reader_settings=G_reader_settings or require('luasettings'):open(settings_tmp)
if not G_defaults then local ok,d=pcall(require,'luadefaults'); if ok then G_defaults=d:open() end end
-- Never initialise the real device layer (input, framebuffer) from a test.
local inert=setmetatable({},{__index=function() return function() end end})
package.loaded['device']=setmetatable({model='test',screen=inert,input=inert,powerd=inert},{__index=function(_,k)
    if type(k)=='string' and (k:match('^is') or k:match('^has') or k:match('^can')) then return function() return false end end
end})
local queue={}
package.loaded['ui/uimanager']={
    scheduleIn=function(_,_,fn) queue[#queue+1]=fn end,
    nextTick=function(_,fn) queue[#queue+1]=fn end,
    unschedule=function() end,
}
local Sync=require('miuread.sync')
local function drain()
    local ran=0
    while #queue>0 do table.remove(queue,1)(); ran=ran+1; assert(ran<1000,'runaway scheduling') end
    return ran
end
local function make(pending,settle_after)
    local obj=setmetatable({daemon={final_flush_pending=pending,book_id='1'},async=nil},Sync)
    obj.cancel_writer_barrier_waits=function() obj.barrier_cancelled=true end
    obj.imports=0
    obj._import_daemon_status=function(self,force)
        assert(force==false,'final flush wait forced a session persist')
        self.imports=self.imports+1
        if settle_after and self.imports>=settle_after then self.daemon.final_flush_pending=false end
    end
    return obj
end
local function run(obj)
    local result
    assert(obj:preempt_reading_time_for_progress('test',function(ok,meta) result={ok=ok,meta=meta} end))
    return result
end

-- No final flush pending: unchanged, immediate preempt.
local obj=make(false)
local r=run(obj)
assert(r and r.ok and obj.imports==0 and obj.barrier_cancelled,'no-flush preempt changed')

-- Pending flush settles on the third status read: preempt only afterwards.
obj=make(true,3)
r=run(obj)
assert(r==nil and not obj.barrier_cancelled,'preempted before the final flush settled')
local function run_until_done(o)
    local result
    queue={}
    assert(o:preempt_reading_time_for_progress('test',function(ok,meta) result={ok=ok,meta=meta} end))
    drain()
    return result
end
obj=make(true,3)
r=run_until_done(obj)
assert(r and r.ok and obj.imports==3 and obj.barrier_cancelled,'settled flush did not continue the preempt')

-- Never settles: bounded wait, then the original drop policy.
obj=make(true,nil)
r=run_until_done(obj)
assert(r and r.ok and obj.imports==24 and obj.barrier_cancelled,'timeout did not fall back after 24 polls: '..obj.imports)

-- The daemon is replaced while waiting: continue without importing more.
obj=make(true,nil)
queue={}
local done
assert(obj:preempt_reading_time_for_progress('test',function(ok) done=ok end))
obj.daemon=nil
drain()
assert(done==true and obj.imports==1,'replaced daemon kept waiting')

os.remove(settings_tmp)
print('reading-time final flush: settles before preempt, bounded fallback, unchanged without flush: PASS')
