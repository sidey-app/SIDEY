# SIDEY website

The public SIDEY website is an Astro static site deployed under
`https://sidey-app.github.io/SIDEY/`.

```sh
cd website
pnpm install --frozen-lockfile
pnpm run dev
```

- `src/pages/`: page sources; localized public routes live under `/ko/`,
  `/en/`, and `/ja/`. The root and every locale-neutral counterpart of a localized public
  route detect the browser language and redirect to the matching localized
  route.
- `src/styles/styles.scss`: shared SCSS entry point. Component-level rules are
  split into Sass partials in `src/styles/` and compiled together by Astro.
- `public/`: client-side JavaScript, images, and other files copied as-is.
- `dist/`: generated build output; do not commit it.

Run `pnpm build` before submitting website changes to validate the Astro build.

Checkout uses the Spring API configured at build time with
`PUBLIC_SIDEY_API_BASE_URL` (default `https://api.sidey.app/api`). The value must
be an HTTPS `/api` base, or loopback HTTP for local tests. Its exact origin is
included in checkout's Content Security Policy. URL query parameters cannot
override the API destination. Configure the server's `SIDEY_WEBSITE_URL` with
the deployed site base and `SIDEY_WEBSITE_ORIGIN` with its exact origin.

Run `pnpm --dir website test` from the repository root to build the site and run
catalog, checkout, consent, redirect and payment-result contract tests. Checkout
tests use deterministic provider responses and do not initiate real payments.

`pnpm --dir website test:browser` checks checkout and result interaction at
1280px and 390px with headless Chrome, including unavailable-provider handling.
Set `CHROME_BIN` to the Chrome executable if it is not installed at the default
macOS path. Browser payment responses are fixtures; no provider charge occurs.
Screenshots are written to a temporary directory printed by the runner.
