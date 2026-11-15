-- DeckKit.JSON.Decode(text) -> value, or nil + why. JSON from outside the game (an assistant's layouts,
-- UI.Build specs) as plain Lua tables. Data only: nothing in it is ever run. Objects become tables with
-- string keys, arrays 1-based lists, null nil (so a null in an array leaves a hole; specs don't use it).
-- Bounded: at most 64 deep and 64 KB, so a bad or hostile string can't hang the game.
local _, ns = ...

local JSON = {}
ns.JSON = JSON

local MAX_DEPTH, MAX_LEN = 64, 65536
local ESC = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

-- A code point as UTF-8.
local function Utf8(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
    if cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
    end
    return string.char(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64,
        0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

function JSON.Decode(s)
    if type(s) ~= "string" then return nil, "not a string" end
    if #s > MAX_LEN then return nil, "over " .. MAX_LEN .. " bytes" end
    local i = 1
    local Value

    local function Fail(why) error({ why = why .. " at byte " .. i }, 0) end
    local function Space() i = s:find("[^ \t\r\n]", i) or #s + 1 end

    local function String()
        i = i + 1 -- the opening quote
        local out = {}
        while true do
            local j = s:find('["\\]', i)
            if not j then Fail("unfinished string") end
            out[#out + 1] = s:sub(i, j - 1)
            if s:sub(j, j) == '"' then
                i = j + 1
                return table.concat(out)
            end
            local e = s:sub(j + 1, j + 1)
            if ESC[e] then
                out[#out + 1] = ESC[e]
                i = j + 2
            elseif e == "u" then
                local hex = s:sub(j + 2, j + 5)
                if not hex:match("^%x%x%x%x$") then Fail("bad \\u escape") end
                local cp = tonumber(hex, 16)
                i = j + 6
                -- A surrogate pair: two escapes for one code point.
                if cp >= 0xD800 and cp <= 0xDBFF and s:sub(i, i + 1) == "\\u" then
                    local lo = tonumber(s:sub(i + 2, i + 5), 16)
                    if lo and lo >= 0xDC00 and lo <= 0xDFFF then
                        cp = 0x10000 + (cp - 0xD800) * 1024 + (lo - 0xDC00)
                        i = i + 6
                    end
                end
                out[#out + 1] = Utf8(cp)
            else
                Fail("bad escape")
            end
        end
    end

    local function Number()
        local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
        local v = num and tonumber(num)
        if not v then Fail("bad number") end
        i = i + #num
        return v
    end

    function Value(depth)
        if depth > MAX_DEPTH then Fail("too deep") end
        Space()
        local c = s:sub(i, i)
        if c == "{" then
            local t = {}
            i = i + 1
            Space()
            if s:sub(i, i) == "}" then i = i + 1 return t end
            while true do
                Space()
                if s:sub(i, i) ~= '"' then Fail("expected a key") end
                local k = String()
                Space()
                if s:sub(i, i) ~= ":" then Fail("expected :") end
                i = i + 1
                t[k] = Value(depth + 1)
                Space()
                c = s:sub(i, i)
                i = i + 1
                if c == "}" then return t end
                if c ~= "," then Fail("expected , or }") end
            end
        elseif c == "[" then
            local t, n = {}, 0
            i = i + 1
            Space()
            if s:sub(i, i) == "]" then i = i + 1 return t end
            while true do
                n = n + 1
                t[n] = Value(depth + 1)
                Space()
                c = s:sub(i, i)
                i = i + 1
                if c == "]" then return t end
                if c ~= "," then Fail("expected , or ]") end
            end
        elseif c == '"' then
            return String()
        elseif c == "-" or c:match("%d") then
            return Number()
        elseif s:sub(i, i + 3) == "true" then
            i = i + 4
            return true
        elseif s:sub(i, i + 4) == "false" then
            i = i + 5
            return false
        elseif s:sub(i, i + 3) == "null" then
            i = i + 4
            return nil
        end
        Fail("unexpected " .. (c == "" and "end" or ("'" .. c .. "'")))
    end

    local ok, v = pcall(function()
        local out = Value(1)
        Space()
        if i <= #s then Fail("extra text") end
        return out
    end)
    if ok then return v end
    if type(v) == "table" then return nil, v.why end
    return nil, tostring(v)
end
