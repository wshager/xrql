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

declare function local:analyze-string-ordered($string as xs:string, $regex as xs:string,$n as xs:integer ) {
 transform:transform   
(<any/>, 
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="2.0"> 
	<xsl:template match='/' >  
		<xsl:analyze-string regex="{$regex}" select="'{$string}'" > 
			<xsl:matching-substring>
				<xsl:for-each select="1 to {$n}">
					<match>
						<xsl:attribute name="n"><xsl:value-of select="."/></xsl:attribute>
						<xsl:value-of select="regex-group(.)"/>  
					</match>  
				</xsl:for-each> 
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

declare function rql:to-xq-string($value as node()*) {
	if($value/name/text() = $rql:operators) then
		let $path := $value/args[1]/text()
		let $target := $value/args[2]/text()
		return concat($path," ",$value/name/text()," '",$target,"'")
	else if($value/name/text() = ("and","or")) then
		let $terms :=
			for $x in $value/args return
				rql:to-xq-string($x)
		return concat("(",string-join($terms, concat(" ",$value/name/text()," ")),")")
	else if($value/name/text() = ("sort")) then
		let $args := $value/args
		let $sort :=
			for $x in $args return
				if(starts-with($x,"-")) then
					concat(substring($x,2), " descending")
				else
					$x
		return concat("@order by ",string-join($sort,","),"@")
	else if($value/name/text() = ("limit")) then
		let $args := $value/args
		return concat("@limit ",string-join($args,","),"@")
	else
		()
};

declare function rql:to-xq($value as node()*) {
	let $q := rql:to-xq-string($value)
	let $terms := tokenize($q, "@")
	let $sort :=
		for $x in $terms return
			if(contains($x,"order by")) then
				replace($x,"order by ","")
			else
				()
	let $limit :=
		for $x in $terms return
			if(contains($x,"limit")) then
				replace($x, "limit ","")
			else
				()
	let $terms :=
		for $x in $terms return
			if(contains($x,"order by") or contains($x,"limit")) then
				()
			else
				$x
	return
		element root {
			element sort {
				$sort
			},
			element limit {
				$limit
			},
			element terms {
				replace(string-join($terms,"@")," and @","")
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
	let $q := rql:to-xq($value)
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
			$parts[2]
		else
			$string
	(: return converter(string) :)
	return rql:converters-default($string)
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
	let $range :=
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
				return ($limit,$start,$maxCount)
			else
				($limit,$start,$maxCount)
		else
			($limit,$start,$maxCount)
	return string-join($range,",")
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
		if($q/limit) then
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
				let $string := xmldb:decode-uri($string)
				(:
				if($rql:jsonQueryCompatible) then
					if(string.charAt(0) == "'" && string.charAt(string.length-1) == "'"){
						return JSON.parse('"' + string.substring(1,string.length-1) + '"');
					}
				}
				:)
				return $string
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
	let $query := local:setConjunction($query)
	(: (\))|([&\|,])?([\+\*\$\-:\w%\._]*)(\(?) :)
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
	    else if(contains($x,"(")) then
	        concat("<args><name>",replace($x,"\(",""),"</name>")
	    else if($x eq ")") then 
	    	"</args>"
	    else if($x eq ",") then 
	    	"</args><args>"
	    else 
	    	concat("<args>",$x, "</args>")
	   
	return util:parse(string-join($q,""))
};

declare function rql:parse-query($query as xs:string?, $parameters as xs:anyAtomicType?){
	let $query :=
		if(not($query)) then
			""
		else
			$query
	let $term := <root><args /><name>and</name></root>
	let $topTerm := $term
	let $query :=
		if(starts-with($query,"?")) then
			substring($query,2)
		else
			$query
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
	                                                              (:<------- property ------------><----- operator -----><--------- value --------------->:)
	let $matches := $analysis//match
	let $nomatch := $analysis//nomatch
	let $queryp := 
		for $n in 1 to xs:integer(count($matches) div 4) return
			let $property := $matches[@n=1][$n]/text()
			let $operator := $matches[@n=2][$n]/text()
			let $value := $matches[@n=4][$n]/text()
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
	let $queryp := 
		for $n in 1 to count($queryp) return
			concat($queryp[$n],$nomatch[$n]/text())
	
	let $query := string-join($queryp,"")
	return $query
};
