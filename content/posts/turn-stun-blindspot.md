---
title: "TURNt, STUN, and the New Blind Spot in Trusted Collaboration Traffic"
date: 2026-06-25
draft: false
tags:
  - turn
  - stun
  - webrtc
  - teams
  - zoom
  - paloalto
  - fortinet
  - ransomware
  - redteam
  - detection
  - c2
description: "STUN and TURN make Teams, Zoom, Twilio, and other RTC platforms work through NAT, but broad trusted relay egress can become a C2 blind spot for defenders."
---
![TURNt, STUN, and trusted collaboration traffic blind spot banner](/images/posts/turn-stun-blindspot/turn_down_for_what.png)

**What if your trusted collaboration traffic is also a C2 blind spot?**

Collaboration traffic has long been one of those firewall exceptions everyone understands. Users need calls to work. UDP has to get out. Vendor ranges change. TLS inspection breaks things. So the rule gets written, the proxy bypass goes in, and the traffic becomes trusted.

That trust is the problem.

In 2020, many firewall teams had to make Zoom, Teams, Twilio-backed apps, and other RTC platforms work almost overnight. The early security concern was operational: large destination ranges, UDP media paths, NAT traversal, and call quality. Business continuity won, and in many environments broad collaboration egress became normal.

The uncomfortable part is that one of those trusted traffic classes is now part of the attack surface.

