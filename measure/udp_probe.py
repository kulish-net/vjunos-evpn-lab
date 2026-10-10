#!/usr/bin/env python3
"""Measure a forwarding outage with millisecond resolution.

Why not ping: `ping -c 5` has one-second resolution, so an outage shorter
than the interval is invisible and a longer one is quantised to whole
seconds. This sends a paced UDP stream with a sequence number and measures
the gap in arrival times on the receiver, which resolves to ~1 ms.

The rate is deliberately modest: cJunosEvolved is rated for 2000 pps across
all interfaces, so anything near that measures the simulator, not the network.

    receiver:  udp_probe.py recv --bind 10.10.10.2 --port 5000 --json out.json
    sender:    udp_probe.py send --dst 10.10.10.2 --port 5000 --pps 1000 --secs 30
"""
import argparse
import json
import socket
import struct
import sys
import time

HDR = struct.Struct("!Qd")  # sequence number, send timestamp


def send(args):
    """Paced sender.

    The naive version of this slept for a fraction of the interval each
    round and silently delivered ~740 pps instead of 1000: at a 1 ms
    interval the sleep syscall's own overhead is a large part of the
    budget. So sleep only while there is a comfortable margin, then spin.
    The achieved rate is always reported - a measurement tool that lies
    about its own rate is worse than no tool.
    """
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    pad = b"\x00" * max(0, args.size - HDR.size)
    interval = 1.0 / args.pps
    start = time.perf_counter()
    deadline = start + args.secs
    seq = 0
    while True:
        target = start + seq * interval
        now = time.perf_counter()
        if now >= deadline:
            break
        slack = target - now
        if slack > 0.0015:
            time.sleep(slack - 0.0012)
        while time.perf_counter() < target:
            pass
        sock.sendto(HDR.pack(seq, time.time()) + pad, (args.dst, args.port))
        seq += 1
    elapsed = time.perf_counter() - start
    print(
        f"sent {seq} packets in {elapsed:.2f}s = {seq / elapsed:.0f} pps "
        f"(requested {args.pps})",
        file=sys.stderr,
    )


def recv(args):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((args.bind, args.port))

    # Run for a fixed wall clock window. The earlier version stopped after a
    # few idle seconds, which meant it died *during* the very outage it was
    # supposed to measure and never saw traffic resume.
    hard_stop = time.perf_counter() + args.secs
    arrivals = []  # (seq, monotonic arrival)
    while True:
        remaining = hard_stop - time.perf_counter()
        if remaining <= 0:
            break
        sock.settimeout(min(remaining, 1.0))
        try:
            data, _ = sock.recvfrom(2048)
        except socket.timeout:
            continue
        if len(data) < HDR.size:
            continue
        seq, _sent_at = HDR.unpack(data[: HDR.size])
        arrivals.append((seq, time.perf_counter()))

    if not arrivals:
        print(json.dumps({"error": "no packets received"}))
        return

    arrivals.sort()
    seqs = [s for s, _ in arrivals]
    times = [t for _, t in arrivals]
    expected = seqs[-1] - seqs[0] + 1
    received = len(arrivals)
    lost = expected - received

    # The outage is the largest gap between two consecutive arrivals. The
    # nominal inter-packet interval is subtracted so an idle gap of one
    # interval does not read as an outage.
    nominal = 1.0 / args.pps
    gaps = sorted(
        ((times[i + 1] - times[i], seqs[i], seqs[i + 1]) for i in range(len(times) - 1)),
        reverse=True,
    )
    worst = gaps[0] if gaps else (0.0, 0, 0)
    second = gaps[1] if len(gaps) > 1 else (0.0, 0, 0)
    outage_ms = max(0.0, worst[0] - nominal) * 1000.0

    result = {
        "received": received,
        "expected": expected,
        "lost": lost,
        "loss_pct": round(100.0 * lost / expected, 3) if expected else 0.0,
        "outage_ms": round(outage_ms, 1),
        "gap_between_seq": [worst[1], worst[2]],
        # the runner-up gap separates a real outage from a scheduling hiccup
        "second_gap_ms": round(max(0.0, second[0] - nominal) * 1000.0, 1),
        "first_seq": seqs[0],
        "last_seq": seqs[-1],
        "pps": args.pps,
    }
    print(json.dumps(result))
    if args.json:
        with open(args.json, "w") as fh:
            json.dump(result, fh)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="mode", required=True)

    s = sub.add_parser("send")
    s.add_argument("--dst", required=True)
    s.add_argument("--port", type=int, default=5000)
    s.add_argument("--pps", type=int, default=1000)
    s.add_argument("--secs", type=float, default=30)
    s.add_argument("--size", type=int, default=64)
    s.set_defaults(func=send)

    r = sub.add_parser("recv")
    r.add_argument("--bind", default="0.0.0.0")
    r.add_argument("--port", type=int, default=5000)
    r.add_argument("--pps", type=int, default=1000)
    r.add_argument("--secs", type=float, default=60, help="fixed capture window; must outlast the outage")
    r.add_argument("--json", default=None)
    r.set_defaults(func=recv)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
