This guide will show you how to use pg_graphql with [Apollo](https://www.apollographql.com/docs/react/) and [GraphQL Code Generator](https://the-guild.dev/graphql/codegen) for type-safe GraphQL queries in your React application.

## Apollo Setup

### Pre-requisites

1. Follow the [Apollo Getting Started Guide](https://www.apollographql.com/docs/react/get-started).
2. Follow the [GraphQL Code Generator Installation Guide](https://the-guild.dev/graphql/codegen/docs/getting-started/installation).

### Configuring GraphQL Code Generator

Modify your `codegen.ts` file to reflect the following:

```javascript
import type { CodegenConfig } from '@graphql-codegen/cli'
import { addTypenameSelectionDocumentTransform } from '@graphql-codegen/client-preset'

const config: CodegenConfig = {
  schema: 'http://localhost:54321/graphql/v1', // Using the local endpoint, update if needed
  documents: 'src/**/*.tsx',
  overwrite: true,
  ignoreNoDocuments: true,
  generates: {
    'src/gql/': {
      preset: 'client',
      documentTransforms: [addTypenameSelectionDocumentTransform],
      plugins: [],
      config: {
        scalars: {
          UUID: 'string',
          Date: 'string',
          Time: 'string',
          Datetime: 'string',
          JSON: 'string',
          BigInt: 'string',
          BigFloat: 'string',
          Opaque: 'any',
        },
      },
    },
  },
  hooks: {
    afterAllFileWrite: ['npm run prettier'], // optional
  },
}

export default config
```

### Configuring Apollo Client

This example uses [Supabase](https://supabase.com) for the GraphQL server, but pg_graphql can be used independently.

```typescript
import {
  ApolloClient,
  InMemoryCache,
  createHttpLink,
  defaultDataIdFromObject
} from '@apollo/client'
import { setContext } from '@apollo/client/link/context'
import { relayStylePagination } from '@apollo/client/utilities'
import supabase from './supabase'

const cache = new InMemoryCache({
  dataIdFromObject(responseObject) {
    if ('nodeId' in responseObject) {
      return `${responseObject.nodeId}`
    }

    return defaultDataIdFromObject(responseObject)
  },
  possibleTypes: { Node: ['Todos'] } // optional, but useful to specify supertype-subtype relationships
  typePolicies: {
    Query: {
      fields: {
        todosCollection: relayStylePagination(), // example of paginating a collection
        node: {
          read(_, { args, toReference }) {
            const ref = toReference({
              nodeId: args?.nodeId,
            })

            return ref
          },
        },
      },
    },
  },
})

const httpLink = createHttpLink({
  uri: 'http://localhost:54321/graphql/v1',
})

const authLink = setContext(async (_, { headers }) => {
  const token = (await supabase.auth.getSession()).data.session?.access_token

  return {
    headers: {
      ...headers,
      Authorization: token ? `Bearer ${token}` : '',
    },
  }
})

const apolloClient = new ApolloClient({
  link: authLink.concat(httpLink),
  cache,
})

export default apolloClient
```

- `typePolicies.Query.fields.node` is also optional, but useful for reducing cache misses. Learn more about [Redirecting to cached data](https://www.apollographql.com/docs/react/performance/performance#redirecting-to-cached-data).

## Example Query

```javascript
import { useQuery } from '@apollo/client'
import { graphql } from './gql'

const allTodosQueryDocument = graphql(/* GraphQL */ `
  query AllTodos($cursor: Cursor) {
    todosCollection(first: 10, after: $cursor) {
      edges {
        node {
          nodeId
          title
        }
      }
      pageInfo {
        endCursor
        hasNextPage
      }
    }
  }
`)

const TodoList = () => {
  const { data, fetchMore } = useQuery(allTodosQueryDocument)

  return (
    <>
      {data?.thingsCollection?.edges.map(({ node }) => (
        <Todo key={node.nodeId} title={node.title} />
      ))}
      {data?.thingsCollection?.pageInfo.hasNextPage && (
        <Button
          onClick={() => {
            fetchMore({
              variables: {
                cursor: data?.thingsCollection?.pageInfo.endCursor,
              },
            })
          }}
        >
          Load More
        </Button>
      )}
    </>
  )
}

export default TodoList
```
