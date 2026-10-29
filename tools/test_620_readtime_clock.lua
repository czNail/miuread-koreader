-- Behavioral test for 6.2 periodic time reports and reader-close tail.
-- Offline only: no WeRead authentication and no KOReader device required.
package.path='./miuread.koplugin/?.lua;./miuread.koplugin/?/init.lua;'..package.path
local real_time=os.time
local now=1000
os.time=function() return now end
local reports,files={},{}
local job={generation=1,controller_token='tok',login_session_id='login',auth_revision=1,
 account_vid='acct',book_id='b',core_map_hash='hash',record_generation=1,
 book_path='file.epub',time_only=true,report_mode='reading_time_compat',
 book={},auth={cookies={a='b'}},interval=60,first_delay=15,idle_timeout=600}
local control={generation=1,controller_token='tok',login_session_id='login',auth_revision=1,
 account_vid='acct',book_id='b',core_map_hash='hash',record_generation=1,
 time_only=true,active=true,last_activity=1000}
files.job=job; files.control=control
local function cp(o)
 if type(o)~='table' then return o end
 local v={};for k,x in pairs(o) do v[k]=cp(x) end;return v
end
package.loaded['miuread.json']={encode=cp,decode=cp}
package.loaded['miuread.util']={copy=cp,
 read_file=function(p) return files[p] end,
 atomic_write=function(p,v) files[p]=cp(v);return true end,
 file_exists=function(p) return p=='stop' and now>=1170 end}
package.loaded['miuread.subprocess_hygiene']={reset_resolver=function()end}
package.loaded['miuread.legacy_adapter_worker']={run=function(v)
 reports[#reports+1]={at=now,elapsed=v.elapsed_seconds,mode=v.report_mode,only=v.time_only}
 return {accepted=true,request_dispatched=true,meta={request_dispatched=true}}
end}
package.loaded.socket={sleep=function()
 now=now+1
 if now==1158 then
  control.active=false;control.flush_seq=1;control.flush_auto=true
  control.flush_reason='close'
 end
end}
local Service=require('miuread.read_report_service')
assert(Service.run{job_path='job',control_path='control',status_path='status',context_path='context',stop_path='stop',
 heartbeat_path='heartbeat',poll_interval=1})
assert(#reports==4,'expected 3 periodic reports and one final close flush, got '..#reports)
assert(reports[1].at==1015 and reports[1].elapsed==15,'first 15s report missing')
assert(reports[2].at==1075 and reports[2].elapsed==60,'first 60s interval missing')
assert(reports[3].at==1135 and reports[3].elapsed==60,'second 60s interval missing')
assert(reports[4].at==1158 and reports[4].elapsed==23,'close tail missing')
local total=0
for _,v in ipairs(reports) do
 assert(v.mode=='reading_time_compat' and v.only==true)
 total=total+v.elapsed
end
assert(total==158,'lost or duplicate reading time: '..tostring(total))
os.time=real_time
print('6.2 periodic 15/60 + final 23 seconds: PASS ('..total..'s)')
