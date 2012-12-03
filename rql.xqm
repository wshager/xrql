xquery version "1.0";

(:
 * This module provides RQL parsing and querying. For example:
 * var parsed = require("./parser").parse("b=3&le(c,5)");
 :)

module namespace rql="http://lagua.nl/rql";

declare namespace text="http://exist-db.org/xquery/text";
declare namespace transform="http://exist-db.org/xquery/transform";
declare namespace request="http://exist-db.org/xquery/request";
declare namespace response="http://exist-db.org/xquery/response";

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
	 		if($node/name = ("and","or") and count($node/args) = 1) then
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

declare variable $rql:operators := ("eq","gt","ge","lt","le","ne");

declare function rql:to-xq-string($value) {
	if($value/name/text() = $rql:operators) then
		let $path := replace($value/args[1]/text(),"\.",":")
		let $target := $value/args[2]/text()
		return concat($path," ",$value/name/text()," '",$target,"'")
	else if($value/name/text() = ("and","or")) then
		let $terms :=
			for $x in $value/args return
				rql:to-xq-string($x)
		return concat("(",string-join($terms, concat(" ",$value/name/text()," ")),")")
	else
		""
};

declare function local:get-by-name($value as node()*,$name as xs:string) {
	if($value/name and $value/name/text() eq $name) then
		$value
	else
		for $arg in $value/args return
			local:get-by-name($arg,$name)
};

declare function rql:to-xq($value as node()*) {
	let $value := rql:remove-elements-by-property($value,("source","print","embed"))
	let $value := rql:remove-nested-conjunctions($value)
	let $sort := local:get-by-name($value,"sort")
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
	let $limit := local:get-by-name($value,"limit")
	let $filter := rql:remove-elements-by-name($value,("limit","sort"))
	let $filter := rql:remove-nested-conjunctions($filter)
	let $filter := rql:to-xq-string($filter)
	return
		element root {
			element sort {
				$sort
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
				util:unescape-uri($filter,"UTF-8")
			}
		}
};

declare function rql:sequence($items as node()*,$value as node()*, $maxLimit as xs:integer) {
	let $accept := request:get-header("Accept")
	let $null :=
		if($accept = ("application/json","application/javascript")) then
			util:declare-option("exist:serialize", "method=json media-type=application/json")
		else if($accept = ("text/xml","application/xml")) then
			util:declare-option("exist:serialize", "method=xml media-type=application/xml")
		else if($accept = ("text/html")) then
			util:declare-option("exist:serialize", "method=html media-type=text/html")
		else
			()
	let $q := rql:to-xq($value/args)
	return rql:apply-xq($items,$q,$maxLimit)
};

