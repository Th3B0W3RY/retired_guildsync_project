/**
 * Shared helper functions for generating test failure summaries
 * Used by both the live reporter and the post-test script
 */

import fs from 'fs';
import path from 'path';

/**
 * Strip ANSI color codes from text
 */
export function stripAnsi(text) {
  if (typeof text !== 'string') return text;
  return text.replace(/\x1b\[[0-9;]*m/g, '');
}

/**
 * Clean error message - remove color codes and normalize whitespace
 */
export function cleanError(error) {
  if (!error) return '';
  return stripAnsi(error)
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Convert absolute path to relative path
 */
export function getRelativePath(filePath, workspaceRoot) {
  if (!filePath) return 'unknown';
  try {
    // If already relative, return as is
    if (!path.isAbsolute(filePath)) {
      return filePath;
    }
    // Convert absolute to relative
    return path.relative(workspaceRoot, filePath);
  } catch (error) {
    // If conversion fails, return original
    return filePath;
  }
}

/**
 * Extract skip reason from source code by reading the file and parsing the line
 */
export function extractSkipReasonFromSource(annotation) {
  if (!annotation || !annotation.location) return null;
  
  const filePath = annotation.location.file;
  const lineNumber = annotation.location.line;
  
  if (!filePath || !lineNumber) return null;
  
  try {
    // Read the source file
    const sourceCode = fs.readFileSync(filePath, 'utf-8');
    const lines = sourceCode.split('\n');
    
    // Get the line where test.skip() was called (line numbers are 1-indexed)
    const targetLine = lines[lineNumber - 1];
    
    if (!targetLine) return null;
    
    // PRIORITY 1: Look for comments on the same line or following lines (most reliable)
    // Check the same line first (for inline comments)
    const sameLineCommentMatch = targetLine.match(/\/\/\s*(?:Reason|SKIP):\s*(.+)/i);
    if (sameLineCommentMatch && sameLineCommentMatch[1]) {
      return sameLineCommentMatch[1].trim();
    }
    
    // PRIORITY 2: Check following lines for comment blocks (up to 5 lines)
    // Look for comments that contain "Reason:" or "SKIP:"
    // lineNumber is 1-indexed, so we need to subtract 1 to get 0-indexed array position
    for (let i = 0; i < 5 && (lineNumber - 1 + i) < lines.length; i++) {
      const checkLine = lines[lineNumber - 1 + i];
      if (!checkLine) break;
      
      // Skip if we hit the function body start (opening brace)
      if (checkLine.trim().startsWith('{') && i > 0) {
        break;
      }
      
      // Look for "Reason:" comment (highest priority - this is the explicit reason)
      const reasonMatch = checkLine.match(/\/\/\s*Reason:\s*(.+)/i);
      if (reasonMatch && reasonMatch[1]) {
        return reasonMatch[1].trim();
      }
      
      // Look for "SKIP:" comment (might be multi-line)
      const skipCommentMatch = checkLine.match(/\/\/\s*SKIP:\s*(.+)/i);
      if (skipCommentMatch && skipCommentMatch[1]) {
        // Try to get more context from following lines if this is just the start
        let reason = skipCommentMatch[1].trim();
        if (reason && reason.length < 50 && (lineNumber - 1 + i + 1) < lines.length) {
          const nextCommentLine = lines[lineNumber - 1 + i + 1];
          if (nextCommentLine && nextCommentLine.trim().startsWith('//')) {
            const nextComment = nextCommentLine.replace(/^\s*\/\/\s*/, '').trim();
            if (nextComment && !nextComment.match(/^(Reason|The API|which expects)/i)) {
              reason += ' ' + nextComment;
            }
          }
        }
        return reason;
      }
    }
    
    // PRIORITY 3: Try to extract the reason from test.skip('reason') or test.skip("reason")
    // Only use this if no comments were found (to avoid matching test titles)
    // Match: test.skip('reason'), test.skip("reason"), test.skip(`reason`)
    const skipMatch = targetLine.match(/test\.skip\s*\(\s*['"`]([^'"`]+)['"`]\s*[,)]/);
    if (skipMatch && skipMatch[1]) {
      const extractedReason = skipMatch[1].trim();
      // Only return if it doesn't look like a test title (test titles usually start with "should")
      // If it starts with "should", it's probably the test title, not a reason
      if (!extractedReason.toLowerCase().startsWith('should')) {
        return extractedReason;
      }
    }
    
    // PRIORITY 4: Check for multi-line cases where the reason might be on the next line
    // test.skip(
    //   'reason'
    // )
    if (lineNumber < lines.length) {
      const nextLine = lines[lineNumber];
      const nextLineMatch = nextLine.match(/^\s*['"`]([^'"`]+)['"`]\s*[,)]/);
      if (nextLineMatch && nextLineMatch[1]) {
        const extractedReason = nextLineMatch[1].trim();
        // Only return if it doesn't look like a test title
        if (!extractedReason.toLowerCase().startsWith('should')) {
          return extractedReason;
        }
      }
    }
    
    return null;
  } catch (error) {
    // If we can't read the file, return null
    return null;
  }
}

/**
 * Extract skip reason from test and result objects
 * Checks multiple possible locations where Playwright might store the skip reason
 */
export function extractSkipReason(test, result, debug = false) {
  let skipReason = null;
  
  // Method 1: Check result.error.message (most common for programmatic skips via test.skip())
  if (result.error) {
    if (typeof result.error === 'string') {
      skipReason = result.error;
    } else if (result.error.message) {
      skipReason = result.error.message;
    } else if (result.error.toString && result.error.toString() !== '[object Object]') {
      skipReason = result.error.toString();
    }
  }
  
  // Method 2: Check test.skipReason (if set directly on test object)
  if (!skipReason && test.skipReason) {
    skipReason = test.skipReason;
  }
  
  // Method 3: Check test.annotations (Playwright metadata)
  if (!skipReason && test.annotations && Array.isArray(test.annotations)) {
    const skipAnnotation = test.annotations.find(ann => ann.type === 'skip');
    if (skipAnnotation) {
      // First check if description/reason/message exists in annotation
      skipReason = skipAnnotation.description || skipAnnotation.reason || skipAnnotation.message;
      
      // If not found, try to extract from source code
      if (!skipReason && skipAnnotation.location) {
        skipReason = extractSkipReasonFromSource(skipAnnotation);
      }
    }
  }
  
  // Method 3b: Also check result.annotations (sometimes the annotation is on the result)
  if (!skipReason && result.annotations && Array.isArray(result.annotations)) {
    const skipAnnotation = result.annotations.find(ann => ann.type === 'skip');
    if (skipAnnotation) {
      skipReason = skipAnnotation.description || skipAnnotation.reason || skipAnnotation.message;
      
      // If not found, try to extract from source code
      if (!skipReason && skipAnnotation.location) {
        skipReason = extractSkipReasonFromSource(skipAnnotation);
      }
    }
  }
  
  // Method 4: Check nested error properties
  if (!skipReason && result.error) {
    skipReason = result.error.cause?.message || 
                result.error.reason ||
                result.error.description;
  }
  
  // Method 5: Extract from error stack if it contains the reason
  if (!skipReason && result.error?.stack) {
    const stackLines = result.error.stack.split('\n');
    // Sometimes the reason is in the first line of the stack
    for (const line of stackLines) {
      if (line.includes('skip') || line.length > 20) {
        const match = line.match(/skip[:\s]+(.+)/i);
        if (match && match[1]) {
          skipReason = match[1].trim();
          break;
        }
      }
    }
  }
  
  // Clean and validate the skip reason
  if (skipReason) {
    skipReason = String(skipReason).trim();
    // Remove common prefixes that might be added by Playwright
    skipReason = skipReason.replace(/^(Test was skipped|Skipped|Skip):\s*/i, '');
  }
  
  // Final fallback
  if (!skipReason || skipReason === 'undefined' || skipReason === '' || skipReason === '[object Object]') {
    skipReason = 'No reason provided';
    if (debug) {
      console.log('WARNING: Could not find skip reason, using fallback');
    }
  }
  
  return skipReason;
}

/**
 * Generate summary text from failures and skipped tests
 */
export function generateSummaryText({ failures, skipped, totalTests, passedTests, failed, duration, workspaceRoot }) {
  const lines = [];
  
  // Header
  lines.push('='.repeat(80));
  lines.push('TEST FAILURE SUMMARY');
  lines.push('='.repeat(80));
  lines.push('');
  
  // Overall stats
  const total = totalTests || 0;
  const passed = passedTests || 0;
  const failedCount = failed || failures.length || 0;
  const skippedCount = skipped.length || 0;
  
  lines.push(`Total Tests: ${total}`);
  lines.push(`Passed: ${passed}`);
  lines.push(`Failed: ${failedCount}`);
  lines.push(`Skipped: ${skippedCount}`);
  lines.push(`Duration: ${(duration / 1000).toFixed(2)}s`);
  lines.push('');
  
  // Show skipped tests section if any were skipped
  if (skipped.length > 0) {
    lines.push('='.repeat(80));
    lines.push(`SKIPPED TESTS (${skippedCount})`);
    lines.push('='.repeat(80));
    lines.push('');
    lines.push('The following tests were skipped during execution:');
    lines.push('');
    
    // Group skipped tests by file
    const skippedByFile = {};
    skipped.forEach(skip => {
      const file = skip.file;
      if (!skippedByFile[file]) {
        skippedByFile[file] = [];
      }
      skippedByFile[file].push(skip);
    });
    
    // Sort files alphabetically, then sort tests within each file by title, then line
    const sortedFiles = Object.keys(skippedByFile).sort();
    sortedFiles.forEach(file => {
      const fileSkipped = skippedByFile[file];
      // Sort by title first, then by line number
      fileSkipped.sort((a, b) => {
        const titleCompare = a.title.localeCompare(b.title);
        if (titleCompare !== 0) return titleCompare;
        return (a.line || 0) - (b.line || 0);
      });
      
      lines.push(`FILE: ${file}`);
      lines.push('-'.repeat(80));
      
      fileSkipped.forEach((skip, index) => {
        lines.push(`${index + 1}. ${skip.title}`);
        if (skip.line > 0) {
          lines.push(`   Line: ${skip.line}`);
        }
        const cleanReason = cleanError(skip.reason);
        lines.push(`   Reason: ${cleanReason}`);
        lines.push('');
      });
    });
    
    lines.push('='.repeat(80));
    lines.push('');
  }
  
  if (failures.length === 0) {
    if (skipped.length > 0) {
      lines.push('All non-skipped tests passed!');
    } else {
      lines.push('All tests passed!');
    }
    return lines.join('\n');
  }
  
  // Check for setup/configuration issues
  const setupFailures = failures.filter(f => 
    f.file.includes('setup/verify') || 
    f.error.toLowerCase().includes('setup') ||
    f.error.toLowerCase().includes('not configured') ||
    f.error.toLowerCase().includes('test user')
  );
  
  if (setupFailures.length > 0) {
    lines.push('SETUP/CONFIGURATION ISSUES DETECTED');
    lines.push('='.repeat(80));
    lines.push('Some tests failed due to environment setup issues.');
    lines.push('This may cause cascading failures in other tests.');
    lines.push('');
    lines.push('SETUP FAILURES:');
    // Sort setup failures by title, then line number
    setupFailures.sort((a, b) => {
      const titleCompare = a.title.localeCompare(b.title);
      if (titleCompare !== 0) return titleCompare;
      return (a.line || 0) - (b.line || 0);
    });
    setupFailures.forEach((failure, index) => {
      lines.push(`${index + 1}. ${failure.title}`);
      const cleanErr = cleanError(failure.error);
      lines.push(`   ${cleanErr.split('\n')[0]}`);
      lines.push('');
    });
    lines.push('Please fix setup issues first, then re-run tests.');
    lines.push('Run: npm run test:verify');
    lines.push('');
    lines.push('='.repeat(80));
    lines.push('');
  }
  
  // Failure details
  lines.push('='.repeat(80));
  lines.push(`FAILED TESTS (${failedCount})`);
  lines.push('='.repeat(80));
  lines.push('');
  
  // Sort failures by file, then by title, then by line number
  const sortedFailures = [...failures].sort((a, b) => {
    const fileCompare = a.file.localeCompare(b.file);
    if (fileCompare !== 0) return fileCompare;
    const titleCompare = a.title.localeCompare(b.title);
    if (titleCompare !== 0) return titleCompare;
    return (a.line || 0) - (b.line || 0);
  });
  
  sortedFailures.forEach((failure, index) => {
    lines.push(`${index + 1}. ${failure.title}`);
    lines.push(`   File: ${failure.file}:${failure.line || 0}`);
    lines.push(`   Status: ${failure.status.toUpperCase()}`);
    lines.push(`   Duration: ${(failure.duration / 1000).toFixed(2)}s`);
    if (failure.retry > 0) {
      lines.push(`   Retry: ${failure.retry}`);
    }
    
    // Clean error message
    const cleanErr = cleanError(failure.error);
    lines.push(`   Error: ${cleanErr}`);
    
    // Include error details if available (truncated and cleaned)
    if (failure.errorDetails) {
      const details = failure.errorDetails.split('\n').slice(0, 3);
      if (details.length > 0) {
        lines.push(`   Stack:`);
        details.forEach(line => {
          const cleaned = stripAnsi(line.trim());
          if (cleaned) {
            lines.push(`     ${cleaned}`);
          }
        });
        if (failure.errorDetails.split('\n').length > 3) {
          lines.push(`     ... (truncated, see HTML report for full details)`);
        }
      }
    }
    
    lines.push('');
  });
  
  // Footer
  lines.push('='.repeat(80));
  lines.push(`For detailed information, see: playwright-report/index.html`);
  lines.push('='.repeat(80));
  
  return lines.join('\n');
}
