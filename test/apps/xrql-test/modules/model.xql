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

declare function local:resolve-links($node as element(), $schema as element(), $store as xs:string) as element() {
    element json:root {
        $node/node(),
        for $l in $schema/links return
            let $href := tokenize($l/href,"\?")
            let $uri := $href[1]
            let $qstr := $href[2]
            let $qstr := string-join(
                for $x in analyze-string($qstr, "\{([^}]*)\}")/* return
                	if(local-name($x) eq "non-match") then
            			$x
            		else
                        for $g in $x/fn:group
                            return $node/*[local-name() eq $g]
            )
            return
                if($l/resolution eq "lazy") then
                    element { $l/rel } {
                        element { "_ref" } { concat($uri,"?",$qstr) }
                    }
                else
                    let $q := xrql:parse($qstr,())
                    return element { $l/rel } {
                        for $x in xrql:sequence(collection(resolve-uri($uri,$store || "/"))/json:root,$q,500,false()) return
                            element {"json:value"} {
        					    attribute {"json:array"} {"true"},
    						    $x/node()
                            }
                    }
    }
};

let $model := request:get-parameter("model","")
let $method := request:get-method()
let $qstr := request:get-query-string()
let $q := xrql:parse($qstr,())
let $id := request:get-parameter("id","")
let $maxLimit := 100
let $domain := request:get-server-name()
let $store := concat("/db/",$domain,"/model/",$model)
let $schemastore := concat("/db/",$domain,"/model/Class")
let $schemauri := concat($schemastore,"/",$model,".xml")
let $schema :=
    if(doc-available($schemauri)) then
        doc($schemauri)/json:root
    else
        ()
let $data := util:binary-to-string(request:get-data())
let $accept := request:get-header("Accept")
let $null :=
	if(matches($accept,"application/[json|javascript]")) then
		util:declare-option("exist:serialize", "method=json media-type=application/json")
	else if(matches($accept,"[text|application]/xml")) then
		util:declare-option("exist:serialize", "method=xml media-type=application/xml")
	else if(matches($accept,"text/html")) then
		util:declare-option("exist:serialize", "method=html media-type=text/html")
	else
		()

return
    if($model eq "") then
        response:set-status-code(500)
	else if($method = ("PUT","POST")) then
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
		else if($qstr ne "" or request:get-header("range") or sm:is-authenticated()) then
    		element {"json:root"} {
				for $x in xrql:sequence(collection($store)/json:root,$q,$maxLimit) return
					element {"json:value"} {
						attribute {"json:array"} {"true"},
						if($schema) then local:resolve-links($x,$schema,$store)/node() else $x/node()
					}
			}
        else
            (element {"json:root"} {
                "Error: Guests are not allowed to query the entire collection"
            },
            response:set-status-code(403))
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