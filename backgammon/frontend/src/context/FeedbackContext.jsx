import { createContext, useContext } from "react";
import { useFeedback } from "../hooks/useFeedback";

const FeedbackContext = createContext(null);

export function FeedbackProvider({ children }) {
  const feedback = useFeedback();
  return <FeedbackContext.Provider value={feedback}>{children}</FeedbackContext.Provider>;
}

export function useFeedbackContext() {
  const ctx = useContext(FeedbackContext);
  if (!ctx) throw new Error("useFeedbackContext must be used inside <FeedbackProvider>");
  return ctx;
}
