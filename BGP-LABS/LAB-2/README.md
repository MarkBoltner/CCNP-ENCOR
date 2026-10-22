# BGP Lab 2 — iBGP over Loopbacks, Route Reflector Cluster, Community Control and Path Preference

> CCNP ENCOR (350-401) preparation · Lab source: *101 CCNP ENCOR Labs* · Platform: EVE-NG (Cisco IOS)

## 1. Overview

This lab builds a four-router iBGP domain (AS 254) on top of an EIGRP underlay. Unlike Lab 1, BGP sessions are formed between **Loopback 0** addresses, two route reflectors share one **cluster ID**, and the four 150.x.x.0/24 LANs are **redistributed** into BGP with a community that keeps them inside the AS. A single configuration change on one router then steers path selection for two other routers.

The lab forces you to think about *where* a configuration takes effect: a peer group is local to one router, a `send-community` is per neighbor, and a local-preference set on the right router becomes network-wide because iBGP carries it.

**Skills demonstrated:** EIGRP underlay design, iBGP peering on loopbacks (`update-source`), peer-group templates, route reflector redundancy and cluster ID, TCP MD5 authentication, timer tuning, selective redistribution, well-known communities, local-preference path control, Ansible-based verification automation over SSH, and structured troubleshooting.

## 2. Topology

| Link | Subnet | Endpoints (EVE-NG interfaces) |
|---|---|---|
| R1 – R2 | 10.0.0.0/30 | R1 e1/0 .1 / R2 e1/0 .2 |
| R1 – R3 | 10.0.0.4/30 | R1 e1/1 .5 / R3 e1/0 .6 |
| R3 – R4 | 10.0.0.12/30 | R3 e1/1 .13 / R4 e1/0 .14 |
| WAN / automation segment | 200.0.0.0/30 | R1 e1/2 .2 (toward the WAN switch; in EIGRP, not in BGP) |

The book uses serial and FastEthernet interfaces; this build uses Ethernet interfaces in EVE-NG, so the names differ from the book's figure. The physical topology is a chain: **R2 — R1 — R3 — R4**.

The 200.0.0.0/30 segment on R1 e1/2 was added after the five tasks. It connects R1 to the WAN switch, which gives the lab its Internet access and lets the automation described in section 6 reach the routers. The segment is advertised in EIGRP (R1 only) but is not redistributed into BGP, so the BGP design is unchanged. The WAN switch itself is outside the scope of this lab and its configuration is not included.

| Router | LAN (interface) | Loopback 0 / Router ID |
|---|---|---|
| R1 | 150.1.1.0/24 (e1/3) | 1.1.1.1/32 |
| R2 | 150.2.2.0/24 (e1/1) | 2.2.2.2/32 |
| R3 | 150.3.3.0/24 (e1/2) | 3.3.3.3/32 |
| R4 | 150.4.4.0/24 (e1/1) | 4.4.4.4/32 |

BGP sessions (loopback addresses): R1↔R2, R1↔R3, R1↔R4, R3↔R2, R3↔R4. R1 and R3 are the route reflectors; R2 and R4 are clients of both.

![Topology](screenshots/00-topology.png)

## 3. Lab Tasks

The lab comes from *101 CCNP ENCOR Labs*. The tasks are summarized here in my own words; the topology image is my own EVE-NG screenshot.

### Task 1: Base configuration
Set hostnames and IP addressing on all routers according to the topology.

### Task 2: Loopbacks and EIGRP underlay
Create Loopback 0 on every router (x.x.x.x/32, where x is the router number). Run EIGRP AS 254 on every interface **except** the four 150.x.x.0/24 LAN interfaces, and verify.

### Task 3: iBGP with route reflectors
Build iBGP in AS 254 with these requirements:

- Router IDs and peering addresses are the Loopback 0 addresses.
- R1 and R3 are route reflectors in the **same cluster**, to reduce the size of the RIB.
- R2 and R4 peer with both R1 and R3.
- R2 and R4 use a **peer group**; R1 and R3 must **not**.
- TCP MD5 authentication with the password `CCNP`.
- Keepalive 5 seconds, hold time 15 seconds.

### Task 4: Advertise the LANs and keep them inside AS 254
Redistribute the 150.x.x.0/24 LANs into BGP on every router. In the future, eBGP sessions to ISPs will be added, and these prefixes must **never** leave AS 254. No prefix lists and no filters of any kind. Verify, including pings between all LANs.

### Task 5: Prefer R3 over R1
R2 and R4 must always prefer the path learned from R3 over the path learned from R1 for each other's LAN. Only **one** router may be configured, the solution must be globally significant, and BGP administrative distances must not be changed.

## 4. Implementation

### 4.1 Loopbacks and EIGRP underlay

```
interface Loopback0
 ip address 1.1.1.1 255.255.255.255

router eigrp 254
 network 10.0.0.0 0.0.0.3
 network 10.0.0.4 0.0.0.3
 network 1.1.1.1 0.0.0.0
```

The `network` statements with wildcard masks enable EIGRP only on the transit links and the loopback. The 150.x.x.0/24 LANs are deliberately left out, so they are carried by BGP alone. The loopbacks must be in EIGRP because BGP sessions between non-adjacent routers need IP reachability to each other's loopback. R1 has one extra statement, `network 200.0.0.0 0.0.0.3`, which enables EIGRP on its WAN-facing interface (see section 4.7).

