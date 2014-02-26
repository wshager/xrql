xquery version "3.0";

(:
 * This module provides RQL parsing and querying. For example:
 * var parsed = require("./parser").parse("b=3&le(c,5)");
 :)

module namespace xrql="http://lagua.nl/lib/xrql";

declare namespace text="http://exist-db.org/xquery/text";
declare namespace transform="http://exist-db.org/xquery/transform";
declare namespace request="http://exist-db.org/xquery/request";
declare namespace response="http://exist-db.org/xquery/response";

declare function xrql:remove-elements-by-name($nodes as node()*, $names as xs:string*) as node()* {
    for $node in $nodes return
		if($node instance of element()) then
	 		if($node/name = $names) then
				()
			else
				element {node-name($node)} {
					xrql:remove-elements-by-name($node/node(), $names)
				}
		else if ($node instance of document-node())
			then xrql:remove-elements-by-name($node/node(), $names)
		else
			$node
};

declare function xrql:remove-elements-by-property($nodes as node()*, $properties as xs:string*) as node()* {
	for $node in $nodes return
		if($node instance of element()) then
	 		if($node/args[1] = $properties) then
				()
			else
				element {node-name($node)} {
					xrql:remove-elements-by-property($node/node(), $properties)
				}
		else if ($node instance of document-node())
			then xrql:remove-elements-by-property($node/node(), $properties)
		else
			$node
};

