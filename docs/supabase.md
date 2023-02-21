## Version Upgrades

See which version is installed, and which is available

```sql
select * from pg_available_extensions;
```

```sql
drop extension pg_graphql;
create extension pg_graphql;
```

## Making a Request

Add `apiKey` header

(double check)
```
https://<project_ref>.supabase.co/graphql/v1
```

### Supabase Studio

add screenshot

### cURL
```
curl ...
```

### supabase-js
```

```

## FAQ

1. Beta test unreleased feature

2. Support for subscriptions

3. ...
