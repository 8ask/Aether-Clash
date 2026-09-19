local TweenService = game:GetService("TweenService")
local Util = {}

local SUFFIX = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx" }

function Util.abbrev(n)
    n = math.floor(tonumber(n) or 0)
    if n < 0 then return "-" .. Util.abbrev(-n) end
    if n < 1000 then return tostring(n) end
    local i = math.min(#SUFFIX, math.floor(math.log(n, 1000)))
    local v = n / (1000 ^ i)
    local s
    if v >= 100 then s = string.format("%.0f", v)
    elseif v >= 10 then s = string.format("%.1f", v)
    else s = string.format("%.2f", v) end
    s = s:gsub("%.0+$", ""):gsub("(%.%d)0$", "%1")
    return s .. SUFFIX[i]
end
function Util.cash(n) return "$" .. Util.abbrev(n) end

function Util.tween(inst, time, props, style, dir)
    local tw = TweenService:Create(inst,
        TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end

function Util.lerp(a, b, t) return a + (b - a) * t end

return Util

