# EAWS synchronization design and current test contract

## Scope and source of truth

The intended source of truth is the EAWS backend. Citizen and operator clients should submit events to it and render only server-recorded incident state. This checkout does not contain the deployable backend; the separate Next.js staff dashboard has a TEST-only adapter to the local Node service in `tooling/dev_dispatcher_server.mjs`. The local service now atomically persists its synthetic TEST state to an ignored JSON file across process restarts and sign-out/sign-in. It remains a local test double, not a deployable dispatch service.

The dashboard TEST adapter reads `/api/incidents/feed`, polls every second, and sends synthetic dispatch actions to `/api/incidents/:id/dispatch`. The harness records acknowledgement, assignment, dispatch state, two-way incident messages and history on the same incident record. The citizen demo can reopen its own TEST threads from Messages; the dashboard inbox lists incident conversations and exposes message delivery/read state. The mobile TEST client uses one synthetic `TEST-USER-MOBILE` identity, so this harness cannot simulate separate authenticated citizens or staff. Posts, comments, reactions and reporter profiles use the same persisted TEST state file; `/api/profiles/:user_id` returns only the exact reporter profile. This does not connect the dashboard to production. There is no realtime subscription, push service, SMS gateway, or production audit system.

## Local TEST persistence

- The standalone TEST server writes to `tooling/.data/dispatcher-state.json` by default. Set `EAWS_TEST_STATE_FILE` to choose another local path.
- Each successful mutation is written through a temporary file and atomic rename before the API returns success. A restart loads the saved state; malformed or unsupported saved state stops startup rather than silently replacing records with seed fixtures.
- Logout clears the mobile authentication/session cache only. It does not call a TEST data reset. The explicit `/api/dev/reset` route is still destructive and remains protected by the developer-only harness header.
- Automated restart tests cover incident fields, messages, comments, history, community posts and exact-ID profile lookup.
- This local store is single-process and for synthetic testing only. It is not a backup strategy, multi-host database, authenticated production backend, or a durable cloud event log.

## Event envelope

The production API should persist events with at least:

| Field | Purpose |
|---|---|
| `client_event_id` | Client-generated idempotency key, stable across retry/offline replay |
| `incident_id` | Canonical server incident ID; all pins, reports, messages, and status history refer to this ID |
| `event_type` | SOS/report/post/comment/reaction/message/status/location/zone event |
| `actor_id`, `actor_role` | Authenticated citizen/operator identity and role |
| `occurred_at` | Client UTC time for the originating action |
| `recorded_at` | Server UTC time; authoritative ordering time |
| `payload` | Validated event fields, with medical/private fields access-controlled |

The app now generates stable `client_event_id` values for SOS and incident-report creation, and message client IDs deduplicate TEST chat retries. The local harness persists its resulting state to disk. It does not yet provide a durable client-side offline queue for comments, reactions, chat, or arbitrary actions. Server timestamps are used for the local history and message order. Client-supplied IDs/times do not replace server validation.

## SOS state machine

Expected citizen-facing progression:

```text
Sent -> Acknowledged -> Dispatched -> En route -> On scene -> Resolved by operator
  |              \
  +-> Retracted   +-> operator-controlled alternate transition
  +-> SMS sent, unconfirmed (only after a real gateway confirms submission)
```

`I am safe` is a separate citizen signal and must not itself close the incident. Resolution requires an operator action, outcome, and notes. The local harness models this separate `citizen_safe` flag and validates the operator transition sequence; it requires closure outcome and resolution notes. It is intentionally not evidence that a production backend enforces the same rules.

The mobile SOS screen submits immediately and treats the seven-second timer only as a cancel window. The client persists its event key before starting the POST, reuses it after connection recovery, and sends a retraction when the incident ID is known. If the request outcome is unknown, it retains the retry key and does not show operator acknowledgement. The screen polls the incident status and chat separately; a chat endpoint failure no longer suppresses a successfully fetched status. Local state is surfaced as unconfirmed when server status is unavailable.

## Delivery priority and escalation

Required production ordering:

