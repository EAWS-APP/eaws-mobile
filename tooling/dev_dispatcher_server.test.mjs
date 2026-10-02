import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createTestDispatcherServer } from './dev_dispatcher_server.mjs';

async function withServer(run) {
  const app = createTestDispatcherServer({ port: 0, host: '127.0.0.1' });
  const address = await app.listen();
  try {
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    await app.close();
  }
}

async function withPersistentServer(stateFile, run) {
  const app = createTestDispatcherServer({
    port: 0,
    host: '127.0.0.1',
    persistencePath: stateFile,
  });
  const address = await app.listen();
  try {
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    await app.close();
  }
}

async function api(base, path, { method = 'GET', body, dev = false, client } = {}) {
  const response = await fetch(`${base}/api${path}`, {
    method,
    headers: {
      ...(body ? { 'content-type': 'application/json' } : {}),
      ...(dev ? { 'x-eaws-test-harness': 'true' } : {}),
      ...(client ? { 'x-eaws-test-client': client } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  return { status: response.status, body: response.status === 204 ? null : await response.json() };
}

test('seeds TEST incidents, noise, edge cases, and a threat reply on an older post', async () => {
  await withServer(async (base) => {
    const { status, body } = await api(base, '/incidents/feed');
    assert.equal(status, 200);
    assert.equal(body.incidents.length, 10);
    assert.ok(body.incidents.every((incident) => incident.id.startsWith('TEST-')));
    assert.ok(body.incidents.some((incident) => incident.severity === 'critical'));
    assert.ok(body.incidents.every((incident) => incident.severity_confidence === 'unverified'));
    assert.ok(body.incidents.some((incident) => incident.latitude === null));
    assert.ok(body.incidents.some((incident) => incident.media_url && !incident.description));
    assert.ok(body.incidents.some((incident) => incident.location_name?.includes('Fictional')));
    const profile = body.incidents[0].reporter_profile;
    assert.equal(profile.full_name, body.incidents[0].user_name);
    assert.match(profile.phone, /^TEST ONLY · \+233 00 /);
    assert.ok(profile.email.endsWith('@example.invalid'));
    assert.equal(profile.emergency_contacts.length, 1);
    const posts = await api(base, '/community/posts');
    const olderPost = posts.body.posts.find((post) => post.id === 'TEST-POST-OLDER-01');
    assert.ok(olderPost);
    assert.ok(Date.now() - Date.parse(olderPost.created_at) > 2 * 24 * 60 * 60 * 1000);
    assert.ok(olderPost.replies.some((reply) => reply.threat_flag));
    assert.ok(posts.body.posts.some((post) => /[áéíóúñ]/i.test(post.content)));
    assert.ok(posts.body.posts.some((post) => post.content.length > 1000));
    assert.ok(posts.body.posts.some((post) => post.id === 'TEST-POST-SPAM-01'));
  });
});

test('requires explicit test header for seed and load controls', async () => {
  await withServer(async (base) => {
    assert.equal((await api(base, '/dev/load', { method: 'POST', body: { count: 500 } })).status, 403);
    assert.equal((await api(base, '/dev/load', { method: 'POST', body: { count: 500 }, dev: true })).body.incidents, 500);
    assert.equal((await api(base, '/incidents/feed')).body.incidents.length, 500);
    assert.equal((await api(base, '/dev/load', { method: 'POST', body: { count: 51 }, dev: true })).status, 400);
  });
});

test('creates a report with intact fields and timestamp and returns stable identifier', async () => {
  await withServer(async (base) => {
    const created = await api(base, '/incidents', {
      method: 'POST',
      body: {
        category: 'medical',
        title: 'TEST: Report submitted from mobile client',
        description: 'TEST report details',
        is_anonymous: true,
        location_name: 'TEST LOCATION: Fictional Clinic',
        latitude: 5.6,
        longitude: -0.2,
        media_url: 'https://example.invalid/test-only/photo.jpg',
        media_type: 'image',
      },
    });

    test('persists reports, posts, comments, messages, status and profile across server restarts', async () => {
      const directory = await mkdtemp(path.join(os.tmpdir(), 'eaws-test-state-'));
      const stateFile = path.join(directory, 'dispatcher-state.json');
      let incidentId;
      let citizenId;

      try {
        await withPersistentServer(stateFile, async (base) => {
          const created = await api(base, '/incidents', {
            method: 'POST',
            body: {
              category: 'SOS',
              title: 'TEST: Durable incident record',
              description: 'TEST: retained after server restart and operator logout',
              status: 'sent',
              client_event_id: 'TEST-DURABLE-EVENT-001',
            },
          });
          assert.equal(created.status, 201);
          incidentId = created.body.incident.id;
          citizenId = created.body.incident.user_id;

          const acknowledged = await api(base, `/incidents/${incidentId}`, {
            method: 'PATCH',
            body: {
              expected_version: created.body.incident.version,
              status: 'acknowledged',
              operator_name: 'TEST Operator Akua Sarpong',
              action: 'TEST acknowledgement persisted',
            },
          });
          assert.equal(acknowledged.status, 200);

          const comment = await api(base, `/community/incidents/${incidentId}/comments`, {
            method: 'POST',
            body: { content: 'TEST: durable citizen comment' },
          });
          assert.equal(comment.status, 201);
          const message = await api(base, `/incidents/${incidentId}/messages`, {
            method: 'POST',
            body: {
              content: 'TEST: durable dispatcher text',
              client_message_id: 'TEST-DISPATCH-MESSAGE-001',
            },
          });
          assert.equal(message.status, 201);
          const citizenReply = await api(base, `/incidents/${incidentId}/messages`, {
            method: 'POST',
            client: 'citizen',
            body: {
              content: 'TEST: durable citizen reply',
              client_message_id: 'TEST-CITIZEN-MESSAGE-001',
            },
          });
          assert.equal(citizenReply.status, 201);
          const post = await api(base, '/community/posts', {
            method: 'POST',
            body: { content: 'TEST: durable community post' },
          });
          assert.equal(post.status, 201);
          const reply = await api(base, `/community/posts/${post.body.post.id}/replies`, {
            method: 'POST',
            body: { content: 'TEST: durable reply' },
          });
          assert.equal(reply.status, 201);
          const reaction = await api(base, `/community/incidents/${post.body.post.id}/reactions`, {
            method: 'POST',
            body: { reaction_type: 'concerned' },
          });
          assert.equal(reaction.status, 201);
        });

        await withPersistentServer(stateFile, async (base) => {
          const incident = await api(base, `/incidents/${incidentId}`);
          assert.equal(incident.status, 200);
          assert.equal(incident.body.incident.client_event_id, 'TEST-DURABLE-EVENT-001');
          assert.equal(incident.body.incident.status, 'acknowledged');
          assert.equal(incident.body.incident.comments[0].content, 'TEST: durable citizen comment');
          assert.deepEqual(
            incident.body.incident.messages.map((item) => item.content),
            ['TEST: durable dispatcher text', 'TEST: durable citizen reply'],
          );
          assert.equal(
            incident.body.incident.messages[0].delivery_state,
            'awaiting_citizen_poll',
          );
          assert.equal(
            incident.body.incident.messages[1].delivery_state,
            'received_by_dispatch',
          );
          assert.ok(incident.body.incident.history.some((event) => event.action === 'TEST acknowledgement persisted'));
          const dispatcherThreads = await api(base, '/messages/threads');
          assert.ok(
            dispatcherThreads.body.threads.some(
              (thread) => thread.incident_id === incidentId,
            ),
          );
          const citizenThreads = await api(base, '/citizen/messages/threads', {
            client: 'citizen',
          });
          assert.ok(
            citizenThreads.body.threads.some(
              (thread) => thread.incident_id === incidentId,
            ),
          );

          const profile = await api(base, `/profiles/${citizenId}`);
          assert.equal(profile.status, 200);
          assert.equal(profile.body.profile.user_id, citizenId);
          assert.equal(profile.body.profile.full_name, 'TEST Ama Mensah');
          assert.ok(profile.body.profile.incident_history.some((item) => item.id === incidentId));

          const posts = await api(base, '/community/posts');
          const durablePost = posts.body.posts.find((item) => item.content === 'TEST: durable community post');
          assert.ok(durablePost);
          assert.equal(durablePost.replies[0].content, 'TEST: durable reply');
          assert.equal(durablePost.concerned_count, 1);
        });
      } finally {
        await rm(directory, { recursive: true, force: true });
      }
    });

    test('profile lookup never returns a different reporter and reports unknown IDs', async () => {
      await withServer(async (base) => {
        const matchingIncident = (await api(base, '/incidents/feed')).body.incidents[0];
        const matchingProfile = await api(base, `/profiles/${matchingIncident.user_id}`);
        assert.equal(matchingProfile.status, 200);
        assert.equal(matchingProfile.body.profile.user_id, matchingIncident.user_id);
        assert.equal(matchingProfile.body.profile.full_name, matchingIncident.user_name);

        const missing = await api(base, '/profiles/TEST-USER-NOT-FOUND');
        assert.equal(missing.status, 404);
      });
    });
    assert.equal(created.status, 201);
    assert.match(created.body.incident.id, /^TEST-INC-/);
    assert.ok(Number.isFinite(Date.parse(created.body.incident.created_at)));
    assert.equal(created.body.incident.latitude, 5.6);
    assert.equal(created.body.incident.media_type, 'image');
    assert.equal(created.body.incident.reporter_profile.full_name, 'TEST Ama Mensah');
    const feed = await api(base, '/incidents/feed');
    assert.ok(feed.body.incidents.some((incident) => incident.id === created.body.incident.id));
  });
});

test('accepts media-only reports without inventing location or verifying severity', async () => {
  await withServer(async (base) => {
    const result = await api(base, '/incidents', {
      method: 'POST',
      body: {
        client_event_id: 'TEST-REPORT-MEDIA-ONLY-001',
        category: 'fire',
        title: 'TEST: Media-only fire report',
        description: '',
        media_type: 'image',
        media_status: 'test_placeholder_only',
        latitude: null,
        longitude: null,
        severity: 'critical',
        severity_confidence: 'unverified',
      },
    });
    assert.equal(result.status, 201);
    assert.equal(result.body.incident.description, '');
    assert.equal(result.body.incident.latitude, null);
    assert.equal(result.body.incident.longitude, null);
    assert.equal(result.body.incident.severity_confidence, 'unverified');
    assert.equal(result.body.incident.media_status, 'test_placeholder_only');
    assert.equal(result.body.incident.reporter_profile.phone, 'TEST ONLY · +233 00 000 0001');
  });
});

test('SOS retries with one client event ID and reports safe without closing the incident', async () => {
  await withServer(async (base) => {
    const request = {
      category: 'SOS',
      title: 'TEST SOS: citizen needs help',
      description: 'Synthetic Accra test event',
      status: 'sent',
      client_event_id: 'TEST-SOS-EVENT-001',
      latitude: 5.6,
      longitude: -0.2,
    };
    const first = await api(base, '/incidents', { method: 'POST', body: request });
    const retry = await api(base, '/incidents', { method: 'POST', body: request });
    assert.equal(first.status, 201);
    assert.equal(retry.status, 200);
    assert.equal(retry.body.idempotent_replay, true);
    assert.equal(first.body.incident.id, retry.body.incident.id);
    assert.equal(
      (await api(base, '/incidents/feed')).body.incidents.filter(
        (incident) => incident.client_event_id === request.client_event_id,
      ).length,
      1,
    );

    const safe = await api(base, `/incidents/${first.body.incident.id}`, {
      method: 'PATCH',
      body: { citizen_safe: true, action: 'citizen reported safe' },
    });
    assert.equal(safe.status, 200);
    assert.equal(safe.body.incident.citizen_safe, true);
    assert.equal(safe.body.incident.status, 'sent');
    const fetched = await api(base, `/incidents/${first.body.incident.id}`);
    assert.equal(fetched.body.incident.id, first.body.incident.id);
  });
});

test('enforces operator status progression and requires closure outcome and notes', async () => {
  await withServer(async (base) => {
    const created = await api(base, '/incidents', {
      method: 'POST',
      body: {
        category: 'SOS',
        title: 'TEST SOS: status drill',
        status: 'sent',
        client_event_id: 'TEST-SOS-EVENT-002',
      },
    });
    const id = created.body.incident.id;
    const retracted = await api(base, `/incidents/${id}`, {
      method: 'PATCH',
      body: { status: 'retracted', action: 'retracted by user' },
    });
    assert.equal(retracted.status, 200);
    const invalid = await api(base, `/incidents/${id}`, {
      method: 'PATCH',
      body: { status: 'dispatched' },
    });
    assert.equal(invalid.status, 409);

    const second = await api(base, '/incidents', {
      method: 'POST',
      body: {
        category: 'SOS',
        title: 'TEST SOS: operator state drill',
        status: 'sent',
        client_event_id: 'TEST-SOS-EVENT-003',
      },
    });
    const incidentId = second.body.incident.id;
    for (const status of ['acknowledged', 'dispatched', 'en_route', 'on_scene']) {
      const result = await api(base, `/incidents/${incidentId}`, {
        method: 'PATCH',
        body: {
          status,
          operator_name: 'TEST Operator Akua Sarpong',
          dispatch_unit: 'TEST Unit Alpha',
          eta_minutes: 8,
        },
      });
      assert.equal(result.status, 200);
      assert.equal(result.body.incident.status, status);
    }
    const incompleteClose = await api(base, `/incidents/${incidentId}`, {
      method: 'PATCH',
      body: { status: 'resolved' },
    });
    assert.equal(incompleteClose.status, 400);
    const resolved = await api(base, `/incidents/${incidentId}`, {
      method: 'PATCH',
      body: {
        status: 'resolved',
        outcome: 'TEST: handoff drill completed',
        resolution_notes: 'TEST: verified the closure flow; no real responder involved.',
        operator_name: 'TEST Operator Akua Sarpong',
      },
    });
    assert.equal(resolved.body.incident.status, 'resolved');
    assert.equal(resolved.body.incident.outcome, 'TEST: handoff drill completed');
    assert.equal(resolved.body.incident.resolved_by, 'TEST Operator Akua Sarpong');
    assert.equal(
      resolved.body.incident.resolution_notes,
      'TEST: verified the closure flow; no real responder involved.',
    );
    assert.ok(resolved.body.incident.resolved_at);
    assert.match(resolved.body.incident.notes.at(-1).content, /closure flow/);
    const audit = await api(base, '/audit/logs');
    const closeEvent = audit.body.logs.find(
      (event) => event.incident_id === incidentId && event.status === 'resolved',
    );
    assert.equal(closeEvent.operator_name, 'TEST Operator Akua Sarpong');
    assert.equal(closeEvent.outcome, 'TEST: handoff drill completed');
    assert.match(closeEvent.resolution_notes, /closure flow/);
  });
});

test('applies versioned status, assignment, note and test-message actions', async () => {
  await withServer(async (base) => {
    const initial = (await api(base, '/incidents/feed')).body.incidents[0];
    const patched = await api(base, `/incidents/${initial.id}`, {
      method: 'PATCH',
      body: {
        expected_version: initial.version,
        status: 'assigned',
        assigned_to: 'TEST Operator Akua Sarpong',
        operator_name: 'TEST Operator Akua Sarpong',
        action: 'assigned to TEST Operator Akua Sarpong',
      },
    });
    assert.equal(patched.status, 200);
    assert.equal(patched.body.incident.assigned_to, 'TEST Operator Akua Sarpong');
    const conflict = await api(base, `/incidents/${initial.id}`, {
      method: 'PATCH',
      body: { expected_version: initial.version, status: 'resolved' },
    });
    assert.equal(conflict.status, 409);
    const note = await api(base, `/incidents/${initial.id}/notes`, {
      method: 'POST',
      body: { content: 'TEST internal coordination note' },
    });
    assert.equal(note.status, 201);
    const mobileIncident = await api(base, '/incidents', {
      method: 'POST',
      body: {
        category: 'SOS',
        title: 'TEST: mobile chat authorization drill',
        status: 'sent',
        client_event_id: 'TEST-MOBILE-CHAT-AUTH-001',
      },
    });
    const mobileIncidentId = mobileIncident.body.incident.id;
    const message = await api(base, `/incidents/${mobileIncidentId}/messages`, {
      method: 'POST',
      body: {
        content: 'TEST follow-up question',
        client_message_id: 'TEST-OPERATOR-MESSAGE-001',
      },
    });
    assert.equal(message.body.message.delivery_state, 'awaiting_citizen_poll');
    assert.equal(message.body.message.sender, 'TEST Operator Akua Sarpong');
    const operatorView = await api(base, `/incidents/${mobileIncidentId}/messages`);
    assert.equal(
      operatorView.body.messages.at(-1).delivery_state,
      'awaiting_citizen_poll',
    );
    const citizenMessages = await api(base, `/incidents/${mobileIncidentId}/messages`, {
      client: 'citizen',
    });
    assert.equal(citizenMessages.body.messages.at(-1).content, 'TEST follow-up question');
    assert.equal(
      citizenMessages.body.messages.at(-1).delivery_state,
      'fetched_by_citizen_app',
    );
    assert.ok(citizenMessages.body.messages.at(-1).delivered_at);
    const audit = await api(base, '/audit/logs');
    assert.ok(
      audit.body.logs.some(
        (event) =>
          event.incident_id === mobileIncidentId &&
          event.text === 'TEST message sent to citizen' &&
          event.message_content === 'TEST follow-up question',
      ),
    );
  });
});

test('retains a scoped, ordered two-way TEST chat with delivery, read and retry states', async () => {
  await withServer(async (base) => {
    const created = await api(base, '/incidents', {
      method: 'POST',
      body: {
        category: 'SOS',
        title: 'TEST: two-way mobile chat',
        status: 'sent',
        client_event_id: 'TEST-TWO-WAY-CHAT-001',
      },
    });
    const incidentId = created.body.incident.id;
    const operatorMessageBody = {
      content: 'TEST dispatcher: Please confirm you received this.',
      client_message_id: 'TEST-OPERATOR-CHAT-001',
    };
    const operatorMessage = await api(
      base,
      `/incidents/${incidentId}/messages`,
      { method: 'POST', body: operatorMessageBody },
    );
    const operatorRetry = await api(
      base,
      `/incidents/${incidentId}/messages`,
      { method: 'POST', body: operatorMessageBody },
    );
    assert.equal(operatorMessage.status, 201);
    assert.equal(operatorRetry.status, 200);
    assert.equal(operatorRetry.body.idempotent_replay, true);
    assert.equal(operatorRetry.body.message.id, operatorMessage.body.message.id);

    const beforeCitizenPoll = await api(
      base,
      `/incidents/${incidentId}/messages`,
    );
    assert.equal(
      beforeCitizenPoll.body.messages[0].delivery_state,
      'awaiting_citizen_poll',
    );
    const mobileThreads = await api(base, '/citizen/messages/threads', {
      client: 'citizen',
    });
    assert.ok(
      mobileThreads.body.threads.some(
        (thread) => thread.incident_id === incidentId,
      ),
    );

    const citizenPoll = await api(
      base,
      `/incidents/${incidentId}/messages`,
      { client: 'citizen' },
    );
    assert.equal(
      citizenPoll.body.messages[0].delivery_state,
      'fetched_by_citizen_app',
    );
    assert.equal(citizenPoll.body.messages[0].read_state, 'read');
    assert.ok(citizenPoll.body.messages[0].delivered_at);

    const citizenMessageBody = {
      content: 'TEST citizen: I received the message.',
      client_message_id: 'TEST-CITIZEN-CHAT-001',
    };
    const citizenMessage = await api(
      base,
      `/incidents/${incidentId}/messages`,
      { method: 'POST', client: 'citizen', body: citizenMessageBody },
    );
    const citizenRetry = await api(
      base,
      `/incidents/${incidentId}/messages`,
      { method: 'POST', client: 'citizen', body: citizenMessageBody },
    );
    assert.equal(citizenMessage.body.message.sender_role, 'citizen');
    assert.equal(
      citizenMessage.body.message.delivery_state,
      'received_by_dispatch',
    );
    assert.equal(citizenRetry.status, 200);
    assert.equal(citizenRetry.body.idempotent_replay, true);

    const unreadThreads = await api(base, '/messages/threads');
    const thread = unreadThreads.body.threads.find(
      (item) => item.incident_id === incidentId,
    );
    assert.equal(thread.citizen_id, 'TEST-USER-MOBILE');
    assert.equal(thread.unread_count, 1);
    assert.equal(
      thread.last_message.text,
      'TEST citizen: I received the message.',
    );

    const otherIncident = 'TEST-INC-0001';
    const unauthorizedRead = await api(
      base,
      `/incidents/${otherIncident}/messages`,
      { client: 'citizen' },
    );
    const unauthorizedSend = await api(
      base,
      `/incidents/${otherIncident}/messages`,
      {
        method: 'POST',
        client: 'citizen',
        body: { content: 'TEST cross-citizen attempt' },
      },
    );
    assert.equal(unauthorizedRead.status, 403);
    assert.equal(unauthorizedSend.status, 403);

    const dispatcherRead = await api(
      base,
      `/incidents/${incidentId}/messages`,
    );
    assert.equal(dispatcherRead.body.messages.length, 2);
    assert.equal(
      dispatcherRead.body.messages[1].read_state,
      'read',
    );
    const readThreads = await api(base, '/messages/threads');
    assert.equal(
      readThreads.body.threads.find((item) => item.incident_id === incidentId)
        .unread_count,
      0,
    );
    assert.ok(
      dispatcherRead.body.messages[0].created_at <=
        dispatcherRead.body.messages[1].created_at,
    );

    const tooLong = await api(base, `/incidents/${incidentId}/messages`, {
      method: 'POST',
      body: { content: 'x'.repeat(2001) },
    });
    assert.equal(tooLong.status, 400);
  });
});

test('incident claims are exclusive and recorded in audit history', async () => {
  await withServer(async (base) => {
    const incident = (await api(base, '/incidents/feed')).body.incidents[0];
    const claimed = await api(base, `/incidents/${incident.id}`, {
      method: 'PATCH',
      body: {
        assigned_to: 'TEST Operator Ama Serwaa',
        operator_name: 'TEST Operator Ama Serwaa',
        expected_version: incident.version,
        action: 'claimed by TEST Operator Ama Serwaa',
      },
    });
    assert.equal(claimed.status, 200);
    assert.equal(claimed.body.incident.assigned_to, 'TEST Operator Ama Serwaa');
    assert.equal(claimed.body.incident.version, incident.version + 1);

    const staleCompetingClaim = await api(base, `/incidents/${incident.id}`, {
      method: 'PATCH',
      body: {
        assigned_to: 'TEST Operator Kofi Mensah',
        operator_name: 'TEST Operator Ama Serwaa',
        expected_version: incident.version,
        action: 'claimed by TEST Operator Kofi Mensah',
      },
    });
    assert.equal(staleCompetingClaim.status, 409);
    assert.equal(staleCompetingClaim.body.incident.assigned_to, 'TEST Operator Ama Serwaa');

    const competingMessage = await api(base, `/incidents/${incident.id}/messages`, {
      method: 'POST',
      body: { content: 'TEST competing operator message' },
    });
    assert.equal(competingMessage.status, 409);
    const competingUpdate = await api(base, `/incidents/${incident.id}`, {
      method: 'PATCH',
      body: {
        expected_version: claimed.body.incident.version,
        operator_name: 'TEST Operator Kofi Mensah',
        assigned_to: 'TEST Operator Kofi Mensah',
        status: 'acknowledged',
      },
    });
    assert.equal(competingUpdate.status, 409);
    const competingDismissal = await api(base, `/incidents/${incident.id}`, {
      method: 'DELETE',
    });
    assert.equal(competingDismissal.status, 409);

    const audit = await api(base, '/audit/logs');
    assert.ok(
      audit.body.logs.some(
        (event) =>
          event.incident_id === incident.id &&
          event.text === 'claimed by TEST Operator Ama Serwaa' &&
          event.operator_name === 'TEST Operator Ama Serwaa',
      ),
    );
  });
});

test('TEST dispatch acknowledges, assigns and records one synthetic unit action', async () => {
  await withServer(async (base) => {
    const created = await api(base, '/incidents', {
      method: 'POST',
      body: {
        category: 'SOS',
        title: 'TEST SOS: dashboard dispatch drill',
        status: 'sent',
        client_event_id: 'TEST-SOS-DASHBOARD-DISPATCH-001',
      },
    });
    const id = created.body.incident.id;
    const dispatched = await api(base, `/incidents/${id}/dispatch`, {
      method: 'POST',
      body: { agency_type: 'ambulance', priority: 'critical', expected_version: created.body.incident.version },
    });
    assert.equal(dispatched.status, 201);
    assert.equal(dispatched.body.incident.status, 'dispatched');
    assert.equal(dispatched.body.incident.operator_name, 'TEST Operator Akua Sarpong');
    assert.equal(dispatched.body.incident.dispatch_unit, 'TEST ambulance unit');
    assert.deepEqual(
      dispatched.body.incident.history.slice(-2).map((event) => event.action),
      ['acknowledged', 'TEST ambulance unit dispatched'],
    );
    assert.equal(
      (await api(base, `/incidents/${id}/dispatch`, {
        method: 'POST',
        body: { agency_type: 'ambulance' },
      })).status,
      409,
    );
    assert.equal(
      (await api(base, `/incidents/${id}/dispatch`, {
        method: 'POST',
        body: { agency_type: 'police', expected_version: created.body.incident.version },
      })).body.error,
      'Incident changed; refresh before dispatching.',
    );
  });
});

test('audit feed reflects synthetic incident history and dispatch attribution', async () => {
  await withServer(async (base) => {
    const created = await api(base, '/incidents', {
      method: 'POST',
      body: {
        category: 'SOS',
        title: 'TEST SOS: audit history drill',
        status: 'sent',
        client_event_id: 'TEST-SOS-AUDIT-001',
      },
    });
    const id = created.body.incident.id;
    await api(base, `/incidents/${id}/dispatch`, {
      method: 'POST',
      body: { agency_type: 'ambulance', expected_version: created.body.incident.version },
    });
    const audit = await api(base, '/audit/logs');
    const actions = audit.body.logs.filter((log) => log.incident_id === id);
    assert.deepEqual(actions.map((log) => log.text).reverse(), [
      'created',
      'acknowledged',
      'TEST ambulance unit dispatched',
    ]);
    assert.equal(actions[0].operator_name, 'TEST Operator Akua Sarpong');
    assert.equal(actions[0].agency, 'ambulance');
    assert.equal(actions[0].citizen_id, created.body.incident.user_id);
  });
});

test('community TEST posts support replies, comments, and signal reactions', async () => {
  await withServer(async (base) => {
    const post = (await api(base, '/community/posts')).body.posts[0];
    const reply = await api(base, `/community/posts/${post.id}/replies`, {
      method: 'POST',
      body: { content: 'TEST: additional context for the operator.' },
    });
    assert.equal(reply.status, 201);
    const replies = await api(base, `/community/posts/${post.id}/replies`);
    assert.ok(replies.body.replies.some((item) => item.id === reply.body.reply.id));
    const comment = await api(base, `/community/incidents/${post.id}/comments`, {
      method: 'POST',
      body: { content: 'TEST THREAT: attack planned; flag for human review.' },
    });
    assert.equal(comment.body.comment.threat_flag, true);
    const comments = await api(base, `/community/incidents/${post.id}/comments`);
    assert.ok(comments.body.comments.some((item) => item.id === comment.body.comment.id));
    const reaction = await api(base, `/community/incidents/${post.id}/reactions`, {
      method: 'POST',
      body: { reaction_type: 'alarmed' },
    });
    assert.equal(reaction.status, 201);
    assert.equal(reaction.body.counts.alarmed_count, 1);
  });
});

test('validates inputs and filters search, priority and status', async () => {
  await withServer(async (base) => {
    assert.equal((await api(base, '/incidents', { method: 'POST', body: { description: 'missing title' } })).status, 400);
    assert.equal((await api(base, '/incidents/TEST-INC-0001', { method: 'PATCH', body: { status: 'not-a-status' } })).status, 400);
    const critical = await api(base, '/incidents/feed?severity=critical');
    assert.ok(critical.body.incidents.length > 0);
    assert.ok(critical.body.incidents.every((item) => item.severity === 'critical'));
    const search = await api(base, '/incidents/feed?search=unconscious');
    assert.equal(search.body.incidents.length, 1);
    assert.match(search.body.incidents[0].title, /unconscious/i);
    const posts = await api(base, '/community/posts');
    assert.ok(posts.body.posts.some((post) => post.id === 'TEST-POST-OLDER-01'));
  });
});
