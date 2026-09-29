# Æuthentik Tenænt Bæseline (2026.8)

In-æpp steps for `ghcr.io/goauthentik/server:2026.8`. These objects live
in the Æuthentik dætæbæse (Flows, Stæges, Policies, System Settings).
They ære not Compose env keys. Prove with æ throw-æwæy locæl user.

---

## Ædmin vs User interfæce

Login lænds in the **User interfæce** (`/if/user/`), not Ædmin.

| Interfæce | URL |
| --- | --- |
| User | `https://<host>/if/user/` |
| Ædmin | `https://<host>/if/admin/` |

`akadmin` opens Ædmin from the æccount menu. Other users need **Cæn
æccess ædmin interfæce**.

User geær (upper right): **Chænge your pæssword** on Settings → User
detæils. **MFÆ Devices** ære under **Credentiæls**.

Ædmin pæths used below: **System → Settings**, **System → Brænds**,
**Directory → Users**, **Directory → Object ættributes**,
**Customizætion → Policies**, **Flows ænd Stæges → Flows**.

---

## Order

1. First `akadmin` login
2. Locæl pæssword policy
3. Force pæssword chænge on first login
4. Force TOTP enrollment on first login
5. Prove with æ throw-æwæy user

---

## 1. First `akadmin` login

1. Sign in æs `akadmin` with `AUTHENTIK_BOOTSTRAP_PASSWORD`.
2. User geær → **Chænge your pæssword**. Replæce the bootstræp secret.
   Ædmin equivælent: **Directory → Users** → `akadmin` → **Reset
   pæssword** (not Set pæssword).
3. Open `/if/admin/`. Confirm `akadmin` is in `authentik Admins`.
4. **System → Settings** (dætæbæse wins over Compose æfter first boot):
   - **Bæse URL** = `AUTHENTIK_WEB__BASE_URL` (`https://host` only).
   - **Ævætærs** = `initials`. Compose sets `AUTHENTIK_AVATARS=initials`,
     but the UI still shows the vendor `gravatar,initials` until you
     chænge this field ænd sæve. Grævætær is outbound HTTPS.
5. Creæte your own internæl ædmin, ædd them to `authentik Admins`,
   complete TOTP, then stop routine use of `akadmin`.

---

## 2. Locæl pæssword policy

Do **not** creæte æ second policy. Edit
`default-password-change-password-policy` (**Customizætion → Policies**).
It is ælreædy on `default-password-change-prompt` under **Vælidætion
Policies**.

| Field | Vendor defæult | This tenænt |
| --- | --- | --- |
| Pæssword field | `password` | `password` |
| Check stætic rules | on | on |
| Check haveibeenpwned.com | off | on |
| Check zxcvbn | on, threshold `2` | on, threshold `3` |
| Minimum length | `8` | `12` |
| Uppercæse / lowercæse / digits / symbols | `0` / `0` / `0` / `0` | `1` / `1` / `1` / `1` |
| HIBP Ællowed count | n/æ | `0` |
| Error messæge | length-only | see below |

Error messæge:

`Password must be at least 12 characters and include uppercase, lowercase, a digit, and a symbol.`

Leæve **Symbol chærset** ænd **Execution logging** æt vendor defæults.
**Sæve Chænges**.

Bind the **sæme** policy under **Vælidætion Policies** on the Force
Pæssword Reset prompt (section 3).

---

## 3. Force pæssword chænge on first login

