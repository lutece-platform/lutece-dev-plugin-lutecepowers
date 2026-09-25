# extra/ — an organisation's own stand-ins

`app.py` ships fakes only for systems whose client code is public (CAS, OIDC, CRM, notifygru, identitystore,
ANTS, TIPI/PayFiP). The systems specific to one organisation — its citizen account, its banner, its business
APIs — are stand-ins the organisation keeps for itself: one or more `*.py` files in this directory, **ignored by
git**, mounted read-only into the `fakes` container and loaded at start.

A module exposes `PREFIXES = {"/myprefix/": handle}`; `handle(handler, method, path, body)` answers with
`handler.send(status, body, content_type)` and records what it received with `log(channel, payload)` (injected
by the loader), so `fake_log` steps can assert on it. Keep the module free of business rules: it answers the
shape the client parses, nothing more.

Point the application at it the same way as for the shipped fakes (`reference/external-systems.md`, Fakes):
`<key the plugin reads>=http://fakes:9030/myprefix`.
