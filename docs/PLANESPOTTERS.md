# Planespotters photo integration

FlightSaver uses the public Planespotters photo lookup endpoints. No API key is configured or required by this client.

## Lookup order

1. Normalise the aircraft registration by trimming whitespace, removing internal whitespace and converting letters to uppercase.
2. Request `https://api.planespotters.net/pub/photos/reg/{registration}`.
3. If the response has no usable photo, or the registration lookup fails for a reason other than HTTP 429, try `https://api.planespotters.net/pub/photos/hex/{hex}` using the aircraft's ICAO 24-bit address.
4. Select the first usable photo returned by the API, download its thumbnail from the returned CDN URL, display the photographer credit and link to the original Planespotters photo page.

HTTP 429 is handled separately with a backoff. FlightSaver does not retry repeatedly to evade provider limits. Lookup metadata (including empty results) is cached in memory for up to 24 hours. Thumbnails are not added to FlightSaver's disk cache.

## Application identity

Every FlightSaver network client uses the same User-Agent:

```http
User-Agent: FlightSaver/1.1.1 (+https://github.com/Isaaker/FlightSaver)
```

The URL is the public project contact page requested by the maintainer. Keep this URL current if the repository moves. Do not remove the contact URL or impersonate a browser; providers need to identify the application rather than receive a generic browser identity.

## Diagnose an API request from macOS

Use the exact User-Agent shipped in `Sources/NetworkIdentity.swift`:

```bash
UA='FlightSaver/1.1.1 (+https://github.com/Isaaker/FlightSaver)'
curl -i -A "$UA" \
  'https://api.planespotters.net/pub/photos/reg/D-ABCD'
```

Replace `D-ABCD` with the aircraft registration. A successful API lookup normally returns HTTP 200 with a JSON `photos` array. An empty array means no photo was found for that identifier. HTTP 403 means the provider denied the request; check the response body and User-Agent. HTTP 429 means the provider is rate-limiting the client; wait instead of retrying rapidly.

## Diagnose the image CDN separately

The JSON response contains a thumbnail URL. Extract one with Python and download it separately:

```bash
UA='FlightSaver/1.1.1 (+https://github.com/Isaaker/FlightSaver)'
PHOTO_URL="$(curl -fsS -A "$UA" \
  'https://api.planespotters.net/pub/photos/reg/D-ABCD' | \
  python3 -c 'import json,sys; d=json.load(sys.stdin); p=d.get("photos") or []; print((p[0].get("thumbnail_large") or p[0].get("thumbnail") or {}).get("src", ""))')"

[ -n "$PHOTO_URL" ] && curl -fL -A "$UA" -o /tmp/flightsaver-planespotters.jpg "$PHOTO_URL"
file /tmp/flightsaver-planespotters.jpg
```

A successful API response and a successful image download are separate checks. If the API returns HTTP 200 but the CDN request fails, preserve the API response status and CDN response status separately when reporting the issue.

## Image attribution and rights

FlightSaver displays the photographer name returned by Planespotters.net and links the image to its original page. The image remains the property of its photographer / rights holder. Do not redistribute photographs in the repository or release packages without permission. Follow Planespotters.net's current API terms, rate limits and attribution requirements.
