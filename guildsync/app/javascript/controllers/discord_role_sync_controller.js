import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["rolesTable", "loading", "error"]
  static values = { guildId: String, i18n: Object }

  connect() {
    this._initialPlaceholderHTML = this.hasRolesTableTarget ? this.rolesTableTarget.innerHTML : ""
    this._lastSuccessfulRolesRender = false
    Promise.resolve(this.refreshRoles()).catch((error) => this.showError(this._messageFrom(error)))
  }

  async refreshRoles(event) {
    this._preventDefault(event)
    this.showLoading()
    this.hideError()

    try {
      const response = await fetch(`/guilds/${this.guildIdValue}/discord_roles`, {
        method: "GET",
        headers: {
          "Accept": "application/json",
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin"
      })

      if (!response.ok) {
        throw new Error(await this._parseErrorMessage(response, "Failed to fetch roles"))
      }

      const data = await this._safeJson(response)
      this.renderRoles(Array.isArray(data?.roles) ? data.roles : [])
      this._lastSuccessfulRolesRender = true
    } catch (error) {
      if (!this._lastSuccessfulRolesRender) {
        this.renderInitialPlaceholder()
      }
      this.showError(this._messageFrom(error))
    } finally {
      this.hideLoading()
    }
  }

  async syncRole(event) {
    this._preventDefault(event)
    const button = event?.currentTarget
    const roleId = button?.dataset?.roleId
    const roleName = button?.dataset?.roleName

    if (!roleId || !roleName) {
      this.showError(this._strings().missingRole)
      return
    }

    const restore = this._disableButton(button, "Syncing...", "Sync")

    try {
      const response = await fetch(`/guilds/${this.guildIdValue}/discord_roles/sync`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.getCSRFToken(),
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin",
        body: JSON.stringify({ role_id: roleId, role_name: roleName })
      })

      if (!response.ok) {
        throw new Error(await this._parseErrorMessage(response, "Failed to sync role"))
      }

      await this.refreshRoles()
    } catch (error) {
      restore()
      this.showError(this._messageFrom(error))
    }
  }

  async removeSync(event) {
    this._preventDefault(event)
    const button = event?.currentTarget
    const roleId = button?.dataset?.roleId

    if (!roleId) {
      this.showError(this._strings().missingRole)
      return
    }

    if (!confirm("Are you sure you want to remove the sync for this role?")) {
      return
    }

    const restore = this._disableButton(button, "Removing...", "Remove Sync")

    try {
      const response = await fetch(`/guilds/${this.guildIdValue}/discord_roles/sync/${roleId}`, {
        method: "DELETE",
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": this.getCSRFToken(),
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin"
      })

      if (!response.ok) {
        throw new Error(await this._parseErrorMessage(response, "Failed to remove sync"))
      }

      await this.refreshRoles()
    } catch (error) {
      restore()
      this.showError(this._messageFrom(error))
    }
  }

  async syncAll(event) {
    this._preventDefault(event)
    if (!confirm("Are you sure you want to sync all Discord roles?")) {
      return
    }

    this.showLoading()
    this.hideError()

    try {
      const response = await fetch(`/guilds/${this.guildIdValue}/discord_roles/sync_all`, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": this.getCSRFToken(),
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin"
      })

      if (!response.ok) {
        throw new Error(await this._parseErrorMessage(response, "Failed to sync all roles"))
      }

      const data = await this._safeJson(response)
      const count = Number.isFinite(data?.synced_count) ? data.synced_count : 0
      this._notify("success", `Successfully synced ${count} roles.`)
      await this.refreshRoles()
    } catch (error) {
      this.showError(this._messageFrom(error))
    } finally {
      this.hideLoading()
    }
  }

  async removeAllSyncs(event) {
    this._preventDefault(event)
    if (!confirm("Are you sure you want to remove all role syncs? This action cannot be undone.")) {
      return
    }

    this.showLoading()
    this.hideError()

    try {
      const response = await fetch(`/guilds/${this.guildIdValue}/discord_roles/sync_all`, {
        method: "DELETE",
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": this.getCSRFToken(),
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin"
      })

      if (!response.ok) {
        throw new Error(await this._parseErrorMessage(response, "Failed to remove all syncs"))
      }

      const data = await this._safeJson(response)
      this._notify("success", data?.message || "All role syncs removed successfully.")
      await this.refreshRoles()
    } catch (error) {
      this.showError(this._messageFrom(error))
    } finally {
      this.hideLoading()
    }
  }

  renderRoles(roles) {
    if (!this.hasRolesTableTarget) return

    if (!Array.isArray(roles) || roles.length === 0) {
      this.rolesTableTarget.innerHTML = `
        <tr>
          <td colspan="4" class="py-8 text-center text-theme-secondary">No Discord roles found</td>
        </tr>
      `
      return
    }

    this.rolesTableTarget.innerHTML = roles.map(role => {
      const statusIcon = role.synced
        ? '<svg class="w-5 h-5 text-green-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"></path></svg>'
        : '<svg class="w-5 h-5 text-red-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"></path></svg>'

      const actionButton = role.synced
        ? `<button
            type="button"
            data-action="click->discord-role-sync#removeSync"
            data-role-id="${this._attrEscape(role.id)}"
            class="px-3 py-1 bg-red-600 text-white rounded hover:bg-red-700 transition-colors text-sm font-semibold"
          >
            Remove Sync
          </button>`
        : `<button
            type="button"
            data-action="click->discord-role-sync#syncRole"
            data-role-id="${this._attrEscape(role.id)}"
            data-role-name="${this._attrEscape(role.name)}"
            class="px-3 py-1 bg-green-600 text-white rounded hover:bg-green-700 transition-colors text-sm font-semibold"
          >
            Sync
          </button>`

      return `
        <tr class="border-b border-theme-primary hover:bg-theme-primary/10">
          <td class="py-3 px-4 text-theme-primary">${this.escapeHtml(role.name)}</td>
          <td class="py-3 px-4 text-theme-secondary text-sm font-mono hidden md:table-cell">${this.escapeHtml(role.id)}</td>
          <td class="py-3 px-4 text-center">${statusIcon}</td>
          <td class="py-3 px-4 text-center">${actionButton}</td>
        </tr>
      `
    }).join("")
  }

  renderInitialPlaceholder() {
    if (this.hasRolesTableTarget && this._initialPlaceholderHTML) {
      this.rolesTableTarget.innerHTML = this._initialPlaceholderHTML
    }
  }

  showLoading() {
    if (this.hasLoadingTarget) this.loadingTarget.classList.remove("hidden")
  }

  hideLoading() {
    if (this.hasLoadingTarget) this.loadingTarget.classList.add("hidden")
  }

  showError(message) {
    if (!this.hasErrorTarget || !message) return
    const text = String(message)
    const inner = this.errorTarget.querySelector("p")
    if (inner) {
      inner.textContent = text
    } else {
      this.errorTarget.textContent = text
    }
    this.errorTarget.classList.remove("hidden")
  }

  hideError() {
    if (!this.hasErrorTarget) return
    const inner = this.errorTarget.querySelector("p")
    if (inner) inner.textContent = ""
    else this.errorTarget.textContent = ""
    this.errorTarget.classList.add("hidden")
  }

  getCSRFToken() {
    const token = document.querySelector('meta[name="csrf-token"]')
    return token ? token.getAttribute("content") : ""
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text == null ? "" : String(text)
    return div.innerHTML
  }

  _attrEscape(text) {
    return String(text == null ? "" : text)
      .replace(/&/g, "&amp;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
  }

  _strings() {
    const raw = this.hasI18nValue && this.i18nValue ? this.i18nValue : {}
    return {
      missingRole: typeof raw.missing_role === "string" && raw.missing_role.trim().length > 0
        ? raw.missing_role
        : "Missing role information; refresh and try again.",
      genericError: typeof raw.generic_error === "string" && raw.generic_error.trim().length > 0
        ? raw.generic_error
        : "Something went wrong. Please try again."
    }
  }

  _preventDefault(event) {
    if (event && typeof event.preventDefault === "function") {
      event.preventDefault()
    }
  }

  _disableButton(button, busyText, idleText) {
    if (!button) return () => {}
    const previousText = button.textContent
    button.disabled = true
    button.textContent = busyText
    return () => {
      button.disabled = false
      button.textContent = previousText || idleText
    }
  }

  _notify(type, message) {
    try {
      if (typeof window !== "undefined" && typeof window.showToast === "function") {
        window.showToast(type, message)
      }
    } catch (_e) {
      // Toast is best-effort; never let it break the main flow.
    }
  }

  async _safeJson(response) {
    try {
      return await response.json()
    } catch (_e) {
      return null
    }
  }

  async _parseErrorMessage(response, fallback) {
    const data = await this._safeJson(response)
    if (data && typeof data.error === "string" && data.error.trim().length > 0) {
      return data.error
    }
    if (response && response.statusText) {
      return `${fallback} (${response.status} ${response.statusText})`
    }
    return fallback
  }

  _messageFrom(error) {
    const fallback = this._strings().genericError
    if (!error) return fallback
    if (typeof error === "string") return error
    if (typeof error.message === "string" && error.message.trim().length > 0) return error.message
    return fallback
  }
}
