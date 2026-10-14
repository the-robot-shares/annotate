/**
 * Tailwind Plus demo bridge (Hologram styleguide)
 * - Syncs selected theme + color mode from parent viewer
 * - Maps theme CSS variables into Tailwind CDN palette
 * - Progressive enhancement: toggles, tabs, overlays, dropdowns
 */
(function () {
  'use strict';

  var THEME_CSS = {
    'style-guide': '/themes/style-guide.css',
    cyberpunk: '/themes/cyberpunk.css',
    'sumi-e': '/themes/sumi-e.css',
    swiss: '/themes/swiss.css'
  };

  function cookie(name) {
    try {
      var m = document.cookie.match(new RegExp('(?:^|; )' + name + '=([^;]*)'));
      return m ? decodeURIComponent(m[1]) : null;
    } catch (e) {
      return null;
    }
  }

  function queryParam(name) {
    try {
      return new URLSearchParams(location.search).get(name);
    } catch (e) {
      return null;
    }
  }

  function parentHtml() {
    try {
      if (window.parent && window.parent !== window) {
        return window.parent.document.documentElement;
      }
    } catch (e) {
      /* cross-origin */
    }
    return null;
  }

  function readTheme() {
    // Prefer live parent viewer (updates when theme select changes).
    var p = parentHtml();
    if (p) {
      var slug = p.getAttribute('data-design-theme');
      if (slug && THEME_CSS[slug]) return slug;
    }

    var c = cookie('sg-theme');
    if (c && THEME_CSS[c]) return c;

    // Query is first-paint fallback only (standalone / cold load).
    var q = queryParam('theme');
    if (q && THEME_CSS[q]) return q;
    return 'style-guide';
  }

  function readDark() {
    var mode = cookie('color-mode'); // dark | light | system | null
    var p = parentHtml();

    if (p) {
      // Layout sets class="dark" only when color_mode == "dark".
      if (p.classList.contains('dark')) return true;
      if (mode === 'light') return false;
      if (mode === 'dark') return true; // brief race before class paints
      // system / unset → OS preference
    } else {
      if (mode === 'dark') return true;
      if (mode === 'light') return false;
    }

    var q = queryParam('mode');
    if (q === 'dark') return true;
    if (q === 'light') return false;

    try {
      return window.matchMedia('(prefers-color-scheme: dark)').matches;
    } catch (e) {
      return false;
    }
  }

  function ensureThemeLink(slug) {
    var href = THEME_CSS[slug] || THEME_CSS['style-guide'];
    var id = 'twp-theme-css';
    var el = document.getElementById(id);
    if (!el) {
      el = document.createElement('link');
      el.id = id;
      el.rel = 'stylesheet';
      document.head.appendChild(el);
    }
    if (el.getAttribute('href') !== href) {
      el.setAttribute('href', href);
    }
  }

  function applyThemeAttrs(slug, dark) {
    var root = document.documentElement;
    root.setAttribute('data-design-theme', slug);
    root.classList.toggle('dark', !!dark);
    if (!root.classList.contains('h-full')) root.classList.add('h-full');
  }

  function tailwindConfig() {
    // Theme tokens drive palette; utilities re-resolve when CSS vars change.
    var g = function (n, fb) {
      return 'var(--gray-' + n + ', var(--slate-' + n + ', ' + fb + '))';
    };
    return {
      darkMode: 'class',
      theme: {
        extend: {
          colors: {
            indigo: {
              50: 'color-mix(in srgb, var(--brand-blue, #4f46e5) 10%, white)',
              100: 'color-mix(in srgb, var(--brand-blue, #4f46e5) 18%, white)',
              200: 'color-mix(in srgb, var(--brand-blue, #4f46e5) 30%, white)',
              300: 'color-mix(in srgb, var(--brand-blue, #4f46e5) 45%, white)',
              400: 'color-mix(in srgb, var(--brand-blue, #4f46e5) 70%, white)',
              500: 'var(--brand-blue, #6366f1)',
              600: 'var(--brand-blue, #4f46e5)',
              700: 'color-mix(in srgb, var(--brand-blue, #4f46e5) 85%, black)',
              800: 'color-mix(in srgb, var(--brand-blue, #4f46e5) 70%, black)',
              900: 'color-mix(in srgb, var(--brand-blue, #4f46e5) 55%, black)',
              950: 'color-mix(in srgb, var(--brand-blue, #4f46e5) 40%, black)'
            },
            gray: {
              50: g(50, '#f9fafb'),
              100: g(100, '#f3f4f6'),
              200: g(200, '#e5e7eb'),
              300: g(300, '#d1d5db'),
              400: g(400, '#9ca3af'),
              500: g(500, '#6b7280'),
              600: g(600, '#4b5563'),
              700: g(700, '#374151'),
              800: g(800, '#1f2937'),
              900: g(900, '#111827'),
              950: g(950, '#030712')
            },
            red: {
              50: 'color-mix(in srgb, var(--brand-red, #ef4444) 10%, white)',
              100: 'color-mix(in srgb, var(--brand-red, #ef4444) 18%, white)',
              400: 'color-mix(in srgb, var(--brand-red, #ef4444) 75%, white)',
              500: 'var(--brand-red, #ef4444)',
              600: 'var(--brand-red, #dc2626)',
              700: 'color-mix(in srgb, var(--brand-red, #dc2626) 85%, black)',
              800: 'color-mix(in srgb, var(--brand-red, #dc2626) 70%, black)'
            },
            yellow: {
              50: 'color-mix(in srgb, var(--brand-yellow, #eab308) 12%, white)',
              400: 'var(--brand-yellow, #facc15)',
              500: 'var(--brand-yellow, #eab308)',
              800: 'color-mix(in srgb, var(--brand-yellow, #eab308) 55%, black)'
            }
          }
        }
      }
    };
  }

  function ensureTailwind() {
    if (window.tailwind && window.__twpTailwindReady) {
      window.tailwind.config = tailwindConfig();
      return;
    }
    window.tailwind = window.tailwind || {};
    window.tailwind.config = tailwindConfig();
    if (!document.getElementById('twp-tailwind-cdn')) {
      var s = document.createElement('script');
      s.id = 'twp-tailwind-cdn';
      s.src = 'https://cdn.tailwindcss.com';
      s.onload = function () {
        window.__twpTailwindReady = true;
        if (window.tailwind) window.tailwind.config = tailwindConfig();
      };
      document.head.appendChild(s);
    }
  }

  function ensureBridgeCss() {
    if (document.getElementById('twp-bridge-css')) return;
    var l = document.createElement('link');
    l.id = 'twp-bridge-css';
    l.rel = 'stylesheet';
    l.href = '/twp/demo-bridge.css';
    document.head.appendChild(l);
  }

  function syncFromParent() {
    var slug = readTheme();
    var dark = readDark();
    applyThemeAttrs(slug, dark);
    ensureThemeLink(slug);
    ensureTailwind();
    return { slug: slug, dark: dark };
  }

  // ── Interactivity ─────────────────────────────────────────────────────────

  function setSwitch(btn, on) {
    btn.setAttribute('aria-checked', on ? 'true' : 'false');
    // Prefer the sliding knob (first direct span, else first span with translate classes)
    var knob =
      btn.querySelector(':scope > span') ||
      btn.querySelector('span[class*="translate"]') ||
      btn.querySelector('span');
    // Background track
    if (on) {
      btn.classList.add('bg-indigo-600');
      btn.classList.remove('bg-gray-200', 'dark:bg-white/10');
    } else {
      btn.classList.remove('bg-indigo-600');
      btn.classList.add('bg-gray-200');
      // dark:bg-white/10 is a Tailwind variant class — keep it for dark mode off-state
      if (!btn.className.includes('dark:bg-white/10')) btn.classList.add('dark:bg-white/10');
    }
    // Knob translate (common Tailwind patterns)
    if (knob) {
      if (on) {
        knob.classList.add('translate-x-5');
        knob.classList.remove('translate-x-0');
      } else {
        knob.classList.remove('translate-x-5');
        knob.classList.add('translate-x-0');
      }
    }
  }

  function enhanceSwitches(root) {
    root.querySelectorAll('[role="switch"]').forEach(function (btn) {
      if (btn.dataset.twpBound) return;
      btn.dataset.twpBound = '1';
      btn.addEventListener('click', function (e) {
        e.preventDefault();
        var on = btn.getAttribute('aria-checked') === 'true';
        setSwitch(btn, !on);
      });
      btn.addEventListener('keydown', function (e) {
        if (e.key === ' ' || e.key === 'Enter') {
          e.preventDefault();
          btn.click();
        }
      });
    });
  }

  function enhanceCheckboxToggles(root) {
    // group/has-checked toggles: ensure the wrapping control toggles the input
    root.querySelectorAll('.group').forEach(function (group) {
      var input = group.querySelector(':scope > input[type="checkbox"]');
      if (!input || group.dataset.twpBound) return;
      // Already natively clickable if input covers area; ensure label behavior
      group.dataset.twpBound = '1';
      group.addEventListener('click', function (e) {
        if (e.target === input) return; // native
        if (e.target.closest('a,button')) return;
        e.preventDefault();
        input.checked = !input.checked;
        input.dispatchEvent(new Event('change', { bubbles: true }));
      });
    });
  }

  function enhanceTabs(root) {
    root.querySelectorAll('[role="tablist"], nav[aria-label="Tabs"]').forEach(function (list) {
      if (list.dataset.twpBound) return;
      list.dataset.twpBound = '1';
      var tabs = list.querySelectorAll('[role="tab"], a');
      tabs.forEach(function (tab) {
        tab.addEventListener('click', function (e) {
          if (tab.tagName === 'A') e.preventDefault();
          tabs.forEach(function (t) {
            t.setAttribute('aria-current', 'false');
            t.setAttribute('aria-selected', 'false');
            // underline pattern
            t.classList.remove('border-indigo-500', 'text-indigo-600', 'dark:text-indigo-400');
            t.classList.add('border-transparent', 'text-gray-500');
            // pill pattern
            t.classList.remove('bg-indigo-100', 'text-indigo-700', 'dark:bg-indigo-500/20', 'dark:text-indigo-300');
          });
          tab.setAttribute('aria-current', 'page');
          tab.setAttribute('aria-selected', 'true');
          tab.classList.add('border-indigo-500', 'text-indigo-600', 'dark:text-indigo-400');
          tab.classList.remove('border-transparent', 'text-gray-500');
          if (tab.className.indexOf('rounded-md') !== -1 || tab.className.indexOf('rounded-t-md') !== -1) {
            tab.classList.add('bg-indigo-100', 'text-indigo-700', 'dark:bg-indigo-500/20', 'dark:text-indigo-300');
          }
        });
      });
    });
  }

  function isOpenTrigger(btn) {
    if (btn.hasAttribute('data-twp-open')) return true;
    var t = (btn.textContent || '').replace(/\s+/g, ' ').trim().toLowerCase();
    return (
      t === 'open drawer' ||
      t === 'open dialog' ||
      t === 'open modal' ||
      t.indexOf('open drawer') === 0 ||
      t.indexOf('open dialog') === 0 ||
      t === 'open demo'
    );
  }

  function isCloseTrigger(btn) {
    if (btn.hasAttribute('data-twp-close')) return true;
    var t = (btn.textContent || '').replace(/\s+/g, ' ').trim().toLowerCase();
    var sr = btn.querySelector('.sr-only');
    var srT = sr ? (sr.textContent || '').toLowerCase() : '';
    var al = (btn.getAttribute('aria-label') || '').toLowerCase();
    return (
      t === 'close' ||
      t === 'cancel' ||
      t === 'save' ||
      t === 'got it' ||
      t === 'deactivate' ||
      t === 'go back to dashboard' ||
      srT.indexOf('close') !== -1 ||
      al === 'close' ||
      al === 'close panel'
    );
  }

  function enhanceOverlays(root) {
    // Prefer explicit demos rebuilt with data-twp-* hooks
    var hosts = Array.prototype.slice.call(
      root.querySelectorAll('.twp-overlay-demo, [data-twp-kind]')
    );

    // Legacy: relative min-height containers that already show a panel
    root.querySelectorAll('.twp-root .relative.min-h-\\[28rem\\], .twp-root .relative').forEach(function (el) {
      if (hosts.indexOf(el) !== -1) return;
      if (el.querySelector('[data-twp-layer], .twp-overlay-layer, [role="dialog"]')) {
        hosts.push(el);
      }
    });

    hosts.forEach(function (host) {
      if (host.dataset.twpOverlayBound) return;
      host.dataset.twpOverlayBound = '1';
      host.classList.add('twp-overlay-host');
      if (!host.hasAttribute('data-open')) host.setAttribute('data-open', 'true');

      var layer =
        host.querySelector(':scope > [data-twp-layer]') ||
        host.querySelector(':scope > .twp-overlay-layer');

      // Legacy markup: wrap everything except open triggers into a layer
      if (!layer) {
        layer = document.createElement('div');
        layer.setAttribute('data-twp-layer', '');
        layer.className = 'twp-overlay-layer';
        var nodes = Array.prototype.slice.call(host.childNodes);
        nodes.forEach(function (n) {
          if (n.nodeType === 1 && isOpenTrigger(n)) return;
          if (n.nodeType === 1 && n.matches && n.matches('button') && isOpenTrigger(n)) return;
          layer.appendChild(n);
        });
        // Re-find open buttons still in host
        host.appendChild(layer);
      }

      function open() {
        host.setAttribute('data-open', 'true');
      }
      function close() {
        host.setAttribute('data-open', 'false');
      }

      // Open triggers (explicit + "Open drawer" buttons)
      host.querySelectorAll('button, [role="button"]').forEach(function (btn) {
        if (!isOpenTrigger(btn)) return;
        // open triggers live outside the layer or inside host
        btn.addEventListener('click', function (e) {
          e.preventDefault();
          e.stopPropagation();
          open();
        });
      });

      // Close triggers
      host.querySelectorAll('button, [role="button"]').forEach(function (btn) {
        if (isOpenTrigger(btn)) return;
        if (!isCloseTrigger(btn)) return;
        btn.addEventListener('click', function (e) {
          e.preventDefault();
          e.stopPropagation();
          close();
        });
      });

      // Backdrop
      host.querySelectorAll('[data-twp-backdrop]').forEach(function (backdrop) {
        backdrop.style.cursor = 'pointer';
        backdrop.addEventListener('click', function (e) {
          if (e.target === backdrop) close();
        });
      });
    });
  }

  function enhanceDropdowns(root) {
    root.querySelectorAll('.relative.inline-block').forEach(function (wrap) {
      var btn = wrap.querySelector(':scope > button');
      var menu = wrap.querySelector(':scope > div.absolute, :scope > div[class*="absolute"]');
      if (!btn || !menu || wrap.dataset.twpBound) return;
      wrap.dataset.twpBound = '1';
      // Start open for design review, but allow toggle
      menu.dataset.twpMenu = '1';
      btn.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        var hidden = menu.style.display === 'none';
        menu.style.display = hidden ? '' : 'none';
      });
    });
  }

  function enhanceAll() {
    var root = document.querySelector('.twp-root') || document.body;
    enhanceSwitches(root);
    enhanceCheckboxToggles(root);
    enhanceTabs(root);
    enhanceOverlays(root);
    enhanceDropdowns(root);
  }

  function observeParent() {
    var p = parentHtml();
    if (!p || typeof MutationObserver === 'undefined') return;
    var last = readTheme() + '|' + readDark();
    var obs = new MutationObserver(function () {
      var next = readTheme() + '|' + readDark();
      if (next !== last) {
        last = next;
        syncFromParent();
      }
    });
    obs.observe(p, { attributes: true, attributeFilter: ['class', 'data-design-theme'] });

    // Also poll lightly — Hologram may replace nodes without attr mutation on cookie-only paths
    setInterval(function () {
      var next = readTheme() + '|' + readDark();
      if (next !== last) {
        last = next;
        syncFromParent();
      }
    }, 800);
  }

  // Boot (runs in <head> or at end of body)
  ensureBridgeCss();
  syncFromParent();
  observeParent();

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', enhanceAll);
  } else {
    enhanceAll();
  }

  // Expose for debugging
  window.TwpDemoBridge = {
    sync: syncFromParent,
    enhance: enhanceAll,
    readTheme: readTheme,
    readDark: readDark
  };
})();
