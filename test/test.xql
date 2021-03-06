xquery version "3.0";

import module namespace rql="http://lagua.nl/lib/rql";

let $q := rql:parse("and(gt(price,1),sort(name))")

let $data :=
<root>
	<item>
		<name>aa</name>
		<price>1.00</price>
	</item>
	<item>
		<name>bb</name>
		<price>1.50</price>
	</item>
	<item>
		<name>cc</name>
		<price>1.00</price>
	</item>
	<item>
		<name>dd</name>
		<price>2.00</price>
	</item>
	<item>
		<name>ee</name>
		<price>1.20</price>
	</item>
	<item>
		<name>ff</name>
		<price>3.00</price>
	</item>
	<item>
		<name>gg</name>
		<price>11.20</price>
	</item>
	<item>
		<name>hh</name>
		<price>1.00</price>
	</item>
	<item>
		<name>ii</name>
		<price>1.00</price>
	</item>
	<item>
		<name>jj</name>
		<price>1.00</price>
	</item>
	<item>
		<name>kk</name>
		<price>1.00</price>
	</item>
	<item>
		<name>ll</name>
		<price>1.00</price>
	</item>
</root>

(: params: data, query, maxLimit :)
return element root {
    rql:sequence($data/item,$q,100)
}