### 4.2 iBGP on loopbacks (R1 and R3: per-neighbor, no peer group)

```
! R1 (excerpt)
router bgp 254
 bgp router-id 1.1.1.1
 bgp cluster-id 13.13.13.13
 timers bgp 5 15
 neighbor 2.2.2.2 remote-as 254
 neighbor 2.2.2.2 password 0 CCNP
 neighbor 2.2.2.2 update-source Loopback0
 neighbor 2.2.2.2 route-reflector-client
 neighbor 2.2.2.2 send-community
 neighbor 3.3.3.3 remote-as 254
 neighbor 3.3.3.3 password 0 CCNP
 neighbor 3.3.3.3 update-source Loopback0
 neighbor 3.3.3.3 send-community
 neighbor 4.4.4.4 remote-as 254
 neighbor 4.4.4.4 password 0 CCNP
 neighbor 4.4.4.4 update-source Loopback0
 neighbor 4.4.4.4 route-reflector-client
 neighbor 4.4.4.4 send-community
```

- BGP needs only IP reachability between the session endpoints, not a shared segment. The EIGRP underlay provides that for loopbacks.
- `update-source Loopback0` is required on **both** ends. Without it the router sources the TCP session from the outgoing interface address, and the neighbor, which expects the loopback address, rejects it.
- iBGP packets have TTL 255, so `ebgp-multihop` is not needed.
- `timers bgp 5 15` sets keepalive and hold time; they take effect after a session reset because hold time is negotiated in the OPEN message.

### 4.3 Peer group (R2 and R4)

```
! R2
router bgp 254
 bgp router-id 2.2.2.2
 timers bgp 5 15
 neighbor TASK2 peer-group
 neighbor TASK2 password 0 CCNP
 neighbor TASK2 update-source Loopback0
 neighbor TASK2 send-community
 neighbor 1.1.1.1 remote-as 254
 neighbor 1.1.1.1 peer-group TASK2
 neighbor 3.3.3.3 remote-as 254
 neighbor 3.3.3.3 peer-group TASK2
```

A peer group is a configuration template that exists only on the router where it is written. The neighbor at the other end knows nothing about it and needs its own matching configuration (password, update-source). The group removes repetition and lets the router build one update for all members. R4 uses the same structure.

### 4.4 Route reflector cluster

R1 and R3 both reflect for R2 and R4, and use the same cluster ID:

```
router bgp 254
 bgp cluster-id 13.13.13.13
```

- R2 and R4 are clients of **both** reflectors, so each client keeps working if one reflector is lost.
- R1 and R3 are ordinary (non-client) iBGP peers of each other.
- When a reflector reflects a route it prepends its cluster ID to CLUSTER_LIST, and it discards any route that already contains its own cluster ID. With a shared cluster ID, R3 discards the copy of a route that R1 has already reflected (and vice versa), so the two reflectors do not keep duplicate copies of every client prefix. This is the "reduce the size of the RIB" in the task. The clients still receive a path from each reflector, which is the redundancy.

### 4.5 Redistributing the LANs with a community

```
route-map REDISTRIBUTE permit 10
 match interface Ethernet1/3
 set community no-export

router bgp 254
 redistribute connected route-map REDISTRIBUTE
```

(The interface differs per router: e1/3 on R1, e1/1 on R2, e1/2 on R3, e1/1 on R4.)

- A plain `redistribute connected` imports **every** connected network, including Loopback 0 and the transit links. The route-map selects only the LAN interface; everything else hits the implicit deny and stays out of BGP.
- The community `no-export` tells any router not to advertise the prefix to eBGP peers, so when ISP sessions are added later the LANs cannot leak. `local-AS` was tried first; without BGP confederations the two behave the same toward external peers, and `no-export` is the conventional choice for "never leave the AS".
- **Interpretation of "no filters":** the route-map is used to *select* the source interface and to *set an attribute*. It does not filter anything between neighbors, and no prefix list, ACL or outbound policy is used.
- Communities are not sent by default. `send-community` is required for **every** neighbor on every router, including each reflector-to-client session; otherwise the reflector copies the route to the client without the attribute.

### 4.6 Path preference on R3 (Task 5)

```
! R3 only
route-map TASK5 permit 10
 set local-preference 5000

router bgp 254
 neighbor 2.2.2.2 route-map TASK5 in
 neighbor 4.4.4.4 route-map TASK5 in
```

Local preference is carried between iBGP peers, so a value set on R3 travels with the route. R3 raises the preference of routes it receives from R2 and R4, then reflects them to the other client. R4 sees 150.2.2.0/24 twice: via R3 with local-preference 5000 and via R1 with the default 100, and it picks R3. R2 does the same for 150.4.4.0/24. Only R3 is configured, and no administrative distance is touched. The route-map is not applied to the R1 neighbor, so 150.1.1.0/24 keeps its default preference.

### 4.7 Management access for automation

After the five tasks were complete, every router received the same SSH baseline so that validation can be run against all four devices from a script instead of by hand. These commands do not touch the routing design.

```
ip domain name LAB
ip ssh version 2
crypto key generate rsa        ! modulus 2048
username cisco secret cisco
enable secret cisco
line 0 4
 transport input ssh
 login local
```