1. Commit SOS/status/message events to a durable, high-priority queue.
2. Publish to the operator queue over realtime; retain REST polling as recovery.
3. Push a notification where authorized and configured.
4. If online delivery cannot be confirmed, submit to an approved test SMS gateway, targeting the control room before contacts.
5. Retry quickly with bounded exponential backoff and the same event key; reconcile a later online sync against that same incident.

Only REST polling, client event-key reuse, local TEST-file persistence, and one-second incident polling exist here. In the local dashboard, SOS-category incidents are ranked before other categories, then severity and wait time are used; this is a client-side test presentation rule, not a durable backend priority lane. The TEST chat marks operator messages fetched when the citizen app polls and marks citizen messages read when a dispatcher opens the incident thread. SMS is a preview only; no destination is configured and no SMS is sent. Push, realtime delivery, production delivery receipts, offline chat replay, and end-to-end escalation are not implemented.

Feed processing must not share a blocking queue with SOS/operator messages. Automatic keyword/duplicate/reaction detection may rank items and show reasons, but must never dispatch. Neither priority lanes nor automated signal ranking are implemented in this checkout.

## Concurrency, roles, privacy, and audit

The test API supports optimistic `expected_version` checks for incident edits. Operators can claim an unowned case by writing `assigned_to`, `operator_name`, and a claim action against the current version. Competing claims or mutations against another owner are rejected and the claim is included in the persisted TEST audit history. The dashboard reflects that owner on the queue, incident detail, and map popup; reporter profile and incident chat actions are available from both the map and detail panel. The test fixtures provide explicitly synthetic profile fields and invalid, non-dialable `+233 00...` numbers only.

This is a TEST-only concurrency simulation, not production access control: actor names come from request data, and no authenticated staff roles or durable edit locks exist. Production must derive actor identity from the authenticated session and perform an atomic owner check on every status, dispatch, note, message, and resolution write. Medical-data reveal still needs an authorized reason and a durable access audit. The TEST community UI disables delete/block controls because those moderation routes are not implemented, and unit assignment remains unavailable. These gaps block real-shift use.

## Latency and evidence

Target requirements are SOS visibility on the operator dashboard under 3 seconds on a normal network and operator acknowledgement visible on the phone under 2 seconds. Production latency is unmeasured. Browser timing against the loopback test API is a local integration measurement only and does not include production services or mobile hardware.

Observed local evidence:

