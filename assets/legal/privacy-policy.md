# EQ Cards — Privacy Policy

**Effective date:** 2026-04-29
**Version:** 1.1

---

## 1. Who we are

EQ Cards is a product of **CDC Solutions Pty Ltd** (trading as **EQ Solutions**).

- **ACN:** 651 962 935
- **ABN:** 40 651 962 935
- **Registered office:** 173 Chuter Ave, Sans Souci NSW 2219
- **Directors:** Royce Milmlow, Emma Curth
- **Privacy contact:** contact@eq.solutions

We are an APP entity under the Australian Privacy Act 1988 (Cth) and we comply with the 13 Australian Privacy Principles as amended.

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
- **Mobile phone number** — the primary sign-in identifier. A one-time code is sent to it by **SMS** (delivered via Twilio — see §6).
- Email address — used for notifications and as an alternative sign-in identifier, where you provide one.
- One-time codes (SMS or email) — consumed at sign-in, not stored.

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

### 3.3a Government-related identifiers

Some licence information we hold constitutes government-related identifiers under APP 9 — for example, driver licence numbers, passport numbers, WWCC numbers, and police check references. We do not adopt these as our own identifier for you, use them for any purpose other than displaying and sharing them on your instruction, or disclose them except as described in §6. This is consistent with our obligations under APP 9.

### 3.4 Sensitive information

Some licences contain **sensitive information** as defined in section 6 of the Privacy Act 1988. This includes:

- **Health-adjacent credentials** — Medicare card details, first-aid certifications, WWCC numbers.
- **Identity document photos** — photos on driver licences and passports. We do not use facial recognition or automated biometric identification on any photos you upload; photos are stored as static images. However, we treat identity document photos as sensitive information out of caution and apply heightened security to them (see §7).

**Consent requirement.** We will seek your express consent within the app at the point you first upload each document in a sensitive category, before any sensitive information is collected. A brief consent prompt will describe what is being collected and why. You may withdraw consent at any time by deleting the relevant licence from your wallet. Uploading a sensitive document without completing the in-app consent prompt is not possible.

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
| Sensitive info (Medicare etc.) | Same as licence data — only because you've added it to your wallet, with your express consent |
| Analytics events | Improve the product. Identify which features work, which break (secondary purpose — see §4a) |
| Crash reports | Diagnose and fix bugs (secondary purpose — see §4a) |

We will not use your information for any other purpose without your consent.

We do **not** sell your information. We do **not** use it for advertising. We do **not** disclose it to data brokers.

**Analytics and crash reporting as secondary purposes (APP 6).** Analytics and error tracking are secondary purposes for personal information collected primarily for the wallet and credentialing function. By using EQ Cards you consent to this secondary use, and we disclose it upfront so it forms part of your informed consent at account creation. You may opt out of analytics and crash reporting via **Settings → Privacy** without affecting core wallet functionality. Opting out means we cannot collect information used solely for product improvement and debugging.

### 4a. Automated processing

Some features of EQ Cards involve automated processing of your information — for example, OCR to pre-fill licence fields from uploaded photos, and automated expiry reminders sent before a licence expires. These automated processes are designed to assist you and do not constitute decisions that significantly affect your legal rights or interests.

We will update this policy before December 2026 with full disclosures required under APP 1.7 as introduced by the Privacy and Other Legislation Amendment Act 2024, which regulates automated decision-making that significantly affects individual rights.

---

## 5. How we collect it

### 5.1 Directly from you
You enter your information into the app, or upload photos via the camera or file picker.

### 5.2 OCR processing
When you upload a licence photo, we send the photo to **Anthropic's Claude Vision API** to extract the structured fields (licence number, dates, authority, etc.). The photo is processed and the result returned; Anthropic does not retain the photo for training (per their commercial API terms). See §6 for overseas-disclosure detail.

### 5.3 Automatic collection
Analytics and crash reports are collected automatically by SDKs running in the app. You can disable analytics and crash reporting at any time in **Settings → Privacy**; once disabled, no further events are sent to the relevant processor.

### 5.4 What we do not do
- We do not buy data from third parties.
- We do not perform face recognition on uploaded photos.
- We do not infer biometric templates from photos.

### 5.5 Collection notices (APP 5)
At or before each material collection event — account creation, profile setup, and first upload of each licence category — the app displays a brief collection notice stating the purpose, who will see the information, and how to withdraw. This notice is separate from this policy. The Privacy Policy is not a substitute for these collection-specific notices and does not by itself satisfy APP 5.

---

## 6. Where your information is stored and disclosed

We use third-party processors. Each is bound by their own contractual obligations to handle your data lawfully.

| Service | Data | Location | Transferred outside Australia? |
|---|---|---|---|
| **Supabase** (database, storage, auth) | Profile, licences, photos, audit log, email + OTP | Sydney (`ap-southeast-2`) | No — primary data in AU |
| **Twilio** (SMS delivery for sign-in one-time codes) | Your mobile phone number and the one-time code | United States | **Yes** |
| **Anthropic Claude Vision** (OCR) | Licence photo bytes (transient) | United States | **Yes** |
| **PostHog** (analytics) | Event names, properties, anonymous device ID, user UUID and email address | Frankfurt, Germany (EU) | **Yes** |
| **Sentry** (crash reporting) | Stack traces, occasional URL/screen context | Frankfurt, Germany (EU) | **Yes** |
| **Netlify** (hosting) | Web app static assets (no personal info on the host) | United States CDN | Yes (hosting only) |

