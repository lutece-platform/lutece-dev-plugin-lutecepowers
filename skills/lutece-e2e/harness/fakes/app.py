"""Stand-ins for the external systems a Lutece site calls, one URL prefix per system.

Only systems whose client code is public live here. An organisation adds its own in `extra/*.py` (mounted at
/app/extra, ignored by git): each module exposes `PREFIXES = {"/prefix/": handle}` with
`handle(handler, method, path, body)`, and uses `handler.send`, `handler.query`, `log` from this module."""
import html
import json
import os
import pathlib
import re
import ssl
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PORT", "9030"))
DATA_DIR = os.environ.get("DATA_DIR", "/data")
TLS_PORT = 9443
"""HTTPS listener for the services a page calls from the browser (BAN): the core CSP carries upgrade-insecure-requests,
so a plain-http fetch from an admin page is rewritten to https. The certificate is a test one (CN fakes), accepted by
the bench browser only."""
HERE = pathlib.Path(__file__).resolve().parent
PRO_GUID = os.environ.get("PRO_GUID", "e2e-pro-guid")

# CAS accounts. The key is what the operator types in the fake login form.
CAS_USERS = {
    "admin": {
        "GUID": "admin",
        "LOGIN": "admin",
        "NOM": "Admin",
        "PRENOM": "E2E",
        "EMAIL": "admin@e2e.local",
        "ID_CRM": "1",
    },
    "pro": {
        "GUID": PRO_GUID,
        "LOGIN": "pro",
        "NOM": "Pro",
        "PRENOM": "E2E",
        "EMAIL": "pro@e2e.local",
        "ID_CRM": "2",
    },
}

_lock = threading.Lock()
_ants = {}
"""ANTS appointments the fake recorded, keyed by application number."""
ANTS_KO = "E2EKO"
"""Application-number prefix the ANTS fake refuses, to reach the failure branch of the plugin."""
_tickets = {}
_payments = {}
_counters = {"ticket": 0, "crm": 100000, "idop": 0}


def _next(name):
    with _lock:
        _counters[name] += 1
        return _counters[name]


BAN_ADDRESSES = [
    {"label": "4 Rue de Rivoli 75004 Paris", "name": "4 Rue de Rivoli", "id": "75104_8249_00004", "postcode": "75004",
     "citycode": "75104", "lon": 2.361406, "lat": 48.855254},
    {"label": "Place de l'Hôtel de Ville 75004 Paris", "name": "Place de l'Hôtel de Ville", "id": "75104_4633",
     "postcode": "75004", "citycode": "75104", "lon": 2.351828, "lat": 48.856614},
    {"label": "8 Boulevard du Palais 75001 Paris", "name": "8 Boulevard du Palais", "id": "75101_7043_00008",
     "postcode": "75001", "citycode": "75101", "lon": 2.346344, "lat": 48.855410},
]
"""The addresses the BAN stand-in knows, in the shape of the real service (label, id, lon/lat in WGS84)."""


def log(channel, payload):
    """Appends one JSON line to artifacts/fakes/<channel>.log."""
    try:
        os.makedirs(DATA_DIR, exist_ok=True)
        with open(os.path.join(DATA_DIR, channel + ".log"), "a", encoding="utf-8") as fh:
            fh.write(json.dumps(payload, ensure_ascii=False) + "\n")
    except OSError:
        pass


def add_param(url, name, value):
    sep = "&" if "?" in url else "?"
    return url + sep + name + "=" + urllib.parse.quote(value, safe="")


CAS_LOGIN_PAGE = """<!doctype html><html lang="fr"><head><meta charset="utf-8">
<title>CAS (fake)</title></head><body style="font-family:sans-serif;margin:3rem">
<h1>CAS de test</h1>
<form method="post" action="/cas/login?service={service}">
<label>Identifiant <input name="username" value="{default}" autofocus></label>
<button type="submit">Se connecter</button>
</form>
<p>Comptes: {accounts}</p>
</body></html>"""

