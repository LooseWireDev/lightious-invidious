# Lightious server architecture

Lightious is a focused Light Phone III video and audio experience built on an
Invidious server fork. Invidious remains responsible for account signup,
signin, subscriptions, search, and YouTube extraction. The Lightious additions
are deliberately isolated so the fork can continue to merge upstream changes.

The browser is a control plane. It can search, curate, configure, and send
items to paired phones, but it never embeds or plays media. Playback happens
only in the Kotlin Lightious client.

## Product modes

- **Explore** preserves the current Lightious experience: search, account feed,
  local histories, and explicitly enabled pages.
- **Focused** exposes only companion-managed entries. Search, Popular, account
  feed, pasted links, and reopening unauthorized history entries are denied by
  the client rather than merely hidden.

Every focused video has one of two playback policies:

- `listen_only`: the client may resolve and play audio, but must not construct
  a video playback source.
- `watch_and_listen`: the client may offer both actions.

Channels are materialized into a bounded set of video IDs. Adding a channel
must not silently create an endless phone feed.

## Authentication boundary

The managed service uses the existing Invidious account system. Browser routes
under `/lightious` use the normal Invidious SID cookie and CSRF protection. The
fork does not create another password, recovery, or human account system.

The phone never receives the Invidious SID, password, or API token. It receives
an independently revocable Lightious device credential that identifies one
device associated with the authenticated Invidious user.

Custom upstream Invidious instances are a separate provider adapter. They must
not be used as identity for the managed service, and callback-provided usernames
must not be trusted as authenticated identity.

## Pairing

Pairing follows the constrained-device shape of OAuth device authorization,
without making the Lightious credential an OAuth token:

1. The phone generates a 256-bit device credential and sends only its SHA-256
   hash when creating a pairing request.
2. The server returns a high-entropy polling secret and a short, unambiguous,
   eight-character user code with a ten-minute expiry.
3. The phone displays the code and the `/lightious/pair` address.
4. The signed-in user enters the code in the companion page and approves the
   named device.
5. The phone polls with the pairing secret, displays the approved account, and
   confirms the association.
6. The server atomically creates the device using the previously supplied
   credential hash. The plaintext device credential never crosses the network.

Pairing codes are single-use, short-lived, and stored only as keyed hashes.
Device credentials are random opaque bearer tokens stored only as hashes and
can be revoked per device from the companion page. Production deployments must
also rate-limit pairing creation and code-preview requests at the trusted
reverse proxy; forwarded client-address headers are not trusted in application
code.

## Current device API

The first vertical slice is revisioned and intentionally small:

- `POST /api/lightious/v1/pairings` accepts a phone-generated device-credential
  digest and returns a pairing ID, polling secret, user code, verification URL,
  and expiry.
- `GET /api/lightious/v1/pairings/:id` uses the polling secret to report
  `pending`, `claimed`, `consumed`, or `expired` without exposing account
  credentials.
- `POST /api/lightious/v1/pairings/:id/activate` atomically installs the
  pre-committed device digest after browser approval and is safe to retry after
  a lost response.
- `GET /api/lightious/v1/sync` accepts only the opaque Lightious device bearer
  and returns the mode, profile revision, masked account label, and curated
  video policies.

All device responses use `Cache-Control: no-store`. Browser mutations use the
normal Invidious SID plus a signed CSRF scope; the device API never accepts an
Invidious SID or API token as a Lightious credential.

## Fork surface

Keep additions in these namespaces and tables:

- Browser UI: `/lightious/*`
- Device API: `/api/lightious/v1/*`
- Crystal modules: `Invidious::Lightious::*`
- Database objects: `lightious_*`

Do not modify Invidious's YouTube extraction, search, or playback-selection
internals for companion behavior. The production reverse proxy exposes the
Lightious control plane, required account routes, image routes, and Lightious
device API while denying the standard browser watch/embed surfaces. This makes
the no-browser-playback rule enforceable without scattering conditionals
through upstream route handlers.

## Provider model

The first provider is the managed Invidious instance in this fork. A later
custom provider may point at another HTTPS Invidious instance, but it requires
strict outbound-address validation, DNS rebinding defenses, timeouts, response
limits, and an explicit policy for private-network instances in self-hosted
deployments.

Media bytes should use direct upstream URLs when possible. Proxying through the
hosted Invidious instance is a controlled fallback because browser playback
restrictions do not reduce phone-streaming bandwidth when `local=true` is used.

## Initial delivery slices

1. Pairing tables, device credential authentication, companion pairing page,
   and device pairing API. **Implemented in the first vertical slice.**
2. Companion mode setting plus revisioned device sync. **Implemented.**
3. Explicit-video library with `listen_only` and `watch_and_listen` policy.
   **Implemented; enforcement lives in the Kotlin client.**
4. Bounded channel policies and a companion review inbox.
5. Optional custom-instance provider.

The Kotlin client remains a clean Light SDK application. This server-side fork
does not change that client into an Invidious, Clipious, or Materialious wrapper.
