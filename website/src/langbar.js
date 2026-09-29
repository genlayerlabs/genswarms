// The suggestion bar (playbook §5). It only offers; it never redirects. If the browser prefers a language this page
// has a version in, one dismissible line in that language links to it. A dismissal or an explicit choice (the header
// picker, the footer links, the bar's own link) is remembered on this browser, and the bar stays away after that.
// Crawlers and headless browsers never see it. Traditional Chinese readers are never offered Simplified Chinese.
// Its strings come from the catalogue, in the <script type="application/json" id="langbar"> block above.
(function () {
  var KEY = 'gs-lang', here = document.documentElement.lang;
  function get() { try { return localStorage.getItem(KEY); } catch (e) { return null; } }
  function set(v) { try { localStorage.setItem(KEY, v); } catch (e) {} }
  var pick = document.querySelector('details.lang');
  document.addEventListener('click', function (e) {
    var a = e.target.closest && e.target.closest('.lang a[hreflang], .foot-langs a[hreflang], .langbar a[hreflang]');
    if (a) set(a.getAttribute('hreflang'));
    if (pick && pick.open && !pick.contains(e.target)) pick.open = false;
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && pick && pick.open) { pick.open = false; pick.querySelector('summary').focus(); }
  });

  var data = document.getElementById('langbar');
  if (!data || get() || /bot|crawl|spider|slurp|lighthouse|headless/i.test(navigator.userAgent)) return;
  var S = JSON.parse(data.textContent);
  // the first browser language we have a version for; zh-TW, zh-HK, zh-MO and zh-Hant never get Simplified
  var prefs = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || ''];
  // (a Traditional tag anywhere in the list rules out Simplified, even after a bare "zh")
  var want = null, hant = false;
  for (var j = 0; j < prefs.length; j++) if (/^zh-(tw|hk|mo|hant)/i.test(String(prefs[j]))) hant = true;
  for (var i = 0; i < prefs.length && !want; i++) {
    var p = String(prefs[i]).toLowerCase();
    if (/^zh/.test(p) && hant) continue;
    var c = /^zh/.test(p) ? 'zh-Hans' : p.split('-')[0];
    if (S[c]) want = c;
  }
  if (!want || want === here) return;

  var s = S[want], bar = document.createElement('div');
  bar.className = 'langbar';
  bar.lang = want;
  var line = document.createElement('p'), a = document.createElement('a'), x = document.createElement('button');
  line.appendChild(document.createTextNode(s.msg + ' '));
  a.href = s.href; a.hreflang = want; a.textContent = s.go;
  line.appendChild(a);
  x.type = 'button'; x.setAttribute('aria-label', s.close); x.textContent = '\u00d7';
  // the bar floats over the bottom of the screen: it never pushes the page down as it appears (no layout shift)
  x.addEventListener('click', function () { set(here); bar.parentNode.removeChild(bar); });
  bar.appendChild(line); bar.appendChild(x);
  document.body.appendChild(bar);
})();
