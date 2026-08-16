
## scripts/helm-update-snapshots.sh

Each key under `tests:` names a snapshot; its list is the complete, ordered set of values
files passed to `helm template` (on top of the chart's own `values.yaml`). A trailing
`.yaml` on the key is optional — `alpha.yaml` and `alpha` both render
`snapshots/alpha.yaml`, so two keys differing only by that suffix are rejected.

**helm/tests.yaml**
```yaml
tests:
  # -> snapshots/alpha.yaml
  alpha.yaml:
    - values/operators/dragonfly.yaml
    - values/alpha.yaml
    - values/traefik.yaml
  # -> snapshots/staging.yaml
  staging:
    - values/traefik.yaml
    - values/operators/dragonfly.yaml
    - values/operators/elasticsearch.yaml
    - values/go-deploy/base.yaml
    - values/go-deploy/staging.yaml
    - tests/go-deploy-dummy.yaml
```

Files under `helm/tests/` are for values a snapshot needs but a real deployment supplies
(dummy image tags, hosts, secrets). They are ordinary list entries — list them where their
precedence should apply.

**helm/update-snapshots.sh**
```bash
#!/bin/bash

export SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

$SCRIPT_DIR/../fugit/scripts/helm-update-snapshots.sh "$@"
```

Running this script will create snapshots using **helm/tests.yaml**.
```bash
helm/update-snapshots.sh
```

### Examples
- https://github.com/IFRCGo/montandon-etl/tree/develop/helm
