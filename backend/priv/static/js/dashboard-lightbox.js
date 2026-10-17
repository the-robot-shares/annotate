/*
 * Dashboard lightbox for inbox attachment thumbnails (delegated listener).
 *
 * Clicks on any `a[data-lightbox]` (inbox thumbnails) open the target image in
 * a fixed overlay instead of a new tab; the anchor still works as a plain link
 * if JS is off. One document-level listener, registered once per page —
 * Hologram re-renders the panel freely without re-binding anything.
 * Overlay lives on <body>, outside the Hologram-managed root.
 */
(function () {
  'use strict';
  if (window.__annotateLightbox) return;
  window.__annotateLightbox = true;

  var overlay = null;
  var img = null;
  var caption = null;
  var lastFocus = null;

  function ensureOverlay() {
    if (overlay) return;

    overlay = document.createElement('div');
    overlay.className = 'dsh-lightbox';
    overlay.hidden = true;

    img = document.createElement('img');
    img.alt = '';
    caption = document.createElement('p');
    caption.className = 'dsh-lightbox__caption';
    caption.setAttribute('role', 'status');

    var close = document.createElement('button');
    close.type = 'button';
    close.className = 'dsh-lightbox__close';
    close.setAttribute('aria-label', 'Close image');
    close.textContent = '×';

    overlay.appendChild(img);
    overlay.appendChild(caption);
    overlay.appendChild(close);
    document.body.appendChild(overlay);

    overlay.addEventListener('click', function (e) {
      // Backdrop or close button dismisses; the image itself stays open.
      if (e.target === overlay || e.target === close) hide();
    });
  }

  function show(src, alt) {
    ensureOverlay();
    lastFocus = document.activeElement;
    img.src = src;
    img.alt = alt || 'Attachment';
    caption.textContent = alt || '';
    caption.hidden = !alt;
    overlay.hidden = false;
    overlay.querySelector('.dsh-lightbox__close').focus();
    document.addEventListener('keydown', onKey);
  }

  function hide() {
    if (!overlay) return;
    overlay.hidden = true;
    img.src = '';
    document.removeEventListener('keydown', onKey);
    if (lastFocus && typeof lastFocus.focus === 'function') lastFocus.focus();
    lastFocus = null;
  }

  function onKey(e) {
    if (e.key === 'Escape') hide();
  }

  document.addEventListener('click', function (e) {
    var anchor = e.target.closest ? e.target.closest('a[data-lightbox]') : null;
    if (!anchor) return;
    e.preventDefault();
    show(anchor.href, anchor.getAttribute('aria-label'));
  });
})();
