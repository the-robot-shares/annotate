# Cookie Consent Policy

This starter treats session, CSRF, security, load-balancing, and auth handoff
cookies as strictly necessary. They are disclosed in the cookie settings UI, but
they are not optional and are not disabled by the preference form.

Optional storage is off until the user opts in:

- `analytics`: product analytics and usage measurement.
- `marketing`: advertising, campaign attribution, and cross-site tracking.
- `preferences`: non-essential display and personalization storage.

The implementation persists choices by anonymous browser-session UUID before
registration and by `user_id` after authentication. If a user signs in after
choosing preferences anonymously, the frontend re-saves the current preference
state while authenticated so the backend can attach it to the user.

## Legal Baseline

This is not legal advice, but the implementation follows the common conservative
baseline from official guidance:

- UK ICO PECR guidance says cookies require clear information and consent, but
  includes an exception for cookies essential to provide an online service
  requested by the user. It also says non-essential cookies should not be set
  before consent and users need an easy way to enable or disable non-essential
  cookies. See: https://ico.org.uk/for-organisations/direct-marketing-and-privacy-and-electronic-communications/guide-to-pecr/cookies-and-similar-technologies/
- California CCPA/CPRA guidance focuses on notice and opt-out of sale/sharing,
  including Global Privacy Control for covered businesses. It does not require
  opt-in consent for strictly necessary app-session cookies. See:
  https://oag.ca.gov/privacy/ccpa

## Product Rule

Do not offer a UI toggle that disables strictly necessary session/security
cookies. Show them as required, persist that they are required, and block only
optional categories until the user opts in.

If a downstream app adds tracking that sells/shares personal information or uses
cross-context behavioral advertising, add a visible opt-out path and honor GPC
before setting those tracking technologies.
