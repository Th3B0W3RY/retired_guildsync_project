import { test, expect } from '@playwright/test';
import { createTestUserAndGetToken, loginAndSettle } from '../../helpers/test-helpers';
import { getBaseURL } from '../../../config/test-config.js';

test.describe('Roadmap / Feature Requests', () => {
  test('should display roadmap index without authentication', async ({ page }) => {
    await page.goto('/roadmap');
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    const url = page.url();
    expect(url).toContain('/roadmap');
    await expect(page.locator('h1').first()).toBeVisible({ timeout: 5000 });
  });

  test('should display a feature request detail page without authentication', async ({ page }) => {
    // Load the index first to find any existing feature request link
    await page.goto('/roadmap');
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    const featureLink = page.locator('a[href*="/roadmap/"]').first();
    const hasLink = await featureLink.isVisible({ timeout: 3000 }).catch(() => false);

    if (!hasLink) {
      test.skip('No feature requests found on roadmap index — cannot test detail page');
      return;
    }

    await featureLink.click();
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    expect(page.url()).toMatch(/\/roadmap\/.+/);
    await expect(page.locator('h1').first()).toBeVisible({ timeout: 5000 });
  });

  test('should redirect unauthenticated users when voting', async ({ request }) => {
    const voteRes = await request.post(`${getBaseURL()}/roadmap/requests/1/vote`, {
      headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
      data: {}
    });

    // 302 (Devise redirect), 401, 403, or 422 (CSRF before auth) are all valid rejections
    expect([302, 401, 403, 422]).toContain(voteRes.status());
  });

  test('should redirect unauthenticated users when creating a request', async ({ request }) => {
    const createRes = await request.post(`${getBaseURL()}/roadmap/requests`, {
      headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
      data: { feature_request: { title: 'Test', description: 'Test' } }
    });

    expect([302, 401, 403, 422]).toContain(createRes.status());
  });

  test('should allow authenticated user to view roadmap', async ({ page, request }) => {
    const { email, password } = await createTestUserAndGetToken(request, {
      emailAffix: 'rm',
      usernameAffix: 'rm',
      authMethod: 'discord'
    });
    await loginAndSettle(page, email, password);

    await page.goto('/roadmap');
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});

    const url = page.url();
    if (url.includes('/login') || url.includes('/mfa')) {
      throw new Error(`Redirected to auth when accessing roadmap: ${url}`);
    }

    await expect(page.locator('h1').first()).toBeVisible({ timeout: 5000 });
  });
});
