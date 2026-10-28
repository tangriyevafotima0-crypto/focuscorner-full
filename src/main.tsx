import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "@fontsource/outfit/300.css";
import "@fontsource/outfit/400.css";
import "@fontsource/outfit/500.css";
import "@fontsource/outfit/600.css";
import "@fontsource/cormorant-garamond/500.css";
import "@fontsource/cormorant-garamond/600.css";
import "@fontsource/cormorant-garamond/500-italic.css";
import "./styles.css";
import { Desktop } from "@/components/desktop/desktop";
import { installNativeBridge } from "@/native-bridge";

installNativeBridge();

createRoot(document.getElementById("app")!).render(
  <StrictMode>
    <Desktop />
  </StrictMode>,
);
