import { test, expect } from '@playwright/test';
import { createTestUserAndGetToken, createGuildViaAPI } from '../../helpers/test-helpers';
import { getAPIBaseURL } from '../../../config/test-config.js';

test.describe('Event Participation', () => {
  let user;
  let guildId;
  let eventId;

  async function createEvent(request, token, guild, overrides = {}) {
    const scheduledAt = overrides.scheduled_at || new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
    const response = await request.post(`${getAPIBaseURL()}/guilds/${guild}/events`, {
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: 'application/json',
        'Content-Type': 'application/json'
      },
      data: {
        event: {
          title: overrides.title || `Participation Test ${Date.now()}`,
          event_type: overrides.event_type || 'raid',
          scheduled_at: scheduledAt,
          duration: overrides.duration || 60
        }
      }
    });

    expect(response.status()).toBe(201);
    const body = await response.json();
    return body.id || body.event?.id;
  }

  function authHeaders(token) {
    return {
      Authorization: `Bearer ${token}`,
      Accept: 'application/json',
      'Content-Type': 'application/json'
    };
  }

  test.beforeEach(async ({ request }) => {
    user = await createTestUserAndGetToken(request, {
      emailAffix: 'event-participant',
      usernameAffix: 'eventparticipant',
      authMethod: 'discord'
    });
    guildId = await createGuildViaAPI(request, user.token, `Participation Guild ${Date.now()}`);
    eventId = await createEvent(request, user.token, guildId);
  });

  test('should return event details for a real event', async ({ request }) => {
    const response = await request.get(`${getAPIBaseURL()}/events/${eventId}`, {
      headers: authHeaders(user.token)
    });

    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.id).toBe(eventId);
  });

  test('should allow user to participate in event', async ({ request }) => {
    const response = await request.post(`${getAPIBaseURL()}/events/${eventId}/participate`, {
      headers: authHeaders(user.token),
      data: {
        status: 'attending',
        notes: 'Will be there'
      }
    });

    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.status).toBe('attending');
    expect(body.notes).toBe('Will be there');
  });

  test('should allow user to leave event', async ({ request }) => {
    await request.post(`${getAPIBaseURL()}/events/${eventId}/participate`, {
      headers: authHeaders(user.token),
      data: { status: 'attending' }
    });

    const response = await request.delete(`${getAPIBaseURL()}/events/${eventId}/participate`, {
      headers: authHeaders(user.token)
    });

    expect(response.status()).toBe(204);
  });

  test('should list event participants', async ({ request }) => {
    await request.post(`${getAPIBaseURL()}/events/${eventId}/participate`, {
      headers: authHeaders(user.token),
      data: { status: 'attending' }
    });

    const response = await request.get(`${getAPIBaseURL()}/events/${eventId}/participants`, {
      headers: authHeaders(user.token)
    });

    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.participants.length).toBeGreaterThanOrEqual(1);
    expect(body.participants.some((participant) => participant.user_id === user.user.id)).toBeTruthy();
  });

  test('should handle past events through the current event API', async ({ request }) => {
    const pastEventId = await createEvent(request, user.token, guildId, {
      title: `Past Participation Test ${Date.now()}`,
      scheduled_at: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()
    });

    const response = await request.get(`${getAPIBaseURL()}/events/${pastEventId}`, {
      headers: authHeaders(user.token)
    });

    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.id).toBe(pastEventId);
  });
});