- `ip domain name` is required because the RSA key pair is named from the hostname and the domain name; key generation fails without it.
- `ip ssh version 2` and a 2048-bit key restrict access to SSHv2 with a modern key size.
- `username ... secret` creates a local account (stored as a hash), and `login local` makes the lines authenticate against it.
- `transport input ssh` on the lines disables Telnet, so SSH is the only way in over the network.
- `enable secret` gives automation tools access to privileged EXEC.
- The credentials are lab-only. They are published here because the environment is an isolated EVE-NG lab; never reuse them anywhere real.

R1 also gets one extra interface, `Ethernet1/2` (200.0.0.2/30), facing the WAN switch that connects the lab to the Internet and provides the path used by the automation.

```
! R1 only
router eigrp 254
 network 200.0.0.0 0.0.0.3
```

- The `network` statement enables EIGRP on `Ethernet1/2` and advertises 200.0.0.0/30 to the rest of the lab. R2, R3 and R4 therefore learn the segment through EIGRP and can send traffic toward the WAN side through R1. Whether the WAN switch forms an EIGRP adjacency depends on its own configuration, which is outside this lab.
- The segment stays out of BGP: `redistribute connected` is controlled by the `REDISTRIBUTE` route-map, which matches only the LAN interface, and EIGRP routes are not redistributed into BGP. The `show ip bgp` table is therefore identical to the one verified in section 5.
- The automation that uses this access is described in section 6.

### 4.8 Complete configurations

<details>
<summary>R1</summary>

```
hostname R1
!
interface Loopback0
 ip address 1.1.1.1 255.255.255.255
interface Ethernet1/0
 ip address 10.0.0.1 255.255.255.252
 duplex full
 no shutdown
interface Ethernet1/1
 ip address 10.0.0.5 255.255.255.252
 duplex full
 no shutdown
interface Ethernet1/2
 ip address 200.0.0.2 255.255.255.252
 duplex full
 no shutdown
interface Ethernet1/3
 ip address 150.1.1.1 255.255.255.0
 duplex full
 no shutdown
!
router eigrp 254
 network 10.0.0.0 0.0.0.3
 network 10.0.0.4 0.0.0.3
 network 1.1.1.1 0.0.0.0
 network 200.0.0.0 0.0.0.3
!
route-map REDISTRIBUTE permit 10
 match interface Ethernet1/3
 set community no-export
!
router bgp 254
 bgp router-id 1.1.1.1
 bgp cluster-id 13.13.13.13
 timers bgp 5 15
 redistribute connected route-map REDISTRIBUTE
 neighbor 2.2.2.2 remote-as 254
 neighbor 2.2.2.2 password 0 CCNP
 neighbor 2.2.2.2 update-source Loopback0
 neighbor 2.2.2.2 route-reflector-client
 neighbor 2.2.2.2 send-community
 neighbor 3.3.3.3 remote-as 254
 neighbor 3.3.3.3 password 0 CCNP
 neighbor 3.3.3.3 update-source Loopback0
 neighbor 3.3.3.3 send-community
 neighbor 4.4.4.4 remote-as 254
 neighbor 4.4.4.4 password 0 CCNP
 neighbor 4.4.4.4 update-source Loopback0
 neighbor 4.4.4.4 route-reflector-client
 neighbor 4.4.4.4 send-community
!
ip domain name LAB
ip ssh version 2
crypto key generate rsa        ! modulus 2048
username cisco secret cisco
enable secret cisco
line 0 4
 transport input ssh
 login local
```
</details>

<details>
<summary>R2</summary>

```
hostname R2
!
interface Loopback0
 ip address 2.2.2.2 255.255.255.255
interface Ethernet1/0
 ip address 10.0.0.2 255.255.255.252
 duplex full
 no shutdown
interface Ethernet1/1
 ip address 150.2.2.2 255.255.255.0
 duplex full
 no shutdown
!
router eigrp 254
 network 10.0.0.0 0.0.0.3
 network 2.2.2.2 0.0.0.0
!
route-map REDISTRIBUTE permit 10
 match interface Ethernet1/1
 set community no-export
!
router bgp 254
 bgp router-id 2.2.2.2
 timers bgp 5 15
 redistribute connected route-map REDISTRIBUTE
 neighbor TASK2 peer-group
 neighbor TASK2 password 0 CCNP
 neighbor TASK2 update-source Loopback0
 neighbor TASK2 send-community
 neighbor 1.1.1.1 remote-as 254
 neighbor 1.1.1.1 peer-group TASK2
 neighbor 3.3.3.3 remote-as 254
 neighbor 3.3.3.3 peer-group TASK2
!
ip domain name LAB
ip ssh version 2
crypto key generate rsa        ! modulus 2048
username cisco secret cisco
enable secret cisco
line 0 4
 transport input ssh
 login local
```
</details>

<details>
<summary>R3</summary>

