import re

from pygments.lexer import include, bygroups, words, default, RegexLexer
from pygments.token import (
    Comment,
    Operator,
    String,
    Punctuation,
    Keyword,
    Number,
    Text,
    Name,
)

Whitespace = Text.Whitespace

__all__ = ["GraphQLLexer"]

name_re = r"[_A-Za-z][_0-9A-Za-z]*"
name_capture_re = "({})".format(name_re)


def match_tuple(match, token_type, group_num, start=0):
    return (start + match.start(group_num), token_type, match.group(group_num))


def match_tuple_many(match, token_type_list, start=0):
    for group_num, token_type in enumerate(token_type_list, 1):
        yield match_tuple(match, token_type, group_num, start)


class GraphQLLexer(RegexLexer):
    """
    Lexer for GraphQL.
    """

    name = "GraphQL"
    aliases = ["graphql", "gql"]
    filenames = ["*.graphql", "*.gql"]
    mimetypes = ["application/graphql"]

    def union_callback(self, match):
        union_def = match.group(1)
        match_start = 0
        while True:
            match_str = union_def[match_start:]
            type_match = re.match(r"(\s*)(\|?)(\s*)" + name_capture_re, match_str)
            if type_match is None:
                break
            yield from match_tuple_many(
                type_match,
                [
                    Whitespace,
                    Punctuation,
                    Text.Whitesspace,
                    Text.Name,
                ],
                start=match_start,
            )
            match_start += type_match.end()

    tokens = {
        "whitespace": [
            (r"( |,|\n|\r|\uFEFF)", Whitespace),
        ],
        "comment": [
            (r"#.*", Comment.Singline),
        ],
        "directive": [
            (
                r"(@{})(\s*)(\()".format(name_re),
                bygroups(Name.Function, Whitespace, Punctuation),
                "query-field-args",
            ),
            (r"@{}".format(name_re), Name.Function),
        ],
        "schema-def": [
            include("whitespace"),
            (r"\{", Punctuation, ("#pop", "fields-def")),
        ],
        "type-def": [
            include("whitespace"),
            (
                r"(implements\b)(\s*){}".format(name_capture_re),
                bygroups(Keyword, Whitespace, Name),
            ),
            (r"\{", Punctuation, ("#pop", "fields-def")),
        ],
        "fragment-def": [
            include("whitespace"),
            (
                name_capture_re + r"(\s+)(on)(\s+)" + name_capture_re,
                bygroups(Name.Function, Whitespace, Keyword, Whitespace, Name.Class),
            ),
            (r"\{", Punctuation, ("#pop", "fields-query")),
        ],
        "union-def": [
            include("whitespace"),
            (
                name_capture_re + r"(\s*)(=)",
                bygroups(Name.Class, Whitespace, Punctuation),
            ),
            (r"({name}(?:\s*\|\s*{name})+)".format(name=name_re), union_callback),
            default("#pop"),
        ],
        "args-def": [
            (r"(?i)[a-z_]\w*(?=\s*:)", Name.Attribute),
            (r"(?i)(?::[\s\[]*)([a-z_]\w*)", Name),
            include("common"),
            (r"\)", Punctuation, "#pop"),
        ],
        "fields-def": [
            (r"\(", Punctuation, "args-def"),
            (r"(?i)[a-z_]\w*(?=\s*[:\(])", Name.Attribute),
            (r"(?i)(?::[\s\[]*)([a-z_]\w*)", Name),
            (r"\}", Punctuation, "#pop"),
            include("common"),
        ],
        "query": [
            include("whitespace"),
            (name_re, Name.Class),
            (r"\(", Punctuation, "query-args"),
            (r"\{", Punctuation, ("#pop", "fields-query")),
            include("directive"),
        ],
        "query-args": [
            (r"\${}:".format(name_re), Name.Attribute),
            (name_re, Text),
            (r"\)", Punctuation, "#pop"),
            include("common"),
        ],
        "fields-query": [
            (name_re, Text),
            (r"\(", Punctuation, "query-field-args"),
            (r":", Punctuation, "query-alias"),
            (r"\}", Punctuation, "#pop"),
            (r"\{", Punctuation, "#push"),
            (
                r"(\.{3})(\s*)(on)(\s*)" + name_capture_re,
                bygroups(Operator, Whitespace, Keyword, Whitespace, Name.Class),
            ),
            include("directive"),
            include("common"),
        ],
        "query-alias": [
            (r"\)", Punctuation, "#pop"),
            (r"\(", Punctuation, "query-field-args"),
            (r"\{", Punctuation, ("#pop", "fields-query")),
            include("common"),
        ],
        "query-field-args": [
            (r"{}(:)".format(name_capture_re), bygroups(Name.Attribute, Punctuation)),
            (r"\)", Punctuation, "#pop"),
            include("common"),
        ],
        "literal": [
            (r'"(?:\\.|[^\\"])*"', String.Double),
            (
                r"(-?0|-?[1-9][0-9]*)(\.[0-9]+[eE][+-]?[0-9]+|\.[0-9]+|[eE][+-]?[0-9]+)",
                Number.Float,
            ),
            (r"(-?0|-?[1-9][0-9]*)", Number.Integer),
            (r"\b(true|false|null)\b", Keyword.Constant),
        ],
        "common": [
            include("comment"),
            include("whitespace"),
            include("literal"),
            (r"!|=|\.{3}\b", Operator),
            (r"[!(){|}[\]:=,]", Punctuation),
            (r"(?i)\$[a-z_]\w*", Name.Variable),
            (name_re, Text),
        ],
        "root": [
            include("whitespace"),
            include("comment"),
            (r"schema\b", Keyword.Declaration, "schema-def"),
            (
                r"(type|interface|input|enum)(\s*){}".format(name_capture_re),
                bygroups(Keyword.Declaration, Whitespace, Name.Class),
                "type-def",
            ),
            (r"union\b", Keyword.Declaration, "union-def"),
            (r"(?i)[a-z_]\w*(?=\s*:)", Name.Attribute),
            (r"fragment\b", Keyword.Declaration, "fragment-def"),
            (r"(query|mutation|subscription)\b", Keyword, "query"),
            (
                r"(extend)\b(\s*)(type)\b(\s*)" + name_capture_re + r"(\s*)(\{)",
                bygroups(
                    Keyword,
                    Whitespace,
                    Keyword.Declaration,
                    Whitespace,
                    Name.Class,
                    Whitespace,
                    Punctuation,
                ),
                "fields-def",
            ),
            (r"\{", Punctuation, "fields-query"),
            (
                r"(scalar)\b(\s*){}".format(name_capture_re),
                bygroups(Keyword, Whitespace, Name.Class),
            ),
        ],
    }
