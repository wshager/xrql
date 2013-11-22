xrql
====

An implementation of rql in xquery:

https://github.com/persvr/rql

Test with eXist:
--------

Download eXist @ http://exist-db.org

Install & clone xrql into the /eXist/webapp directory. To run the test:

http://localhost:8080/exist/xrql/test/test.xql?price>1.10&sort(name)

Paging is enabled through persvr/perstore Range header:

Range : items=0/10

See https://github.com/persvr/perstore

The Accept header is used for content negotiation. Featured types: application/json, application/xml, text/html, text/plain.
