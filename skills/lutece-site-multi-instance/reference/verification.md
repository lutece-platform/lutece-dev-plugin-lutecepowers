# Runtime verification

When the user asks to prove the configuration.

Over plain HTTP on a host other than `localhost` (a NodePort), the CSP `upgrade-insecure-requests` of the security headers makes the
browser load the resources over HTTPS and the back office breaks: test behind TLS or through `localhost` (port-forward, relay).

1. Two replicas start; the logs show `Members {size:2` and the client `Client Connectivity` to both members.
2. A multi-step form completed with each step served by a different replica (cookie or round robin): no "session expired".
   With an attachment field: upload on one replica, submit on the other, the saved response has the file. Numbering entries:
   concurrent submissions on both replicas get distinct numbers.
3. Back office login on one replica, menu on the other; rights changed on one, visible on the other.
4. A site property changed on one replica is visible on the other within a second (near cache invalidation).
5. An exclusive daemon runs once per schedule across the cluster.
6. `kill -9` of one replica: sessions continue on the other; rolling restart (SIGTERM) of both replicas without session loss
   and without `migration` errors in the Hazelcast logs.
7. Under load behind the real ingress: no 502.

How the checks were run on minikube (a bench to rebuild, nothing of it ships with the site):

- Every step on another replica: reach each pod (a NodePort service per pod, selected by a label set on it, relayed to
  `localhost`: `kubectl port-forward` resets under load and fails the load runs) and put a small reverse proxy in front that sends each dynamic
  request (`.jsp`, `/upload`, servlets) to the next pod and adds a response header naming it; drive the form journey with
  Playwright through it (step 1, step 2 with an upload, summary, save) and assert against the database: the response has
  its file, the numbers of concurrent responses are distinct. The same journey on a single pod must pass first (control).
- Back office: log in, then open a page protected by a right several times; a lost session shows `AdminMessage.jsp`, not
  the login form.
- Cache: change a site property in the back office of one pod, read the portal of the other one second later.
- Failover and rollout: k6 journeys through the real ingress (round robin, no affinity) while one pod is deleted with
  `--grace-period=0 --force`, then during `kubectl rollout restart`: no failed journey, no 502.
- A run of the same tests on the single-instance site deployed with two replicas must fail (red): it shows the tests
  can see the defects.
