xquery version "3.0";

(:
 * This module provides RQL parsing and querying. For example:
 * var parsed = require("./parser").parse("b=3&le(c,5)");
 :)

module namespace rql="http://lagua.nl/lib/rql";

declare namespace text="http://exist-db.org/xquery/text";
declare namespace request="http://exist-db.org/xquery/request";
declare namespace response="http://exist-db.org/xquery/response";


declare function rql:to-string($q as node()*) {
    if($q/name) then
        concat($q/name,"(",
            string-join(
                for $x in $q/args return
                    if($x/args) then
                        rql:to-string($x)
                    else
                        $x
            ,",")
        ,")")
    else if($q/args) then
       if($q/args/*) then
            rql:to-string($q/args)
        else
            "(" || string-join($q/args,",") || ")"
    else
    	"" 
};

declare function rql:remove-elements-by-name($nodes as node()*, $names as xs:string*) as node()* {
    for $node in $nodes return
		if($node instance of element()) then
	 		if($node/name = $names) then
				()
			else
				element {node-name($node)} {
					rql:remove-elements-by-name($node/node(), $names)
				}
		else if ($node instance of document-node())
			then rql:remove-elements-by-name($node/node(), $names)
		else
			$node
};

declare function rql:remove-elements-by-property($nodes as node()*, $properties as xs:string*) as node()* {
	for $node in $nodes return
		if($node instance of element()) then
	 		if($node/args[1] = $properties) then
				()
			else
				element {node-name($node)} {
					rql:remove-elements-by-property($node/node(), $properties)
				}
		else if ($node instance of document-node())
			then rql:remove-elements-by-property($node/node(), $properties)
		else
			$node
};

declare function rql:remove-nested-conjunctions($nodes as node()*) as node()* {
	for $node in $nodes return
		if($node instance of element()) then
			if($node/name = ("and","or") and count($node/args) = 0) then
				()
	 		else if($node/name = ("and","or") and count($node/args) = 1) then
				element {node-name($node)} {
					rql:remove-nested-conjunctions($node/args/*)
				}
			else
				element {node-name($node)} {
					rql:remove-nested-conjunctions($node/node())
				}
		else
			$node
};

declare variable $rql:operators := ("eq","gt","ge","lt","le","ne");
declare variable $rql:methods := ("matches","exists","empty","search","contains","in","string","integer","boolean","lower-case","upper-case");
declare variable $rql:aggregators := ("count","sum","mean","avg","max","min","values","distinct-values");
declare variable $rql:operatorMap := map {
	"=" := "eq",
	"==" := "eq",
	">" := "gt",
	">=" := "ge",
	"<" := "lt",
	"<=" := "le",
	"!=" := "ne",
	"values" := "ne",
	"!=" := "distinct-values",
	"mean" := "avg"
};


declare function rql:declare-namespaces($node as element(),$nss as xs:string*) {
	for $ns in $nss return util:declare-namespace($ns,namespace-uri-for-prefix($ns,$node))
};

declare function rql:to-xq-string($value as node()*) {
	(: get rid of arrays :)
	let $value := 
		if(name($value/*[1]) eq "args") then
			$value/*[1]
		else
			$value
    let $v := $value/name/text()
	return
	if($v = $rql:operators) then
		let $path :=
			if($value/args[1]/args) then
				rql:to-xq-string($value/args[1])
			else
				util:unescape-uri(replace($value/args[1]/text(),"\.",":"),"UTF-8")
		let $operator := $v
		let $target :=
			if($value/args[2]/args) then
				rql:to-xq-string($value/args[2])
			else
				rql:converters-default($value/args[2]/text())
		(: ye olde wildcard :)
		let $operator :=
			if($value/args[2]/args) then
				$operator
			else if($operator eq "eq" and contains($target,"*")) then
				"wildcardmatch"
			else if($target instance of xs:double) then
				(: reverse lookup :)
				let $operator := 
					for $k in map:keys($rql:operatorMap) return
					    if($rql:operatorMap($k) eq $operator) then
					        $k
					    else
					        ()
				return $operator[last()]
			else
				$operator
		return
			if($operator eq "wildcardmatch") then
				concat("matches(",$path,",'^",replace($value/args[2]/text(),"\*",".*"),"$','i'",")")
			else
				concat($path," ",$operator," ", string($target))
	else if($v = $rql:methods) then
		let $v :=
			if($v eq "search") then
				"ft:query"
			else $v
		let $path :=
			if($value/args[1]/args) then
				rql:to-xq-string($value/args[1])
			else
				util:unescape-uri(replace($value/args[1]/text(),"\.",":"),"UTF-8")
		let $range :=
			if($value/args[3]) then
				$value/args[3]/text()
			else
				"any"
		let $target := 
			if($value/args[2]) then
				if($v eq "ft:query" and $range eq "phrase") then
					concat(",<phrase>",util:unescape-uri($value/args[2]/text(),"UTF-8"),"</phrase>")
				else if($v eq "in") then
					string-join(for $x in $value/args[2]/args return rql:converters-default($x/text()),",")
				else
					concat(",",rql:converters-default($value/args[2]/text()))
			else
				""
		let $params := 
			if($v eq "ft:query") then
				concat(",<options><default-operator>",(
					if($range eq "any") then
						"or"
					else
						"and"
				),"</default-operator></options>")
			else
				""
		return
			if($v eq "in") then
				concat($path,"=(",$target,")")
			else
				concat($v,"(",$path,$target,$params,")")
	else if($v = "deep") then
		let $path :=
			if($value/args[1]/args) then
				rql:to-xq-string($value/args[1])
			else
				util:unescape-uri(replace($value/args[1]/text(),"\.",":"),"UTF-8")
		let $expr := rql:to-xq-string($value/args[2])
		return concat($path,"[",$expr,"]")
	else if($v = ("not")) then
		let $expr := rql:to-xq-string($value/args)
		return concat("not(",$expr,")")
	else if($v = ("and","or")) then
		let $terms :=
			for $x in $value/args return
				rql:to-xq-string($x)
		return concat("(",string-join($terms, concat(" ",$v," ")),")")
	else
		""
};

declare function rql:get-element-by-name($value as node()*,$name as xs:string) {
	if($value/name and $value/name/text() = $name) then
		$value
	else
		for $arg in $value/args return
			rql:get-element-by-name($arg,$name)
};

declare function rql:get-elements-by-name($value as node()*,$name as xs:string*) {
	for $n in $name return
		rql:get-element-by-name($value,$n)
};

declare function rql:get-element-by-property($value as node()*,$prop as xs:string) {
	for $arg in $value/args return
		let $r := if($arg/position() = 1 and $arg/text() = $prop) then
			subsequence($value/args,2,count($value/args))
		else
			()
		return $r | rql:get-element-by-property($arg,$prop)
};

declare function rql:to-xq($value as node()*) {
	let $sort := rql:get-element-by-name($value,"sort")
	let $sort :=
			for $x in $sort/args/text() return
				let $x := util:unescape-uri(replace($x,"\.",":"),"UTF-8")
				return
					if(starts-with($x,"-")) then
						concat(substring($x,2), " descending")
					else if(starts-with($x,"+")) then
						substring($x,2)
					else
						$x
	let $limit := rql:get-element-by-name($value,"limit")
	let $aggregate := rql:get-elements-by-name($value,$rql:aggregators)
	let $filter := rql:remove-elements-by-name($value,insert-before(("limit","sort"),0,$rql:aggregators))
	let $filter := rql:remove-nested-conjunctions($filter)
	let $filter := rql:to-xq-string($filter)
	let $limit := $limit/args/text()
	let $limit :=
		if(count($limit) > 0 and count($limit)<2) then
			insert-before(0,0,$limit)
		else
			$limit
	let $limit := 
		if(count($limit) > 0 and count($limit)<3) then
			insert-before(1,0,$limit)
		else
			$limit
	return
		map {
			"sort" := $sort,
			"limit" := $limit,
			"filter" :=	$filter,
			"aggregate" := $aggregate[1]/args (: use only the first, aggregate may not be combined :) 
		}
};

declare function rql:sequence($items as node()*,$value as node()*, $maxLimit as xs:integer) {
	rql:sequence($items,$value, $maxLimit, "")
};

declare function rql:sequence($items as node()*,$value as node()*, $maxLimit as xs:integer, $range as xs:string) {
	let $q := rql:to-xq($value/args)
	let $filter := $q("filter")
	let $aggregate := $q("aggregate")
	let $sort := $q("sort")
	let $limit := 
		if($q("limit")) then
			$q("limit")
		else if($range) then
			rql:get-limit-from-range($range,$maxLimit)
		else
			(0,0,0)
	
	(: filter :)
	let $items := rql:xq-filter($items,$filter,$aggregate)
	(: sort, but only if returns a sequence :)
	let $items := 
		if($aggregate) then
			$items
		else
			rql:xq-sort($items,$sort)
	return
		if($range and not($aggregate)) then
			rql:xq-limit($items, $limit)
		else
			$items
};

declare function local:stringToValue($string as xs:string, $parameters){
	let $param-index :=
		if(starts-with($string,"$")) then
			number(substring($string,2)) - 1
		else
			0
	let $string := 
		if($param-index ge 0 and exists($parameters)) then
			$parameters[$param-index]
		else
			$string
	let $parts :=
		if(contains($string,":")) then
			tokenize($string,":")
		else
			()
	let $string := 
		if(count($parts) > 1) then
			(: check for possible typecast :)
			let $cast := $parts[1]
			return
				if(matches($cast,"^([^.]*(xs|fn)\.[^.]+)|([^.]*(number|text|string|\-case))$"))then
					let $path := string-join(subsequence($parts,2,count($parts)),":")
					return concat($cast,"(",$path,")")
				else
					$string
		else
			$string
	return $string
};

declare function rql:get-limit-from-range($range as xs:string, $maxLimit as xs:integer) {
	let $maxCount := 0
	let $limit := 
		if($maxLimit) then
			$maxLimit
		else
			1 div 0e0
	let $start := 0
	let $end := 1 div 0e0
	return
		if($range) then
			let $groups := text:groups($range, "^items=(\d+)-(\d+)?$")
			return
			if(count($groups)>0) then
				let $start := 
					if($groups[2]) then
						number($groups[2])
					else
						$start
				
				let $end := 
					if($groups[3]) then
						number($groups[3])
					else
						$end
				let $limit :=
					if($end >= $start) then
						min(($limit, $end + 1 - $start))
					else
						$limit
				let $maxCount :=
					if($end >= $start) then
						1
					else
						$maxCount
				return ($limit,$start,$maxCount)
			else
				($limit,$start,$maxCount)
		else
			($limit,$start,$maxCount)
};

declare function rql:get-content-range-header($ranges as xs:integer*,$totalcount as xs:integer) {
	concat("items ",min(($ranges[2],$totalcount)),"-",min(($ranges[2]+$ranges[1],$totalcount))-1,"/",$totalcount)
};

declare function rql:xq-filter($items as node()*, $filter as xs:string) {
	rql:xq-filter($items,$filter,())
};

declare function rql:xq-filter($items as node()*, $filter as xs:string, $aggregate as node()?) {
	(: are there items to return? :)
	let $items := 
		if($filter ne "") then
			util:eval(concat("$items[",$filter,"]"))
		else
			$items
	return rql:xq-aggregate($items,$aggregate)
};

declare function rql:xq-aggregate($items as node()*, $aggregate as node()?) {
	if($aggregate and $aggregate/name) then
		let $operator := $aggregate/name/text()
		let $operator := 
			if(map:contains($rql:operatorMap,$operator)) then
				$rql:operatorMap($operator)
			else
				$operator
		let $path := $aggregate/args[1]/text()
		return util:eval($operator || "($items/" || $path || ")")
	else
		$items
};

declare function rql:xq-sort($items as node()*, $sort as xs:string*) {
	if(exists($sort)) then
		util:eval(concat("for $x in $items order by ", string-join(for $x in $sort return concat("$x/",$x),","), " return $x"))
	else
		$items
};

declare function rql:xq-limit($items as node()*, $ranges as xs:integer*) {
	let $limit := $ranges[1]
	let $start := $ranges[2]
	let $maxCount := $ranges[3]
	return
		if($maxCount and $limit and $start < count($items)) then
			(: sequence is 1-based :)
			(: this will return the filtered count :)
			let $totalCount := count($items)
			let $items :=
				if($limit and $limit < 1 div 0e0) then
					subsequence($items,$start+1,$limit)
				else
					$items
			return $items
		else if($maxCount) then
			()
		else
			$items
};

declare variable $rql:autoConvertedString := (
	"true",
	"false",
	"null",
	"undefined",
	"Infinity",
	"-Infinity"
);

declare variable $rql:autoConvertedValue := (
	"true()",
	"false()",
	"()",
	"()",
	"1 div 0e0",
	"-1 div 0e0"
);

declare function rql:converters-auto($string){
	if($rql:autoConvertedString = $string) then
		$rql:autoConvertedValue[index-of($rql:autoConvertedString,$string)]
	else
		let $number := number($string)
		return 
			if($number ne 0 and string($number) ne $string) then
				if(contains($string,"(")) then
					util:unescape-uri($string,"UTF-8")
				else
					concat("'",util:unescape-uri($string,"UTF-8"),"'")
			else
				$number
};
declare function rql:converters-number($x){
	number($x)
};
declare function rql:converters-epoch($x){
	(:
		var date = new Date(+x);
		if (isNaN(date.getTime())) {
			throw new URIError("Invalid date " + x);
		}
		return date;
		:)
	$x
};
declare function rql:converters-isodate($x){
	$x
	(:
		// four-digit year
		var date = '0000'.substr(0,4-x.length)+x;
		// pattern for partial dates
		date += '0000-01-01T00:00:00Z'.substring(date.length);
		return exports.converters.date(date);
	:)
};
declare function rql:converters-date($x){
	$x
	(:
		var isoDate = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2}(?:\.\d*)?)Z$/.exec(x);
		if (isoDate) {
			date = new Date(Date.UTC(+isoDate[1], +isoDate[2] - 1, +isoDate[3], +isoDate[4], +isoDate[5], +isoDate[6]));
		}else{
			date = new Date(x);
		}
		if (isNaN(date.getTime())){
			throw new URIError("Invalid date " + x);
		}
		return date;
	:)
};

(: original character class [\+\*\$\-:\w%\._] or with comma :)
declare variable $rql:ignore := "[A-Za-z0-9\+\*\$\-:%\._]";
declare variable $rql:ignorec := "[A-Za-z0-9\+\*\$\-:%\._,]";

declare function rql:converters-boolean($x){
	$x eq "true"
};
declare function rql:converters-string($string){
	xmldb:decode-uri($string)
};
declare function rql:converters-re($x){
	xmldb:decode-uri($x)
};
declare function rql:converters-RE($x){
	xmldb:decode-uri($x)
};
declare function rql:converters-glob($x){
	$x
	(:
		var s = decodeURIComponent(x).replace(/([\\|\||\(|\)|\[|\{|\^|\$|\*|\+|\?|\.|\<|\>])/g, function(x){return '\\'+x;}).replace(/\\\*/g,'.*').replace(/\\\?/g,'.?');
		if (s.substring(0,2) !== '.*') s = '^'+s; else s = s.substring(2);
		if (s.substring(s.length-2) !== '.*') s = s+'$'; else s = s.substring(0, s.length-2);
		return new RegExp(s, 'i');
	:)
};

