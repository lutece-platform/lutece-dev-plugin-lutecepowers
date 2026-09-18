---
max_turns: 40
allowed_tools: [Read, Glob, Grep, Skill]
---

I am migrating a Lutece plugin from v7 to v8. Its REST endpoints were protected in v7 by a filter
declared in the plugin descriptor:

```xml
<filters>
    <filter>
        <filter-name>myplugin.restAuthFilter</filter-name>
        <filter-class>fr.paris.lutece.plugins.myplugin.web.RestAuthFilter</filter-class>
        <url-pattern>/rest/myplugin/*</url-pattern>
    </filter>
</filters>
```

After the migration to v8, will this filter still protect those endpoints? Tell me what happens and
what I should do.