CAS_VALIDATE_OK = """<cas:serviceResponse xmlns:cas="http://www.yale.edu/tp/cas">
  <cas:authenticationSuccess>
    <cas:user>{user}</cas:user>
    <cas:attributes>
{attributes}
    </cas:attributes>
  </cas:authenticationSuccess>
</cas:serviceResponse>
"""

CAS_VALIDATE_KO = """<cas:serviceResponse xmlns:cas="http://www.yale.edu/tp/cas">
  <cas:authenticationFailure code="INVALID_TICKET">ticket inconnu</cas:authenticationFailure>
</cas:serviceResponse>
"""

PAYFIP_PAGE = """<!doctype html><html lang="fr"><head><meta charset="utf-8">
<title>PayFiP (fake)</title></head><body style="font-family:sans-serif;margin:3rem">
<h1>Paiement PayFiP de test</h1>
<ul><li>idop : {idop}</li><li>refdet : {refdet}</li><li>montant : {montant} centimes</li></ul>
<form method="post" action="/payfip/pay">
<input type="hidden" name="idop" value="{idop}">
<button type="submit" name="resultrans" value="P" id="payer">Payer</button>
<button type="submit" name="resultrans" value="A">Abandonner</button>
</form>
</body></html>"""

SOAP_CREER = """<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">
 <soapenv:Body>
  <ns:creerPaiementSecuriseResponse xmlns:ns="{ns}">
   <return><idOp xmlns="{rep}">{idop}</idOp></return>
  </ns:creerPaiementSecuriseResponse>
 </soapenv:Body>
</soapenv:Envelope>
"""

SOAP_DETAIL = """<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">
 <soapenv:Body>
  <ns:recupererDetailPaiementSecuriseResponse xmlns:ns="{ns}">
   <return xmlns:r="{rep}">
    <r:dattrans>{dattrans}</r:dattrans>
    <r:exer>{exer}</r:exer>
    <r:heurtrans>{heurtrans}</r:heurtrans>
    <r:idOp>{idop}</r:idOp>
    <r:mel>{mel}</r:mel>
    <r:montant>{montant}</r:montant>
    <r:numauto>{numauto}</r:numauto>
    <r:numcli>{numcli}</r:numcli>
    <r:objet>{objet}</r:objet>
    <r:refdet>{refdet}</r:refdet>
    <r:resultrans>{resultrans}</r:resultrans>
    <r:saisie>{saisie}</r:saisie>
   </return>
  </ns:recupererDetailPaiementSecuriseResponse>
 </soapenv:Body>
</soapenv:Envelope>
"""

NS_SERVICE = ("http://securite.service.tpa.cp.finances.gouv.fr/services/"
              "mas_securite/contrat_paiement_securise/PaiementSecuriseService")
NS_REPONSE = "http://securite.service.tpa.cp.finances.gouv.fr/reponse"


