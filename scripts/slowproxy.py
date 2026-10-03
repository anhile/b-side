#!/usr/bin/env python3
"""An HTTP CONNECT proxy that makes the network bad on purpose.

  slowproxy.py PORT [--latency S] [--rate KBPS] [--stall-after S] [--refuse-after S] [--fail-hosts a,b]

--latency      extra delay before each tunnel opens (and before the first bytes)
--rate         bytes per second cap, per direction, per tunnel (KB/s)
--stall-after  after this many seconds since start, tunnels stay open but pass nothing
--refuse-after after this many seconds since start, new tunnels are refused
--fail-hosts   hosts (suffix match) whose tunnels are refused
"""
import argparse, asyncio, sys, time

START = time.monotonic()
ARGS = None
LOG = sys.stderr


def since():
    return time.monotonic() - START


async def pump(reader, writer, rate):
    try:
        while True:
            if ARGS.stall_after and since() > ARGS.stall_after:
                await asyncio.sleep(3600)
            chunk = await reader.read(16384 if not rate else max(512, int(rate / 4)))
            if not chunk:
                break
            writer.write(chunk)
            await writer.drain()
            if rate:
                await asyncio.sleep(len(chunk) / rate)
    except (ConnectionError, asyncio.CancelledError, OSError):
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def handle(reader, writer):
    try:
        line = await reader.readline()
        parts = line.decode(errors="replace").split()
        while True:
            header = await reader.readline()
            if header in (b"\r\n", b"\n", b""):
                break
        if len(parts) < 2 or parts[0] != "CONNECT":
            writer.write(b"HTTP/1.1 405 Method Not Allowed\r\n\r\n")
            await writer.drain(); writer.close(); return
        host, _, port = parts[1].rpartition(":")
        refused = (ARGS.refuse_after and since() > ARGS.refuse_after) or any(host.endswith(h) for h in ARGS.fail_hosts)
        print(f"{since():7.1f}s CONNECT {host}:{port}" + ("  REFUSED" if refused else ""), file=LOG, flush=True)
        if refused:
            writer.close(); return
        if ARGS.latency:
            await asyncio.sleep(ARGS.latency)
        try:
            up_reader, up_writer = await asyncio.wait_for(asyncio.open_connection(host, int(port)), 20)
        except Exception as e:
            print(f"{since():7.1f}s  upstream failed {host}: {e}", file=LOG, flush=True)
            writer.write(b"HTTP/1.1 502 Bad Gateway\r\n\r\n"); await writer.drain(); writer.close(); return
        writer.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
        await writer.drain()
        rate = ARGS.rate * 1024 if ARGS.rate else 0
        await asyncio.gather(pump(reader, up_writer, rate), pump(up_reader, writer, rate))
    except Exception as e:
        print(f"{since():7.1f}s  error {e}", file=LOG, flush=True)
        try:
            writer.close()
        except Exception:
            pass


async def main():
    server = await asyncio.start_server(handle, "127.0.0.1", ARGS.port)
    print(f"slowproxy on 127.0.0.1:{ARGS.port} latency={ARGS.latency}s rate={ARGS.rate}KB/s stall_after={ARGS.stall_after} refuse_after={ARGS.refuse_after} fail_hosts={ARGS.fail_hosts}", file=LOG, flush=True)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("port", type=int)
    p.add_argument("--latency", type=float, default=0)
    p.add_argument("--rate", type=float, default=0)
    p.add_argument("--stall-after", type=float, default=0)
    p.add_argument("--refuse-after", type=float, default=0)
    p.add_argument("--fail-hosts", type=lambda s: [h for h in s.split(",") if h], default=[])
    ARGS = p.parse_args()
    asyncio.run(main())
