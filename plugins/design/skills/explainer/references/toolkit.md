# Explainer Toolkit: CDN Libraries & Code Patterns

Complete reference for building explainer HTML pages. Read this when you need specific CDN URLs, code snippets, or implementation patterns.

## Table of Contents
1. [CDN Quick Reference](#cdn-quick-reference)
2. [Mermaid.js Diagrams](#mermaidjs-diagrams)
3. [Prism.js Code Highlighting](#prismjs-code-highlighting)
4. [Animation Patterns](#animation-patterns)
5. [Scrollytelling](#scrollytelling)
6. [Interactive Elements](#interactive-elements)
7. [Chart.js Data Visualization](#chartjs-data-visualization)
8. [Dark/Light Theme](#darklight-theme)
9. [Table of Contents Component](#table-of-contents-component)
10. [Progress Bar](#progress-bar)
11. [Typography & Fonts](#typography--fonts)

---

## CDN Quick Reference

| Library | CDN URL | Size | Use For |
|---------|---------|------|---------|
| Mermaid 11 | `https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs` | ~1.5MB (lazy) | Diagrams from text DSL |
| Prism.js core | `https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/prism.min.js` | ~2KB gz | Syntax highlighting |
| Prism Tomorrow theme | `https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/themes/prism-tomorrow.min.css` | ~1KB | Dark code theme |
| Prism line-highlight JS | `https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/plugins/line-highlight/prism-line-highlight.min.js` | ~0.5KB | Line highlighting |
| Prism line-highlight CSS | `https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/plugins/line-highlight/prism-line-highlight.min.css` | ~0.3KB | Line highlight styles |
| Chart.js | `https://cdn.jsdelivr.net/npm/chart.js` | ~60KB gz | Data charts |
| GSAP core | `https://cdnjs.cloudflare.com/ajax/libs/gsap/3.13.0/gsap.min.js` | ~24KB gz | Complex animation |
| GSAP ScrollTrigger | `https://cdnjs.cloudflare.com/ajax/libs/gsap/3.13.0/ScrollTrigger.min.js` | ~14KB gz | Scroll-based animation |
| Anime.js 3 | `https://cdn.jsdelivr.net/npm/animejs@3.2.2/lib/anime.min.js` | ~6KB gz | Lightweight animation |

**Prism language plugins** (add as needed):
```
https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-javascript.min.js
https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-typescript.min.js
https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-python.min.js
https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-bash.min.js
https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-json.min.js
https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-css.min.js
https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-rust.min.js
https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-go.min.js
```

---

## Mermaid.js Diagrams

### Setup (ES module)
```html
<script type="module">
  import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
  mermaid.initialize({
    startOnLoad: true,
    theme: 'base',
    themeVariables: {
      primaryColor: 'var(--diagram-primary, #6366f1)',
      primaryTextColor: 'var(--diagram-text, #f8fafc)',
      primaryBorderColor: 'var(--diagram-border, #818cf8)',
      lineColor: 'var(--diagram-line, #94a3b8)',
      secondaryColor: 'var(--diagram-secondary, #1e293b)',
      tertiaryColor: 'var(--diagram-tertiary, #0f172a)',
      fontFamily: 'inherit',
      fontSize: '14px'
    }
  });
</script>
```

**Important:** Mermaid's `themeVariables` do NOT resolve CSS custom properties at runtime. You need to set actual color values. Use JS to read computed styles if you want to match your CSS theme:

```javascript
const style = getComputedStyle(document.documentElement);
mermaid.initialize({
  startOnLoad: false,
  theme: 'base',
  themeVariables: {
    primaryColor: style.getPropertyValue('--color-primary').trim() || '#6366f1',
    primaryTextColor: style.getPropertyValue('--color-text').trim() || '#f8fafc',
    lineColor: style.getPropertyValue('--color-muted').trim() || '#94a3b8',
    fontFamily: 'inherit'
  }
});
mermaid.run();
```

### Common Diagram Types

**Flowchart:**
```html
<div class="mermaid">
flowchart LR
  A[Input] --> B{Decision}
  B -->|Yes| C[Process A]
  B -->|No| D[Process B]
  C --> E[Output]
  D --> E
</div>
```

**Sequence diagram:**
```html
<div class="mermaid">
sequenceDiagram
  participant C as Client
  participant S as Server
  participant DB as Database
  C->>S: POST /api/data
  activate S
  S->>DB: INSERT query
  activate DB
  DB-->>S: Success
  deactivate DB
  S-->>C: 201 Created
  deactivate S
</div>
```

**Architecture diagram (v11.1+):**
```html
<div class="mermaid">
architecture-beta
  group api(cloud)[API Layer]
    service lb(internet)[Load Balancer] in api
    service app(server)[App Server] in api
  group data(cloud)[Data Layer]
    service db(database)[PostgreSQL] in data
    service cache(database)[Redis] in data
  lb:R --> L:app
  app:R --> L:db
  app:R --> L:cache
</div>
```

**Timeline:**
```html
<div class="mermaid">
timeline
  title Project Evolution
  section Phase 1
    Jan : MVP Launch : Core features shipped
    Feb : Beta Testing : 50 users onboarded
  section Phase 2
    Mar : Public Launch : Open registration
    Apr : Scale : 10k users
</div>
```

**Mindmap:**
```html
<div class="mermaid">
mindmap
  root((Project))
    Frontend
      React
      TypeScript
      Tailwind
    Backend
      Node.js
      PostgreSQL
      Redis
    Infrastructure
      AWS
      Docker
      CI/CD
</div>
```

**Styling Mermaid containers:**
```css
.mermaid {
  display: flex;
  justify-content: center;
  margin: 2rem 0;
  padding: 1.5rem;
  background: var(--color-surface);
  border-radius: 12px;
  border: 1px solid var(--color-border);
  overflow-x: auto;
}
.mermaid svg {
  max-width: 100%;
  height: auto;
}
```

---

## Prism.js Code Highlighting

### Setup
```html
<link href="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/themes/prism-tomorrow.min.css" rel="stylesheet">
<link href="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/plugins/line-highlight/prism-line-highlight.min.css" rel="stylesheet">
<script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/prism.min.js" defer></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-javascript.min.js" defer></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/plugins/line-highlight/prism-line-highlight.min.js" defer></script>
```

### Basic highlighted code block
```html
<pre data-line="3-5"><code class="language-javascript">
const app = express();
app.use(cors());
app.get('/api/data', async (req, res) => {
  const data = await db.query('SELECT * FROM items');
  res.json(data);
});
app.listen(3000);
</code></pre>
```

### Step-by-step code walkthrough
```html
<div class="walkthrough">
  <div class="walkthrough-steps">
    <button class="step active" data-lines="1-2" data-step="0">
      <span class="step-num">1</span>
      <h4>Setup</h4>
      <p>Import and create the Express app.</p>
    </button>
    <button class="step" data-lines="3-6" data-step="1">
      <span class="step-num">2</span>
      <h4>Route Handler</h4>
      <p>Define the GET endpoint that queries the database.</p>
    </button>
    <button class="step" data-lines="7" data-step="2">
      <span class="step-num">3</span>
      <h4>Listen</h4>
      <p>Start the server on port 3000.</p>
    </button>
  </div>
  <div class="walkthrough-code">
    <pre id="walkthrough-pre" data-line="1-2"><code class="language-javascript">
const app = express();
app.use(cors());
app.get('/api/data', async (req, res) => {
  const data = await db.query('SELECT * FROM items');
  res.json(data);
});
app.listen(3000);
    </code></pre>
  </div>
</div>

<script>
document.querySelectorAll('.walkthrough .step').forEach(btn => {
  btn.addEventListener('click', () => {
    // Update active step
    document.querySelectorAll('.walkthrough .step').forEach(s => s.classList.remove('active'));
    btn.classList.add('active');
    // Update highlighted lines
    const pre = document.getElementById('walkthrough-pre');
    pre.setAttribute('data-line', btn.dataset.lines);
    Prism.plugins.lineHighlight.highlightLines(pre)();
  });
});
</script>
```

### Walkthrough CSS
```css
.walkthrough {
  display: grid;
  grid-template-columns: 1fr 1.5fr;
  gap: 1.5rem;
  margin: 2rem 0;
}
.walkthrough-code {
  position: sticky;
  top: 2rem;
  align-self: start;
}
.walkthrough .step {
  all: unset;
  cursor: pointer;
  display: block;
  padding: 1rem;
  border-left: 3px solid var(--color-border);
  margin-bottom: 0.5rem;
  border-radius: 0 8px 8px 0;
  transition: all 0.2s ease;
}
.walkthrough .step:hover {
  background: var(--color-surface-hover);
}
.walkthrough .step.active {
  border-left-color: var(--color-primary);
  background: var(--color-surface);
}
.step-num {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: 24px;
  border-radius: 50%;
  background: var(--color-primary);
  color: white;
  font-size: 0.75rem;
  font-weight: 600;
  margin-right: 0.5rem;
}
@media (max-width: 768px) {
  .walkthrough { grid-template-columns: 1fr; }
  .walkthrough-code { position: relative; }
}
```

---

## Animation Patterns

### Scroll-reveal (use on every explainer)
```css
.reveal {
  opacity: 0;
  transform: translateY(24px);
  transition: opacity 0.6s ease-out, transform 0.6s ease-out;
}
.reveal.revealed {
  opacity: 1;
  transform: translateY(0);
}
/* Stagger children */
.reveal-group > .reveal:nth-child(1) { transition-delay: 0s; }
.reveal-group > .reveal:nth-child(2) { transition-delay: 0.1s; }
.reveal-group > .reveal:nth-child(3) { transition-delay: 0.15s; }
.reveal-group > .reveal:nth-child(4) { transition-delay: 0.2s; }
.reveal-group > .reveal:nth-child(5) { transition-delay: 0.25s; }
.reveal-group > .reveal:nth-child(6) { transition-delay: 0.3s; }
```

```javascript
function initScrollReveal() {
  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('revealed');
        observer.unobserve(entry.target);
      }
    });
  }, { rootMargin: '0px 0px -60px 0px', threshold: 0.1 });
  document.querySelectorAll('.reveal').forEach(el => observer.observe(el));
}
document.addEventListener('DOMContentLoaded', initScrollReveal);
```

### Hero entrance animation
```css
@keyframes hero-fade-up {
  from { opacity: 0; transform: translateY(32px); }
  to { opacity: 1; transform: translateY(0); }
}
.hero h1 {
  animation: hero-fade-up 0.8s ease-out 0.1s both;
}
.hero .subtitle {
  animation: hero-fade-up 0.8s ease-out 0.3s both;
}
.hero .meta {
  animation: hero-fade-up 0.8s ease-out 0.5s both;
}
```

### Counter animation (for stats/metrics)
```javascript
function animateCounter(el) {
  const target = parseInt(el.dataset.target);
  const duration = 2000;
  const start = performance.now();

  function update(now) {
    const elapsed = now - start;
    const progress = Math.min(elapsed / duration, 1);
    const eased = 1 - Math.pow(1 - progress, 3); // ease-out cubic
    el.textContent = Math.round(eased * target).toLocaleString();
    if (progress < 1) requestAnimationFrame(update);
  }
  requestAnimationFrame(update);
}

// Trigger on scroll
const counterObserver = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      animateCounter(entry.target);
      counterObserver.unobserve(entry.target);
    }
  });
});
document.querySelectorAll('[data-target]').forEach(el => counterObserver.observe(el));
```

```html
<div class="stats reveal-group">
  <div class="stat reveal">
    <span class="stat-value" data-target="42">0</span>
    <span class="stat-label">Files Changed</span>
  </div>
  <div class="stat reveal">
    <span class="stat-value" data-target="1337">0</span>
    <span class="stat-label">Lines Added</span>
  </div>
</div>
```

### Typewriter effect (CSS-only, single line)
```css
.typewriter {
  overflow: hidden;
  border-right: 2px solid var(--color-primary);
  white-space: nowrap;
  animation:
    typing 2s steps(30) 0.5s both,
    blink 0.7s step-end infinite;
  width: 0;
}
@keyframes typing { to { width: 100%; } }
@keyframes blink {
  50% { border-color: transparent; }
}
```

### Pulse / glow effect (for drawing attention)
```css
@keyframes pulse-glow {
  0%, 100% { box-shadow: 0 0 0 0 rgba(99, 102, 241, 0.4); }
  50% { box-shadow: 0 0 0 12px rgba(99, 102, 241, 0); }
}
.highlight-element {
  animation: pulse-glow 2s ease-in-out 3;
}
```

---

## Scrollytelling

For complex multi-step explanations where a visual changes as the reader scrolls.

### Layout
```css
.scrollytelling {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 2rem;
  align-items: start;
  margin: 3rem 0;
}
.scrollytelling .sticky-panel {
  position: sticky;
  top: 2rem;
  height: calc(100vh - 4rem);
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--color-surface);
  border-radius: 12px;
  padding: 2rem;
  border: 1px solid var(--color-border);
}
.scrollytelling .steps {
  padding: 20vh 0; /* breathing room at top/bottom */
}
.scrollytelling .step {
  min-height: 40vh;
  padding: 2rem;
  margin-bottom: 2rem;
  opacity: 0.3;
  transition: opacity 0.4s ease;
}
.scrollytelling .step.active {
  opacity: 1;
}
@media (max-width: 768px) {
  .scrollytelling {
    grid-template-columns: 1fr;
  }
  .scrollytelling .sticky-panel {
    position: relative;
    height: auto;
    margin-bottom: 1rem;
  }
}
```

### Scroll trigger
```javascript
function initScrollytelling() {
  const steps = document.querySelectorAll('.scrollytelling .step');
  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        // Deactivate all steps, activate current
        steps.forEach(s => s.classList.remove('active'));
        entry.target.classList.add('active');
        // Update the sticky panel based on step data
        const stepId = entry.target.dataset.step;
        updateStickyPanel(stepId);
      }
    });
  }, { rootMargin: '-30% 0px -60% 0px' });

  steps.forEach(step => observer.observe(step));
}
```

---

## Interactive Elements

### Toggle/Switch demo
```html
<div class="demo-box">
  <div class="demo-controls">
    <label class="toggle">
      <input type="checkbox" id="demo-toggle">
      <span class="toggle-slider"></span>
      <span>Enable Feature</span>
    </label>
  </div>
  <div class="demo-output" id="demo-output">
    <!-- Visual changes based on toggle state -->
  </div>
</div>
```

### Slider control
```html
<div class="demo-box">
  <label for="speed-slider">Animation Speed: <span id="speed-value">50</span>%</label>
  <input type="range" id="speed-slider" min="0" max="100" value="50">
  <div class="demo-canvas" id="demo-canvas"></div>
</div>

<script>
document.getElementById('speed-slider').addEventListener('input', (e) => {
  document.getElementById('speed-value').textContent = e.target.value;
  // Update the demo visualization
});
</script>
```

### Collapsible detail sections
```html
<details class="faq-item">
  <summary>
    <span class="faq-icon">+</span>
    What about edge case X?
  </summary>
  <div class="faq-content">
    <p>Detailed explanation...</p>
  </div>
</details>
```

```css
details.faq-item {
  border: 1px solid var(--color-border);
  border-radius: 8px;
  margin-bottom: 0.5rem;
  overflow: hidden;
}
details.faq-item summary {
  padding: 1rem 1.5rem;
  cursor: pointer;
  font-weight: 600;
  display: flex;
  align-items: center;
  gap: 0.75rem;
  list-style: none;
}
details.faq-item summary::-webkit-details-marker { display: none; }
details.faq-item[open] .faq-icon { transform: rotate(45deg); }
.faq-icon {
  transition: transform 0.2s ease;
  font-size: 1.25rem;
  color: var(--color-primary);
}
.faq-content {
  padding: 0 1.5rem 1rem;
}
```

---

## Chart.js Data Visualization

```html
<canvas id="myChart" style="max-height: 400px;"></canvas>
<script src="https://cdn.jsdelivr.net/npm/chart.js" defer></script>
<script>
document.addEventListener('DOMContentLoaded', () => {
  const ctx = document.getElementById('myChart');
  new Chart(ctx, {
    type: 'bar',  // 'line', 'pie', 'doughnut', 'radar', 'scatter'
    data: {
      labels: ['Jan', 'Feb', 'Mar', 'Apr', 'May'],
      datasets: [{
        label: 'Requests',
        data: [120, 190, 300, 500, 420],
        backgroundColor: 'rgba(99, 102, 241, 0.5)',
        borderColor: 'rgb(99, 102, 241)',
        borderWidth: 2,
        borderRadius: 6
      }]
    },
    options: {
      responsive: true,
      plugins: {
        legend: { labels: { color: '#94a3b8' } }
      },
      scales: {
        x: { ticks: { color: '#94a3b8' }, grid: { color: '#1e293b' } },
        y: { ticks: { color: '#94a3b8' }, grid: { color: '#1e293b' } }
      }
    }
  });
});
</script>
```

---

## Dark/Light Theme

### CSS custom properties
```css
:root {
  /* Light theme */
  --color-bg: #ffffff;
  --color-text: #1e293b;
  --color-text-muted: #64748b;
  --color-surface: #f8fafc;
  --color-surface-hover: #f1f5f9;
  --color-border: #e2e8f0;
  --color-primary: #6366f1;
  --color-primary-soft: rgba(99, 102, 241, 0.1);
}

[data-theme="dark"] {
  --color-bg: #0f172a;
  --color-text: #f8fafc;
  --color-text-muted: #94a3b8;
  --color-surface: #1e293b;
  --color-surface-hover: #334155;
  --color-border: #334155;
  --color-primary: #818cf8;
  --color-primary-soft: rgba(129, 140, 248, 0.1);
}

body {
  background: var(--color-bg);
  color: var(--color-text);
  transition: background-color 0.3s ease, color 0.3s ease;
}
```

### Theme toggle (JS)
```javascript
function initTheme() {
  const toggle = document.getElementById('theme-toggle');
  const saved = localStorage.getItem('theme');
  const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  const theme = saved || (prefersDark ? 'dark' : 'light');
  document.documentElement.setAttribute('data-theme', theme);

  toggle?.addEventListener('click', () => {
    const current = document.documentElement.getAttribute('data-theme');
    const next = current === 'dark' ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', next);
    localStorage.setItem('theme', next);
  });
}
```

### Theme toggle button
```html
<button id="theme-toggle" class="theme-toggle" aria-label="Toggle theme">
  <svg class="sun-icon" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
    <circle cx="12" cy="12" r="5"/><path d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"/>
  </svg>
  <svg class="moon-icon" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
    <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>
  </svg>
</button>
```

```css
.theme-toggle {
  position: fixed;
  top: 1rem;
  right: 1rem;
  z-index: 100;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: 50%;
  width: 40px;
  height: 40px;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--color-text);
  transition: all 0.2s ease;
}
[data-theme="dark"] .sun-icon { display: none; }
[data-theme="light"] .moon-icon { display: none; }
```

---

## Table of Contents Component

```html
<aside class="toc">
  <nav aria-label="Table of contents">
    <h3>Contents</h3>
    <ol>
      <li><a href="#overview">Overview</a></li>
      <li><a href="#how-it-works">How It Works</a></li>
      <li><a href="#deep-dive">Deep Dive</a></li>
      <li><a href="#summary">Summary</a></li>
    </ol>
  </nav>
</aside>
```

```css
.toc {
  position: sticky;
  top: 2rem;
  align-self: start;
  max-height: calc(100vh - 4rem);
  overflow-y: auto;
  padding: 1rem;
  border-left: 2px solid var(--color-border);
}
.toc ol { list-style: none; padding: 0; margin: 0; }
.toc a {
  display: block;
  padding: 0.4rem 0.75rem;
  color: var(--color-text-muted);
  text-decoration: none;
  font-size: 0.875rem;
  border-radius: 4px;
  transition: all 0.2s ease;
}
.toc a:hover { color: var(--color-text); }
.toc a.active {
  color: var(--color-primary);
  background: var(--color-primary-soft);
  font-weight: 600;
}
```

```javascript
function initToc() {
  const sections = document.querySelectorAll('section[id]');
  const tocLinks = document.querySelectorAll('.toc a');

  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        tocLinks.forEach(l => l.classList.remove('active'));
        const active = document.querySelector(`.toc a[href="#${entry.target.id}"]`);
        active?.classList.add('active');
      }
    });
  }, { rootMargin: '-10% 0px -80% 0px' });

  sections.forEach(s => observer.observe(s));
}
```

---

## Progress Bar

### CSS scroll-driven (Chrome/Edge, progressive enhancement)
```css
.progress-bar {
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  height: 3px;
  background: var(--color-primary);
  transform-origin: left;
  transform: scaleX(0);
  z-index: 1000;
}

/* Modern browsers: pure CSS */
@supports (animation-timeline: scroll()) {
  .progress-bar {
    animation: grow-progress linear;
    animation-timeline: scroll(root);
  }
  @keyframes grow-progress {
    to { transform: scaleX(1); }
  }
}
```

### JS fallback
```javascript
// Only if CSS scroll-driven isn't supported
if (!CSS.supports('animation-timeline', 'scroll()')) {
  const bar = document.querySelector('.progress-bar');
  window.addEventListener('scroll', () => {
    const scrolled = window.scrollY / (document.body.scrollHeight - window.innerHeight);
    bar.style.transform = `scaleX(${scrolled})`;
  }, { passive: true });
}
```

---

## Typography & Fonts

### Google Fonts loading
```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
```

### Type scale
```css
body {
  font-family: 'Inter', system-ui, -apple-system, sans-serif;
  font-size: 1rem;
  line-height: 1.7;
}
code, pre {
  font-family: 'JetBrains Mono', 'Fira Code', monospace;
}
h1 { font-size: clamp(2rem, 5vw, 3.5rem); font-weight: 700; line-height: 1.1; }
h2 { font-size: clamp(1.5rem, 3vw, 2.25rem); font-weight: 600; line-height: 1.2; }
h3 { font-size: clamp(1.25rem, 2.5vw, 1.5rem); font-weight: 600; line-height: 1.3; }

/* Smooth scroll + offset for sticky header */
html { scroll-behavior: smooth; }
section[id] { scroll-margin-top: 5rem; }
```

### Skip link (accessibility)
```css
.skip-link {
  position: absolute;
  top: -100%;
  left: 1rem;
  padding: 0.5rem 1rem;
  background: var(--color-primary);
  color: white;
  border-radius: 4px;
  z-index: 10000;
  text-decoration: none;
}
.skip-link:focus {
  top: 1rem;
}
```
