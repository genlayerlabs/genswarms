(function () {
  var root = document.documentElement;
  var mqW = matchMedia('(min-width: 1000px) and (min-height: 600px) and (orientation: landscape)');
  var mqR = matchMedia('(prefers-reduced-motion: reduce)');
  var stage = document.querySelector('.sys.live');
  var steps = Array.prototype.slice.call(document.querySelectorAll('.step'));
  var rail = Array.prototype.slice.call(document.querySelectorAll('.rail button'));

  function current() {
    var line = innerHeight * 0.46, best = 0;
    for (var i = 0; i < steps.length; i++) if (steps[i].getBoundingClientRect().top <= line) best = i;
    return best;
  }
  function sync() { setStage(current()); }
  function mode() { root.classList.toggle('cine', mqW.matches && !mqR.matches); sync(); }
  mode();
  [mqW, mqR].forEach(function (m) { (m.addEventListener ? m.addEventListener('change', mode) : m.addListener(mode)); });
  addEventListener('load', sync);
  addEventListener('resize', sync, { passive: true });
  // fallback for the gap between load and a still-animating fragment/restored scroll
  // (e.g. a deep link's smooth scroll), and for engines without IntersectionObserver:
  // keep syncing on scroll, throttled to one check per frame.
  var ticking = false;
  addEventListener('scroll', function () {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(function () { sync(); ticking = false; });
  }, { passive: true });

  function setStage(k) {
    steps[k].classList.add('seen');
    if (stage.getAttribute('data-s') === String(k)) return;
    stage.setAttribute('data-s', k);
    var still = steps[k].querySelector('figure.still');
    stage.setAttribute('aria-label', still.querySelector('svg').getAttribute('aria-label'));
    rail.forEach(function (b, i) { if (i === k) b.setAttribute('aria-current', 'step'); else b.removeAttribute('aria-current'); });
  }

  if ('IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { if (e.isIntersecting) setStage(+e.target.getAttribute('data-step')); });
    }, { rootMargin: '-46% 0px -52% 0px' });
    steps.forEach(function (s) { io.observe(s); });
  }

  rail.forEach(function (b) {
    b.addEventListener('click', function () {
      var k = +b.getAttribute('data-go');
      steps[k].scrollIntoView({ behavior: mqR.matches ? 'auto' : 'smooth', block: 'start' });
    });
  });

  var copy = document.getElementById('copy');
  var promptEl = document.getElementById('prompt');
  if (copy) copy.addEventListener('click', function () {
    var idle = copy.getAttribute('data-idle');
    var done = function () { copy.textContent = copy.getAttribute('data-copied'); setTimeout(function () { copy.textContent = idle; }, 1800); };
    var fallback = function () {
      var r = document.createRange();
      r.selectNodeContents(promptEl);
      var sel = getSelection();
      sel.removeAllRanges();
      sel.addRange(r);
      copy.textContent = copy.getAttribute('data-fallback');
      setTimeout(function () { copy.textContent = idle; }, 1800);
    };
    if (navigator.clipboard) navigator.clipboard.writeText(promptEl.textContent).then(done, fallback);
    else fallback();
  });
})();
