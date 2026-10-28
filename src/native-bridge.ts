import { historyMarkdown, useFocusStore } from "@/lib/store";

/**
 * Connects the store to the Electron main process:
 *  - mirrors rules/tasks/history to ~/.focus_corner/{rules.json,tasks.json,history.md}
 *  - applies the "Launch at login" setting to the OS
 * No-op when running in a plain browser.
 */
export function installNativeBridge(): void {
  const api = window.focusCorner;
  if (!api) return;

  let lastLogin: boolean | null = null;
  let timer: number | undefined;

  const sync = () => {
    const s = useFocusStore.getState();
    if (!s.hydrated) return;
    if (s.settings.launchAtLogin !== lastLogin) {
      lastLogin = s.settings.launchAtLogin;
      void api.setLaunchAtLogin(lastLogin);
    }
    window.clearTimeout(timer);
    timer = window.setTimeout(() => {
      const cur = useFocusStore.getState();
      void api.saveData({
        rules: JSON.stringify(cur.rules, null, 2),
        tasks: JSON.stringify(cur.tasks, null, 2),
        history: historyMarkdown(cur.history),
      });
    }, 400);
  };

  useFocusStore.subscribe(sync);
  sync();
}
