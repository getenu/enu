// Smoke test for the JS backend under a bare JS engine (jsc): a minimal fake
// DOM, then the compiled app, then clicks. Not a real browser check.
function El(tag) { this.tag = tag; this.children = []; this.textContent = ""; this.listeners = {}; this.attrs = {}; }
El.prototype.appendChild = function (c) { c.parentNode = this; this.children.push(c); return c; };
El.prototype.removeChild = function (c) { this.children = this.children.filter(x => x !== c); };
El.prototype.setAttribute = function (k, v) { this.attrs[k] = v; };
El.prototype.addEventListener = function (t, f) { this.listeners[t] = f; };
const byId = {};
var document = {
  body: {},
  querySelector(sel) { return byId[sel] || (byId[sel] = new El("div")); },
  createElement(tag) { return new El(tag); },
};
