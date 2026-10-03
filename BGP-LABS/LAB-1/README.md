# BGP Lab 1 — iBGP, Route Reflection, Communities and Default Origination

> CCNP ENCOR (350-401) preparation · Lab source: *101 CCNP ENCOR Labs* · Platform: EVE-NG (Cisco IOS)

## 1. Overview

This lab builds a four-router iBGP domain (AS 254) **without a full mesh and without any IGP**. Reachability between four 150.x.x.0/24 LAN segments is achieved purely with BGP features: route reflectors, next-hop manipulation, standard communities and a conditionally-free default route.

The lab goes beyond basic neighbor configuration. It forces you to understand *why* iBGP behaves the way it does (split horizon, unchanged next hop) and which tools fix it without redistribution or static routes.

**Skills demonstrated:** iBGP design, route reflector topology, BGP next-hop behaviour, TCP MD5 authentication, timer tuning, community tagging without route-maps on neighbors, and structured troubleshooting.

## 2. Topology

| Link | Subnet | Endpoints (EVE-NG interfaces) |
|---|---|---|
| R1 – R2 | 10.0.0.0/30 | R1 e1/0 .1 / R2 e1/0 .2 |
| R1 – R3 | 10.0.0.4/30 | R1 e1/1 .5 / R3 e1/0 .6 |
| R3 – R4 | 10.0.0.12/30 | R3 e1/1 .13 / R4 e1/0 .14 |

LAN interfaces: R1 e1/2, R2 e1/1, R3 e1/2, R4 e1/1. The book uses serial and FastEthernet interfaces; this build uses Ethernet interfaces in EVE-NG, so the names differ from the book's figure.

| Router | LAN | Router ID |
|---|---|---|
| R1 | 150.1.1.0/24 | 1.1.1.1 |
| R2 | 150.2.2.0/24 | 2.2.2.2 |
| R3 | 150.3.3.0/24 | 3.3.3.3 |
| R4 | 150.4.4.0/24 | 4.4.4.4 |

Peering (physical interface addresses): R1↔R2, R1↔R3, R3↔R4.

![Topology](screenshots/00-topology.png)

## 3. Lab Tasks

The lab comes from *101 CCNP ENCOR Labs*. The tasks are summarized here in my own words; the topology image is my own EVE-NG screenshot.

### Task 1: Base configuration
Set hostnames and IP addressing on all four routers according to the topology.

### Task 2: iBGP peering (AS 254)
Build iBGP sessions **without peer groups**:

- Static BGP router IDs derived from the router number (1.1.1.1 for R1, and so on).
- Peering on physical interface addresses: R1↔R2, R1↔R3, R3↔R4.
- TCP MD5 authentication with the password `CCNP` on every session.
- Keepalive every 5 seconds and a hold time of 15 seconds on every speaker.
- Standard communities must be supported (sent to neighbors).

### Task 3: Prefix advertisement with communities
Advertise the LANs of R1, R2 and R3 into BGP and tag each with a standard community:

| Prefix | Community |
|---|---|
| 150.1.1.0/24 | 254:111 |
| 150.2.2.0/24 | 254:222 |
| 150.3.3.0/24 | 254:333 |

Constraints: no redistribution, and no inbound or outbound route-maps on neighbors. Communities must be displayed in `ASN:nn` format (RFC 1997), and the result verified with the appropriate show commands.

### Task 4: Full reachability
Make all four 150.x.x.0/24 subnets reach each other under these constraints:

- No static routes and no dynamic routing protocol.
- 150.4.4.0/24 must not be advertised or redistributed into BGP on R4; other BGP features must be used instead.
- The task statement also says R2 and R4 must not be configured. The book's own solution nevertheless originates a default route on R4 with `neighbor default-originate` (see section 4.5), so the statement and the official solution are inconsistent on this point.

Verification: extended pings between LAN addresses (for example R1 to 150.2.2.2 sourced from 150.1.1.1) must all succeed.

