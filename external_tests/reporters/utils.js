/**
 * Utility functions for reporters
 */

/**
 * Inspect an object recursively to a specified depth
 * Useful for debugging complex objects
 * @param {any} obj - Object to inspect
 * @param {number} depth - Maximum depth to recurse
 * @param {number} currentDepth - Current recursion depth
 * @returns {string} String representation of the object
 */
export function inspect(obj, depth = 3, currentDepth = 0) {
  if (currentDepth >= depth || obj === null || typeof obj !== 'object') {
    return String(obj);
  }
  
  // Handle arrays
  if (Array.isArray(obj)) {
    if (obj.length === 0) return '[]';
    const items = obj.slice(0, 5).map(item => 
      `${'  '.repeat(currentDepth + 1)}${inspect(item, depth, currentDepth + 1)}`
    ).join('\n');
    const more = obj.length > 5 ? `\n${'  '.repeat(currentDepth + 1)}... (${obj.length - 5} more)` : '';
    return `[\n${items}${more}\n${'  '.repeat(currentDepth)}]`;
  }
  
  // Handle objects
  const entries = Object.entries(obj).slice(0, 20); // Limit to first 20 properties
  if (entries.length === 0) return '{}';
  
  const props = entries.map(([key, value]) => {
    const valueStr = inspect(value, depth, currentDepth + 1);
    return `${'  '.repeat(currentDepth + 1)}${key}: ${valueStr}`;
  }).join('\n');
  
  const more = Object.keys(obj).length > 20 ? `\n${'  '.repeat(currentDepth + 1)}... (${Object.keys(obj).length - 20} more properties)` : '';
  
  return `{\n${props}${more}\n${'  '.repeat(currentDepth)}}`;
}

/**
 * Try to use Node's util.inspect if available, otherwise fall back to custom inspect
 * @param {any} obj - Object to inspect
 * @param {object} options - Options for inspection
 * @returns {string} String representation of the object
 */
export function inspectObject(obj, options = {}) {
  try {
    // Try to use Node's built-in util.inspect if available
    const util = require('util');
    return util.inspect(obj, { 
      depth: options.depth || null, 
      colors: options.colors !== false,
      maxArrayLength: options.maxArrayLength || 100,
      maxStringLength: options.maxStringLength || 1000,
      ...options
    });
  } catch (e) {
    // Fall back to custom inspect function
    return inspect(obj, options.depth || 3);
  }
}