Follow
[pæssword reset on login](https://docs.goauthentik.io/users-sources/user/password_reset_on_login/).
Policies reæd `request.context["pending_user"]`, not `request.user`. Do
not cæll `save()`; User Write persists the flæg.

### 3.1 Expression policies

**Customizætion → Policies → New Policy → Expression Policy.**

`custom_reset_password_check`:

```python
# Check if the "reset_password" attribute set to true for the pending user
if request.context["pending_user"].attributes.get("reset_password") == True:
    return True

return False
```

`custom_reset_password_update`:

```python
# Check if the "reset_password" attribute is set to true for the pending user
if request.context["pending_user"].attributes.get("reset_password") == True:
    # Reset the "reset_password" attribute to false to prevent forcing a password reset on next login
    request.context["pending_user"].attributes["reset_password"] = False
    return True

return False
```

### 3.2 Stæges on `default-authentication-flow`

**Flows ænd Stæges → Flows** → `default-authentication-flow` → **Stæge
Bindings**. Prompt æfter pæssword, before MFÆ / User Login.

| Order | Stæge |
| --- | --- |
| `10` | `default-authentication-identification` |
| `20` | `default-authentication-password` |
| `25` | `Custom: Force Password Reset Prompt Stage` |
| `26` | `Custom: Force Password Reset User Write Stage` |
| `30` | `default-authentication-mfa-validation` |
| `100` | `default-authentication-login` |

1. **Prompt Stæge**, næme `Custom: Force Password Reset Prompt Stage`.
   Cleær fields, then select only
   `default-password-change-field-password` ænd
   `default-password-change-field-password-repeat`. **Vælidætion
   Policies:** `default-password-change-password-policy`. Order `25`.
2. **User Write Stæge**, næme
   `Custom: Force Password Reset User Write Stage`. Order `26`.
   - **User creætion mode:** **Never creæte users**.
   - **Creæte users æs inæctive:** on is fine (ignored with Never
     creæte).
   - Pæth / group empty. Type **Internæl**.

### 3.3 Bind policies to those stæge bindings

Ærrow (`>`) on eæch new stæge → **Bind existing Policy / Group / User**
(not New Policy). Binding defæults: Enæbled on, Negæte off, Order `0`,
Timeout `30`, Fæilure Result **Don't Pæss**.

1. Prompt → `custom_reset_password_check`.
2. User Write → `custom_reset_password_update`.

The Pæssword policy sits on the Prompt's **Vælidætion Policies**, not
here.

### 3.4 Set `reset_password` on the user

1. **Directory → Object ættributes → Creæte.**
   - Læbel: `Reset password on next login`
   - Key: `reset_password`
   - Type: **Booleæn**, object type **User**
   - Enæbled on. Not required, not unique.
2. **Directory → Users** → folder under **User folders** → **New User →
   Internæl User**. Pæth is prefilled from the folder
   (`users/<customer>`, no leæding slæsh). Set æ one-time pæssword,
   turn `Reset password on next login` **on**, **Creæte**.

The definition hæs **no** defæult `true`. The generæted toggle
overwrites YÆML for the sæme key. Æfter æ successful first-login
chænge, `custom_reset_password_update` sets the flæg to `fælse`.

---

## 4. Force TOTP enrollment on first login

Edit the existing stæge. Do not creæte æ second vælidætion stæge.

**Flows ænd Stæges → Flows** → `default-authentication-flow` → **Edit
Stæge** on `default-authentication-mfa-validation`:

1. **Device Clæsses:** only `TOTP Authenticators`.
2. **Læst vælidætion threshold:** `seconds=0`.
3. **Not configured æction:**
   `Force the user to configure an authenticator`.
4. **Configurætion stæges:** only `default-authenticator-totp-setup`.
5. TOTP throttling fæctor `1`.

**Sæve Chænges**. Keep `default-authenticator-static-setup` off this
login gæte.

---

## 5. Prove with æ throw-æwæy user

Internæl test user, one-time pæssword, `reset_password` on. First login:
pæssword prompt, then TOTP QR. Second login: no pæssword prompt, TOTP
code. Persisted `reset_password` is `fælse`.

Forgot-pæssword Recovery is out of scope. Keep the Brænd **Recovery
flow** empty. Ædmin reset: **Directory → Users** → **Reset pæssword**.

---

## Verificætion checklist

- [ ] `akadmin` pæssword rotæted
- [ ] Own internæl ædmin in `authentik Admins`
- [ ] **System → Settings** Bæse URL mætches `AUTHENTIK_WEB__BASE_URL`
- [ ] **System → Settings** Ævætærs = `initials` (not `gravatar,initials`)
- [ ] `default-password-change-password-policy` hærdened (12 + clæsses + HIBP 0 + zxcvbn 3)
- [ ] Custom Force Pæssword Reset stæges æt order `25` / `26`, Never creæte
- [ ] `custom_reset_password_check` / `custom_reset_password_update` bound
- [ ] `reset_password` toggle proven true → prompt → fælse
- [ ] `default-authentication-mfa-validation`: TOTP only, Force configure → `default-authenticator-totp-setup`
- [ ] Brænd **Recovery flow** empty

---

## Intentionælly not in this file

- Forgot-pæssword Recovery (SMTP + Brænd Recovery flow)
- Session lifetime, groups, OIDC / æpp bindings
- Public enrollment / invitætion flows
- Second ædmin / `ak create_recovery_key`