```
hostname R3
!
interface Loopback0
 ip address 3.3.3.3 255.255.255.255
interface Ethernet1/0
 ip address 10.0.0.6 255.255.255.252
 duplex full
 no shutdown
interface Ethernet1/1
 ip address 10.0.0.13 255.255.255.252
 duplex full
 no shutdown
interface Ethernet1/2
 ip address 150.3.3.3 255.255.255.0
 duplex full
 no shutdown
!
router eigrp 254
 network 10.0.0.12 0.0.0.3
 network 10.0.0.4 0.0.0.3
 network 3.3.3.3 0.0.0.0
!
route-map REDISTRIBUTE permit 10
 match interface Ethernet1/2
 set community no-export
route-map TASK5 permit 10
 set local-preference 5000
!
router bgp 254
 bgp router-id 3.3.3.3
 bgp cluster-id 13.13.13.13
 timers bgp 5 15
 redistribute connected route-map REDISTRIBUTE
 neighbor 1.1.1.1 remote-as 254
 neighbor 1.1.1.1 password 0 CCNP
 neighbor 1.1.1.1 update-source Loopback0
 neighbor 1.1.1.1 send-community
 neighbor 2.2.2.2 remote-as 254
 neighbor 2.2.2.2 password 0 CCNP
 neighbor 2.2.2.2 update-source Loopback0
 neighbor 2.2.2.2 route-reflector-client
 neighbor 2.2.2.2 send-community
 neighbor 2.2.2.2 route-map TASK5 in
 neighbor 4.4.4.4 remote-as 254
 neighbor 4.4.4.4 password 0 CCNP
 neighbor 4.4.4.4 update-source Loopback0
 neighbor 4.4.4.4 route-reflector-client
 neighbor 4.4.4.4 send-community
 neighbor 4.4.4.4 route-map TASK5 in
!
ip domain name LAB
ip ssh version 2
crypto key generate rsa        ! modulus 2048
username cisco secret cisco
enable secret cisco
line 0 4
 transport input ssh
 login local
```
</details>

<details>
<summary>R4</summary>

```
hostname R4
!
interface Loopback0
 ip address 4.4.4.4 255.255.255.255
interface Ethernet1/0
 ip address 10.0.0.14 255.255.255.252
 duplex full
 no shutdown
interface Ethernet1/1
 ip address 150.4.4.4 255.255.255.0
 duplex full
 no shutdown
!
router eigrp 254
 network 10.0.0.12 0.0.0.3
 network 4.4.4.4 0.0.0.0
!
route-map REDISTRIBUTE permit 10
 match interface Ethernet1/1
 set community no-export
!
router bgp 254
 bgp router-id 4.4.4.4
 timers bgp 5 15
 redistribute connected route-map REDISTRIBUTE
 neighbor TASK2 peer-group
 neighbor TASK2 password 0 CCNP
 neighbor TASK2 update-source Loopback0
 neighbor TASK2 send-community
 neighbor 1.1.1.1 remote-as 254
 neighbor 1.1.1.1 peer-group TASK2
 neighbor 3.3.3.3 remote-as 254
 neighbor 3.3.3.3 peer-group TASK2
!
ip domain name LAB
ip ssh version 2
crypto key generate rsa        ! modulus 2048
username cisco secret cisco
enable secret cisco
line 0 4
 transport input ssh
 login local
```
</details>

## 5. Verification

Verification is automated. Each check below is collected by an Ansible playbook (see section 6) from all four routers in a single run, and the raw `show` and `ping` output is stored per router and per check under [`Automation/bgp_lab2_verification/results/`](Automation/bgp_lab2_verification/results/). That output is the evidence for this table. The playbooks collect the output; the pass criteria in the "Expected result" column are judged by reading it (see the limitations in section 6.8).

| # | Check | Expected result | Playbook and results folder |
|---|---|---|---|
| 1 | EIGRP neighbors | R1 and R3: 2 neighbors; R2 and R4: 1 neighbor (R1 shows one more only if the WAN switch also runs EIGRP) | [`01_eigrp_neighbors`](Automation/bgp_lab2_verification/results/01_eigrp_neighbors/) |
| 2 | Loopbacks reachable | All loopbacks learned via EIGRP (R2, R3 and R4 also learn 200.0.0.0/30); pings to 4.4.4.4 sourced from each loopback succeed | [`02_loopback_reachability`](Automation/bgp_lab2_verification/results/02_loopback_reachability/) |
| 3 | Sessions up | R1/R3: 3 neighbors, R2/R4: 2 neighbors, all with a numeric `State/PfxRcd` | [`03_bgp_summary_router_id`](Automation/bgp_lab2_verification/results/03_bgp_summary_router_id/) |
| 4 | Router IDs | `BGP router identifier` equals the router's loopback | [`03_bgp_summary_router_id`](Automation/bgp_lab2_verification/results/03_bgp_summary_router_id/) |
| 5 | Timers and MD5 | Hold time 15, keepalive 5, MD5 password in use, for every neighbor | [`05_timers_md5`](Automation/bgp_lab2_verification/results/05_timers_md5/) |
| 6 | Peer group | R2 and R4: group `TASK2` with members 1.1.1.1 and 3.3.3.3 | [`06_peer_group`](Automation/bgp_lab2_verification/results/06_peer_group/) |
| 7 | Reflector clients | R1 and R3 report R2 and R4 as route-reflector clients | [`07_reflector_clients`](Automation/bgp_lab2_verification/results/07_reflector_clients/) |
| 8 | Cluster ID and loop prevention | R4 sees 150.2.2.0/24 with `Originator: 2.2.2.2` and `Cluster list: 13.13.13.13` | [`08_cluster_list`](Automation/bgp_lab2_verification/results/08_cluster_list/) |
| 9 | Only the LANs in BGP | Only 150.x.x.0/24 prefixes; no loopbacks, 10.0.0.x or 200.0.0.0/30 | [`09_bgp_table`](Automation/bgp_lab2_verification/results/09_bgp_table/) |
| 10 | Community on every path | `Community: no-export` on **each** path of each LAN prefix | [`10_communities`](Automation/bgp_lab2_verification/results/10_communities/) |
| 11 | send-community per neighbor | The community attribute is sent to every neighbor of every router | [`11_send_community`](Automation/bgp_lab2_verification/results/11_send_community/) |
| 12 | Path preference | R2 and R4: best path (`>`) via 3.3.3.3 with `localpref 5000`; backup via 1.1.1.1 with `localpref 100` | [`12_path_preference`](Automation/bgp_lab2_verification/results/12_path_preference/) |
| 13 | Full LAN reachability | Every router reaches the other three LANs, sourced from its own LAN address (100 % success) | [`13_ping_matrix`](Automation/bgp_lab2_verification/results/13_ping_matrix/) |
| 14 | SSH management access | Every router accepts SSH logins from the controller | No dedicated playbook: every playbook connects over SSH with the local `cisco` account, so a successful run proves it |

