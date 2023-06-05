pg_graphql implements the [GraphQL Global Object Identification Specification](https://relay.dev/graphql/objectidentification.htm) (`Node` interface) and the [GraphQL Cursor Connections Specification](https://relay.dev/graphql/connections.htm#) to be compatible with [Relay](https://relay.dev/).

## Relay Setup

### Pre-requisites
Follow the [Relay Installation Guide](https://relay.dev/docs/getting-started/installation-and-setup/).

### Configuring the Relay Compiler
Modify your `relay.config.js` file to reflect the following:

   ```javascript
   module.exports = {
     // standard relay config options
     src: './src',
     language: 'typescript',
     schema: './data/schema.graphql',
     exclude: ['**/node_modules/**', '**/__mocks__/**', '**/__generated__/**'],
     // pg_graphql specific options
     schemaConfig: {
       nodeInterfaceIdField: 'nodeId',
       nodeInterfaceIdVariableName: 'nodeId',
     },
     customScalars: {
       UUID: 'string',
       Datetime: 'string',
       JSON: 'string',
       BigInt: 'string',
       BigFloat: 'string',
       Opaque: 'any',
     },
   }
   ```

   - `schemaConfig` tells the Relay compiler where to find the `nodeId` field on the `node` interface
   - `customScalars` will improve Relay's type emission

### Configuring your Relay Environment

   This example uses [Supabase](https://supabase.com) for the GraphQL server, but pg_graphql can be used independently.

   ```typescript
   import {
     Environment,
     FetchFunction,
     Network,
     RecordSource,
     Store,
   } from 'relay-runtime'

   import supabase, { SUPABASE_ANON_KEY, SUPABASE_URL } from './supabase'

   const fetchQuery: FetchFunction = async (operation, variables) => {
     const {
       data: { session },
     } = await supabase.auth.getSession()

     const response = await fetch(`${SUPABASE_URL}/graphql/v1`, {
       method: 'POST',
       headers: {
         'Content-Type': 'application/json',
         apikey: SUPABASE_ANON_KEY,
         Authorization: `Bearer ${session?.access_token ?? SUPABASE_ANON_KEY}`,
       },
       body: JSON.stringify({
         query: operation.text,
         variables,
       }),
     })

     return await response.json()
   }

   const network = Network.create(fetchQuery)
   const store = new Store(new RecordSource())

   const environment = new Environment({
     network,
     store,
     getDataID: (node) => node.nodeId,
     missingFieldHandlers: [
       {
         handle(field, _record, argValues) {
           if (field.name === 'node' && 'nodeId' in argValues) {
             // If field is node(nodeId: $nodeId), look up the record by the value of $nodeId
             return argValues.nodeId
           }

           return undefined
         },
         kind: 'linked',
       },
     ],
   })

   export default environment
   ```

   - `getDataID` is the most important option to add, as it tells Relay how to store data correctly in the cache.
   - `missingFieldHandlers` is optional in this example but helps with [Rendering Partially Cached Data](https://relay.dev/docs/guided-tour/reusing-cached-data/rendering-partially-cached-data/).

## Pagination

Say you are working on a Todo app and want to add pagination. You can use `@connection` and `@prependNode` to do this.

**Fragment passed to `usePaginationFragment()`**

```graphql
fragment TodoList_query on Query
@argumentDefinitions(
  cursor: { type: "Cursor" }
  count: { type: "Int", defaultValue: 20 }
)
@refetchable(queryName: "TodoListPaginationQuery") {
  todosCollection(after: $cursor, first: $count)
    @connection(key: "TodoList_query_todosCollection") {
    pageInfo {
      hasNextPage
      endCursor
    }
    edges {
      cursor
      node {
        nodeId
        ...TodoItem_todos
      }
    }
  }
}
```

**Mutation to create a new Todo**

```graphql
mutation TodoCreateMutation($input: TodosInsertInput!, $connections: [ID!]!) {
  insertIntoTodosCollection(objects: [$input]) {
    affectedCount
    records @prependNode(connections: $connections, edgeTypeName: "TodosEdge") {
      ...TodoItem_todos
    }
  }
}
```

**Code to call the mutation**

```typescript
import { ConnectionHandler, graphql, useMutation } from 'react-relay'

// inside a React component
const [todoCreateMutate, isMutationInFlight] =
  useMutation<TodoCreateMutation>(CreateTodoMutation)

// inside your create todo function
const connectionID = ConnectionHandler.getConnectionID(
  'root',
  'TodoList_query_todosCollection'
)

todoCreateMutate({
  variables: {
    input: {
      // ...new todo data
    },
    connections: [connectionID],
  },
})
```
