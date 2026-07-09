/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["./app/**/*.{js,ts,jsx,tsx}", "./components/**/*.{js,ts,jsx,tsx}"],
  darkMode: "class",
  theme: {
    extend: {
      colors: {
        brand: {
          50: "#eefcf7",
          100: "#d5f7ea",
          200: "#adeed7",
          300: "#75dfbe",
          400: "#3ec89f",
          500: "#1aab84",
          600: "#10896a",
          700: "#0f6d57",
          800: "#0f5747",
          900: "#0d483c",
          950: "#052922",
        },
      },
    },
  },
  plugins: [],
};
