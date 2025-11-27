#!/bin/bash -x

echo "Processing for repo: $(pwd)"
read -rp "Proceed? Y to confirm: " confirm

if [[ "$confirm" != "Y" ]]; then
    echo "Aborted by user."
    exit 1
fi

git submodule foreach 'git fetch'
git submodule foreach "git checkout \$(git config -f \$toplevel/.gitmodules submodule.\$name.branch || echo main)"
