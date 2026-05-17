import type { Config } from "tailwindcss";

const config: Config = {
  darkMode: ["class"],
  content: [
    "./app/**/*.{ts,tsx}",
    "./components/**/*.{ts,tsx}",
    "./lib/**/*.{ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        ink: "rgba(245, 242, 236, 0.92)",
        "ink-dim": "rgba(245, 242, 236, 0.55)",
        "ink-faint": "rgba(245, 242, 236, 0.32)",
        vault: "#0a0a0f",
        "vault-rise": "#11111a",
        hairline: "rgba(255, 255, 255, 0.10)",
      },
      fontFamily: {
        serif: ['"New York"', "Georgia", '"Iowan Old Style"', "serif"],
      },
      borderRadius: {
        lg: "16px",
        md: "12px",
        sm: "8px",
      },
      keyframes: {
        "fade-in": {
          from: { opacity: "0", transform: "translateY(6px)" },
          to: { opacity: "1", transform: "translateY(0)" },
        },
        "soft-pulse": {
          "0%, 100%": { opacity: "0.55" },
          "50%": { opacity: "0.85" },
        },
      },
      animation: {
        "fade-in": "fade-in 0.5s ease-out both",
        "soft-pulse": "soft-pulse 3.2s ease-in-out infinite",
      },
    },
  },
  plugins: [require("tailwindcss-animate")],
};

export default config;
