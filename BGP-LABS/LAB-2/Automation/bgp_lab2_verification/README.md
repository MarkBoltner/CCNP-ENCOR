# BGP Lab 2 — Ansible Verification Playbooks

These playbooks implement all 13 checks in section **5. Verification** of the supplied README.
Each playbook writes one text file per router under `results/<check-name>/`, so command outputs remain separate and can be attached to the lab evidence.

## Files
- `playbooks/01_eigrp_neighbors.yml` through `playbooks/13_ping_matrix.yml`: one playbook per verification item (items 3 and 4 share item 3's `show ip bgp summary` playbook).
- `inventory.ini.example`: copy to `inventory.ini` and replace example IPs and credentials.
- `ansible.cfg`: local inventory defaults.
- `requirements.yml`: required Ansible collections.

## Prerequisites
Run from a Linux controller with SSH/IP reachability to the routers, and IOS devices that support the commands in the README.

Install collections:
```bash
ansible-galaxy collection install -r requirements.yml
```

Install `ansible-core` in your chosen Python environment if needed. `ansible.netcommon` and `cisco.ios` are collections, not Python packages.

## Configure
```bash
cp inventory.ini.example inventory.ini
nano inventory.ini
```
Set each `ansible_host` to the actual management/reachable IP of R1-R4 and enter valid credentials. If the routers are reachable through a jump host or EVE-NG console server, adjust the inventory connection accordingly.

## Run one check
From this directory:
```bash
ansible-playbook playbooks/01_eigrp_neighbors.yml
```
Example for all checks:
```bash
for f in playbooks/*.yml; do ansible-playbook "$f" || break; done
```

## Output structure
```text
results/
  01_eigrp_neighbors/R1.txt
  01_eigrp_neighbors/R2.txt
  ...
  13_ping_matrix/R4.txt
```
The controller creates the folders/files automatically when each playbook runs. The `results/` directory in this ZIP is initially empty.

## Notes and limitations
- These are **verification/collection** playbooks. They do not change router configuration.
- Item 3 and item 4 are combined because both use `show ip bgp summary`; its output verifies both session state and router ID.
- Item 5 queries every configured BGP neighbor, not just one, to make the timer/MD5 evidence comprehensive.
- Item 7 checks Route-Reflector status on R1 and R3 for both clients. R2/R4 collect a summary only.
- Item 10 checks the specified prefixes on R2/R4 and collects `show ip bgp community no-export` to inspect all matching routes.
- Item 13 runs 12 directed pings: every router LAN interface to each of the other three LAN interface IPs, with the source set to the local LAN interface address. It saves the raw IOS output; verify each ping reports 100 percent success.
- IOS output varies by image/release. A command may need slight adjustment if your specific EVE-NG IOS image does not support that exact syntax.
- These playbooks save raw evidence; they do not automatically parse every IOS output into pass/fail assertions.
