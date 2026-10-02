import { createServer } from 'node:http';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const dashboardPath = path.join(currentDirectory, 'dev_dispatcher.html');
const statuses = new Set([
  'new',
  'sent',
  'sms_unconfirmed',
  'acknowledged',
  'assigned',
  'dispatched',
  'en_route',
  'on_scene',
  'escalated',
  'awaiting_info',
  'retracted',
  'resolved',
  'dismissed',
  'merged',
]);
const allowedTransitions = {
  new: new Set(['sent', 'acknowledged', 'assigned', 'escalated', 'dismissed', 'merged', 'retracted']),
  sent: new Set(['acknowledged', 'sms_unconfirmed', 'retracted']),
  sms_unconfirmed: new Set(['sent', 'acknowledged', 'retracted']),
  acknowledged: new Set(['assigned', 'dispatched', 'escalated', 'awaiting_info', 'resolved', 'retracted']),
  assigned: new Set(['acknowledged', 'dispatched', 'escalated', 'awaiting_info', 'resolved', 'retracted']),
  dispatched: new Set(['en_route', 'on_scene', 'resolved']),
  en_route: new Set(['on_scene', 'resolved']),
  on_scene: new Set(['resolved']),
  escalated: new Set(['acknowledged', 'assigned', 'dispatched', 'resolved', 'retracted']),
  awaiting_info: new Set(['acknowledged', 'assigned', 'dispatched', 'resolved', 'retracted']),
};
const priorities = ['critical', 'high', 'medium', 'low'];
const testOnlyHeader = 'x-eaws-test-harness';

function isoMinutesAgo(minutes) {
  return new Date(Date.now() - minutes * 60_000).toISOString();
}

function testReporterProfile(fullName, sequence = '0001') {
  const testNumber = String(sequence).padStart(4, '0');
  return {
    full_name: fullName,
    user_role: 'citizen',
    phone: `TEST ONLY · +233 00 000 ${testNumber}`,
    email: `test.user.${testNumber}@example.invalid`,
    address: 'TEST ADDRESS · Accra, Ghana',
    emergency_contacts: [
      {
        name: `TEST Contact ${testNumber}`,
        relation: 'Emergency contact',
        phone: `TEST ONLY · +233 00 001 ${testNumber}`,
      },
    ],
  };
}

function seedIncidents(size = 10) {
  const seeds = [
    {
      category: 'medical',
      severity: 'critical',
      title: 'TEST: Person unconscious near transit stop',
      description: 'TEST REPORT. Person is unresponsive; bystanders are present.',
      location_name: 'TEST LOCATION: Circle interchange, Accra',
      latitude: 5.5571,
      longitude: -0.2058,
      minutesAgo: 2,
    },
    {
      category: 'fire',
      severity: 'critical',
      title: 'TEST: Smoke from apartment building',
      description: 'TEST REPORT. Smoke visible on an upper floor; occupants may remain inside.',
      location_name: 'TEST LOCATION: Fictional Block A, Osu',
      latitude: 5.556,
      longitude: -0.182,
      minutesAgo: 4,
    },
    {
      category: 'violence',
      severity: 'high',
      title: 'TEST: Threatening person at market entrance',
      description: 'TEST REPORT. Person is shouting and threatening passers-by.',
      location_name: 'TEST LOCATION: Fictional Market Gate, Madina',
      latitude: 5.679,
      longitude: -0.164,
      minutesAgo: 7,
    },
    {
      category: 'accident',
      severity: 'high',
      title: 'TEST: Two-vehicle collision blocking lane',
      description: 'TEST REPORT. Collision at junction; one person reports pain.',
      location_name: 'TEST LOCATION: Fictional Junction, East Legon',
      latitude: 5.635,
      longitude: -0.158,
      minutesAgo: 11,
    },
    {
      category: 'missing_person',
      severity: 'medium',
      title: 'TEST: Older adult missing from family home',
      description: 'TEST REPORT. Family is searching nearby streets. No medical details provided.',
      location_name: 'TEST LOCATION: Fictional Street, Labone',
      latitude: 5.570,
      longitude: -0.165,
      minutesAgo: 19,
    },
    {
      category: 'natural_hazard',
      severity: 'high',
      title: 'TEST: Water rising across low-lying road',
      description: 'TEST REPORT. Vehicles are turning back; water is still rising.',
      location_name: 'TEST LOCATION: Fictional Road, Kaneshie',
      latitude: 5.568,
      longitude: -0.247,
      minutesAgo: 23,
    },
    {
      category: 'medical',
      severity: 'low',
      title: 'TEST: Request for non-urgent first-aid information',
      description: 'TEST REPORT. No immediate danger reported.',
      location_name: 'TEST LOCATION: Fictional Community Centre, Adenta',
      latitude: 5.706,
      longitude: -0.168,
      minutesAgo: 36,
    },
    {
      category: 'accident',
      severity: 'medium',
      title: 'TEST: Duplicate collision report',
      description: 'TEST REPORT. May describe the same collision as TEST incident 04.',
      location_name: 'TEST LOCATION: Fictional Junction, East Legon',
      latitude: 5.6352,
      longitude: -0.1582,
      minutesAgo: 41,
    },
    {
      category: 'other',
      severity: 'medium',
      title: 'TEST: Report submitted without a location',
      description: 'TEST REPORT. Reporter could not grant location permission.',
      location_name: null,
      latitude: null,
      longitude: null,
      minutesAgo: 49,
    },
    {
      category: 'fire',
      severity: 'high',
      title: 'TEST: Evidence-only fire report',
      description: '',
      location_name: null,
      latitude: null,
      longitude: null,
      media_url: 'https://example.invalid/test-only/fire-evidence.jpg',
      media_type: 'image',
      minutesAgo: 54,
    },
  ];

  return Array.from({ length: size }, (_, index) => {
    const seed = seeds[index % seeds.length];
    const sequence = String(index + 1).padStart(4, '0');
    const userName = [
      'TEST Ama Mensah',
      'TEST Kofi Boateng',
      'TEST Efua Owusu',
      'TEST Kwame Asare',
      'TEST Abena Osei',
      'TEST Yaw Addo',
      'TEST Akosua Arthur',
      'TEST Kojo Antwi',
      'TEST Adwoa Frimpong',
      'TEST Nana Kwarteng',
    ][index % 10];
    return {
      id: `TEST-INC-${sequence}`,
      user_id: `TEST-USER-${sequence}`,
      user_name: userName,
      reporter_profile: testReporterProfile(userName, sequence),
      is_anonymous: false,
      category: seed.category,
      severity: seed.severity,
      severity_confidence: 'unverified',
      status: 'new',
      title: index < seeds.length ? seed.title : `TEST LOAD: ${seed.title}`,
      description: seed.description,
      location_name: seed.location_name,
      latitude: seed.latitude,
      longitude: seed.longitude,
      media_url: seed.media_url ?? null,
      media_type: seed.media_type ?? null,
      created_at: isoMinutesAgo(seed.minutesAgo + Math.floor(index / seeds.length)),
      version: 1,
      assigned_to: null,
      comments: [],
      notes: [],
      messages: [],
      history: [
        {
          action: 'created',
          actor: 'TEST Reporter',
          created_at: isoMinutesAgo(seed.minutesAgo),
        },
      ],
    };
  });
}

