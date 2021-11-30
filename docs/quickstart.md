If you are new to the project, start here.

!!! Important:
The latest PostgREST docker image is not currently compatible with ARM devices, including M1 Macs. That issue is being tracked [here](https://github.com/PostgREST/postgrest/issues/1117). If you are on one of those platforms, see you **must** configure Docket to used 4GB of Memory **_and_** 4GB of Swap so that PostgREST can run properly. If you see that PostgREST starts up, exits, then restarts repeatedly, please adjust your Memory and Swap space settings.

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

Finally, access GraphiQL at `http://localhost:4000/`.

![GraphiQL](./assets/quickstart_graphiql.png)
