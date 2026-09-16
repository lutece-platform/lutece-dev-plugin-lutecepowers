// k6 load on the back-office entry screens. Logs in ONCE per VU with a real CSRF token (the token is read from the
// login page, else DoAdminLogin rejects every post with "Invalid security token" and the run measures auth-failure
// pages instead of the real BO). Reads artifacts/inventory.json. Thresholds are the perf budget.
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = __ENV.E2E_BASE || 'http://localhost:9090/lutece';
const inventory = JSON.parse(open('/e2e/artifacts/inventory.json'));
const scoped = inventory.features.some(f => f.origin === 'env');
const entries = inventory.features.filter(f => !scoped || f.origin !== 'env').map(f => f.url).filter(u => u && u.startsWith('jsp/admin/'));

export const options = {
  scenarios: { bo: { executor: 'constant-vus', vus: Number(__ENV.VUS || 10), duration: __ENV.DURATION || '30s' } },
  thresholds: { http_req_duration: ['p(95)<1500'], http_req_failed: ['rate<0.01'], checks: ['rate>0.99'] },
};

function looksAuthenticated(res) {
  // Judge on the url we landed on (bounced to the login or to a Lutece message) and on the auth wording rendered
  // in place — never on a substring of the body: a screen merely linking to AdminMessage.jsp is authenticated.
  const b = res.body || '';
  return res.status === 200 && !res.url.includes('AdminLogin.jsp') && !res.url.includes('AdminMessage.jsp')
      && !/vous (identifier|authentifier)|please authenticate|security token/i.test(b);
}

function login() {
  const page = http.get(`${BASE}/jsp/admin/AdminLogin.jsp`);
  const m = page.body.match(/name=["']token["'][^>]*?value=["']([^"']+)["']/);
  http.post(`${BASE}/jsp/admin/DoAdminLogin.jsp`,
    { access_code: 'admin', password: 'adminadmin', token: m ? m[1] : '' }, { redirects: 5 });
  return http.get(`${BASE}/jsp/admin/AdminMenu.jsp`);   // land on an authenticated page to confirm the session
}

export default function () {
  // k6 resets the cookie jar between iterations, so the session never survives one: authenticate every time.
  const res = login();
  if (!check(res, { 'login authenticated': r => looksAuthenticated(r) })) { sleep(1); return; }
  for (const u of entries) {
    const r = http.get(`${BASE}/${u}`, { tags: { screen: u.replace('jsp/admin/', '') } });
    check(r, { 'screen 200': x => x.status === 200, 'authenticated screen': x => looksAuthenticated(x) });
    sleep(0.2);
  }
}