function seedPosts() {
  return [
    {
      id: 'TEST-POST-OLDER-01',
      user_id: 'TEST-USER-OLDER-01',
      author_name: 'TEST Akosua Arthur',
      content: 'TEST: Neighbourhood clean-up is planned for Saturday.',
      created_at: isoMinutesAgo(60 * 24 * 3),
      replies: [
        {
          id: 'TEST-COMMENT-THREAT-01',
          content:
            'TEST THREAT: I intend to hurt people near the station tonight. This comment is synthetic test data.',
          author_name: 'TEST Kojo Antwi',
          created_at: isoMinutesAgo(60 * 24 * 2),
          threat_flag: true,
        },
      ],
      likes_count: 0,
    },
    {
      id: 'TEST-POST-NOISE-01',
      user_id: 'TEST-USER-NOISE-01',
      author_name: 'TEST Nana Kwarteng',
      content: 'TEST: Is this the right place to ask about a lost umbrella?',
      created_at: isoMinutesAgo(75),
      replies: [
        {
          id: 'TEST-COMMENT-NOISE-01',
          content: 'TEST: This is a joke, not an emergency.',
          author_name: 'TEST Yaw Addo',
          created_at: isoMinutesAgo(70),
          threat_flag: false,
        },
      ],
      likes_count: 0,
    },
    {
      id: 'TEST-POST-SPAM-01',
      user_id: 'TEST-USER-SPAM-01',
      author_name: 'TEST Kofi Boateng',
      content: 'TEST SPAM: Repeated promotional message; not an emergency.',
      created_at: isoMinutesAgo(90),
      replies: [],
      likes_count: 0,
    },
    {
      id: 'TEST-POST-RANT-01',
      user_id: 'TEST-USER-RANT-01',
      author_name: 'TEST Efua Owusu',
      content: 'TEST ANGRY RANT: I am frustrated with the roadworks. No immediate danger reported.',
      created_at: isoMinutesAgo(110),
      replies: [],
      likes_count: 0,
    },
    {
      id: 'TEST-POST-VAGUE-01',
      user_id: 'TEST-USER-VAGUE-01',
      author_name: 'TEST Kwame Asare',
      content: 'TEST: Something strange is happening nearby.',
      created_at: isoMinutesAgo(130),
      replies: [],
      likes_count: 0,
    },
    {
      id: 'TEST-POST-NONENGLISH-01',
      user_id: 'TEST-USER-NONENGLISH-01',
      author_name: 'TEST Abena Osei',
      content: 'TEST: No hay una emergencia; solo necesito información sobre el centro comunitario.',
      created_at: isoMinutesAgo(150),
      replies: [],
      likes_count: 0,
    },
    {
      id: 'TEST-POST-LONG-01',
      user_id: 'TEST-USER-LONG-01',
      author_name: 'TEST Ama Mensah',
      content: `TEST LONG TEXT: ${'This is synthetic community chatter with no emergency. '.repeat(80)}`,
      created_at: isoMinutesAgo(170),
      replies: [],
      likes_count: 0,
    },
  ];
}

export function createTestState(size = 10) {
  const incidents = seedIncidents(size);
  return {
    incidents,
    posts: seedPosts(),
    profiles: profilesFromIncidents(incidents),
    nextId: size + 1,
  };
}

