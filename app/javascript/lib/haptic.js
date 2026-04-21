// Haptic feedback na iOS + Android. Port logiki z tijnjh/ios-haptics (MIT).
//
// Na Androidzie (i desktopach z vibration API) woła `navigator.vibrate()`.
// Na iOS (Safari 17.4+) wstrzykuje niewidzialny <input type="checkbox" switch>
// i klika go — switch ma wbudowane haptics przy toggle. Na niewspierających
// platformach no-op.

const supportsCoarsePointer =
  typeof window !== "undefined" &&
  window.matchMedia("(pointer: coarse)").matches

function iosSwitchTick() {
  if (!supportsCoarsePointer) return
  try {
    const label = document.createElement("label")
    label.ariaHidden = "true"
    label.style.display = "none"
    const input = document.createElement("input")
    input.type = "checkbox"
    input.setAttribute("switch", "")
    label.appendChild(input)
    document.head.appendChild(label)
    label.click()
    document.head.removeChild(label)
  } catch {
    // no-op
  }
}

export function tap() {
  if (navigator.vibrate) {
    navigator.vibrate(20)
    return
  }
  iosSwitchTick()
}

export function confirm() {
  if (navigator.vibrate) {
    navigator.vibrate([40, 60, 40])
    return
  }
  iosSwitchTick()
  setTimeout(iosSwitchTick, 120)
}

export function error() {
  if (navigator.vibrate) {
    navigator.vibrate([40, 60, 40, 60, 40])
    return
  }
  iosSwitchTick()
  setTimeout(iosSwitchTick, 120)
  setTimeout(iosSwitchTick, 240)
}

// Jeden listener dla całego dokumentu — każdy element z `data-haptic`
// atrybutem odpala haptic na click. Wartość: `tap` (domyślnie), `confirm`,
// `error`. Używamy capture fazy, żeby haptic zdążył się odpalić zanim
// przeglądarka zacznie navigation/submit.
export function install() {
  document.addEventListener(
    "click",
    (event) => {
      const el = event.target.closest("[data-haptic]")
      if (!el) return
      const kind = el.dataset.haptic || "tap"
      if (kind === "confirm") confirm()
      else if (kind === "error") error()
      else tap()
    },
    { capture: true }
  )
}
