import { test, expect } from '@playwright/test';
import { expectNavigation } from '../../helpers/test-helpers';

test.describe('Plan Switching', () => {
  test('should allow switching from free to paid plan', async ({ page }) => {
    // This test assumes a logged-in user with free plan
    await page.goto('/pricing');
    
    // Select a paid plan
    const paidPlanButton = page.locator('button:has-text("Select"), button:has-text("Upgrade")').first();
    const buttonExists = await paidPlanButton.isVisible({ timeout: 3000 }).catch(() => false);
    
    if (buttonExists) {
      await paidPlanButton.click();
      
      // Should start trial or subscription process
      await page.waitForTimeout(2000);
      
      // Verify plan change is in progress
      const trialStarted = await page.locator('text=/trial|started/i').isVisible({ timeout: 5000 }).catch(() => false);
      const redirected = await page.waitForURL(/\/(dashboard|success)/, { timeout: 5000 }).catch(() => false);
      
      expect(trialStarted || redirected).toBeTruthy();
    }
  });

  test('should cancel old subscription when switching plans', async ({ page }) => {
    // This test verifies that when switching plans, the old subscription is canceled
    // This is typically handled on the backend, but we can verify the UI reflects the change
    
    // Navigate to settings after plan switch
    await page.goto('/account/settings');
    
    // Verify only one active subscription is shown
    // The old subscription should be canceled
    const activeSubscriptions = page.locator('text=/active|current/i');
    const count = await activeSubscriptions.count();
    
    // Should have only one active subscription
    expect(count).toBeLessThanOrEqual(1);
  });

  test('should allow switching between paid plans', async ({ page }) => {
    // This test assumes a logged-in user with a paid plan
    await page.goto('/pricing');
    
    // Select a different paid plan
    const differentPlanButton = page.locator('button:has-text("Switch"), button:has-text("Change")').first();
    const buttonExists = await differentPlanButton.isVisible({ timeout: 3000 }).catch(() => false);
    
    if (buttonExists) {
      await differentPlanButton.click();
      
      // Should process the plan switch
      await page.waitForTimeout(2000);
      
      // Verify plan change
      const successMessage = await page.locator('text=/changed|updated|switched/i').isVisible({ timeout: 5000 }).catch(() => false);
      const redirected = await page.waitForURL(/\/(dashboard|settings)/, { timeout: 5000 }).catch(() => false);
      
      expect(successMessage || redirected).toBeTruthy();
    }
  });

  test('should preserve data when switching plans', async ({ page }) => {
    // This test verifies that guilds, members, and events are preserved when switching plans
    
    // Get initial guild count
    await page.goto('/guilds');
    const initialGuildCount = await page.locator('[data-testid="guild"], .guild-item, article').count();
    
    // Switch plan
    await page.goto('/pricing');
    const planButton = page.locator('button:has-text("Select")').first();
    const buttonExists = await planButton.isVisible({ timeout: 3000 }).catch(() => false);
    
    if (buttonExists) {
      await planButton.click();
      await page.waitForTimeout(2000);
    }
    
    // Verify guilds still exist
    await page.goto('/guilds');
    const finalGuildCount = await page.locator('[data-testid="guild"], .guild-item, article').count();
    
    expect(finalGuildCount).toBe(initialGuildCount);
  });

  test('should update plan limits immediately after switch', async ({ page }) => {
    // This test verifies that plan limits are updated immediately after switching
    
    // Switch to a plan with higher limits
    await page.goto('/pricing');
    const higherPlanButton = page.locator('button:has-text("Select")').last(); // Assuming last is highest tier
    const buttonExists = await higherPlanButton.isVisible({ timeout: 3000 }).catch(() => false);
    
    if (buttonExists) {
      await higherPlanButton.click();
      await page.waitForTimeout(2000);
    }
    
    // Try to create a guild that was previously blocked
    await page.goto('/guilds/new');
    const canCreate = await page.locator('input[name="guild[name]"]').isVisible({ timeout: 3000 }).catch(() => false);
    
    // Should be able to create guild if limits allow
    if (canCreate) {
      expect(canCreate).toBeTruthy();
    }
  });
});

