# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

import json
import os
import urllib.request


site = os.environ["ERPNEXT_SITE_NAME"]
request = urllib.request.Request(
    "http://127.0.0.1:8000/api/method/ping",
    headers={"Host": site, "X-Frappe-Site-Name": site},
)
with urllib.request.urlopen(request, timeout=4) as response:
    payload = json.load(response)
    if response.status != 200 or payload.get("message") != "pong":
        raise SystemExit(1)
