xquery version "1.0";

declare namespace request="http://exist-db.org/xquery/request";

import module namespace rql="http://lagua.nl/rql" at "rql.xqm";

let $qstr := request:get-query-string()
let $q := rql:parse-query($qstr,())

$q := rql:construct-query-string($q/args)


return $q