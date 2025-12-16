-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- ProxifyLocals.lua
--
-- This Script provides a Obfuscation Step for putting all Locals into Proxy Objects

local Step = require("prometheus.step");
local Ast = require("prometheus.ast");
local Scope = require("prometheus.scope");
local visitast = require("prometheus.visitast");
local RandomLiterals = require("prometheus.randomLiterals")
local util = require("prometheus.util") -- Assuming util is part of the Prometheus framework

local AstKind = Ast.AstKind;

local ProifyLocals = Step:extend();
ProifyLocals.Description = "This Step wraps all locals into Proxy Objects with dynamic access logic";
ProifyLocals.Name = "Proxify Locals (Advanced)";

ProifyLocals.SettingsDescriptor = {
	LiteralType = {
		name = "LiteralType",
		description = "The type of the randomly generated literals",
		type = "enum",
		values = {
			"dictionary",
			"number",
			"string",
            "any",
		},
		default = "string",
	},
}

-- Utility function to create a string expression that is concatenation-based
function ProifyLocals:CreateDynamicKey(keyString, depth)
    local len = #keyString
    -- Use simple string literal 80% of the time, or if string is too short
    if len < 4 or math.random() < 0.8 then 
        return Ast.StringExpression(keyString)
    end
    
    local parts = {}
    local start = 1
    while start <= len do
        local part_len = math.random(2, math.min(len - start + 1, 4))
        table.insert(parts, Ast.StringExpression(keyString:sub(start, start + part_len - 1)))
        start = start + part_len
    end

    local expr = parts[1]
    for i = 2, #parts do
        expr = Ast.StrCatExpression(expr, parts[i])
    end
    return expr
end

local function shallowcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

local function callNameGenerator(generatorFunction, ...)
	if(type(generatorFunction) == "table") then
		generatorFunction = generatorFunction.generateName;
	end
	return generatorFunction(...);
end

local MetatableExpressions = {
    { constructor = Ast.AddExpression, key = "__add" },
    { constructor = Ast.SubExpression, key = "__sub" },
    { constructor = Ast.IndexExpression, key = "__index" },
    { constructor = Ast.MulExpression, key = "__mul" },
    { constructor = Ast.DivExpression, key = "__div" },
    { constructor = Ast.PowExpression, key = "__pow" },
    { constructor = Ast.StrCatExpression, key = "__concat" },
    { constructor = Ast.UnmExpression, key = "__unm" },
    { constructor = Ast.LenExpression, key = "__len" },
}

function ProifyLocals:init(settings)
	-- No custom init logic needed
end