### Packet-level validation (Wireshark)

A single capture, `pcap/bgp-lab-02.pcapng`, was taken on the **R1–R3 link** (R1 e1/1 – R3 e1/0, 10.0.0.4/30). The physical topology is a chain, so this link is the middle of every path: besides the direct R1↔R3 session it carries the R2↔R3 and R1↔R4 sessions in transit, plus every reflected prefix and the ICMP between the outer LANs. The R1↔R2 and R3↔R4 sessions are not visible from this point.

The capture was started *before* the sessions were reset (`clear ip bgp *` on both R1 and R3, so that all five sessions re-establish), left running for about 30 seconds after they came up, and ended with extended pings between 150.2.2.2 and 150.4.4.4 sourced from the LAN addresses.

Each claim is verified with a display filter on the same file:

| Display filter | What it proves |
|---|---|
| `tcp.port == 179` | Every BGP session crossing the link |
| `bgp && ip.addr == 10.0.0.0/8` | **Expected: no packets.** Every BGP packet uses loopback addresses, so `update-source Loopback0` is in effect |
| `ip.addr == 2.2.2.2 && ip.addr == 3.3.3.3 && tcp.port == 179` | The R2↔R3 session between non-adjacent routers crossing R1, which shows that loopback peering needs only IP reachability |
| `bgp.type == 1` | OPEN messages: Hold Time 15 and the BGP identifiers (router IDs) of each pair |
| `bgp.type == 4` | KEEPALIVEs arrive about every 5 s per session (Time delta column) |
| `tcp.option_kind == 19` | MD5 signature option in the TCP header of every BGP segment |
| `bgp.type == 2` | UPDATE messages: NLRI and path attributes |
| `bgp.type == 2 && bgp.update.path_attribute.type_code == 8` | COMMUNITIES attribute on the 150.x.x.0/24 prefixes: `no-export` (0xFFFFFF01) |
| `bgp.type == 2 && bgp.update.path_attribute.type_code == 9` | ORIGINATOR_ID on reflected routes (2.2.2.2 for 150.2.2.0/24, 4.4.4.4 for 150.4.4.0/24) |
| `bgp.type == 2 && bgp.update.path_attribute.type_code == 10` | CLUSTER_LIST containing the shared cluster ID 13.13.13.13 |
| `bgp.type == 2 && bgp.update.path_attribute.type_code == 5` | LOCAL_PREF: updates from R3 for 150.2.2.0/24 and 150.4.4.0/24 carry 5000, while R1's own prefix keeps 100 |
| `icmp` | Echo requests and replies between 150.2.2.2 and 150.4.4.4 crossing the link, proving data-plane reachability |

Notes:

- MD5 authenticates the segment but does not encrypt it, so BGP messages stay readable in Wireshark; only the presence of option 19 shows that authentication is active.
- Filters on a specific attribute *value* (for example `LOCAL_PREF == 5000`) depend on the Wireshark version's field names. The easiest way to build them is to expand the attribute in the packet details, right-click the value and choose *Apply as Filter*.
- The attribute-type filters use the BGP path attribute type codes: 5 = LOCAL_PREF, 8 = COMMUNITIES, 9 = ORIGINATOR_ID, 10 = CLUSTER_LIST.

## 6. Verification Automation (Ansible)

### 6.1 Overview

After the lab was finished, the verification from section 5 was automated with Ansible. Instead of logging in to four routers and typing the same `show` commands by hand, one command connects to all four routers over SSH, runs a fixed set of read-only commands, and writes the output into a results folder that is committed to the repository next to the README.

Why this approach:

- **Repeatable.** The same commands run in the same way after every change, for example after the `send-community` fix, and `git diff` on the results shows what changed.
- **Parallel.** Ansible runs each task on all four routers at once (its default of five parallel forks covers the four routers).
- **Evidence by design.** Every check in section 5 has a playbook, and every playbook writes one file per router, so the repository documents the verification without screenshots.
- **Safe.** The playbooks only run `show` and `ping` commands through `ios_command`; they never enter configuration mode.

### 6.2 Repository layout

```
LAB-2/Automation/bgp_lab2_verification/
├── ansible.cfg        # Ansible defaults and connection timeouts
├── inventory.ini      # the four routers and how to log in to them
├── run_all.sh         # runs every playbook in order
├── playbooks/         # 13 playbooks, one per verification
│   ├── 01_eigrp_neighbors.yml
│   ├── 02_loopback_reachability.yml
│   ├── 03_bgp_summary_router_id.yml
│   ├── 05_timers_md5.yml
│   ├── 06_peer_group.yml
│   ├── 07_reflector_clients.yml
│   ├── 08_cluster_list.yml
│   ├── 09_bgp_table.yml
│   ├── 10_communities.yml
│   ├── 11_send_community.yml
│   ├── 12_path_preference.yml
│   └── 13_ping_matrix.yml
└── results/           # created by the playbooks
    └── <playbook name>/R1.txt, R2.txt, R3.txt, R4.txt
```

