# BGP Lab 2 — iBGP over Loopbacks, Route Reflector Cluster, Community Control and Path Preference

> CCNP ENCOR (350-401) preparation · Lab source: *101 CCNP ENCOR Labs* · Platform: EVE-NG (Cisco IOS)

## 1. Overview

This lab builds a four-router iBGP domain (AS 254) on top of an EIGRP underlay. Unlike Lab 1, BGP sessions are formed between **Loopback 0** addresses, two route reflectors share one **cluster ID**, and the four 150.x.x.0/24 LANs are **redistributed** into BGP with a community that keeps them inside the AS. A single configuration change on one router then steers path selection for two other routers.

The lab forces you to think about *where* a configuration takes effect: a peer group is local to one router, a `send-community` is per neighbor, and a local-preference set on the right router becomes network-wide because iBGP carries it.

**Skills demonstrated:** EIGRP underlay design, iBGP peering on loopbacks (`update-source`), peer-group templates, route reflector redundancy and cluster ID, TCP MD5 authentication, timer tuning, selective redistribution, well-known communities, local-preference path control, SSH management access for automation, and structured troubleshooting.

## 2. Topology

| Link | Subnet | Endpoints (EVE-NG interfaces) |
|---|---|---|
| R1 – R2 | 10.0.0.0/30 | R1 e1/0 .1 / R2 e1/0 .2 |
| R1 – R3 | 10.0.0.4/30 | R1 e1/1 .5 / R3 e1/0 .6 |
| R3 – R4 | 10.0.0.12/30 | R3 e1/1 .13 / R4 e1/0 .14 |
| Automation segment | 200.0.0.0/30 | R1 e1/2 .2 (not part of the lab design) |

The book uses serial and FastEthernet interfaces; this build uses Ethernet interfaces in EVE-NG, so the names differ from the book's figure. The physical topology is a chain: **R2 — R1 — R3 — R4**.

The 200.0.0.0/30 segment on R1 e1/2 was added after the five tasks, to support the automation described in section 4.7. It is deliberately kept out of EIGRP and BGP, so it does not change the lab design.

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

The `network` statements with wildcard masks enable EIGRP only on the transit links and the loopback. The 150.x.x.0/24 LANs are deliberately left out, so they are carried by BGP alone. The loopbacks must be in EIGRP because BGP sessions between non-adjacent routers need IP reachability to each other's loopback.

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

R1 also gets one extra interface, `Ethernet1/2` (200.0.0.2/30), for the connection to the automation environment. The segment is not in EIGRP, and the `REDISTRIBUTE` route-map matches only the LAN interface, so it never enters BGP. This keeps the `show ip bgp` table identical to the one verified in section 5.

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

> Evidence for every item is stored in `screenshots/` and `pcap/` (see section 8).

| # | Check | Command | Expected result | Evidence |
|---|---|---|---|---|
| 1 | EIGRP neighbors | `show ip eigrp neighbors` | R1 and R3: 2 neighbors; R2 and R4: 1 neighbor | `screenshots/01-eigrp-neighbors-*.png` |
| 2 | Loopbacks reachable | `show ip route eigrp`, `ping 4.4.4.4 source loopback 0` | All loopbacks learned via EIGRP; pings succeed | `screenshots/02-loopback-reachability.png` |
| 3 | Sessions up | `show ip bgp summary` | R1/R3: 3 neighbors, R2/R4: 2 neighbors, all with a numeric `State/PfxRcd` | `screenshots/03-bgp-summary-*.png` |
| 4 | Router IDs | `show ip bgp summary` | `BGP router identifier` equals the loopback | `screenshots/03-bgp-summary-*.png` |
| 5 | Timers and MD5 | `show ip bgp neighbors <ip> \| include hold\|keepalive\|md5` | Hold 15, keepalive 5, MD5 in use | `screenshots/04-timers-md5.png` |
| 6 | Peer group | `show ip bgp peer-group TASK2` on R2 and R4 | Members 1.1.1.1 and 3.3.3.3 | `screenshots/05-peer-group.png` |
| 7 | Reflector clients | `show ip bgp neighbors <ip> \| include Route-Reflector` on R1 and R3 | R2 and R4 reported as clients | `screenshots/06-rr-clients.png` |
| 8 | Cluster ID and loop prevention | `show ip bgp 150.2.2.0` on R4 | `Originator: 2.2.2.2`, `Cluster list: 13.13.13.13` | `screenshots/07-cluster-list.png` |
| 9 | Only the LANs in BGP | `show ip bgp` | Only 150.x.x.0/24 prefixes; no loopbacks, 10.0.0.x or 200.0.0.0/30 | `screenshots/08-bgp-table.png` |
| 10 | Community on every path | `show ip bgp 150.2.2.0` on R4, `show ip bgp 150.4.4.0` on R2, `show ip bgp community no-export` | `Community: no-export` on **each** path | `screenshots/09-community-*.png` |
| 11 | send-community per neighbor | `show ip bgp neighbors <ip> \| include community` | Standard community sent to every neighbor | `screenshots/10-send-community.png` |
| 12 | Path preference | `show ip bgp 150.4.4.0` on R2, `show ip bgp 150.2.2.0` on R4 | Best path (`>`) via 3.3.3.3 with `localpref 5000`; backup via 1.1.1.1 with `localpref 100` | `screenshots/11-localpref-*.png` |
| 13 | Full reachability | Extended ping, source = LAN address, all pairs | 100 % success | `screenshots/12-ping-matrix.png` |
| 14 | SSH management access | `show ip ssh` on each router | `SSH Enabled - version 2.0` | `screenshots/13-ssh.png` |

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

