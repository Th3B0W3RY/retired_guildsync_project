/**
 * Custom Playwright Reporter
 * Generates a concise summary of failed tests to a single file
 */

import fs from 'fs';
import path from 'path';
import { inspectObject } from './utils.js';
import { 
  stripAnsi, 
  cleanError, 
  getRelativePath as getRelativePathHelper, 
  extractSkipReason, 
  generateSummaryText 
} from './summary-helpers.mjs';

class FailureSummaryReporter {
  constructor(options = {}) {
    this.outputFile = options.outputFile || 'test-results/failures-summary.txt';
    this.failures = [];
    this.skipped = [];
    this.totalTests = 0;
    this.passedTests = 0;
    this.workspaceRoot = process.cwd();
  }

  onBegin(config, suite) {
    this.config = config;
    this.suite = suite;
    this.startTime = Date.now();
    // Use config rootDir if available, otherwise use process.cwd()
    this.workspaceRoot = config.rootDir || process.cwd();
  }

  // Convert absolute path to relative path (wrapper for shared function)
  getRelativePath(filePath) {
    return getRelativePathHelper(filePath, this.workspaceRoot);
  }

  onTestEnd(test, result) {
    const filePath = test.location?.file || 'unknown';
    
    // Track total tests
    this.totalTests++;
    
    if (result.status === 'failed' || result.status === 'timedOut') {
      this.failures.push({
        title: test.title,
        file: this.getRelativePath(filePath),
        line: test.location?.line || 0,
        status: result.status,
        duration: result.duration,
        error: stripAnsi(result.error?.message || 'Unknown error'),
        errorDetails: stripAnsi(result.error?.stack || ''),
      });
    } else if (result.status === 'skipped') {
      // DEBUG: Log the structure of test and result objects to understand skip reason location
      const debugMode = process.env.DEBUG_SKIP_REASONS === '1';
      if (debugMode) {
        console.log('\n=== DEBUG: Skipped Test ===');
        console.log('Test object keys:', Object.keys(test));
        console.log('Test object:', inspectObject(test, { depth: 2 }));
        console.log('\nResult object keys:', Object.keys(result));
        console.log('Result object:', inspectObject(result, { depth: 2 }));
        console.log('Result.error:', inspectObject(result.error, { depth: 3 }));
        if (test.annotations) {
          console.log('Test.annotations:', inspectObject(test.annotations, { depth: 2 }));
        }
        console.log('=== END DEBUG ===\n');
      }
      
      // Extract skip reason using shared function
      const skipReason = extractSkipReason(test, result, debugMode);
      
      if (debugMode) {
        console.log(`Found skip reason: "${skipReason}"`);
      }
      
      this.skipped.push({
        title: test.title,
        file: this.getRelativePath(filePath),
        line: test.location?.line || 0,
        reason: stripAnsi(skipReason),
      });
    } else if (result.status === 'passed') {
      this.passedTests++;
    }
  }

  onEnd(result) {
    const duration = Date.now() - this.startTime;
    const summary = this.generateSummary(result, duration);
    
    // Ensure directory exists
    const dir = path.dirname(this.outputFile);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    
    // Write summary to file
    fs.writeFileSync(this.outputFile, summary, 'utf-8');
    
    // Also log a brief message to console
    if (this.failures.length > 0) {
      console.log(`\n❌ ${this.failures.length} test(s) failed. Summary saved to: ${this.outputFile}`);
    }
    if (this.skipped.length > 0) {
      console.log(`⏭️  ${this.skipped.length} test(s) skipped. See summary for details.`);
    }
  }

  generateSummary(result, duration) {
    return generateSummaryText({
      failures: this.failures,
      skipped: this.skipped,
      totalTests: this.totalTests,
      passedTests: this.passedTests,
      failed: result.failed,
      duration,
      workspaceRoot: this.workspaceRoot
    });
  }
}

export default FailureSummaryReporter;

