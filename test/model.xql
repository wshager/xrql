xquery version "3.0";

import module namespace json="http://www.json.org";
import module namespace xdb="http://exist-db.org/xquery/xmldb";
import module namespace xqjson="http://xqilla.sourceforge.net/lib/xqjson";
import module namespace xrql="http://lagua.nl/lib/xrql";

declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare option output:method "json";
declare option output:media-type "application/json";

(:
Transform into xml serializable to json natively by eXist
:)

declare function local:to-plain-xml($node as element()) as element()* {
	let $name := string(node-name($node))
	let $name :=
		if($name = "json") then
			"json:root"
		else if($name = "pair" and $node/@name) then
			$node/@name
		else
			$name
	return
		if($node[@type = "array"]) then
			for $item in $node/node() return
				let $item := element {$name} {
					attribute {"json:array"} {"true"},
						$item/node()
					}
					return local:to-plain-xml($item)
		else
			element {$name} {
				if($node/@type = ("number","boolean")) then
					attribute {"json:literal"} {"true"}
				else
					(),
				$node/@*[matches(name(.),"json:")],
				for $child in $node/node() return
					if($child instance of element()) then
						local:to-plain-xml($child)
					else
						$child
			}
};

let $sess := session:create()
let $model := request:get-parameter("model","")
let $locale := request:get-parameter("locale","")
let $method := request:get-method()
let $qstr := request:get-query-string()
let $q := xrql:parse($qstr,())
let $id := request:get-parameter("id","")
let $maxLimit := 100
let $domain := request:get-server-name()
let $store := concat("/db/",$domain,"/",$locale,"/model/",$model)
let $data := util:binary-to-string(request:get-data())

return
	if($method = ("PUT","POST")) then
		let $data := 
			if($data != "") then
				$data
			else
				"{}"
		let $xml := xqjson:parse-json($data)
		let $xml := local:to-plain-xml($xml)
		let $did := $xml/id/text()
		(: check if id in data:
		this will take precedence, and actually move a resource 
		from the original ID if that ID differs
		:)
		let $oldId := 
			if($did and $id and $did != $id) then
				$id
			else
				""
		let $id :=
			if($did) then
				$did
			else if($id) then
				$id
			else
				util:uuid()
		let $xml := 
			if($did) then
			   $xml
			else
				element {"json:root"} {
					$xml/@*,
					$xml/*[name(.) != "id"],
					element id {
						$id
					}
				}
		let $doc :=
			if(exists(collection($store)/json:root[id = $id])) then
				base-uri(collection($store)/json:root[id = $id])
			else
				$id || ".xml"
		let $res := xdb:store($store, $doc, $xml)
		return
			if($res) then
				$xml
			else
				response:set-status-code(500)
	else if($method="GET") then
		if($id != "") then
			collection($store)/json:root[id = $id]
		else
			element {"json:root"} {
				for $x in xrql:sequence(collection($store)/json:root,$q,$maxLimit) return
					element {"json:value"} {
						attribute {"json:array"} {"true"},
						 $x/node()
					}
			}
	else if($method="DELETE") then
		if($id != "") then
			let $path := base-uri(collection($store)/json:root[id = $id])
			let $parts := tokenize($path,"/")
			let $doc := $parts[last()]
			let $parts := remove($parts,last())
			let $path  := string-join($parts,"/")
			return xmldb:remove($path, $doc)
		else
			response:set-status-code(500)
	else
		response:set-status-code(500)