function profilesFromIncidents(incidents) {
  return Object.fromEntries(
    incidents
      .filter((incident) => incident.user_id && incident.reporter_profile)
      .map((incident) => [
        incident.user_id,
        {
          user_id: incident.user_id,
          ...incident.reporter_profile,
        },
      ]),
  );
}

function exactReporterProfile(state, userId) {
  const storedProfile = state.profiles[userId];
  const relatedIncidents = state.incidents
    .filter((incident) => incident.user_id === userId)
    .sort((left, right) => right.created_at.localeCompare(left.created_at));
  const latestIncident = relatedIncidents[0];
  const profile = storedProfile ?? (
    latestIncident?.reporter_profile
      ? { user_id: userId, ...latestIncident.reporter_profile, profile_details_available: true }
      : latestIncident?.user_name
        ? {
            user_id: userId,
            full_name: latestIncident.user_name,
            profile_details_available: false,
          }
        : null
  );
  if (!profile) return null;

  const activeIncident = relatedIncidents.find(
    (incident) => !['resolved', 'dismissed', 'retracted', 'merged'].includes(incident.status),
  );
  return {
    ...profile,
    full_name: profile.full_name ?? latestIncident?.user_name ?? 'Name unavailable',
    citizen_id: profile.citizen_id ?? userId,
    profile_details_available: profile.profile_details_available ?? true,
    incident_history: relatedIncidents.map((incident) => ({
      id: incident.id,
      date: incident.created_at,
      type: incident.category,
      severity: incident.severity,
      status: incident.status,
      outcome: incident.outcome ?? incident.status,
    })),
    active_incident_id: activeIncident?.id ?? null,
    active_incident_note: activeIncident?.title ?? null,
  };
}

function messageThreadSummary(incident) {
  const messages = incident.messages ?? [];
  const lastMessage = messages.at(-1);
  return {
    incident_id: incident.id,
    citizen_id: incident.user_id,
    citizen_name: incident.user_name ?? 'TEST Citizen',
    incident_title: incident.title,
    incident_status: incident.status,
    last_message: lastMessage
      ? {
          id: lastMessage.id,
          text: lastMessage.content,
          sender: lastMessage.sender_role,
          time: lastMessage.created_at,
          delivery_state: lastMessage.delivery_state,
          read_state: lastMessage.read_state,
        }
      : null,
    unread_count: messages.filter(
      (message) =>
        message.sender_role === 'citizen' && message.read_state !== 'read',
    ).length,
  };
}

function validatePersistedState(value) {
  if (
    !value ||
    value.version !== 1 ||
    !Array.isArray(value.incidents) ||
    !Array.isArray(value.posts) ||
    !Number.isInteger(value.nextId) ||
    value.nextId < 1
  ) {
    throw new Error('Persisted TEST state is invalid; refusing to replace it with fresh seed data.');
  }
  return {
    incidents: value.incidents,
    posts: value.posts,
    profiles:
      value.profiles && typeof value.profiles === 'object' && !Array.isArray(value.profiles)
        ? value.profiles
        : profilesFromIncidents(value.incidents),
    nextId: value.nextId,
  };
}

function sendJson(response, statusCode, payload) {
  response.writeHead(statusCode, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET,POST,PATCH,DELETE,OPTIONS',
    'access-control-allow-headers': 'content-type,authorization,x-eaws-test-harness,x-eaws-test-client',
  });
  response.end(JSON.stringify(payload));
}

async function readJson(request) {
  let content = '';
  for await (const chunk of request) {
    content += chunk;
    if (content.length > 1_000_000) {
      throw Object.assign(new Error('Request body is too large.'), { statusCode: 413 });
    }
  }
  if (!content) return {};
  try {
    const parsed = JSON.parse(content);
    if (parsed === null || Array.isArray(parsed) || typeof parsed !== 'object') {
      throw new Error('Expected a JSON object.');
    }
    return parsed;
  } catch {
    throw Object.assign(new Error('Request body must be a JSON object.'), { statusCode: 400 });
  }
}

function recordHistory(incident, action, actor = 'TEST Dispatcher', details = {}) {
  incident.history.push({
    action,
    actor,
    status: incident.status,
    created_at: new Date().toISOString(),
    ...details,
  });
  incident.version += 1;
}

function matchIncidentRoute(pathname) {
  return pathname.match(/^\/api\/incidents\/([^/]+)(?:\/(notes|messages|media|dispatch))?$/);
}

function filterIncidents(incidents, searchParams) {
  const query = (searchParams.get('search') ?? '').trim().toLocaleLowerCase();
  const severity = searchParams.get('severity');
  const category = searchParams.get('category');
  const status = searchParams.get('status');
  const filtered = incidents.filter((incident) => {
    const searchable = [
      incident.id,
      incident.title,
      incident.description,
      incident.location_name,
      ...incident.comments.map((comment) => comment.content),
    ]
      .filter(Boolean)
      .join(' ')
      .toLocaleLowerCase();
    return (
      (!query || searchable.includes(query)) &&
      (!severity || incident.severity === severity) &&
      (!category || incident.category === category) &&
      (!status || incident.status === status)
    );
  });

  const priorityOrder = new Map(priorities.map((priority, index) => [priority, index]));
  return filtered.sort((left, right) => {
    const priorityDifference =
      (priorityOrder.get(left.severity) ?? priorities.length) -
      (priorityOrder.get(right.severity) ?? priorities.length);
    if (priorityDifference !== 0) return priorityDifference;
    return left.created_at.localeCompare(right.created_at);
  });
}

