select
    graphql.arg_to_jsonb(arg_ast.arg, x.vars),
    arg_ast.arg
from 
    (
        values 
            ('{ abc (int_val: 1) { x } }', null::jsonb),
            ('{ abc (float_val: 1.1) { x } }', null),
            ('{ abc (bool_val: false) { x } }', null),
            ('{ abc (string_val: "my string") { x } }', null),
            ('{ abc (enum_val: customEnum) { x } }', null),
            ('{ abc (list_val: [1, 2]) { x } }', null),
            ('{ abc (object_val: {key: "val"}) { x } }', null),
            ('query Abc($v: Int!) { abc(int_val: $v)  { x } }', '{"v": 1}'),
            ('query Abc($v: XFilter!) { abc(obj_val: $v) { x } }', '{"v": {"id": {"eq": "aghle"}}}'),
            ('query Mixed($v: Obj!) { abc(list_obj_val: [{abc: $v}]) { x } }', '{"v": {"id": {"eq": 1}}}')

    ) x(q, vars),
    lateral (
        select
            graphql.ast_pass_strip_loc(
                (
                    graphql.parse(x.q)
                ).ast::jsonb
            ) -> 'definitions' -> 0 -> 'selectionSet' -> 'selections' -> 0 -> 'arguments' -> 0
    ) arg_ast(arg);
