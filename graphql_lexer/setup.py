from setuptools import setup, find_packages

setup(
    name='graphql_lexer',
    packages=find_packages(),
    entry_points=
    """
    [pygments.lexers]
    graphqllexer = graphql_lexer:GraphQLLexer
    """,
)