def soap_field(body, name):
    m = re.search(r"<(?:\w+:)?%s[^>]*>(.*?)</(?:\w+:)?%s>" % (name, name), body, re.S)
    return html.unescape(m.group(1).strip()) if m else ""


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        print("%s %s" % (self.command, self.path), flush=True)

    # -- plumbing ---------------------------------------------------------
    def send(self, status, body, ctype="text/plain; charset=utf-8", headers=None):
        raw = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(raw)

    def redirect(self, url):
        self.send_response(302)
        self.send_header("Location", url)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length).decode("utf-8", "replace") if length else ""

    def query(self):
        raw = urllib.parse.urlparse(self.path).query
        return {k: v[0] for k, v in urllib.parse.parse_qs(raw, keep_blank_values=True).items()}

    def do_GET(self):
        self.route("GET", "")

    def do_POST(self):
        self.route("POST", self.body())

    def do_PUT(self):
        self.route("PUT", self.body())

    def do_DELETE(self):
        self.route("DELETE", "")

    # -- routing ----------------------------------------------------------
    def route(self, method, body):
        path = urllib.parse.urlparse(self.path).path
        if path == "/health":
            return self.send(200, "ok")
        for prefix, handle in EXTRAS.items():
            if path.startswith(prefix):
                return handle(self, method, path, body)
        if path.startswith("/cas/"):
            return self.cas(method, path, body)
        if path.startswith("/crm/"):
            return self.crm(method, path, body)
        if path.startswith("/tipi/"):
            return self.tipi(body)
        if path.startswith("/payfip/"):
            return self.payfip(method, path, body)
        if path.startswith("/notifygru/"):
            return self.notifygru(path, body)
        if path.startswith("/identitystore/"):
            return self.identitystore(path, body)
        if path.startswith("/ants/"):
            return self.ants(method, path, body)
        if path.startswith("/ban/"):
            return self.ban(path)
        return self.send(404, "no fake for " + path)

    # -- BAN (api-adresse.data.gouv.fr), called by the browser --------------
    def ban(self, path):
        """GET /ban/search/?q=&limit= answers the BAN GeoJSON: the fixed Paris addresses whose label holds every word
        of the query, best first. The browser calls it from the application's origin, so it allows any origin."""
        q = self.query()
        words = [w for w in re.split(r"\W+", (q.get("q") or "").lower()) if w]
        limit = int(q.get("limit") or 5) if (q.get("limit") or "5").isdigit() else 5
        hits = [a for a in BAN_ADDRESSES if words and all(w in a["label"].lower() for w in words)][:limit]
        log("ban", {"q": q.get("q"), "limit": limit, "results": len(hits)})
        features = [{"type": "Feature", "geometry": {"type": "Point", "coordinates": [a["lon"], a["lat"]]},
                     "properties": {"label": a["label"], "score": 0.97, "id": a["id"], "name": a["name"],
                                    "postcode": a["postcode"], "citycode": a["citycode"], "city": "Paris",
                                    "context": "75, Paris, \u00cele-de-France", "type": "housenumber"}} for a in hits]
        return self.send(200, json.dumps({"type": "FeatureCollection", "features": features}),
                         "application/json; charset=utf-8", {"Access-Control-Allow-Origin": "*"})

    # -- CAS 2 ------------------------------------------------------------
    def cas(self, method, path, body):
        q = self.query()
        if path == "/cas/login" and method == "GET":
            service = q.get("service", "")
            return self.send(200, CAS_LOGIN_PAGE.format(
                service=html.escape(urllib.parse.quote(service, safe="")),
                default="pro", accounts=", ".join(CAS_USERS)), "text/html; charset=utf-8")
        if path == "/cas/login" and method == "POST":
            form = {k: v[0] for k, v in urllib.parse.parse_qs(body).items()}
            username = form.get("username", "pro").strip()
            user = CAS_USERS.get(username) or dict(CAS_USERS["pro"], GUID=username, LOGIN=username)
            ticket = "ST-%d-e2e" % _next("ticket")
            service = urllib.parse.unquote(q.get("service", ""))
            with _lock:
                _tickets[ticket] = {"service": service, "user": user}
            log("cas", {"event": "login", "user": user["GUID"], "service": service})
            return self.redirect(add_param(service, "ticket", ticket))
        if path in ("/cas/serviceValidate", "/cas/proxyValidate"):
            entry = _tickets.pop(q.get("ticket", ""), None)
            if entry is None:
                return self.send(200, CAS_VALIDATE_KO, "text/xml; charset=utf-8")
            user = entry["user"]
            # cas-client 3.1 parses attributes line by line: one element per line.
            attrs = "\n".join("      <cas:%s>%s</cas:%s>" % (k, html.escape(v), k)
                              for k, v in user.items())
            log("cas", {"event": "validate", "user": user["GUID"]})
            return self.send(200, CAS_VALIDATE_OK.format(user=html.escape(user["GUID"]),
                                                         attributes=attrs),
                             "text/xml; charset=utf-8")
        if path == "/cas/logout":
            return self.redirect(q.get("service") or q.get("url") or "/cas/login")
        return self.send(404, "unknown CAS route " + path)

    # -- CRM (plugin-crm REST contract used by library-crmclient) ---------
    def crm(self, method, path, body):
        log("crm", {"method": method, "path": self.path, "body": body[:4000]})
        if path.endswith("/createByUserGuid") or path.endswith("/createByIdCRMUser"):
            return self.send(200, str(_next("crm")))
        if path.endswith("/user_guid"):
            return self.send(200, PRO_GUID)
        return self.send(200, "OK")

    # -- PayFiP / TIPI SOAP ----------------------------------------------
    def tipi(self, body):
        log("tipi", {"soap": body[:8000]})
        if "recupererDetailPaiementSecurise" in body:
            idop = soap_field(body, "idOp")
            p = _payments.get(idop, {})
            now = time.localtime()
            return self.send(200, SOAP_DETAIL.format(
                ns=NS_SERVICE, rep=NS_REPONSE, idop=idop,
                dattrans=time.strftime("%d%m%Y", now), heurtrans=time.strftime("%H%M", now),
                exer=p.get("exer", time.strftime("%Y", now)), mel=p.get("mel", ""),
                montant=p.get("montant", "0"), numauto="%06d" % (int(idop[-6:] or 0) % 1000000),
                numcli=p.get("numcli", ""), objet=p.get("objet", ""),
                # un idop inconnu du bouchon n'est pas un paiement abouti : « A » (abandon), jamais
                # « P », que l'applicatif traiterait comme un règlement à notifier
                refdet=p.get("refdet", ""), resultrans=p.get("resultrans", "A"),
                saisie=p.get("saisie", "T")), "text/xml; charset=utf-8")
        if "creerPaiementSecurise" in body:
            idop = "E2E%08d" % _next("idop")
            with _lock:
                _payments[idop] = {f: soap_field(body, f) for f in
                                   ("mel", "montant", "refdet", "numcli", "urlnotif",
                                    "urlredirect", "exer", "objet", "saisie")}
                # tant que l'usager n'a pas validé sur l'écran de paiement, la transaction n'est pas aboutie
                _payments[idop]["resultrans"] = "A"
            return self.send(200, SOAP_CREER.format(ns=NS_SERVICE, rep=NS_REPONSE, idop=idop),
                             "text/xml; charset=utf-8")
        return self.send(500, "unsupported SOAP operation")

    def payfip(self, method, path, body):
        if method == "GET":
            idop = self.query().get("idop", "")
            p = _payments.get(idop)
            if p is None:
                return self.send(404, "idop inconnu: " + idop)
            return self.send(200, PAYFIP_PAGE.format(idop=html.escape(idop),
                                                     refdet=html.escape(p.get("refdet", "")),
                                                     montant=html.escape(p.get("montant", ""))),
                             "text/html; charset=utf-8")
        form = {k: v[0] for k, v in urllib.parse.parse_qs(body).items()}
        idop = form.get("idop", "")
        p = _payments.get(idop)
        if p is None:
            return self.send(404, "idop inconnu: " + idop)
        p["resultrans"] = form.get("resultrans", "P")
        notif = p.get("urlnotif") or ""
        if notif:
            try:
                urllib.request.urlopen(add_param(notif, "idop", idop), timeout=30).read()
                log("tipi", {"event": "notif", "url": notif, "idop": idop})
            except Exception as exc:  # the redirect must happen even if the app errors out
                log("tipi", {"event": "notif-failed", "url": notif, "error": str(exc)})
        return self.redirect(p.get("urlredirect") or "/health")

    # -- Mon Compte -------------------------------------------------------
    # -- GRU stubs --------------------------------------------------------
    def notifygru(self, path, body):
        log("notifygru", {"path": path, "body": body[:4000]})
        if path.endswith("/token"):
            return self.send(200, json.dumps({"access_token": "e2e-token", "token_type": "Bearer",
                                              "expires_in": 3600}), "application/json")
        return self.send(200, json.dumps({"status": "OK", "id": _next("crm")}), "application/json")

    # -- ANTS (rendez-vous passeport / CNI) -------------------------------
    def ants(self, method, path, body):
        """ANTS coordination API: statuses keyed by application number, and appointments it remembers.

        Stateful on purpose: a POST records the appointment, so a later GET /status returns it and a DELETE
        answers a real rowcount. That is what makes the round-trip provable instead of a fixed answer. An
        application number starting with E2EKO is refused everywhere, to exercise the failure branch."""
        log("ants", {"method": method, "path": self.path, "body": body,
                     "token": self.headers.get("x-rdv-opt-auth-token", "")})
        raw = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query, keep_blank_values=True)
        ids = raw.get("application_ids") or raw.get("application_id") or []

        if path.endswith("/status"):
            out = {}
            for app_id in ids:
                with _lock:
                    booked = list(_ants.get(app_id, []))
                out[app_id] = {"status": "in_progress" if app_id.startswith(ANTS_KO) else "validated",
                               "appointments": booked}
            return self.send(200, json.dumps(out), "application/json")

        app_id = ids[0] if ids else ""
        if method == "POST":
            if app_id.startswith(ANTS_KO):
                return self.send(200, json.dumps({"success": False}), "application/json")
            with _lock:
                _ants.setdefault(app_id, []).append({
                    "management_url": raw.get("management_url", [""])[0],
                    "meeting_point": raw.get("meeting_point", [""])[0],
                    "appointment_date": raw.get("appointment_date", [""])[0]})
            return self.send(200, json.dumps({"success": True}), "application/json")
        if method == "DELETE":
            with _lock:
                n = len(_ants.pop(app_id, []))
            return self.send(200, json.dumps({"rowcount": n}), "application/json")
        return self.send(405, "method not supported by the ANTS fake: " + method)

    def identitystore(self, path, body):
        log("identitystore", {"path": path, "body": body[:4000]})
        if path.endswith("/token"):
            return self.send(200, json.dumps({"access_token": "e2e-token", "token_type": "Bearer",
                                              "expires_in": 3600}), "application/json")
        guid = self.query().get("connection_id") or self.query().get("customer_id") or PRO_GUID
        return self.send(200, json.dumps({
            "identity": {"connection_id": guid, "customer_id": guid,
                         "attributes": {
                             "family_name": {"key": "family_name", "value": "E2E"},
                             "first_name": {"key": "first_name", "value": "Test"},
                             "email": {"key": "email", "value": "pro@e2e.local"}}},
            "status": {"http_code": 200, "message": "OK"}}), "application/json")

