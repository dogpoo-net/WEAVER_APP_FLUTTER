# Tile loading recovery (2026-11-19)

All map screens use RegionalTileLayer. flutter_map 8.3.2's network image provider uses URL equality for Flutter's shared ImageCache. Aborting a request returns a successful transparent image to existing listeners. Eviction prevents future cache hits but does not change the transparent image already delivered to a surviving TileImage, which considers itself loaded. Initial fitting/zoom changes and concurrent map views can trigger this. Existing layer-wide retries cancelled unrelated pending tiles and stopped permanently after two attempts.

Fix:
- Disable obsolete-request cancellation for regional tiles, allowing shared image streams to finish.
- Share the default HTTP retry client for the app lifetime so disposing one map does not close requests serving another map's cached stream.
- Treat non-success HTTP responses as errors even if their bodies decode as images.
- Evict and reload only failed, still-live TileImages; back off 2/4/8/16/30 seconds and continue at 30 seconds. Hidden retained tabs pause retries; disposed tiles/maps are skipped.
- Keep regional routing and tile caching. No new fallback from masked Korean detail to global tiles.

Tradeoff: requests already started for obsolete tiles finish instead of being aborted. Normal tile pruning and cache reuse still apply; this may use extra bytes during rapid zooming.

Verification: regression reproduces transparent 1x1 output with the original provider and actual 2x2 test tile with the fix, while two consumers share a URL and one is cancelled. Tests cover HTTP error images, retries beyond two attempts, hidden/disposed maps, Korean/global routing. A limited live GET sample from this environment (Weaver Origin/Referer) returned HTTP 200 PNG and CORS * for Seoul z14/16/17/19, Kitakyushu z14 and global z2. This is not exhaustive provider coverage or a reproduction on the user's device.
