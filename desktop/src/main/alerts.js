import { dialog } from 'electron';

export function showError(error, title = 'Orbit') {
  const message = error instanceof Error ? error.message : String(error);
  console.error(error);
  dialog.showMessageBox({ type: 'error', title, message: title === 'Orbit' ? 'Something went wrong' : title, detail: message, buttons: ['OK'] });
}
