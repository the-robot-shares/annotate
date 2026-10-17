// Copy for the tobor-kit <noizu-auth> sign-in modal (GitHub + Google, provider-redirect
// mode). `text` is a property, not an attribute, so it is set here from a static
// same-origin module (CSP-safe). Hologram's client boot may re-create the element
// after first paint (dropping JS properties), so the copy is (re)applied on every
// trigger click, in the capture phase — before the kit's own handler opens it.
const TEXT = {
  loginTitle: 'Sign in to annotate',
  signupTitle: 'Create your annotate account',
  description: 'Sign in with GitHub or Google; we use your account’s verified email. By continuing you agree to the Terms of Service and Privacy Policy (annotate.therobotlives.com/terms and /privacy).',
  close: 'Close sign-in dialog',
  login: 'Sign in',
  signup: 'Sign up',
  haveAccount: 'Already have an account?',
  needAccount: 'New to annotate?',
};

const apply = () => {
  for (const el of document.querySelectorAll('noizu-auth[data-annotate-auth]')) {
    if (el.text !== TEXT) el.text = TEXT;
  }
};

customElements.whenDefined('noizu-auth').then(apply);
document.addEventListener('click', (event) => {
  if (event.target instanceof Element && event.target.closest('[data-auth-open]')) apply();
}, true);