The playbook numbers follow the check numbers in section 5. There is no `04` playbook because check 4 (router IDs) is read from the same `show ip bgp summary` output as check 3.

### 6.3 Prerequisites

- Ansible on a controller machine, with the `cisco.ios` and `ansible.netcommon` collections (`ansible-galaxy collection install cisco.ios ansible.netcommon`) and the `paramiko` Python library, which is the SSH transport configured in the inventory.
- The SSH baseline from section 4.7 on every router: local user `cisco`, `enable secret`, SSHv2, and SSH-only VTY lines.
- IP reachability from the controller to the routers' Loopback 0 addresses, because the inventory addresses the routers by their loopbacks. The controller enters the lab through the WAN switch and R1's `Ethernet1/2`, and EIGRP carries the loopbacks and the 200.0.0.0/30 segment between the lab routers.

### 6.4 Configuration files

**`ansible.cfg`**

| Setting | Value | Purpose |
|---|---|---|
| `inventory` | `inventory.ini` | Use the lab inventory without passing `-i` |
| `host_key_checking` | `False` | Do not stop to ask about unknown SSH host keys; acceptable only in a disposable lab |
| `retry_files_enabled` | `False` | Do not create `.retry` files after failed runs |
| `stdout_callback` | `default` | Standard console output |
| `interpreter_python` | `auto_silent` | Detect the Python interpreter without warnings |
| `connect_timeout` (persistent connection) | `30` s | Time allowed to open the SSH session |
| `command_timeout` (persistent connection) | `60` s | Time allowed for a single command; this matters for `ping`, which waits for replies |

**`inventory.ini`**

```
[routers]
R1 ansible_host=1.1.1.1 ...
R2 ansible_host=2.2.2.2 ...
R3 ansible_host=3.3.3.3 ...
R4 ansible_host=4.4.4.4 ...

[routers:vars]
ansible_connection=ansible.netcommon.network_cli
ansible_network_os=cisco.ios.ios
ansible_user=cisco
ansible_password=cisco
ansible_become=true
ansible_become_method=enable
ansible_become_password=cisco
```

- All four routers form the group `routers`, which every playbook targets (`hosts: routers`). The host names `R1` to `R4` are also the keys used inside the playbooks.
- Each router is addressed by its **Loopback 0** address. The control machine therefore reaches R2, R3 and R4 only through R1 and the lab network itself, so verification depends on a working underlay.
- `network_cli` is the connection type for CLI-based network devices, and `ansible_network_os=cisco.ios.ios` selects the IOS behaviour. `ansible_become` with the `enable` method moves every session into privileged EXEC using the enable secret from section 4.7.
- The SSH library is set to `paramiko` on each host and to `libssh` for the whole group. The per-host value takes precedence in Ansible's variable order, so `paramiko` is the one in use and the group-level `libssh` line is redundant.
- The credentials are in clear text because this is an isolated lab. Outside a lab they belong in Ansible Vault.

**`run_all.sh`**

```
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
for playbook in playbooks/*.yml; do
  echo "===== Running ${playbook} ====="
  ansible-playbook "$playbook"
done
```

- `set -euo pipefail` makes the script stop on the first error, on an unset variable and on a failed command inside a pipe. A failing playbook therefore stops the run instead of being silently skipped.
- `cd "$(dirname "$0")"` moves into the script's own folder, so `ansible.cfg`, `inventory.ini` and the relative `playbooks/` path are found no matter where the script is launched from.
- The `for` loop runs the playbooks in alphabetical order, which is the numeric order 01 to 13 because of the file-name prefixes.
- Run everything with `./run_all.sh` (the file needs the executable bit), or a single check with, for example, `ansible-playbook playbooks/09_bgp_table.yml`.

### 6.5 Anatomy of a playbook

All 13 playbooks share the same template and differ only in their name, their result folder and their command lists.

```yaml
- name: Verification 01 - EIGRP neighbors
  hosts: routers
  gather_facts: false
  vars:
    result_dir: "{{ playbook_dir }}/../results/01_eigrp_neighbors"
    verification_commands:
      R1:
        - "show ip eigrp neighbors"
      R2: ...
  tasks:
    - name: Ensure local result directory exists      # task 1
    - name: Run verification commands                 # task 2
    - name: Save command output for this router       # task 3
```

- **`gather_facts: false`** skips fact collection, which is not needed and would only add time.
- **`result_dir`** is built from `playbook_dir`, so results always land in `results/<playbook name>/` next to the `playbooks/` folder.
- **`verification_commands`** is a dictionary keyed by router name. Each router runs only its own list, which is how a check can ask R1 for one thing and R4 for another.
- **Task 1** creates the result folder with the `file` module. It runs on the controller (`delegate_to: localhost`) and only once (`run_once: true`), not once per router. `become: false` stops the global enable-mode setting from being applied to these local tasks.
- **Task 2** runs the router's commands with `cisco.ios.ios_command` and registers the result. `verification_output.stdout` is a list with one entry per command, in the same order as the commands.
- **Task 3** writes one text file per router with the `copy` module. A Jinja2 loop walks `verification_output.stdout`, and `loop.index0` picks the matching command from the dictionary so each output is labelled with the command that produced it. The timestamp comes from `date -Is` on the controller, in ISO 8601 format with the time zone.

