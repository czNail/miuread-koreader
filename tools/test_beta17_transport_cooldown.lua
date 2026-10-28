package.path='./miuread.koplugin/?.lua;./miuread.koplugin/?/init.lua;'..package.path
package.preload['miuread.http']=function()return {is_auth_error=function(err)return tostring(err):find('401',1,true)~=nil end}end
package.preload['miuread.diagnostic_log']=function()return {record=function()end,now=function()return os.clock()end}end
package.preload['miuread.shelf_client']=function()return {credentials=function()return true end}end
local store={revision=1}
function store:preferences()return {api_transport='auto'}end
function store:auth()return {login_session_id='x',auth_revision=self.revision}end
local Transport=require('miuread.api_transport')
local attempts=0
local native=function() attempts=attempts+1;error('HTTP 401 status=401')end
local web=function()return {ok=true}end
local route=Transport.new(store)
assert(route.selected=='eink')
route:invoke('readreviews',native,web,{phase='annotations'})
assert(attempts==1,'first Native request must be attempted')
route=Transport.new(store)
assert(route.selected=='web','new operation must respect session cooldown')
route:invoke('readreviews',native,web,{phase='annotations'})
assert(attempts==1,'do not repeat known 401')
store.revision=2
route=Transport.new(store)
assert(route.selected=='eink','auth revision must release 401 cooldown')
print('PASS beta17: E-Ink 401 cooldown and auth revision reset')
