
On a machine with:

- 4 CPUs
- 16GB of RAM
- PostgreSQL 13 (docker)
- Postgrest +8 (docker, operating as webserver)

pg_graphql served a simple query at an average rate of +2200 req/second.


```
This is ApacheBench, Version 2.3 <$Revision: 1843412 $>

Benchmarking 0.0.0.0 (be patient)
Finished 8000 requests


Server Software:        postgrest/8.0.0
Server Hostname:        0.0.0.0
Server Port:            3000

Document Path:          /rpc/graphql
Document Length:        46 bytes

Concurrency Level:      8
Time taken for tests:   3.628 seconds
Complete requests:      8000
Failed requests:        0
Total transferred:      1768000 bytes
Total body sent:        1928000
HTML transferred:       368000 bytes
Requests per second:    2205.21 [#/sec] (mean)
Time per request:       3.628 [ms] (mean)
Time per request:       0.453 [ms] (mean, across all concurrent requests)
Transfer rate:          475.93 [Kbytes/sec] received
                        519.00 kb/s sent
                        994.93 kb/s total

Connection Times (ms)
              min  mean[+/-sd] median   max
Connect:        0    0   0.1      0       2
Processing:     1    4   3.7      2      39
Waiting:        0    3   3.6      2      39
Total:          1    4   3.7      2      39

Percentage of the requests served within a certain time (ms)
  50%      2
  66%      3
  75%      3
  80%      4
  90%      7
  95%     10
  98%     15
  99%     22
 100%     39 (longest request)
```

To reproduce this result, start the demo described in the [quickstart guide](quickstart.md) and apache bench on a sample query.

i.e.

```shell
docker-compose up

echo '{"query": "{ account(nodeId: $nodeId) { id }}", "variables": {"nodeId": "WyJhY2NvdW50IiwgMV0="}}' > query.json

ab -n 8000 -c 8 -T application/json -p query.json http://0.0.0.0:3000/rpc/graphql
```
