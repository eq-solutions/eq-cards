# EQ Cards — Privacy Policy

**Effective date:** 2026-04-29
**Version:** 1.0 (template — pending Australian privacy-lawyer review)

> ⚠ **This document is a working template, not legal advice.** It was drafted to comply with the Australian Privacy Act 1988 (Cth) and the Australian Privacy Principles (APPs), but **must be reviewed by a qualified Australian privacy lawyer before being published as the public-facing policy**. Webb Financial (the entity's accountant) handles tax, not privacy law — different specialist required.

---

## 1. Who we are

EQ Cards is a product of **CDC Solutions Pty Ltd** (trading as **EQ Solutions**).

- **ABN:** _[TO INSERT]_
- **Registered office:** _[TO INSERT]_
- **Directors:** Royce Milmlow, Emma Curth
- **Privacy contact:** _[TO INSERT — e.g. privacy@eq.solutions]_

We are an APP entity under the Australian Privacy Act 1988 (Cth) and we comply with the 13 Australian Privacy Principles.

---

## 2. What this policy covers

This policy explains how EQ Cards (the mobile and web app at `cards.eq.solutions` and any installed PWA) handles personal information.

It does **not** cover:
- Other EQ Solutions products you may use separately (each will have its own policy)
- Third-party services we link to or integrate with (their own policies apply)

---

## 3. What information we collect

We collect only what's needed to operate the wallet.

### 3.1 Account information
- Mobile phone number — used as the unique sign-in identifier
- One-time codes sent to that number (consumed at sign-in, not stored)

### 3.2 Profile information
- Full name
- Date of birth
- Mobile, email
- Postal/residential address (street, suburb, state, postcode)
- Emergency contact (name, relationship, mobile)

You decide which of these to enter. None are mandatory beyond the mobile number used for sign-in.

### 3.3 Licence and certificate information
- Licence type (e.g. White Card, driver licence, HLTAID first aid)
- Licence number
- Issue date, expiry date
- Issuing authority and state
- Photos of the front and back of the licence (uploaded by you)
- Type-specific metadata you enter (e.g. driver-class, forklift-class)
- Free-text notes you add

### 3.4 Sensitive information

Some licences are or may contain **sensitive information** under section 6 of the Privacy Act:

- **Medicare card details** are health-adjacent identifying information.
- **Driver licence photos** contain a portrait that could be used for biometric identification (we do not perform any biometric matching — see §5.4).

By uploading these, **you give us your express consent** to collect and store them for the purposes described in §4. You can delete any licence at any time (§9).

### 3.5 Information we automatically collect
- **Analytics events** describing your interactions with the app (e.g. "tap-to-copy a field", "add a licence"). These do not contain the values you copy or the contents of your fields — only that an action happened. Sent to PostHog (see §6).
- **Crash reports** when something goes wrong, with stack traces and (sometimes) the URL of the screen you were on. Sent to Sentry (see §6).
- **Device/browser information** required for the app to render — operating system, browser version, screen size. Standard for any web app.

### 3.6 Information we do NOT collect
- We do not collect your real-time location.
- We do not collect contacts from your phone.
- We do not access your camera roll except when you explicitly pick a photo to upload.
- We do not perform face recognition or biometric matching on uploaded photos.
- We strip GPS/location metadata (EXIF) from photos before storage.

---

## 4. Why we collect it (purpose)

| Information | Purpose |
|---|---|
| Mobile + OTP | Authenticate you as the account owner |
| Profile fields | Render the wallet; tap-to-copy onto induction forms; emergency contact display |
| Licence data + photos | Display your licences; share with sites/employers when you choose to |
| Sensitive info (Medicare etc.) | Same as licence data — only because you've added it to your wallet |
| Analytics events | Improve the product. Identify which features work, which break |
| Crash reports | Diagnose and fix bugs |

We will not use your information for any other purpose without your consent.

We do **not** sell your information. We do **not** use it for advertising. We do **not** disclose it to data brokers.

---

## 5. How we collect it

### 5.1 Directly from you
You enter your information into the app, or upload photos via the camera or file picker.

### 5.2 OCR processing
When you upload a licence photo, we send the photo to **Anthropic's Claude Vision API** to extract the structured fields (licence number, dates, authority, etc.). The photo is processed and the result returned; Anthropic does not retain the photo for training (per their commercial API terms). See §6 for overseas-disclosure detail.

### 5.3 Automatic collection
Analytics and crash reports are collected automatically by SDKs running in the app. You can disable analytics in Settings → Privacy (planned for v1.1).

### 5.4 What we do not do
- We do not buy data from third parties.
- We do not perform face recognition on uploaded photos.
- We do not infer biometric templates from photos.

---

## 6. Where your information is stored and disclosed

We use third-party processors. Each is bound by their own contractual obligations to handle your data lawfully.

| Service | Data | Location | Transferred outside Australia? |
|---|---|---|---|
| **Supabase** (database, storage, auth) | Profile, licences, photos, audit log | Sydney (Australia) — `ap-southeast-2` region | No — data resides in AU |
| **Twilio** (SMS for OTP) | Mobile phone number, OTP code | United States | Yes |
| **Anthropic Claude Vision** (OCR) | Licence photo bytes (transient) | United States | Yes — photo sent for OCR processing, not retained |
| **PostHog** (analytics) | Event names, properties, anonymous device ID, signed-in user UUID | Frankfurt, Germany (EU region) | Yes |
| **Sentry** (crash reporting) | Stack traces, occasional URL/screen context | Frankfurt, Germany (EU region) | Yes |
| **Netlify** (hosting) | Web app static assets (no personal info on the host) | United States CDN | Yes (hosting only) |

**Overseas disclosure consent:** by using EQ Cards, you consent to your information being disclosed to the overseas recipients above for the purposes described in §4. If you object to overseas disclosure, please do not use the service.

We have taken reasonable steps (contractual review of each provider's privacy and security practices) to ensure they handle your information consistently with the Australian Privacy Principles.

---

## 7. How we secure your information

- **Encryption in transit:** all communication uses HTTPS / TLS 1.2+.
- **Encryption at rest:** Supabase encrypts the database and storage with AES-256.
- **Row-level security:** every database row is scoped to the authenticated user; RLS policies enforce this in the database layer, not just the app layer.
- **Photo URLs:** licence photos are served via 1-hour signed URLs, not public links.
- **EXIF stripping:** GPS/location metadata is removed from photos before upload.
- **Authentication:** phone-OTP via Twilio. We do not store passwords.
- **Biometric unlock:** optional Face ID / fingerprint gate on the app itself (mobile only).
- **Access controls:** internally, only the named directors (Royce Milmlow, Emma Curth) have administrative access to the production Supabase project. Access is logged.

No system is perfectly secure. We will notify you and the Office of the Australian Information Commissioner (OAIC) of any eligible data breach as required by the Notifiable Data Breaches scheme.

---

## 8. How long we keep your information

| Data | Retention |
|---|---|
| Active account data | While the account exists |
| Licence photos | While the licence exists in your wallet, plus 30 days after you delete it (soft-delete window) |
| Soft-deleted licences | Permanently deleted 30 days after deletion |
| Account on request to delete | Hard-deleted within 30 days |
| Analytics events (PostHog) | 7 years from collection (default) |
| Crash reports (Sentry) | 90 days from collection (default) |
| Authentication logs | 90 days |
| Audit log (database row history) | While the account exists, then deleted with the account |

You can request deletion of your account at any time — see §9.

---

## 9. Your rights

Under the Australian Privacy Principles you may:

- **Access** the personal information we hold about you. The app already shows you everything we hold; you can also request a machine-readable export by emailing the privacy contact above.
- **Correct** inaccurate information. Edit the relevant field in the app, or email the privacy contact.
- **Delete your account.** Settings → Sign out → email the privacy contact requesting deletion. We will hard-delete all data within 30 days and confirm by email. Note: deleting the account does not retroactively scrub analytics events that were generated under your distinct user ID — those are anonymised but retained per the table in §8. You may separately request the anonymised analytics record be deleted; we will comply within 30 days.
- **Object** to processing for analytics or crash reporting. You can disable each in Settings → Privacy (planned for v1.1). Until that ships, email the privacy contact and we will exclude your account.
- **Withdraw consent** for overseas disclosure by ceasing to use the service. We cannot retroactively recall data already disclosed under your prior consent, but we will not disclose further.

We will respond to requests within 30 days.

---

## 10. Children

EQ Cards is intended for **users aged 18 and over** (the wallet typically holds work-related licences, which presupposes adult employment). We do not knowingly collect information from children under 18. If you become aware that a child has provided us with personal information, please contact us; we will delete the information.

---

## 11. Cookies and similar technology

The web app uses `localStorage` and `sessionStorage` to:
- Persist your sign-in session
- Remember your design preference (Settings → Design picker)
- Cache fonts and bundles for performance

It does **not** use third-party advertising or tracking cookies. The PostHog SDK uses a single first-party cookie / localStorage entry to maintain its anonymous distinct ID across sessions. You can clear this any time via your browser's site-data tools.

---

## 12. Complaints

If you believe we have breached the Australian Privacy Principles, contact us first at the privacy contact email in §1. We will investigate and respond within 30 days.

If you are not satisfied with our response, you may complain to the **Office of the Australian Information Commissioner (OAIC)**:

- Web: https://www.oaic.gov.au/
- Phone: 1300 363 992
- Post: GPO Box 5288, Sydney NSW 2001

---

## 13. Changes to this policy

We may update this policy. The "Effective date" at the top changes when we do. For material changes (new categories of data collected, new overseas recipients, new disclosed purposes), we will notify you in-app and via email before the change takes effect. By continuing to use the service after a non-material change, you accept the updated policy.

---

## 14. Contact

Questions or requests:

**EQ Solutions — Privacy**
_[email TO INSERT]_

CDC Solutions Pty Ltd
ABN: _[TO INSERT]_
_[Registered address TO INSERT]_

---

**End of Privacy Policy.**

Source: [`docs/PRIVACY-POLICY.md`](PRIVACY-POLICY.md). Generated render lives in the app at Settings → Legal → Privacy Policy.
