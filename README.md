# vjunos-evpn-lab

A reproducible **EVPN-VXLAN fabric on free Junos lab images**, built with
containerlab — and, more to the point, an honest measurement of how long
traffic is black-holed when a leaf dies.

Every EVPN-VXLAN tutorial ends at `show evpn database` with the MACs present
and the words "the fabric is up". None of them answer the only question that
matters in production: *how many milliseconds of traffic are lost on failure,
and what actually determines that number?*

Spoiler: not the VXLAN data plane. BGP timers and BFD.

## Topology

```
                      ┌─────────────────┐
                      │     spine1      │   AS 65100
                      └────┬───────┬────┘
                  eBGP     │       │     eBGP
              underlay     │       │     underlay
                      ┌────┴───┐ ┌─┴──────┐
                      │ leaf1  │ │ leaf2  │  AS 65101 / 65102
                      └────┬───┘ └───┬────┘
                           │         │
                        ┌──┴──┐   ┌──┴──┐
                        │ h1  │   │ h2  │     VLAN 10 -> VNI 10010
                        └─────┘   └─────┘
```

Underlay: eBGP, one ASN per node. Overlay: MP-BGP EVPN, VXLAN data plane,
one VNI per VLAN. Hosts are plain Alpine containers.

## Which image, and why it matters

Juniper publishes several free lab images, and they are **not**
interchangeable for this setup:

- **`vJunos-switch` does not work here.** Its requirements specify Intel VT-x
  and state it is *not supported on EVE-NG or any other deployments that launch
  vJunos from within a VM due to the constraints of deeply nested
  virtualization*. It inherits the vMX architecture — VCP and VFP are already
  nested inside the VM — so a third nesting layer is out. Any WSL2 or
  VM-on-VM host is ruled out by design, not by resources.
- **`cJunosEvolved` (25.2R1) is the one to use.** Its requirements allow
  *any x86 processor (Intel or AMD)* and name containerlab as a supported
  deployment. The cost is 8 GB per node instead of 5.

Both are free, with no licence and no time limit, for non-production lab use
only. They cannot be found through the site's product search — Juniper
publishes direct links on its vJunos Labs page.

## Requirements

- Docker Engine **28.0.0 or newer** — Juniper's own guide warns that earlier
  versions attach interfaces out of order, which silently breaks traffic
  between connected containers
- Ubuntu 22.04 / 24.04, qemu-kvm, and `/dev/kvm` present (`kvm-ok`)
- 8 GB RAM and 4 cores per node; 20 GB of disk per container at runtime,
  growing to 40 GB
- containerlab
- The cJunosEvolved image — free, account required, **not** redistributed here

Host used for this lab: Windows 11 + WSL2 on an AMD Ryzen 5600X. `/dev/kvm` is
exposed inside WSL2 and the `svm` flag reaches the guest. Most guides assume
bare-metal Linux on Intel.

## What this lab demonstrates

- EVPN-VXLAN control plane: type-2 MAC advertisement and withdrawal
- the difference between a graceful shutdown, a link failure and a hard node
  kill, as measured at the data plane
- why BFD is a precondition rather than a tuning option: with default BGP
  timers a hard node failure leaves a 90-second hold-time window
- a measurement method with 1 ms resolution, instead of `ping -c 5`

## Measurement method

Convergence is measured with a UDP stream at 1000 pps carrying a sequence
number; the receiver counts the gap in the sequence and converts it to an
outage in milliseconds. Each scenario is run ten times and reported as median
and maximum — not as the best run. Scripts live in `measure/`.

## Status

Working. Two leaves back to back with EVPN-VXLAN: BGP up, type-2/type-3
exchanged, host-to-host ping across the tunnel at 0% loss. See
`docs/ru/stend-fakty.md` for the full build log in Russian.

Done:

- [x] cJunosEvolved 26.2R1.7-EVO pinned, kind `juniper_cjunosevolved`
- [x] WSL2 on AMD confirmed as a host: `/dev/kvm` present, nested virt works
- [x] Docker 29.9.0, containerlab 0.80.0
- [x] Two-leaf EVPN-VXLAN fabric forwarding end to end

Open:

- [ ] Add a spine (8 GB more) or stay back-to-back
- [ ] Measurement harness: UDP stream with sequence numbers, 1 ms resolution,
      capped at ~1000 pps because the simulator is rated for 2000 pps
- [ ] BFD: the platform lists aggressive sub-second timers as unsupported,
      so the planned timer matrix needs rethinking
- [ ] Whether the WSL2 kernel ships `bonding` (decides ESI-LAG stage)
- [ ] English setup walkthrough

## License

MIT
