# Page Object Model (POM)

This directory contains Page Object Model classes that encapsulate page interactions and selectors, making tests more maintainable and readable.

## Benefits

- **Centralized Selectors**: All selectors for a page are in one place
- **Reusability**: Page methods can be reused across multiple tests
- **Maintainability**: When UI changes, update selectors in one place
- **Readability**: Tests read like user interactions: `await loginPage.login(email, password)`

## Structure

Each page object:
- Contains all selectors for that page
- Provides methods for common actions (fill, click, submit)
- Provides assertion helpers
- Handles navigation to the page

## Usage Example

**Before (scattered selectors):**
```javascript
test('should login', async ({ page }) => {
  await page.goto('/login');
  await page.fill('input[name="user[email]"]', 'test@example.com');
  await page.fill('input[name="user[password]"]', 'password123');
  await page.click('input[type="submit"], button[type="submit"]');
});
```

**After (using page objects):**
```javascript
import { LoginPage } from '../../pages';

test('should login', async ({ page }) => {
  const loginPage = new LoginPage(page);
  await loginPage.goto();
  await loginPage.login('test@example.com', 'password123');
});
```

## Available Page Objects

- `LoginPage` - Login form interactions
- `RegistrationPage` - User registration form
- `MfaVerificationPage` - MFA code verification
- `MfaSetupPage` - MFA setup with QR code
- `PasswordResetPage` - Password reset request form

## Adding New Page Objects

1. Create a new file: `tests/pages/YourPageName.js`
2. Export a class that:
   - Takes `page` in constructor
   - Defines `selectors` object
   - Provides action methods
   - Provides assertion helpers
3. Export from `tests/pages/index.js`

Example template:
```javascript
export class YourPage {
  constructor(page) {
    this.page = page;
  }

  selectors = {
    // Define all selectors here
  };

  async goto() {
    await this.page.goto('/your-path');
  }

  // Action methods
  async doSomething() {
    // Implementation
  }

  // Assertion helpers
  async expectSomething() {
    // Implementation
  }
}
```
