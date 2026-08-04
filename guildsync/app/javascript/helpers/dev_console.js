/** Same host check as controllers/application.js — keep logs off in production. */
export function isDevHost() {
  if (typeof location === "undefined") return false
  const h = location.hostname
  return h === "localhost" || h === "127.0.0.1"
}

export function devLog(...args) {
  if (isDevHost()) console.log(...args)
}

export function devWarn(...args) {
  if (isDevHost()) console.warn(...args)
}

export function devError(...args) {
  if (isDevHost()) console.error(...args)
}
