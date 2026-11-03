// The notebook's own word under a field that is not right yet, never the
// browser's bubble ("Please fill in this field."). A form's `required`,
// `minlength`, `pattern` and type still hold it back; the browser's
// `invalid` event is taken in the capture phase, its bubble prevented, and
// the field says why, until it is changed.
const message = (field) => {
  const v = field.validity
  if (v.valueMissing) return field.type === "checkbox" ? "Tick this to go on." : "This is needed."
  if (v.typeMismatch && field.type === "email") return "That isn't an email address."
  if (v.typeMismatch && field.type === "url") return "That isn't a web address."
  if (v.tooShort) return `At least ${field.minLength} characters.`
  if (v.tooLong) return `At most ${field.maxLength} characters.`
  if (v.rangeUnderflow) return `At least ${field.min}.`
  if (v.rangeOverflow) return `At most ${field.max}.`
  if (v.patternMismatch) return field.title || "This isn't in the right form."
  return "This isn't right yet."
}

const hintOf = (field) => {
  const id = `${field.id || field.name}-invalid`
  let hint = document.getElementById(id)
  if (!hint) {
    hint = document.createElement("p")
    hint.id = id
    hint.className = "field-invalid"
    hint.setAttribute("role", "alert")
    // After the field, or after its box when a picker or a label wraps it.
    const anchor = field.closest(".erabi, .money-input, label") || field
    anchor.insertAdjacentElement("afterend", hint)
  }
  return hint
}

const clear = (field) => {
  field.removeAttribute("aria-invalid")
  document.getElementById(`${field.id || field.name}-invalid`)?.remove()
}

export function enableValidation() {
  let first = null

  document.addEventListener("invalid", (event) => {
    const field = event.target
    event.preventDefault()
    field.setAttribute("aria-invalid", "true")
    hintOf(field).textContent = message(field)
    // The first field of the form that is not right yet takes the focus.
    if (!first) {
      first = field
      queueMicrotask(() => { first.focus({preventScroll: false}); first = null })
    }
  }, true)

  document.addEventListener("input", (event) => {
    if (event.target.getAttribute?.("aria-invalid") === "true" && event.target.checkValidity()) clear(event.target)
  }, true)
  document.addEventListener("change", (event) => {
    if (event.target.getAttribute?.("aria-invalid") === "true" && event.target.checkValidity()) clear(event.target)
  }, true)
}
