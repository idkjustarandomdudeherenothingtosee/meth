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
    
    -- Create variables for DECRYPT function
    local decryptVar = scope:addVariable()
    local stringsVar = scope:addVariable()
    
    -- Set parent scope of do-block to main scope
    dostat.body.scope:setParent(scope)

    -- Modify the parsed AST to use our variables
    -- Find DECRYPT function and STRINGS table references
    local function renameVariables(node)
        if node.kind == AstKind.FunctionDeclaration then
            -- Check if this is the DECRYPT function
            local varName = node.scope:getVariableName(node.id)
            if varName == "DECRYPT" then
                -- Change to use our variable from outer scope
                node.id = decryptVar
                node.scope = scope
            end
        elseif node.kind == AstKind.VariableExpression then
            -- Check if this is a reference to STRINGS or DECRYPT
            local varName = node.scope:getVariableName(node.id)
            if varName == "STRINGS" or varName == "DECRYPT" then
                -- Replace with our variable
                if varName == "STRINGS" then
                    node.id = stringsVar
                elseif varName == "DECRYPT" then
                    node.id = decryptVar
                end
                node.scope = scope
            end
        elseif node.kind == AstKind.AssignmentVariable then
            -- Same for assignment variables
            local varName = node.scope:getVariableName(node.id)
            if varName == "STRINGS" or varName == "DECRYPT" then
                if varName == "STRINGS" then
                    node.id = stringsVar
                elseif varName == "DECRYPT" then
                    node.id = decryptVar
                end
                node.scope = scope
            end
        end
    end

    -- Walk through the do-block AST and rename variables
    local function walkAndRename(node)
        renameVariables(node)
        
        -- Recursively process child nodes
        if node.kind == AstKind.Block then
            for _, stmt in ipairs(node.statements) do
                walkAndRename(stmt)
            end
        elseif node.kind == AstKind.FunctionDeclaration or node.kind == AstKind.LocalFunctionDeclaration then
            if node.body then walkAndRename(node.body) end
        elseif node.kind == AstKind.DoStatement or node.kind == AstKind.WhileStatement or 
               node.kind == AstKind.RepeatStatement or node.kind == AstKind.ForStatement or
               node.kind == AstKind.ForInStatement or node.kind == AstKind.IfStatement then
            if node.body then walkAndRename(node.body) end
            if node.elsebody then walkAndRename(node.elsebody) end
            if node.elseifs then
                for _, elseifBlock in ipairs(node.elseifs) do
                    if elseifBlock.body then walkAndRename(elseifBlock.body) end
                end
            end
        elseif node.kind == AstKind.FunctionLiteralExpression then
            if node.body then walkAndRename(node.body) end
        elseif node.kind == AstKind.FunctionCallExpression or node.kind == AstKind.PassSelfFunctionCallExpression then
            renameVariables(node.base)
            if node.args then
                for _, arg in ipairs(node.args) do
                    if type(arg) == "table" then walkAndRename(arg) end
                end
            end
        elseif node.kind == AstKind.IndexExpression or node.kind == AstKind.AssignmentIndexing then
            renameVariables(node.base)
            renameVariables(node.index)
        elseif node.kind == AstKind.AssignmentStatement then
            for _, lhs in ipairs(node.lhs) do
                renameVariables(lhs)
            end
            for _, rhs in ipairs(node.rhs) do
                if type(rhs) == "table" then walkAndRename(rhs) end
            end
        elseif node.kind == AstKind.LocalVariableDeclaration then
            for _, expr in ipairs(node.expressions) do
                if type(expr) == "table" then walkAndRename(expr) end
            end
        elseif node.kind == AstKind.OrExpression or node.kind == AstKind.AndExpression or
               node.kind == AstKind.AddExpression or node.kind == AstKind.SubExpression or
               node.kind == AstKind.MulExpression or node.kind == AstKind.DivExpression or
               node.kind == AstKind.ModExpression or node.kind == AstKind.PowExpression or
               node.kind == AstKind.StrCatExpression or node.kind == AstKind.LessThanExpression or
               node.kind == AstKind.GreaterThanExpression or node.kind == AstKind.LessThanOrEqualsExpression or
               node.kind == AstKind.GreaterThanOrEqualsExpression or node.kind == AstKind.EqualsExpression or
               node.kind == AstKind.NotEqualsExpression then
            renameVariables(node.lhs)
            renameVariables(node.rhs)
        elseif node.kind == AstKind.NotExpression or node.kind == AstKind.NegateExpression or 
               node.kind == AstKind.LenExpression then
            renameVariables(node.rhs)
        elseif node.kind == AstKind.TableConstructorExpression then
            for _, entry in ipairs(node.entries) do
                if entry.kind == AstKind.TableEntry then
                    renameVariables(entry.value)
                elseif entry.kind == AstKind.KeyedTableEntry then
                    renameVariables(entry.key)
                    renameVariables(entry.value)
                end
            end
        end
    end

    -- Rename variables in the do-block
    walkAndRename(dostat)

    -- Insert do block first
    table.insert(ast.body.statements, 1, dostat)
    
    -- Insert local variable declarations after do block
    table.insert(ast.body.statements, 2,
        Ast.LocalVariableDeclaration(scope, { decryptVar, stringsVar }, {})
    )

    -- Replace all string literals with calls to DECRYPT
    -- We'll create STRINGS table and use it as a cache
    visitast(ast, nil, function(node)
        if node.kind == AstKind.StringExpression and not node.IsGenerated then
            local encrypted, seed = enc.encrypt(node.value)
            
            -- Create STRINGS[DECRYPT(encrypted, seed)] pattern
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
end

return EncryptStrings
