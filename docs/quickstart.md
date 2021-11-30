If you are new to the project, start here.

The easiest way to try `pg_graphql` is to run the interactive [GraphiQL IDE](https://github.com/graphql/graphiql) demo. The demo environment launches a database, webserver and the GraphiQL IDE/API explorer with a small pre-populated schema.

Requires:

- git
- docker-compose

First, clone the repo

```shell
git clone https://github.com/supabase/pg_graphql.git
cd pg_graphql
```

Next, launch the demo with docker-compose.

```shell
docker-compose up
```
!!! important
    On ARM devices, including M1 Macs, the PostgREST Docker image **requires** >= 4GB of memory **and** 4GB of swap. If you see that PostgREST exit repeatedly, please adjust your memory and swap space settings within Docker.

Finally, access GraphiQL at `http://localhost:4000/`.

![GraphiQL](./assets/quickstart_graphiql.png)