export function createTestDispatcherServer({
  port = Number(process.env.PORT ?? 5001),
  host = process.env.HOST ?? '127.0.0.1',
  persistencePath = null,
} = {}) {
  const state = createTestState();
  let writeQueue = Promise.resolve();
  let writeSequence = 0;
  const stateReady = (async () => {
    if (!persistencePath) return;
    try {
      const saved = JSON.parse(await readFile(persistencePath, 'utf8'));
      Object.assign(state, validatePersistedState(saved));
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  })();
  const persistState = () => {
    if (!persistencePath) return Promise.resolve();
    const snapshot = JSON.stringify({ version: 1, ...state });
    const operation = writeQueue.then(async () => {
      await mkdir(path.dirname(persistencePath), { recursive: true });
      const temporaryPath = `${persistencePath}.${process.pid}.${++writeSequence}.tmp`;
      await writeFile(temporaryPath, snapshot, { encoding: 'utf8', mode: 0o600 });
      await rename(temporaryPath, persistencePath);
    });
    writeQueue = operation.catch(() => {});
    return operation;
  };
  const server = createServer(async (request, response) => {
    const requestUrl = new URL(request.url ?? '/', `http://${request.headers.host ?? 'localhost'}`);
    const { pathname, searchParams } = requestUrl;

    if (request.method === 'OPTIONS') {
      response.writeHead(204, {
        'access-control-allow-origin': '*',
        'access-control-allow-methods': 'GET,POST,PATCH,DELETE,OPTIONS',
        'access-control-allow-headers': 'content-type,authorization,x-eaws-test-harness,x-eaws-test-client',
      });
      response.end();
      return;
    }

    if (pathname === '/' && request.method === 'GET') {
      try {
        const html = await readFile(dashboardPath);
        response.writeHead(200, {
          'content-type': 'text/html; charset=utf-8',
          'cache-control': 'no-store',
        });
        response.end(html);
      } catch (error) {
        sendJson(response, 500, { error: error.message });
      }
      return;
    }

    if (pathname === '/api/health' && request.method === 'GET') {
      sendJson(response, 200, {
        ok: true,
        mode: 'TEST ONLY',
        persistence: persistencePath ? 'disk' : 'memory',
        incident_count: state.incidents.length,
      });
      return;
    }

    if (
      (pathname === '/api/messages/threads' ||
        pathname === '/api/citizen/messages/threads') &&
      request.method === 'GET'
    ) {
      const isCitizenInbox = pathname === '/api/citizen/messages/threads';
      const threads = state.incidents
        .filter((incident) => {
          if (isCitizenInbox && incident.user_id !== 'TEST-USER-MOBILE') {
            return false;
          }
          const hasMessages = (incident.messages?.length ?? 0) > 0;
          const isOpen = ![
            'resolved',
            'dismissed',
            'retracted',
            'merged',
          ].includes(incident.status);
          return hasMessages || isOpen;
        })
        .map(messageThreadSummary)
        .sort(
          (left, right) =>
            (right.last_message?.time ?? '').localeCompare(
              left.last_message?.time ?? '',
            ) || right.incident_id.localeCompare(left.incident_id),
        );
      sendJson(response, 200, { threads });
      return;
    }

    if (pathname.startsWith('/api/dev/')) {
      if (request.headers[testOnlyHeader] !== 'true') {
        sendJson(response, 403, { error: 'Developer test-harness header required.' });
        return;
      }

      if (pathname === '/api/dev/reset' && request.method === 'POST') {
        const resetState = createTestState(10);
        Object.assign(state, resetState);
        await persistState();
        sendJson(response, 200, {
          mode: 'TEST ONLY',
          incidents: state.incidents.length,
          posts: state.posts.length,
        });
        return;
      }

      if (pathname === '/api/dev/load' && request.method === 'POST') {
        try {
          const { count } = await readJson(request);
          if (![5, 10, 50, 500].includes(count)) {
            sendJson(response, 400, { error: 'count must be 5, 10, 50, or 500.' });
            return;
          }
          state.incidents = seedIncidents(count);
          state.profiles = profilesFromIncidents(state.incidents);
          state.nextId = count + 1;
          await persistState();
          sendJson(response, 200, { mode: 'TEST ONLY', incidents: count });
        } catch (error) {
          sendJson(response, error.statusCode ?? 400, { error: error.message });
        }
        return;
      }

      sendJson(response, 404, { error: 'Unknown developer test route.' });
      return;
    }

    try {
      const profileMatch = pathname.match(/^\/api\/profiles\/([^/]+)$/);
      if (profileMatch && request.method === 'GET') {
        const userId = decodeURIComponent(profileMatch[1]);
        const profile = exactReporterProfile(state, userId);
        if (!profile) {
          sendJson(response, 404, { error: 'TEST citizen profile not found for this reporter ID.' });
          return;
        }
        sendJson(response, 200, { profile });
        return;
      }

      if (pathname === '/api/incidents/feed' && request.method === 'GET') {
        sendJson(response, 200, { incidents: filterIncidents(state.incidents, searchParams) });
        return;
      }

      if (pathname === '/api/audit/logs' && request.method === 'GET') {
        const logs = state.incidents
          .flatMap((incident) =>
            incident.history.map((event, index) => {
              const dispatchAction = event.action.match(/^TEST (police|fire|ambulance|nadmo) unit dispatched$/i);
              return {
                id: `${incident.id}-HISTORY-${index + 1}`,
                incident_id: incident.id,
                incident_title: incident.title,
                operator_name: event.actor,
                agency: dispatchAction?.[1] ?? incident.category,
                citizen_id: incident.user_id,
                text: event.action,
                created_at: event.created_at,
                status: event.status ?? incident.status,
                outcome: event.outcome ?? null,
                resolution_notes: event.resolution_notes ?? null,
                message_content: event.message_content ?? null,
                event_index: index,
              };
            }),
          )
          .sort(
            (left, right) =>
              right.created_at.localeCompare(left.created_at) ||
              left.incident_id.localeCompare(right.incident_id) ||
              right.event_index - left.event_index,
          );
        sendJson(response, 200, { logs, thread_owners: {} });
        return;
      }

      if (pathname === '/api/community/posts' && request.method === 'GET') {
        sendJson(response, 200, { posts: state.posts });
        return;
      }

      if (pathname === '/api/community/posts' && request.method === 'POST') {
        const body = await readJson(request);
        if (typeof body.content !== 'string' || !body.content.trim()) {
          sendJson(response, 400, { error: 'content is required.' });
          return;
        }
        const post = {
          id: `TEST-POST-${String(state.nextId++).padStart(4, '0')}`,
          user_id: 'TEST-USER-MOBILE',
          author_name: 'TEST Ama Mensah',
          content: body.content.trim(),
          created_at: new Date().toISOString(),
          replies: [],
          likes_count: 0,
        };
        state.posts.unshift(post);
        await persistState();
        sendJson(response, 201, { post });
        return;
      }

      const incidentMatch = matchIncidentRoute(pathname);
      if (pathname === '/api/incidents' && request.method === 'POST') {
        const body = await readJson(request);
        if (typeof body.title !== 'string' || !body.title.trim()) {
          sendJson(response, 400, { error: 'title is required.' });
          return;
        }
        const clientEventId =
          typeof body.client_event_id === 'string' ? body.client_event_id : null;
        if (clientEventId) {
          const existing = state.incidents.find(
            (item) => item.client_event_id === clientEventId,
          );
          if (existing) {
            sendJson(response, 200, {
              incident: existing,
              idempotent_replay: true,
            });
            return;
          }
        }
        const createdAt = new Date().toISOString();
        const incident = {
          id: `TEST-INC-${String(state.nextId++).padStart(4, '0')}`,
          client_event_id: clientEventId,
          user_id: 'TEST-USER-MOBILE',
          user_name: 'TEST Ama Mensah',
          reporter_profile: testReporterProfile('TEST Ama Mensah'),
          is_anonymous: body.is_anonymous === true,
          category: String(body.category ?? 'other'),
          severity:
            String(body.category ?? '').toLowerCase() === 'sos'
              ? 'critical'
              : String(body.severity ?? 'medium').toLowerCase(),
          severity_confidence: body.severity_confidence ?? 'unverified',
          status: String(body.status ?? 'new'),
          title: body.title.trim(),
          description: typeof body.description === 'string' ? body.description : '',
          location_name: body.location_name || null,
          latitude: Number.isFinite(body.latitude) ? body.latitude : null,
          longitude: Number.isFinite(body.longitude) ? body.longitude : null,
          accuracy_meters: Number.isFinite(body.accuracy_meters) ? body.accuracy_meters : null,
          media_url: body.media_url ?? null,
          media_type: body.media_type ?? null,
          media_status: body.media_status ?? null,
          created_at: createdAt,
          occurred_at: body.occurred_at ?? createdAt,
          version: 1,
          assigned_to: null,
          operator_name: null,
          dispatch_unit: null,
          eta_minutes: null,
          citizen_safe: false,
          outcome: null,
          resolved_at: null,
          comments: [],
          notes: [],
          messages: [],
          history: [{ action: 'created', actor: 'TEST Ama Mensah', created_at: createdAt }],
        };
        state.incidents.unshift(incident);
        state.profiles[incident.user_id] = {
          user_id: incident.user_id,
          ...incident.reporter_profile,
        };
        await persistState();
        sendJson(response, 201, { incident });
        return;
      }

      if (
        pathname.startsWith('/api/community/incidents/') &&
        pathname.endsWith('/comments') &&
        request.method === 'GET'
      ) {
        const incidentId = pathname.split('/')[4];
        const target =
          state.incidents.find((item) => item.id === incidentId) ??
          state.posts.find((item) => item.id === incidentId);
        if (!target) {
          sendJson(response, 404, { error: 'TEST post or incident not found.' });
          return;
        }
        sendJson(response, 200, { comments: target.comments ?? target.replies ?? [] });
        return;
      }

      if (pathname.startsWith('/api/community/incidents/') && pathname.endsWith('/comments') && request.method === 'POST') {
        const body = await readJson(request);
        const incidentId = pathname.split('/')[4];
        const incident = state.incidents.find((item) => item.id === incidentId);
        const post = state.posts.find((item) => item.id === incidentId);
        const target = incident ?? post;
        if (!target) {
          sendJson(response, 404, { error: 'TEST post or incident not found.' });
          return;
        }
        if (typeof body.content !== 'string' || !body.content.trim()) {
          sendJson(response, 400, { error: 'content is required.' });
          return;
        }
        const comment = {
          id: `TEST-COMMENT-${String(state.nextId++).padStart(4, '0')}`,
          content: body.content.trim(),
          author_name: 'TEST Ama Mensah',
          created_at: new Date().toISOString(),
          threat_flag: /threat|hurt|attack/i.test(body.content),
        };
        target.comments?.push(comment);
        target.replies?.push(comment);
        await persistState();
        sendJson(response, 201, { comment, reply: comment });
        return;
      }

      const replyMatch = pathname.match(/^\/api\/community\/posts\/([^/]+)\/replies$/);
      if (replyMatch && ['GET', 'POST'].includes(request.method ?? '')) {
        const post = state.posts.find((item) => item.id === decodeURIComponent(replyMatch[1]));
        if (!post) {
          sendJson(response, 404, { error: 'TEST post not found.' });
          return;
        }
        if (request.method === 'GET') {
          sendJson(response, 200, { replies: post.replies });
          return;
        }
        const body = await readJson(request);
        if (typeof body.content !== 'string' || !body.content.trim()) {
          sendJson(response, 400, { error: 'content is required.' });
          return;
        }
        const reply = {
          id: `TEST-COMMENT-${String(state.nextId++).padStart(4, '0')}`,
          content: body.content.trim(),
          author_name: 'TEST Ama Mensah',
          author_initials: 'TA',
          created_at: new Date().toISOString(),
          threat_flag: /threat|hurt|attack/i.test(body.content),
        };
        post.replies.push(reply);
        await persistState();
        sendJson(response, 201, { reply });
        return;
      }

      const reactionMatch = pathname.match(/^\/api\/community\/incidents\/([^/]+)\/reactions$/);
      if (reactionMatch && request.method === 'POST') {
        const targetId = decodeURIComponent(reactionMatch[1]);
        const target =
          state.incidents.find((item) => item.id === targetId) ??
          state.posts.find((item) => item.id === targetId);
        if (!target) {
          sendJson(response, 404, { error: 'TEST post or incident not found.' });
          return;
        }
        const body = await readJson(request);
        const countField = {
          like: 'likes_count',
          alarmed: 'alarmed_count',
          concerned: 'concerned_count',
        }[body.reaction_type];
        if (!countField) {
          sendJson(response, 400, { error: 'reaction_type must be like, alarmed, or concerned.' });
          return;
        }
        target[countField] = (target[countField] ?? 0) + 1;
        const reaction = {
          id: `TEST-REACTION-${String(state.nextId++).padStart(4, '0')}`,
          reaction_type: body.reaction_type,
          created_at: new Date().toISOString(),
        };
        await persistState();
        sendJson(response, 201, {
          reaction,
          counts: {
            likes_count: target.likes_count ?? 0,
            alarmed_count: target.alarmed_count ?? 0,
            concerned_count: target.concerned_count ?? 0,
          },
        });
        return;
      }

      if (!incidentMatch) {
        sendJson(response, 404, { error: 'TEST endpoint not found.' });
        return;
      }

      const [, rawId, subresource] = incidentMatch;
      const id = decodeURIComponent(rawId);
      const incident = state.incidents.find((item) => item.id === id);
      if (!incident) {
        sendJson(response, 404, { error: 'TEST incident not found.' });
        return;
      }

      if (request.method === 'GET' && !subresource) {
        sendJson(response, 200, { incident });
        return;
      }

      if (subresource === 'dispatch' && request.method === 'POST') {
        const body = await readJson(request);
        const agencies = new Set(['police', 'fire', 'ambulance', 'nadmo']);
        if (body.expected_version !== undefined && body.expected_version !== incident.version) {
          sendJson(response, 409, { error: 'Incident changed; refresh before dispatching.', incident });
          return;
        }
        if (!agencies.has(body.agency_type)) {
          sendJson(response, 400, { error: 'A valid TEST agency_type is required.' });
          return;
        }
        if (['resolved', 'dismissed', 'retracted', 'merged'].includes(incident.status)) {
          sendJson(response, 409, { error: `Cannot dispatch a ${incident.status} incident.` });
          return;
        }
        const actor = 'TEST Operator Akua Sarpong';
        if (incident.assigned_to && incident.assigned_to !== actor) {
          sendJson(response, 409, {
            error: `Incident is already being handled by ${incident.assigned_to}.`,
            incident,
          });
          return;
        }
        if (incident.status === 'new' || incident.status === 'sent' || incident.status === 'sms_unconfirmed') {
          incident.status = 'acknowledged';
          incident.operator_name = actor;
          recordHistory(incident, 'acknowledged', actor);
        }
        if (!allowedTransitions[incident.status]?.has('dispatched') && incident.status !== 'dispatched') {
          sendJson(response, 409, { error: `Cannot dispatch from ${incident.status}.` });
          return;
        }
        if (incident.status === 'dispatched') {
          sendJson(response, 409, { error: 'Incident is already dispatched.' });
          return;
        }
        incident.status = 'dispatched';
        incident.assigned_to = actor;
        incident.operator_name = actor;
        incident.dispatch_unit = `TEST ${body.agency_type} unit`;
        recordHistory(incident, `TEST ${body.agency_type} unit dispatched`, actor);
        await persistState();
        sendJson(response, 201, {
          response: { id: `TEST-DISPATCH-${incident.id}`, status: incident.status },
          incident,
        });
        return;
      }

      if (subresource === 'notes' && request.method === 'POST') {
        const body = await readJson(request);
        const actor = 'TEST Operator Akua Sarpong';
        if (incident.assigned_to && incident.assigned_to !== actor) {
          sendJson(response, 409, {
            error: `Incident is already being handled by ${incident.assigned_to}.`,
            incident,
          });
          return;
        }
        if (typeof body.content !== 'string' || !body.content.trim()) {
          sendJson(response, 400, { error: 'content is required.' });
          return;
        }
        const note = {
          id: `TEST-NOTE-${String(state.nextId++).padStart(4, '0')}`,
          content: body.content.trim(),
          actor,
          created_at: new Date().toISOString(),
        };
        incident.notes.push(note);
        recordHistory(incident, 'internal note added', actor);
        await persistState();
        sendJson(response, 201, { note, incident });
        return;
      }

      if (subresource === 'messages' && request.method === 'GET') {
        const clientRole = request.headers['x-eaws-test-client'];
        if (
          clientRole === 'citizen' &&
          incident.user_id !== 'TEST-USER-MOBILE'
        ) {
          sendJson(response, 403, {
            error: 'This TEST citizen cannot access another reporter’s messages.',
          });
          return;
        }
        let changed = false;
        for (const message of incident.messages) {
          if (
            clientRole === 'citizen' &&
            message.sender_role === 'operator' &&
            (message.delivery_state === 'awaiting_citizen_poll' ||
              message.read_state !== 'read')
          ) {
            if (message.delivery_state === 'awaiting_citizen_poll') {
              message.delivery_state = 'fetched_by_citizen_app';
              message.delivered_at = new Date().toISOString();
              changed = true;
              recordHistory(
                incident,
                'TEST message fetched by citizen app',
                'TEST Citizen App',
                { message_id: message.id },
              );
            }
            if (message.read_state !== 'read') {
              message.read_state = 'read';
              message.read_at = new Date().toISOString();
              changed = true;
              recordHistory(
                incident,
                'TEST message read by citizen app',
                'TEST Citizen App',
                { message_id: message.id },
              );
            }
          } else if (
            clientRole !== 'citizen' &&
            message.sender_role === 'citizen' &&
            message.read_state !== 'read'
          ) {
            message.read_state = 'read';
            message.read_at = new Date().toISOString();
            changed = true;
            recordHistory(
              incident,
              'TEST citizen message read by dispatcher',
              'TEST Operator Akua Sarpong',
              { message_id: message.id },
            );
          }
        }
        if (changed) await persistState();
        sendJson(response, 200, { messages: incident.messages ?? [] });
        return;
      }

      if (subresource === 'messages' && request.method === 'POST') {
        const body = await readJson(request);
        const isCitizen = request.headers['x-eaws-test-client'] === 'citizen';
        if (isCitizen && incident.user_id !== 'TEST-USER-MOBILE') {
          sendJson(response, 403, {
            error: 'This TEST citizen cannot message another reporter.',
          });
          return;
        }
        const actor = isCitizen
          ? incident.user_name ?? 'TEST Ama Mensah'
          : 'TEST Operator Akua Sarpong';
        if (
          !isCitizen &&
          incident.assigned_to &&
          incident.assigned_to !== actor
        ) {
          sendJson(response, 409, {
            error: `Incident is already being handled by ${incident.assigned_to}.`,
            incident,
          });
          return;
        }
        if (
          typeof body.content !== 'string' ||
          !body.content.trim() ||
          body.content.trim().length > 2000
        ) {
          sendJson(response, 400, {
            error: 'content is required and must not exceed 2000 characters.',
          });
          return;
        }
        if (
          body.client_message_id !== undefined &&
          (typeof body.client_message_id !== 'string' ||
            !body.client_message_id.trim() ||
            body.client_message_id.length > 128)
        ) {
          sendJson(response, 400, {
            error: 'client_message_id must be a non-empty string of at most 128 characters.',
          });
          return;
        }
        if (body.client_message_id) {
          const previous = incident.messages.find(
            (message) =>
              message.client_message_id === body.client_message_id &&
              message.sender_role === (isCitizen ? 'citizen' : 'operator'),
          );
          if (previous) {
            sendJson(response, 200, { message: previous, idempotent_replay: true });
            return;
          }
        }
        const message = {
          id: `TEST-MESSAGE-${String(state.nextId++).padStart(4, '0')}`,
          client_message_id: body.client_message_id ?? null,
          content: body.content.trim(),
          sender: actor,
          sender_role: isCitizen ? 'citizen' : 'operator',
          delivery_state: isCitizen
            ? 'received_by_dispatch'
            : 'awaiting_citizen_poll',
          read_state: 'not_read',
          created_at: new Date().toISOString(),
        };
        incident.messages.push(message);
        incident.messages.sort((a, b) => a.created_at.localeCompare(b.created_at));
        recordHistory(
          incident,
          isCitizen ? 'TEST citizen message received' : 'TEST message sent to citizen',
          message.sender,
          {
            message_id: message.id,
            message_content: message.content,
            delivery_state: message.delivery_state,
          },
        );
        await persistState();
        sendJson(response, 201, { message });
        return;
      }

      if (subresource) {
        sendJson(response, 404, { error: 'TEST subresource not found.' });
        return;
      }

      if (request.method === 'DELETE') {
        const actor = 'TEST Operator Akua Sarpong';
        if (incident.assigned_to && incident.assigned_to !== actor) {
          sendJson(response, 409, {
            error: `Incident is already being handled by ${incident.assigned_to}.`,
            incident,
          });
          return;
        }
        incident.status = 'dismissed';
        recordHistory(incident, 'dismissed', actor);
        await persistState();
        sendJson(response, 200, { incident });
        return;
      }

      if (request.method === 'PATCH') {
        const body = await readJson(request);
        if (body.expected_version !== undefined && body.expected_version !== incident.version) {
          sendJson(response, 409, { error: 'Incident changed; refresh before retrying.', incident });
          return;
        }
        const actor = body.operator_name ?? 'TEST Operator Akua Sarpong';
        if (
          incident.assigned_to &&
          incident.assigned_to !== actor &&
          (body.status !== undefined || body.assigned_to !== undefined)
        ) {
          sendJson(response, 409, {
            error: `Incident is already being handled by ${incident.assigned_to}.`,
            incident,
          });
          return;
        }
        if (body.status !== undefined && !statuses.has(body.status)) {
          sendJson(response, 400, { error: 'Invalid incident status.' });
          return;
        }
        if (
          body.status !== undefined &&
          body.status !== incident.status &&
          !allowedTransitions[incident.status]?.has(body.status)
        ) {
          sendJson(response, 409, {
            error: `Invalid status transition: ${incident.status} -> ${body.status}.`,
          });
          return;
        }
        if (
          body.status === 'resolved' &&
          (!String(body.outcome ?? '').trim() ||
            !String(body.resolution_notes ?? '').trim())
        ) {
          sendJson(response, 400, {
            error: 'Outcome and resolution notes are required to close an incident.',
          });
          return;
        }
        if (body.severity !== undefined && !priorities.includes(body.severity)) {
          sendJson(response, 400, { error: 'Invalid incident severity.' });
          return;
        }
        if (body.status !== undefined) incident.status = body.status;
        if (body.assigned_to !== undefined) incident.assigned_to = body.assigned_to || null;
        if (body.operator_name !== undefined) incident.operator_name = body.operator_name;
        if (body.dispatch_unit !== undefined) incident.dispatch_unit = body.dispatch_unit;
        if (body.eta_minutes !== undefined) incident.eta_minutes = body.eta_minutes;
        if (body.severity !== undefined) incident.severity = body.severity;
        if (body.merged_into !== undefined) incident.merged_into = body.merged_into;
        if (body.citizen_safe === true) incident.citizen_safe = true;
        if (body.outcome !== undefined) incident.outcome = body.outcome;
        if (body.status === 'resolved') {
          incident.resolved_at = new Date().toISOString();
          incident.resolved_by = body.operator_name ?? 'TEST Operator Akua Sarpong';
          incident.resolution_notes = String(body.resolution_notes).trim();
          incident.notes.push({
            id: `TEST-NOTE-${String(state.nextId++).padStart(4, '0')}`,
            content: incident.resolution_notes,
            actor: incident.resolved_by,
            created_at: incident.resolved_at,
          });
        }
        recordHistory(
          incident,
          body.action ?? `updated to ${incident.status}`,
          actor,
          body.status === 'resolved'
            ? {
                outcome: incident.outcome,
                resolution_notes: incident.resolution_notes,
                resolved_by: incident.resolved_by,
              }
            : {},
        );
        await persistState();
        sendJson(response, 200, { incident });
        return;
      }

      sendJson(response, 405, { error: 'Method not allowed.' });
    } catch (error) {
      sendJson(response, error.statusCode ?? 500, {
        error: error.statusCode ? error.message : 'TEST harness request failed.',
      });
    }
  });

  return {
    server,
    state,
    listen() {
      return new Promise((resolve, reject) => {
        stateReady.then(() => {
          server.once('error', reject);
          server.listen(port, host, () => {
            server.off('error', reject);
            resolve(server.address());
          });
        }, reject);
      });
    },
    close() {
      return new Promise((resolve, reject) => {
        server.close((error) => (error ? reject(error) : resolve()));
      });
    },
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const app = createTestDispatcherServer({
    persistencePath:
      process.env.EAWS_TEST_STATE_FILE ??
      path.join(currentDirectory, '.data', 'dispatcher-state.json'),
  });
  app.listen().then((address) => {
    console.log(`EAWS TEST-ONLY dispatcher at http://${address.address}:${address.port}`);
    console.log(`TEST data persists at ${process.env.EAWS_TEST_STATE_FILE ?? path.join(currentDirectory, '.data', 'dispatcher-state.json')}`);
    console.log('TEST chat stays on the local API; no SMS, push, calls, or emergency services are contacted.');
  }).catch((error) => {
    console.error('Could not start the local dispatcher test harness:', error);
    process.exitCode = 1;
  });
}
