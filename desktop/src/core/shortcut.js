// The global shortcut that opens Orbit, as an Electron accelerator string
// (https://www.electronjs.org/docs/latest/api/accelerator).

export const defaultAccelerator = 'CommandOrControl+Shift+5';

const modifierOrder = ['CommandOrControl', 'Control', 'Alt', 'Shift', 'Super'];

const keyNames = {
  ' ': 'Space', ArrowUp: 'Up', ArrowDown: 'Down', ArrowLeft: 'Left', ArrowRight: 'Right',
  Enter: 'Return', Escape: 'Escape', Backspace: 'Backspace', Delete: 'Delete', Tab: 'Tab',
  Home: 'Home', End: 'End', PageUp: 'PageUp', PageDown: 'PageDown', Insert: 'Insert',
};

/**
 * Accelerator for a keydown event, or null while only modifiers are held.
 * Uses `event.code` so the result doesn't depend on the keyboard layout or Shift.
 */
export function acceleratorFromEvent(event) {
  const { code, key } = event;
  let name = null;
  if (/^Key[A-Z]$/.test(code)) name = code.slice(3);
  else if (/^Digit[0-9]$/.test(code)) name = code.slice(5);
  else if (/^F([1-9]|1[0-9]|2[0-4])$/.test(code)) name = code;
  else if (/^Numpad[0-9]$/.test(code)) name = `num${code.slice(6)}`;
  else if (keyNames[key]) name = keyNames[key];
  else if (code === 'Minus') name = '-';
  else if (code === 'Equal') name = '=';
  else if (code === 'Comma') name = ',';
  else if (code === 'Period') name = '.';
  else if (code === 'Slash') name = '/';
  else if (code === 'Semicolon') name = ';';
  else if (code === 'Quote') name = "'";
  else if (code === 'BracketLeft') name = '[';
  else if (code === 'BracketRight') name = ']';
  else if (code === 'Backslash') name = '\\';
  else if (code === 'Backquote') name = '`';
  if (!name) return null;
  const parts = [];
  if (event.ctrlKey) parts.push('CommandOrControl');
  if (event.altKey) parts.push('Alt');
  if (event.shiftKey) parts.push('Shift');
  if (event.metaKey) parts.push('Super');
  return [...parts, name].join('+');
}

/** A message when the shortcut can't be used, else null. */
export function validationProblem(accelerator) {
  if (!accelerator) return 'Press a key combination.';
  const parts = accelerator.split('+');
  const key = parts[parts.length - 1];
  const modifiers = parts.slice(0, -1);
  if (!key || modifierOrder.includes(key)) return 'Press a key combination.';
  const isFunctionKey = /^F([1-9]|1[0-9]|2[0-4])$/.test(key);
  const hasRealModifier = modifiers.some((m) => m !== 'Shift');
  return isFunctionKey || hasRealModifier ? null : 'Add Ctrl, Alt, or the Windows/Super key so the shortcut doesn’t type a character.';
}

/** "Ctrl + Shift + 5" on Windows and Linux. */
export function displayString(accelerator, platform = 'win32') {
  const names = {
    CommandOrControl: platform === 'darwin' ? '⌘' : 'Ctrl',
    Control: 'Ctrl',
    Alt: 'Alt',
    Shift: 'Shift',
    Super: platform === 'win32' ? 'Win' : 'Super',
  };
  return accelerator.split('+').map((p) => names[p] ?? p).join(' + ');
}