Each run overwrites the previous file for that router and check, so the folder always holds the latest run, and the git history keeps the older ones. The saved file has this format:

```
Verification: Verification 01 - EIGRP neighbors
Router: R1
Timestamp (controller): <ISO 8601 timestamp>
========================================
COMMAND 1: show ip eigrp neighbors
----------------------------------------
<command output>
```

When a playbook has several commands, the `COMMAND n:` blocks follow one another in the same file.

### 6.6 Playbook catalogue

| Playbook | Check | Commands (per router) | What to look for in the output |
|---|---|---|---|
| `01_eigrp_neighbors` | 1 | `show ip eigrp neighbors` on all routers | Neighbor count: 2 on R1 and R3, 1 on R2 and R4 |
| `02_loopback_reachability` | 2 | `show ip route eigrp`; `ping 4.4.4.4 source <own loopback>` | All other loopbacks in the EIGRP routes (plus 200.0.0.0/30 on R2, R3 and R4); successful pings. On R4 the ping targets its own loopback, so it is a local self-test and does not test the network |
| `03_bgp_summary_router_id` | 3 and 4 | `show ip bgp summary` | The router identifier equals the loopback, local AS 254, every neighbor with a numeric `State/PfxRcd` |
| `05_timers_md5` | 5 | For each neighbor: `show ip bgp neighbors <ip> \| include hold time\|keepalive\|MD5\|md5\|Password` | Hold time 15, keepalive 5, and the MD5 password indication. The filter lists several spellings so it matches whichever wording the IOS version uses |
| `06_peer_group` | 6 | R2 and R4: `show ip bgp peer-group TASK2`; R1 and R3: `show ip bgp summary` | On R2 and R4, group `TASK2` with members 1.1.1.1 and 3.3.3.3. On R1 and R3 the summary shows per-neighbor sessions up; the absence of a peer group there is a configuration requirement confirmed from the configs in section 4 |
| `07_reflector_clients` | 7 | R1 and R3: `show ip bgp neighbors <ip> \| include Route-Reflector` for 2.2.2.2 and 4.4.4.4; R2 and R4: `show ip bgp summary` | Both clients reported as route-reflector clients on each reflector. The R1↔R3 neighbor is deliberately not queried, because it is not a client |
| `08_cluster_list` | 8 | R1 and R4: `show ip bgp 150.2.2.0`; R2 and R3: `show ip bgp summary` | On R4, `Originator: 2.2.2.2` and `Cluster list: 13.13.13.13`. Compare the number of paths on R1 and R4: with the shared cluster ID, R1 should keep only its direct path from R2, while R4 keeps one path from each reflector |
| `09_bgp_table` | 9 | `show ip bgp` on all routers | Exactly the four 150.x.x.0/24 prefixes, nothing else |
| `10_communities` | 10 | R1 and R3: `show ip bgp community no-export`; R2: `show ip bgp 150.4.4.0` and the community query; R4: `show ip bgp 150.2.2.0` and the community query | `Community: no-export` on every path of the prefix, and all LAN prefixes listed by the community query |
| `11_send_community` | 11 | For each neighbor: `show ip bgp neighbors <ip> \| include community` | A line stating that the community attribute is sent to the neighbor, for every neighbor on every router. This is the check that exposes the missing `send-community` problem from the troubleshooting log |
| `12_path_preference` | 12 | R1: 150.2.2.0 and 150.4.4.0; R2: 150.4.4.0; R3: 150.2.2.0 and 150.4.4.0; R4: 150.2.2.0 (all `show ip bgp <prefix>`) | On R2 and R4 the best path (`>`) comes from 3.3.3.3 with `localpref 5000`, and the path from 1.1.1.1 keeps `localpref 100`. The R1 and R3 views give context for where the value is set |
| `13_ping_matrix` | 13 | Each router pings the three other LANs, sourced from its own LAN address | Three successful pings per router, 12 in total. The `source` keyword is required, because the 10.0.0.x transit addresses are not advertised in BGP and the remote router could not reply to them |

### 6.7 Typical workflow

1. Bring the lab up and confirm that the controller can reach the loopbacks.
2. Run `./run_all.sh`.
3. Open the result files and compare them with the "Expected result" column in section 5.
4. After any configuration change, rerun the affected playbook (or all of them) and review the difference with `git diff`; the timestamp lines will differ on every run.
5. Commit the `results/` folder together with the README.

### 6.8 Design decisions and limitations

- **Evidence collection, not assertion.** The playbooks record what the routers say but do not decide pass or fail. The judgement is made by reading the files. A natural next step is to add `ansible.builtin.assert` tasks that test the output for the expected strings, so a run ends with PASS or FAIL per check.
- **One playbook per verification.** Each check can be run alone, failures are easy to locate, and the result folders map one-to-one to the table in section 5. The cost is repeated boilerplate in 13 files; moving the shared tasks into a role or a common task file, with only the command lists left per playbook, would remove it.
- **Hard-coded command lists.** The commands and neighbor addresses are written directly in each playbook, so adding a router means editing every file. Generating them from inventory variables would avoid that.
- **Plain-text output.** The output is stored as text, not as structured data. Parsing it (for example with `ansible.netcommon.cli_parse`) would allow real comparisons and a summary table.
- **Weak spots in a few checks.** The R4 loopback self-ping and the `show ip bgp summary` output collected on R1 and R3 for the peer-group check do not prove what their check names suggest; the table in section 6.6 says what each output does and does not show.
- **Dependency on the underlay.** Because the routers are addressed by their loopbacks, a broken EIGRP underlay also breaks the verification itself, so a connection failure points to Task 2 before anything else.
- **Credentials.** The username and passwords are in clear text, acceptable in this isolated lab only.

