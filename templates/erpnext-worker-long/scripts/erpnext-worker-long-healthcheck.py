# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

import os
import re
import socket
from pathlib import Path


sites_root = Path("/home/frappe/frappe-bench/sites")
os.chdir(sites_root)
import frappe
from frappe.utils.background_jobs import generate_qname, get_redis_conn, get_workers


def is_live_local_worker(worker):
    pid = getattr(worker, "pid", None)
    if worker.hostname != local_hostname or not isinstance(pid, int) or pid <= 1:
        return False
    try:
        process_argv = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
        process_state = Path(f"/proc/{pid}/stat").read_text(encoding="ascii").rsplit(") ", 1)[1][0]
    except (FileNotFoundError, PermissionError, ProcessLookupError, TypeError, IndexError):
        return False
    return b"worker-pool" in process_argv and process_state in {"R", "S", "D", "I"}


site = os.environ["ERPNEXT_SITE_NAME"]
local_hostname = socket.gethostname()
worker_count_value = os.environ.get("ERPNEXT_WORKER_LONG_PROCESSES", "")
if not re.fullmatch(r"[1-9][0-9]*", worker_count_value):
    raise SystemExit(1)
expected_worker_count = int(worker_count_value)
if expected_worker_count > 32:
    raise SystemExit(1)
frappe.init(site, sites_path=str(sites_root))
try:
    connection = get_redis_conn()
    if connection.ping() is not True:
        raise SystemExit(1)
    expected = {
        generate_qname("long"),
        generate_qname("default"),
        generate_qname("short"),
    }
    healthy_workers = 0
    for worker in get_workers():
        state = worker.get_state()
        state_name = str(getattr(state, "value", state)).lower()
        if (
            is_live_local_worker(worker)
            and expected == {queue.name for queue in worker.queues}
            and state_name in {"idle", "busy", "started"}
        ):
            healthy_workers += 1
    raise SystemExit(0 if healthy_workers >= expected_worker_count else 1)
finally:
    frappe.destroy()
