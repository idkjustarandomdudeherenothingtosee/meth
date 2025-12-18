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
    local byteToSymbol = {}
    local symbolToByte = {}
    local count = 0

    for i = 1, #syms do
        for j = 1, #syms do
            for k = 1, #syms do
                if count <= 255 then
                    local seq = syms[i] .. syms[j] .. syms[k]
                    byteToSymbol[count] = seq
                    symbolToByte[seq] = count
                    count = count + 1
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
        repeat
            state_8 = state_8 * param_mul_8 % 257
        until state_8 ~= 1
        local r = state_8 % 32
        local exp = 13 - (state_8 - r) / 32
        local n = floor(state_45 / (2 ^ exp))
        return n % 4294967296
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
        return table.remove(prev_values)
    end

    local function encrypt(str)
        local seed = math.random(0, 35184372088832)
        set_seed(seed)
        local out = {}
        local prevVal = secret_key_8

        for i = 1, #str do
            local byte = string.byte(str, i)
            local encryptedByte = (byte - (get_next_pseudo_random_byte() + prevVal)) % 256
            out[#out + 1] = byteToSymbol[encryptedByte]
            prevVal = byte
        end

        return table.concat(out), seed
    end

    local function genCode()
        local mapStr = "local symMap={"
        for seq, byte in pairs(symbolToByte) do
            mapStr = mapStr .. "['" .. seq .. "']=" .. byte .. ","
        end
        mapStr = mapStr .. "}"

        return [[
do
]] .. mapStr .. [[
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
    return table.remove(prev_values)
end

local cache={}
STRINGS=setmetatable({}, {__index=cache})

function DECRYPT(str,seed)
    if cache[seed] then return seed end
    state_45=seed%35184372088832
    state_8=seed%255+2
    prev_values={}
    local res={}
    local prevVal=]]..secret_key_8..[[

    for i=1,#str,3 do
        local sym=sub(str,i,i+2)
        local encryptedByte=symMap[sym] or 0
        prevVal=(encryptedByte+get_next_pseudo()+prevVal)%256
        prevVal=floor(prevVal)%256
        res[#res+1]=char(prevVal)
    end

    cache[seed]=table.concat(res)
    return seed
end
end]]
    end

    return {
        encrypt = encrypt,
        genCode = genCode
    }
end

function EncryptStrings:apply(ast, pipeline)
    local encryptor = self:CreateEncrypionService()
    local newAst = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 }):parse(encryptor.genCode())
    local doStat = newAst.body.statements[1]

    local scope = ast.body.scope
    local decryptVar, stringsVar = scope:addVariable(), scope:addVariable()

    doStat.body.scope:setParent(scope)

    visitast(newAst, nil, function(node)
        if node.kind == AstKind.FunctionDeclaration
            and node.scope:getVariableName(node.id) == "DECRYPT" then
            node.id = decryptVar
        elseif (node.kind == AstKind.AssignmentVariable
            or node.kind == AstKind.VariableExpression)
            and node.scope:getVariableName(node.id) == "STRINGS" then
            node.id = stringsVar
        end
    end)

    visitast(ast, nil, function(node)
        if node.kind == AstKind.StringExpression and not node.IsGenerated then
            local encrypted, seed = encryptor.encrypt(node.value)
            local call = Ast.IndexExpression(
                Ast.VariableExpression(scope, stringsVar),
                Ast.FunctionCallExpression(
                    Ast.VariableExpression(scope, decryptVar),
                    {
                        Ast.StringExpression(encrypted),
                        Ast.NumberExpression(seed)
                    }
                )
            )
            call.IsGenerated = true
            return call
        end
    end)

    table.insert(ast.body.statements, 1, doStat)
    table.insert(ast.body.statements, 1,
        Ast.LocalVariableDeclaration(scope, { decryptVar, stringsVar }, {}))
end

return EncryptStrings
