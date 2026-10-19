#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
for playbook in playbooks/*.yml; do
  echo "===== Running ${playbook} ====="
  ansible-playbook "$playbook"
done
