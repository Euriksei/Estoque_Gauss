import type { Config } from "tailwindcss";

// Identidade Gauss Fleet (tirada da logo): vermelho, azul-marinho e petróleo.
// Os "slate" são redefinidos com um tom azulado do marinho, assim todo o sistema herda a paleta.
export default {
  content: ["./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        marca: { 50: "#fff1f0", 100: "#ffdedc", 500: "#f23a33", 600: "#e1241d", 700: "#c21812" },
        marinho: { 700: "#123b4f", 800: "#0f2a3d", 900: "#0c1f2e", 950: "#08151f" },
        slate: {
          50: "#f5f7f9", 100: "#ebeff3", 200: "#dbe2e9", 300: "#c3cdd7", 400: "#8d9bab",
          500: "#64748b", 600: "#4a5b6e", 700: "#33465a", 800: "#1c3043", 900: "#0c1f2e",
        },
      },
      fontFamily: { sans: ["var(--font-sans)", "system-ui", "sans-serif"] },
      boxShadow: { card: "0 1px 2px rgba(12,31,46,.05), 0 4px 14px -6px rgba(12,31,46,.12)" },
    },
  },
  plugins: [],
} satisfies Config;