declare variable $rql:operatorMap := element root {
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

declare function local:stringToValue($string, $parameters){
	(: not possible to call anonymous function in xquery 1.0
	$converter := rql:converters-default 
	:)
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
	(:
	let $converter :=
		if(count($parts) gt 1) then
			rql:converters-parts[1]
		else $converter
	:)
	let $string := 
		if(count($parts) gt 1) then
			concat($parts[1],"(",$parts[2],")")
		else
			$string
	return $string
	(: return converter(string) 
	return rql:converters-default($string):)
};

declare function rql:get-range($maxLimit as xs:integer) {
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
						min(($limit, $end - $start))
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

declare function rql:set-range-header($limit as xs:integer,$start as xs:integer,$maxCount as xs:integer,$totalCount as xs:integer) {
	let $range := concat("items ",min(($start,$totalCount)),"-",min(($start+$limit,$totalCount)),"/",$totalCount)
	return
	(
		response:set-header("Accept-Ranges","items"),
		response:set-header("Content-Range",$range)
	)
};

declare function rql:apply-xq($items as node()*,$q as node()*,$maxLimit as xs:integer){
	let $filter := $q/terms/text()
	let $limit := $q/limit/text()
	let $limit := 
		if($q/limit/text()) then
			$q/limit/text()
		else
			rql:get-range($maxLimit)
	let $range := tokenize($limit,",")
	let $limit := xs:integer($range[1])
	let $start := xs:integer($range[2])
	let $maxCount := xs:integer($range[3])
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
			rql:apply-rql-paging($items,$limit,$start,$maxCount)
		else
			$items
};

declare function rql:apply-rql-paging($items as node()*,$limit as xs:integer,$start as xs:integer,$maxCount as xs:integer){
	if($maxCount and $limit and $start < count($items)) then
		(: sequence is 1-based :)
		(: this will return the filtered count :)
		let $totalCount := count($items)
		let $null := rql:set-range-header($limit,$start,$maxCount,$totalCount)
		let $items :=
			if($limit and $limit < 1 div 0e0) then
				subsequence($items,$start+1,$limit)
			else
				$items
		return $items
	else if($maxCount) then
		let $null := rql:set-range-header($limit,$start,$maxCount,0)
		return ()
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
	true(),
	false(),
	(),
	(),
	1 div 0e0,
	-1 div 0e0
);

declare function rql:converters-auto($string){
	if($rql:autoConvertedString = $string) then
		$rql:autoConvertedValue[index-of($rql:autoConvertedString,$string)]
	else
		let $number := number($string)
		return 
			if($number ne 0 and string($number) ne $string) then
				(:let $string := xmldb:decode-uri($string):)
				(:
				if($rql:jsonQueryCompatible) then
					if(string.charAt(0) == "'" && string.charAt(string.length-1) == "'"){
						return JSON.parse('"' + string.substring(1,string.length-1) + '"');
					}
				}
				:)
				$string
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
declare variable $rql:lastSeen := ('sort', 'select', 'values', 'limit');
declare variable $rql:jsonQueryCompatible := true();

declare function local:setConjunction($x){
	if(contains($x,"&amp;")) then
		let $terms := tokenize($x,"&amp;")
		let $terms :=
			for $x in $terms return
				if(contains($x,"|")) then
					concat("or(",string-join(tokenize($x,"\|"),","),")")
				else
					$x
		return concat("and(",string-join($terms,","),")")
	else
		$x
};

declare function rql:parse($query as xs:string?, $parameters as xs:anyAtomicType?) {
	let $query:= rql:parse-query($query,$parameters)
	(: (\))|([&\|,])?([\+\*\$\-:\w%\._]*)(\(?) :)
	return if($query ne "") then
		let $analysis := local:analyze-string-ordered($query, concat("(\))|(,)?(",$rql:ignore,"+)(\(?)"),4)
		
		let $matches := $analysis//match
		let $nomatch := $analysis//nomatch
		
		let $r :=
			for $n in 1 to xs:integer(count($matches) div 4) return
				let $closedParen := $matches[@n=1][$n]/text()
				let $delim := $matches[@n=2][$n]/text()
				let $propertyOrValue := $matches[@n=3][$n]/text()
				let $openParen := $matches[@n=4][$n]/text()
				return 
					if($openParen) then
						concat($propertyOrValue,"(")
					else if($closedParen) then
						")"
					else if($propertyOrValue or $delim eq ",") then
						local:stringToValue($propertyOrValue,())
					else
						()
		let $q := for $x in $r return
			(: treat number separately, throws error on compare :)
			if(string(number($x)) ne "NaN") then
				concat("<args>",$x, "</args>")
			else if(matches($x,"^.*\($")) then
				concat("<args><name>",replace($x,"\(",""),"</name>")
			else if($x eq ")") then 
				"</args>"
			else if($x eq ",") then 
				"</args><args>"
			else 
				concat("<args>",$x, "</args>")
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
	let $pre := concat($groups[@s = 0]/@t,"(")
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
		if(fn:contains($query,"/")) then
			let $tokens := tokenize($query,concat("",$rql:ignore,"*\/[",$rql:ignore,"\/]*"))
			let $tokens := 
				for $x in $tokens
					return concat("(",replace($x,"\/", ","), ")")
			return string-join($tokens,"")
		else
			$query
	(: convert FIQL to normalized call syntax form :)
	let $analysis := local:analyze-string-ordered($query, concat("(\(",$rql:ignorec,"+\)|",$rql:ignore,"*|)([<>!]?=([A-Za-z0-9]*=)?|>|<)(\(",$rql:ignorec,"+\)|",$rql:ignore,"*|)"),4)
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
							if($rql:operatorMap//map[@operator=$operator]) then
								$rql:operatorMap//map[@operator=$operator]/@name
							else
								(:throw new URIError("Illegal operator " + operator):)
								()
						else
							substring($operator, 2, string-length($operator) - 2)
					return concat($operator, "(" , $property , "," , $value , ")")
	let $query := string-join($analysis,"")
	return local:set-conjunction($query)
};

