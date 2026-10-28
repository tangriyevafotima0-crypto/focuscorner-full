export {};

declare global {
  interface Window {
    focusCorner?: {
      isDesktop: true;
      platform: string;
      setLaunchAtLogin: (enabled: boolean) => Promise<void>;
      saveData: (data: { rules: string; tasks: string; history: string }) => Promise<void>;
      onToggleNotes: (cb: () => void) => () => void;
    };
  }
}