In June 2026, [Symantec reported](https://www.security.com/threat-intelligence/dragonforce-msteams-backdoor) on **Backdoor.Turn**, a custom Go-based RAT used by DragonForce during an intrusion at a major U.S. services company. [BleepingComputer covered the same case](https://www.bleepingcomputer.com/news/security/ransomware-gang-abuses-microsoft-teams-relays-to-hide-malicious-traffic/).

The notable tradecraft was not a strange destination or a brand-new protocol. It was Teams-associated relay infrastructure helping mask command-and-control setup and traffic patterns that many environments already permit.

Symantec reported that Backdoor.Turn obtains an anonymous Teams visitor token and uses Microsoft’s TURN relay infrastructure during initial connection setup. It then establishes a QUIC session to attacker-controlled infrastructure for command and control.

The intrusion began in December 2025. The broader DragonForce activity included the typical pre-ransomware work: persistence, bring-your-own-vulnerable-driver activity, credential access, LDAP and Active Directory reconnaissance, lateral movement, staging, and exfiltration.

The important part isn’t the custom backdoor. It’s that the traffic is something most enterprises already trust.

## STUN/TURN in Plain English

STUN, or Session Traversal Utilities for NAT, helps a client discover how it appears from the public internet side of NAT. TURN, or Traversal Using Relays around NAT, goes further: when direct connectivity fails, a relay server forwards traffic between peers.

[RFC 8489](https://www.rfc-editor.org/rfc/rfc8489.html) defines STUN as a NAT traversal utility used by ICE, WebRTC, SIP, and related protocols. [RFC 8656](https://www.rfc-editor.org/rfc/rfc8656.html) describes TURN as a relay protocol for hosts behind NATs that cannot communicate directly. TURN is built to get traffic out when direct paths do not work.

## Why This Became a C2 Problem

These collaboration tools are attractive paths for covert communications because they are encrypted, commonly exempt from proxy and TLS inspection, frequently split-tunneled, and broadly available to employees.

The vendor guidance explains why this traffic so often gets broad treatment:

- Microsoft’s [Microsoft 365 endpoint guidance](https://learn.microsoft.com/en-us/microsoft-365/enterprise/urls-and-ip-address-ranges?view=o365-worldwide) lists Teams media requirements including UDP 3478-3481, UDP 443, and TCP 443/80 to Teams domains and IP ranges. Microsoft’s [Teams proxy guidance](https://learn.microsoft.com/en-us/microsoftteams/proxy-servers-for-skype-for-business-online) also recommends bypassing proxy infrastructure and SSL inspection for Teams traffic where possible because media is already encrypted and proxies can hurt quality.
- [Zoom’s network firewall guidance](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0060548) documents outbound TCP 443/8801/8802 and UDP 3478, 3479, 8801-8810 for meetings and webinars.
- Twilio’s [Network Traversal Service](https://www.twilio.com/docs/stun-turn) documentation includes TURN over TCP 443 and TCP/UDP 3478, and its [IP/port documentation](https://www.twilio.com/docs/stun-turn/regions) includes TCP 5349 and ephemeral relay UDP ports.

## The Red Side: TURNt, Ghost Calls, and Relay Abuse

Praetorian’s [Ghost Calls research](https://www.praetorian.com/blog/ghost-calls-abusing-web-conferencing-for-covert-command-control-part-2-of-2/) explains the red-team idea clearly: obtain temporary TURN credentials from a conferencing platform, use WebRTC to establish a relayed path, then run SOCKS and port-forwarding through trusted infrastructure. Their work on Zoom and Microsoft Teams became the [TURNt](https://github.com/praetorian-inc/turnt) tool.

TURNt gives operators an interactive SOCKS and port-forwarding channel over infrastructure most environments are reluctant to block. It is most useful as a **secondary, high-interaction lane** — not necessarily the primary long-term implant, but the channel turned on when an operator needs to browse internal applications, proxy tools, move data, or work around a slow primary C2 path. Globally distributed TURN infrastructure also makes blunt blocking difficult without breaking legitimate collaboration traffic.

## What an Attacker Actually Needs

Practically, TURN abuse needs a few conditions to line up. There are two related modes to separate: provider relay C2 smuggling, like Ghost Calls/TURNt, and misconfigured TURN pivoting, like open relay or permissive coturn abuse. Credentials matter for both. Arbitrary peer reachability matters most for pivoting.

| Step | What they need | Difficulty |
|---|---|---|
| 1 | Reachable TURN server and port | Easy |
| 2 | Working credentials | Medium to hard |
| 3 | Relay can reach useful peers | Often the failure point |
| 4 | Foothold + signaling path | Required |
| 5 | Tooling & knowledge | Easy |

Discovery can come from Shodan/Censys-style searches, internal recon after compromise, or simply watching what the real application already does. In WebRTC apps, the interesting strings are often obvious: `iceServers`, `stun:`, `turn:`, `turns:`, realms, usernames, and credential fields.

Credentials are the first real gate. Without them, tools usually hit a `401 Unauthorized` and stop. That gate weakens when credentials are delivered to clients, stored too long, leaked via REST secrets, or issued by weak coturn deployments.

Peer policy decides the blast radius. A TURN server that only relays between intended media peers is a strong defense. A TURN server that lets an authenticated user pick arbitrary peer addresses becomes a proxy.

## The Blue Side: What Defenders Actually See

From the firewall’s perspective, traffic to these collaboration and TURN services usually looks fairly ordinary. The logs typically show a known source user and source host, a destination that resolves to Microsoft, Zoom, Twilio, or another approved RTC provider, and standard ports and protocols. Session duration, bytes transferred in and out, and any available application signatures generally appear consistent with normal meeting or media traffic.

The problem is that this network-level visibility stops at the destination and protocol. The firewall sees traffic going to a trusted provider over an allowed port, but it has limited visibility into which process on the endpoint is making the connection.

## Policy Matrix: Teams Is Not Special

Teams is the current headline, but the same risk class applies to any RTC provider or self-hosted relay that hands clients ICE/TURN details.

Use a policy matrix to force ownership before arguing about tools:

| Provider | Who needs it? | From where? | Ports/protocols | Detection notes |
|---|---|---|---|---|
| Teams media/TURN | All users? Call-center only? | Managed workstations only | Microsoft-published ranges; commonly UDP 3478-3481, UDP 443, TCP 443/80 | Alert on non-Teams process and no meeting context |
| Zoom media/TURN | Licensed Zoom users | Managed endpoints, conference rooms | Zoom-published meeting ports; commonly UDP 3478/3479/8801-8810 and TCP 443/8801/8802 | Alert on TCP fallback spikes and unusual long sessions |
| Twilio TURN | Approved apps only | App servers or approved client groups | TCP 443, TCP/UDP 3478, TCP 5349, relay UDP ranges | Alert when random workstations use Twilio TURN |
| Vonage / Agora / embedded RTC | Specific business app users | Only app-using groups | Vendor-published ICE/TURN ports | Ask for credential TTL and peer restrictions |
| Self-hosted coturn | Internal apps | Required app subnets only | Your own TURN config | Deny private/link-local/metadata peers; log allocations |
| Unknown STUN/TURN | Nobody by default | Nowhere by default | UDP/TCP 3478, TCP 5349, suspicious UDP 443 | Block or monitor during discovery |

This forces the right review: are credentials scoped, are peer targets restricted, and can your firewall distinguish the authorized app from an arbitrary process using the same relay path?

If nobody truly owns a TURN allow firewall rule, attackers will.

## Firewall Engineer Playbook: Palo Alto and Fortinet

The weak version is simple: broad RTC allow rules, blanket no-decrypt exceptions, no explicit deny for unknown STUN/TURN, and no endpoint correlation. That design works for meetings. It also works for malware.

The better pattern is boring: approved users, managed devices, sanctioned apps, approved relay destinations, required ports only, security profiles attached, and explicit deny/log rules for everything else.

| Control | What to do |
|---|---|
| Separate RTC from web | Teams/Zoom web traffic is not the same as media or TURN relay traffic. Use dedicated policies. |
| Scope egress | Restrict by user group, managed device, source subnet, destination/FQDN/EDL/ISDB object, and required service. Do not allow from servers or admin hosts by default. |
| Inspect deliberately | Decrypt where feasible, but do not assume outer TLS inspection reveals WebRTC/DTLS/SRTP. Keep no-decrypt exceptions narrow and documented. |
| Control relay ports | Explicitly allow only required UDP/TCP 3478, TCP 5349, UDP 443/QUIC, and TCP 443 paths. Block and log the rest. |
| Keep profiles on | Attach C2/Anti-Spyware, IPS/Vuln Protection, WildFire/sandboxing, DNS security/filtering, URL/Web Filter, AV/File Blocking where practical. |
| Correlate endpoint | Alert when non-Teams, non-Zoom, or non-browser processes use approved RTC relay paths. |

**Palo Alto**: Use App-ID, User-ID/device context, EDL/FQDN objects, URL categories, `application-default` where feasible, and security profiles on allow rules. [SSL Forward Proxy](https://docs.paloaltonetworks.com/network-security/decryption/administration/enabling-decryption/configure-ssl-forward-proxy) helps with outbound encrypted traffic, but it is not a magic decoder for inner WebRTC media.

**FortiGate**: Use firewall policy with destination/FQDN/Internet Service Database objects, [Application Control](https://docs.fortinet.com/document/fortigate/7.6.0/administration-guide/302748/application-control), [SSL/SSH Inspection](https://docs.fortinet.com/document/fortigate/7.6.0/administration-guide/929997/ssl-ssh-inspection), [DNS Filter](https://docs.fortinet.com/document/fortigate/7.6.0/administration-guide/605868/dns-filter), Web Filter, IPS/AV, and FortiAnalyzer/FortiSIEM correlation. Validate app names and signatures in the [FortiGuard Application Control encyclopedia](https://www.fortiguard.com/appcontrol). Certificate inspection gives TLS-layer visibility; deep inspection may break RTC, so keep exceptions narrow instead of creating a giant “no-inspection for all collaboration” hole.

Do not let either platform become a rubber stamp for “allow Teams/Zoom/Twilio.” The useful rule is closer to: allow this user group on managed workstations to these specific RTC destinations and ports, with inspection, logging, DNS/web controls, IPS, and endpoint correlation.

## What to Detect

Network logs alone are not enough. You need correlation across firewall, DNS, proxy, EDR, identity, and collaboration telemetry.

| Signal | Why it matters |
|---|---|
| Non-Teams process connects to Teams relay infrastructure | Process mismatch. The destination may be legitimate; the process is not. |
| Non-Zoom process connects to Zoom media/TURN infrastructure | Same idea, different provider. |
| Browser or unknown binary talks to Twilio TURN outside an approved app flow | Possible shadow RTC or covert relay usage. |
| TURN/STUN traffic from server, admin, or unmanaged hosts | Bad egress scope. These systems usually should not need meeting relays. |
| Long-lived TCP/TLS TURN sessions | TCP fallback can be normal, but sustained interactive tunnels deserve review. |
| High upload volume to RTC relay destinations | Exfil can hide behind meeting-like traffic patterns. |
| Relay traffic after BYOVD, credential dumping, LDAP/AD enumeration, RDP, SMB, or internal scanning | Ransomware-chain correlation. |
| Local SOCKS listener or unusual port-forwarding process before relay traffic | Strong operator-behavior signal. |
| Relay allocation without meeting/call/session context | Session legitimacy failure. |

For a ransomware simulation, this is the test: can the SOC tell the difference between a real meeting and an interactive tunnel hiding behind meeting infrastructure? If that question cannot be answered with telemetry, the exercise is not mature enough yet.

## How to Test This Safely

Do not start by throwing offensive tooling at production meeting infrastructure. Do not test third-party conferencing providers outside explicit authorization; validate detection with approved lab infrastructure or scoped purple-team activity.

Use a ladder:

1. **Inventory** allowed RTC/collaboration providers, ports, subnets, TLS/proxy bypasses, and split-tunnel exceptions.
2. **Baseline** normal Teams/Zoom/Twilio/Vonage/Agora relay usage by user group, subnet, process, destination, duration, transport, and byte count.
3. **Validate benignly** with Trickle ICE, Nmap NSE scripts where authorized, and coturn utilities for lab or owned infrastructure.
4. **Audit** owned TURN for authentication, short-lived credentials, peer restrictions, allocation logging, and denial of private, loopback, link-local, multicast, reserved, and metadata ranges.
5. **Simulate in scope** with Stunner, StunCheck, or TURNt only after pre-coordination. Capture Palo Alto/FortiGate logs, DNS, proxy, EDR, and SIEM alerts. Measure whether detection fires on destination, process, behavior, and session context.

That gives you a clean path: **Inventory → Baseline → Validate → Audit → Simulate**.

## Tooling Worth Knowing

Use these only in authorized environments.

| Tool | Best use | Why it matters |
|---|---|---|
| [TURNt](https://github.com/praetorian-inc/turnt) | Covert WebRTC relay tunneling through trusted providers | Models Ghost Calls-style C2 over Teams/Zoom-like infrastructure. |
| [Stunner](https://github.com/firefart/stunner) | TURN/STUN exploitation and relay abuse testing | Tests STUN, TURN, TURN-over-TCP, and misconfigured relay pivoting. |
| [StunCheck](https://github.com/Pepelux/stuncheck) | Python toolkit for scanning and testing TURN/STUN | Useful for discovery, login testing, transport testing, SOCKS proxying, IP scanning, and port scanning through relays. |
| [coturn turnutils](https://raw.githubusercontent.com/coturn/coturn/master/README.turnutils) | Baseline validation and load/testing utilities | Good for lab servers and owned infrastructure. |
| [Trickle ICE](https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/) | Quick browser validation of ICE server configs | Shows `srflx` candidates for STUN and `relay` candidates for TURN. |
| [Nmap stun-info](https://nmap.org/nsedoc/scripts/stun-info.html) / [stun-version](https://nmap.org/nsedoc/scripts/stun-version.html) | Lightweight recon | Useful for identifying STUN services during authorized inventory. |

Additional references worth knowing: [Turner](https://github.com/staaldraad/turner), [turnproxy](https://github.com/trichimtrich/turnproxy), and [Enable Security’s awesome-rtc-hacking](https://github.com/EnableSecurity/awesome-rtc-hacking) list. The standout historical case is Enable Security’s [Slack TURN research](https://www.enablesecurity.com/blog/slack-webrtc-turn-compromise-and-bug-bounty/), which showed Slack’s TURN servers could be abused to relay traffic to internal Slack network and AWS metadata services. That report predates Ghost Calls and Backdoor.Turn, but it explains the same core issue: a TURN server can become an open proxy if peer restrictions are wrong.

The theme is simple: if a relay accepts your credentials and lets you choose dangerous peers, it becomes a pivot.

## Vendor Questions

If a SaaS platform needs TURN/STUN access through your Palo Alto or FortiGate firewalls, ask more than “what domains do we whitelist?”

Start with these:

- Which exact features require TURN/STUN?
- Which RTC provider is used underneath?
- Are ICE/TURN credentials delivered to the client?
- What is the credential TTL?
- Are credentials bound to tenant, user, device, meeting, session, or peer?
- Can TURN relays connect to arbitrary peers?
- Are private, loopback, link-local, metadata, multicast, and reserved ranges blocked?
- Can customers get logs for relay allocation, duration, peer targets, and byte counts?
- What is the recommended firewall policy if we want to allow the app but block generic STUN/TURN?
- Does the vendor control the relay infrastructure directly, or is it shared through an underlying RTC, CDN, or cloud provider?

If the vendor cannot answer those questions, the firewall exception should not be broad.

## The Takeaway

TURN and STUN are not the enemy.  
**Blind trust is.**

Teams, Zoom, Twilio, Vonage, Agora, and every other RTC provider exist because modern networks are hostile to real-time media. NAT breaks things. Firewalls break things. Proxies break things. TURN fixes that by relaying traffic through infrastructure everyone agrees to trust.

That trust is now part of the attack surface.

DragonForce and Backdoor.Turn moved this from a red-team research concern into actual ransomware tradecraft. Praetorian’s TURNt shows how an operator can turn the same class of infrastructure into SOCKS and port-forwards. Stunner, StunCheck, coturn utilities, Trickle ICE, and Nmap give defenders and authorized testers ways to measure the exposure.

The defensive answer is not panic.  
It is precision.

Allow the business tools that need to work. But scope them tightly. Log them aggressively. Correlate them with endpoint process data and real user sessions. Deny everyone else. Then test it like a ransomware operator would.

Because if your firewall cannot tell the difference between a Teams call and a tunnel, an attacker does not need to bypass your egress policy.

**They just need to look like the meeting you already allowed.**
