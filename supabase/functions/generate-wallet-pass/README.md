# generate-wallet-pass

Supabase Edge Function that generates an Apple Wallet `.pkpass` file for a
worker credential stored in `public.worker_credentials`.

## Request

```
GET /functions/v1/generate-wallet-pass?credentialId=<uuid>
Authorization: Bearer <supabase-auth-jwt>
```

Returns `application/vnd.apple.pkpass` binary (a signed ZIP).

---

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `SUPABASE_URL` | Auto | Injected by Supabase runtime |
| `SUPABASE_ANON_KEY` | Auto | Injected by Supabase runtime |
| `SUPABASE_SERVICE_ROLE_KEY` | Auto | Injected by Supabase runtime |
| `APPLE_TEAM_ID` | Yes (prod) | 10-character Apple Developer Team ID |
| `APPLE_PASS_CERT_P12` | Yes (prod) | Base64-encoded PKCS#12 bundle (cert + key) |
| `APPLE_PASS_CERT_PASSWORD` | Yes (prod) | Passphrase for the P12 |
| `APPLE_WWDR_CERT` | Yes (prod) | Base64-encoded Apple WWDR G4 cert (DER) |

Without the Apple vars the function still returns a valid ZIP with an empty
signature and an `X-Pass-Status: unsigned` header. iOS Wallet will reject it
but the file structure is correct for local development/debugging.

---

## Setting up Apple signing certs (step by step)

### 1. Create a Pass Type ID

1. Log in to [developer.apple.com](https://developer.apple.com) → **Certificates, IDs & Profiles** → **Identifiers**.
2. Click **+** → choose **Pass Type IDs** → Continue.
3. Description: `EQ Cards Pass`, Identifier: `pass.solutions.eq.cards`.
4. Register. The identifier `pass.solutions.eq.cards` matches the
   `passTypeIdentifier` hardcoded in `index.ts`.

### 2. Create the Pass Type ID certificate

1. In **Identifiers**, select the Pass Type ID you just created.
2. Click **Create Certificate** under the production certificate section.
3. On your Mac: open **Keychain Access** → **Certificate Assistant** →
   **Request a Certificate from a CA** → save to disk as a `.certSigningRequest`
   file.
4. Upload the `.certSigningRequest` file to Apple, download the resulting
   `.cer` file.
5. Double-click the `.cer` to install it into your Keychain.

### 3. Export as P12

1. Open **Keychain Access** → find the cert named like
   *Pass Type ID: pass.solutions.eq.cards*.
2. Expand it — you should see the private key nested under it.
3. Select **both** the certificate and the private key (Cmd+click).
4. Right-click → **Export 2 items…** → choose **Personal Information
   Exchange (.p12)** format.
5. Set a strong passphrase — this becomes `APPLE_PASS_CERT_PASSWORD`.

### 4. Get the Apple WWDR G4 intermediate cert

Download the **Apple Worldwide Developer Relations Certification Authority
G4** cert from Apple's PKI page:
<https://www.apple.com/certificateauthority/>

Direct link (as of 2026):
<https://www.apple.com/certificateauthority/AppleWWDRCAG4.cer>

This is a DER-encoded `.cer` file. Do **not** convert it — use it as-is.

### 5. Base64-encode and add to Supabase secrets

On macOS/Linux:

```bash
# Encode the P12
base64 -i ~/Downloads/YourPassCert.p12 | tr -d '\n' > pass_cert.b64
# Encode the WWDR cert
base64 -i ~/Downloads/AppleWWDRCAG4.cer | tr -d '\n' > wwdr.b64
```

On Windows (PowerShell):

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\Downloads\YourPassCert.p12")) | Out-File -NoNewline pass_cert.b64
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\Downloads\AppleWWDRCAG4.cer")) | Out-File -NoNewline wwdr.b64
```

Then add to Supabase (CLI or dashboard **Settings → Edge Functions → Secrets**):

```bash
supabase secrets set \
  APPLE_TEAM_ID=ABCDE12345 \
  APPLE_PASS_CERT_P12="$(cat pass_cert.b64)" \
  APPLE_PASS_CERT_PASSWORD="your-p12-passphrase" \
  APPLE_WWDR_CERT="$(cat wwdr.b64)"
```

### 6. Find your Team ID

In the Apple Developer portal → top-right account dropdown → **Membership
details**. It is a 10-character string like `ABCDE12345`.

---

## Replacing placeholder icons

The function ships 1×1 transparent PNG placeholders for `icon.png`,
`icon@2x.png`, `logo.png`, `logo@2x.png`. Apple Wallet rejects passes
without these four files.

Replace the `TRANSPARENT_1X1_PNG_B64` constant in `index.ts` with a real
icon, **or** update `buildPassZip` to read from Supabase Storage:

| File | Recommended size |
|---|---|
| `icon.png` | 29×29 px |
| `icon@2x.png` | 58×58 px |
| `logo.png` | 160×50 px |
| `logo@2x.png` | 320×100 px |

PNG, 72 DPI. No transparency required but transparent background works well
on the dark pass background (`rgb(26, 26, 46)`).

---

## Deploying the function

```bash
supabase functions deploy generate-wallet-pass --project-ref jvknxcmbtrfnxfrwfimn
```