## 7. Concepts Learned

**iBGP peering on loopbacks.** BGP runs over TCP port 179, so it needs only IP reachability between the endpoints. An IGP supplies the loopback routes. `update-source` must be set on both sides, because each router checks the source address of incoming sessions.

**Peer groups are local.** A peer group is a template on one router. It is never signalled to the neighbors. The other end must be configured separately, and each router can have its own group.

**Route reflector rules.** A route from a client goes to all clients and non-clients; a route from a non-client goes to clients only. Making a router a client of both reflectors gives redundancy; the shared cluster ID prevents the reflectors from re-accepting each other's reflected copies.

**ORIGINATOR_ID and CLUSTER_LIST.** Reflectors replace the AS_PATH-based loop check with these two attributes. A reflector drops a route whose CLUSTER_LIST contains its own cluster ID. By default the cluster ID is the router ID, which is why two reflectors are separate clusters unless configured otherwise.

**Redistribution scope.** `redistribute connected` takes every connected network. Selecting only the wanted source with a route-map keeps infrastructure prefixes such as loopbacks and transit links out of BGP.

**Communities.** `no-export` keeps a route inside the AS (and out of eBGP sessions), but only if the attribute survives the whole path. Communities need `send-community` per neighbor, including reflector-to-client sessions.

**Local preference.** An iBGP-wide attribute: higher is better, default 100, carried in updates between iBGP peers. Setting it where routes enter the AS or are reflected makes the decision consistent for other routers. Setting the default value (100) changes nothing.

**Where an attribute takes effect.** `weight` is local to the router and is never advertised, so it cannot satisfy "globally significant". Local preference is advertised inside the AS, so one router can influence the choice of several others.

## 8. Troubleshooting Log

| Symptom | Root cause | How it was found | Fix |
|---|---|---|---|
| iBGP sessions flapped after `redistribute connected` was added | The redistribution imported all connected networks, including Loopback 0 (the BGP peering address) and the transit links, into BGP; this is the most likely source of the instability | `show ip bgp` contained the loopback and 10.0.0.x prefixes | Route-map with `match interface <LAN>` on the `redistribute` statement |
| Community missing on some paths | Several reflector-to-client sessions lacked `send-community` (R1 to 4.4.4.4 and R3 to 2.2.2.2), so the reflected copy was sent without the attribute | `show ip bgp 150.2.2.0` on R4 and `show ip bgp 150.4.4.0` on R2 showed `Community` on only one of the two paths | Added `send-community` to the missing neighbors, then `clear ip bgp * soft out` |
| Prefix reached R4 even though R4 was a client of only one reflector | An asymmetric design (R2 a client of R1 only, R4 a client of R3 only) still works through reflection, but each client depends on a single reflector | Compared the client list against the requirement that R2 and R4 peer with both | Made R2 and R4 clients of both R1 and R3 |
| Task 5 had no effect with `set local-preference 100` | 100 is the default value, and the policy was applied on R4 only, so it could not influence R2 | `show ip bgp 150.2.2.0` already showed `localpref 100` | Moved the policy to R3 (value 5000) and applied it to the R2 and R4 neighbors only |

**Takeaway:** a prefix being present in the table, or a ping succeeding, does not prove the policy works. The community was missing from one of two paths while everything still looked reachable. Always inspect every path of a prefix, not only the best one, and check which router an attribute is actually set on.

## 9. Repository Structure

```
BGP-LABS/LAB-2/
├── README.md
├── configs/        # running-config of R1–R4
├── screenshots/    # topology figure (section 2)
├── pcap/           # bgp-lab-02.pcapng, single capture on the R1–R3 link (section 5)
└── Automation/
    └── bgp_lab2_verification/
        ├── ansible.cfg
        ├── inventory.ini
        ├── run_all.sh
        ├── playbooks/    # 13 verification playbooks (section 6)
        └── results/      # per-router output of every playbook (section 5 evidence)
```

## 10. Conclusion

This lab combined an EIGRP underlay with an iBGP overlay built on loopback addresses, a redundant pair of route reflectors sharing a single cluster ID, and two small policies that each had a network-wide effect: a `no-export` community that keeps the LANs inside AS 254, and a local-preference set on one router that steers two others. The main lessons came from the mistakes. A broad `redistribute connected` pulled infrastructure prefixes into BGP, a missing `send-community` silently removed the protection on one of two paths, and a policy placed on the wrong router had no effect on the rest of the network. Verification was done at three levels: control plane (`show ip bgp` per prefix and per path, neighbor details), data plane (pings between all LANs), and packet level (a Wireshark capture of OPEN, KEEPALIVE and UPDATE messages showing loopback-sourced sessions, MD5, communities, cluster attributes and local preference). The control-plane and data-plane checks were then automated with 13 Ansible playbooks that collect the same read-only commands from all four routers in one run and store the output per router, which makes the verification repeatable and turns the repository itself into the evidence. The playbooks collect evidence rather than judge it, so the next step is to add automated pass/fail assertions.
