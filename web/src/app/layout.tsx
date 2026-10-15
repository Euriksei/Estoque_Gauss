import "./globals.css";
import type { Metadata } from "next";
import { Inter } from "next/font/google";

const inter = Inter({ subsets: ["latin"], variable: "--font-sans" });

export const metadata: Metadata = { title: "Estoque Gauss", icons: { icon: "/logo.png" } };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="pt-BR">
      <body className={`${inter.variable} min-h-screen bg-slate-50 font-sans text-slate-900`}>{children}</body>
    </html>
  );
}