declare function xrql:remove-nested-conjunctions($nodes as node()*) as node()* {
	for $node in $nodes return
		if($node instance of element()) then
			if($node/name = ("and","or") and count($node/args) = 0) then
				()
	 		else if($node/name = ("and","or") and count($node/args) = 1) then
				element {node-name($node)} {
					xrql:remove-nested-conjunctions($node/args/*)
				}
			else
				element {node-name($node)} {
					xrql:remove-nested-conjunctions($node/node())
				}
		else
			$node
};

declare function local:analyze-string-ordered($string as xs:string, $regex as xs:string,$n as xs:integer ) {
 transform:transform   
(<any/>, 
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="2.0"> 
	<xsl:template match='/' >
		<xsl:analyze-string regex="{$regex}" select="'{$string}'" > 
			<xsl:matching-substring>
				<matches>
					<xsl:for-each select="1 to {$n}">
						<match>
							<xsl:attribute name="n"><xsl:value-of select="."/></xsl:attribute>
							<xsl:value-of select="regex-group(.)"/>  
						</match>
					</xsl:for-each>
				</matches>
			</xsl:matching-substring>
			<xsl:non-matching-substring>
				<nomatch>
					<xsl:value-of select="."/>  
				</nomatch>
			</xsl:non-matching-substring>  
		</xsl:analyze-string>
	</xsl:template>
</xsl:stylesheet>,
()
)
};

declare variable $xrql:operators := ("eq","gt","ge","lt","le","ne");
declare variable $xrql:methods := ("matches","exists","empty","search","contains");

declare function xrql:declare-namespaces($node as element(),$nss as xs:string*) {
	for $ns in $nss return util:declare-namespace($ns,namespace-uri-for-prefix($ns,$node))
};

declare function xrql:to-xq-string($value as node()*) {
	(: get rid of arrays :)
	let $value := 
		if(name($value/*[1]) eq "args") then
			$value/*[1]
		else
			$value
    let $v := $value/name/text()
	return
	if($v = $xrql:operators) then
		let $path := replace($value/args[1]/text(),"\.",":")
		let $operator := $v
		let $target := xrql:converters-default($value/args[2]/text())
		(: ye olde wildcard :)
		let $operator :=
			if($operator eq "eq" and contains($target,"*")) then
				"wildcardmatch"
			else if($target instance of xs:string) then
				$operator
			else
				$xrql:operatorMap//map[@name eq $operator][1]/@operator
		return
			if($operator eq "wildcardmatch") then
				concat("matches(",$path,",",replace($target,"\*",".*"),",'i'",")")
			else
				concat($path," ",$operator," ", string($target))
	else if($v = $xrql:methods) then
		let $v := if($v eq "search") then "ft:query" else $v
		let $path := replace($value/args[1]/text(),"\.",":")
		let $range :=
			if($value/args[3]) then
				$value/args[3]/text()
			else
				"any"
		let $target := 
			if($value/args[2]) then
				if($v eq "ft:query" and $range eq "phrase") then
					concat(",<phrase>",util:unescape-uri($value/args[2]/text(),"UTF-8"),"</phrase>")
				else
					concat(",",xrql:converters-default($value/args[2]/text()))
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
		return concat($v,"(",$path,$target,$params,")")
	else if($v = "deep") then
		let $path := util:unescape-uri(replace($value/args[1]/text(),"\.",":"),"UTF-8")
		let $expr := xrql:to-xq-string($value/args[2])
		return concat($path,"[",$expr,"]")
	else if($v = ("not")) then
		let $expr := xrql:to-xq-string($value/args)
		return concat("not(",$expr,")")
	else if($v = ("and","or")) then
		let $terms :=
			for $x in $value/args return
				xrql:to-xq-string($x)
		return concat("(",string-join($terms, concat(" ",$v," ")),")")
	else
		""
};

declare function xrql:get-element-by-name($value as node()*,$name as xs:string) {
	if($value/name and $value/name/text() = $name) then
		$value
	else
		for $arg in $value/args return
			xrql:get-element-by-name($arg,$name)
};

declare function xrql:get-element-by-property($value as node()*,$prop as xs:string) {
	for $arg in $value/args return
		let $r := if($arg/position() = 1 and $arg/text() = $prop) then
			subsequence($value/args,2,count($value/args))
		else
			()
		return $r | xrql:get-element-by-property($arg,$prop)
};

declare function xrql:to-xq($value as node()*) {
	let $sort := xrql:get-element-by-name($value,"sort")
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
	let $limit := xrql:get-element-by-name($value,"limit")
	let $filter := xrql:remove-elements-by-name($value,("limit","sort"))
	let $filter := xrql:remove-nested-conjunctions($filter)
	let $filter := xrql:to-xq-string($filter)
	return
		element root {
			element sort {
				string-join($sort,",")
			},
			element limit {
				let $range := $limit/args/text()
				let $limit := string-join($range,",")
				let $limit :=
					if(count($range) > 0 and count($range)<2) then
						concat($limit,",0")
					else
						$limit
				let $limit := 
					if(count($range) > 0 and count($range)<3) then
						concat($limit,",1")
					else
						$limit
				return $limit
			},
			element terms {
				$filter
			}
		}
};

declare function xrql:sequence($items as node()*,$value as node()*, $maxLimit as xs:integer) {
	xrql:sequence($items,$value, $maxLimit, true())
};

declare function xrql:sequence($items as node()*,$value as node()*, $maxLimit as xs:integer, $useRange as xs:boolean) {
	let $q := xrql:to-xq($value/args)
	return xrql:apply-xq($items,$q,$maxLimit,$useRange)
};

declare variable $xrql:operatorMap := element root {
	element map {
		attribute operator {"="},
		attribute name {"eq"}
	},
	element map {
		attribute operator {"=="},
		attribute name {"eq"}
	},
	element map {
		attribute operator {">"},
		attribute name {"gt"}
	},
	element map {
		attribute operator {">="},
		attribute name {"ge"}
	},
	element map {
		attribute operator {"<"},
		attribute name {"lt"}
	},
	element map {
		attribute operator {"<="},
		attribute name {"le"}
	},
	element map {
		attribute operator {"!="},
		attribute name {"ne"}
	}
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

declare function xrql:get-range($maxLimit as xs:integer) {
	(:
	// from https://github.com/persvr/pintura/blob/master/jsgi/rest-store.js
	var limit = Math.min(model.maxLimit||Infinity, model.defaultLimit||Infinity) || Infinity;
	var maxCount = 0; // don't trigger totalCount evaluation unless a valid Range: is seen
	var start = 0;
	var end = Infinity;
	if (metadata.range) {
		var range = metadata.range.match(/^items=(\d+)-(\d+)?$/);
		if (range) {
			start = +range[1] || 0;
			end = range[2];
			end = (end !== undefined) ? +end : Infinity;
			// compose the limit op
			if (end >= start) {
				limit = Math.min(limit, end + 1 - start);
				// trigger totalCount evaluation
				maxCount = Infinity;
			}
		}
		// always honor existing finite model.maxLimit
		if (limit !== Infinity) {
			queryString += "&limit(" + limit + "," + start + "," + maxCount + ")";
			// FIXME: won't be better to not mangle the query and pass limit params via metadata?!
			//metadata.limit = {skip: start, limit: limit, totalCount: maxCount};
		}
	}
	:)
	let $range := request:get-header("Range")
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
						xs:integer($groups[2])
					else
						$start
				
				let $end := 
					if($groups[3]) then
						xs:integer($groups[3])
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
				return concat($limit,",",$start,",",$maxCount)
			else
				concat($limit,",",$start,",",$maxCount)
		else
			concat($limit,",",$start,",",$maxCount)
};

declare function xrql:set-range-header($limit as xs:integer,$start as xs:integer,$maxCount as xs:integer,$totalCount as xs:integer) {
	let $range := concat("items ",min(($start,$totalCount)),"-",min(($start+$limit,$totalCount))-1,"/",$totalCount)
	return
	(
		response:set-header("Accept-Ranges","items"),
		response:set-header("Content-Range",$range)
	)
};

declare function xrql:apply-xq($items as node()*,$q as node()*,$maxLimit as xs:integer) {
	xrql:apply-xq($items,$q,$maxLimit,true())
};

declare function xrql:apply-xq($items as node()*,$q as node()*,$maxLimit as xs:integer, $useRange as xs:boolean){
	let $filter := $q/terms/text()
	let $limit := $q/limit/text()
	let $limit := 
		if($q/limit/text()) then
			$q/limit/text()
		else if($useRange) then
			xrql:get-range($maxLimit)
		else
			"0,0,0"
	let $range := tokenize($limit,",")
	let $limit := xs:integer($range[1])
	let $start := xs:integer($range[2])
	let $maxCount :=
		if($useRange) then
			xs:integer($range[3])
		else
			0
	let $sort := string-join(for $x in tokenize($q/sort,",") return concat("$x/",$x),",")
	(: are there items to return? :)
	let $items := 
			if($filter ne "") then
				util:eval(concat("$items[",$filter,"]"))
			else
				$items
		let $items := 
			if($sort ne "") then
				util:eval(concat("for $x in $items order by ", $sort, " return $x"))
			else
				$items
	return 
		if($maxCount) then
			xrql:apply-paging($items,$limit,$start,$maxCount)
		else
			$items
};

declare function xrql:apply-paging($items as node()*,$limit as xs:integer,$start as xs:integer,$maxCount as xs:integer){
	if($maxCount and $limit and $start < count($items)) then
		(: sequence is 1-based :)
		(: this will return the filtered count :)
		let $totalCount := count($items)
		let $null := xrql:set-range-header($limit,$start,$maxCount,$totalCount)
		let $items :=
			if($limit and $limit < 1 div 0e0) then
				subsequence($items,$start+1,$limit)
			else
				$items
		return $items
	else if($maxCount) then
		let $null := xrql:set-range-header($limit,$start,$maxCount,0)
		return ()
	else
		$items
};

declare variable $xrql:autoConvertedString := (
	"true",
	"false",
	"null",
	"undefined",
	"Infinity",
	"-Infinity"
);

declare variable $xrql:autoConvertedValue := (
	"true()",
	"false()",
	"()",
	"()",
	"1 div 0e0",
	"-1 div 0e0"
);

declare function xrql:converters-auto($string){
	if($xrql:autoConvertedString = $string) then
		$xrql:autoConvertedValue[index-of($xrql:autoConvertedString,$string)]
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
declare function xrql:converters-number($x){
	number($x)
};
declare function xrql:converters-epoch($x){
	(:
		var date = new Date(+x);
		if (isNaN(date.getTime())) {
			throw new URIError("Invalid date " + x);
		}
		return date;
		:)
	$x
};
declare function xrql:converters-isodate($x){
	$x
	(:
		// four-digit year
		var date = '0000'.substr(0,4-x.length)+x;
		// pattern for partial dates
		date += '0000-01-01T00:00:00Z'.substring(date.length);
		return exports.converters.date(date);
	:)
};
declare function xrql:converters-date($x){
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
declare variable $xrql:ignore := "[A-Za-z0-9\+\*\$\-:%\._]";
declare variable $xrql:ignorec := "[A-Za-z0-9\+\*\$\-:%\._,]";

declare function xrql:converters-boolean($x){
	$x eq "true"
};
declare function xrql:converters-string($string){
	xmldb:decode-uri($string)
};
declare function xrql:converters-re($x){
	xmldb:decode-uri($x)
};
declare function xrql:converters-RE($x){
	xmldb:decode-uri($x)
};
declare function xrql:converters-glob($x){
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

declare function xrql:converters-default($x) {
	xrql:converters-auto($x)
};

declare variable $xrql:primaryKeyName := 'id';
declare variable $xrql:lastSeen := ('sort', 'select', 'values', 'limit');
declare variable $xrql:jsonQueryCompatible := true();

declare function xrql:parse($query as xs:string?, $parameters as xs:anyAtomicType?) {
	let $query:= xrql:parse-query($query,$parameters)
	(: (\))|([&\|,])?([\+\*\$\-:\w%\._]*)(\(?) :)
	return if($query ne "") then
		let $analysis := local:analyze-string-ordered($query, concat("(\))|(,)?(",$xrql:ignore,"+)(\(?)"),4)
		
		let $analysis :=
			for $n in 1 to count($analysis) return
				let $x := $analysis[$n]
				return
					if(name($x) eq "nomatch") then
						replace($x,"\(","<args>")
					else
						let $property := $x/match[1]/text()
						let $operator := $x/match[2]/text()
						let $value := $x/match[4]/text()
						let $closedParen := $x/match[1]/text()
						let $delim := $x/match[2]/text()
						let $propertyOrValue := $x/match[3]/text()
						let $openParen := $x/match[4]/text()

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
	let $parts := local:analyze-string-ordered($query,"(\()|(&amp;)|(\|)|(\))",4)
	let $groups := 
		for $i in 1 to count($parts) return
			if(name($parts[$i]) eq "nomatch") then
				element group {
					$parts[$i]/text()
				}
			else
			let $p := $parts[$i]//match/text()
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

declare function xrql:parse-query($query as xs:string?, $parameters as xs:anyAtomicType?){
	let $query :=
		if(not($query)) then
			""
		else
			replace($query," ","%20")
	let $query := replace($query,"%3A",":")
	let $query := replace($query,"%2C",",")
	let $query :=
		if($xrql:jsonQueryCompatible) then
			let $query := fn:replace($query,"%3C=","=le=")
			let $query := fn:replace($query,"%3E=","=ge=")
			let $query := fn:replace($query,"%3C","=lt=")
			let $query := fn:replace($query,"%3E","=gt=")
			return $query
		else
			$query
	let $query :=
		if(contains($query,"/")) then
			let $tokens := tokenize($query,concat("",$xrql:ignore,"*\/[",$xrql:ignore,"\/]*"))
			let $tokens := 
				for $x in $tokens
					return concat("(",replace($x,"\/", ","), ")")
			return string-join($tokens,"")
		else
			$query
	(: convert FIQL to normalized call syntax form :)
	let $analysis := local:analyze-string-ordered($query, concat("(\(",$xrql:ignorec,"+\)|",$xrql:ignore,"*|)([<>!]?=([A-Za-z0-9]*=)?|>|<)(\(",$xrql:ignorec,"+\)|",$xrql:ignore,"*|)"),4)
	                                                              (:<--------------- property ------------><--------- operator --------><---------------- value ---------------->:)
	let $analysis :=
		for $n in 1 to count($analysis) return
			let $x := $analysis[$n]
			return
				if(name($x) eq "nomatch") then
					$x
				else
					let $property := $x/match[1]/text()
					let $operator := $x/match[2]/text()
					let $value := $x/match[4]/text()
					let $operator := 
						if(string-length($operator) < 3) then
							if($xrql:operatorMap//map[@operator=$operator]) then
								$xrql:operatorMap//map[@operator=$operator]/@name
							else
								(:throw new URIError("Illegal operator " + operator):)
								()
						else
							substring($operator, 2, string-length($operator) - 2)
					return concat($operator, "(" , $property , "," , $value , ")")
	let $query := string-join($analysis,"")
	return local:set-conjunction($query)
};

