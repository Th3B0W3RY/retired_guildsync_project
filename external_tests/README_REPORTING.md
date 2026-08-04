# Test Reporting Guide

This guide explains the different test reports available and how to use them.

## Report Types

### 1. HTML Report (Detailed)
**Location**: `playwright-report/index.html`  
**View**: `npm run test:report`

The HTML report provides:
- Full test execution details
- Screenshots and videos of failures
- Step-by-step test execution
- Time traces
- Interactive debugging

**Best for**: Detailed debugging, understanding test failures, sharing with team

### 2. Failure Summary (Concise)
**Location**: `test-results/failures-summary.txt`  
**Auto-generated**: After each test run  
**Regenerate**: `npm run test:summary`

The failure summary provides:
- Quick overview of test statistics
- List of failed tests only
- Error messages and file locations
- No verbose output

**Best for**: Quick review of failures, CI/CD logs, identifying patterns

### 3. JSON Results (Machine-readable)
**Location**: `test-results/results.json`  
**Format**: JSON

Contains all test results in structured format for:
- Custom processing scripts
- CI/CD integration
- Data analysis

## Console Output

By default, tests use the `line` reporter which provides:
- ✅ Minimal console output
- ✅ One line per test
- ✅ Summary at the end
- ✅ Link to failure summary if tests fail

### Changing Console Output

You can customize console output by modifying `playwright.config.js`:

```javascript
reporter: [
  ['html'],
  ['line'],        // Minimal (default)
  // ['list'],     // More verbose
  // ['dot'],      // Dots only
  ['json', { outputFile: 'test-results/results.json' }],
  ['./reporters/failure-summary-reporter.js']
]
```

## Example Failure Summary

```
================================================================================
TEST FAILURE SUMMARY
================================================================================

Total Tests: 45
Passed: 40
Failed: 5
Skipped: 0
Duration: 123.45s

================================================================================
FAILED TESTS (5)
================================================================================

1. User Login > should successfully login with valid credentials
   File: tests/integration/auth/login.spec.js:9
   Status: FAILED
   Duration: 2.34s
   Error: Timeout 10000ms exceeded while waiting for event "page.goto"
   Details:
      at tests/integration/auth/login.spec.js:15:5
      ... (truncated, see HTML report for full details)

2. Guild Creation > should successfully create a new guild with valid data
   File: tests/integration/guilds/create.spec.js:30
   Status: FAILED
   Duration: 5.67s
   Error: Element not found: input[name="guild[name]"]
   Details:
      at tests/integration/guilds/create.spec.js:35:8
      ... (truncated, see HTML report for full details)

...

================================================================================
For detailed information, see: playwright-report/index.html
================================================================================
```

## Customizing the Failure Summary

The failure summary reporter can be customized in `playwright.config.js`:

```javascript
['./reporters/failure-summary-reporter.js', {
  outputFile: 'test-results/custom-summary.txt',  // Custom output file
}]
```

## Tips

1. **Quick Review**: Check `failures-summary.txt` first for a quick overview
2. **Deep Dive**: Use HTML report for detailed debugging
3. **CI/CD**: Use failure summary in CI logs, HTML report for artifacts
4. **Regenerate**: Run `npm run test:summary` anytime to regenerate from JSON results

## Troubleshooting

**Summary file not generated?**
- Ensure tests completed (even with failures)
- Check that `test-results/results.json` exists
- Run `npm run test:summary` manually

**Summary file is empty?**
- All tests passed! ✅
- Or check that the JSON results file is valid

**Want more/less detail?**
- Edit `reporters/failure-summary-reporter.js` to customize output format
- Modify the `generateSummary()` method

