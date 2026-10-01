import { createClient } from 'npm:@insforge/sdk';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-API-Key'
};

export default async function(req) {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }

  const client = createClient({
    baseUrl: Deno.env.get('INSFORGE_BASE_URL') ?? 'https://gcj3agx8.us-west.insforge.app',
    anonKey: Deno.env.get('ANON_KEY')
  });

  let body;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON body' }), {
      status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }

  const { table, event, record, old_record } = body;
  const payload = {
    table,
    event,
    record: record ?? null,
    old_record: old_record ?? null,
    timestamp: new Date().toISOString()
  };

  const publishes = [];

  await client.realtime.connect();

  if (table === 'incidents') {
    // Broadcast to all incident-related channels
    const channels = [
      'incidents',
      'shell-incident-count',
      'police-incident-queue',
      'fire-incident-queue',
      'ambulance-incident-queue',
      'nadmo-incident-queue'
    ];
    for (const ch of channels) {
      await client.realtime.subscribe(ch);
      publishes.push(client.realtime.publish(ch, 'db:incidents', payload));
    }
  } else if (table === 'alerts') {
    await client.realtime.subscribe('alerts');
    publishes.push(client.realtime.publish('alerts', 'db:alerts', payload));
  } else if (table === 'incident_logs') {
    await client.realtime.subscribe('radio-comms-logs');
    publishes.push(
      client.realtime.publish('radio-comms-logs', 'incident_log_created', payload.record)
    );
  }

  await Promise.allSettled(publishes);

  return new Response(
    JSON.stringify({ ok: true, table, event, channels_notified: publishes.length }),
    { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  );
}