## 4. Implementation

### 4.1 Neighbors, router ID, authentication and timers

```
router bgp 254
 bgp router-id 1.1.1.1
 timers bgp 5 15
 neighbor 10.0.0.2 remote-as 254
 neighbor 10.0.0.2 password 0 CCNP
 neighbor 10.0.0.2 send-community standard
 neighbor 10.0.0.6 remote-as 254
 neighbor 10.0.0.6 password 0 CCNP
 neighbor 10.0.0.6 send-community standard
```

- The router ID is configured inside the BGP process (`bgp router-id`), not as a standalone `router-id` command as in OSPF/EIGRP.
- `neighbor ... password` always enables TCP MD5 (RFC 2385). There is no algorithm selector; the optional leading digit only controls how the password is *stored* in the configuration.
- `timers bgp 5 15` sets keepalive and hold time. Hold time is negotiated in the OPEN message (the lower of both sides wins), so a session reset is required for new values to take effect.
- Cisco does not send communities by default; `send-community` is required per neighbor.

### 4.2 Prefix origination with communities (no neighbor route-maps)

```
ip bgp-community new-format

route-map TASK3 permit 10
 set community 254:111

router bgp 254
 network 150.1.1.0 mask 255.255.255.0 route-map TASK3
```

R2 uses `254:222` and R3 uses `254:333`. The route-map is attached to the `network` statement itself, so it only describes attributes of the locally originated prefix. It is not a neighbor policy, which satisfies the constraint. `ip bgp-community new-format` changes only the *display* (`254:111` instead of `16646255`); the value is the same 32-bit number.

### 4.3 Route reflection (R1 and R3)

```
! R1
router bgp 254
 neighbor 10.0.0.2 route-reflector-client
 neighbor 10.0.0.6 route-reflector-client

! R3
router bgp 254
 neighbor 10.0.0.14 route-reflector-client
 neighbor 10.0.0.5 route-reflector-client
```

R2 and R4 are untouched: a route-reflector client does not need to know it is a client. R1 reflects between R2 and R3, R3 reflects between R1 and R4. This removes the need for a full iBGP mesh.

> **Design note:** on R3, only R4 needs to be a client (R3 then reflects between R4 and its non-client peer R1). Declaring R1 a client of R3 as well is redundant for reachability in this topology. It is kept in the lab configuration as built.

### 4.4 Next-hop correction

```
route-map TASK4 permit 10
 set ip next-hop peer-address

router bgp 254
 neighbor 10.0.0.2 route-map TASK4 out
 neighbor 10.0.0.6 route-map TASK4 out
```

(R3 applies the same route-map outbound to both R4 (10.0.0.14) and R1 (10.0.0.5): R4 needs next hops it can resolve for the R1/R2 prefixes, and R1 needs a resolvable next hop for the default route originated by R4.) iBGP does not change the next hop, and on the IOS image used here `next-hop-self` does not apply to *reflected* routes. An outbound route-map with `set ip next-hop peer-address` rewrites the next hop to the local address of each individual session, so one route-map serves all neighbors.

### 4.5 Reaching 150.4.4.0/24 with a default route

```
! R4
router bgp 254
 neighbor 10.0.0.13 default-originate
```

`neighbor default-originate` sends 0.0.0.0/0 to that specific neighbor even when no default exists in the local table. It is not redistribution and does not create the route in R4's own BGP table. R3 receives it (R4 is a client), reflects it to R1, and R1 reflects it to R2. Everyone reaches 150.4.4.0/24 via the default; R4 reaches the rest through the specific prefixes it learns from R3.

### 4.6 Complete configurations

<details>
<summary>R1</summary>

