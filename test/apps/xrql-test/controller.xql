xquery version "3.0";

declare variable $exist:path external;
declare variable $exist:resource external;
declare variable $exist:controller external;
declare variable $exist:prefix external;
declare variable $exist:root external;

(: Determine if the persistent login module is available :)
declare variable $login :=
    let $tryImport :=
        try {
            util:import-module(xs:anyURI("http://exist-db.org/xquery/login"), "login", xs:anyURI("resource:org/exist/xquery/modules/persistentlogin/login.xql")),
            true()
        } catch * {
            false()
        }
    return
        if ($tryImport) then
            function-lookup(xs:QName("login:set-user"), 4)
        else
            local:fallback-login#4
;

declare variable $domain := request:get-server-name();
(:~
    Fallback login function used when the persistent login module is not available.
    Stores user/password in the HTTP session.
 :)
declare function local:fallback-login($domain as xs:string, $path as xs:string, $maxAge as xs:dayTimeDuration?, $asDba as xs:boolean) {
    let $durationParam := request:get-parameter("duration", ())
    let $user := request:get-parameter("user", ())
    let $password := request:get-parameter("password", ())
    let $logout := request:get-parameter("logout", ())
    return
        if ($durationParam) then
            error(xs:QName("login"), "Persistent login module not enabled in this version of eXist-db")
        else if ($logout) then
            session:invalidate()
        else 
            if ($user) then
                let $isLoggedIn := xmldb:login("/db", $user, $password, true())
                return
                    if ($isLoggedIn and (not($asDba) or xmldb:is-admin-user($user))) then (
                        session:set-attribute("eXide.user", $user),
                        session:set-attribute("eXide.password", $password),
                        request:set-attribute($domain || ".user", $user),
                        request:set-attribute("xquery.user", $user),
                        request:set-attribute("xquery.password", $password)
                    ) else
                        ()
            else
                let $user := session:get-attribute("eXide.user")
                let $password := session:get-attribute("eXide.password")
                return (
                    request:set-attribute($domain || ".user", $user),
                    request:set-attribute("xquery.user", $user),
                    request:set-attribute("xquery.password", $password)
                )
};

if(starts-with($exist:path,"/model")) then
    let $params := subsequence(tokenize($exist:path,"/"), 3)
    let $model := $params[1]
    let $params := remove($params,1)
    let $id := string-join($params,"/")
    return
    	<dispatch xmlns="http://exist.sourceforge.net/NS/exist">
			<forward url="{$exist:controller}/modules/model.xql">
                {$login("org.exist.login", "/", (), false())}
                <set-header name="Cache-Control" value="no-cache"/>
				<add-parameter name="model" value="{$model}"/>
                <add-parameter name="id" value="{$id}"/>
			</forward>
		</dispatch>
else if(starts-with($exist:path,"/test")) then
	<dispatch xmlns="http://exist.sourceforge.net/NS/exist">
		<forward url="{$exist:controller}/modules/test.xql" />
	</dispatch>
else
    (: everything else is passed through :)
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <cache-control cache="yes"/>
    </dispatch>
