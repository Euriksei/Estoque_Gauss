"use client";
import { useState } from "react";

// Botão que mostra ou esconde um formulário (ex.: "Nova transferência").
export function Colapsavel({ rotulo, children }: { rotulo: string; children: React.ReactNode }) {
  const [aberto, setAberto] = useState(false);
  return (
    <div className="space-y-3">
      <button type="button" className={aberto ? "btn-sec" : "btn"} onClick={() => setAberto(!aberto)}>
        {aberto ? "Fechar" : rotulo}
      </button>
      {aberto && children}
    </div>
  );
}
