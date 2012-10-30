xrql
====

An implementation of rql in xquery:

https://github.com/persvr/rql

Testing:
--------
# With eXist

Download eXist @ http://exist-db.org

Install & clone xrql to the /eXist/webapp directory. To run the test:

http://localhost:8080/exist/xrql/test.xql?price>1.10&sort(name)

Paging is enabled through persvr/perstore Range header:

Range : items=0/10

See https://github.com/persvr/perstore

The accept header is used for content negotiation.