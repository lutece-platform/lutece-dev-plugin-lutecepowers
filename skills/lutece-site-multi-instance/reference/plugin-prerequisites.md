# Plugin prerequisites

Report them, do not patch the plugins (plugin code belongs to `lutece-scalability-v8`).

Check the resolved versions; for a SNAPSHOT at the boundary (`6.0.1-SNAPSHOT` sorts before `6.0.1`), look for the fix in the jar (class, SQL script) rather than trusting the number. Each line was reproduced with two replicas behind nginx, except the workflow lines (found by
review, covered by the plugin-workflow tests).

| Component | Defect | Symptom | Fixed by |
|---|---|---|---|
| plugin-forms, module-forms-breadcrumbaccordion | Breadcrumb beans `@ApplicationScoped` without no-args constructor | "Your session has expired" on every node switch (`WELD-001435`) | protected no-args constructor |
| module-forms-breadcrumbaccordion ≤ 2.0.2-SNAPSHOT | `BreadcrumbAccordionConfig` and `BreadcrumbAccordionConfigItem` put in the forms cache but not `Serializable` | **500** on every step of a form using the accordion breadcrumb, with Hazelcast (`ReflectiveCompactSerializationUnsupportedException`) as with Ehcache (`NotSerializableException`) | both classes `Serializable` |
| plugin-forms | `AbstractFormJsonService` (super class of `FormJsonService`), `PDFExport`, `PdfFullExport`, `CSVExport`, `LuceneLockManagerDB`, `LuceneFormSearchIndexer` without no-args constructor | Back office form creation fails when display and submission hit different replicas (`WELD-001435`, then `bean is null`); not reported at deployment nor on one replica | protected no-args constructors + hierarchy test |
| plugin-forms | Quota lock row never created; acquire query sets `is_locked=0` | Forms with quota refuse every response; quota exceeded under concurrency | `LockDAO` fix |
| lutece-core ≥ 8.0.2-beta-04 + plugin-forms | Admin actions checked by CSRF token from startup, step form posts several actions | Back office "add a response" fails at the first step (`Invalid security token`) | core checks an action under its `securityTokenAction`; forms shares one key |
| lutece-core | Admin MVC JSPs write after a redirect | OpenLiberty closes the keep-alive connection; behind ingress-nginx the next request gets a **502** | `MainFilter` discards the body after `sendRedirect` |
| lutece-core | Caches iterated on every page (security headers, plugin list), session attributes read ~10 times per page, CSRF tokens never trimmed | Most of the CPU and of the latency under load with Hazelcast | not referenced here: measure the site under load (`reference/verification.md`) |
| plugin-htmlpage < 6.0.1 | Page include counts then lists the html page cache on every portal page, and the refresh clears the shared cache before reloading it; a created page keeps the id 0 | Every portal page iterates the whole cache over the network (and queries the database when the site has no html page); concurrent readers find the cache empty and reload it again | index entry of the cached ids read by key (near cache), refresh without clear, generated key read on insert |
| plugin-genericattributes | Asynchronous uploads kept in a static map of the instance | A file uploaded on one replica is missing when the form is submitted on another (silently: the response has no file) | uploads kept in the session (`SessionMultipartItem`, content copied only when the session is serialized) |
| module-workflow-upload | Same static map, keyed by the session id | Workflow "upload" task loses its files on a node switch, and after a login | same fix |
| plugin-genericattributes | Numbering entries counted in a static map | Two responses get the same number | counter table `genatt_entry_numbering`, incremented in database (upgrade script `3.0.2-3.0.3`, run by Liquibase) |
| plugin-htmltopdf | Builder bean keeps the HTML and a static renderer | Two concurrent PDF exports swap their contents (one replica is enough) | one rendering object per call |
| lutece-core | Mail queue: next mail selected then locked without check | The same mail sent twice if two replicas run `mailSender` | atomic lock; keep `mailSender` exclusive anyway |
| module-mylutece-database | `DatabaseUserParameterService` without non-private constructor | `WELD-001435` when a session moves to another replica | protected constructor |
| module-mylutece-oauth2 < 3.0.3 | Registry of the sessions to refresh kept per instance | A user update notified by the identity provider only reaches the sessions of the replica that receives it | version of each notified user in a Lutece cache (Hazelcast), the session keeps the version it has seen and refreshes the user when they differ |
| library-workflow-core < 4.0.2, plugin-workflow < 7.0.2 | Nothing prevents two requests from processing an action on the same resource at the same time (two agents on two replicas, an agent and the automatic action daemon) | The action runs twice, the tasks (notification, assignment) are repeated and the resource ends in a state computed from a stale one | resource claimed by a single conditional `UPDATE` on `workflow_resource_workflow.lock_date` (released after the action, expires after `workflow.resourceWorkflow.lockTimeout`, 300 s); a refused claim throws `ResourceWorkflowLockedException` (wrapped in `AppException` by the core) |
| plugin-forms < 4.0.2, workflow-rest < 3.0.0, actionsbatch < 2.0.0, alertforms < 3.0.1, extend-comment < 2.0.0, extend-feedback < 3.0.1, plugin-appointment < 4.0.0, module-appointment-alert < 4.0.0 | Callers of the workflow do not handle `ResourceWorkflowLockedException` | With the claim above, an action refused because another replica is processing the resource shows an error page instead of a message | catch the exception (or an `AppException` caused by it) and display "action in progress, try again" |

Plugin code storing per-item session attributes (one attribute per token, per uploaded file, created and removed at run time)
does not survive node switches with OpenLiberty `sessionCache`: an instance that already holds the session in memory misses
the attributes created on another instance (reproduced: a form step alternating 1-2-1-2 loses its state, an upload on one
instance is missing on the next step on the other). Keep one attribute per concern (a map) whose value changes; the remaining
limit is two concurrent requests of one session on two instances (last write wins).

Locks (`synchronized`) found on DAO inserts (workflow and its modules, extend, unittree, notifygru, mylutece-database) protect
nothing: keys are generated by the database. They only serialize the hot paths of one replica; removing them is safe.

Until a fixed version is deployed: session affinity at the load balancer, no form with a quota, no numbering entry, and no
attachment field.
