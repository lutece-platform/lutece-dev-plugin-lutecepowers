#!/usr/bin/env bash
# Checks three things the e2e bench needs to credit MVC screens: the inventory reads the @View/@Action methods and
# the constants a controller inherits from an abstract parent (tools/inventory.py), a navigation keeps its whole url
# so a long query still names its view or action (lutece.observe), and the DOM classification survives a page that
# navigates by itself while it is read (lutece.classify).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
E2E="$HERE/../../skills/lutece-e2e"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/src/java/p/web"
cat > "$T/src/java/p/web/AbstractThingJspBean.java" <<'JAVA'
package p.web;
import fr.paris.lutece.portal.util.mvc.commons.annotations.View;
import fr.paris.lutece.portal.util.mvc.commons.annotations.Action;
public abstract class AbstractThingJspBean extends MVCAdminJspBean
{
    public static final String CONTROLLER_PATH = "jsp/admin/plugins/p/thing/";
    public static final String VIEW_SHARED = "sharedView";
    @View( VIEW_SHARED )
    public String sharedView( HttpServletRequest request ) { return null; }
    @Action( value = "sharedAction", securityTokenDisabled = true )
    public String doShared( HttpServletRequest request ) { return null; }
}
JAVA
cat > "$T/src/java/p/web/ThingJspBean.java" <<'JAVA'
package p.web;
import fr.paris.lutece.portal.util.mvc.admin.annotations.Controller;
import fr.paris.lutece.portal.util.mvc.commons.annotations.View;
@Controller( controllerJsp = ThingJspBean.CONTROLLER_JSP, controllerPath = ThingJspBean.CONTROLLER_PATH, right = "P_THING" )
public class ThingJspBean extends AbstractThingJspBean
{
    public static final String CONTROLLER_JSP = "ManageThing.jsp";
    @View( value = "ownView", defaultView = true )
    public String ownView( HttpServletRequest request ) { return null; }
}
JAVA
out=$(python3 - "$E2E" "$T" <<'PY'
import pathlib, sys
e2e, root = sys.argv[1], pathlib.Path(sys.argv[2])
sys.path.insert(0, e2e + "/tools")
sys.path.insert(0, e2e + "/tests")
import inventory, lutece
try:
    screens, actions = inventory.mvc_inventory(root)
    print(" ".join(sorted(x["url"] for x in screens + actions)))
except Exception as e:
    print("inventory crashed", type(e).__name__)

class Req:
    resource_type, post_data_buffer, frame = "document", None, "main"
    timing = {"responseStart": 1, "requestStart": 0}
    def is_navigation_request(self): return True
class Resp:
    status, headers, request = 200, {}, Req()
    def __init__(self, url): self.url = url
class Page:
    main_frame = "main"
    def __init__(self): self.handlers, self.calls = {}, 0
    def on(self, event, fn): self.handlers[event] = fn
    def wait_for_load_state(self, state): pass
    def evaluate(self, script):
        self.calls += 1
        if self.calls == 1:
            raise RuntimeError("Page.evaluate: Execution context was destroyed, most likely because of a navigation")
        return {"menu": True, "footer": True, "login": False, "danger": False, "warning": False, "card": False,
                "forms": 0, "fo": False, "foAlert": False, "layout": True, "text": "a screen"}
page = Page()
lutece.observe(page)
long = "http://localhost/lutece/jsp/admin/plugins/p/thing/ManageThing.jsp?" + "x=" + "a" * 250 + "&action=sharedAction"
page.handlers["response"](Resp(long))
print(page.obs["nav"][0]["url"] == long)
try:
    lutece.classify(page)
    print("classified", page.calls)
except Exception as e:
    print("crashed", str(e)[:60])
PY
)
fail=0
check() { if eval "$2"; then :; else echo "FAIL: $1"; fail=1; fi; }
check "view inherited from the parent" 'echo "$out" | sed -n 1p | grep -qF "ManageThing.jsp?view=sharedView"'
check "action inherited from the parent" 'echo "$out" | sed -n 1p | grep -qF "ManageThing.jsp?action=sharedAction"'
check "controller path read from a parent constant" 'echo "$out" | sed -n 1p | grep -qF "jsp/admin/plugins/p/thing/ManageThing.jsp?view=ownView"'
check "a long navigation url is kept whole" '[ "$(echo "$out" | sed -n 2p)" = True ]'
check "classification retried after the page navigated" '[ "$(echo "$out" | sed -n 3p)" = "classified 2" ]'
if [ $fail = 0 ]; then echo "PASS: inherited MVC methods inventoried, long navigation urls kept, classification survives a navigation"; else echo "$out"; exit 1; fi