(:
// exports.converters["default"] can be changed to a different converter if you want
// a different default converter, for example:
// RP = require("rql/parser");
// RP.converters["default"] = RQ.converter.string;
:)

declare function rql:converters-default($x) {
	rql:converters-auto($x)
};

declare variable $rql:primaryKeyName := 'id';
declare variable $rql:jsonQueryCompatible := true();


declare function rql:parse($query as xs:string) {
	rql:parse($query, ())
};

declare function rql:parse($query as xs:string?, $parameters as xs:anyAtomicType?) {
	let $query:= rql:parse-query($query,$parameters)
	(: (\))|([&\|,])?([\+\*\$\-:\w%\._]*)(\(?) :)
	return if($query ne "") then
		let $analysis := analyze-string($query, concat("(\))|(,)?(",$rql:ignore,"+)(\(?)"))
		
		let $analysis :=
			for $x in $analysis/* return
					if(name($x) eq "non-match") then
						replace(replace($x,",",""),"\(","<args>")
					else
						let $property := $x/fn:group[@nr=1]/text()
						let $operator := $x/fn:group[@nr=2]/text()
						let $value := $x/fn:group[@nr=4]/text()
						let $closedParen := $x/fn:group[@nr=1]/text()
						let $delim := $x/fn:group[@nr=2]/text()
						let $propertyOrValue := $x/fn:group[@nr=3]/text()
						let $openParen := $x/fn:group[@nr=4]/text()

				let $r := 
					if($openParen) then
						concat($propertyOrValue,"(")
					else if($closedParen) then
						")"
					else if($propertyOrValue or $delim eq ",") then
						local:stringToValue($propertyOrValue,())
					else
						()
				return for $s in $r return
					(: treat number separately, throws error on compare :)
					if(string(number($s)) ne "NaN") then
						concat("<args>",$s, "</args>")
					else if(matches($s,"^.*\($")) then
						concat("<args><name>",replace($s,"\(",""),"</name>")
					else if($s eq ")") then 
						"</args>"
					else if($s eq ",") then 
						"</args><args>"
					else 
						concat("<args>",$s, "</args>")
		let $q := string-join($analysis,"")
		return util:parse(string-join($q,""))
	else
		<args/>
};

declare function local:no-conjunction($seq,$hasopen) {
	if($seq[1]/text() eq ")") then
		if($hasopen) then
			local:no-conjunction(subsequence($seq,2,count($seq)),false())
		else
			$seq[1]
	else if($seq[1]/text() = ("&amp;", "|")) then
		false()
	else if($seq[1]/text() eq "(") then
		local:no-conjunction(subsequence($seq,2,count($seq)),true())
	else
		false()
};

declare function local:set-conjunction($query as xs:string) {
	let $parts := analyze-string($query,"(\()|(&amp;)|(\|)|(\))")/*
	let $groups := 
		for $i in 1 to count($parts) return
			if(name($parts[$i]) eq "non-match") then
				element group {
					$parts[$i]/text()
				}
			else
			let $p := $parts[$i]/fn:group/text()
			return
				if($p eq "(") then
						element group {
							attribute i {$i},
							$p
						}
				else if($p eq "|") then
						element group {
							attribute i {$i},
							$p
						}
				else if($p eq "&amp;") then
						element group {
							attribute i {$i},
							$p
						}
				else if($p eq ")") then
						element group {
							attribute i {$i},
							$p
						}
				else
					()
	let $cnt := count($groups)
	let $remove :=
		for $n in 1 to $cnt return
			let $p := $groups[$n]
			return
				if($p/@i and $p/text() eq "(") then
					let $close := local:no-conjunction(subsequence($groups,$n+1,$cnt)[@i],false())
					return 
						if($close) then
							(string($p/@i),string($close/@i))
						else
							()
				else
					()
	let $groups :=
		for $x in $groups return
			if($x/@i = $remove) then
				element group {$x/text()}
			else
				$x
	let $groups :=
		for $n in 1 to $cnt return
			let $x := $groups[$n]
			return
				if($x/@i and $x/text() eq "(") then
					let $conjclose :=
						for $y in subsequence($groups,$n+1,$cnt) return
							if($y/@i and $y/text() = ("&amp;","|",")")) then
								$y
							else
								()
					let $t := $conjclose[text() = ("&amp;","|")][1]
					let $conj :=
						if($t/text() eq "|") then
							"or"
						else
							"and"
					let $close := $conjclose[text() eq ")"][1]/@i
					return
						element group {
							attribute c {$t/@i},
							attribute e {$close},
							concat($conj,"(")
						}
				else if($x/text() = ("&amp;","|")) then
					element group {
						attribute i {$x/@i},
						attribute e {10e10},
						attribute t {
							if($x/text() eq "|") then
								"or"
							else
								"and"
						},
						","
					}
				else
					$x
	let $groups :=
		for $n in 1 to $cnt return
			let $x := $groups[$n]
			return
				if($x/@i and not($x/@c) and $x/text() ne ")") then
					let $seq := subsequence($groups,1,$n - 1)
					let $open := $seq[@c eq $x/@i]
					return
						if($open) then
							element group {
								attribute s {$x/@i},
								attribute e {$open/@e},
								","
							}
						else
							$x
				else
					$x
	let $groups :=
		for $n in 1 to $cnt return
			let $x := $groups[$n]
			return
				if($x/@i and not($x/@c) and $x/text() ne ")") then
					let $seq := subsequence($groups,1,$n - 1)
					let $open := $seq[@c eq $x/@i][last()]
					let $prev := $seq[text() eq ","][last()]
					let $prev := 
							if($prev and $prev/@e < 10e10) then
								$seq[@c = $prev/@s]/@c
							else
								$prev/@i
					return
						if($open) then
							$x
						else
							element group {
								attribute i {$x/@i},
								attribute t {$x/@t},
								attribute e {$x/@e},
								attribute s {
									if($prev) then
										$prev
									else
										0
								},
								","
							}
				else
					$x
	let $groups :=
			for $n in 1 to $cnt return
				let $x := $groups[$n]
				return
					if($x/@i or $x/@c) then
						let $start := $groups[@s eq $x/@i] | $groups[@s eq $x/@c]
						return
							if($start) then
								element group {
									$x/@*,
									if($x/@c) then
										concat($start/@t,"(",$x/text())
									else
										concat($x/text(),$start/@t,"(")
								}
							else
								$x
					else
						$x
	let $pre := 
		if(count($groups[@s = 0]) > 0) then
			concat($groups[@s = 0]/@t,"(")
		else
			""
	let $post := 
		for $x in $groups[@e = 10e10] return
			")"
	return concat($pre,string-join($groups,""),string-join($post,""))
};

declare function rql:parse-query($query as xs:string?, $parameters as xs:anyAtomicType?){
	let $query :=
		if(not($query)) then
			""
		else
			replace($query," ","%20")
	let $query := replace($query,"%3A",":")
	let $query := replace($query,"%2C",",")
	let $query :=
		if($rql:jsonQueryCompatible) then
			let $query := fn:replace($query,"%3C=","=le=")
			let $query := fn:replace($query,"%3E=","=ge=")
			let $query := fn:replace($query,"%3C","=lt=")
			let $query := fn:replace($query,"%3E","=gt=")
			return $query
		else
			$query
	let $query :=
		if(contains($query,"/")) then
			let $tokens := tokenize($query,concat("",$rql:ignore,"*/",substring($rql:ignore,1,string-length($rql:ignore)-1),"/]*"))
			let $replaced := fold-left(?,$query,function($q, $x) {
				if($x) then
					replace($q,$x,"?")
				else
					$q
			})
			let $tokens := tokenize($replaced($tokens),"\?")
			let $slashed := fold-left(?,$query,function($q, $x) {
				if($x) then
					replace($q,$x,concat("(",replace($x,"/", ","), ")"))
				else
					$q
			})
			return $slashed($tokens)
		else
			$query
		(: convert FIQL to normalized call syntax form :)
		let $analysis := analyze-string($query, concat("(\(",$rql:ignorec,"+\)|",$rql:ignore,"*|)([<>!]?=([A-Za-z0-9]*=)?|>|<)(\(",$rql:ignorec,"+\)|",$rql:ignore,"*|)"))
		
		let $analysis :=
			for $x in $analysis/* return
				if(name($x) eq "non-match") then
					$x
				else
					let $property := $x/fn:group[@nr=1]/text()
					let $operator := $x/fn:group[@nr=2]/text()
					let $value := $x/fn:group[@nr=4]/text()
					let $operator := 
						if(string-length($operator) < 3) then
							if(map:contains($rql:operatorMap,$operator)) then
								$rql:operatorMap($operator)
							else
								(:throw new URIError("Illegal operator " + operator):)
								()
						else
							substring($operator, 2, string-length($operator) - 2)
					return concat($operator, "(" , $property , "," , $value , ")")
	let $query := string-join($analysis,"")
	return local:set-conjunction($query)
};