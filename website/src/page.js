(function () {
  var copy = document.getElementById('copy');
  var promptEl = document.getElementById('prompt');
  if (copy) copy.addEventListener('click', function () {
    var idle = copy.getAttribute('data-idle');
    var reset = function () { setTimeout(function () { copy.textContent = idle; }, 1800); };
    var fallback = function () {
      var r = document.createRange();
      r.selectNodeContents(promptEl);
      var sel = getSelection();
      sel.removeAllRanges();
      sel.addRange(r);
      copy.textContent = copy.getAttribute('data-fallback');
      reset();
    };
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(promptEl.textContent).then(function () { copy.textContent = copy.getAttribute('data-copied'); reset(); }, fallback);
      } else fallback();
    } catch (e) { fallback(); }
  });
})();