```
hostname R1
ip bgp-community new-format
!
interface Ethernet1/0
 ip address 10.0.0.1 255.255.255.252
 duplex full
 no shutdown
interface Ethernet1/1
 ip address 10.0.0.5 255.255.255.252
 duplex full
 no shutdown
interface Ethernet1/2
 ip address 150.1.1.1 255.255.255.0
 duplex full
 no shutdown
!
route-map TASK3 permit 1
 set community 254:111
route-map TASK4 permit 10
 set ip next-hop peer-address
!
router bgp 254
 bgp router-id 1.1.1.1
 timers bgp 5 15
 network 150.1.1.0 mask 255.255.255.0 route-map TASK3
 neighbor 10.0.0.2 remote-as 254
 neighbor 10.0.0.2 password 0 CCNP
 neighbor 10.0.0.2 send-community standard
 neighbor 10.0.0.2 route-reflector-client
 neighbor 10.0.0.2 route-map TASK4 out
 neighbor 10.0.0.6 remote-as 254
 neighbor 10.0.0.6 password 0 CCNP
 neighbor 10.0.0.6 send-community standard
 neighbor 10.0.0.6 route-reflector-client
 neighbor 10.0.0.6 route-map TASK4 out
```
</details>

<details>
<summary>R2</summary>

```
hostname R2
ip bgp-community new-format
!
interface Ethernet1/0
 ip address 10.0.0.2 255.255.255.252
 duplex full
 no shutdown
interface Ethernet1/1
 ip address 150.2.2.2 255.255.255.0
 duplex full
 no shutdown
!
route-map TASK3 permit 1
 set community 254:222
!
router bgp 254
 bgp router-id 2.2.2.2
 timers bgp 5 15
 network 150.2.2.0 mask 255.255.255.0 route-map TASK3
 neighbor 10.0.0.1 remote-as 254
 neighbor 10.0.0.1 password 0 CCNP
 neighbor 10.0.0.1 send-community standard
```
</details>

<details>
<summary>R3</summary>

```
hostname R3
ip bgp-community new-format
!
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
route-map TASK3 permit 1
 set community 254:333
route-map TASK4 permit 10
 set ip next-hop peer-address
!
router bgp 254
 bgp router-id 3.3.3.3
 timers bgp 5 15
 network 150.3.3.0 mask 255.255.255.0 route-map TASK3
 neighbor 10.0.0.5 remote-as 254
 neighbor 10.0.0.5 password 0 CCNP
 neighbor 10.0.0.5 send-community standard
 neighbor 10.0.0.5 route-reflector-client
 neighbor 10.0.0.5 route-map TASK4 out
 neighbor 10.0.0.14 remote-as 254
 neighbor 10.0.0.14 password 0 CCNP
 neighbor 10.0.0.14 send-community standard
 neighbor 10.0.0.14 route-reflector-client
 neighbor 10.0.0.14 route-map TASK4 out
```
</details>

<details>
<summary>R4</summary>

```
hostname R4
!
interface Ethernet1/0
 ip address 10.0.0.14 255.255.255.252
 duplex full
 no shutdown
interface Ethernet1/1
 ip address 150.4.4.4 255.255.255.0
 duplex full
 no shutdown
!
router bgp 254
 bgp router-id 4.4.4.4
 timers bgp 5 15
 neighbor 10.0.0.13 remote-as 254
 neighbor 10.0.0.13 password 0 CCNP
 neighbor 10.0.0.13 send-community standard
 neighbor 10.0.0.13 default-originate
```
</details>

## 5. Verification

> Evidence for every item is stored in `screenshots/` and `pcap/` (see section 8).