- Node suite: 15 test cases pass (response-level tests against loopback only; aggregate duration is not an end-to-end latency measurement). Tests verify local state survives a server restart, exact-ID profile lookup, two-way incident chat ordering, retry deduplication, synthetic-citizen isolation, and delivery/read states. A dedicated case-claim test verifies that the first versioned claim wins, stale/current competing ownership writes are rejected, competing messages are rejected, and the claim is visible in audit history.
- The actual Flutter web demo created `TEST-INC-0011` as `sent`; the separate dashboard displayed that same ID and dispatched it to `TEST police unit`, recording acknowledgement and dispatch history under `TEST Operator Akua Sarpong`. The citizen SOS screen then showed the same operator and unit from the record. This verifies one local browser/API round trip in both directions, not a native-device or production flow.
- Fresh follow-up: Flutter web submitted `TEST-INC-0014` with unavailable location and the server recorded it as `sent`. The TEST dashboard loaded the identical ID and recorded acknowledgement plus dispatch to `TEST police unit`, operator `TEST Operator Akua Sarpong`; Flutter's one-second polling subsequently rendered that same unit/operator and dispatched state. Timing thresholds were not measured.
- The Fire Service tab dispatched `TEST-INC-0002` and both its API record and the Audit view showed the same fire unit/action. The Ambulance tab showed the same API-backed SOS state as Live Map. The community route exercised a flagged synthetic threat reply, an Alarmed reaction, and a new reply against the TEST API.
- The TEST audit endpoint derives entries from persisted incident history; it is not immutable or compliance-grade. Analytics is a snapshot from the current incident feed, not historical/official service telemetry. Browser-local settings do not configure backend services.
- Local dashboard render timings were approximately 877 ms / 1,497 ms / 873 ms for 5 / 50 / 500 synthetic incidents; a separate 500-incident Critical-filter run displayed 100 cards in 461 ms. These are browser measurements, not concurrent load, server throughput, or SLA results.
- Post-dispatch dashboard controls were verified disabled; the test API also rejects repeat dispatch attempts. Medical details are hidden where audited reveal is not implemented. Calls remain disabled; the TEST incident inbox and message controls are enabled for synthetic records only.
- The community UI now states when contact records are absent rather than inventing contacts; unavailable TEST moderation and live unit-assignment actions are disabled. Agency queues identify the current assigned unit on already-dispatched records.
- Follow-up browser drill showed a TEST operator message on the citizen SOS screen after polling and then rendered `en_route` with ETA 7 from the same incident. The old API process returned legacy `test_only_not_delivered`; after restarting the approved volatile service with current source, a new drill recorded `fetched_by_citizen_app`.
- After restart, a fresh SOS progressed through dashboard dispatch, `en_route` ETA 6, `on_scene`, and resolution. Citizen showed the recorded unit/ETA and then a case-closed outcome; the active queue hid the resolved record and the cleared toggle restored it. Audit search returned the same incident's message, status changes, resolver, outcome, and notes.
- The first fresh browser drill exposed two dashboard-source errors: the TEST feed read non-TEST InsForge records, and Quick Dispatch used a stale selected incident. TEST feed reads now route to loopback, TEST unit data stays empty, and Quick Dispatch targets the rendered incident. The initial misdispatch affected only synthetic `TEST-INC-0002`; the repeated action after the fix targeted `TEST-INC-0012`.
- Earlier open-browser runs showed different persisted event IDs and a stale receipt label; those observations describe that run and are not evidence of shared active chat. A subsequent fix aligned the Flutter web API's IPv4 loopback default with the TEST server bind address. Re-run the browser integration against a freshly rebuilt bundle before treating the old screenshots as current evidence.
- Latest checks: dashboard TypeScript check passes; the current Node TEST API suite passes 12/12. The dashboard production build passed in the prior closeout run. Targeted ESLint reports existing React effect, `no-explicit-any`, and unused-import errors/warnings in dashboard Map/API/model code; no broad lint cleanup was made.
- The dashboard loopback TEST adapter skips remote auth lookup and uses its local test token; the configured non-TEST API path continues to use the configured auth session. Dashboard typecheck passed after this change; end-to-end verification used the running development build.
- The browser/API drill does not include a native device, persistent storage, network shaping, concurrent operators, notification delivery, or measured production latency. The under-3-second and under-2-second targets remain unverified.
- Follow-up dashboard interaction: selecting a queue record focuses its marker and opens a popup with the matching report details and profile/chat actions; a record without coordinates produces an explicit no-pin message. The profile modal consumes nested or flattened reporter contact fields and keeps medical information masked. “Take this case” updates the versioned owner and the live queue/detail UI; the local API test verifies competing writes are rejected. The current already-running feed lacks profile contact fields; newly seeded TEST records have invalid non-dialable numbers, and production profile lookup/auth/concurrency remain unimplemented.
- Chat integration follow-up: after rebuilding the citizen demo with the IPv4 loopback default, its pending synthetic event was accepted by the current local API and the saved cancel request was honored as `retracted`. The final loopback smoke exchange on `TEST-INC-0011` persisted operator message `TEST-MESSAGE-0021` and citizen reply `TEST-MESSAGE-0022`; citizen polling marked the operator message fetched/read, dispatcher polling marked the reply received/read, and both inbox endpoints returned the same incident thread. The refreshed dashboard inbox also sent `TEST-MESSAGE-0023` into that incident and displayed its waiting-for-app state. Automated Flutter widget coverage verifies that the citizen can reopen a retained conversation and send a reply. These tests do not claim that two authenticated users, the hosted InsForge backend, push, or SMS are connected.

## Required next integration

Before using this as an operational system, implement the event contract and enforced transitions in the isolated EAWS backend; replace the volatile test adapter with authenticated shared records; add realtime plus push/SMS acknowledgements; configure and verify test-only map/storage services; enforce role and medical-data policies; and run device-to-dashboard drills including duplicate retries, offline recovery, restart, two operators, and 5/50/500 concurrent events. Keep production credentials and real recipient numbers out of this test setup.
