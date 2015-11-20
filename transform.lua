local lua_ast = require('sci-lang.lua-ast')

local function add_body(body, ...)
  local arg = { ... }
  for i=1,#arg do
    body[#body + 1] = arg[i]
  end
end

local function aexpr_index(ast, var, line)
  local p_idx = ast:expr_property(var, '_p', line)
  return ast:expr_index(p_idx, ast:identifier('__i'), line)
end

local function aexpr_loop1(ast, lhs, rhs)
  return ast:for_stmt(
    ast:identifier('__i', 1), 
    ast:literal(0, 1),
    ast:expr_binop('-', ast:expr_property(lhs, '_n', 1), ast:literal(1, 1), 1),
    nil, 
    { ast:assignment_expr({ aexpr_index(ast, lhs, 1) }, { rhs }, 1) }, 
    1, 1)
end

local function aexpr_dim(ast, what, arrays)
  return ast:expr_function_call(ast:identifier('__dim_'..what, 1), arrays, 1)
end

local function aexpr_terminal(ast, node, fargs, fvals)
  assert(#fargs == #fvals)
  local kind, ivar = node.kind, #fargs + 1
  fargs[ivar] = ast:identifier('__x'..ivar, 1)
  if kind == 'IndexAlgebraExpression' then
    fvals[ivar] = node.object
  elseif kind == 'Identifier' or kind == 'Literal' then
    fvals[ivar] = node
  end
  return fargs[ivar]
end

local aexpr_set

local function aexpr_linear_access(ast, node, fbody, fargs, fvals, temps, arrays)
  assert(type(temps) == 'table')
  local kind, operator = node.kind, node.operator
  if kind == 'IndexAlgebraExpression' then
    local var = aexpr_terminal(ast, node, fargs, fvals)
    arrays[#arrays + 1] = var
    return aexpr_index(ast, var, 1)
  elseif kind == 'Identifier' or kind == 'Literal' then
    return aexpr_terminal(ast, node, fargs, fvals)
  elseif kind == 'UnaryAlgebraExpression' then
    return ast:expr_unop(node.operator, aexpr_linear_access(ast, node.argument, fbody, fargs, fvals, temps, arrays), node.line)
  elseif kind == 'BinaryAlgebraExpression' then
    if operator == '**' or operator == '^^' then
      local ivar = #temps + 1
      temps[ivar] = ast:identifier('__t'..ivar, 1)
      arrays[#arrays + 1] = temps[ivar]
      aexpr_set(ast, node, temps[ivar], ast:identifier('__stack_array', 1), fbody, fargs, fvals, temps)
      return aexpr_index(ast, temps[ivar], 1)
    else
      local left  = aexpr_linear_access(ast, node.left,  fbody, fargs, fvals, temps, arrays)
      local right = aexpr_linear_access(ast, node.right, fbody, fargs, fvals, temps, arrays)
      return ast:expr_binop(node.operator, left, right, node.line)
    end
  end
  error('internal: unreachable')
end

local function aexpr_elw_set(ast, node, out, out_kind, fbody, fargs, fvals, temps)
  local arrays = { }
  local access = aexpr_linear_access(ast, node, fbody, fargs, fvals, temps, arrays)
  local pre
  if out_kind then
    local __dim = aexpr_dim(ast, 'elw_'..(#arrays), arrays) 
    pre = ast:local_decl({ out.name }, { ast:expr_function_call(out_kind, { arrays[1], __dim }, 1) }, 1)
  else
    local __dim = aexpr_dim(ast, 'elw_'..(#arrays + 1), { out, unpack(arrays) })
    pre = ast:new_statement_expr(__dim, 1)
  end
  local elw = aexpr_loop1(ast, out, access)
  return pre, elw
end

local function aexpr_singlify(ast, node, fbody, fargs, fvals, temps)
  local kind, transpose = node.kind, false
  if kind == 'UnaryAlgebraExpression' and node.operator == '`' then
    transpose = true
    node = node.argument
    kind = node.kind
  end
  transpose = ast:literal(transpose, 1)
  if kind == 'IndexAlgebraExpression' or kind == 'Identifier' or kind == 'Literal' then
    return aexpr_terminal(ast, node, fargs, fvals), transpose
  else
    local ivar = #temps + 1
    temps[ivar] = ast:identifier('__t'..ivar, 1)
    aexpr_set(ast, node, temps[ivar], ast:identifier('__stack_array', 1), fbody, fargs, fvals, temps)
    return temps[ivar], transpose
  end
end

local function aexpr_mul_set(ast, out, out_kind, left, right, left_tr, right_tr)
  local __mul = ast:identifier('__mul', 1)
  local pre
  if out_kind then
    local __dim = aexpr_dim(ast, 'mul_2', { left, right, left_tr, right_tr }) 
    pre = ast:local_decl({ out.name }, { ast:expr_function_call(out_kind, { left, __dim }, 1) }, 1)
  else
    local __dim = aexpr_dim(ast, 'mul_3', { out, left, right, left_tr, right_tr })
    pre = ast:new_statement_expr(__dim, 1)
  end
  local mul = ast:new_statement_expr(ast:expr_function_call(__mul, { out, left, right, left_tr, right_tr }, 1), 1)
  return pre, mul
end

local function aexpr_pow_set(ast, out, out_kind, left, right)
  local __pow = ast:identifier('__pow', 1)
  local pre
  if out_kind then
    local __dim = aexpr_dim(ast, 'pow_1', { left }) 
    pre = ast:local_decl({ out.name }, { ast:expr_function_call(out_kind, { left, __dim }, 1) }, 1)
  else
    local __dim = aexpr_dim(ast, 'pow_2', { out, left })
    pre = ast:new_statement_expr(__dim, 1)
  end
  local pow = ast:new_statement_expr(ast:expr_function_call(__pow, { out, left, right }, 1), 1)
  return pre, pow
end

aexpr_set = function(ast, node, out, out_kind, fbody, fargs, fvals, temps)
  local kind, operator = node.kind, node.operator
  if kind == 'BinaryAlgebraExpression' and (operator == '**' or operator == '^^') then
    local left,  left_tr  = aexpr_singlify(ast, node.left,  fbody, fargs, fvals, temps)
    local right, right_tr = aexpr_singlify(ast, node.right, fbody, fargs, fvals, temps)
    if operator == '**' then
      add_body(fbody, aexpr_mul_set(ast, out, out_kind, left, right, left_tr, right_tr))
    else
      add_body(fbody, aexpr_pow_set(ast, out, out_kind, left, right))
    end 
  else
    add_body(fbody, aexpr_elw_set(ast, node, out, out_kind, fbody, fargs, fvals, temps))
  end
end

local expr_count = 0
local proto = { firstline = 1, lastline = 1 }

local function aexpr_clear(ast, temps, fbody)
  if #temps > 0 then
    add_body(fbody, ast:new_statement_expr(ast:expr_function_call(ast:identifier('__stack_clear', 1), { }, 1), 1))
  end
end

local function aexpr_root(ast, fargs, fvals, set_node, out_kind, return_stmt)
  expr_count = expr_count + 1

  local __r1 = ast:identifier('__r1', 1)
  local fbody, temps = { }, { }

  aexpr_set(ast, set_node, __r1, out_kind, fbody, fargs, fvals, temps)
  aexpr_clear(ast, temps, fbody)
  add_body(fbody, return_stmt)
  fbody.lastline = 1

  ast.pre[#ast.pre + 1] = ast:local_function_decl('__aexpr_'..expr_count, fargs, fbody, proto) 
  return ast:expr_function_call(ast:identifier('__aexpr_'..expr_count, 1), fvals, 1)
end

local function aexpr_new(ast, node)
  local __r1 = ast:identifier('__r1', 1)
  return aexpr_root(ast, { }, { }, node, ast:identifier('__array_alloc', 1), ast:return_stmt({ __r1 }, 1))
end

local function aexpr_assign(ast, node)
  local __r1 = ast:identifier('__r1', 1)
   return aexpr_root(ast, { __r1 }, { node.left[1].object }, node.right[1], nil, nil)
end

local transform_map = {
  IndexAlgebraExpression  = aexpr_new,
  UnaryAlgebraExpression  = aexpr_new,
  BinaryAlgebraExpression = aexpr_new,
  AssignmentAlgebraExpression = aexpr_assign,
}

local function transform(ast, node)
  if type(node) == 'table' then
    local transform_kind = transform_map[node.kind] -- Fails if not node.
    if transform_kind then -- To be transformed nodes.
      return transform_kind(ast, node)
    else -- Not to be transformed nodes.
      local o = { }
      for k,v in pairs(node) do
        o[k] = transform(ast, v)
      end
      return o
    end
  end
  return node -- Not nodes.
end

local function localize(ast, what, from, line)
  local lhs, rhs = { }, { }
  for i,k in ipairs(what) do
    lhs[i] = '__'..k
    rhs[i] = ast:expr_property(from, k, line)
  end
  return ast:local_decl(lhs, rhs, line)
end

local function pre_init(ast)
  local dim_elw_x = { }
  for i=1,10 do dim_elw_x[i] = 'dim_elw_'..i end
  local __alg = ast:identifier('__alg', 1)
  return { 
    ast:local_decl(
      { __alg.name }, 
      { ast:expr_property(
          ast:expr_function_call(ast:identifier('require', 1), { ast:literal('sci.alg', 1) }, 1),
          '__',
          1), },
      1),
    localize(ast, { 'mul', 'pow', 'dim_mul_2', 'dim_mul_3', 'dim_pow_1', 'dim_pow_2', 'stack_array', 'stack_clear', 'array_alloc' }, __alg, 1),
    localize(ast, dim_elw_x, __alg, 1)
  }
end

local function root(tree)
  local tast = lua_ast.New()
  tast:fscope_begin()
  tast.pre = pre_init(tast)
  local valid_tree = transform(tast, tree)
  for i=1,#tast.pre do
    table.insert(valid_tree.body, i, tast.pre[i])
  end
  tast:fscope_end()
  return valid_tree
end

return {
  root = root,
}

