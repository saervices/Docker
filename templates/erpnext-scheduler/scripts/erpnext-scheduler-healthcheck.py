# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

import os
from pathlib import Path


sites_root = Path("/home/frappe/frappe-bench/sites")
os.chdir(sites_root)
import frappe
from frappe.utils.background_jobs import get_redis_conn
from frappe.utils.scheduler import is_scheduler_inactive


site = os.environ["ERPNEXT_SITE_NAME"]
frappe.init(site, sites_path=str(sites_root))
try:
    frappe.connect()
    frappe.db.sql("SELECT 1")
    if get_redis_conn().ping() is not True or is_scheduler_inactive(verbose=False):
        raise SystemExit(1)
finally:
    frappe.destroy()