EXTRAS = {}
"""URL prefix → handler, from the organisation's extra/*.py modules."""


def load_extras(directory):
    import importlib.util
    import sys
    for f in sorted(pathlib.Path(directory).glob("*.py")) if os.path.isdir(directory) else []:
        spec = importlib.util.spec_from_file_location("fakes_extra_" + f.stem, f)
        mod = importlib.util.module_from_spec(spec)
        mod.log, mod.add_param = log, add_param
        sys.modules[spec.name] = mod
        spec.loader.exec_module(mod)
        EXTRAS.update(getattr(mod, "PREFIXES", {}))
        print("fakes: extra %s → %s" % (f.name, ", ".join(getattr(mod, "PREFIXES", {}))), flush=True)


if __name__ == "__main__":
    os.makedirs(DATA_DIR, exist_ok=True)
    load_extras(os.environ.get("EXTRA_DIR", "/app/extra"))
    tls = ThreadingHTTPServer(("0.0.0.0", TLS_PORT), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(HERE / "fakes-cert.pem", HERE / "fakes-key.pem")
    tls.socket = context.wrap_socket(tls.socket, server_side=True)
    threading.Thread(target=tls.serve_forever, daemon=True).start()
    print("fakes listening on %d, https on %d" % (PORT, TLS_PORT), flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
