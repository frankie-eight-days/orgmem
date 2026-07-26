"""OrgMem — fullstack entry point.

Three modules meet here and nothing else lives in this file:

  * `main.jac`  owns the graph and the walkers.
  * `api.jac`   spawns those walkers and normalises their reports.
  * `web/`      is the client: `AppShell` picks the route, the rest is UI.

The plain (non-`sv`) import below is what registers `api`'s endpoints at server
start. The client reaches the same functions through `sv import from ..api` in
`web/AppScreen.jac`, which is where the RPC stubs are generated.

Routing is MANUAL (`<Router>`/`<Routes>` inside `AppShell`), not file-based, so
`app` correctly takes no arguments and there is deliberately no `pages/`
directory — the two systems fight over the URL if both are present.
"""

import from api { graph_data, expand_node, ask }
import from .web.AppShell { AppShell }

def:pub app -> JsxElement {
    return <AppShell />;
}