> Analytics and crash reporting (PostHog, Sentry) are only sent if you leave them enabled — you can turn each off in **Settings → Privacy**.

**Overseas disclosure and your rights.** Where we disclose your personal information to overseas recipients (see table above), we take reasonable steps under APP 8.1 to ensure each recipient is contractually obligated to handle your information consistently with the Australian Privacy Principles. We note that where you consent to overseas disclosure under this policy, the Australian Privacy Principles may not apply to the overseas recipient's handling of your information, and you may have limited recourse under Australian law. Where we have not relied on your consent and have instead relied on taking reasonable steps under APP 8.1, we retain accountability for breaches by overseas recipients as if they were our own (s16C, Privacy Act 1988). If you do not consent to overseas disclosure, you cannot use EQ Cards — the service depends on these processors. By creating an account, you confirm you understand and accept this.

We have taken reasonable steps (contractual review of each provider's privacy and security practices) to ensure they handle your information consistently with the Australian Privacy Principles.

---

## 7. How we secure your information

**Technical security measures:**
- **Encryption in transit:** all communication uses HTTPS / TLS 1.2+.
- **Encryption at rest:** Supabase encrypts the database and storage with AES-256.
- **Row-level security:** every database row is scoped to the authenticated user; RLS policies enforce this in the database layer, not just the app layer.
- **Photo URLs:** licence photos are served via 1-hour signed URLs, not public links.
- **EXIF stripping:** GPS/location metadata is removed from photos before upload.
- **Authentication:** mobile number + 6-digit SMS one-time code via Supabase Auth (email one-time code also supported). We do not store passwords.
- **Biometric unlock:** optional Face ID / fingerprint gate on the app itself (mobile only).

**Organisational security measures (APP 11.3):**
- Mandatory privacy and security training for all personnel with access to personal information.
- Documented access management policies restricting personal data access to those with a genuine operational need. Internally, only the named directors (Royce Milmlow, Emma Curth) have administrative access to the production Supabase project. Access is logged.
- A formal incident response and data breach assessment procedure (see NDB commitment below).
- Contractual data processing agreements with all third-party processors requiring equivalent security and data-handling standards.
- Periodic security reviews including vulnerability assessments.

**Data breach notification (NDB scheme).** If we become aware of grounds to suspect an eligible data breach — that is, unauthorised access to, or disclosure of, your personal information that is likely to result in serious harm — we will assess the incident within 30 days as required under Part IIIC of the Privacy Act 1988. If we form reasonable grounds to believe an eligible data breach has occurred, we will notify the Office of the Australian Information Commissioner (OAIC) and all affected individuals as soon as practicable after completing that assessment. Our notification to you will include: a description of the breach; the kinds of information involved; what serious harm you may face; and steps you can take to reduce that risk. We may notify you directly by email or SMS, or by prominent notice on our website and in the app where direct contact is impracticable.

No system is perfectly secure. We will comply with all notification obligations under the Notifiable Data Breaches scheme.

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

- **Access** the personal information we hold about you. The app already shows you everything we hold. You can also generate a machine-readable JSON export of your profile + licences in-app via **Settings → Export my data**, or request the same by emailing the privacy contact above.
- **Correct** inaccurate information. Edit the relevant field in the app, or email the privacy contact.
- **Delete your account.** Settings → Sign out → email the privacy contact requesting deletion. We will hard-delete all data within 30 days and confirm by email. Note: deleting the account does not retroactively scrub analytics events that were generated under your distinct user ID — those are anonymised but retained per the table in §8. You may separately request the anonymised analytics record be deleted; we will comply within 30 days.
- **Object** to processing for analytics or crash reporting. You can disable each at any time in **Settings → Privacy**. You may also email the privacy contact and we will exclude your account.
- **Withdraw consent** for overseas disclosure by ceasing to use the service. We cannot retroactively recall data already disclosed under your prior consent, but we will not disclose further.

We will respond to all access and correction requests within 30 days.

**Grounds for refusing access (APP 12.3).** We may decline an access request where giving access would pose a serious threat to the safety of any person, unreasonably impact another person's privacy, or is subject to legal privilege. Where we refuse or limit access, we will provide written reasons and advise you of your right to complain to the OAIC.

---

## 10. Children

EQ Cards is intended for **users aged 18 and over** (the wallet holds work-related licences, which presupposes adult employment). By creating an account you represent that you are 18 or over. We do not knowingly collect personal information from persons under 18. If we become aware that a person under 18 has created an account, we will delete that account and associated data promptly.

Note: the OAIC is developing a Children's Online Privacy Code (due by December 2026) — we will update our age-verification practices and this policy to comply when the Code is registered.

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
contact@eq.solutions

CDC Solutions Pty Ltd
ACN: 651 962 935
ABN: 40 651 962 935
173 Chuter Ave, Sans Souci NSW 2219

---

**End of Privacy Policy.**
