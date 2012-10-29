xquery version "1.0";

declare namespace request="http://exist-db.org/xquery/request";

import module namespace rql="http://lagua.nl/rql" at "rql.xqm";


let $q := rql:parse(request:get-query-string(),())

let $q := rql:query($q/args)


return $sort