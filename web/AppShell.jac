"""Route table for the whole site.

Manual routing, chosen deliberately over file-based: the app already had the
single-page `def:pub app` shape, and manual routing is the one system where that
signature stays correct. There is no `pages/` directory anywhere in this project
— a `pages/` directory plus a manual `<Router>` fight over the URL.

  /      the marketing page (owned by the site agent)
  /app   the graph explorer
  *      anything else falls back to the marketing page

Deep links work because `[serve] base_route_app = "app"` in `jac.toml` makes the
server serve the app HTML for extensionless non-API paths.
"""

import from "@jac/runtime" { Router, Routes, Route, Navigate, Link }
import from .site.Landing { Landing }
import from .AppScreen { AppScreen }

def:pub AppShell -> JsxElement {
    return <Router>
        <Routes>
            <Route path="/" element={<LandingRoute />} />
            <Route path="/app" element={<AppScreen />} />
            <Route path="*" element={<Navigate to="/" replace={True} />} />
        </Routes>
    </Router>;
}

def:pub LandingRoute -> JsxElement {
    # A persistent way into the app that does not depend on the landing page's
    # own layout — the marketing page is another agent's file, and its in-page
    # CTA can come and go without stranding the demo on `/`.
    return <div>
        <Landing />
        <Link to="/app"
              style={{"position": "fixed", "right": "20px", "bottom": "20px",
                      "zIndex": "50", "padding": "12px 18px",
                      "background": "#ffd166", "color": "#0b0e14",
                      "borderRadius": "999px", "fontWeight": "600",
                      "fontSize": "14px", "textDecoration": "none",
                      "fontFamily": "system-ui, sans-serif",
                      "boxShadow": "0 6px 24px rgba(0,0,0,0.45)"}}>
            {"Open the graph →"}
        </Link>
    </div>;
}
