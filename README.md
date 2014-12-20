rql
====

An implementation of rql in xquery:

https://github.com/persvr/rql

Test with eXist:
--------

Download and install eXist-db 2.x @ http://exist-db.org

Build the package and install into eXist using the manager in the dashboard.

To test, run test.xql from the test folder.

----

Paging is enabled through the Range header:

Range : items=0/10

----

Extensions:

* search(path,query,range): performs a full-text query on Lucene indexes. Word ranges are all, any and phrase
* deep(path,expression): performs a query on nested items using the provided rql expression