## 6. Concepts Learned

**iBGP peering on loopbacks.** BGP runs over TCP port 179, so it needs only IP reachability between the endpoints. An IGP supplies the loopback routes. `update-source` must be set on both sides, because each router checks the source address of incoming sessions.

**Peer groups are local.** A peer group is a template on one router. It is never signalled to the neighbors. The other end must be configured separately, and each router can have its own group.

**Route reflector rules.** A route from a client goes to all clients and non-clients; a route from a non-client goes to clients only. Making a router a client of both reflectors gives redundancy; the shared cluster ID prevents the reflectors from re-accepting each other's reflected copies.

**ORIGINATOR_ID and CLUSTER_LIST.** Reflectors replace the AS_PATH-based loop check with these two attributes. A reflector drops a route whose CLUSTER_LIST contains its own cluster ID. By default the cluster ID is the router ID, which is why two reflectors are separate clusters unless configured otherwise.

**Redistribution scope.** `redistribute connected` takes every connected network. Selecting only the wanted source with a route-map keeps infrastructure prefixes such as loopbacks and transit links out of BGP.

**Communities.** `no-export` keeps a route inside the AS (and out of eBGP sessions), but only if the attribute survives the whole path. Communities need `send-community` per neighbor, including reflector-to-client sessions.

**Local preference.** An iBGP-wide attribute: higher is better, default 100, carried in updates between iBGP peers. Setting it where routes enter the AS or are reflected makes the decision consistent for other routers. Setting the default value (100) changes nothing.

**Where an attribute takes effect.** `weight` is local to the router and is never advertised, so it cannot satisfy "globally significant". Local preference is advertised inside the AS, so one router can influence the choice of several others.

## 7. Troubleshooting Log

| Symptom | Root cause | How it was found | Fix |
|---|---|---|---|
| iBGP sessions flapped after `redistribute connected` was added | The redistribution imported all connected networks, including Loopback 0 (the BGP peering address) and the transit links, into BGP; this is the most likely source of the instability | `show ip bgp` contained the loopback and 10.0.0.x prefixes | Route-map with `match interface <LAN>` on the `redistribute` statement |
| Community missing on some paths | Several reflector-to-client sessions lacked `send-community` (R1 to 4.4.4.4 and R3 to 2.2.2.2), so the reflected copy was sent without the attribute | `show ip bgp 150.2.2.0` on R4 and `show ip bgp 150.4.4.0` on R2 showed `Community` on only one of the two paths | Added `send-community` to the missing neighbors, then `clear ip bgp * soft out` |
| Prefix reached R4 even though R4 was a client of only one reflector | An asymmetric design (R2 a client of R1 only, R4 a client of R3 only) still works through reflection, but each client depends on a single reflector | Compared the client list against the requirement that R2 and R4 peer with both | Made R2 and R4 clients of both R1 and R3 |
| Task 5 had no effect with `set local-preference 100` | 100 is the default value, and the policy was applied on R4 only, so it could not influence R2 | `show ip bgp 150.2.2.0` already showed `localpref 100` | Moved the policy to R3 (value 5000) and applied it to the R2 and R4 neighbors only |

**Takeaway:** a prefix being present in the table, or a ping succeeding, does not prove the policy works. The community was missing from one of two paths while everything still looked reachable. Always inspect every path of a prefix, not only the best one, and check which router an attribute is actually set on.

## 8. Repository Structure

```
bgp-lab-02/
├── README.md
├── configs/        # running-config of R1–R4
├── screenshots/    # verification evidence (section 5)
└── pcap/           # bgp-lab-02.pcapng, single capture on the R1–R3 link (section 5)
```

## 9. Conclusion

This lab combined an EIGRP underlay with an iBGP overlay built on loopback addresses, a redundant pair of route reflectors sharing a single cluster ID, and two small policies that each had a network-wide effect: a `no-export` community that keeps the LANs inside AS 254, and a local-preference set on one router that steers two others. The main lessons came from the mistakes. A broad `redistribute connected` pulled infrastructure prefixes into BGP, a missing `send-community` silently removed the protection on one of two paths, and a policy placed on the wrong router had no effect on the rest of the network. Verification was done at three levels: control plane (`show ip bgp` per prefix and per path, neighbor details), data plane (extended pings between all LANs), and packet level (a Wireshark capture of OPEN, KEEPALIVE and UPDATE messages showing loopback-sourced sessions, MD5, communities, cluster attributes and local preference).
