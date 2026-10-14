# Project Layout Summary — hologram-start-app/backend

```
backend/
├── lib/
│   ├── annotate.ex
│   ├── annotate/                    # auth, authz, entities, schema, workers
│   │   └── + hologram/, style_guide/
│   ├── annotate_web/                # controllers, plugs, channels
│   ├── mix/tasks/liquibase.update.ex
│   └── supports/
├── config/
├── themes/                         # theme CSS sources
├── db/changelog/                   # Liquibase 000–025
├── priv/repo/                      # migrations, seeds
├── test/                           # annotate · annotate_web · support
├── docs/
├── Dockerfile · Dockerfile.dev
└── mix.exs                         # :annotate
```

See [PROJ-LAYOUT.md](PROJ-LAYOUT.md).
