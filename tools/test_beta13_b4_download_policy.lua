-- Execute with: texlua tools/test_beta13_b4_download_policy.lua miuread.koplugin/main.lua
local filename=assert(arg[1])
local f=assert(io.open(filename,"rb"));local source=f:read("*a");f:close()
-- Isolate the production policy function, without initializing KOReader UI.
local snippet=assert(source:match('(local function b4_content_only_options.-\nend)\n\nfunction Plugin:choose_download_mode'),"missing B4 policy function")
local factory=assert(load([[
local function copy(v)
  if type(v)~="table" then return v end
  local out={}
  for k,x in pairs(v) do out[k]=copy(x) end
  return out
end
local U={copy=copy}
]]..snippet..'\nreturn b4_content_only_options'))
local normalize=factory()
local previous={annotations=true,annotation_requested=true,annotation_pending=true,
  annotation_fallback=true,annotation_only=true,chapter_uid="abc",images=false,
  range_start_index=4,range_end_index=8,nested={x=1}}
local cleaned=normalize(previous)
assert(cleaned.annotations==false)
assert(cleaned.annotation_requested==nil and cleaned.annotation_pending==nil)
assert(cleaned.annotation_fallback==nil and cleaned.annotation_only==nil)
assert(cleaned.chapter_uid=="abc" and cleaned.images==false)
assert(cleaned.range_start_index==4 and cleaned.range_end_index==8)
assert(cleaned.nested.x==1)
cleaned.nested.x=2
assert(previous.annotations==true and previous.nested.x==1,"must not mutate old task")
assert(normalize(nil).annotations==false)
print("B4 download policy: 12 assertions passed")
