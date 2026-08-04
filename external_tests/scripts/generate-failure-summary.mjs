/**
 * Post-test script to generate a failure summary from JSON results
 * Can be run independently after tests complete
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import util from 'util';
import dotenv from 'dotenv';

// ES module equivalents for __dirname
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Load runner-specific overrides from external_tests/.env regardless of cwd.
dotenv.config({ path: path.join(__dirname, '..', '.env') });

// Import shared helpers
import { 
  stripAnsi, 
  cleanError, 
  getRelativePath, 
  extractSkipReason, 
  generateSummaryText 
} from '../reporters/summary-helpers.mjs';

const RESULTS_FILE = path.join(__dirname, '..', 'test-results', 'results.json');
const OUTPUT_FILE = path.join(__dirname, '..', 'test-results', 'failures-summary.txt');
const WORKSPACE_ROOT = process.cwd();

function generateSummary() {
  if (!fs.existsSync(RESULTS_FILE)) {
    console.error(`Results file not found: ${RESULTS_FILE}`);
    process.exit(1);
  }

  const results = JSON.parse(fs.readFileSync(RESULTS_FILE, 'utf-8'));
  const failures = [];
  const skipped = [];
  let totalTests = 0;
  let passedTests = 0;
  let totalDuration = 0;

  // Extract failures and skipped tests from results, and calculate stats
  function extractResults(suite) {
    if (suite.specs) {
      suite.specs.forEach(spec => {
        spec.tests.forEach(test => {
          totalTests++;
          test.results.forEach(result => {
            totalDuration += result.duration || 0;
            
            if (result.status === 'failed' || result.status === 'timedOut') {
              failures.push({
                title: `${spec.title} > ${test.title}`,
                file: getRelativePath(spec.file || 'unknown', WORKSPACE_ROOT),
                line: test.location?.line || spec.line || 0,
                status: result.status,
                duration: result.duration,
                error: stripAnsi(result.error?.message || 'Unknown error'),
                errorDetails: stripAnsi(result.error?.stack || ''),
                retry: result.retry || 0,
              });
            } else if (result.status === 'skipped') {
              // DEBUG: Log the structure of test and result objects to understand skip reason location
              const debugMode = process.env.DEBUG_SKIP_REASONS === '1';
              if (debugMode) {
                console.log('\n=== DEBUG: Skipped Test (JSON) ===');
                console.log('Test object keys:', Object.keys(test));
                console.log('Test object:', util.inspect(test, { depth: 2, colors: true }));
                console.log('\nResult object keys:', Object.keys(result));
                console.log('Result object:', util.inspect(result, { depth: 2, colors: true }));
                console.log('Result.error:', util.inspect(result.error, { depth: 3, colors: true }));
                if (test.annotations) {
                  console.log('Test.annotations:', util.inspect(test.annotations, { depth: 2, colors: true }));
                }
                console.log('=== END DEBUG ===\n');
              }
              
              // Extract skip reason using shared function
              const skipReason = extractSkipReason(test, result, debugMode);
              
              if (debugMode) {
                console.log(`Found skip reason: "${skipReason}"`);
              }
              
              skipped.push({
                title: `${spec.title} > ${test.title}`,
                file: getRelativePath(spec.file || 'unknown', WORKSPACE_ROOT),
                line: test.location?.line || spec.line || 0,
                reason: stripAnsi(skipReason),
              });
            } else if (result.status === 'passed') {
              passedTests++;
            }
          });
        });
      });
    }

    if (suite.suites) {
      suite.suites.forEach(subSuite => extractResults(subSuite));
    }
  }

  extractResults(results);

  // Generate summary using shared function
  const summary = generateSummaryText({
    failures,
    skipped,
    totalTests,
    passedTests,
    failed: failures.length,
    duration: totalDuration,
    workspaceRoot: WORKSPACE_ROOT
  });

  // Write summary
  fs.writeFileSync(OUTPUT_FILE, summary, 'utf-8');
  
  console.log(`\n📊 Failure summary generated: ${OUTPUT_FILE}`);
  if (failures.length > 0) {
    console.log(`❌ ${failures.length} test(s) failed`);
  } else {
    console.log(`✅ All tests passed!`);
  }
  if (skipped.length > 0) {
    console.log(`⏭️  ${skipped.length} test(s) skipped (see summary for details)`);
  }
}

generateSummary();
