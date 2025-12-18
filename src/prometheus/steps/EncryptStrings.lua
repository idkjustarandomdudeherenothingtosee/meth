-- EncryptStrings.lua - Safe Lua 5.4 Version
-- Generates only valid Lua tokens

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Scope = require("prometheus.scope")
local Parser = require("prometheus.parser")
local Enums = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local util = require("prometheus.util")
local AstKind = Ast.AstKind

local EncryptStrings = Step:extend()
EncryptStrings.Description = "Encrypts strings using safe Lua 5.4 compatible encoding"
EncryptStrings.Name = "Encrypt Strings (Lua 5.4 Safe)"

function EncryptStrings:init(settings) end

function EncryptStrings:CreateEncryptionService()
    -- Use only characters that are safe for Lua strings
    local safe_chars = {}
    for i = 65, 90 do  -- A-Z
        table.insert(safe_chars, string.char(i))
    end
    for i = 97, 122 do -- a-z
        table.insert(safe_chars, string.char(i))
    end
    for i = 48, 57 do  -- 0-9
        table.insert(safe_chars, string.char(i))
    end
    
    -- Create encoding/decoding tables
    local char_to_index = {}
    local index_to_char = {}
    
    for i, char in ipairs(safe_chars) do
        char_to_index[char] = i - 1
        index_to_char[i - 1] = char
    end
    
    local base = #safe_chars
    
    -- Simple encryption: character shift + XOR
    local function encrypt_string(str)
        -- Generate random shift (1-25)
        local shift = math.random(1, 25)
        -- Generate random XOR key
        local xor_key = math.random(0, 255)
        
        local encoded = {}
        
        -- First two chars encode the shift and xor_key
        table.insert(encoded, index_to_char[shift])
        table.insert(encoded, index_to_char[xor_key % base])
        
        -- Encode the string
        for i = 1, #str do
            local byte = string.byte(str, i)
            -- Apply shift and XOR
            local encrypted = (byte + shift) ~ xor_key
            -- Convert to base-N representation (2 chars)
            local high = math.floor(encrypted / base)
            local low = encrypted % base
            table.insert(encoded, index_to_char[high])
            table.insert(encoded, index_to_char[low])
        end
        
        return table.concat(encoded), shift, xor_key
    end
    
    -- Generate simple, safe decryption code
    local function genDecryptionCode()
        return [[
do
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    local char_index = {}
    
    for i = 1, #chars do
        char_index[chars:sub(i, i)] = i - 1
    end
    
    local base = #chars
    local str_cache = {}
    local STR = {}
    
    function DEC(encoded)
        if str_cache[encoded] then
            return str_cache[encoded]
        end
        
        local shift = char_index[encoded:sub(1, 1)]
        local xor_key = char_index[encoded:sub(2, 2)]
        local result = {}
        
        for i = 3, #encoded, 2 do
            local high_char = encoded:sub(i, i)
            local low_char = encoded:sub(i + 1, i + 1)
            local high = char_index[high_char] or 0
            local low = char_index[low_char] or 0
            local val = high * base + low
            local decrypted = (val ~ xor_key) - shift
            result[#result + 1] = string.char(decrypted)
        end
        
        local decrypted_str = table.concat(result)
        str_cache[encoded] = decrypted_str
        return decrypted_str
    end
end
]]
    end
    
    return {
        encrypt = function(str)
            local encoded, shift, xor_key = encrypt_string(str)
            return encoded
        end,
        genCode = genDecryptionCode
    }
end

function EncryptStrings:apply(ast, pipeline)
    local Encryptor = self:CreateEncryptionService()
    local scope = ast.body.scope
    
    -- Create variable names
    local decrypt_var = scope:addVariable()
    local strings_var = scope:addVariable()
    
    -- Generate and parse decryption code
    local decryption_code = Encryptor.genCode()
    
    -- Simple manual AST construction to avoid parser errors
    -- We'll create the AST nodes directly instead of parsing
    
    -- Create a do block manually
    local do_block = Ast.DoStatement(scope:createChildScope())
    
    -- Add variables and function to the do block
    local do_scope = do_block.body.scope
    
    -- Create the DEC function
    local dec_func_name = do_scope:addVariable("DEC")
    local dec_func = Ast.FunctionDeclaration(
        do_scope,
        dec_func_name,
        {do_scope:addVariable("encoded")},
        Ast.Block(do_scope:createChildScope())
    )
    
    -- Create the STR table
    local str_table_name = do_scope:addVariable("STR")
    local str_table = Ast.LocalVariableDeclaration(
        do_scope,
        {str_table_name},
        {Ast.TableExpression(do_scope)}
    )
    
    -- Add statements to do block
    do_block.body.statements = {
        -- Add char_index table creation
        Ast.LocalVariableDeclaration(do_scope, 
            {do_scope:addVariable("chars")}, 
            {Ast.StringExpression("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")}
        ),
        Ast.LocalVariableDeclaration(do_scope,
            {do_scope:addVariable("char_index")},
            {Ast.TableExpression(do_scope)}
        ),
        -- Add for loop to populate char_index
        self:createCharIndexLoop(do_scope),
        -- Add base variable
        Ast.LocalVariableDeclaration(do_scope,
            {do_scope:addVariable("base")},
            {Ast.IndexExpression(
                Ast.VariableExpression(do_scope, do_scope:getVariable("chars")),
                Ast.UnaryOperatorExpression("#", Ast.VariableExpression(do_scope, do_scope:getVariable("chars")))
            )}
        ),
        -- Add cache table
        Ast.LocalVariableDeclaration(do_scope,
            {do_scope:addVariable("str_cache")},
            {Ast.TableExpression(do_scope)}
        ),
        -- Add STR table
        str_table,
        -- Add DEC function
        dec_func
    }
    
    -- Rename variables in the do block to use our generated names
    self:renameVariables(do_block, dec_func_name, decrypt_var, str_table_name, strings_var)
    
    -- Add the do block to the main AST
    table.insert(ast.body.statements, 1, do_block)
    
    -- Declare local variables in outer scope
    table.insert(ast.body.statements, 1, 
        Ast.LocalVariableDeclaration(scope, {decrypt_var, strings_var}, {})
    )
    
    -- Replace string literals
    self:replaceStringLiterals(ast, Encryptor, scope, decrypt_var, strings_var)
    
    return ast
end

function EncryptStrings:createCharIndexLoop(scope)
    -- Create: for i = 1, #chars do char_index[chars:sub(i, i)] = i - 1 end
    
    local i_var = scope:addVariable("i")
    
    local for_loop = Ast.ForNumericStatement(
        scope,
        i_var,
        Ast.NumberExpression(1),
        Ast.UnaryOperatorExpression("#", Ast.VariableExpression(scope, scope:getVariable("chars"))),
        Ast.NumberExpression(1),
        Ast.Block(scope:createChildScope())
    )
    
    -- Create the assignment: char_index[chars:sub(i, i)] = i - 1
    local index_expr = Ast.IndexExpression(
        Ast.VariableExpression(for_loop.body.scope, scope:getVariable("char_index")),
        Ast.FunctionCallExpression(
            Ast.IndexExpression(
                Ast.VariableExpression(for_loop.body.scope, scope:getVariable("chars")),
                Ast.StringExpression("sub")
            ),
            {
                Ast.VariableExpression(for_loop.body.scope, i_var),
                Ast.VariableExpression(for_loop.body.scope, i_var)
            }
        )
    )
    
    local assignment = Ast.AssignmentStatement(
        for_loop.body.scope,
        {index_expr},
        {Ast.BinaryOperatorExpression(
            "-",
            Ast.VariableExpression(for_loop.body.scope, i_var),
            Ast.NumberExpression(1)
        )}
    )
    
    table.insert(for_loop.body.statements, assignment)
    
    return for_loop
end

function EncryptStrings:renameVariables(do_block, internal_dec_var, external_dec_var, internal_str_var, external_str_var)
    local function rename(node)
        if node.kind == AstKind.VariableExpression then
            if node.scope:getVariableName(node.id) == internal_dec_var then
                node.id = external_dec_var
            elseif node.scope:getVariableName(node.id) == internal_str_var then
                node.id = external_str_var
            end
        elseif node.kind == AstKind.FunctionDeclaration then
            if node.scope:getVariableName(node.id) == internal_dec_var then
                node.id = external_dec_var
            end
        elseif node.kind == AstKind.LocalVariableDeclaration then
            for i, var in ipairs(node.ids) do
                if node.scope:getVariableName(var) == internal_str_var then
                    node.ids[i] = external_str_var
                end
            end
        end
    end
    
    visitast(do_block, nil, rename)
end

function EncryptStrings:replaceStringLiterals(ast, Encryptor, scope, decrypt_var, strings_var)
    local replacements = {}
    
    local function processNode(node)
        if node.kind == AstKind.StringExpression and not node.IsGenerated then
            local encrypted = Encryptor.encrypt(node.value)
            
            -- Create: STR[DEC(encrypted)]
            local dec_call = Ast.FunctionCallExpression(
                Ast.VariableExpression(scope, decrypt_var),
                {Ast.StringExpression(encrypted)}
            )
            
            local index_expr = Ast.IndexExpression(
                Ast.VariableExpression(scope, strings_var),
                dec_call
            )
            
            index_expr.IsGenerated = true
            return index_expr
        end
    end
    
    -- We need to actually replace nodes in the AST
    -- This is a simplified approach - in reality, Prometheus should have
    -- proper AST manipulation functions
    
    local function traverseAndReplace(node, parent, key)
        if node.kind == AstKind.StringExpression and not node.IsGenerated then
            local replacement = processNode(node)
            if replacement then
                if parent then
                    if parent.expressions and key then
                        parent.expressions[key] = replacement
                    elseif parent.statements and key then
                        parent.statements[key] = replacement
                    elseif parent.value == node then
                        parent.value = replacement
                    end
                end
            end
        else
            -- Recurse
            if node.expressions then
                for i, expr in ipairs(node.expressions) do
                    traverseAndReplace(expr, node, i)
                end
            end
            if node.statements then
                for i, stmt in ipairs(node.statements) do
                    traverseAndReplace(stmt, node, i)
                end
            end
            if node.value and node.value.kind then
                traverseAndReplace(node.value, node, "value")
            end
            if node.key and node.key.kind then
                traverseAndReplace(node.key, node, "key")
            end
            if node.init then
                for i, init in ipairs(node.init) do
                    if init.kind then
                        traverseAndReplace(init, node.init, i)
                    end
                end
            end
        end
    end
    
    traverseAndReplace(ast)
end

return EncryptStrings
