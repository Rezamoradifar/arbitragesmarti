import React from "react";
import ReactDOM from "react-dom/client";
import { WagmiProvider } from "wagmi";
import { QueryClientProvider, QueryClient } from "@tanstack/react-query";
import { config } from "./wagmi";
import { FeedbackProvider } from "./context/FeedbackContext";
import App from "./App";
import "./styles/global.css";

const queryClient = new QueryClient();

ReactDOM.createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <FeedbackProvider>
          <App />
        </FeedbackProvider>
      </QueryClientProvider>
    </WagmiProvider>
  </React.StrictMode>
);