| # | Check | Command | Expected result | Evidence |
|---|---|---|---|---|
| 1 | Sessions up on all routers | `show ip bgp summary` | All neighbors Established, numeric `State/PfxRcd` | `screenshots/01-bgp-summary-*.png` |
| 2 | Router IDs | `show ip bgp summary` | `BGP router identifier x.x.x.x` matches router number | `screenshots/01-bgp-summary-*.png` |
| 3 | Timers negotiated | `show ip bgp neighbors <ip> \| include hold\|keepalive` | Hold 15, keepalive 5 | `screenshots/02-timers.png` |
| 4 | MD5 active | `show ip bgp neighbors <ip> \| include md5\|MD5` | Session uses MD5 | `screenshots/03-md5.png` |
| 5 | Communities in ASN:nn format | `show ip bgp 150.1.1.0` on R4 | `Community: 254:111` | `screenshots/04-community-r4.png` |
| 6 | Route reflection | `show ip bgp 150.3.3.0` on R2 | `Originator` and `Cluster list` present | `screenshots/05-rr-r2.png` |
| 7 | Next hop correct | `show ip bgp` on R2 and R4 | Next hop is the adjacent router, `>` present | `screenshots/06-nexthop.png` |
| 8 | Default route | `show ip route bgp` on R1, R2, R3 | `B* 0.0.0.0/0` | `screenshots/07-default-route.png` |
| 9 | Full reachability | Extended ping, source = LAN address, all pairs | 100 % success | `screenshots/08-ping-matrix-*.png` |
| 10 | Forwarding path | `show ip cef <dest>` and `traceroute` | Egress interface matches expected path | `screenshots/09-cef-traceroute.png` |

### Packet-level validation (Wireshark)

A single capture, `pcap/bgp-lab-01.pcapng`, was taken on the **R1–R3 link**. This link carries the whole story: R1 and R3 are both route reflectors, so every prefix in the domain (including the default route originated by R4) crosses it. The capture was started *before* the session was reset (`clear ip bgp 10.0.0.6` on R1), left running for about 30 seconds after the session came up, and ended with an extended ping from 150.1.1.1 to 150.4.4.4.

Each claim is verified with a display filter on the same file:

| Display filter | What it proves |
|---|---|
| `bgp.type == 1` | OPEN messages: Hold Time 15 and BGP identifiers 1.1.1.1 / 3.3.3.3 |
| `bgp.type == 4` | KEEPALIVEs arrive every ~5 s (Time delta column) |
| `tcp.option_kind == 19` | MD5 signature option in the TCP header of every BGP segment |
| `bgp.type == 2` | UPDATEs: NLRI, next hop and path attributes |
| `bgp.type == 2` → COMMUNITIES attribute | 254:111 (150.1.1.0), 254:222 (150.2.2.0, reflected), 254:333 (150.3.3.0) |
| `bgp.type == 2` → ORIGINATOR_ID / CLUSTER_LIST | 150.2.2.0 shows originator 2.2.2.2 and the reflector's cluster ID |
| `bgp.type == 2` → NLRI 0.0.0.0/0 | Default route from R3 to R1 with ORIGINATOR_ID 4.4.4.4, proving R4 originated it |
| `bgp.type == 2` → NEXT_HOP | Rewritten to the sender's own address on this link (10.0.0.5 / 10.0.0.6) |
| `icmp` | Echo request/reply between the LANs crossing the link, proving data-plane reachability |

Note: MD5 authenticates the segment but does not encrypt it, so BGP messages stay readable in Wireshark; only the presence of the option (kind 19) shows that authentication is active.

## 6. Concepts Learned

**iBGP split horizon.** A route learned from an iBGP peer is never advertised to another iBGP peer. This prevents loops inside an AS (there is no AS_PATH change to detect them), and is why iBGP traditionally needs a full mesh.

**Route reflectors (RFC 4456).** A reflector relaxes split horizon for its *clients*. Loop prevention is replaced by two attributes: ORIGINATOR_ID (the router that first injected the route into the AS) and CLUSTER_LIST (reflectors the route passed through). Clients require no configuration.

**BGP next hop behaviour.** Next hop is unchanged inside iBGP, so every internal router must be able to resolve the next hop recursively. When it cannot, the route is inaccessible and is not installed. `next-hop-self` is the standard fix at an eBGP-to-iBGP boundary, but it did not rewrite reflected routes in this IOS version; an outbound route-map with `set ip next-hop peer-address` did.

