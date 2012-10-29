xrql
====

An implementation of rql in xquery:

https://github.com/persvr/rql

Testing:
--------

http://localhost:8080/exist/xrql/test.xql?price>1.10&sort(name)

Paging is enabled through persvr/perstore Range header:

Range : items=0/10

See https://github.com/persvr/perstore