# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

app_name = "saervices_erpnext_sso_guard"
app_title = "it.særvices ERPNext SSO Guard"
app_publisher = "it.særvices"
app_description = "Server-side Authentik SSO and API authentication enforcement"
app_email = "admin@it.saervices.de"
app_license = "MIT"
app_version = "1"

required_apps = ["frappe"]

auth_hooks = [
    "saervices_erpnext_sso_guard.api_auth.enforce_api_service_account_allowlist"
]

before_login = [
    "saervices_erpnext_sso_guard.api_auth.enforce_host_sso_before_login"
]

permission_query_conditions = {
    "OAuth Authorization Code": (
        "saervices_erpnext_sso_guard.api_auth.oauth_credential_query_condition"
    ),
    "OAuth Bearer Token": (
        "saervices_erpnext_sso_guard.api_auth.oauth_credential_query_condition"
    ),
    "OAuth Client": (
        "saervices_erpnext_sso_guard.api_auth.oauth_credential_query_condition"
    ),
}

has_permission = {
    "OAuth Authorization Code": (
        "saervices_erpnext_sso_guard.api_auth.enforce_oauth_credential_permission"
    ),
    "OAuth Bearer Token": (
        "saervices_erpnext_sso_guard.api_auth.enforce_oauth_credential_permission"
    ),
    "OAuth Client": (
        "saervices_erpnext_sso_guard.api_auth.enforce_oauth_credential_permission"
    ),
}

doc_events = {
    "User": {
        "before_validate": (
            "saervices_erpnext_sso_guard.user_document.guard_user_password_fields"
        )
    },
    "Social Login Key": {
        "before_validate": (
            "saervices_erpnext_sso_guard.user_document.guard_social_login_key_mutation"
        ),
        "before_rename": (
            "saervices_erpnext_sso_guard.user_document.guard_social_login_key_mutation"
        ),
        "on_trash": (
            "saervices_erpnext_sso_guard.user_document.guard_social_login_key_mutation"
        ),
    },
    "Report": {
        "before_validate": (
            "saervices_erpnext_sso_guard.api_auth.guard_nonstandard_script_report_mutation"
        ),
        "before_rename": (
            "saervices_erpnext_sso_guard.api_auth.guard_nonstandard_script_report_mutation"
        ),
        "on_trash": (
            "saervices_erpnext_sso_guard.api_auth.guard_nonstandard_script_report_mutation"
        ),
    },
}

extend_doctype_class = {
    "User": ["saervices_erpnext_sso_guard.user_document.UserSSOGuardMixin"]
}

override_whitelisted_methods = {
    "frappe.core.doctype.user.user.reset_password": (
        "saervices_erpnext_sso_guard.password_login.reset_password"
    ),
    "frappe.core.doctype.user.user.update_password": (
        "saervices_erpnext_sso_guard.password_login.update_password"
    ),
    "frappe.integrations.oauth2.get_token": (
        "saervices_erpnext_sso_guard.password_login.get_token"
    ),
    "frappe.core.api.user_invitation.accept_invitation": (
        "saervices_erpnext_sso_guard.password_login.accept_invitation"
    ),
    "frappe.integrations.doctype.ldap_settings.ldap_settings.login": (
        "saervices_erpnext_sso_guard.password_login.ldap_login"
    ),
    "frappe.www.login.login_via_key": (
        "saervices_erpnext_sso_guard.password_login.login_via_key"
    ),
    "frappe.core.doctype.user.user.impersonate": (
        "saervices_erpnext_sso_guard.password_login.impersonate"
    ),
    "frappe.core.doctype.user.user.generate_keys": (
        "saervices_erpnext_sso_guard.password_login.generate_keys"
    ),
    "frappe.client.get_password": (
        "saervices_erpnext_sso_guard.password_login.get_password"
    ),
    "frappe.desk.doctype.system_console.system_console.execute_code": (
        "saervices_erpnext_sso_guard.password_login.execute_system_console_code"
    ),
    "frappe.desk.doctype.system_console.system_console.show_processlist": (
        "saervices_erpnext_sso_guard.password_login.show_processlist"
    ),
    "frappe.desk.query_report.run": (
        "saervices_erpnext_sso_guard.password_login.run_query_report"
    ),
    "frappe.desk.page.setup_wizard.setup_wizard.setup_complete": (
        "saervices_erpnext_sso_guard.password_login.setup_complete"
    ),
    "frappe.desk.page.setup_wizard.setup_wizard.initialize_system_settings_and_user": (
        "saervices_erpnext_sso_guard.password_login.initialize_system_settings_and_user"
    ),
    "frappe.integrations.oauth2_logins.custom": (
        "saervices_erpnext_sso_guard.password_login.authentik_custom_login"
    ),
}
