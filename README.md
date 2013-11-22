xrql
====

An implementation of rql in xquery:

https://github.com/persvr/rql

Test with eXist:
--------

Download eXist 2.x @ http://exist-db.org

Build the package and install into eXist using the manager in the dashboard.

To run the test, create an application "xrql-test" containing the files in the folder "test".

http://localhost:8080/exist/apps/xrql-test/test.xql?price>1.10&sort(name)

---

Paging is enabled through persvr/perstore Range header:

Range : items=0/10

See https://github.com/persvr/perstore

The Accept header is used for content negotiation. Featured types: application/json, application/xml, text/html, text/plain.
