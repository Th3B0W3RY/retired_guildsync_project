import { test, expect } from '@playwright/test';
import { createTestUserAndGetToken, loginAndSettle } from '../../helpers/test-helpers';

test.describe('Global Search', () => {
  test('should redirect unauthenticated users to login', async ({ page }) => {
    await page.goto('/search');
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    expect(page.url()).toMatch(/\/login|\/mfa/);
  });

  test('should return empty results JSON when authenticated with no query', async ({ page, request }) => {
    const { email, password } = await createTestUserAndGetToken(request, {
      emailAffix: 'srch',
      usernameAffix: 'srch',
      authMethod: 'discord'
    });
    await loginAndSettle(page, email, password);

    // /search is a JSON API — use page.request to carry the session cookie
    const res = await page.request.get('/search', {
      headers: { Accept: 'application/json' }
    });

    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body).toHaveProperty('results');
    expect(Array.isArray(body.results)).toBeTruthy();
  });

  test('should return JSON results for a search query', async ({ page, request }) => {
    const { email, password } = await createTestUserAndGetToken(request, {
      emailAffix: 'srchq',
      usernameAffix: 'srchq',
      authMethod: 'discord'
    });
    await loginAndSettle(page, email, password);

    const res = await page.request.get('/search?q=guild', {
      headers: { Accept: 'application/json' }
    });

    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body).toHaveProperty('results');
    expect(body).toHaveProperty('total');
  });
});
