/* Canopy OS · charts drawn in plain SVG, no library (D-020): bars, a line, a donut, horizontal bars and a legend.
   Each chart is drawn at its box's real pixel width, so text keeps its size on a tablet and on a wide screen.
   Usage: HG_CHARTS.box(function (W) { return HG_CHARTS.bar([series], labels, colors, 220, W); }) returns a placeholder;
   HG_CHARTS.mount(root) draws every placeholder inside root. HG_CHARTS.money(fn) sets the money formatter. */
(function () {
  'use strict';
  var esc = function (s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };
  var money = function (v) { return String(Math.round(v)); };
  var kfmt = function (v) {
    var a = Math.abs(v);
    if (a >= 1e6) return (v / 1e6).toLocaleString('fr-FR', { maximumFractionDigits: 1 }) + ' M';
    if (a >= 1e3) return Math.round(v / 1e3) + ' k';
    return String(Math.round(v));
  };
  var CH = { l: 56, r: 24, t: 12, b: 26 };
  function niceMax(v) { if (v <= 0) return 1; var p = Math.pow(10, Math.floor(Math.log10(v))); var m = v / p; var n = m <= 1 ? 1 : m <= 2 ? 2 : m <= 2.5 ? 2.5 : m <= 5 ? 5 : 10; return n * p; }
  function sum(arr, f) { return arr.reduce(function (s, x) { return s + (f ? f(x) : x); }, 0); }

  var DRAW = {}, seq = 0;
  function box(draw, extraClass) { var id = 'ch' + (++seq); DRAW[id] = draw; return '<div class="chartbox' + (extraClass ? ' ' + extraClass : '') + '" data-chart="' + id + '"></div>'; }
  function mount(root) {
    Array.prototype.forEach.call((root || document).querySelectorAll('[data-chart]'), function (el) {
      var f = DRAW[el.dataset.chart]; if (!f) return;
      var w = Math.max(240, el.clientWidth || 600);
      el.innerHTML = f(w);
    });
  }
  var rt = null;
  window.addEventListener('resize', function () { clearTimeout(rt); rt = setTimeout(function () { mount(document); }, 150); });

  /* grouped bars: series = [[v,v,…], …], one group per label */
  function bar(series, labels, colors, h, W, unit) {
    var H = h || 220, iw = W - CH.l - CH.r, ih = H - CH.t - CH.b, lab = unit || kfmt;
    var all = [].concat.apply([], series).concat([1]), max = niceMax(Math.max.apply(null, all));
    var g = Math.max(1, labels.length), gw = iw / g, bw = Math.max(4, Math.min(28, (gw * 0.7) / Math.max(1, series.length)));
    var s = '<svg class="chart" viewBox="0 0 ' + W + ' ' + H + '" width="' + W + '" height="' + H + '" role="img" aria-label="Chart">';
    for (var i = 0; i <= 4; i++) { var y = CH.t + ih - (ih * i) / 4; s += '<line x1="' + CH.l + '" x2="' + (W - CH.r) + '" y1="' + y + '" y2="' + y + '" stroke="var(--grid)"/><text x="' + (CH.l - 8) + '" y="' + (y + 4) + '" text-anchor="end" font-size="11" fill="var(--sec)" font-family="var(--mono)">' + esc(lab((max * i) / 4)) + '</text>'; }
    var every = Math.ceil(g / Math.max(3, Math.floor(iw / 70)));
    labels.forEach(function (lb, gi) {
      var x0 = CH.l + gi * gw + (gw - bw * series.length) / 2;
      series.forEach(function (ser, si) { var v = Math.max(0, ser[gi] || 0), bh = (ih * v) / max; s += '<rect x="' + (x0 + si * bw + 1) + '" y="' + (CH.t + ih - bh) + '" width="' + (bw - 2) + '" height="' + bh + '" rx="3" fill="' + colors[si] + '"><title>' + esc(lb) + ': ' + esc(unit ? unit(v) : money(v)) + '</title></rect>'; });
      if ((g - 1 - gi) % every === 0) s += '<text x="' + (CH.l + gi * gw + gw / 2) + '" y="' + (H - 8) + '" text-anchor="middle" font-size="11" fill="var(--sec)" data-no-translate>' + esc(lb) + '</text>';
    });
    return s + '</svg>';
  }
  /* one line, optionally filled; negative values allowed */
  function line(vals, labels, color, h, fill, W) {
    var H = h || 200, iw = W - CH.l - CH.r, ih = H - CH.t - CH.b;
    var lo = Math.min.apply(null, [0].concat(vals)), hi = Math.max.apply(null, [0].concat(vals)), max = hi > 0 ? niceMax(hi) : (lo < 0 ? 0 : 1), min = lo < 0 ? -niceMax(-lo) : 0, span = max - min || 1;
    var n = Math.max(1, vals.length - 1);
    var X = function (i) { return CH.l + (iw * i) / n; }, Y = function (v) { return CH.t + ih - (ih * (v - min)) / span; };
    var s = '<svg class="chart" viewBox="0 0 ' + W + ' ' + H + '" width="' + W + '" height="' + H + '" role="img" aria-label="Chart">';
    for (var i = 0; i <= 4; i++) { var v = min + (span * i) / 4, y = Y(v); s += '<line x1="' + CH.l + '" x2="' + (W - CH.r) + '" y1="' + y + '" y2="' + y + '" stroke="var(--grid)"/><text x="' + (CH.l - 8) + '" y="' + (y + 4) + '" text-anchor="end" font-size="11" fill="var(--sec)" font-family="var(--mono)">' + esc(kfmt(v)) + '</text>'; }
    if (!vals.length) return s + '</svg>';
    var pts = vals.map(function (v, i) { return X(i) + ',' + Y(v); }).join(' ');
    if (fill) s += '<polygon points="' + X(0) + ',' + Y(0) + ' ' + pts + ' ' + X(vals.length - 1) + ',' + Y(0) + '" fill="' + color + '" opacity=".12"/>';
    s += '<polyline points="' + pts + '" fill="none" stroke="' + color + '" stroke-width="2.2" stroke-linejoin="round"/>';
    vals.forEach(function (v, i) { if (i === vals.length - 1 || vals.length <= 14) s += '<circle cx="' + X(i) + '" cy="' + Y(v) + '" r="' + (i === vals.length - 1 ? 5 : 3.5) + '" fill="' + color + '" stroke="var(--panel)" stroke-width="2"><title>' + esc(labels[i]) + ': ' + esc(money(v)) + '</title></circle>'; });
    var step = Math.ceil(labels.length / Math.max(3, Math.floor(iw / 70)));
    labels.forEach(function (lb, i) { if ((labels.length - 1 - i) % step === 0) s += '<text x="' + X(i) + '" y="' + (H - 8) + '" text-anchor="middle" font-size="11" fill="var(--sec)" data-no-translate>' + esc(lb) + '</text>'; });
    return s + '</svg>';
  }
  /* parts = [[label, value], …] */
  function donut(parts, colors) {
    var total = sum(parts, function (p) { return Math.max(0, p[1]); }) || 1, a = -Math.PI / 2, R = 54, r = 34, cx = 70, cy = 70;
    var s = '<svg viewBox="0 0 140 140" width="140" height="140" role="img" aria-label="Chart" style="flex:none">';
    parts.forEach(function (p, i) {
      var f = Math.max(0, p[1]) / total; if (f <= 0) return;
      if (f >= 0.9999) { s += '<circle cx="' + cx + '" cy="' + cy + '" r="' + ((R + r) / 2) + '" fill="none" stroke="' + colors[i] + '" stroke-width="' + (R - r) + '"><title>' + esc(p[0]) + ': 100 %</title></circle>'; return; }
      var b = a + f * Math.PI * 2;
      var x1 = cx + R * Math.cos(a), y1 = cy + R * Math.sin(a), x2 = cx + R * Math.cos(b), y2 = cy + R * Math.sin(b), x3 = cx + r * Math.cos(b), y3 = cy + r * Math.sin(b), x4 = cx + r * Math.cos(a), y4 = cy + r * Math.sin(a);
      var L = f > 0.5 ? 1 : 0;
      s += '<path d="M' + x1 + ',' + y1 + ' A' + R + ',' + R + ' 0 ' + L + ',1 ' + x2 + ',' + y2 + ' L' + x3 + ',' + y3 + ' A' + r + ',' + r + ' 0 ' + L + ',0 ' + x4 + ',' + y4 + 'Z" fill="' + colors[i] + '" stroke="var(--panel)" stroke-width="2"><title>' + esc(p[0]) + ': ' + Math.round(f * 100) + ' %</title></path>';
      a = b;
    });
    return s + '</svg>';
  }
  /* items = [[label, value], …] as horizontal bars with the value at the end */
  function hbars(items, color) {
    var max = Math.max.apply(null, [1].concat(items.map(function (i) { return i[1]; })));
    return '<div class="list hbars">' + items.map(function (i) {
      return '<li><span class="t" title="' + esc(i[0]) + '">' + esc(i[0]) + '</span><span class="bar"><span style="width:' + Math.round((Math.max(0, i[1]) / max) * 100) + '%;background:' + color + '"></span></span><span class="mono num">' + esc(money(i[1])) + '</span></li>';
    }).join('') + '</div>';
  }
  function legend(items) { return '<div class="legend">' + items.map(function (i) { return '<span><i style="background:' + i[1] + '"></i>' + esc(i[0]) + '</span>'; }).join('') + '</div>'; }

  window.HG_CHARTS = { box: box, mount: mount, bar: bar, line: line, donut: donut, hbars: hbars, legend: legend, money: function (fn) { money = fn; }, kfmt: kfmt };
})();
