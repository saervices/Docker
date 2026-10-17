#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

set -eu

bench_root=/home/frappe/frappe-bench
app_name=saervices_erpnext_sso_guard
app_root="${bench_root}/apps/${app_name}"
canonical_apps_file=/usr/local/share/saervices-erpnext-apps.txt
runtime_manifest=/usr/local/share/saervices-erpnext-runtime-manifest

if [ ! -d "${app_root}/${app_name}" ] || [ -L "${app_root}" ]; then
  echo "ERPNext SSO guard source is missing or unsafe" >&2
  exit 1
fi
site_packages=$("${bench_root}/env/bin/python" -c 'import site; print(site.getsitepackages()[0])')
if [ ! -d "${site_packages}" ] || [ -L "${site_packages}" ]; then
  echo "Frappe site-packages path is missing or unsafe" >&2
  exit 1
fi

printf '%s\n' "${app_root}" > "${site_packages}/${app_name}.pth"
chown frappe:0 "${site_packages}/${app_name}.pth"
chmod 0644 "${site_packages}/${app_name}.pth"
"${bench_root}/env/bin/python" -c '
from pathlib import Path
from saervices_erpnext_sso_guard.runtime_manifest import canonical_apps_payload
payload = canonical_apps_payload()
Path("/usr/local/share/saervices-erpnext-apps.txt").write_bytes(payload)
Path("/home/frappe/frappe-bench/sites/apps.txt").write_bytes(payload)
'
chown root:root "${canonical_apps_file}"
chmod 0644 "${canonical_apps_file}"
chown frappe:0 "${bench_root}/sites/apps.txt"
chmod 0644 "${bench_root}/sites/apps.txt"

"${bench_root}/env/bin/python" -c \
  'from pathlib import Path; from saervices_erpnext_sso_guard import __version__; from saervices_erpnext_sso_guard.api_auth import AUTH_HOOK, BEFORE_LOGIN_HOOK, OAUTH_CREDENTIAL_DOCTYPES, OAUTH_CREDENTIAL_HAS_PERMISSION_HOOK, OAUTH_CREDENTIAL_QUERY_CONDITION_HOOK, REPORT_MUTATION_HOOK; from saervices_erpnext_sso_guard.hooks import auth_hooks, before_login, doc_events, extend_doctype_class, has_permission, override_whitelisted_methods, permission_query_conditions; from saervices_erpnext_sso_guard.runtime_manifest import CANONICAL_APPS, EXPECTED_APPS, MANIFEST_SCHEMA, canonical_apps_payload; from saervices_erpnext_sso_guard.user_document import SOCIAL_LOGIN_KEY_MUTATION_HOOK, USER_BEFORE_VALIDATE_HOOK, USER_CONTROLLER_EXTENSION; assert __version__ == "1"; assert MANIFEST_SCHEMA == 1; assert EXPECTED_APPS == frozenset(CANONICAL_APPS); assert Path("/usr/local/share/saervices-erpnext-apps.txt").read_bytes() == canonical_apps_payload(); assert auth_hooks == [AUTH_HOOK]; assert before_login == [BEFORE_LOGIN_HOOK]; assert has_permission == {doctype: OAUTH_CREDENTIAL_HAS_PERMISSION_HOOK for doctype in OAUTH_CREDENTIAL_DOCTYPES}; assert permission_query_conditions == {doctype: OAUTH_CREDENTIAL_QUERY_CONDITION_HOOK for doctype in OAUTH_CREDENTIAL_DOCTYPES}; assert doc_events == {"User": {"before_validate": USER_BEFORE_VALIDATE_HOOK}, "Social Login Key": {"before_validate": SOCIAL_LOGIN_KEY_MUTATION_HOOK, "before_rename": SOCIAL_LOGIN_KEY_MUTATION_HOOK, "on_trash": SOCIAL_LOGIN_KEY_MUTATION_HOOK}, "Report": {"before_validate": REPORT_MUTATION_HOOK, "before_rename": REPORT_MUTATION_HOOK, "on_trash": REPORT_MUTATION_HOOK}}; assert extend_doctype_class == {"User": [USER_CONTROLLER_EXTENSION]}; assert set(override_whitelisted_methods) == {"frappe.core.doctype.user.user.reset_password", "frappe.core.doctype.user.user.update_password", "frappe.integrations.oauth2.get_token", "frappe.core.api.user_invitation.accept_invitation", "frappe.integrations.doctype.ldap_settings.ldap_settings.login", "frappe.www.login.login_via_key", "frappe.core.doctype.user.user.impersonate", "frappe.core.doctype.user.user.generate_keys", "frappe.client.get_password", "frappe.desk.doctype.system_console.system_console.execute_code", "frappe.desk.doctype.system_console.system_console.show_processlist", "frappe.desk.query_report.run", "frappe.desk.page.setup_wizard.setup_wizard.setup_complete", "frappe.desk.page.setup_wizard.setup_wizard.initialize_system_settings_and_user", "frappe.integrations.oauth2_logins.custom"}'
"${bench_root}/env/bin/python" -c \
  'from saervices_erpnext_sso_guard.runtime_manifest import write_runtime_manifest; write_runtime_manifest("/usr/local/share/saervices-erpnext-runtime-manifest")'
if [ ! -f "${runtime_manifest}" ] || [ -L "${runtime_manifest}" ]; then
  echo "ERPNext runtime manifest publication failed" >&2
  exit 1
fi
