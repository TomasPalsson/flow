# React View Transitions

Native browser view transitions driven from React with the `<ViewTransition>` component. Load this when animating route changes, shared-element morphs, list reorders, or Suspense reveals in React or Next.js.

## Required React version and channel

`<ViewTransition>` is not in stable React. Check the channel before writing any code, or the component imports as undefined or does nothing.

- **Next.js App Router:** works with no setup. The App Router bundles a React canary internally. Do not install `react@canary` and do not add the old `experimental.viewTransition` flag. `npm ls react` may show a stable-looking version; that is expected.
- **Vite or any other setup:** install `react@canary react-dom@canary`. Unsupported browsers skip the animation and show the normal update.
- **`transitionTypes` on `<Link>`:** needs Next.js 16.2.0 or later. If `grep -r "transitionTypes" node_modules/next/dist/` finds nothing, use `startTransition` with `addTransitionType` and `router.push()` instead.

Before adding any transition, say what it communicates (going deeper, same item rearranged, data arrived). If there is no answer, leave it out; this is the same test as the "should it animate" question in [decision-framework.md](decision-framework.md).

## How a transition fires

- The state change must run inside `startTransition` (or `useDeferredValue`, or a Suspense reveal). A bare `viewTransitionName` only isolates an element; it does not start a React view transition.
- Use `startTransition`, not `flushSync`; `flushSync` skips the animation.
- Updates during a running animation are batched, so A to B to C to D plays as B to D.
- Respect reduced motion in the CSS that styles the `::view-transition-*` pseudo-elements.

## Boundary placement

- Put `<ViewTransition>` before any DOM node in the subtree it wraps.
- React only measures boundaries that are direct children of nodes along the changed path. A boundary buried under an extra wrapper element never activates. Place it as a direct sibling of the content that changes.
- Keep route boundaries in pages, not in a layout wrapping `{children}`. A nested boundary skips its own enter and exit when it mounts or unmounts together with a parent boundary.
- Names must be globally unique: `name={`hero-${item.id}`}`. Two boundaries with the same name at once is an error.
- Use `key` with a stable `name` and `share` for a real identity change. Omit `key` for crossfades between tabs and panels.

## `default="none"` versus `update`

A bare `<ViewTransition>` crossfades on every trigger, so unrelated content dissolves. Set `default="none"` and opt in only to the triggers this boundary should handle (`enter`, `exit`, `share`, `update`).

`default="none"` also turns off `update`. That is right for named shared elements and wrong for a section that should glide when content above it changes; leave those bare or set `update="auto"`.

An element that must not animate with its parent needs a real `view-transition-name`. `view-transition-name: none` is the CSS default and does nothing, so the element stays in the root snapshot.

## Next.js wiring

- Directional slides: `<Link href=... transitionTypes={['nav-forward']}>`, or `addTransitionType('nav-forward')` inside `startTransition` before `router.push()`.
- Use type-keyed props for navigation: `enter={{ 'nav-forward': 'slide-in', default: 'none' }}`. A type-keyed object always needs a `default` key.
- `router.back()` and browser back/forward carry no types, so type-keyed maps resolve to `default`. Use `router.push()` for typed animations.
- A Suspense reveal resolves in its own transition without navigation types. Give it plain string `enter`/`exit` props, not a type map.
- If the destination content sits behind an unresolved Suspense boundary, the route transition animates the fallback instead. Prefetch the route (`prefetch={true}`) and cache its data. Verify in a production build with a cold client cache; dev mode does not prefetch.
- Skip hash fragments in the navigation; they cause scroll jumps. Scroll programmatically afterwards.

## Troubleshooting

These failures are silent, so check the list before concluding the API is broken.

| Symptom | Cause and fix |
|---|---|
| Nothing animates | Boundary not before a DOM node, update not inside `startTransition`, or boundary not a direct child of the changed path |
| Only updates animate, no enter or exit | Without `<Suspense>`, swaps count as updates. Render the boundary itself conditionally, or wrap in `<Suspense>` |
| Unrelated content crossfades | Bare boundary. Add `default="none"` |
| Shared morph does not fire | `share` resolved to `none`: `default="none"` with no explicit `share`, or a type-keyed `share` and the navigation never added the type |
| Shared morph fights a page fade | A fading page exit dissolves the source mid-morph. Remove that exit |
| Enter animation runs though the fallback never showed | Put a host DOM element directly outside `Suspense` at that call site |
| Section below a list jumps instead of gliding | It is outside an activated boundary, has `default="none"`, or is not an immediate sibling of the changing content |
| Open popover flickers when a transition settles | It was captured in the root snapshot. Give it a real name and isolate it |
| Popover closes when clicked mid-transition | Named elements are skipped by hit-testing during a transition. Portal the popover |
| List reorder does not animate with `useOptimistic` | Optimistic values resolve before the snapshot. Order the list from committed state |
| Same-route content ignores `update` | A nested boundary owns the mutation. Use `key` with a stable `name` and `share` |
| Scrolling hangs during the animation | Browser limit: the overlay is fixed and does not scroll. Keep reveals short |
| Border radius lost, backdrop blur flickers | Apply `border-radius` to the captured element; use a backdrop-blur workaround |
| Skeleton controls slide away | Give the skeleton and the real control the same `viewTransitionName` |

Fixed-size lists need no morph at all: pad them to a constant slot count so nothing below moves (see [decision-framework.md](decision-framework.md)).

Credit: adapted from vercel-labs/agent-skills react-view-transitions @ 063bee9 (MIT).
