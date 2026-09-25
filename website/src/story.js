(function () {
  var root = document.documentElement;
  var mqW = matchMedia('(min-width: 1000px)');
  var mqR = matchMedia('(prefers-reduced-motion: reduce)');
  var stage = document.querySelector('.sys.live');
  var steps = Array.prototype.slice.call(document.querySelectorAll('.step'));
  var rail = Array.prototype.slice.call(document.querySelectorAll('.rail button'));
  var figN = document.getElementById('figN');
  var figCap = document.getElementById('figCap');

  function mode() { root.classList.toggle('cine', mqW.matches && !mqR.matches); }
  mode();
  [mqW, mqR].forEach(function (m) { (m.addEventListener ? m.addEventListener('change', mode) : m.addListener(mode)); });

  function setStage(k) {
    steps[k].classList.add('seen');
    if (stage.getAttribute('data-s') === String(k)) return;
    stage.setAttribute('data-s', k);
    stage.setAttribute('aria-label', ARIA[k]);
    figN.textContent = 'Figure ' + (k + 1);
    figCap.textContent = CAPS[k];
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
  if (copy) copy.addEventListener('click', function () {
    var t = document.getElementById('prompt').textContent;
    var done = function () { copy.textContent = 'Copied'; setTimeout(function () { copy.textContent = 'Copy'; }, 1800); };
    if (navigator.clipboard) navigator.clipboard.writeText(t).then(done, function () { copy.textContent = 'Select and copy'; });
  });
})();
