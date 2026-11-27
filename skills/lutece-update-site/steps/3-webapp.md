# Step 3 — The webapp overlay

Codes: SI40-SI44, SI50-SI58, and the template checks of `tools/lutece-check.sh` (TM*).

## plugins.dat

Regenerate it from the descriptors the after war ships, never by hand
(`site_check.py plugins-dat <after war> > webapp/WEB-INF/plugins/plugins.dat`): one `<name>.installed=1` per
`WEB-INF/plugins/*.xml` of the war (the `<name>` of the descriptor, not the artefact name: `healthc` for
`plugin-health`), one `<name>.pool=portal` per plugin declaring `<db-pool-required>1</db-pool-required>`, and
`core_extensions.installed=1`. SI40-SI42 then pass. On an existing database it only installs plugins the database
does not know yet (`reference/configuration.md`).

## Overrides of templates, JSP and static files

`check` lists every file of the site that replaces a file of a dependency (SI50). Replay them first:

```bash
python3 ${LUTECEPOWERS_ROOT}/tools/site_check.py rebase . --before .migration/before --before-m2 .migration/m2 \
        --war <after war> --m2 .migration/m2 --write
```

A three-way merge (base: the v7 upstream) replays the site's lines on the v8 upstream: `CLEAN` files are replaced
by the merge, `CONFLICT` files get a `.conflict` next to them where the site's intent and the new upstream meet;
resolve each by hand, keeping the site's intent on the v8 lines. For each file:

1. Take the upstream file the override was written against (the before war's dependency, its `-webapp.zip` in
   `.migration/m2`) and the v8 upstream (the after war's). `unzip -p <zip> <path>` prints either.
2. `diff` the site's file with the v7 upstream: that is the site's customisation.
3. Apply that customisation to a copy of the v8 upstream, or drop the override when the customisation is gone
   (the v8 file already does it, the feature left). Never keep a v7 copy: it freezes v7 macros (SI52-SI54).
4. Write `- file <path>: rebased on <artefact> <version>, keeps <what>` or `dropped: <why>` in the decisions file.

A copy of a core `commons*.html` or of the corporate theme is always dropped (SI54). A skin override of a plugin
template that the v8 plugin renders through `<@cTpl>` moves under `skin/themes/<code>/tpl/` of the theme.

## web.xml and JSP

A site ships no `web.xml` unless it must; then it starts from the v8 core's one (SI56). `diff` the site's `web.xml`
with the core `web.xml` of the before version (`unzip -p lutece-core-<v7>-webapp.zip WEB-INF/web.xml`): every
difference is a choice of the site to carry, one decision each.

- A filter parameter that v8 reads from the configuration first is ignored by v8 as soon as the key exists, and the
  core defines them: the XSS filters read `lutece.safe.request.{admin|site}.{activateXssFilter,sanitizeFilterMode,
  xssCharacters}` (`SafeRequestFilterSite`, `SafeRequestFilterAdmin`) and fall back to `web.xml` only when all three
  are absent. The site's choice becomes those keys in `conf/override`.
- The upload limit of v7 (`requestSizeMax` of the upload filters) is the `<multipart-config><max-request-size>` of
  the v8 core's servlets: the site ships the v8 core's `web.xml` with that value changed, and nothing else.

A JSP of the site uses no `jsp:useBean` (SI55, `rules/jsp-admin.md`).

## Files two dependencies ship

SI57 names a path two dependencies both ship: which one lands in the war is unspecified. When the file matters, the
site ships its own. A dependency shipping `WEB-INF/plugins/plugins.dat` while the site ships none is a FAIL (SI58).
