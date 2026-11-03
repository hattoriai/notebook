# Publishing

Any page can be published for anyone to read, signed in or not, and any folder can be published as a blog with a feed. See "Publish" in the [tour](tour.md). This guide is about reading them at an address of your own.

Published pages are read at `/<handle>/<slug>` (a blog's posts at `/<handle>/<blog>/<slug>`, its feed at `/<handle>/<blog>/feed.xml`), never with an `@`. One person's notebook may drop the handle (`/<slug>`). Pages may also be read at another address of yours, under a prefix:

```elixir
# config/runtime.exs, or NOTEBOOK_PUBLISH_URL, NOTEBOOK_PUBLISH_PREFIX,
# NOTEBOOK_PUBLISH_PATHS=solo and NOTEBOOK_SITE_NAME in production
config :notebook, :publishing,
  url: "https://hattori.ai",   # where readers read (the notebook's own by default)
  prefix: "/libs",             # what your proxy sends to the notebook ("" by default)
  paths: :people,              # /libs/hanzo/kotoba; :solo for /libs/kotoba
  name: "Hattori"              # the site's name, in the pages and the feeds
```

Only a page's HTML needs to go through your site. Its styles, scripts, files and live socket come from the notebook's own address, which takes your site as an origin. With the notebook at `notebook.hattori.ai`, this Cloudflare Worker on `hattori.ai` serves `hattori.ai/libs/*` from it:

```js
export default {
  async fetch(request) {
    const url = new URL(request.url)
    if (url.pathname === "/libs" || url.pathname.startsWith("/libs/")) {
      url.hostname = "notebook.hattori.ai"
      return fetch(new Request(url, request))
    }
    return fetch(request)
  },
}
```

The same pages are at `notebook.hattori.ai/libs/...` too, and their links, canonical addresses and feeds say `hattori.ai/libs/...`.
