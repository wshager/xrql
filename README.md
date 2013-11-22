xrql
====

An implementation of rql in xquery:

https://github.com/persvr/rql

Test with eXist:
--------

Download and install eXist 2.x @ http://exist-db.org

Build the package and install into eXist using the manager in the dashboard.

To run the test, build an application from "xrql-test" located in the folder "test" and install into eXist.

Point the browser to:

http://localhost:8080/exist/apps/xrql-test/test?price>1.10&sort(name)

---

Paging is enabled through persvr/perstore Range header:

Range : items=0/10

See https://github.com/persvr/perstore

The Accept header is used for content negotiation. Featured types: application/json, application/xml, text/html, text/plain.