local function generateLocalMetatableInfo(pipeline)
    local usedOps = {};
    local info = {};
    
    local shuffled_ops = util.shuffle(MetatableExpressions)

    for i, v in ipairs({"setValue","getValue", "index"}) do
        local rop;
        repeat
            rop = shuffled_ops[math.random(#shuffled_ops)]
        until not usedOps[rop]
        
        usedOps[rop] = true;
        info[v] = rop;
    end

    info.valueName = callNameGenerator(pipeline.namegenerator, math.random(1, 4096));

    return info;
end

function ProifyLocals:CreateAssignmentExpression(info, expr, parentScope)
    local metatableVals = {};

    -- === Setvalue Entry (__newindex Logic) ===
    local setValueFunctionScope = Scope:new(parentScope);
    local setValueSelf = setValueFunctionScope:addVariable();
    local setValueArg = setValueFunctionScope:addVariable();
    
    local dynamicKeyExpr = self:CreateDynamicKey(info.valueName);

    -- Junk logic: Local variable declaration
    local junkVarId = setValueFunctionScope:addVariable(callNameGenerator(self.pipeline.namegenerator, 16));
    local junkStatement = Ast.LocalVariableDeclaration(setValueFunctionScope, {junkVarId}, {
        Ast.AddExpression(Ast.VariableExpression(setValueFunctionScope, setValueArg), Ast.NumberExpression(0), false)
    });

    local setvalueFunctionLiteral = Ast.FunctionLiteralExpression(
        {
            Ast.VariableExpression(setValueFunctionScope, setValueSelf), 
            Ast.VariableExpression(setValueFunctionScope, setValueArg), 
        },
        Ast.Block({
            junkStatement, 
            Ast.AssignmentStatement({
                Ast.AssignmentIndexing(Ast.VariableExpression(setValueFunctionScope, setValueSelf), dynamicKeyExpr);
            }, {
                Ast.VariableExpression(setValueFunctionScope, setValueArg)
            })
        }, setValueFunctionScope)
    );
    table.insert(metatableVals, Ast.KeyedTableEntry(Ast.StringExpression(info.setValue.key), setvalueFunctionLiteral));

    -- === Getvalue Entry (__index Logic) ===
    local getValueFunctionScope = Scope:new(parentScope);
    local getValueSelf = getValueFunctionScope:addVariable();
    local getValueArg = getValueFunctionScope:addVariable();
    local rawgetVarId = getValueFunctionScope:resolveGlobal("rawget");

    local dynamicKeyExpr_get = self:CreateDynamicKey(info.valueName);

    local getValueIdxExpr = Ast.FunctionCallExpression(Ast.VariableExpression(getValueFunctionScope, rawgetVarId), {
        Ast.VariableExpression(getValueFunctionScope, getValueSelf),
        dynamicKeyExpr_get,
    });
    
    -- Obfuscate the return: wrap the actual lookup in another expression
    local returnExpr = Ast.AddExpression(getValueIdxExpr, Ast.NumberExpression(0), false);
    
    local getvalueFunctionLiteral = Ast.FunctionLiteralExpression(
        {
            Ast.VariableExpression(getValueFunctionScope, getValueSelf), 
            Ast.VariableExpression(getValueFunctionScope, getValueArg), 
        },
        Ast.Block({
            Ast.ReturnStatement({
                returnExpr;
            });
        }, getValueFunctionScope)
    );
    table.insert(metatableVals, Ast.KeyedTableEntry(Ast.StringExpression(info.getValue.key), getvalueFunctionLiteral));

    -- Final assignment: setmetatable( { [dynamic key] = expr }, metatable )
    parentScope:addReferenceToHigherScope(self.setMetatableVarScope, self.setMetatableVarId);
    return Ast.FunctionCallExpression(
        Ast.VariableExpression(self.setMetatableVarScope, self.setMetatableVarId),
        {
            Ast.TableConstructorExpression({
                Ast.KeyedTableEntry(self:CreateDynamicKey(info.valueName), expr)
            }),
            Ast.TableConstructorExpression(metatableVals)
        }
    );
end

function ProifyLocals:apply(ast, pipeline)
    self.pipeline = pipeline 
    local localMetatableInfos = {};
    local function getLocalMetatableInfo(scope, id)
        if(scope.isGlobal) then return nil end;
        localMetatableInfos[scope] = localMetatableInfos[scope] or {};
        if localMetatableInfos[scope][id] then
            if localMetatableInfos[scope][id].locked then
                return nil
            end
            return localMetatableInfos[scope][id];
        end
        local localMetatableInfo = generateLocalMetatableInfo(pipeline);
        localMetatableInfos[scope][id] = localMetatableInfo;
        return localMetatableInfo;
    end

    local function disableMetatableInfo(scope, id)
        if(scope.isGlobal) then return nil end;
        localMetatableInfos[scope] = localMetatableInfos[scope] or {};
        localMetatableInfos[scope][id] = {locked = true}
    end

    -- Setup global helper variables
    self.setMetatableVarScope = ast.body.scope;
    self.setMetatableVarId    = ast.body.scope:addVariable();
    self.emptyFunctionScope   = ast.body.scope;
    self.emptyFunctionId      = ast.body.scope:addVariable();
    self.emptyFunctionUsed    = false;

    -- Add Empty Function Declaration (first statement)
    table.insert(ast.body.statements, 1, Ast.LocalVariableDeclaration(self.emptyFunctionScope, {self.emptyFunctionId}, {
        Ast.FunctionLiteralExpression({}, Ast.Block({}, Scope:new(ast.body.scope)));
    }));


    visitast(ast, function(node, data)
        -- Lock Variables (Pre-walk)
        if(node.kind == AstKind.ForStatement) then disableMetatableInfo(node.scope, node.id) end
        if(node.kind == AstKind.ForInStatement) then
            for i, id in ipairs(node.ids) do disableMetatableInfo(node.scope, id); end
        end
        if(node.kind == AstKind.FunctionDeclaration or node.kind == AstKind.LocalFunctionDeclaration or node.kind == AstKind.FunctionLiteralExpression) then
            for i, expr in ipairs(node.args) do
                if expr.kind == AstKind.VariableExpression then disableMetatableInfo(expr.scope, expr.id); end
            end
        end

        -- Assignment Statements (a = 1)
        if(node.kind == AstKind.AssignmentStatement) then
            if(#node.lhs == 1 and node.lhs[1].kind == AstKind.AssignmentVariable) then
                local variable = node.lhs[1];
                local localMetatableInfo = getLocalMetatableInfo(variable.scope, variable.id);
                if localMetatableInfo then
                    local args = shallowcopy(node.rhs);
                    local vexp = Ast.VariableExpression(variable.scope, variable.id);
                    vexp.__ignoreProxifyLocals = true;
                    
                    -- Metatable call (vexp + args[1]) triggers __add/sub/etc
                    args[1] = localMetatableInfo.setValue.constructor(vexp, args[1]);
                    
                    self.emptyFunctionUsed = true;
                    data.scope:addReferenceToHigherScope(self.emptyFunctionScope, self.emptyFunctionId);
                    -- Assignment is replaced by function call to obscure the statement
                    return Ast.FunctionCallStatement(Ast.VariableExpression(self.emptyFunctionScope, self.emptyFunctionId), args);
                end
            end
        end
    end, function(node, data)
        -- Post-walk transformations

        -- Local Variable Declaration (local a = setmetatable(...) )
        if(node.kind == AstKind.LocalVariableDeclaration) then
            for i, id in ipairs(node.ids) do
                local expr = node.expressions[i] or Ast.NilExpression();
                local localMetatableInfo = getLocalMetatableInfo(node.scope, id);
                if localMetatableInfo then
                    local newExpr = self:CreateAssignmentExpression(localMetatableInfo, expr, node.scope);
                    node.expressions[i] = newExpr;
                end
            end
        end

        -- Variable Expression (print(a) -> print(a + literal) )
        if(node.kind == AstKind.VariableExpression and not node.__ignoreProxifyLocals) then
            local localMetatableInfo = getLocalMetatableInfo(node.scope, node.id);
            if localMetatableInfo then
                local literal_value;
                local literal_type = self.settings.LiteralType;
                
                -- Determine literal value
                if literal_type == "dictionary" then
                    literal_value = RandomLiterals.Dictionary();
                elseif literal_type == "number" then
                    literal_value = RandomLiterals.Number();
                elseif literal_type == "string" then
                    literal_value = RandomLiterals.String(pipeline);
                else
                    literal_value = RandomLiterals.Any(pipeline);
                end
                
                local literal_node = RandomLiterals.CreateExpression(literal_value, literal_type);
                
                -- Apply the metatable constructor for value retrieval
                return localMetatableInfo.getValue.constructor(node, literal_node);
            end
        end

        -- Assignment Variable for Assignment Statement (a = 1 -> proxy[dynamic_key] = 1)
        if(node.kind == AstKind.AssignmentVariable) then
            local localMetatableInfo = getLocalMetatableInfo(node.scope, node.id);
            if localMetatableInfo then
                return Ast.AssignmentIndexing(node, self:CreateDynamicKey(localMetatableInfo.valueName));
            end
        end

        -- Local Function Declaration (local function f() ... -> local f = setmetatable(...) )
        if(node.kind == AstKind.LocalFunctionDeclaration) then
            local localMetatableInfo = getLocalMetatableInfo(node.scope, node.id);
            if localMetatableInfo then
                local funcLiteral = Ast.FunctionLiteralExpression(node.args, node.body);
                local newExpr = self:CreateAssignmentExpression(localMetatableInfo, funcLiteral, node.scope);
                return Ast.LocalVariableDeclaration(node.scope, {node.id}, {newExpr});
            end
        end

        -- Function Declaration (function a:f() ... )
        if(node.kind == AstKind.FunctionDeclaration) then
            local localMetatableInfo = getLocalMetatableInfo(node.scope, node.id);
            if(localMetatableInfo) then
                table.insert(node.indices, 1, self:CreateDynamicKey(localMetatableInfo.valueName));
            end
        end
    end)

    -- Add Setmetatable Variable Declaration (second statement)
    table.insert(ast.body.statements, 1, Ast.LocalVariableDeclaration(self.setMetatableVarScope, {self.setMetatableVarId}, {
        Ast.VariableExpression(self.setMetatableVarScope:resolveGlobal("setmetatable"))
    }));
end

return ProifyLocals;
