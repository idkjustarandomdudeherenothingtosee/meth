-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- NumbersToExpressions.lua
--
-- This Script provides an Obfuscation Step, that converts Number Literals to expressions
unpack = unpack or table.unpack;

local Step = require("prometheus.step");
local Ast = require("prometheus.ast");
local Scope = require("prometheus.scope");
local visitast = require("prometheus.visitast");
local util     = require("prometheus.util")

local AstKind = Ast.AstKind;

-- Check if the 'bit' library is available for advanced obfuscation
local bit = pcall(require, 'bit') and require('bit') or nil

local NumbersToExpressions = Step:extend();
NumbersToExpressions.Description = "This Step Converts number Literals to complex Expressions";
NumbersToExpressions.Name = "Numbers To Expressions (Advanced)";

NumbersToExpressions.SettingsDescriptor = {
	Treshold = {
        type = "number",
        default = 1,
        min = 0,
        max = 1,
    },
    InternalTreshold = {
        type = "number",
        default = 0.2,
        min = 0,
        max = 0.8,
    },
    -- New setting to control the depth of conditional logic
    ConditionalTreshold = {
        type = "number",
        default = 0.1,
        min = 0,
        max = 0.5,
    }
}

function NumbersToExpressions:init(settings)
    self.ExpressionGenerators = {
        -- Base Generators (from previous version)
        function(val, depth) -- Addition
            local val2 = math.random(-2^20, 2^20);
            local diff = val - val2;
            if math.abs((val2 + diff) - val) > 1e-9 then return false; end
            return Ast.AddExpression(self:CreateNumberExpression(val2, depth), self:CreateNumberExpression(diff, depth), false);
        end, 
        function(val, depth) -- Subtraction
            local val2 = math.random(-2^20, 2^20);
            local diff = val + val2;
            if math.abs((diff - val2) - val) > 1e-9 then return false; end
            return Ast.SubExpression(self:CreateNumberExpression(diff, depth), self:CreateNumberExpression(val2, depth), false);
        end,
        function(val, depth) -- Multiplication
            local val2_options = {};
            for i = 1, 10 do 
                if val % i == 0 and i ~= 0 then table.insert(val2_options, i); end
                if val % (-i) == 0 and -i ~= 0 then table.insert(val2_options, -i); end
            end
            if #val2_options == 0 then return false; end
            local val2 = val2_options[math.random(1, #val2_options)];
            local factor = val / val2;
            if math.abs((val2 * factor) - val) > 1e-9 then return false; end
            return Ast.MulExpression(self:CreateNumberExpression(val2, depth), self:CreateNumberExpression(factor, depth), false);
        end,
        function(val, depth) -- Division
            local val2 = math.random(1, 10);
            local dividend = val * val2;
            if math.abs((dividend / val2) - val) > 1e-9 then return false; end
            return Ast.DivExpression(self:CreateNumberExpression(dividend, depth), self:CreateNumberExpression(val2, depth), false);
        end,
        function(val, depth) -- Aggregation-like function
            local num_terms = math.random(3, 5);
            local sum_rand = 0;
            local rand_terms = {};
            for i = 1, num_terms do
                local term = math.random(-100, 100);
                table.insert(rand_terms, term);
                sum_rand = sum_rand + term;
            end
            local required_term = val - sum_rand;
            local expr = self:CreateNumberExpression(rand_terms[1], depth);
            for i = 2, num_terms do
                expr = Ast.AddExpression(expr, self:CreateNumberExpression(rand_terms[i], depth), false);
            end
            return Ast.AddExpression(expr, self:CreateNumberExpression(required_term, depth), false);
        end,

        -- *** New Advanced Generators ***

        function(val, depth) -- Modulo/Remainder Obfuscation: val = (val % M) + (val - (val % M))
            local M = math.random(2, 20); -- Modulo base
            local remainder = val % M;
            local quotient_part = val - remainder;

            if math.abs((remainder + quotient_part) - val) > 1e-9 then return false; end
            
            local M_expr = self:CreateNumberExpression(M, depth);
            local Rem_expr = Ast.ModExpression(self:CreateNumberExpression(val, depth), M_expr, false);
            local Quot_expr = Ast.SubExpression(self:CreateNumberExpression(val, depth), Rem_expr, false);
            
            return Ast.AddExpression(Rem_expr, Quot_expr, false);
        end,

        function(val, depth) -- Power/Logarithm Identity: val = 2 ^ log2(val)
            if val <= 0 then return false; end -- Must be positive

            -- Ast.FunctionCall(name, args)
            local log_expr = Ast.FunctionCall(Ast.Identifier("math.log"), {self:CreateNumberExpression(val, depth), self:CreateNumberExpression(2, depth)});
            local pow_expr = Ast.FunctionCall(Ast.Identifier("math.pow"), {self:CreateNumberExpression(2, depth), log_expr});
            
            -- This relies on the expression evaluator supporting function calls
            return pow_expr;
        end,

        -- Bitwise Generators (only if 'bit' is available)
        bit and function(val, depth) -- Bitwise AND + XOR: val = (val AND M) + (val XOR M)
            local M = math.random(1, 2048); -- Random mask
            
            local band_call = Ast.FunctionCall(Ast.Identifier("bit.band"), {self:CreateNumberExpression(val, depth), self:CreateNumberExpression(M, depth)});
            local bxor_call = Ast.FunctionCall(Ast.Identifier("bit.bxor"), {self:CreateNumberExpression(val, depth), self:CreateNumberExpression(M, depth)});
            
            -- bit.band(val, M) + bit.bxor(val, M) == val (for non-negative integers)
            return Ast.AddExpression(band_call, bxor_call, false);
        end,

        bit and function(val, depth) -- Bitwise OR + NOT: val = M - (M XOR val)
            local M = math.random(2^10, 2^12); -- Larger mask
            
            local bxor_call = Ast.FunctionCall(Ast.Identifier("bit.bxor"), {self:CreateNumberExpression(val, depth), self:CreateNumberExpression(M, depth)});
            local sub_expr = Ast.SubExpression(self:CreateNumberExpression(M, depth), bxor_call, false);
            
            -- This property only holds if val <= M and they are non-negative. It's a tricky one.
            if val < 0 or val > M then return false; end 
            return sub_expr;
        end,
    }
    
    -- Filter out nil generators if the 'bit' library is missing
    self.ExpressionGenerators = util.filter(self.ExpressionGenerators, function(g) return g ~= nil end)
end

function NumbersToExpressions:CreateNumberExpression(val, depth)
    -- Check for conditional depth threshold
    if depth > 0 and math.random() <= self.ConditionalTreshold then
        return self:CreateConditionalExpression(val, depth);
    end

    if depth > 0 and math.random() >= self.InternalTreshold or depth > 15 then
        return Ast.NumberExpression(val)
    end

    local generators = util.shuffle({unpack(self.ExpressionGenerators)});
    for i, generator in ipairs(generators) do
        local node = generator(val, depth + 1);
        if node then
            return node;
        end
    end

    return Ast.NumberExpression(val)
end

function NumbersToExpressions:CreateConditionalExpression(val, depth)
    -- Generates an expression like: (true_condition and val) or fallback_expr
    
    -- 1. Create a simple, always-true condition (e.g., 5 > 3)
    local left_val = math.random(1, 100);
    local right_val = left_val - math.random(1, 10); -- Ensure left > right
    
    local condition = Ast.BinaryExpression(
        self:CreateNumberExpression(left_val, depth + 1), 
        Ast.BinaryOperator.GreaterThan, 
        self:CreateNumberExpression(right_val, depth + 1)
    );

    -- 2. Create the first term: (condition AND val)
    local true_branch = Ast.AndExpression(
        condition,
        Ast.ParenthesesExpression(self:CreateNumberExpression(val, depth + 1)),
        false -- Add 'false' if the AST constructor requires it
    );

    -- 3. Create a junk/fallback expression that evaluates to the same 'val'
    -- This uses the original Add/Sub generator but is guaranteed to be simpler
    local fallback_val2 = math.random(-10, 10);
    local fallback_diff = val - fallback_val2;
    local fallback_expr = Ast.AddExpression(
        self:CreateNumberExpression(fallback_val2, depth + 1), 
        self:CreateNumberExpression(fallback_diff, depth + 1),
        false
    );

    -- 4. Combine: (true_condition and val) or fallback_expr. 
    -- Because Lua's 'and'/'or' short-circuiting and 'true_condition' is always true, 
    -- the expression resolves to 'val', but it hides the value inside control flow.
    return Ast.OrExpression(true_branch, fallback_expr, false);
end


function NumbersToExpressions:apply(ast)
	visitast(ast, nil, function(node, data)
        if node.kind == AstKind.NumberExpression then
            if math.random() <= self.Treshold then
                return self:CreateNumberExpression(node.value, 0);
            end
        end
    end)
end

return NumbersToExpressions;
