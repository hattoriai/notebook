// The notebook's own "Are you sure?" (Layouts.confirm_dialog/1), never the
// browser's. A click on anything with data-confirm is held, in the capture
// phase, before LiveView or phoenix_html see it; the dialog asks; on its
// answer the click is made again without data-confirm, and goes ahead.
const label = (el) => el.dataset.confirmOk || el.textContent.trim().replace(/\s+/g, " ") || "Continue"

function ask(message, ok, danger) {
  const dialog = document.getElementById("confirm-dialog")
  if (!dialog) return Promise.resolve(false)
  dialog.querySelector("#confirm-dialog-message").textContent = message
  const okButton = dialog.querySelector("#confirm-dialog-ok")
  okButton.textContent = ok
  okButton.classList.toggle("is-danger", danger)
  dialog.returnValue = ""

  return new Promise((resolve) => {
    dialog.addEventListener("close", () => resolve(dialog.returnValue === "ok"), {once: true})
    dialog.showModal()
    dialog.querySelector("#confirm-dialog-cancel").focus()
  })
}

export function enableConfirm() {
  document.addEventListener("click", (event) => {
    const el = event.target.closest?.("[data-confirm]")
    if (!el) return
    event.preventDefault()
    event.stopImmediatePropagation()

    const message = el.getAttribute("data-confirm")
    const danger = el.classList.contains("danger") || /delete|remove|revoke/i.test(label(el))

    ask(message, label(el), danger).then((ok) => {
      if (!ok || !el.isConnected) return
      el.removeAttribute("data-confirm")
      el.click()
      el.setAttribute("data-confirm", message)
    })
  }, true)

  // A click on the backdrop, outside the box, is a Cancel.
  document.addEventListener("click", (event) => {
    if (event.target.id === "confirm-dialog") event.target.close("cancel")
  })
}