**Soft reset and policy application.** Changing an outbound policy does not change what was already advertised. `clear ip bgp <peer> soft out` re-sends updates without dropping the session. A hard reset (`clear ip bgp *`) is only required for things negotiated in OPEN (timers, capabilities, router ID).

**Timers.** BGP has no hello packets; the equivalent is the keepalive. Keepalive is conventionally one third of hold time. Hold time is the lower value of the two peers' proposals.

**TCP MD5 (RFC 2385).** Authentication happens at the TCP layer, so a mismatch silently drops segments and logs `%TCP-6-BADAUTH`. MD5 is legacy; TCP-AO (RFC 5925) is the modern replacement.

**Communities (RFC 1997).** A 32-bit tag (`ASN:nn`) with no inherent behaviour; policy elsewhere acts on it. Not sent unless `send-community` is configured. Well-known values: `no-export`, `no-advertise`, `local-AS`.

**`network` vs `redistribute` vs `default-originate`.** `network` requires an exact match in the RIB. `redistribute` imports from another source. `neighbor default-originate` is a per-neighbor feature that sends 0.0.0.0/0 regardless of the local table.

**CEF as ground truth.** `show ip cef` shows how the router actually forwards, which can differ from what the BGP table suggests.

## 7. Troubleshooting Log

| Symptom | Root cause | How it was found | Fix |
|---|---|---|---|
| No `router-id` command in BGP mode | Command is `bgp router-id` | Used `bgp ?` | Configured under `router bgp` |
| R2 and R3 did not see each other's prefixes | iBGP split horizon | Compared `show ip bgp` on all routers | Route-reflector-client on R1 and R3 |
| Reflected prefixes had unreachable next hops | iBGP leaves next hop unchanged; `next-hop-self` did not affect reflected routes | `show ip route` showed next hop of another subnet | Outbound route-map, `set ip next-hop peer-address` |
| Route-map configured but R3 still held an old next hop | Outbound policy not re-applied to already-sent updates | Next hop corrected right after `clear ip bgp 10.0.0.6 soft out` | Soft reset after every outbound policy change |
| R3 forwarded traffic for 150.1.1.0 toward R4 | Unresolvable next hop was recursively resolved through the default route from R4 | `show ip cef 150.1.1.1` showed egress toward R4 | Fixed the next hop (previous row); default route stays |

**Takeaway:** the default route masked the real fault. A working path in the data plane can hide a broken control plane, so always check next-hop resolution and CEF, not just the BGP table.

## 8. Repository Structure

```
bgp-lab-01/
├── README.md
├── configs/        # running-config of R1–R4
├── screenshots/    # verification evidence (section 5)
└── pcap/           # bgp-lab-01.pcapng, single capture on the R1–R3 link (section 5)
```

## 9. Interview Talking Points

- Why iBGP needs a full mesh, and two ways to scale it (route reflectors, confederations).
- How a route reflector avoids loops (ORIGINATOR_ID, CLUSTER_LIST).
- Why next hop is unchanged in iBGP and what breaks when it is not reachable.
- Difference between hard and soft reset, and when each is justified.
- How `default-originate` differs from `redistribute` and `network`, and the risk of a blanket default in production.
- How I troubleshot a forwarding problem that was hidden by a default route (BGP table vs RIB vs CEF).

## 10. Conclusion

This lab replaced a full-mesh iBGP design with two route reflectors and achieved complete reachability between four LANs using only BGP features: no IGP, no static routes, no redistribution. The most valuable lessons came from the failures. Next-hop behaviour on reflected routes, the need for a soft reset after policy changes, and a default route masking an unreachable next hop are the kinds of problems that appear in production and in exam troubleshooting scenarios. Verification was done at three levels: control plane (`show ip bgp`), forwarding plane (`show ip cef`, extended ping, traceroute), and packet level (Wireshark captures of OPEN, KEEPALIVE and UPDATE messages).
