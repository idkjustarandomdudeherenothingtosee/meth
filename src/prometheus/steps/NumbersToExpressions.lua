local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Parser = require("prometheus.parser")
local Enums = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local AstKind = Ast.AstKind

local EncryptStrings = Step:extend()
EncryptStrings.Description = "Encrypts strings and converts bytes into unique symbol sequences."
EncryptStrings.Name = "Encrypt Strings (Symbolic)"

function EncryptStrings:init(settings) end

function EncryptStrings:CreateEncrypionService()
    local syms = {"!","@","#","$","%","^","&","*","(",")","-","+","=","{","}"}
    local bytetosymbol = {}
    local symboltobyte = {}
    local c = 0

    for i = 1, #syms do
        for j = 1, #syms do
            for k = 1, #syms do
                if c <= 255 then
                    local s = syms[i] .. syms[j] .. syms[k]
                    bytetosymbol[c] = s
                    symboltobyte[s] = c
                    c = c + 1
                end
            end
        end
    end

    local secret_key_6 = math.random(0, 63)
    local secret_key_7 = math.random(0, 127)
    local secret_key_44 = math.random(0, 17592186044415)
    local secret_key_8 = math.random(0, 255)
    local floor = math.floor

    local function primitive_root_257(idx)
        local g, m, d = 1, 128, 2 * idx + 1
        repeat
            g = g * g * (d >= m and 3 or 1) % 257
            m = m / 2
            d = d % m
        until m < 1
        return g
    end

    local param_mul_8 = primitive_root_257(secret_key_7)
    local param_mul_45 = secret_key_6 * 4 + 1
    local param_add_45 = secret_key_44 * 2 + 1

    local state_45, state_8 = 0, 2
    local prev_values = {}

    local function set_seed(seed)
        state_45 = seed % 35184372088832
        state_8 = seed % 255 + 2
        prev_values = {}
    end

    local function get_random_32()
        state_45 = (state_45 * param_mul_45 + param_add_45) % 35184372088832
        repeat state_8 = state_8 * param_mul_8 % 257 until state_8 ~= 1
        local r = state_8 % 32
        local exp = 13 - (state_8 - r) / 32
        return floor(state_45 / (2 ^ exp)) % 4294967296
    end

    local function get_next_pseudo_random_byte()
        if #prev_values == 0 then
            local rnd = get_random_32()
            prev_values = {
                rnd % 256,
                floor(rnd / 256) % 256,
                floor(rnd / 65536) % 256,
                floor(rnd / 16777216) % 256
            }
        end
        local v = prev_values[#prev_values]
        prev_values[#prev_values] = nil
        return v or 0
    end

    local function encrypt(str)
        local seed = math.random(0, 35184372088832)
        set_seed(seed)
        local out = {}
        local prev = secret_key_8
        for i = 1, #str do
            local b = string.byte(str, i)
            local e = (b - (get_next_pseudo_random_byte() + prev)) % 256
            out[#out + 1] = bytetosymbol[e]
            prev = b
        end
        return table.concat(out), seed
    end

    local function genCode()
        local mapstr = "local symMap={"
        for s, b in pairs(symboltobyte) do
            mapstr = mapstr .. "['" .. s .. "']=" .. b .. ","
        end
        mapstr = mapstr .. "}"

        return [[
do
local DECRYPT
]] .. mapstr .. [[
local floor,char,sub=math.floor,string.char,string.sub
local state_45,state_8,prev_values=0,2,{}

local function get_next_pseudo()
    if #prev_values==0 then
        state_45=(state_45*]]..param_mul_45..[[+]]..param_add_45..[[)%35184372088832
        repeat state_8=state_8*]]..param_mul_8..[[%257 until state_8~=1
        local r=state_8%32
        local exp=13-(state_8-r)/32
        local rnd=floor(state_45/(2^exp))%4294967296
        prev_values={
            rnd%256,
            floor(rnd/256)%256,
            floor(rnd/65536)%256,
            floor(rnd/16777216)%256
        }
    end
    local v=prev_values[#prev_values]
    prev_values[#prev_values]=nil
    return v or 0
end

local cache={}

function DECRYPT(str,seed)
    if cache[seed] then return cache[seed] end
    
    state_45=seed%35184372088832
    state_8=seed%255+2
    prev_values={}
    local res={}
    local prev=]]..secret_key_8..[[

    for i=1,#str,3 do
        local sym=sub(str,i,i+2)
        local eb=symMap[sym] or 0
        prev=(eb+get_next_pseudo()+prev)%256
        res[#res+1]=char(prev)
    end

    local result=table.concat(res)
    cache[seed]=result
    return result
end
end]]
    end

    return { encrypt = encrypt, genCode = genCode }
end

function EncryptStrings:apply(ast, pipeline)
    local enc = self:CreateEncrypionService()
    local newAst = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 }):parse(enc.genCode())
    local dostat = newAst.body.statements[1]

    local scope = ast.body.scope
    local decryptVar = scope:addVariable()
    
    -- Insert do block first
    table.insert(ast.body.statements, 1, dostat)

    -- Add local declaration after do block
    table.insert(ast.body.statements, 2,
        Ast.LocalVariableDeclaration(scope, { decryptVar }, {})
    )

    -- The do-block already declares DECRYPT as a local and defines it
    // We just need to use our local variable to reference it
    // Since DECRYPT is already declared locally in the do-block,
    // we can just use our variable to call it

    -- Replace all string literals with calls to DECRYPT
    visitast(ast, nil, function(node)
        if node.kind == AstKind.StringExpression and not node.IsGenerated then
            local e, s = enc.encrypt(node.value)
            local call = Ast.FunctionCallExpression(
                Ast.VariableExpression(scope, decryptVar),
                { Ast.StringExpression(e), Ast.NumberExpression(s) }
            )
            call.IsGenerated = true
            return call
        end
    end)
end

return EncryptStrings
