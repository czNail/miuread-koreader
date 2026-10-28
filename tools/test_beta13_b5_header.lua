-- B5 pure geometry regression. No KOReader display backend required.
package.path = "miuread.koplugin/?.lua;miuread.koplugin/?/init.lua;" .. package.path
local layout=require("miuread.home_header_layout")
local function verify(width,inputs,gap)
    local row=layout.arrange(width,inputs,gap)
    local previous_end=0
    local gaps={}
    for i,item in ipairs(row) do
        assert(item.x>=previous_end,"Header item overlap: "..tostring(item.key))
        assert(item.x+item.width<=width,"Header item overflow: "..tostring(item.key))
        if i>1 then gaps[#gaps+1]=item.x-previous_end end
        previous_end=item.x+item.width
    end
    for i=2,#gaps do assert(math.abs(gaps[i]-gaps[1])<=1,"Uneven visual gaps") end
    return row
end
local full={
    {key="title",width=70,priority=0},{key="account",width=125,priority=4},
    {key="wifi",width=46,priority=0},{key="bluetooth",width=46,priority=5},
    {key="sync",width=100,priority=3},{key="battery",width=88,priority=2},
    {key="tools",width=46,priority=0},
}
local full_row=verify(800,full,12)
assert(#full_row==7,"Full mode lost cells")
assert(full_row[1].x==0,"Unbalanced left inset")
assert(full_row[#full_row].x+full_row[#full_row].width==800,"Unbalanced right inset")
local narrow=verify(485,full,10)
assert(#narrow<7,"Narrow screens must compact rather than overlap")
assert(narrow[1].key=="title" and narrow[#narrow].key=="tools","Keep navigation on narrow screens")
local hidden=verify(800,{{key="wifi",width=46},{key="battery",width=80}},12)
assert(#hidden==2 and hidden[1].x==0 and hidden[2].x+hidden[2].width==800)
local one=verify(800,{{key="wifi",width=46}},12)
assert(one[1].x==377,"Single icon should be centered")
local none=verify(800,{},12)
assert(#none==0)
print("B5 header geometry tests passed")
