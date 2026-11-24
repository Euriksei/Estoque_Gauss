"use client";
import { useState } from "react";

// Campo de senha com botão para mostrar ou ocultar o que foi digitado.
export function CampoSenha({ value, onChange, autoComplete = "current-password" }: {
  value: string;
  onChange: (v: string) => void;
  autoComplete?: string;
}) {
  const [visivel, setVisivel] = useState(false);
  return (
    <div className="relative mt-1">
      <input type={visivel ? "text" : "password"} autoComplete={autoComplete} className="campo pr-16 font-normal"
        value={value} onChange={(e) => onChange(e.target.value)} required minLength={6} />
      <button type="button" onClick={() => setVisivel(!visivel)} aria-label={visivel ? "Ocultar senha" : "Mostrar senha"}
        className="absolute inset-y-0 right-0 px-3 text-xs font-medium text-slate-500 hover:text-marca-600">
        {visivel ? "Ocultar" : "Mostrar"}
      </button>
    </div>
  );
}
