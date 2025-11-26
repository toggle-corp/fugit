
## scripts/helm-update-snapshots.sh


**helm/values/alpha.yaml**
```yaml
...Your base configs
```

**helm/tests/alpha-1.yaml**
```yaml
...Your environment configs
```

**helm/tests.yaml**
```yaml
tests:
  alpha-1.yaml:
    - values/alpha.yaml
```

**helm/update-snapshots.sh**
```bash
#!/bin/bash

export SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

$SCRIPT_DIR/../fugit/scripts/helm-update-snapshots.sh
```

Running this script will create snapshots using **helm/tests.yaml**.
```bash
helm/update-snapshots.sh
```

### Examples
- https://github.com/IFRCGo/montandon-etl/tree/develop/helm
