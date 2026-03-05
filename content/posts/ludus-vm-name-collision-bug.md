---
title: How Jinja2's match Silently Broke My Ludus Lab
date: 2026-03-05
draft: false
tags:
  - ludus
  - ansible
  - proxmox
  - debugging
  - jinja2
---

## The Symptom

After adding a second Windows VM (`DF-windows-jump` on VLAN 20) alongside the existing `DF-windows` (VLAN 22) in my PivotLab range config, `DF-windows` kept ending up with `DF-windows-jump`'s IP address. Every deploy, `ludus range status` would initially show the correct DHCP IP for `DF-windows`, then it would silently flip to `10.2.20.221` -- the static IP belonging to `DF-windows-jump`.

The hostname never changed. The static IP (`10.2.22.60`) was never applied. Deleting and redeploying didn't help. Changing templates (win2019 to win2022) didn't help. The collision persisted across every combination I tried.

## The Investigation

I initially suspected the Proxmox dynamic inventory script (`proxmox.py`), since it resolves which IP Ansible uses for each VM. I spent time analyzing `check_ip_addresses()`, considering `force_ip` behavior, DHCP cross-talk, qemu-guest-agent bugs, and Proxmox API issues. None of these panned out.

I instrumented `proxmox.py` with debug logging in `check_ip_addresses()` and `qemu_agent_info()` to trace exactly what IPs the Proxmox agent reported per VMID, and what the inventory script returned. The debug output revealed something critical:

- **First inventory run** (during deploy): VMID 112 (`DF-windows`) correctly reported DHCP IP `10.2.22.206` on VLAN 22.
- **Second inventory run** (after configure-ip phase): VMID 112 now reported `10.2.20.221` -- `DF-windows-jump`'s IP.

The agent was queried by VMID. The Proxmox API returned the right VM. The IP was genuinely set on the wrong VM's network interface. Something in the configure-ip phase had set the wrong static IP on `DF-windows`.

## The Root Cause

The bug is in `ludus.yml` -- the main Ansible playbook that orchestrates Ludus deployments. During the "Configure IP and Hostname" phase, every VM's static IP, gateway, hostname, and DNS server are resolved using Jinja2 expressions like:

```yaml
static_ip: "10.{{ range_second_octet }}.{{ vlan }}.{{ (ludus | selectattr('vm_name', 'match', inventory_hostname) | first).ip_last_octet }}"
```

The problem is `selectattr('vm_name', 'match', inventory_hostname)`. Jinja2's `match` test is a **regex prefix match** -- it checks if the string *starts with* the pattern, not whether it's an exact match. From the [Ansible docs](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_tests.html#testing-strings):

> `match` succeeds if it finds the pattern at the beginning of the string.

So when `inventory_hostname` is `DF-windows`, the filter `selectattr('vm_name', 'match', 'DF-windows')` matches **both**:
- `DF-windows-jump` (starts with "DF-windows")
- `DF-windows` (exact match)

The `| first` filter then returns whichever appears first in the range config. In my case, `DF-windows-jump` was listed before `DF-windows`, so every variable lookup for `DF-windows` silently returned `DF-windows-jump`'s config:

| Variable | Expected (DF-windows) | Actual (from DF-windows-jump) |
|---|---|---|
| `vlan` | 22 | 20 |
| `ip_last_octet` | 60 | 221 |
| `static_ip` | 10.2.22.60 | 10.2.20.221 |
| `default_gateway` | 10.2.22.254 | 10.2.20.254 |
| `hostname` | DF-windows | DF-windows-jump |

This pattern appears **56 times** throughout `ludus.yml`, affecting static IPs, gateways, hostnames, DNS, domain joins, autologon, chocolatey packages, user roles, role variables -- essentially every per-VM configuration lookup.

## Why It Was So Hard to Find

Several factors made this bug deceptive:

1. **`proxmox.py` was innocent.** It uses `==` for exact comparison, so the inventory script itself correctly identifies VMs. The bug only manifests during Ansible playbook execution.
2. **The collision looks like a Proxmox/agent bug.** The qemu-guest-agent genuinely reports the wrong IP, because the wrong IP was actually configured on the VM. Without instrumentation, you'd reasonably suspect the Proxmox API.
3. **It's order-dependent.** If the shorter name happened to appear first in the range config, `| first` would return the correct entry and the bug would be invisible.
4. **Template changes don't help.** I tried different Windows versions, different templates -- none of it matters because the bug is in the Ansible variable resolution, not in VM cloning or OS identity.
5. **The async fire-and-forget pattern masks the error.** The static IP task runs asynchronously and the connection drops (as expected when changing a NIC's IP). The subsequent "wait for network" task succeeds because the wrong IP *does* come up -- it's just on a different VM.

## The Fix

Replace `'match'` with `'equalto'` in all 56 `selectattr` calls that compare `vm_name` to `inventory_hostname`:

```diff
- vlan: "{{ (ludus | selectattr('vm_name', 'match', inventory_hostname) | first).vlan }}"
+ vlan: "{{ (ludus | selectattr('vm_name', 'equalto', inventory_hostname) | first).vlan }}"
```

The 4 remaining `match` instances on `domain.fqdn` and `domain.role` fields are legitimate regex uses and don't need changing.

## Upstream Issue

Filed as [badsectorlabs/ludus#122](https://gitlab.com/badsectorlabs/ludus/-/issues/122) on GitLab.

## Workarounds (Before the Fix)

If you can't patch `ludus.yml`, avoid having one VM name be a prefix of another:

- Rename `DF-windows` to `DF-wintarget`
- Or reorder the range config so the shorter name appears first (fragile, not recommended)
- Or deploy the VMs in separate passes (slow but works)
